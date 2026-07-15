# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare wire-state params.
    # Provides the `param` class DSL and `params` instance reader.
    # Used by Component (for partial route params) and Page (for page route params).
    module Params
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare a wire param. Accepts optional default: and type: kwargs.
        #   param :status, default: "active", type: :string
        def param(name, default: nil, **options)
          meta = { default: default }
          meta[:type] = options[:type] if options.key?(:type)
          own_params[name] = meta
        end

        # Returns all declared params (own + inherited), preserving declaration order.
        def params
          if superclass.respond_to?(:params)
            superclass.params.merge(own_params)
          else
            own_params.dup
          end
        end

        private

        def own_params
          @own_params ||= {}
        end
      end

      # Instance access to resolved wire param values.
      # Returns a Weft::Params object with method-style and hash access.
      attr_reader :params
    end
  end
end
