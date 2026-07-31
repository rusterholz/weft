# frozen_string_literal: true

require "arbre"
require "uri"

require "weft/action"

module Weft
  class Context < Arbre::Context
    # The low-level wiring layer under the kwarg grammar: htmx attribute
    # builders and render-tree lookups. Context::Expansion decides WHICH
    # interaction claims an element; these methods build the actual hx-*
    # hashes and find the components they point at. Mixed into Weft::Context
    # alongside Expansion and Modifiers (whose resolve_swap/resolve_target
    # vocabulary the builders lean on).
    module Wiring
      private

      # On <form> elements, also emit the HTML action and method attributes so
      # non-JS submission works (browser POSTs to the same URL htmx would).
      # Drop hx-vals because the form fields are the submission payload —
      # hx-vals would duplicate or shadow them.
      def augment_for_form(expanded, action, htmx)
        url = htmx["hx-#{action.method}"]
        expanded.except("hx-vals").merge("action" => url, "method" => action.method.to_s)
      end

      def navigate_attrs(component, overrides)
        {
          "hx-get" => component.weft_url(**overrides),
          "hx-target" => "##{component.weft_dom_id}",
          "hx-swap" => "outerHTML"
        }
      end

      def preset_wiring(attrs, target_or_url, preset, swap, target)
        htmx = if target_or_url.is_a?(String)
                 htmx_get_attrs(target_or_url, swap, target)
               else
                 loads_attrs(target_or_url, resolve_with(attrs), swap, target)
               end
        htmx["hx-trigger"] = resolve_trigger(preset[:trigger]) if preset[:trigger]
        htmx
      end

      def loads_attrs(target_class, with_attrs, swap, target)
        htmx_get_attrs(component_url(target_class, with_attrs), swap, target)
      end

      def component_url(target_class, with_attrs)
        path = target_class.resolved_component_path
        params = with_attrs.compact
        params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
      end

      def htmx_get_attrs(url, swap, target)
        {
          "hx-get" => url,
          "hx-swap" => Action.resolve_swap(swap),
          "hx-target" => resolve_target(target)
        }
      end

      def find_action_context(action_name)
        el = current_arbre_element
        while el
          return el if el.is_a?(Weft::Component) && el.class.action_for(action_name)

          el = el.parent
        end
        nil
      end

      def find_nearest_component
        el = current_arbre_element
        while el
          return el if el.is_a?(Weft::Component)

          el = el.parent
        end
        nil
      end
    end
  end
end
