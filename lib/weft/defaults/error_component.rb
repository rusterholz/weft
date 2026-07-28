# frozen_string_literal: true

require "weft/component"

module Weft
  module Defaults
    # Gem-default component rendered when an action or partial-render fails
    # and no user-declared recovers entry matches. Verbose mode shows the
    # exception class and message; non-verbose shows a generic message.
    # Users override by setting Weft.configuration.error_component or by
    # declaring their own `recovers` chain.
    #
    # Doubles as the default recovery frame for SSE push failures: the Router
    # injects :attempts_remaining only on that path, so its presence switches
    # the build into push shape — a countdown notice while the stream retries,
    # then a stopped notice with a reopen button on the final frame.
    class ErrorComponent < Weft::Component
      abstract!

      # Auto-injected params (opt-in, schema-gated by the Router). The
      # Router populates these at error-handling time on any recovers target
      # that declares them.
      # :component_id preserves the failing component's DOM identity so the
      # recovered fragment lands at the original element's id — preventing
      # duplicate IDs when several siblings fail in the same window.
      # :retry_url is the failing component's GET URL with current params.
      # :attempts_remaining is the push-path countdown (nil on HTTP paths).
      param :component_id, type: :string
      param :exception
      param :request_path, type: :string
      param :status_code, type: :integer
      param :retry_url, type: :string
      param :attempts_remaining, type: :integer

      STYLE = "padding:1rem; border:1px solid #fca5a5; border-radius:6px; " \
              "background:#fef2f2; color:#991b1b; font-size:0.875rem"
      HEADING_STYLE = "font-weight:600; margin-bottom:0.5rem"
      MONO_STYLE = "margin-bottom:0.5rem; font-family:monospace; font-size:0.8rem"
      BUTTON_STYLE = "padding:0.25rem 0.75rem; border:1px solid #b91c1c; border-radius:4px; " \
                     "background:#fff; color:#b91c1c; font-size:0.75rem; cursor:pointer"

      def build(attributes = {})
        super
        return build_push_error if push_context?

        add_class "weft-error"
        set_attribute "style", STYLE

        div(style: HEADING_STYLE) { text_node "Something went wrong" }
        render_verbose if verbose?
        render_retry_button if @params.retry_url
      end

      # Preserve the failing component's DOM identity when the Router injected
      # :component_id. Otherwise fall back to the class-derived default.
      def weft_id
        @params.component_id || super
      end

      private

      def push_context? = !@params.attempts_remaining.nil?
      def verbose? = Weft.configuration.verbose_error_pages && @params.exception

      # Push frames ship children only — the persistent wrapper client-side
      # belongs to the original component — so the visual box must be an inner
      # element; anything set on the wrapper would never reach the browser.
      def build_push_error
        stopped = @params.attempts_remaining.zero?
        div(class: "weft-error", style: STYLE) do
          div(style: HEADING_STYLE) do
            text_node stopped ? "Live updates stopped" : "Live updates interrupted — retrying"
          end
          render_verbose if verbose?
          render_reopen_button if stopped && @params.retry_url
        end
      end

      def render_verbose
        exc = @params.exception
        div(style: MONO_STYLE) { text_node "#{exc.class}: #{exc.message}" }
      end

      # Retry by re-issuing a GET to refresh the failing component. The :retry
      # preset supplies the htmx wiring (outerHTML-swap the closest
      # .weft-error box), so it works whether or not :component_id was carved out.
      def render_retry_button
        button "Retry", retry: @params.retry_url, style: BUTTON_STYLE
      end

      # Resume by re-fetching the component whole: the fresh wrapper's
      # sse-connect reopens the stream with a full attempts budget. The
      # :reopen_stream preset targets the dead wrapper itself.
      def render_reopen_button
        button "Resume live updates", reopen_stream: @params.retry_url, style: BUTTON_STYLE
      end
    end
  end
end
