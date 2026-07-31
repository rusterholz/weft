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
    # Context::Modifiers; the hx-* builders and tree lookups the expanders
    # assemble from live in Context::Wiring.
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
      def weft_kwarg?(hash) = interaction_kwarg?(hash) || modifier_kwarg?(hash) || claimed?(hash, :with)

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

      def expand_navigate(attrs)
        return unless claimed?(attrs, :navigate)

        overrides = attrs[:navigate]
        unless overrides.is_a?(Hash)
          raise Weft::InvalidUsage, "navigate: expects a Hash of wire-param overrides, got #{overrides.inspect}"
        end

        component = navigation_component!
        validate_navigate_keys!(component, overrides)
        attrs.except(:navigate).merge(navigate_attrs(component, overrides))
      end

      # The enclosing component navigate: re-fetches — present and routable,
      # or the wiring could only 404.
      def navigation_component!
        component = find_nearest_component
        raise Weft::InvalidUsage, "navigate: has no enclosing component whose route it could re-fetch" if component.nil?

        unless component.class.routable?
          raise Weft::InvalidUsage,
                "navigate: re-fetches #{component.class.name}, which is not routable — its URL can only 404. " \
                "Drop the class's abstract!/dependent! marking, or reach a routable ancestor with enclosing + loads:"
        end

        component
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

        ensure_routable_target!(target_class, :loads)
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
        ensure_routable_target!(target_or_url, preset_key) if target_or_url.is_a?(Class)
        target = mods[:target] || preset[:target]
        raise Weft::InvalidUsage, "#{preset_key}: requires target: (e.g., target: :self)" unless target

        htmx = preset_wiring(attrs, target_or_url, preset, mods[:swap] || preset[:swap], target)
        attrs.except(preset_key, :with).merge(htmx)
      end

      def resolve_with(attrs) = attrs[:with] || find_nearest_component&.serializable_params || {}

      def validate_loads_kwargs!(mods)
        raise Weft::InvalidUsage, "loads: requires swap: (e.g., swap: :fill)" unless mods[:swap]
        raise Weft::InvalidUsage, "loads: requires target: (e.g., target: :self)" unless mods[:target]
      end

      # A load target is fetched over the wire at click time — a non-routable
      # class wires a URL that can only 404, silently. Raise at render instead.
      # String URLs (retry-style presets) are unverifiable and pass through;
      # transfers to: is exempt by design (a render target, not a route).
      def ensure_routable_target!(target_class, kwarg)
        return if target_class.routable?

        raise Weft::InvalidUsage,
              "#{kwarg}: targets #{target_class.name}, which is not routable — the generated URL can only 404. " \
              "Mark it routable! (or drop its abstract!/dependent! marking) so it can serve standalone fetches"
      end
    end
  end
end
