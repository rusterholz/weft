# frozen_string_literal: true

require "weft/error"

module Weft
  module DSL
    # Mixin for classes that declare OOB-swapped sibling components.
    # Included into Weft::Component.
    #
    # See Weft::Component#includes for the DSL surface.
    module Inclusions
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Contexts a `when:` filter may name. Only :transferred ships today;
        # the vocabulary grows deliberately.
        WHEN_VALUES = %i[transferred].freeze

        # Declare that another component should be OOB-swapped alongside
        # this component's responses.
        #
        #   includes OrderHeader                          # every response
        #   includes OrderHeader, on: :advance            # own action(s) only
        #   includes OrderHeader, on: %i[advance retreat]
        #   includes OrderHeader, when: :transferred      # transfer arrivals only
        #   includes OrderHeader, on: :save, when: :transferred   # union: either
        #   includes OrderHeader do |params|              # companion delta
        #     { order_id: params.order_id, compact: true }
        #   end
        #
        # Unfiltered inclusions ride every response this component renders in:
        # its own actions, SSE pushes, and transfer arrivals. Filters
        # enumerate contexts — `on:` names this component's OWN actions
        # (never a transferring component's), `when: :transferred` fires when
        # this component renders as a transfer target; declaring both is a
        # union. The block's return is a DELTA overlaid on the request for
        # this companion alone; blockless is exactly an empty delta.
        #
        # (`when` rides **options because it's a Ruby reserved word — call
        # sites are unaffected, only this signature is.)
        def includes(component_class, on: nil, **options, &block)
          when_filter = options.delete(:when)
          raise ArgumentError, "unknown keywords: #{options.keys.inspect}" unless options.empty?

          own_inclusions << { component_class: component_class,
                              on: on.nil? ? nil : Array(on),
                              when: validated_when(when_filter),
                              block: block }
        end

        # All declared inclusions (own + inherited).
        def inclusions
          if superclass.respond_to?(:inclusions)
            superclass.inclusions + own_inclusions
          else
            own_inclusions.dup
          end
        end

        private

        def validated_when(value)
          return nil if value.nil?

          contexts = Array(value)
          unknown = contexts - WHEN_VALUES
          unless unknown.empty?
            raise Weft::InvalidDefinition,
                  "includes when: #{unknown.map(&:inspect).join(', ')} names no known context — " \
                  "recognized: #{WHEN_VALUES.map(&:inspect).join(', ')}"
          end

          contexts
        end

        def own_inclusions
          @own_inclusions ||= []
        end
      end
    end
  end
end
