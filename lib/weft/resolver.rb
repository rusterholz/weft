# frozen_string_literal: true

require "bigdecimal/util"

module Weft
  # Projects a wire params hash (string or symbol keys) onto a component
  # class's declared schema, coercing values with declared types.
  # Components self-resolve at build time (see DSL::Params); the Router
  # also calls this directly for error-path bookkeeping. Future home of
  # the reification step (wire primitives → rich objects).
  class Resolver
    # The declarable wire types, each mapped to the classes a declared
    # default may already be an instance of (declaration-side validation
    # lives in DSL::Params; the coercions live below).
    TYPES = {
      string: [String],
      integer: [Integer],
      float: [Float],
      boolean: [TrueClass, FalseClass],
      decimal: [BigDecimal]
    }.freeze

    class << self
      def resolve(component_class, params)
        component_class.params.each_with_object({}) do |(name, meta), result|
          raw = fetch_raw(params, name)
          result[name] = raw.nil? ? meta[:default] : coerce(raw, meta[:type])
        end
      end

      # Coerce only the keys actually present on the wire — no default fill.
      # The construction-time source stack uses this to tell wire-satisfied
      # keys apart from keys that fall through to lower sources.
      def resolve_present(component_class, params)
        component_class.params.each_with_object({}) do |(name, meta), result|
          raw = fetch_raw(params, name)
          result[name] = coerce(raw, meta[:type]) unless raw.nil?
        end
      end

      private

      # Try both key shapes without `||` — a literal false must read as present.
      def fetch_raw(params, name)
        key = name.to_s
        key = name unless params.key?(key)
        params[key]
      end

      # A declared type: coerces the wire's string; untyped params accept any
      # value as-is. Coercion is permissive Ruby (to_i/to_f/to_d/to_s), never
      # raising on malformed wire input.
      def coerce(value, type)
        case type
        when :string then value.to_s
        when :integer then value.to_i
        when :float then value.to_f
        when :decimal then value.to_d
        when :boolean then coerce_boolean(value)
        else value
        end
      end

      def coerce_boolean(value) # rubocop:disable Naming/PredicateMethod
        case value
        when true, "true", "1" then true
        else false
        end
      end
    end
  end
end
