# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare consumed inputs — the doors into `params`.
    # Provides the `param` (wire), `receives` (caller hand-off), and `derives`
    # (lazy server-side derivation) class DSL and the `params` instance reader.
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

        # Declare a lazy server-side derivation: the block runs (at most once
        # per render) when `params.name` is first read, never if it isn't.
        #   derives(:order) { |params| Order.find(params.order_id) }
        # The block is a `(params) -> value` pure function with a void self.
        # Derived values are server-side: never serialized, not
        # routable-making.
        def derives(name, &block)
          unless block
            raise Weft::InvalidDefinition,
                  "derives #{name.inspect} requires a block — the derivation is the declaration"
          end

          own_derived_params[name] = { block: block, source_location: block.source_location }
        end

        # Sugar for statically-known derivations: each pair registers
        # `derives(key) { value }`. This is just `derives` — identical
        # priority, overridability, and laziness; only the value is fixed at
        # declaration. For anything computed per render (queries, clocks),
        # use `derives` — an interpolated value here would freeze at
        # class-load time.
        #   defines label: "Drivers", accent: "available"
        def defines(pairs)
          site = caller_locations(1, 1).first
          pairs.each do |name, value|
            own_derived_params[name] = { block: proc { |_p| value },
                                         source_location: [site.path, site.lineno] }
          end
        end

        # All declared derivations (own + inherited), preserving declaration
        # order. A child redeclaring a parent's key replaces the block, like
        # a method override.
        def derived_params
          if superclass.respond_to?(:derived_params)
            superclass.derived_params.merge(own_derived_params)
          else
            own_derived_params.dup
          end
        end

        private

        def own_params
          @own_params ||= {}
        end

        def own_received_params
          @own_received_params ||= {}
        end

        def own_derived_params
          @own_derived_params ||= {}
        end
      end

      # One-time chrome-collision warnings, keyed [class, key].
      # See #warn_declared_chrome_collisions.
      def self.warned_collisions
        @warned_collisions ||= Set.new
      end

      # One-time divergent-derivation warnings, keyed [class, key].
      # See #warn_shadowed_derivations.
      def self.warned_divergences
        @warned_divergences ||= Set.new
      end

      # Instance access to the resolved bag.
      # Returns a Weft::Params object with method-style and hash access.
      attr_reader :params

      # @api private
      # The bag projected onto this class's own declared wire schema — the
      # only slice that serializes (refresh/stream URLs, DOM ids, hx-vals).
      # Hand-offs and inherited values are server-side and never ride the
      # wire. Per-key reads, NOT to_h: serialization must never materialize
      # non-wire derivations (a thunk on a wire-schema key — the rare
      # param+derives dual — does force here; the refresh contract wins).
      def serializable_params
        return {} unless params

        self.class.params.keys.to_h { |key| [key, params[key]] }
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
        inherited, inherited_provenance = inherited_bag
        bag = inherited.dup
        declared_keys.each { |key| bag[key] = stack_value(key, received, wire, inherited) }
        validate_hand_offs!(bag) if validate
        warn_shadowed_derivations(received, wire, inherited, inherited_provenance)
        Weft::Params.new(bag, bag_provenance(bag, inherited, inherited_provenance))
      end

      def declared_keys
        self.class.params.keys | self.class.received_params.keys | self.class.derived_params.keys
      end

      # The per-key source stack, top wins: hand-off > own wire > inherited >
      # own derivation (registered lazily) > default. nil never wins a level —
      # it means that source didn't have it. A thunk always "produces," so a
      # same-key default is unreachable behind a derives.
      def stack_value(key, received, wire, inherited)
        [received[key], wire[key], inherited[key], derived_thunk(key), default_for(key)].
          find { |v| !v.nil? }
      end

      def derived_thunk(key)
        meta = self.class.derived_params[key]
        Weft::Params::Thunk.new(meta[:block]) if meta
      end

      # source_location per derives-born key still occupying the bag:
      # inherited provenance survives wherever the inherited entry itself
      # survived (forced or not — that's why it isn't recomputed from
      # thunks), plus this class's own registrations.
      def bag_provenance(bag, inherited, inherited_provenance)
        provenance = inherited_provenance.select { |key, _| bag[key].equal?(inherited[key]) }
        self.class.derived_params.each do |key, meta|
          provenance[key] = meta[:source_location] if
            bag[key].is_a?(Weft::Params::Thunk) && !provenance.key?(key)
        end
        provenance
      end

      def validate_hand_offs!(bag)
        self.class.received_params.each_key do |key|
          raise_not_received!(key) if bag[key].nil? && required_hand_off?(key)
        end
      end

      # When an inherited value wins level 3 over this class's own derivation
      # AND was itself derived by a different block, the local derivation is
      # silently dead — surface that once per (class, key). Values inherited
      # through other doors (wire, hand-off) are the stack working as
      # designed; a shared proc (one derivation mixed into many classes) is
      # agreement, not divergence.
      def warn_shadowed_derivations(received, wire, inherited, inherited_provenance)
        self.class.derived_params.each_key do |key|
          next unless received[key].nil? && wire[key].nil? && !inherited[key].nil?

          warn_divergence(key, inherited_provenance[key])
        end
      end

      def warn_divergence(key, upstream)
        meta = self.class.derived_params[key]
        return if upstream.nil? || upstream == meta[:source_location]
        return unless Weft::DSL::Params.warned_divergences.add?([self.class, key])

        Weft.logger.warn(divergence_message(key, meta, upstream))
      end

      def divergence_message(key, meta, upstream)
        "#{self.class.name}: inherited #{key.inspect} (derived at #{upstream.join(':')}) shadows " \
          "this class's own derivation (#{meta[:source_location].join(':')}) — the ancestor's " \
          "value wins. Use distinct keys or share one derivation if that isn't intended."
      end

      def wire_source
        arbre_context.respond_to?(:wire_params) ? arbre_context.wire_params : {}
      end

      # Branch a copy of the nearest tree-ancestor's bag — the in-page
      # parent-child axis: a component sees everything above it, nothing
      # beside it. At construction the current element IS the future parent,
      # so the walk works before the tree links this instance in. Returns
      # [data, provenance]; the copy is thunk-preserving (never forces the
      # ancestor's lazy entries) and nil-dropping.
      def inherited_bag
        el = arbre_context.current_arbre_element
        while el
          return [el.params.branch_data, el.params.provenance] if el.is_a?(Weft::DSL::Params) && el.params

          el = el.parent
        end
        [{}, {}]
      end

      # The wire door's default wins for dual keys — its meta always carries
      # one, and the wire door sits above the hand-off's fallback in the stack.
      def default_for(key)
        wire_meta = self.class.params[key]
        return wire_meta[:default] if wire_meta

        self.class.received_params[key]&.[](:default)
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
