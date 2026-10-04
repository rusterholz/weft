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
    # The slot register records the DOM id each root claims, so two roots in
    # one delivery (an action's primary and a companion, say) can't both land
    # on one element. A root whose build raises gives its slot back, and its
    # recovery, rendering in the same frame, fills that slot in its place.
    class EventFrame
      attr_reader :universe, :slots

      def initialize(universe)
        @universe = universe.frozen? ? universe : universe.dup.freeze
        @slots = Set.new
      end
    end
  end
end
