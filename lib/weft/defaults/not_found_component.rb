# frozen_string_literal: true

module Weft
  module Defaults
    # Gem-default component rendered when a routing miss falls through to
    # the Weft::Page chain (C4) or when an action raises Weft::NotFound and
    # no user recovers entry matches.
    class NotFoundComponent < Weft::Component
      abstract!

      # Opt into the :component_id auto-injected param for parity with
      # ErrorComponent — preserves DOM identity when a component-context
      # NotFound recovers through this.
      param :component_id
      param :request_path
      param :status_code

      STYLE = "padding:1rem; border:1px solid #cbd5e1; border-radius:6px; " \
              "background:#f8fafc; color:#0f172a; font-size:0.875rem"
      MONO_STYLE = "margin-top:0.5rem; font-family:monospace; font-size:0.8rem; color:#475569"

      def build(attributes = {})
        super
        add_class "weft-not-found"
        set_attribute "style", STYLE

        div(style: "font-weight:600") { text_node "Not found" }
        render_verbose if Weft.configuration.verbose_error_pages && @params.request_path
      end

      # Preserve the failing component's DOM identity when the Router injected
      # :component_id. Otherwise fall back to the class-derived default.
      def weft_id
        @params.component_id || super
      end

      private

      def render_verbose
        div(style: MONO_STYLE) { text_node @params.request_path.to_s }
      end
    end
  end
end
