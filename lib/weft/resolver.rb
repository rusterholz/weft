# frozen_string_literal: true

require "weft/types"

module Weft
  # Projects a wire params hash (string or symbol keys) onto a component
  # class's declared schema, coercing values through {Weft::Types}.
  # Components self-resolve at build time (see DSL::Params); the Router
  # also calls this directly for error-path bookkeeping. Future home of
  # the reification step (wire primitives → rich objects).
  class Resolver
    # One wire value a declared type could not represent. Deliberately three
    # fields and no more: this describes what arrived, never what a domain
    # wants. Anything richer is validation, which is the application's job.
    Violation = Struct.new(:key, :raw, :type)

    # What one pass over a wire hash produced: the keys it could read, and the
    # ones it could not. Both together, because a caller redrawing a form needs
    # the good fields and the bad news in the same breath.
    # (+coerced+ rather than +values+, which Struct already defines.)
    Resolution = Struct.new(:coerced, :violations)

    class << self
      # Project a wire hash onto a class's declared schema. **Never raises** —
      # it reports what it could not represent and leaves the answer to the
      # caller. That is what lets the error path re-read the same malformed
      # hash without raising a second time on top of the failure it is
      # reporting, and it keeps the raise policy in one place instead of
      # scattered through every consumer.
      #
      # +fill_defaults+ decides what an absent key becomes: its declared
      # default, or nothing at all.
      def resolution(component_class, params, fill_defaults: false)
        violations = []
        coerced = {}
        component_class.params.each do |name, meta|
          value = wire_value(params, name, meta, violations)
          value = meta[:default] if value.nil? && fill_defaults
          coerced[name] = value if fill_defaults || !value.nil?
        end
        Resolution.new(coerced, violations)
      end

      # A key whose wire value coerces away to nil reads as absent, not as nil:
      # blank is how a query string spells "nothing here", and the declared
      # default is the answer to nothing.
      def resolve(component_class, params)
        resolution(component_class, params, fill_defaults: true).coerced
      end

      # Coerce only the keys actually present on the wire — no default fill.
      # The construction-time source stack uses this to tell wire-satisfied
      # keys apart from keys that fall through to lower sources, so a key that
      # coerced away is left out rather than laid down as nil.
      def resolve_present(component_class, params)
        resolution(component_class, params).coerced
      end

      private

      # The wire's contribution for one key, or nil where it made none —
      # absent, blank, or unrepresentable, the last of which also lodges a
      # violation on the way past.
      def wire_value(params, name, meta, violations)
        raw = fetch_raw(params, name)
        return nil if raw.nil?

        type = Weft::Types.lookup(meta[:type])
        return raw unless type

        strict = strict?(meta)
        return type.cast(raw, strict: strict) if !strict || type.represents?(raw)

        violations << Violation.new(name, raw, meta[:type])
        nil
      end

      # Three-state on the param — declared true, declared false, or unsaid, in
      # which case the gem-wide setting answers.
      def strict?(meta) = meta.fetch(:strict) { Weft.configuration.strict_params }

      # Try both key shapes without `||` — a literal false must read as present.
      def fetch_raw(params, name)
        key = name.to_s
        key = name unless params.key?(key)
        params[key]
      end
    end
  end
end
