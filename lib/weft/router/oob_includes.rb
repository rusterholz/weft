# frozen_string_literal: true

module Weft
  class Router
    # OOB-include slice of the Router. Renders companion components declared
    # via `includes` alongside a response, with the `hx-swap-oob` attribute
    # set so htmx swaps each into its own DOM slot.
    #
    # Depends on Router internals: `filtered_params`,
    # `build_component_with_wire`, and the Errors slice's identity and
    # recovery helpers (`unbuilt_instance`, `resolved_dom_id`,
    # `invoke_recovery_block`, `auto_param_overlay`, `component_tag_for`,
    # `compute_retry_url`, `recovery_status`).
    module OOBIncludes
      private

      # The companions riding an SSE frame. A push is nobody's action and no
      # transfer's destination, so only unfiltered inclusions — "every
      # response I render in" — qualify; `on:` and `when:` both name contexts
      # a stream never enters.
      def render_push_companions(component_class, primary_params, render_env:, slots:)
        render_companions(applicable_inclusions(component_class, :push, nil).
                            map { |inc| [inc, primary_params, render_env] }, slots)
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
      def render_companions(plan, slots)
        return "" if plan.empty?

        winners = {}
        plan.filter_map { |inclusion, view, env| companion_fragment(inclusion, view, env, slots, winners) }.
          join.html_safe
      end

      # One companion's fragment, or nil when it yields none. `winners` records
      # who took each slot, so a collision can name the declaration it lost to.
      def companion_fragment(inclusion, view, env, slots, winners)
        fragment = attempt_companion(inclusion, view, env, slots, winners)
        winners[fragment.id] = inclusion if fragment
        fragment
      end

      # Build a companion, unless its slot is already spoken for.
      #
      # The component abandons its own render the moment it finds the slot
      # taken (Component#claim_dom_slot!) and throws the contested id back
      # here, so a companion that was never going to land doesn't pay for the
      # build. Companions differing in an id-bearing param claim different
      # slots and both ride — which is what makes two of a kind, a left eye
      # and a right eye, a legitimate pair rather than a clash.
      def attempt_companion(inclusion, view, env, slots, winners)
        overlays = companion_overlays(inclusion, view, env)
        component = nil
        # Where Component#claim_dom_slot!'s throw surfaces — one catch per
        # companion, so standing down affects only this one. The block's
        # trailing nil is the no-contest value; the component itself is
        # captured by assignment so a successful build can't read as an id.
        contested = catch(Weft::Context::SLOT_TAKEN) do
          component = build_component_with_wire(inclusion[:component_class], companion_universe(env),
                                                overlays: overlays, branch_bag: env[:branch_bag],
                                                slots: slots)
          nil
        end
        return as_companion(component) unless contested

        warn_companion_collision(contested, winners[contested], inclusion)
        nil
      rescue StandardError => e
        # A delta block that raised leaves no overlays of its own; the
        # companion falls back to what it inherited from the response.
        recovered_companion(inclusion, env, overlays || env[:overlays] || {}, e)
      end

      # Each companion is an OOB-delivered child: it renders against the
      # same request universe, branches the primary's bag (rich values
      # included) exactly like a child built in the primary's own build,
      # and layers its own block delta — blockless is an empty delta.
      def companion_overlays(inclusion, view, env)
        inherited = env[:overlays] || {}
        return inherited unless inclusion[:block]

        delta = Weft::DSL::Sandbox.run(view, &inclusion[:block])
        delta.is_a?(Hash) ? inherited.merge(delta) : inherited
      end

      def companion_universe(env) = env.fetch(:universe) { filtered_params }

      # A companion is a courtesy, not a contract: the response belongs to
      # the primary, whose render, status and headers a failing bystander
      # must never touch. The action has already committed its side effects
      # by now, so failing the response would misstate what happened. The
      # companion walks its OWN recovery chain into its OWN slot instead —
      # component targets only, because a fragment riding inside a successful
      # response cannot redirect, and a companion must never navigate on the
      # primary's behalf.
      #
      # The recovery renders without the slot register: it inherits the failed
      # companion's claim rather than competing with it, since a build that
      # raised after claiming its slot still holds one.
      def recovered_companion(inclusion, env, overlays, error)
        klass = inclusion[:component_class]
        log_companion_failure(inclusion, error)
        entry = klass.component_recovery_for(error)
        return nil unless entry

        dom_id = failed_companion_dom_id(klass, env, overlays)
        component = build_component_with_wire(klass.resolve_recovery_target(entry), companion_universe(env),
                                              overlays: companion_recovery_overlays(klass, env, entry,
                                                                                    error, dom_id))
        as_companion(claim_dom_id(component, dom_id))
      rescue StandardError => e
        Weft.logger.error("Companion recovery render failed: #{e.class}: #{e.message}")
        nil
      end

      # Identity comes from exactly what the failed render was given — a delta
      # that moves an id-bearing param moves the slot with it, and an error
      # fragment addressed anywhere else lands on the wrong element.
      def failed_companion_dom_id(klass, env, overlays)
        resolved_dom_id(klass, unbuilt_instance(klass, companion_universe(env),
                                                overlays: overlays, branch_bag: env[:branch_bag]))
      end

      # The recovery target resolves its own schema from the request universe;
      # the entry's block delta and the auto-injected values ride as overlays,
      # exactly as on the primary's recovery path. No status is set — the
      # response's status belongs to the primary.
      def companion_recovery_overlays(klass, env, entry, error, dom_id)
        resolved = Weft::Resolver.resolve(klass, companion_universe(env))
        component_ctx = { originating_id: dom_id,
                          originating_tag: component_tag_for(klass),
                          retry_url: compute_retry_url(klass, resolved),
                          status: recovery_status(error, entry) }
        invoke_recovery_block(entry, resolved, error).merge(auto_param_overlay(error, component_ctx))
      end

      # The marker telling htmx to swap this fragment into the slot its id
      # names, rather than into the primary's position. The id is already
      # the component's own; only a recovery fragment has to be told.
      def as_companion(component)
        component.set_attribute("hx-swap-oob", "true")
        component
      end

      def log_companion_failure(inclusion, error)
        Weft.logger.error(
          "#{inclusion[:component_class].name} companion declared at " \
          "#{inclusion[:source_location].join(':')} failed to render: #{error.class}: #{error.message}"
        )
      end

      # Names what took the slot: another companion by its declaration site,
      # or — when nothing declared it — the component the response is about.
      def warn_companion_collision(dom_id, kept, dropped)
        claimant = if kept
                     "the companion declared at #{kept[:source_location].join(':')}"
                   else
                     "the component this response renders"
                   end
        Weft.logger.warn(
          "#{dropped[:component_class].name} companion declared at " \
          "#{dropped[:source_location].join(':')} was dropped: it resolves to DOM id " \
          "#{dom_id.inspect}, already claimed by #{claimant}. An out-of-band swap is addressed " \
          "by DOM id, so only one fragment can land there — give them different values for an " \
          "identifying param, or drop one of the declarations."
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
    end
  end
end
