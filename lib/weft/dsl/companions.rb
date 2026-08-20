# frozen_string_literal: true

require "weft/error"

module Weft
  module DSL
    # Mixin for classes that declare OOB-swapped sibling components.
    # Included into Weft::Component.
    #
    # See Weft::Component#brings for the DSL surface.
    module Companions
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
        #   brings OrderHeader                          # every response
        #   brings OrderHeader, on: :advance            # own action(s) only
        #   brings OrderHeader, on: %i[advance retreat]
        #   brings OrderHeader, when: :transferred      # transfer arrivals only
        #   brings OrderHeader, on: :save, when: :transferred   # union: either
        #   brings OrderHeader do |params|              # companion delta
        #     { order_id: params.order_id, compact: true }
        #   end
        #
        # Unfiltered companions ride every response this component renders in:
        # its own actions, SSE pushes, and transfer arrivals. Filters
        # enumerate contexts — `on:` names this component's OWN actions
        # (never a transferring component's), `when: :transferred` fires when
        # this component renders as a transfer target; declaring both is a
        # union. The block's return is a DELTA overlaid on the request for
        # this companion alone; blockless is exactly an empty delta.
        #
        # (`when` rides **options because it's a Ruby reserved word — call
        # sites are unaffected, only this signature is.)
        def brings(component_class, on: nil, **options, &block)
          when_filter = options.delete(:when)
          raise ArgumentError, "unknown keywords: #{options.keys.inspect}" unless options.empty?

          reject_unique_companion!(component_class)

          site = caller_locations(1, 1).first
          own_companions << { component_class: component_class,
                              on: on.nil? ? nil : Array(on),
                              when: validated_when(when_filter),
                              block: block,
                              source_location: [site.path, site.lineno] }
        end

        # A companion is addressed by DOM id, and a `unique!` component's id
        # comes from a token only that component's own requests carry. Resolved
        # from this host's params, it would mint a fresh one and target an
        # element that isn't on the page — and htmx discards an unmatched
        # out-of-band swap silently, client-side, where nothing can report it.
        #
        # `unique!` buys in-page uniqueness and self-refresh stability; being
        # brought by someone else needs a real identifier.
        def reject_unique_companion!(component_class)
          return unless component_class.respond_to?(:unique?) && component_class.unique?

          raise Weft::InvalidDefinition,
                "#{name} brings #{component_class.name}, which is `unique!` — its id comes from a " \
                "token only its own requests carry, so this companion would address an element " \
                "that is not on the page. Give #{component_class.name} an identifying param instead."
        end

        # All declared companions (own + inherited).
        def companions
          if superclass.respond_to?(:companions)
            superclass.companions + own_companions
          else
            own_companions.dup
          end
        end

        private

        def validated_when(value)
          return nil if value.nil?

          contexts = Array(value)
          unknown = contexts - WHEN_VALUES
          unless unknown.empty?
            raise Weft::InvalidDefinition,
                  "brings when: #{unknown.map(&:inspect).join(', ')} names no known context — " \
                  "recognized: #{WHEN_VALUES.map(&:inspect).join(', ')}"
          end

          contexts
        end

        def own_companions
          @own_companions ||= []
        end
      end
    end
  end
end
