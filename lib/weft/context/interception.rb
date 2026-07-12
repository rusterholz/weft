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
        if h.is_a?(Hash) && arbre_context.is_a?(Weft::Context) && arbre_context.weft_kwarg?(h)
          args[-1] = arbre_context.expand_weft_attrs(h, for_class: klass)
        end
        super
      end
    end
  end
end
