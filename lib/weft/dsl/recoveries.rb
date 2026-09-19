# frozen_string_literal: true

require "weft/error"

module Weft
  module DSL
    # Mixin for classes that declare recovery edges via `recovers`.
    # Used by both Component (action and partial-render failures) and Page
    # (full-document render failures, routing misses).
    #
    # See Weft::Component#recovers for the DSL surface.
    module Recoveries
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare a recovery edge: how this class handles a specific error.
        #
        #   recovers from: Weft::Unprocessable do |params, error|
        #     { error_messages: error.messages }
        #   end
        #
        #   recovers from: Weft::Unauthorized, with: LoginPage
        #   recovers from: ActiveRecord::RecordNotFound, with: NotFoundPage, status: 404
        #
        # `from:` accepts a Class (subclass-inclusive), Integer (matched against
        # the status the exception reports — see HTTPError.status_for), Range,
        # or Array of any of the above.
        # `with:` accepts a Class (Page or Component) or Symbol (resolved against
        # Weft.configuration at error-handling time). Default: self.
        # `status:` declares what the error means on the wire, and wins over
        # whatever the exception would have reported for itself. Without it, an
        # error that says nothing about its own status reports 500. Must be an
        # HTTP error status (400..599); raises Weft::InvalidUsage otherwise.
        # The optional block receives `|params, error|` and returns a hash of
        # additional params that merge with the original on the recovery edge.
        # Symmetric with performs/transfers contracts (params first; error is the
        # recovery-specific extra). The block never returns HTML.
        def recovers(from:, with: nil, status: nil, &block)
          validate_recovery_status!(status)
          own_recoveries << { from: from, with: with, status: status, block: block }
        end

        # All declared recovery entries (own + inherited), in resolution order.
        # Own entries precede inherited entries so subclass declarations take
        # precedence over ancestor declarations. Within a class, declaration
        # order is preserved — first-declared wins on ties.
        def recoveries
          if superclass.respond_to?(:recoveries)
            own_recoveries + superclass.recoveries
          else
            own_recoveries.dup
          end
        end

        # Find the first recovery entry whose `from:` matches the given exception.
        # Returns nil if nothing matches. `from:` accepts Class (subclass-inclusive),
        # Integer (status equality), Range (status in range), or Array of any of
        # the above (any element matches). Statuses come from HTTPError.status_for.
        def recovery_for(exception)
          recoveries.find { |entry| recovery_matches?(entry[:from], exception) }
        end

        # Like recovery_for, but skips entries whose target resolves to a Page —
        # for contexts that can only render component fragments (an SSE push
        # can't redirect or full-page swap). The gem-default StandardError
        # entry at the bottom of every component chain resolves to a component,
        # so StandardError-family exceptions always find a match.
        def component_recovery_for(exception)
          recoveries.find do |entry|
            recovery_matches?(entry[:from], exception) &&
              !page_recovery_target?(resolve_recovery_target(entry))
          end
        end

        # Resolve the recovery entry's `with:` value to a concrete target class.
        # Symbol values look up `Weft.configuration.<sym>` (resolved at error-handling
        # time so config reassignment propagates). Nil falls back to self.
        def resolve_recovery_target(entry)
          case entry[:with]
          when Symbol then Weft.configuration.public_send(entry[:with])
          when nil    then self
          else entry[:with]
          end
        end

        private

        def own_recoveries
          @own_recoveries ||= []
        end

        # Declarations raise (a bad status is a coding bug, visible at load);
        # only error semantics are assignable — a recovery can't claim success.
        def validate_recovery_status!(status)
          return if status.nil? || (status.is_a?(Integer) && (400..599).cover?(status))

          raise Weft::InvalidUsage,
                "recovers status: must be an HTTP error status (400..599); got #{status.inspect}"
        end

        # Status matching asks the same question the response does, through the
        # same method — a `from: 400` that matched an error the router then
        # reported as 500 would be answering about a different exception than
        # the one it caught.
        def recovery_matches?(from_clause, exception)
          case from_clause
          when Array   then from_clause.any? { |f| recovery_matches?(f, exception) }
          when Class   then exception.is_a?(from_clause)
          when Integer then Weft::HTTPError.status_for(exception) == from_clause
          when Range   then from_clause.cover?(Weft::HTTPError.status_for(exception))
          else false
          end
        end

        def page_recovery_target?(target)
          target.is_a?(Class) && defined?(Weft::Page) && target <= Weft::Page
        end
      end
    end
  end
end
