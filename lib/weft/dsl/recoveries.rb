# frozen_string_literal: true

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
        #
        # `from:` accepts a Class (subclass-inclusive), Integer (matched against
        # HTTPError#status), Range, or Array of any of the above.
        # `with:` accepts a Class (Page or Component) or Symbol (resolved against
        # Weft.configuration at error-handling time). Default: self.
        # The optional block receives `|params, error|` and returns a hash of
        # additional params that merge with the original on the recovery edge.
        # Symmetric with performs/transfers contracts (params first; error is the
        # recovery-specific extra). The block never returns HTML.
        def recovers(from:, with: nil, &block)
          own_recoveries << { from: from, with: with, block: block }
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
        # Integer (status equality — HTTPError carries .status; non-HTTPError = 500),
        # Range (status in range), or Array of any of the above (any element matches).
        def recovery_for(exception)
          recoveries.find { |entry| recovery_matches?(entry[:from], exception) }
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

        def recovery_matches?(from_clause, exception)
          case from_clause
          when Array   then from_clause.any? { |f| recovery_matches?(f, exception) }
          when Class   then exception.is_a?(from_clause)
          when Integer then recovery_status_of(exception) == from_clause
          when Range   then from_clause.cover?(recovery_status_of(exception))
          else false
          end
        end

        def recovery_status_of(exception)
          exception.is_a?(Weft::HTTPError) ? exception.status : 500
        end
      end
    end
  end
end
