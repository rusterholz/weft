# frozen_string_literal: true

require "securerandom"
require "uri"

require "weft/context"
require "weft/dsl/sandbox"
require "weft/error"
require "weft/page"
require "weft/params"
require "weft/resolver"

module Weft
  class Router
    # Error-and-recovery slice of the Router. Walks recovers chains for
    # component-context failures (A1–A5, C1–C3) and page-context failures
    # (B1, B2, C1 page-context, C4), implements the htmx_errors = :redirect
    # knob (D1, D2 no-op, D3 no-op), and houses the safety-net fallbacks
    # for unmatched errors and recovery handlers that themselves raise.
    #
    # Also owns the schema-gated auto-injection of recovery params
    # (:exception, :request_path, :status_code, :component_tag, :retry_url,
    # :attempts_remaining) and the identity a recovery fragment inherits from
    # the component it stands in for.
    #
    # Depends on Router internals: `headers`, `status`, `request`,
    # `redirect`, `htmx_request?`.
    module Errors # rubocop:disable Metrics/ModuleLength
      # Each entry: { redirect_safe: true } means the auto-injected param is
      # included even when building a redirect URL. The component-context
      # params (:exception, :retry_url) are not redirect-safe — Exception
      # objects aren't URL-encodable, and the destination Page rebuilds its
      # own URL.
      # :attempts_remaining is populated only on the SSE push path (nil, and
      # therefore skipped, on HTTP recoveries) — its presence tells a recovery
      # component it is rendering inside a live stream, counting down to the
      # close; 0 marks the final frame.
      AUTO_INJECTED_PARAMS = [
        { key: :exception,          redirect_safe: false },
        { key: :request_path,       redirect_safe: true },
        { key: :status_code,        redirect_safe: true },
        { key: :component_tag,      redirect_safe: false },
        { key: :retry_url,          redirect_safe: false },
        { key: :attempts_remaining, redirect_safe: false }
      ].freeze
      private_constant :AUTO_INJECTED_PARAMS

      private

      # Walk a Page-context recovers chain (B1, B2, C1 page-context, C4).
      # `originating_page_class` is nil for routing misses (no specific Page);
      # the gem-default chain on Weft::Page handles those.
      def handle_page_chain_failure(error, originating_page_class:, originating_params: nil, originating_wire: nil)
        root = originating_page_class || Weft::Page
        entry = root.recovery_for(error)
        return page_safety_net(error) unless entry

        # D1: htmx + :redirect knob + gem-default fallthrough → HX-Redirect
        # (D3 carves out routing misses).
        return htmx_redirect_to_error_page(error) if d1_applies?(entry, error)

        target = root.resolve_recovery_target(entry)
        block_delta = invoke_recovery_block(entry, originating_params || Weft::Params.new({}), error)

        if page_target?(target)
          dispatch_page_recovery(target, block_delta, error, entry, universe: originating_wire)
        else
          render_recovery_component(target, block_delta, error,
                                    component_ctx: { status: recovery_status(error, entry) },
                                    universe: originating_wire)
        end
      end

      # Render or redirect for a Page recovery target. htmx requests get the
      # Page's body content as a fragment; traditional requests get the full
      # document. Status comes from the exception, or the entry's override.
      # The page renders against the request's universe; the recovery values
      # ride as overlays (one universe per request).
      def dispatch_page_recovery(page_class, block_delta, error, entry = nil, universe: nil)
        wire_status = recovery_status(error, entry)
        overlays = block_delta.merge(auto_param_overlay(error, { status: wire_status }))
        status wire_status
        wire = universe || filtered_params
        htmx_request? ? page_body_html(page_class, wire, overlays) : render_full_page(page_class, wire, overlays)
      end

      def render_full_page(page_class, wire_params, overlays)
        klass = page_class
        Weft::Context.new({}, nil, wire_params: wire_params, overlays: overlays) { insert_tag(klass) }.to_s
      end

      # Extract the rendered HTML inside a Page's <body>. For htmx fragment
      # responses to full-document failures — the surrounding doc shell is
      # already on the client; only the body content should swap.
      def page_body_html(page_class, wire_params, overlays)
        klass = page_class
        ctx = Weft::Context.new({}, nil, wire_params: wire_params, overlays: overlays) { insert_tag(klass) }
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

      # +state+ is the bag the request had composed when it broke — what the
      # recovery block reads. Bags are for blocks; the wire hash below is for
      # URLs, and stays a plain hash so building one can't force a derivation.
      def render_error(component_class, state, error)
        entry = component_class.recovery_for(error)
        if entry
          # D1: htmx + :redirect knob + gem-default fallthrough → HX-Redirect.
          return htmx_redirect_to_error_page(error) if d1_applies?(entry, error)

          begin
            return render_recovery(component_class, entry, state, error)
          rescue StandardError => e
            # The recovery handler itself raised — fall through to the hardcoded
            # safety net rather than recursing. Surface the original error;
            # the recovery error is dropped (it's almost always a coding bug).
            Weft.logger.error("Recovery render failed: #{e.class}: #{e.message}")
          end
        end

        status recovery_status(error)
        render_generic_error(component_class, error)
      end

      # The failing component's own declared wire params. Never the bag: this
      # feeds retry URLs and redirect query strings, where materializing a
      # derivation would run user code in the middle of error handling.
      def error_wire_params(component_class)
        Weft::Resolver.resolve(component_class, filtered_params)
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

      # Execute a matched recovery entry: invoke the block, then dispatch to
      # either a Page-redirect (HX-Redirect / 302) or a fragment render
      # depending on the target's type.
      def render_recovery(component_class, entry, state, error)
        block_result = invoke_recovery_block(entry, state, error)
        target = component_class.resolve_recovery_target(entry)
        wire = error_wire_params(component_class)
        component_ctx = {
          originating_id: resolved_dom_id(component_class,
                                          unbuilt_instance(component_class, filtered_params), wire),
          originating_tag: component_tag_for(component_class),
          retry_url: compute_retry_url(component_class, wire),
          status: recovery_status(error, entry)
        }

        if page_target?(target)
          redirect_to_recovery_page(target, wire.merge(block_result), error, component_ctx)
        else
          render_recovery_component(target, block_result, error, component_ctx: component_ctx)
        end
      end

      # The failing component's wrapper tag, so a recovery fragment can render
      # as a like-for-like element (a div swapped into <tr> position is invalid
      # table content). `allocate` skips initialize — no param resolution, so
      # reading the tag can't re-raise the failure; a tag_name that depends on
      # instance state falls back to nil (target renders its own default).
      def component_tag_for(component_class)
        component_class.allocate.tag_name
      rescue StandardError
        nil
      end

      # An instance constructed only to be asked about itself. Params resolve
      # at construction, so it answers for its own identity and URL before
      # `build` runs, and unlike the class-level derivation it honors a
      # `weft_dom_id` override. nil when the construction itself is what
      # raises. Where the same component goes on to render, pass that instance
      # rather than making a second one — the two would carry separate bags,
      # and a derivation behind a declared param would run in each.
      def unbuilt_instance(component_class, wire_params, overlays: {}, branch_bag: nil)
        component_class.new(Weft::Context.new({}, nil, wire_params: wire_params,
                                                       overlays: overlays, branch_bag: branch_bag))
      rescue StandardError
        nil
      end

      # The DOM id a component wears, asked of an unbuilt instance first and
      # falling back to the class-level derivation from an already-resolved
      # params hash — that covers a construction that raises before the
      # instance exists.
      #
      # Identity that raises when *asked* does not fall through to the
      # class-level derivation, on purpose: a raising `weft_dom_id` is an
      # override, and the convention it overrode would answer with a
      # different id — landing the fragment on some other component's
      # element. Landing nowhere beats landing somewhere wrong.
      def resolved_dom_id(component_class, instance, fallback_params = nil)
        return instance.weft_dom_id if instance
        return component_class.weft_dom_id_for(fallback_params) if fallback_params

        unresolved_dom_id(component_class)
      rescue StandardError
        unresolved_dom_id(component_class)
      end

      # Identity can itself raise — a `weft_dom_id` reading a record deleted
      # between renders — and the id it would have had is unrecoverable.
      #
      # TEMPORARY: an unresolvable identity gets a unique throwaway, so it can
      # never collide with or displace another fragment. Such a fragment simply
      # lands nowhere, which is the honest outcome when we cannot say where it
      # belongs. Component identity is due a design pass of its own; this is a
      # placeholder until it gets one.
      def unresolved_dom_id(component_class)
        "#{component_class.weft_dom_id_for}-unresolved-#{SecureRandom.hex(4)}"
      end

      # A recovery fragment stands in the failing component's place, so it
      # wears the failing component's id — a swap addressed anywhere else
      # lands somewhere else, or nowhere at all. A page-context failure has no
      # originating component, and its target keeps its own id.
      def claim_dom_id(component, dom_id)
        component.set_attribute("id", dom_id) if dom_id
        component
      end

      # GET URL to render the failing component fresh: its resolved_component_path
      # plus the resolved params as query string. For action endpoints this gives
      # the underlying component's view (not the action URL).
      def compute_retry_url(component_class, resolved_params)
        url = component_class.resolved_component_path
        query = resolved_params.compact
        query.empty? ? url : "#{url}?#{URI.encode_www_form(query)}"
      end

      # The block reads the state the request had composed, exactly as the
      # build that failed would have read it.
      def invoke_recovery_block(entry, state, error)
        return {} unless entry[:block]

        result = Weft::DSL::Sandbox.run(state, error, &entry[:block])
        result.is_a?(Hash) ? result : {}
      end

      def page_target?(target)
        target.is_a?(Class) && defined?(Weft::Page) && target <= Weft::Page
      end

      def redirect_to_recovery_page(target, merged_params, error, component_ctx = {})
        params_for_url = inject_auto_params(target, merged_params, error,
                                            on_redirect: true, component_ctx: component_ctx)
        url = target.redirect_url(params_for_url)

        if request.env["HTTP_HX_REQUEST"]
          headers["HX-Redirect"] = url
          status 204
          ""
        else
          redirect url, 302
        end
      end

      # Fragment-only sibling of render_recovery for SSE push failures. Walks
      # the chain via component_recovery_for (a stream swap can't take a Page),
      # and returns the recovery target's children-only HTML — the client swap
      # is innerHTML into the original component's persistent wrapper, so the
      # frame ships content, not wrapper (like-for-like with a normal push).
      # No status (headers are long flushed on a live stream), no oob includes
      # (their params presume the successful build that didn't happen), and no
      # htmx_errors redirect knob (an HTTP-path concern). Returns nil when the
      # chain yields nothing; the caller owns rescue and logging.
      def render_push_recovery(component_class, state, error, attempts_remaining:)
        entry = component_class.component_recovery_for(error)
        return nil unless entry

        block_delta = invoke_recovery_block(entry, state, error)
        target = component_class.resolve_recovery_target(entry)
        component_ctx = {
          retry_url: compute_retry_url(component_class, error_wire_params(component_class)),
          attempts_remaining: attempts_remaining,
          status: recovery_status(error, entry)
        }
        overlays = block_delta.merge(auto_param_overlay(error, component_ctx))
        build_component_with_wire(target, filtered_params, overlays: overlays).content
      end

      # The target resolves its own schema from the request's universe; the
      # recovery values — block delta plus the auto-injected params — ride
      # as overlays, reaching any depth of the recovery render. The failing
      # component's resolution never crowns a new universe, so its defaults
      # and derivations can't leak into the target's.
      def render_recovery_component(target, block_delta, error, component_ctx:, universe: nil)
        overlays = block_delta.merge(auto_param_overlay(error, component_ctx))
        status component_ctx.fetch(:status) { recovery_status(error) }
        component = build_component_with_wire(target, universe || filtered_params, overlays: overlays)
        claim_dom_id(component, component_ctx[:originating_id]).to_s
      end

      # The auto-injected values as an overlay: non-nil values only — a nil
      # here would read as "clear the wire's value," which absence must not do.
      # Declaration-driven reads make schema-gating unnecessary on renders
      # (an unread overlay key is inert); redirects still gate via
      # inject_auto_params below.
      def auto_param_overlay(error, component_ctx)
        auto_param_values(error, component_ctx).compact
      end

      # Schema-gated auto-injection of recovery params for REDIRECT URLs. A
      # recovers target opts in to receiving each value by declaring
      # `param :<key>` — only keys the target's schema knows about (and only
      # redirect-safe, non-nil values) ride the URL.
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
          status_code: component_ctx[:status] || recovery_status(error),
          component_tag: component_ctx[:originating_tag],
          retry_url: component_ctx[:retry_url],
          attempts_remaining: component_ctx[:attempts_remaining]
        }
      end

      # The matched entry's status: override wins; otherwise the error's own
      # semantics (HTTPError carries a status, anything else reports 500).
      def recovery_status(error, entry = nil)
        entry&.[](:status) || (error.is_a?(Weft::HTTPError) ? error.status : 500)
      end

      def render_generic_error(component_class, error)
        component_name = component_class.name || "Component"
        retry_url = compute_retry_url(component_class, error_wire_params(component_class))

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
