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
    # Depends on Router internals: `resolver`, `filtered_params`,
    # `handle_redirect`, `apply_trigger_header`, `render_oob_includes`,
    # `render_error`, `headers`.
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
        resolved_params = resolver.resolve(component_class, filtered_params)
        returned = action.callable&.call(Weft::Params.new(resolved_params))
        return handle_redirect(returned) if returned.is_a?(Weft::Redirect)

        render_action_response(action, component_class, resolved_params, returned)
      rescue StandardError => e
        render_action_error(action, component_class, resolved_params || {}, e)
      end

      # Successive resolution across the component-class boundary. The bag
      # accumulates the declaring component's resolved params plus any hash the
      # callable returned; the rendered class then runs its OWN resolution pass
      # over the bag, so only its declared params reach the builder splat
      # (closing the cross-class leak). The bag itself keeps every key so
      # downstream OOB includes still see callable-returned params.
      def render_action_response(action, component_class, resolved_params, returned)
        bag = returned.is_a?(Hash) ? resolved_params.merge(returned) : resolved_params
        apply_trigger_header(component_class)
        html = action.renders.render(**resolver.resolve(action.renders, bag))
        html + render_oob_includes(component_class, Weft::Params.new(bag), action_name: action.name)
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
