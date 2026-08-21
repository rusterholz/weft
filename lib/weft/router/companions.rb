# frozen_string_literal: true

require "weft/context"
require "weft/dsl/sandbox"
require "weft/params/assembly"

module Weft
  class Router
    # Companion slice of the Router. Renders the companion components a
    # component declares via `brings`, riding alongside its response with the
    # `hx-swap-oob` attribute set so htmx swaps each into its own DOM slot.
    #
    # Depends on Router internals: `filtered_params`,
    # `build_component_with_wire`, and the Errors slice's identity and
    # recovery helpers (`unbuilt_instance`, `resolved_dom_id`,
    # `invoke_recovery_block`, `auto_param_overlay`, `component_tag_for`,
    # `compute_retry_url`, `recovery_status`).
    module Companions
      private

      # The companions riding an SSE frame. A push is nobody's action and no
      # transfer's destination, so only unfiltered companions — "every
      # response I render in" — qualify; `on:` and `when:` both name contexts
      # a stream never enters.
      def render_push_companions(component_class, primary_params, render_env:, slots:)
        render_companions(applicable_companions(component_class, :push, nil).
                            map { |inc| [inc, primary_params, render_env] }, slots)
      end

      # The companions of one component that fire in one context.
      def applicable_companions(component_class, context, action_name)
        component_class.companions.select { |inc| companion_applies?(inc, context, action_name) }
      end

      # The companions that name an action outright. A transfer's declaring
      # component never renders, so its unfiltered companions ("every
      # response I render in") stay silent — but `on:` doesn't narrow that
      # default, it replaces it, and this action is the declarer's own.
      def explicitly_named_companions(component_class, action_name)
        component_class.companions.select { |inc| inc[:on]&.include?(action_name) }
      end

      # Render a planned set of companions: each entry pairs a companion
      # with the params view its block reads and the environment its
      # component builds in, because companions arriving from different
      # branches of one response fork at different points.
      def render_companions(plan, slots)
        return "" if plan.empty?

        winners = {}
        plan.filter_map { |companion, view, env| companion_fragment(companion, view, env, slots, winners) }.
          join.html_safe
      end

      # One companion's fragment, or nil when it yields none. `winners` records
      # who took each slot, so a collision can name the declaration it lost to.
      def companion_fragment(companion, view, env, slots, winners)
        fragment = attempt_companion(companion, view, env, slots, winners)
        winners[fragment.id] = companion if fragment
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
      def attempt_companion(companion, view, env, slots, winners)
        overlays = companion_overlays(companion, view, env)
        component = nil
        # Where Component#claim_dom_slot!'s throw surfaces — one catch per
        # companion, so standing down affects only this one. The block's
        # trailing nil is the no-contest value; the component itself is
        # captured by assignment so a successful build can't read as an id.
        contested = catch(Weft::Context::SLOT_TAKEN) do
          component = build_component_with_wire(companion[:component_class], companion_universe(env),
                                                overlays: overlays, branch_bag: env[:branch_bag],
                                                slots: slots)
          nil
        end
        return as_companion(component) unless contested

        warn_companion_collision(contested, winners[contested], companion)
        nil
      rescue StandardError => e
        # A delta block that raised leaves no overlays of its own; the
        # companion falls back to what it inherited from the response.
        recovered_companion(companion, env, overlays || env[:overlays] || {}, e)
      end

      # Each companion is an OOB-delivered child: it renders against the
      # same request universe, branches the primary's bag (rich values
      # included) exactly like a child built in the primary's own build,
      # and layers its own block delta — blockless is an empty delta.
      def companion_overlays(companion, view, env)
        inherited = env[:overlays] || {}
        return inherited unless companion[:block]

        delta = Weft::DSL::Sandbox.run(view, &companion[:block])
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
      def recovered_companion(companion, env, overlays, error)
        klass = companion[:component_class]
        log_companion_failure(companion, error)
        entry = klass.component_recovery_for(error)
        return nil unless entry

        dom_id = failed_companion_dom_id(klass, env, overlays)
        recovery_overlays = companion_recovery_overlays(klass, companion_state(klass, env, overlays),
                                                        entry, error, dom_id)
        component = build_component_with_wire(klass.resolve_recovery_target(entry),
                                              companion_universe(env), overlays: recovery_overlays)
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

      # The state the failed build was given — its own wire schema over the
      # request universe, the companion block's delta on top, branching
      # whatever the primary composed. Rebuilt rather than read off the
      # instance because a build that raised leaves none.
      #
      # Keys the class doesn't declare are laid on afterwards rather than
      # resolved through the stack, which only visits declared keys — that's
      # what keeps a companion block's ad-hoc delta readable in the recovery
      # block, the same way it stays readable in the block that produced it.
      def companion_state(klass, env, overlays)
        Weft::Params::Assembly.call(klass, companion_universe(env),
                                    overlays: overlays, branched_from: env[:branch_bag]).
          overlay(overlays.except(*klass.declared_keys))
      end

      # The recovery target resolves its own schema from the request universe;
      # the entry's block delta and the auto-injected values ride as overlays,
      # exactly as on the primary's recovery path. No status is set — the
      # response's status belongs to the primary.
      def companion_recovery_overlays(klass, state, entry, error, dom_id)
        component_ctx = { originating_id: dom_id,
                          originating_tag: component_tag_for(klass),
                          retry_url: compute_retry_url(klass, error_wire_params(klass)),
                          status: recovery_status(error, entry) }
        invoke_recovery_block(entry, state, error).merge(auto_param_overlay(error, component_ctx))
      end

      # The marker telling htmx to swap this fragment into the slot its id
      # names, rather than into the primary's position. The id is already
      # the component's own; only a recovery fragment has to be told.
      def as_companion(component)
        component.set_attribute("hx-swap-oob", "true")
        component
      end

      def log_companion_failure(companion, error)
        Weft.logger.error(
          "#{companion[:component_class].name} companion declared at " \
          "#{companion[:source_location].join(':')} failed to render: #{error.class}: #{error.message}"
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
          "identifying param, or drop one of the declarations. If the values already differ and " \
          "still land here, they render to the same slot: declare that param `digest: true` to " \
          "keep them apart."
        )
      end

      def companion_applies?(companion, context, action_name)
        return true if companion[:on].nil? && companion[:when].nil?

        filtered_contexts(companion, action_name).include?(context)
      end

      # The contexts this filtered companion fires in — on: and when: union.
      def filtered_contexts(companion, action_name)
        contexts = []
        contexts << :action if companion[:on]&.include?(action_name)
        contexts << :transfer if companion[:when]&.include?(:transferred)
        contexts
      end
    end
  end
end
