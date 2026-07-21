# frozen_string_literal: true

module Weft
  class Context < Arbre::Context
    # Mixin for Arbre elements that need to forward Weft kwargs
    # (action:, navigate:, trigger:, etc.) to the Context for expansion.
    #
    # Included by Weft::Context, Weft::Component, and Weft::Page — all three
    # share this one #insert_tag. It forwards any Weft kwargs to the root
    # Weft::Context (via +arbre_context+), which is the expansion engine
    # (#weft_kwarg? / #expand_weft_attrs).
    module Interception
      def insert_tag(klass, *args, &)
        h = args.last
        if h.is_a?(Hash) && arbre_context.is_a?(Weft::Context)
          h = stage_received_kwargs(klass, h)
          h = arbre_context.expand_weft_attrs(h, for_class: klass) if arbre_context.weft_kwarg?(h)
          args[-1] = h
        end
        super
      end

      private

      # Kwargs naming a target's declared `receives` keys are hand-offs, not
      # chrome: pull them out before Arbre sees them and stage them on the
      # context register for the instance about to be constructed.
      def stage_received_kwargs(klass, attrs)
        return attrs unless klass.respond_to?(:received_params)

        keys = klass.received_params.keys & attrs.keys
        return attrs if keys.empty?

        attrs = attrs.dup
        arbre_context.stage_received(klass, keys.to_h { |k| [k, attrs.delete(k)] })
        attrs
      end
    end
  end
end
