# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

require "weft/addressing"
require "weft/dsl/sandbox"
require "weft/params"
require "weft/error"
require "weft/resolver"

module Weft
  module DSL
    # Mixin for classes that declare which of their params compose their
    # identity, and the derivation of the DOM id those declarations drive.
    # Included into Weft::Component.
    #
    # Declaration and derivation live together because neither is legible
    # without the other: what `identifies_by` means is exactly what the id
    # composer does with it. The stem both the DOM id and the route path are
    # built from belongs to {Weft::Addressing}, which owns addressing itself.
    #
    # See Weft::Component#identifies_by for the DSL surface.
    module Identity
      # Value classes an identifying param may hold. An allowlist: arrays,
      # hashes, and rich objects stringify to selector-hostile junk, and an id
      # derived from one could never be reconstructed from the wire. NilClass
      # belongs here — a record that isn't saved yet has a legitimately absent
      # key, which is a value, not a category error.
      SCALAR_ID_CLASSES = [String, Symbol, Numeric, TrueClass, FalseClass, NilClass].freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      # Warn-once registry for identifying params rendering blank, keyed by
      # [component class, param name].
      def self.warned_blank_identifiers
        @warned_blank_identifiers ||= Set.new
      end

      module ClassMethods
        # Declare which params identify this component — the values its DOM id
        # is built from, in the order they appear in the id.
        #
        #   identifies_by :order_id
        #   identifies_by :order_id, :line_item_id   # => "line-item-row-6-3"
        #
        # Identity is declared at the component, not marked on a param,
        # because the same inherited param identifies one component and not
        # another. A subclass's declaration REPLACES its ancestor's rather
        # than adding to it — otherwise identity would inherit silently and a
        # subclass would be back to having no say over it.
        #
        # A component that declares nothing has no identity of its own: its id
        # is its class name alone. Declare `unique!` to be handed one.
        # A block form takes over the id entirely: it returns the *whole* id,
        # bypassing the stem, the separator and the sanitizer.
        #
        #   identifies_by { |params| "cart-#{params.user_id}" }
        #
        # It runs in {Weft::DSL::Sandbox} against params — not against the
        # instance — so it stays a pure function of the bag and is answerable
        # on the class path, where there is no instance to ask. That is the
        # hole it closes: an imperative `weft_dom_id` override is instance-only,
        # so a component wore one id in a normal render and another in error
        # recovery.
        #
        # Deliberate collisions are allowed — two components sharing an id so
        # one swaps over the other is a reason to reach for this. Malformed ids
        # are not: an id weft cannot target is broken rather than unusual.
        def identifies_by(*names, &block)
          if block && names.any?
            raise Weft::InvalidDefinition,
                  "#{name} declares identifies_by with both param names and a block — the block " \
                  "returns the whole id, so names alongside it have nothing to compose"
          end

          unless block || names.any?
            raise Weft::InvalidDefinition,
                  "#{name} declares identifies_by with nothing to identify by. Name the params " \
                  "that identify it, pass a block returning the id, or declare `unique!`"
          end

          declare_identity!(block || names)
        end

        # Assert that this component needs a slot of its own on the page while
        # having nothing to name it by — a badge some action swaps into, a
        # panel that exists once per page. Weft issues it a token at first
        # render and carries that token on the wire from then on.
        #
        #   unique!
        #
        # Sugar for "declare a mint param and identify by it", and like
        # `identifies_by` it replaces any identity inherited from above.
        #
        # Uniqueness says nothing about routing: this declaration deliberately
        # does not publish an endpoint, since weft adding a param behind your
        # back is no reason for a public GET to appear. A component that wants
        # one declares something that earns it, or says `routable!`.
        def unique!
          declare_identity!(:unique)
        end

        # Whether this component carries a mint (own declaration, else inherited).
        def unique? = own_identity == :unique

        # The block composing this component's id, if it declared one (own,
        # else inherited). The registry's load-time id check reads this: a
        # per-instance id cannot be derived from a class.
        def identity_block = own_identity.is_a?(Proc) ? own_identity : nil

        # The params composing this component's identity (own, else inherited).
        # A `unique!` component has none: its identity is a mint, which is a
        # property of the instance and never a param. See {#unique?}.
        def identifiers
          own_identity.is_a?(Array) ? own_identity : []
        end

        # This class's own identity declaration, else the nearest ancestor's.
        # One slot for both verbs: that is what makes a subclass's declaration
        # replace its parent's wholesale, whichever verb either used.
        def own_identity
          return @own_identity if instance_variable_defined?(:@own_identity)
          return superclass.own_identity if superclass.respond_to?(:own_identity)

          nil
        end

        # Compute the would-be DOM ID for an instance of this class, without
        # instantiating. Single source of truth: the instance method delegates
        # here, and the Router falls back here when it cannot construct an
        # instance to ask.
        #
        # One of three answers, by what the class declared:
        #
        # * an `identifies_by` block composes the whole id itself;
        # * `unique!` wears the stem plus the mint it is holding (+mint+ — the
        #   instance passes its own; the class path has none and issues one);
        # * otherwise the stem, then one slot per declared identifier in
        #   declaration order, or the stem alone if nothing identifies it.
        #
        # +params+ is a bag wherever weft calls it — the one the request has
        # already composed, never a rebuilt one. A plain hash is accepted
        # because this is public and a hash is the obvious thing to hand it; it
        # carries everything the argument form needs, since identifiers must be
        # declared wire params. A block reading a *derived* value off a hash
        # raises rather than answering, which is the honest outcome.
        def weft_dom_id_for(params = {}, mint = nil)
          return block_dom_id(params) if identity_block
          return "#{weft_dom_id_base}-#{mint_segment(mint)}" if unique?
          return weft_dom_id_base if identifiers.empty?

          segments = identifiers.map { |key| identity_segment(params, key) }
          dom_id = "#{weft_dom_id_base}-#{segments.join('-')}"
          warn_blank_identifiers(segments, dom_id)
          dom_id
        end

        # @api private
        # The id a component wears before any identifying value is composed in.
        # Public so the Router can name a fragment whose identity could not be
        # resolved at all, where asking for slots would only invent blank ones.
        def weft_dom_id_base = addressing_stem.underscore.tr("/", "-").tr("_", "-")

        private

        # Two identity declarations in one class body are contradictory
        # assertions, not a precedence puzzle — refuse rather than pick.
        def declare_identity!(declaration)
          if instance_variable_defined?(:@own_identity)
            raise Weft::InvalidDefinition,
                  "#{name} declares its identity twice — `unique!` and `identifies_by` are " \
                  "alternatives, and a class states one of them once"
          end

          @own_identity = declaration
        end

        # One slot of the id: an opaque token if the param declared `digest:`,
        # otherwise the value itself, sanitized. Every declared identifier keeps
        # its slot even when its value is absent — two components differing only
        # in a value they both leave blank would otherwise collide, and since M17
        # a collision drops a companion rather than merely duplicating an id.
        def identity_segment(bag, key)
          value = identity_value(bag, key)
          length = digest_length_for(key)
          return Weft::Addressing.digest(value, length) if length

          sanitize_identifier(value, key)
        end

        # The block owns the id outright, so weft checks only that what comes
        # back is something it can address. A raise inside the block is left to
        # propagate: the convention it overrode would answer with a *different*
        # id, landing the fragment on another component's element, and landing
        # nowhere beats landing somewhere wrong.
        def block_dom_id(bag)
          rendered = Weft::DSL::Sandbox.run(identity_bag(bag), &identity_block).to_s
          return rendered if rendered.match?(Weft::Addressing::DOM_ID_FORMAT)

          raise Weft::InvalidDefinition,
                "#{name}'s identifies_by block returned #{rendered.inspect}, which is not a usable " \
                "DOM id — weft targets fragments with `#id`, so it must start with a letter or " \
                "underscore and carry only letters, digits, underscores and dashes"
        end

        # The block is documented as receiving *params*, so it gets a bag however
        # the caller reached us. Weft's own callers pass the bag the request
        # already composed; this coerces at the boundary for everyone else,
        # since `weft_dom_id_for` is public and a plain hash is the obvious
        # thing to hand it.
        #
        # A hash is genuinely sufficient for the argument form — identifiers
        # must be declared wire params — and genuinely insufficient for a block
        # reading a derived value, which raises NoMethodError off the wrapped
        # bag rather than composing a quietly wrong id.
        def identity_bag(bag)
          return bag if bag.is_a?(Weft::Params)

          Weft::Params.new(bag.to_h.transform_keys(&:to_sym))
        end

        # A mint is checked, never trusted: it reaches this method from the
        # wire in the ordinary case, and from whatever the caller had in hand
        # on the class path, where there is no instance to ask.
        #
        # Anything unusable is reissued rather than rendered. A `unique!`
        # component with no token would otherwise render blank and collide with
        # every other such instance — landing somewhere wrong, where a fresh
        # token lands nowhere.
        def mint_segment(value)
          Weft::Addressing.mint?(value) ? value.to_s : Weft::Addressing.mint
        end

        # Values render into an alphabet holding no dash, so the separator marks a
        # boundary and nothing else: a doubled separator can only mean an empty
        # slot. A uuid-typed value is the deliberate exception — it keeps its
        # dashes, which is safe only because its width is fixed, so its boundaries
        # are known without the separator having to mark them.
        def sanitize_identifier(value, key)
          return "" if value.nil?

          rendered = value.to_s
          return rendered.downcase if uuid_identifier?(key, rendered)

          rendered.parameterize.tr("-", "_")
        end

        # Declared width for a digested param, or nil when the param renders its
        # value. `digest: true` defers to the gem-wide width so one setting can
        # move every declaration that didn't ask for something specific.
        def digest_length_for(key)
          declared = params.dig(key, :digest)
          return nil unless declared

          declared == true ? Weft.configuration.digest_length : declared
        end

        # An empty slot is the collision-capable state: every instance whose value
        # for that key is blank — absent, nil, or sanitized away to nothing —
        # lands on this same id, and since M17 a collision drops a companion
        # rather than merely duplicating an id. Digested slots are never empty,
        # so this speaks only to params still rendering their values.
        #
        # Warn once per class and key: a hundred-row table would otherwise say
        # the same thing a hundred times.
        def warn_blank_identifiers(segments, dom_id)
          identifiers.zip(segments).each do |key, segment|
            next unless segment.empty?
            next unless Identity.warned_blank_identifiers.add?([self, key])

            Weft.logger.warn(
              "#{name} identifies by #{key.inspect}, which rendered blank, so every instance with a " \
              "blank #{key.inspect} resolves to DOM id #{dom_id.inspect}. An out-of-band swap is " \
              "addressed by DOM id, so only one such fragment can land — declare " \
              "`param #{key.inspect}, digest: true` to give blank values slots of their own."
            )
          end
        end

        def uuid_identifier?(key, value) = params.dig(key, :type) == :uuid && Weft::Resolver.uuid?(value)

        # Wire hashes arrive string-keyed, assembled bags symbol-keyed; identity
        # reads the same value either way.
        def identity_value(bag, key)
          return nil unless bag.respond_to?(:key?)

          bag.key?(key) ? bag[key] : bag[key.to_s]
        end
      end
    end
  end
end
