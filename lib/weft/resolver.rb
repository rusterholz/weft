# frozen_string_literal: true

require "bigdecimal/util"

module Weft
  # Projects a wire params hash (string or symbol keys) onto a component
  # class's declared schema, coercing values with declared types.
  # Components self-resolve at build time (see DSL::Params); the Router
  # also calls this directly for error-path bookkeeping. Future home of
  # the reification step (wire primitives → rich objects).
  class Resolver
    # The declarable wire types, each self-describing: how to coerce a
    # present wire value (permissive Ruby — never raises on malformed
    # input), and the classes a declared default may already be an
    # instance of (declaration-side validation lives in DSL::Params).
    # Self-description is the seam a future registration API extends.
    TYPES = {
      string: { coerce: :to_s.to_proc, classes: [String] },
      integer: { coerce: :to_i.to_proc, classes: [Integer] },
      float: { coerce: :to_f.to_proc, classes: [Float] },
      boolean: { coerce: ->(v) { [true, "true", "1"].include?(v) },
                 classes: [TrueClass, FalseClass] },
      decimal: { coerce: :to_d.to_proc, classes: [BigDecimal] }
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

      # A declared type: coerces via its TYPES entry; untyped params accept
      # any value as-is.
      def coerce(value, type)
        entry = TYPES[type]
        entry ? entry[:coerce].call(value) : value
      end
    end
  end
end
