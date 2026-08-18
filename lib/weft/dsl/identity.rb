# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

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
        def identifies_by(*names)
          @own_identifiers = names
        end

        # The params composing this component's identity (own, else inherited).
        def identifiers
          return @own_identifiers if instance_variable_defined?(:@own_identifiers)
          return superclass.identifiers if superclass.respond_to?(:identifiers)

          []
        end

        # Compute the would-be DOM ID for an instance of this class from a params
        # bag, without instantiating. Single source of truth; the instance method
        # delegates, and the Router falls back here when it cannot construct an
        # instance to ask.
        #
        # The id is the class stem followed by one slot per declared identifier,
        # in declaration order. A component that identifies by nothing wears its
        # stem alone.
        def weft_dom_id_for(params = {})
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

        # One slot of the id: an opaque token if the param declared `digest:`,
        # otherwise the value itself, sanitized. Every declared identifier keeps
        # its slot even when its value is absent — two components differing only
        # in a value they both leave blank would otherwise collide, and since M17
        # a collision drops a companion rather than merely duplicating an id.
        def identity_segment(bag, key)
          value = identity_value(bag, key)
          length = digest_length_for(key)
          return digest(value, length) if length

          sanitize_identifier(value, key)
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
