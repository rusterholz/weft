# frozen_string_literal: true

require "weft/dsl/sandbox"
require "weft/params"
require "weft/params/assembly"
require "weft/redirect"

module Weft
  class Router
    # Action-dispatch slice of the Router. Resolves a request path to a
    # `[Action, ComponentClass]` pair, invokes the action callable, and
    # renders the result (either the component the action renders or a
    # Weft::Redirect). Error-handling delegates to Weft::Router::Errors via
    # `render_error`; the small `render_action_error` wrapper sets the
    # destructive-swap header before delegating.
    #
    # Depends on Router internals: `filtered_params`, `handle_redirect`,
    # `apply_announcement_header`, `render_error`, `headers`, and the
    # companion slice's `render_companions` / `applicable_companions` /
    # `explicitly_named_companions`.
    module Actions
      private

      # Parse path into component + action name, look up the action.
      # Returns [action, component_class] or nil.
      def resolve_action(path, http_method)
        component_class, action_name = find_component_and_action(path)
        return nil unless component_class&.routable?

        key = [action_name, http_method]
        action = component_class.actions[key]
        action ? [action, component_class] : nil
      end

      # Walk the path from longest to shortest prefix to find a registered
      # component. Any remaining path segment is the action name.
      def find_component_and_action(path)
        parts = path.split("/").reject(&:empty?)
        (parts.length - 1).downto(0) do |i|
          component_class = Weft.registry.lookup("/#{parts[0..i].join('/')}")
          next unless component_class

          action_name = i < parts.length - 1 ? parts[i + 1].to_sym : nil
          return [component_class, action_name]
        end
        nil
      end

      # State 1 — what the request composes from the wire before any of the
      # component's own code runs — is the bag the first verb block sees, and
      # it carries every door `build` reads: wire params, derivations (still
      # lazy), and defines. Only `receives` is missing, and structurally so:
      # an action request has no caller and no enclosing build to hand
      # anything over.
      #
      # A failure is recovered from wherever the request had got to, walked
      # from whoever was in charge at the time: the declarer's chain against
      # state 1 while its callable runs, and — once the callable has returned
      # and control has passed on — the rendering component's chain against
      # state 2.
      def handle_action(action, component_class)
        state = Weft::Params::Assembly.for_request(component_class, filtered_params)
        returned = Weft::DSL::Sandbox.run(state, &action.callable) if action.callable
        return handle_redirect(returned) if returned.is_a?(Weft::Redirect)
      rescue StandardError => e
        render_action_error(action, component_class, state || Weft::Params.new({}), e)
      else
        render_action_response(action, component_class, state, returned)
      end

      # One universe per request: the response renders against the request's
      # own wire, with the callable's returned hash riding as an overlay —
      # every component in the response (the rendered class, its nested
      # children, OOB companions) resolves from the same substrate, and the
      # delta overrides or clears wire values at any depth. The rendered
      # class projects its own schema; the declaring class's resolution
      # never crowns a new universe.
      #
      # Delete-swap actions skip the primary render entirely: htmx discards
      # the body on a delete swap, and the component's record is typically
      # gone by now. Companions still ride (a 200, never a 204 — htmx
      # refuses to swap 204s, which would skip the delete itself).
      def render_action_response(action, component_class, state, returned)
        overlay = returned.is_a?(Hash) ? returned : {}
        composed = state.overlay(overlay)
        apply_announcement_header(component_class, action.name)
        slots = Set.new
        primary = build_action_primary(action, overlay, composed, slots)
        (primary ? primary.to_s : "") +
          render_companions(action_companions(action, component_class, primary, composed, overlay), slots)
      rescue StandardError => e
        render_action_error(action, action.renders, composed, e)
      end

      # Which companions ride this response, in precedence order: the
      # rendered component's first, then — on a transfer — the declaring
      # component's explicitly named ones. One list, so two companions
      # claiming a single DOM id are caught across the two sources and the
      # rendered component's declaration keeps the slot.
      def action_companions(action, component_class, primary, composed, overlay)
        target = target_companions(action, component_class, primary, composed, overlay)
        return target if action.renders.equal?(component_class)

        target + declarer_companions(component_class, action.name, composed, overlay)
      end

      # The rendered component's companions: its block reads the primary's
      # rendered bag (rich values included) and each one branches it.
      def target_companions(action, component_class, primary, composed, overlay)
        context = action.renders.equal?(component_class) ? :action : :transfer
        env = { universe: filtered_params, overlays: overlay, branch_bag: primary&.params }
        view = companion_view(primary, composed, overlay)
        applicable_companions(action.renders, context, action.name).map { |inc| [inc, view, env] }
      end

      # The declaring component's companions on a transfer. This branch
      # forks before the hand-off, so the block reads the declarer's own
      # params plus the callable's overlay — never the target's picture —
      # and there is no primary bag to branch, because nothing rendered the
      # declarer and so no rich values exist on this path.
      def declarer_companions(component_class, action_name, composed, overlay)
        env = { universe: filtered_params, overlays: overlay }
        explicitly_named_companions(component_class, action_name).map { |inc| [inc, composed, env] }
      end

      # Delete-swap actions skip the primary render: htmx discards the body
      # on a delete swap, and the component's record is typically gone.
      # The primary claims its DOM slot first, so a companion aimed at the
      # same id is turned away rather than swapping over the very fragment
      # the response is about.
      #
      # The primary branches the state the request has already composed, so a
      # derivation the callable forced isn't paid for twice — and a transfer
      # target inherits it exactly as a nested child inherits its parent's.
      # Declared defaults don't ride a branch, so the target's own fallbacks
      # stay its own; to override an inherited value, return the key (an
      # explicit nil clears it).
      def build_action_primary(action, overlay, composed, slots)
        return nil if action.swap == :delete

        build_component_with_wire(action.renders, filtered_params, overlays: overlay,
                                                                   branch_bag: composed, slots: slots)
      end

      # The params view a companion block receives: the rendered primary's
      # bag with the overlay applied (undeclared delta keys stay readable).
      # On a delete-swap there is no primary — the composed state stands in.
      def companion_view(primary, composed, overlay)
        primary ? primary.params.overlay(overlay) : composed
      end

      # Error handling for actions. Adds HX-Reswap header when the action's
      # swap strategy is destructive (e.g., :delete) so the error fragment
      # renders visibly instead of the element being silently removed.
      def render_action_error(action, component_class, resolved_params, error)
        headers["HX-Reswap"] = "outerHTML" if action.swap == :delete
        render_error(component_class, resolved_params, error)
      end
    end
  end
end
