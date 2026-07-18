# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare consumed inputs — the doors into `params`.
    # Provides the `param` (wire) and `receives` (caller hand-off) class DSL
    # and the `params` instance reader.
    # Used by Component (for partial route params) and Page (for page route params).
    module Params
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare a wire param. Accepts optional default: and type: kwargs.
        #   param :status, default: "active", type: :string
        def param(name, default: nil, **options)
          meta = { default: default }
          meta[:type] = options[:type] if options.key?(:type)
          own_params[name] = meta
        end

        # Returns all declared params (own + inherited), preserving declaration order.
        def params
          if superclass.respond_to?(:params)
            superclass.params.merge(own_params)
          else
            own_params.dup
          end
        end

        # Declare a hand-off param: the caller provides the value as a builder
        # kwarg at the call site; it lands in `params`, never in HTML chrome.
        #   receives :order                  # required — absence raises
        #   receives :page_num, default: 1   # optional — any declared default
        #                                    # (even nil) softens absence
        # Hand-offs are server-side values: they never serialize into URLs and
        # don't make a component routable.
        def receives(name, **options)
          meta = {}
          meta[:default] = options[:default] if options.key?(:default)
          own_received_params[name] = meta
        end

        # All declared hand-offs (own + inherited), preserving declaration
        # order. Kept separate from `params` — the wire door and the hand-off
        # door differ in serialization and routability, even for dual keys.
        def received_params
          if superclass.respond_to?(:received_params)
            superclass.received_params.merge(own_received_params)
          else
            own_received_params.dup
          end
        end

        private

        def own_params
          @own_params ||= {}
        end

        def own_received_params
          @own_received_params ||= {}
        end
      end

      # One-time chrome-collision warnings, keyed [class, key].
      # See #warn_declared_chrome_collisions.
      def self.warned_collisions
        @warned_collisions ||= Set.new
      end

      # Instance access to the resolved bag.
      # Returns a Weft::Params object with method-style and hash access.
      attr_reader :params

      # @api private
      # The bag projected onto this class's own declared wire schema — the
      # only slice that serializes (refresh/stream URLs, DOM ids, hx-vals).
      # Hand-offs and inherited values are server-side and never ride the wire.
      def serializable_params
        params ? params.to_h.slice(*self.class.params.keys) : {}
      end

      private

      # Assemble the bag per the source stack: staged hand-off > own wire
      # value > inherited bag value > declared default. Staging only happens
      # under Weft::Context; in a plain Arbre context the hand-off door is a
      # build-top fallback instead, so hand-off validation waits for it there.
      def assembled_params
        if arbre_context.respond_to?(:take_received!)
          resolve_bag(received: arbre_context.take_received!(self.class) || {}, validate: true)
        else
          resolve_bag(received: {}, validate: false)
        end
      end

      def resolve_bag(received:, validate:)
        wire = Weft::Resolver.resolve_present(self.class, wire_source)
        inherited = inherited_bag
        bag = inherited.dup
        declared_keys.each { |key| bag[key] = stack_value(key, received, wire, inherited) }
        validate_hand_offs!(bag) if validate
        Weft::Params.new(bag)
      end

      def declared_keys = self.class.params.keys | self.class.received_params.keys

      # The per-key source stack, top wins: hand-off > own wire > inherited >
      # default. nil never wins a level — it means that source didn't have it.
      def stack_value(key, received, wire, inherited)
        [received[key], wire[key], inherited[key], default_for(key)].find { |v| !v.nil? }
      end

      def validate_hand_offs!(bag)
        self.class.received_params.each_key do |key|
          raise_not_received!(key) if bag[key].nil? && required_hand_off?(key)
        end
      end

      def wire_source
        arbre_context.respond_to?(:wire_params) ? arbre_context.wire_params : {}
      end

      # Branch a copy of the nearest tree-ancestor's bag — the in-page
      # parent-child axis: a component sees everything above it, nothing
      # beside it. At construction the current element IS the future parent,
      # so the walk works before the tree links this instance in. nil values
      # mean "nobody above had it" and don't ride the copy (they'd shadow
      # this component's own defaults).
      def inherited_bag
        el = arbre_context.current_arbre_element
        while el
          return el.params.to_h.compact if el.is_a?(Weft::DSL::Params) && el.params

          el = el.parent
        end
        {}
      end

      # The wire door's default wins for dual keys — its meta always carries
      # one, and the wire door sits above the hand-off's fallback in the stack.
      def default_for(key)
        wire_meta = self.class.params[key]
        return wire_meta[:default] if wire_meta

        self.class.received_params[key][:default]
      end

      # A hand-off is required when `receives` is its only door and no
      # default was declared — nothing else can satisfy the presumption.
      def required_hand_off?(key)
        meta = self.class.received_params[key]
        meta && !meta.key?(:default) && !self.class.params.key?(key)
      end

      def raise_not_received!(key)
        raise Weft::NotReceived,
              "#{self.class.name} expects to receive #{key.inspect}: pass it as a builder kwarg " \
              "at the call site, or declare a default: to make it optional"
      end

      # Build-top fallback for the hand-off door in plain Arbre contexts,
      # where interception never runs: pull receives-declared kwargs out of
      # the attributes hash (they're hand-offs, not chrome), overlay them on
      # the bag, and run the validation construction had to defer. Handed
      # nil counts as absence, like everywhere else in the stack.
      def apply_received_fallback(attributes)
        keys = self.class.received_params.keys & attributes.keys
        handed = keys.to_h { |k| [k, attributes.delete(k)] }
        bag = @params.to_h.merge(handed.compact)
        validate_hand_offs!(bag)
        @params = Weft::Params.new(bag)
      end

      # A builder kwarg naming a declared param renders as an HTML attribute
      # only (params arrive from the wire, not the call site). Warn once per
      # (class, key): param names legitimately collide with HTML attribute
      # names (height, title, size, ...), so a standing collision shouldn't
      # spam every render. Set#add? races just double-warn; harmless.
      def warn_declared_chrome_collisions(attributes)
        attributes.each_key do |key|
          next unless self.class.params.key?(key)
          next unless Weft::DSL::Params.warned_collisions.add?([self.class, key])

          Weft.logger.warn(
            "#{self.class.name}: builder kwarg #{key.inspect} matches a declared param and " \
            "renders as an HTML attribute only (params arrive from the wire, not the call site)"
          )
        end
      end
    end
  end
end
