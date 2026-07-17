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

      # One-time chrome-collision warnings, keyed [class, key].
      # See #warn_declared_chrome_collisions.
      def self.warned_collisions
        @warned_collisions ||= Set.new
      end

      # Instance access to resolved wire param values.
      # Returns a Weft::Params object with method-style and hash access.
      attr_reader :params

      private

      # Resolve this class's declared params from the context's wire source.
      # Weft::Context carries one; plain Arbre contexts don't → defaults only.
      def resolved_wire_params
        source = arbre_context.respond_to?(:wire_params) ? arbre_context.wire_params : {}
        Weft::Params.new(Weft::Resolver.resolve(self.class, source))
      end

      # A builder kwarg naming a declared param renders as an HTML attribute
      # only (params arrive from the wire, not the call site). Warn once per
      # (class, key): param names legitimately collide with HTML attribute
      # names (height, title, size, ...), so a standing collision shouldn't
      # spam every render. Set#add? races just double-warn; harmless.
      def warn_declared_chrome_collisions(attributes)
        attributes.each_key do |key|
          next unless self.class.params.key?(key)
          next unless Weft::DSL::Params.warned_collisions.add?([self.class, key])

          Weft.logger.warn(
            "#{self.class.name}: builder kwarg #{key.inspect} matches a declared param and " \
            "renders as an HTML attribute only (params arrive from the wire, not the call site)"
          )
        end
      end
    end
  end
end
