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
        # Declare an event this component announces on its action responses.
        # Sets the HX-Trigger response header.
        #
        #   triggers "order-updated"                     # every action
        #   triggers "order-updated", on: :advance       # that action only
        #   triggers "moved", on: %i[advance retreat]
        #
        # `on:` maps the event to the actions it belongs to. Without it an
        # event is welded to every action the component has, which is rarely
        # what a component with more than one action means.
        #
        # There is deliberately no `when:` counterpart: HX-Trigger announces
        # what a callable did, so a render-context filter has nothing to say
        # about it.
        def triggers(event_name, on: nil)
          own_triggers << { event: event_name.to_s, on: on.nil? ? nil : Array(on) }
        end

        # All declared trigger entries (own + inherited), ancestry first.
        def trigger_declarations
          if superclass.respond_to?(:trigger_declarations)
            superclass.trigger_declarations + own_triggers
          else
            own_triggers.dup
          end
        end

        # The event names that fire for one action. Unfiltered declarations
        # fire on every action, including the nameless one; a subclass can
        # therefore widen an inherited filter by redeclaring the event
        # unfiltered, and duplicates collapse.
        def trigger_events(action_name = nil)
          trigger_declarations.
            select { |trigger| trigger[:on].nil? || trigger[:on].include?(action_name) }.
            map { |trigger| trigger[:event] }.uniq
        end

        private

        def own_triggers
          @own_triggers ||= []
        end
      end
    end
  end
end
