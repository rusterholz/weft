# frozen_string_literal: true

require "weft/dsl/identity"
require "weft/error"

module Weft
  class Registry
    # Identity slice of the Registry's validation pass. What has to hold of one
    # class's own declarations: that its identity names keys it actually has,
    # that those keys can compose a DOM id, and that a class declining an id has
    # nothing depending on one.
    #
    # Separate from {Validation}, which answers what has to hold across the
    # registered set as a whole — two classes claiming one route, two deriving
    # one id base. These need no view of their neighbors; they live in the pass
    # rather than in the macros because the declarations they compare can appear
    # in a class body in either order.
    #
    # Depends on Registry internals: `@components`.
    module IdentityValidation
      SCALAR_KINDS = "scalars (String, Symbol, number, boolean, or nil), since weft targets " \
                     "fragments with `#id`"
      private_constant :SCALAR_KINDS

      private

      # `identifies_by` may legally precede the `param` lines it names, so at the
      # macro there is nothing to check against yet. First in the pass: these
      # report one class's own body with a one-line remedy, where the collision
      # checks report a pair and may need a rename or an explicit path.
      def validate_identifiers!
        @components.each do |klass|
          next if klass.identifiers.empty?

          refuse_undeclared_identifiers!(klass)
          judge_pinned_identifiers!(klass)
          refuse_nonscalar_defaults!(klass)
        end
      end

      # A named key no door declares can only be a mistake: it composes a blank
      # slot, and the blank-slot warning then recommends `digest:` on a param
      # that does not exist, sending the reader to declare a second wrong thing.
      def refuse_undeclared_identifiers!(klass)
        missing = klass.identifiers - klass.declared_keys
        return if missing.empty?

        raise Weft::InvalidDefinition,
              "#{klass.name} identifies by #{key_list(missing)}, which it does not declare. " \
              "#{declared_keys_advice(klass)}"
      end

      def declared_keys_advice(klass)
        declared = klass.declared_keys
        if declared.empty?
          "It declares no params at all — declare the key, or `unique!` if it has nothing to " \
            "identify by."
        else
          "It declares #{key_list(declared)} — name one of those, declare the missing key, or " \
            "`unique!` if it has nothing to identify by."
        end
      end

      # A pin holds one value for every instance, so it is always redundant with
      # the stem. Alone in an identity that is fatal — every instance of the
      # class then wears one id — while beside a varying key it is redundant
      # tail, and refusing that would refuse a declaration that works.
      #
      # Until now this was diagnosed only where the pinned value rendered blank,
      # which is an accident of which remedy the blank-slot warning reaches for.
      def judge_pinned_identifiers!(klass)
        pinned = klass.identifiers.select { |key| klass.derived_params[key]&.[](:pinned) }
        return if pinned.empty?

        raise Weft::InvalidDefinition, pinned_identity_message(klass, pinned) if pinned == klass.identifiers

        refuse_unaddressable_pins!(klass, pinned)
        Weft.logger.warn(redundant_pin_warning(klass, pinned))
      end

      # A pin that cannot compose an id outranks the redundancy warning above:
      # that identity is broken rather than merely wasteful. The pinned value
      # lives in the closure `defines` built, which is weft's own proc and
      # answers the same value however often it is asked.
      def refuse_unaddressable_pins!(klass, pinned)
        pinned.each do |key|
          value = klass.derived_params[key][:block].call(nil)
          next if scalar_identifier?(value)

          raise Weft::InvalidDefinition,
                "#{klass.name} identifies by #{key.inspect}, which `defines` pins to " \
                "#{value.inspect}, #{value.class}. A DOM id is composed from #{SCALAR_KINDS}, so " \
                "that slot can never compose one. Pin a scalar, or drop the key from the identity."
        end
      end

      # A declared non-scalar default is the one piece of declare-time evidence
      # an untyped param offers: proof the key can hold a value no DOM id can be
      # composed from. A typed param never arrives here — a default disagreeing
      # with its type is already refused at the macro.
      def refuse_nonscalar_defaults!(klass)
        klass.identifiers.each do |key|
          meta = defaulting_meta(klass, key)
          next if meta.nil? || scalar_identifier?(meta[:default])

          raise Weft::InvalidDefinition,
                "#{klass.name} identifies by #{key.inspect}, whose declared default " \
                "#{meta[:default].inspect} is #{meta[:default].class}. A DOM id is composed from " \
                "#{SCALAR_KINDS}. Declare a scalar default, drop the default, or identify by " \
                "something else."
        end
      end

      # A stream addresses its component by DOM id — `sse-swap` carries it — so a
      # component that declines an id has nowhere for its pushes to land.
      #
      # `refreshes` is deliberately absent: it renders `hx-swap="outerHTML"` with
      # no `hx-target`, so it addresses itself positionally and an anonymous
      # component refreshes perfectly well.
      def validate_addressability!
        @components.each do |klass|
          next unless klass.anonymous? && klass.push_config&.key?(:every)

          raise Weft::InvalidDefinition,
                "#{klass.name} is anonymous! but declares pushes — a stream swaps by DOM id, " \
                "so it has nowhere to land. Give the component an identity, or drop the pushes."
        end
      end

      # Wire first, mirroring the facet lookup the DSL does: for a dual key the
      # wire door is the one a URL round-trips through.
      def defaulting_meta(klass, key)
        [klass.params, klass.received_params].each do |table|
          meta = table[key]
          return meta if meta&.key?(:default)
        end
        nil
      end

      def scalar_identifier?(value)
        Weft::DSL::Identity::SCALAR_ID_CLASSES.any? { |scalar| value.is_a?(scalar) }
      end

      def pinned_identity_message(klass, pinned)
        "#{klass.name} identifies by #{key_list(pinned)}, which `defines` pins to one value for " \
          "every instance, so every instance resolves to the same DOM id. Identify by a value " \
          "that varies, or declare `unique!` for a slot of its own."
      end

      def redundant_pin_warning(klass, pinned)
        adds = pinned.one? ? "it adds" : "they add"
        drop = pinned.one? ? "Drop it" : "Drop them"
        "#{klass.name} identifies by #{key_list(pinned)}, which `defines` pins to one value for " \
          "every instance, so #{adds} nothing the rest of the identity does not already " \
          "distinguish. #{drop} from the identity."
      end

      def key_list(keys) = keys.map(&:inspect).join(", ")
    end
  end
end
