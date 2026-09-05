# frozen_string_literal: true

require "weft/error"
require "weft/addressing"
require "weft/params/assembly"

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
        # Declare a wire param. `default:` fills the key when no source
        # supplies it; `type:` coerces the wire's string into the declared
        # type (see Resolver::TYPES). The two are orthogonal — an untyped
        # param accepts any value uncoerced — but a non-nil default must
        # already be an instance of the declared type.
        # `digest:` renders this param's slot of the DOM id as an opaque
        # token instead of the value itself — reach for it when blank is a
        # legitimate value, or when two distinct values would sanitize to the
        # same string. `digest: 12` widens the token past the gem-wide
        # {Weft::Configuration#digest_length}.
        # `strict:` decides what happens when the wire sends something the
        # declared type cannot represent: refuse it, or coerce anyway. Left
        # unsaid it follows {Weft::Configuration#strict_params}, so the three
        # states are true, false, and "whatever the app says".
        # `required:` is the orthogonal question — `strict:` refuses a malformed
        # value, `required:` refuses an absent one — and pairs with `default:`
        # only as a contradiction, since a default *is* the answer to absence.
        #   param :page, type: :integer
        #   param :status, default: "active", type: :string
        #   param :customer_name, digest: true
        #   param :order_id, type: :uuid, required: true
        def param(name, default: nil, type: nil, digest: false, strict: nil, required: false)
          options = { type: type, digest: digest, strict: strict, required: required }
          validate_param!(name, default, options)
          own_params[name] = param_meta(default, options)
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
        # `type:` and `digest:` say the same thing here as on `param`, but weft
        # can do less about them: a hand-off is already a Ruby object, so there
        # is nothing to coerce. They are declarations weft consults where it
        # consults them — composing a DOM id — not assertions checked on read.
        #
        # The signature is explicit rather than **options because it used to
        # swallow whatever it did not recognise: `receives :x, type: :uuid` was
        # accepted and silently ignored. An unknown keyword now raises, as it
        # already does on `param` and `derives`.
        def receives(name, type: nil, digest: false, **options)
          validate_received!(name, type, digest, options)
          meta = {}
          meta[:default] = options[:default] if options.key?(:default)
          meta[:type] = type unless type.nil?
          meta[:digest] = digest if digest
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
        # Takes `type:` and `digest:` for the same reason `receives` does: a
        # derived value can be the one a component is identified by — a record
        # handed over cannot compose a DOM id, so the row derives the scalar
        # that names it — and that scalar needs to say it is a uuid.
        # `contextual: true` makes the value a function of where it is read
        # rather than one this class owns: every branch inheriting it gets its
        # own unforced copy, so the block answers for the reading bag. It runs
        # more than once by design — even when nothing it reads has changed —
        # so nothing expensive, inconsistent between runs, or side-effecting
        # belongs in one.
        #
        # `override: true` claims the key against an ancestor that also
        # supplies it, for this component and everything it contains. Without
        # it a derivation is a fallback: declare it so you work standalone, and
        # an ancestor's value wins when you are nested. It lifts the derivation
        # above the inherited value only — a wire value and a verb block's
        # overlay still outrank it.
        #
        # `contextual` implies `override`, because a contextual derivation that
        # yielded to an ancestor could never run, and a declaration that
        # silently does nothing is worse than one that is refused.
        def derives(name, type: nil, digest: false, contextual: false, override: contextual, &block)
          unless block
            raise Weft::InvalidDefinition,
                  "derives #{name.inspect} requires a block — the derivation is the declaration"
          end

          refuse_yielding_contextual!(name, contextual, override)
          validate_type!(name, type, nil) unless type.nil?
          validate_digest!(name, digest) if digest
          refuse_conflicting_type!(name, type)
          own_derived_params[name] = derivation_meta(block, type, digest, contextual, override)
        end

        # Only what was actually declared lands in the meta, so a plain
        # derivation stays a two-key hash and the modes read as present-or-not
        # rather than as a pair of falses.
        def derivation_meta(block, type, digest, contextual, override)
          meta = { block: block, source_location: block.source_location }
          meta[:type] = type unless type.nil?
          meta[:digest] = digest if digest
          meta[:contextual] = contextual if contextual
          meta[:override] = override if override
          meta
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

        # Every key this class declares, whichever door it came through —
        # what a bag assembled for this class will hold entries for.
        def declared_keys
          params.keys | received_params.keys | derived_params.keys
        end

        # The declared wire type for a key, whichever door declared it, or nil.
        def declared_type(key) = declared_facet(key, :type)

        # The declared digest width for a key — true for the gem-wide default,
        # an integer for a specific width — whichever door declared it, or nil.
        def declared_digest(key) = declared_facet(key, :digest)

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

        # One key's declarations may be spread across doors — a `param` for the
        # wire shape, a `derives` that computes it — so a consumer that reached
        # into one door's table would answer differently depending on which door
        # happened to declare the key. Asking here instead is what lets identity
        # render a uuid the same way whether it arrived over the wire, from a
        # caller, or from a derivation.
        #
        # Wire first, mirroring Assembly#default_for: its meta is the one a URL
        # round-trips through, so for a dual key it is the one that has to hold.
        def declared_facet(key, facet)
          [params, received_params, derived_params].each do |table|
            meta = table[key]
            return meta[facet] if meta&.key?(facet)
          end
          nil
        end

        # `default:` is the one option that rides the rest hash, because only
        # `options.key?(:default)` can tell "declared nil" from "not declared" —
        # and that distinction is what makes a hand-off required or optional.
        # One key is one value, so two doors naming different types for it are
        # contradictory assertions rather than a precedence puzzle — refuse
        # rather than pick, exactly as `declare_identity!` does for the identity
        # verbs. Unlike `default:`, where two doors holding different fallbacks
        # is meaningful, since they answer for different sources.
        #
        # Reads what THIS class body declared, never the inherited merge: a
        # subclass retyping its parent's key is an override, like redeclaring a
        # derivation block. And only two *stated* types conflict — a door that
        # says nothing simply defers to the one that did.
        # A contextual derivation that yielded to an ancestor's value could
        # never run at all, so the pair is refused at the declaration rather
        # than accepted and quietly ignored.
        def refuse_yielding_contextual!(name, contextual, override)
          return unless contextual && !override

          raise Weft::InvalidDefinition,
                "#{self.name} declares #{name.inspect} as contextual but not overriding — a " \
                "contextual derivation is computed where it is read, so yielding to an " \
                "ancestor's value would leave it never running. Drop override: false, or drop " \
                "contextual: true to take the ancestor's value when you are nested"
        end

        def refuse_conflicting_type!(name, type)
          return if type.nil?

          [own_params, own_received_params, own_derived_params].each do |table|
            declared = table[name]&.[](:type)
            next if declared.nil? || declared == type

            raise Weft::InvalidDefinition,
                  "#{self.name} declares #{name.inspect} as both #{declared.inspect} and " \
                  "#{type.inspect} — one key holds one value, so name the type once or use " \
                  "two keys"
          end
        end

        def validate_received!(name, type, digest, options)
          unknown = options.keys - [:default]
          unless unknown.empty?
            raise ArgumentError,
                  "receives #{name.inspect} got unknown keyword#{'s' if unknown.size > 1} " \
                  "#{unknown.map(&:inspect).join(', ')}"
          end

          validate_type!(name, type, nil) unless type.nil?
          validate_digest!(name, digest) if digest
          refuse_conflicting_type!(name, type)
        end

        def validate_param!(name, default, options)
          validate_type!(name, options[:type], default) unless options[:type].nil?
          validate_digest!(name, options[:digest]) if options[:digest]
          validate_required!(name, default) if options[:required]
          refuse_conflicting_type!(name, options[:type])
        end

        # Only what was actually said: an absent `strict:` has to stay absent
        # so it can defer to the gem-wide setting, which a stored `false` would
        # override. `default:` is the exception — every param carries one,
        # since nil is a legitimate answer to "what if nobody supplies this".
        def param_meta(default, options)
          meta = { default: default }
          meta[:type] = options[:type] unless options[:type].nil?
          meta[:digest] = options[:digest] if options[:digest]
          meta[:strict] = options[:strict] unless options[:strict].nil?
          meta[:required] = true if options[:required]
          meta
        end

        def validate_type!(name, type, default)
          entry = Weft::Types.lookup(type)
          unless entry
            raise Weft::InvalidDefinition,
                  "param #{name.inspect} declares unknown type #{type.inspect} — declarable " \
                  "types are #{Weft::Types.registered.map(&:inspect).join(', ')}"
          end
          return if default.nil? || entry.permits_default?(default)

          raise Weft::InvalidDefinition,
                "param #{name.inspect} declares type #{type.inspect} but its default " \
                "#{default.inspect} is #{default.class} — make them agree, or drop one"
        end

        # A declared default answers absence; `required: true` refuses it. Two
        # answers to one question, so refuse the pair rather than rank them.
        # `default: nil` is not a declared default — it is the signature's own
        # value for "none given".
        def validate_required!(name, default)
          return if default.nil?

          raise Weft::InvalidDefinition,
                "param #{name.inspect} is required but declares default #{default.inspect} — a " \
                "default is what makes a param optional. Drop one of the two"
        end

        def validate_digest!(name, digest)
          return if digest == true
          return if digest.is_a?(Integer) && digest.between?(1, Weft::Addressing::MAX_DIGEST_LENGTH)

          raise Weft::InvalidDefinition,
                "param #{name.inspect} declares digest #{digest.inspect} — pass true for the " \
                "gem-wide length, or an integer between 1 and #{Weft::Addressing::MAX_DIGEST_LENGTH}"
        end

        def own_params = @own_params ||= {}
        def own_received_params = @own_received_params ||= {}
        def own_derived_params = @own_derived_params ||= {}
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
      # value > inherited bag value > declared default. Staging happens at
      # interception, which only a Weft::Context performs — so a component
      # built anywhere else has no hand-off door at all, and a declared
      # `receives` reports as unsatisfied rather than going unchecked.
      def assembled_params
        resolve_bag(received: arbre_context.take_received!(self.class) || {})
      end

      # Uses the Assembly object rather than `.call` because construction needs
      # both halves of what it produced: the bag, and what the wire sent that
      # no declared type could accept.
      def resolve_bag(received:)
        assembly = Weft::Params::Assembly.new(self.class, wire_source,
                                              hand_offs: received,
                                              overlays: context_overlays,
                                              branched_from: inherited_bag)
        bag = assembly.bag
        refuse_violations!(assembly.violations)
        validate_required!(bag)
        validate_hand_offs!(bag)
        bag
      end

      def refuse_violations!(violations)
        return if violations.empty?

        raise Weft::InvalidParamValue.new(
          "#{self.class.name} was sent #{violations.map { |v| violation_phrase(v) }.join(', ')}",
          violations
        )
      end

      # The type says what it wanted, in words. "declares type :uuid" would tell
      # a reader only what they already wrote.
      def violation_phrase(violation)
        "#{violation.raw.inspect} for #{violation.key.inspect}, which " \
          "#{Weft::Types.lookup(violation.type).refusal}"
      end

      # `required:` is the absence door; the malformation door has already had
      # its say above, so a value that arrived badly is reported as malformed
      # rather than counted twice as missing.
      def validate_required!(bag)
        self.class.params.each do |key, meta|
          next unless meta[:required] && bag[key].nil?

          raise Weft::MissingParam,
                "#{self.class.name} requires #{key.inspect}, and no source supplied it — the " \
                "request did not send it and it declares no default"
        end
      end

      def context_overlays
        arbre_context.overlays
      end

      # Checks required_hand_off? before reading the key: a required hand-off
      # is receives-only (never thunked), so the read can't force anything —
      # and dual keys short-circuit without touching their lazy derivation.
      def validate_hand_offs!(bag)
        self.class.received_params.each_key do |key|
          raise_not_received!(key) if required_hand_off?(key) && bag[key].nil?
        end
      end

      def wire_source
        arbre_context.wire_params
      end

      # Branch a copy of the nearest tree-ancestor's bag — the in-page
      # parent-child axis: a component sees everything above it, nothing
      # beside it. At construction the current element IS the future parent,
      # so the walk works before the tree links this instance in. The copy is
      # thunk-preserving (never forces the ancestor's lazy entries) and
      # nil-dropping. A root with no tree
      # ancestor falls back to the context's branch bag — how an OOB
      # companion inherits from the primary it rides alongside, and how the
      # state a request has already composed reaches the component it renders.
      def inherited_bag
        el = arbre_context.current_arbre_element
        while el
          return el.params if el.is_a?(Weft::DSL::Params) && el.params

          el = el.parent
        end
        arbre_context.branch_bag
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
