# frozen_string_literal: true

require "arbre"

require "weft/action"

module Weft
  class Context < Arbre::Context
    # The modifier rank of the element-kwarg grammar: kwargs that adjust
    # whatever htmx wiring the interaction rank generated, applied as
    # call-site overrides after expansion. swap:/target: revert to plain
    # chrome when no interaction kwarg claims the element (target: is real
    # HTML — <a target="_blank">); trigger:/push_url:/confirm: map
    # standalone (all inherit down the DOM in htmx).
    module Modifiers
      MODIFIER_KEYS = %i[trigger push_url confirm swap target].freeze

      # Modifier kwargs that pull an element into expansion on their own.
      # :target is deliberately absent — bare target: stays honest HTML
      # chrome, untouched.
      CLAIMING_MODIFIER_KEYS = (MODIFIER_KEYS - [:target]).freeze

      # Warn-once registry for standalone swap: kwargs, keyed by the nearest
      # component class (nil outside any component).
      def self.warned_standalone_swaps
        @warned_standalone_swaps ||= Set.new
      end

      private

      # Call-site modifiers win over whatever the interaction expander
      # generated (an action's declared target, a preset's default swap, ...).
      def overlay_modifiers(expanded, mods)
        expanded["hx-swap"] = Action.resolve_swap(mods[:swap]) if mods[:swap]
        expanded["hx-target"] = resolve_target(mods[:target]) if mods[:target]
        apply_universal_modifiers(expanded, mods)
      end

      # No interaction kwarg claimed the element: swap:/target: revert to
      # chrome — swap with a warning, since swapping nothing is suspect but
      # not wrong — while the universal modifiers still map.
      def passthrough_modifiers(attrs, mods)
        warn_standalone_swap(mods[:swap]) if mods[:swap]
        attrs[:swap] = mods[:swap] if mods[:swap]
        attrs[:target] = mods[:target] if mods[:target]
        apply_universal_modifiers(attrs, mods)
      end

      def apply_universal_modifiers(attrs, mods)
        attrs["hx-trigger"] = resolve_trigger(mods[:trigger]) if mods[:trigger]
        attrs["hx-push-url"] = mods[:push_url].to_s if mods[:push_url]
        attrs["hx-confirm"] = mods[:confirm] if mods[:confirm]
        attrs
      end

      def warn_standalone_swap(value)
        klass = find_nearest_component&.class
        return unless Modifiers.warned_standalone_swaps.add?(klass)

        Weft.logger.warn "swap: #{value.inspect} has no effect without an interaction kwarg " \
                         "(action:, navigate:, loads:, or a preset)#{" in #{klass}" if klass} — " \
                         "passing it through as an HTML attribute"
      end

      def resolve_target(target)
        case target
        when :self then "this"
        when String then target
        else
          # Arbre element reference — extract #id
          target.respond_to?(:id) ? "##{target.id}" : target.to_s
        end
      end

      def resolve_trigger(value) = Action.resolve_trigger(value)
    end
  end
end
