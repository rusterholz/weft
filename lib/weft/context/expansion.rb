# frozen_string_literal: true

require "arbre"
require "uri"

require "weft/action"
require "weft/context/modifiers"
require "weft/error"

module Weft
  class Context < Arbre::Context
    # The element-kwarg expansion engine: turns Weft kwargs on any element
    # into htmx attributes. Mixed into Weft::Context; Interception#insert_tag
    # invokes it on the root context (via +arbre_context+).
    #
    # This module owns the INTERACTION rank of the kwarg grammar — the kwargs
    # that generate request wiring, first match wins: `action:` (Symbol),
    # `navigate:` (Hash), `loads:` (Class), or a registered preset name
    # (Class or URL String). Value shape is the claim — a String action:
    # stays honest form HTML — and a claimed kwarg that cannot resolve
    # raises Weft::InvalidUsage rather than leaking into the HTML. The
    # MODIFIER rank (trigger:/push_url:/confirm:/swap:/target:) lives in
    # Context::Modifiers.
    module Expansion
      # @api private
      def expand_weft_attrs(attrs, for_class: nil)
        attrs = attrs.dup
        mods = Modifiers::MODIFIER_KEYS.to_h { |k| [k, attrs.delete(k)] }
        validate_with_ownership!(attrs)
        expanded = expand_action(attrs, for_class: for_class) || expand_navigate(attrs) ||
                   expand_loads(attrs, mods) || expand_preset(attrs, mods)
        expanded ? overlay_modifiers(expanded, mods) : passthrough_modifiers(attrs, mods)
      end

      # @api private
      # Whether an attrs hash carries any Weft kwarg.
      def weft_kwarg?(hash)
        interaction_kwarg?(hash) || modifier_kwarg?(hash) || claimed?(hash, :with)
      end

      private

      def interaction_kwarg?(hash)
        hash[:action].is_a?(Symbol) || claimed?(hash, :navigate) ||
          claimed?(hash, :loads) || find_preset_kwarg(hash)
      end

      def modifier_kwarg?(hash) = Modifiers::CLAIMING_MODIFIER_KEYS.any? { |k| hash.key?(k) }

      # A nil value means absent — the conditional-call-site idiom
      # (`tooltip: maybe_class`), mirroring Arbre's nil-attribute omission.
      def claimed?(hash, key) = hash.key?(key) && !hash[key].nil?

      # with: belongs to loads:/preset expansion; anywhere else it would
      # silently ride into the HTML as junk chrome.
      def validate_with_ownership!(attrs)
        return unless claimed?(attrs, :with)
        return if claimed?(attrs, :loads) || find_preset_kwarg(attrs)

        raise Weft::InvalidUsage,
              "with: supplies wire params to a loads:/preset target — it needs one of those kwargs alongside it"
      end

      def expand_action(attrs, for_class: nil)
        action_name = attrs[:action]
        return unless action_name.is_a?(Symbol)

        component = find_action_context(action_name)
        unless component
          raise Weft::InvalidUsage, "action: #{action_name.inspect} matches no action declared by an " \
                                    "enclosing component — check the name against its performs/transfers declarations"
        end

        action = component.class.action_for(action_name)
        htmx = action.to_htmx_attrs(component)
        expanded = attrs.except(:action).merge(htmx)
        return augment_for_form(expanded, action, htmx) if for_class && for_class <= Arbre::HTML::Form

        expanded
      end

      # On <form> elements, also emit the HTML action and method attributes so
      # non-JS submission works (browser POSTs to the same URL htmx would).
      # Drop hx-vals because the form fields are the submission payload —
      # hx-vals would duplicate or shadow them.
      def augment_for_form(expanded, action, htmx)
        url = htmx["hx-#{action.method}"]
        expanded.except("hx-vals").merge("action" => url, "method" => action.method.to_s)
      end

      def expand_navigate(attrs)
        return unless claimed?(attrs, :navigate)

        overrides = attrs[:navigate]
        unless overrides.is_a?(Hash)
          raise Weft::InvalidUsage, "navigate: expects a Hash of wire-param overrides, got #{overrides.inspect}"
        end

        component = find_nearest_component
        raise Weft::InvalidUsage, "navigate: has no enclosing component whose route it could re-fetch" if component.nil?

        validate_navigate_keys!(component, overrides)
        attrs.except(:navigate).merge(navigate_attrs(component, overrides))
      end

      # navigate: re-fetches the component's own route, and the resulting
      # render is standalone — only the component's own declared wire params
      # survive that request. Anything else would silently vanish.
      def validate_navigate_keys!(component, overrides)
        bad = overrides.keys.reject { |k| component.class.params.key?(k) }
        return if bad.empty?

        raise Weft::InvalidUsage,
              "navigate: #{bad.map(&:inspect).join(', ')} not declared as wire params of #{component.class} — " \
              "only its own declared params survive the standalone re-fetch " \
              "(declare `param #{bad.first.inspect}` on it, or reach an ancestor with enclosing + loads:)"
      end

      def expand_loads(attrs, mods)
        return unless claimed?(attrs, :loads)

        target_class = attrs[:loads]
        unless target_class.is_a?(Class)
          raise Weft::InvalidUsage, "loads: expects a component Class, got #{target_class.inspect}"
        end

        validate_loads_kwargs!(mods)
        remaining = attrs.except(:loads, :with)
        remaining.merge(loads_attrs(target_class, resolve_with(attrs), mods[:swap], mods[:target]))
      end

      def expand_preset(attrs, mods)
        preset_key, target_class = find_preset_kwarg(attrs)
        return unless preset_key

        build_preset_attrs(attrs, mods, preset_key, target_class, Weft.preset(preset_key))
      end

      # A preset value is either a target Class (derive the URL from it) or a
      # ready-made URL String (retry-style — the caller already has the URL).
      def find_preset_kwarg(attrs)
        attrs.find do |k, v|
          next false if v.nil? || !Weft.preset(k)
          raise Weft::InvalidUsage, "#{k}: expects a component Class or a URL String, got #{v.inspect}" unless
            v.is_a?(Class) || v.is_a?(String)

          true
        end
      end

      def build_preset_attrs(attrs, mods, preset_key, target_or_url, preset)
        target = mods[:target] || preset[:target]
        raise Weft::InvalidUsage, "#{preset_key}: requires target: (e.g., target: :self)" unless target

        swap = mods[:swap] || preset[:swap]
        htmx = if target_or_url.is_a?(String)
                 htmx_get_attrs(target_or_url, swap, target)
               else
                 loads_attrs(target_or_url, resolve_with(attrs), swap, target)
               end
        htmx["hx-trigger"] = resolve_trigger(preset[:trigger]) if preset[:trigger]
        attrs.except(preset_key, :with).merge(htmx)
      end

      def resolve_with(attrs)
        attrs[:with] || find_nearest_component&.serializable_params || {}
      end

      def validate_loads_kwargs!(mods)
        raise Weft::InvalidUsage, "loads: requires swap: (e.g., swap: :fill)" unless mods[:swap]
        raise Weft::InvalidUsage, "loads: requires target: (e.g., target: :self)" unless mods[:target]
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

      def navigate_attrs(component, overrides)
        {
          "hx-get" => component.weft_url(**overrides),
          "hx-target" => "##{component.weft_dom_id}",
          "hx-swap" => "outerHTML"
        }
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
    end
  end
end
