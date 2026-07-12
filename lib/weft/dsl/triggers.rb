# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare HX-Trigger response events.
    # Included into Weft::Component.
    #
    # See Weft::Component#triggers for the DSL surface.
    module Triggers
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare an event to trigger on all action responses for this component.
        # Sets the HX-Trigger response header.
        #
        #   triggers "order-updated"
        def triggers(event_name)
          own_triggers << event_name.to_s
        end

        # All declared trigger events (own + inherited).
        def trigger_events
          if superclass.respond_to?(:trigger_events)
            superclass.trigger_events | own_triggers
          else
            own_triggers.dup
          end
        end

        private

        def own_triggers
          @own_triggers ||= []
        end
      end
    end
  end
end
