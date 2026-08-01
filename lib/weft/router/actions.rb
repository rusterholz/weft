# frozen_string_literal: true

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
    # `apply_trigger_header`, `render_oob_includes`, `render_error`,
    # `headers`.
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

      def handle_action(action, component_class)
        resolved_params = Weft::Resolver.resolve(component_class, filtered_params)
        returned = Weft::DSL::Sandbox.run(Weft::Params.new(resolved_params), &action.callable) if action.callable
        return handle_redirect(returned) if returned.is_a?(Weft::Redirect)

        render_action_response(action, component_class, resolved_params, returned)
      rescue StandardError => e
        render_action_error(action, component_class, resolved_params || {}, e)
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
      # gone by now. OOB includes still ride (a 200, never a 204 — htmx
      # refuses to swap 204s, which would skip the delete itself).
      def render_action_response(action, component_class, resolved_params, returned)
        overlay = returned.is_a?(Hash) ? returned : {}
        apply_trigger_header(component_class)
        primary = build_action_primary(action, overlay)
        env = { universe: filtered_params, overlays: overlay, branch_bag: primary&.params }
        (primary ? primary.to_s : "") +
          render_oob_includes(action.renders, includes_view(primary, resolved_params, overlay),
                              context: action.renders.equal?(component_class) ? :action : :transfer,
                              action_name: action.name, render_env: env)
      end

      # Delete-swap actions skip the primary render: htmx discards the body
      # on a delete swap, and the component's record is typically gone.
      def build_action_primary(action, overlay)
        return nil if action.swap == :delete

        build_component_with_wire(action.renders, filtered_params, overlays: overlay)
      end

      # The params view an inclusion block receives: the rendered primary's
      # bag with the overlay applied (undeclared delta keys stay readable).
      # On a delete-swap there is no primary — the Router-resolved params
      # stand in.
      def includes_view(primary, resolved_params, overlay)
        return Weft::Params.new(resolved_params.merge(overlay)) unless primary

        primary.params.overlay(overlay)
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
