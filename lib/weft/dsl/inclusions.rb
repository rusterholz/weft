# frozen_string_literal: true

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
        # Declare that another component should be OOB-swapped alongside
        # this component's action responses and SSE pushes.
        #
        #   includes OrderHeader                          # pass-through params
        #   includes OrderHeader, on: :advance            # only on :advance action
        #   includes OrderHeader do |params|              # explicit param mapping
        #     { order_id: params.order_id, compact: true }
        #   end
        #
        # Without a block, the included component resolves from the same
        # request params as the primary component. With a block, the block
        # receives the primary component's resolved params and returns wire
        # params for the included component's Resolver.
        def includes(component_class, on: nil, &block)
          own_inclusions << { component_class: component_class, on: on, block: block }
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

        def own_inclusions
          @own_inclusions ||= []
        end
      end
    end
  end
end
