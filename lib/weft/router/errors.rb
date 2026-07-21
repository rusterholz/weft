# frozen_string_literal: true

module Weft
  class Router
    # Error-and-recovery slice of the Router. Walks recovers chains for
    # component-context failures (A1–A5, C1–C3) and page-context failures
    # (B1, B2, C1 page-context, C4), implements the htmx_errors = :redirect
    # knob (D1, D2 no-op, D3 no-op), and houses the safety-net fallbacks
    # for unmatched errors and recovery handlers that themselves raise.
    #
    # Also owns the schema-gated auto-injection of recovery params
    # (:exception, :request_path, :status_code, :component_id, :retry_url).
    #
    # Depends on Router internals: `headers`, `status`, `request`,
    # `redirect`, `htmx_request?`.
    module Errors # rubocop:disable Metrics/ModuleLength
      # Each entry: { redirect_safe: true } means the auto-injected param is
      # included even when building a redirect URL. The component-context
      # params (:exception, :component_id, :retry_url) are not redirect-safe
      # — no element to preserve identity of, Exception objects aren't
      # URL-encodable, and the destination Page rebuilds its own URL.
      AUTO_INJECTED_PARAMS = [
        { key: :exception,    redirect_safe: false },
        { key: :request_path, redirect_safe: true },
        { key: :status_code,  redirect_safe: true },
        { key: :component_id, redirect_safe: false },
        { key: :retry_url,    redirect_safe: false }
      ].freeze
      private_constant :AUTO_INJECTED_PARAMS

      private

      # Walk a Page-context recovers chain (B1, B2, C1 page-context, C4).
      # `originating_page_class` is nil for routing misses (no specific Page);
      # the gem-default chain on Weft::Page handles those.
      def handle_page_chain_failure(error, originating_page_class:, originating_params: {})
        root = originating_page_class || Weft::Page
        entry = root.recovery_for(error)
        return page_safety_net(error) unless entry

        # D1: htmx + :redirect knob + gem-default fallthrough → HX-Redirect
        # (D3 carves out routing misses).
        return htmx_redirect_to_error_page(error) if d1_applies?(entry, error)

        target = root.resolve_recovery_target(entry)
        merged_params = recovery_merged_params(entry, originating_params, error)

        if page_target?(target)
          dispatch_page_recovery(target, merged_params, error)
        else
          render_recovery_component(target, merged_params, error, component_ctx: {})
        end
      end

      def recovery_merged_params(entry, originating_params, error)
        block_result = invoke_recovery_block(entry, originating_params, error)
        originating_params.merge(block_result)
      end

      # Render or redirect for a Page recovery target. htmx requests get the
      # Page's body content as a fragment; traditional requests get the full
      # document. Status comes from the exception.
      def dispatch_page_recovery(page_class, merged_params, error)
        injected = inject_auto_params(page_class, merged_params, error, on_redirect: false)
        status recovery_status(error)
        htmx_request? ? page_body_html(page_class, injected) : page_class.render(**injected)
      end

      # Extract the rendered HTML inside a Page's <body>. For htmx fragment
      # responses to full-document failures — the surrounding doc shell is
      # already on the client; only the body content should swap.
      def page_body_html(page_class, wire_params)
        klass = page_class
        ctx = Weft::Context.new({}, nil, wire_params: wire_params) { insert_tag(klass) }
        page_instance = ctx.children.first
        body_el = page_instance.children.find { |c| c.respond_to?(:tag_name) && c.tag_name == "body" }
        body_el ? body_el.children.join : page_instance.to_s
      end

      # Last-resort hardcoded response when no recovers entry matched and
      # the gem-default Page can't be rendered. Avoids unbounded recursion
      # while still producing something sensible.
      def page_safety_net(error)
        status recovery_status(error)
        message = "Internal error (#{error.class}: #{error.message})"
        if htmx_request?
          "<div style='padding:1rem;color:#991b1b'>#{message}</div>"
        else
          "<!DOCTYPE html>\n<html><head><title>Error</title></head>" \
            "<body><div style='padding:1rem;color:#991b1b'>#{message}</div></body></html>"
        end
      end

      def render_error(component_class, resolved_params, error)
        entry = component_class.recovery_for(error)
        if entry
          # D1: htmx + :redirect knob + gem-default fallthrough → HX-Redirect.
          return htmx_redirect_to_error_page(error) if d1_applies?(entry, error)

          begin
            return render_recovery(component_class, entry, resolved_params, error)
          rescue StandardError => e
            # The recovery handler itself raised — fall through to the hardcoded
            # safety net rather than recursing. Surface the original error;
            # the recovery error is dropped (it's almost always a coding bug).
            Weft.logger.error("Recovery render failed: #{e.class}: #{e.message}")
          end
        end

        status recovery_status(error)
        render_generic_error(component_class, resolved_params, error)
      end

      # D1 applies when: the htmx_errors knob is :redirect, the request is htmx,
      # the matched entry came from a gem-default (Symbol with:), and the error
      # is not a routing miss (D3 — Weft::NotFound short-circuits the knob).
      def d1_applies?(entry, error)
        Weft.configuration.htmx_errors == :redirect &&
          htmx_request? &&
          entry[:with].is_a?(Symbol) &&
          !error.is_a?(Weft::NotFound)
      end

      def htmx_redirect_to_error_page(error)
        target = Weft.configuration.error_page
        params_for_url = inject_auto_params(target, {}, error, on_redirect: true)
        headers["HX-Redirect"] = target.redirect_url(params_for_url)
        status 204
        ""
      end

      # Execute a matched recovery entry: invoke block, merge params, dispatch
      # to either a Page-redirect (HX-Redirect / 302) or a fragment render
      # depending on the target's type.
      def render_recovery(component_class, entry, resolved_params, error)
        block_result = invoke_recovery_block(entry, resolved_params, error)
        merged_params = resolved_params.merge(block_result)
        target = component_class.resolve_recovery_target(entry)
        component_ctx = {
          originating_id: component_class.weft_id_for(resolved_params),
          retry_url: compute_retry_url(component_class, resolved_params)
        }

        if page_target?(target)
          redirect_to_recovery_page(target, merged_params, error)
        else
          render_recovery_component(target, merged_params, error, component_ctx: component_ctx)
        end
      end

      # GET URL to render the failing component fresh: its resolved_component_path
      # plus the resolved params as query string. For action endpoints this gives
      # the underlying component's view (not the action URL).
      def compute_retry_url(component_class, resolved_params)
        url = component_class.resolved_component_path
        query = resolved_params.compact
        query.empty? ? url : "#{url}?#{URI.encode_www_form(query)}"
      end

      def invoke_recovery_block(entry, resolved_params, error)
        return {} unless entry[:block]

        result = Weft::DSL::Sandbox.run(Weft::Params.new(resolved_params), error, &entry[:block])
        result.is_a?(Hash) ? result : {}
      end

      def page_target?(target)
        target.is_a?(Class) && defined?(Weft::Page) && target <= Weft::Page
      end

      def redirect_to_recovery_page(target, merged_params, error)
        params_for_url = inject_auto_params(target, merged_params, error, on_redirect: true)
        url = target.redirect_url(params_for_url)

        if request.env["HTTP_HX_REQUEST"]
          headers["HX-Redirect"] = url
          status 204
          ""
        else
          redirect url, 302
        end
      end

      def render_recovery_component(target, merged_params, error, component_ctx:)
        injected = inject_auto_params(target, merged_params, error,
                                      on_redirect: false, component_ctx: component_ctx)
        status recovery_status(error)
        # The target projects its own schema from the pseudo-wire kwargs, so
        # the failing component's params (which may share no schema with the
        # target) can't leak. Declared auto-injected params survive: their
        # defaults are nil, and coercion passes non-nil values unchanged.
        target.render(**injected)
      end

      # Schema-gated auto-injection of recovery params. A recovers target
      # opts in to receiving each value by declaring `param :<key>` — the
      # Router only injects keys the target's schema knows about (and only if
      # the value is non-nil).
      def inject_auto_params(target, base_params, error, on_redirect:, component_ctx: {})
        schema = target.respond_to?(:params) ? target.params : {}
        values = auto_param_values(error, component_ctx)
        injected = base_params.dup
        AUTO_INJECTED_PARAMS.each do |meta|
          next if on_redirect && !meta[:redirect_safe]
          next unless schema.key?(meta[:key])

          value = values[meta[:key]]
          injected[meta[:key]] = value unless value.nil?
        end
        injected
      end

      def auto_param_values(error, component_ctx)
        {
          exception: error,
          request_path: request.path,
          status_code: recovery_status(error),
          component_id: component_ctx[:originating_id],
          retry_url: component_ctx[:retry_url]
        }
      end

      def recovery_status(error)
        error.is_a?(Weft::HTTPError) ? error.status : 500
      end

      def render_generic_error(component_class, resolved_params, error)
        component_name = component_class.name || "Component"
        retry_url = compute_retry_url(component_class, resolved_params)

        Weft::Context.new({}, nil) do
          error_style = "padding:1rem; border:1px solid #fca5a5; border-radius:6px; " \
                        "background:#fef2f2; color:#991b1b; font-size:0.875rem"
          div(class: "weft-error", style: error_style) do
            div(style: "font-weight:600; margin-bottom:0.5rem") { text_node "#{component_name} error" }
            div(style: "margin-bottom:0.5rem; font-family:monospace; font-size:0.8rem") do
              text_node "#{error.class}: #{error.message}"
            end
            button "Retry", class: "btn btn-sm btn-outline-danger", retry: retry_url
          end
        end.to_s
      end
    end
  end
end
