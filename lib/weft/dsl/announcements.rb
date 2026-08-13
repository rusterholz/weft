# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare events their responses announce to the
    # page. Included into Weft::Component.
    #
    # See Weft::Component#announces for the DSL surface.
    module Announcements
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare an event this component announces on its action responses.
        # Sets the HX-Trigger response header.
        #
        #   announces "order-updated"                     # every action
        #   announces "order-updated", on: :advance       # that action only
        #   announces "moved", on: %i[advance retreat]
        #
        # `on:` maps the event to the actions it belongs to. Without it an
        # event is welded to every action the component has, which is rarely
        # what a component with more than one action means.
        #
        # There is deliberately no `when:` counterpart: an announcement
        # reports what a callable did, so a render-context filter has nothing
        # to say about it.
        def announces(event_name, on: nil)
          own_announcements << { event: event_name.to_s, on: on.nil? ? nil : Array(on) }
        end

        # All declared announcements (own + inherited), ancestry first.
        def announcements
          if superclass.respond_to?(:announcements)
            superclass.announcements + own_announcements
          else
            own_announcements.dup
          end
        end

        # The event names that fire for one action. Unfiltered declarations
        # fire on every action, including the nameless one; a subclass can
        # therefore widen an inherited filter by redeclaring the event
        # unfiltered, and duplicates collapse.
        def announced_events(action_name = nil)
          announcements.
            select { |entry| entry[:on].nil? || entry[:on].include?(action_name) }.
            map { |entry| entry[:event] }.uniq
        end

        private

        def own_announcements
          @own_announcements ||= []
        end
      end
    end
  end
end
