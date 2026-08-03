# frozen_string_literal: true

module Weft
  class Router
    # OOB-include slice of the Router. Renders companion components declared
    # via `includes` alongside a response, with the `hx-swap-oob` attribute
    # set so htmx swaps each into its own DOM slot.
    #
    # Depends on Router internals: `filtered_params`,
    # `build_component_with_wire`.
    module OOBIncludes
      private

      # Render the RENDERED component's companions — on a transfers response
      # that's the target's declarations, never the declarer's. `context`
      # names how the primary came to render: :action (its own action,
      # action_name given), :transfer (it renders as a transfer target),
      # :push (an SSE frame). Unfiltered inclusions ride all three; `on:`
      # matches own-action names, `when:` matches contexts, either suffices.
      def render_oob_includes(component_class, primary_params, context:, action_name: nil, render_env: {})
        applicable = component_class.inclusions.select { |inc| inclusion_applies?(inc, context, action_name) }
        return "" if applicable.empty?

        applicable.map { |inc| render_oob_component(inc, primary_params, render_env) }.join.html_safe
      end

      def inclusion_applies?(inclusion, context, action_name)
        return true if inclusion[:on].nil? && inclusion[:when].nil?

        filtered_contexts(inclusion, action_name).include?(context)
      end

      # The contexts this filtered inclusion fires in — on: and when: union.
      def filtered_contexts(inclusion, action_name)
        contexts = []
        contexts << :action if inclusion[:on]&.include?(action_name)
        contexts << :transfer if inclusion[:when]&.include?(:transferred)
        contexts
      end

      # Each companion is an OOB-delivered child: it renders against the
      # same request universe, branches the primary's bag (rich values
      # included) exactly like a child built in the primary's own build,
      # and layers its own block delta — blockless is an empty delta.
      def render_oob_component(inclusion, primary_params, render_env)
        delta = inclusion[:block] ? Weft::DSL::Sandbox.run(primary_params, &inclusion[:block]) : {}
        delta = {} unless delta.is_a?(Hash)
        component = build_component_with_wire(inclusion[:component_class],
                                              render_env.fetch(:universe) { filtered_params },
                                              overlays: (render_env[:overlays] || {}).merge(delta),
                                              branch_bag: render_env[:branch_bag])
        component.set_attribute("hx-swap-oob", "true")
        component.to_s
      end
    end
  end
end
