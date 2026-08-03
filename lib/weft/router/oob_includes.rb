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
        render_companions(applicable_inclusions(component_class, context, action_name).
                            map { |inc| [inc, primary_params, render_env] })
      end

      # The inclusions of one component that fire in one context.
      def applicable_inclusions(component_class, context, action_name)
        component_class.inclusions.select { |inc| inclusion_applies?(inc, context, action_name) }
      end

      # The inclusions that name an action outright. A transfer's declaring
      # component never renders, so its unfiltered inclusions ("every
      # response I render in") stay silent — but `on:` doesn't narrow that
      # default, it replaces it, and this action is the declarer's own.
      def explicitly_named_inclusions(component_class, action_name)
        component_class.inclusions.select { |inc| inc[:on]&.include?(action_name) }
      end

      # Render a planned set of companions: each entry pairs an inclusion
      # with the params view its block reads and the environment its
      # component builds in, because companions arriving from different
      # branches of one response fork at different points.
      def render_companions(plan)
        return "" if plan.empty?

        built = plan.map { |inclusion, view, env| [inclusion, build_oob_component(inclusion, view, env)] }
        distinct_by_dom_id(built).join.html_safe
      end

      # An out-of-band swap is addressed by DOM id, so two fragments wearing
      # one id cannot both land — the later would simply swap over the
      # earlier. The first declaration keeps the slot and the loser is
      # announced. Companions differing in an id-bearing param derive
      # different ids and both ride, which is what makes two of a kind
      # (a left eye and a right eye) a legitimate pair rather than a clash.
      def distinct_by_dom_id(built)
        kept = {}
        built.each do |inclusion, component|
          dom_id = component.weft_dom_id
          if kept.key?(dom_id)
            warn_companion_collision(dom_id, kept[dom_id].first, inclusion)
          else
            kept[dom_id] = [inclusion, component]
          end
        end
        kept.values.map(&:last)
      end

      def warn_companion_collision(dom_id, kept, dropped)
        Weft.logger.warn(
          "#{dropped[:component_class].name} companion declared at " \
          "#{dropped[:source_location].join(':')} was dropped: it resolves to DOM id " \
          "#{dom_id.inspect}, already claimed by the companion declared at " \
          "#{kept[:source_location].join(':')}. An out-of-band swap is addressed by DOM id, so " \
          "only one fragment can land there — give them different values for an identifying " \
          "param, or drop one of the declarations."
        )
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
      def build_oob_component(inclusion, primary_params, render_env)
        delta = inclusion[:block] ? Weft::DSL::Sandbox.run(primary_params, &inclusion[:block]) : {}
        delta = {} unless delta.is_a?(Hash)
        component = build_component_with_wire(inclusion[:component_class],
                                              render_env.fetch(:universe) { filtered_params },
                                              overlays: (render_env[:overlays] || {}).merge(delta),
                                              branch_bag: render_env[:branch_bag])
        component.set_attribute("hx-swap-oob", "true")
        component
      end
    end
  end
end
