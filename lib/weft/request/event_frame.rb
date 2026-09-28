# frozen_string_literal: true

module Weft
  class Request
    # @api private
    # One delivered swap-set: an ordinary response, or a single SSE event on a
    # stream. Everything that is one-per-delivery lives here, read directly by
    # every root the delivery renders rather than threaded to each of them.
    #
    # The universe is everything the client sent, undeclared keys included; each
    # component projects it through its own declarations. It is frozen because
    # every root in the delivery shares the one object.
    #
    # The slot register exists only on deliveries whose roots compete for DOM
    # ids: an action response and its companions, or one push. A render that
    # stands in for a root that already claimed its slot (a recovery) is built
    # in an unarbitrated frame, so it inherits the claim rather than contesting it.
    class EventFrame
      attr_reader :universe, :slots

      def initialize(universe, arbitrated: false)
        @universe = universe.frozen? ? universe : universe.dup.freeze
        @slots = Set.new if arbitrated
      end
    end
  end
end
