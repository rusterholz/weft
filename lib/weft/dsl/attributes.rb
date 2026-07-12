# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare wire-state attributes.
    # Provides the `attribute` class DSL and `attrs` instance reader.
    # Used by Component (for partial route params) and Page (for page route params).
    module Attributes
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare a wire attribute. Accepts optional default: and type: kwargs.
        #   attribute :status, default: "active", type: :string
        def attribute(name, default: nil, **options)
          meta = { default: default }
          meta[:type] = options[:type] if options.key?(:type)
          own_attributes[name] = meta
        end

        # Returns all declared attributes (own + inherited), preserving declaration order.
        def attributes
          if superclass.respond_to?(:attributes)
            superclass.attributes.merge(own_attributes)
          else
            own_attributes.dup
          end
        end

        private

        def own_attributes
          @own_attributes ||= {}
        end
      end

      # Instance access to resolved wire attribute values.
      # Returns a Weft::Attributes object with method-style and hash access.
      attr_reader :attrs
    end
  end
end
