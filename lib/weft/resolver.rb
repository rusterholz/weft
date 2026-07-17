# frozen_string_literal: true

module Weft
  # Projects a wire params hash (string or symbol keys) onto a component
  # class's declared schema, coercing types based on param defaults.
  # Components self-resolve at build time (see DSL::Params); the Router
  # also calls this directly for error-path bookkeeping. Future home of
  # the reification step (wire primitives → rich objects).
  class Resolver
    class << self
      def resolve(component_class, params)
        component_class.params.each_with_object({}) do |(name, meta), result|
          raw = params[name.to_s] || params[name]
          result[name] = raw.nil? ? meta[:default] : coerce(raw, meta[:default])
        end
      end

      private

      def coerce(value, default)
        case default
        when Integer then value.to_i
        when Float then value.to_f
        when true, false then coerce_boolean(value)
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
