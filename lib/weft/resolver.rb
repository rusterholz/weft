# frozen_string_literal: true

module Weft
  # Maps request params (string keys/values) to component attribute hashes.
  # Coerces types based on attribute defaults. Future home of the reification
  # step (wire primitives → rich objects).
  class Resolver
    def resolve(component_class, params)
      component_class.attributes.each_with_object({}) do |(name, meta), result|
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
