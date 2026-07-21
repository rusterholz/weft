# frozen_string_literal: true

module Weft
  class Router
    # OOB-include slice of the Router. Renders sibling components declared
    # via `includes` alongside an action response or SSE push, with the
    # `hx-swap-oob` attribute set so htmx swaps each into its own DOM slot.
    #
    # Depends on Router internals: `filtered_params`,
    # `build_component_with_wire`.
    module OOBIncludes
      private

      # Render OOB-swapped components declared via `includes`.
      # Filters by action_name when inclusions declare `on:`.
      def render_oob_includes(component_class, primary_params, action_name: nil)
        applicable = component_class.inclusions.select do |inc|
          inc[:on].nil? || inc[:on] == action_name
        end
        return "" if applicable.empty?

        applicable.map { |inc| render_oob_component(inc, primary_params) }.join.html_safe
      end

      def render_oob_component(inclusion, primary_params)
        wire_params = inclusion[:block] ? Weft::DSL::Sandbox.run(primary_params, &inclusion[:block]) : filtered_params
        component = build_component_with_wire(inclusion[:component_class], wire_params)
        component.set_attribute("hx-swap-oob", "true")
        component.to_s
      end
    end
  end
end
