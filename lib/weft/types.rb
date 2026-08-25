# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "bigdecimal/util"

module Weft
  # Registry of the wire types a `param` may declare. Each entry is
  # self-describing across every facet weft asks a type about, so adding one is
  # a single registration rather than a new branch in each consumer — the shape
  # `Weft::Presets` already proved for interaction presets.
  #
  # Weft's own six are registered at the bottom of this file, through the same
  # door an adopter's `:duration` will use. Public registration itself arrives
  # with the rest of the `register_*` surface; until then the door is here and
  # dogfooded rather than hypothetical.
  module Types
    # What weft asks a type, in the order a wire value meets them:
    #
    # * +coerce+        wire value → Ruby value, leniently. Never raises. For
    #                   the types ActiveModel defines, this IS ActiveModel's
    #                   answer, exactly (see the parity spec).
    # * +valid+         may this value be represented at all? Consulted only
    #                   under `strict:`; a type without one constrains nothing.
    # * +strict_coerce+ optional. Only for a type whose two modes disagree
    #                   about a value rather than merely about refusing it.
    # * +refusal+       what this type wanted, in words, for the error message.
    # * +classes+       what a declared `default:` may already be.
    # * +dom_segment+   optional. How a value of this type renders into a DOM
    #                   id, when the type has an opinion; nil defers to weft's
    #                   ordinary sanitisation.
    Type = Struct.new(:name, :coerce, :valid, :strict_coerce, :refusal, :classes, :dom_segment,
                      keyword_init: true) do
      def cast(value, strict:) = ((strict && strict_coerce) || coerce).call(value)
      def represents?(value) = valid.nil? || valid.call(value)
      def permits_default?(value) = classes.any? { |klass| value.is_a?(klass) }
      def id_segment(value) = dom_segment&.call(value)
    end

    class << self
      def register(name, **facets)
        registry[name] = Type.new(name: name, **facets)
      end

      def lookup(name) = registry[name]
      def registered = registry.keys

      private

      def registry
        @registry ||= {}
      end
    end

    # A blank wire string is a cleared field, not a value — the only spelling of
    # absence a query string has. Returning nil hands the key back to the source
    # stack, which already knows what absence means. The rule is per-type
    # because ActiveModel's is: numerics take `presence` (whitespace counts),
    # booleans test for exactly "", and strings keep whatever arrived, since a
    # cleared text field is a legitimately empty string.
    BLANK = ->(v) { v.is_a?(::String) && v.blank? }
    EMPTY = ->(v) { v == "" }

    # What the numeric coercions can read *faithfully*. Deliberately narrower
    # than Kernel#Integer and Kernel#Float, which accept forms the coercions
    # then disagree with: `Integer("0x1f")` is 31 where `"0x1f".to_i` is 0, so
    # validating with one and coercing with the other would bless a value that
    # renders as garbage — the exact fabrication strictness exists to refuse.
    # `"1.5"` fails INTEGER_FORMAT on the same principle: `to_i` would silently
    # drop the fraction.
    INTEGER_FORMAT = /\A[+-]?\d+\z/
    DECIMAL_FORMAT = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/

    # Canonical 8-4-4-4-12. Identity renders a uuid-typed value with its dashes
    # intact, which is safe *because the shape is fixed* — a segment of known
    # width cannot blur the boundary with the one beside it.
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    # Blank is absence, not malformation — the source stack answers it. A
    # non-String arrived from somewhere other than a query string and carries
    # its own type already.
    NUMERIC_VALID = lambda do |value, pattern|
      !value.is_a?(::String) || value.blank? || value.strip.match?(pattern)
    end

    # Booleans are the one type whose two modes disagree about a value rather
    # than merely about whether to refuse it. Strict reads a closed vocabulary
    # in both directions; lenient is ActiveModel's, where the false set is
    # closed and *everything else is true* — so "no" is false under strict and
    # true under lenient. That inversion is deliberate: lenient mode's job is to
    # be exactly what a Rails developer already expects.
    BOOLEAN_TRUE = %w[true 1 t on yes y].freeze
    BOOLEAN_FALSE = %w[false 0 f off no n].freeze
    # ActiveModel::Type::Boolean::FALSE_VALUES, less the symbol entries a wire
    # value can never be, and less "" which is handled as absence above.
    LENIENT_FALSE = ["0", "f", "F", "false", "FALSE", "off", "OFF", false, 0].freeze

    BOOLEAN_WORD = ->(value) { value.is_a?(::String) ? value.strip.downcase : value }
  end
end

# Weft's own types, registered through the public door so it is exercised by
# the gem before anyone else relies on it.

# A declared scalar refuses a collection: `?x[]=a` and `?x[k]=v` let a caller
# choose the SHAPE, not merely the value, and `to_s` would render `["a", "b"]`
# into the page. Filtering stops undeclared keys; only this stops a declared one
# arriving as something it never promised to be.
Weft::Types.register :string,
                     coerce: :to_s.to_proc,
                     valid: ->(v) { !v.is_a?(Enumerable) },
                     refusal: "is not a single value",
                     classes: [String]

Weft::Types.register :integer,
                     coerce: ->(v) { v.to_i unless Weft::Types::BLANK.call(v) },
                     valid: ->(v) { Weft::Types::NUMERIC_VALID.call(v, Weft::Types::INTEGER_FORMAT) },
                     refusal: "is not a whole number",
                     classes: [Integer]

Weft::Types.register :float,
                     coerce: ->(v) { v.to_f unless Weft::Types::BLANK.call(v) },
                     valid: ->(v) { Weft::Types::NUMERIC_VALID.call(v, Weft::Types::DECIMAL_FORMAT) },
                     refusal: "is not a number",
                     classes: [Float]

Weft::Types.register :decimal,
                     coerce: ->(v) { v.to_d unless Weft::Types::BLANK.call(v) },
                     valid: ->(v) { Weft::Types::NUMERIC_VALID.call(v, Weft::Types::DECIMAL_FORMAT) },
                     refusal: "is not a number",
                     classes: [BigDecimal]

Weft::Types.register :boolean,
                     coerce: lambda { |v|
                       !Weft::Types::LENIENT_FALSE.include?(v) unless Weft::Types::EMPTY.call(v)
                     },
                     strict_coerce: lambda { |v|
                       word = Weft::Types::BOOLEAN_WORD.call(v)
                       Weft::Types::BOOLEAN_TRUE.include?(word) || v == true unless Weft::Types::BLANK.call(v)
                     },
                     valid: lambda { |v|
                       word = Weft::Types::BOOLEAN_WORD.call(v)
                       [true, false].include?(word) || Weft::Types::BLANK.call(v) ||
                         Weft::Types::BOOLEAN_TRUE.include?(word) || Weft::Types::BOOLEAN_FALSE.include?(word)
                     },
                     refusal: "is not true or false",
                     classes: [TrueClass, FalseClass]

# Downcased because a UUID is case-insensitive: the same record handed back in
# either case must be the same component, not two. Its dom_segment is the whole
# reason that facet exists — a uuid keeps its dashes in a DOM id, where every
# other type's value is sanitised dash-free so the separator marks a boundary
# and nothing else. A fixed width is what makes that safe.
Weft::Types.register :uuid,
                     coerce: ->(v) { v.to_s.downcase unless Weft::Types::BLANK.call(v) },
                     valid: lambda { |v|
                       Weft::Types::BLANK.call(v) || v.to_s.match?(Weft::Types::UUID_FORMAT)
                     },
                     refusal: "is not a uuid",
                     classes: [String],
                     dom_segment: lambda { |v|
                       v.to_s.downcase if v.to_s.match?(Weft::Types::UUID_FORMAT)
                     }
