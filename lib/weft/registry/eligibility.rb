# frozen_string_literal: true

module Weft
  class Registry
    # Class-level routing-eligibility behaviors shared by the base classes that
    # auto-register with {Weft.registry} on definition — {Weft::Component} and
    # {Weft::Page}. Mixed in with +extend+, so these become class methods on
    # those bases and their subclasses, and any individual class may override
    # them. The companion +inferred_routable?+ is defined per base class (its
    # logic differs: components infer from interactive behavior, pages from
    # having a usable path).
    module Eligibility
      # Whether this class auto-routes. An explicit override via {abstract!} or
      # {routable!} takes precedence; otherwise routability is inferred (see the
      # per-class +inferred_routable?+).
      #
      # The override is stored as an instance variable on the declaring class
      # object, so it does not percolate to subclasses — an abstract base can
      # have concrete subclasses that auto-route normally.
      def routable?
        return @routable_explicit if instance_variable_defined?(:@routable_explicit)

        inferred_routable?
      end

      # Mark this class as a non-routable abstract base, even if its declared
      # state would otherwise make it routable. Does not percolate to subclasses.
      def abstract!
        @routable_explicit = false
      end

      # Force this class to be routable, even if its declared state would
      # otherwise make it non-routable. Does not percolate to subclasses.
      def routable!
        @routable_explicit = true
      end

      # Whether this class object has been superseded — its fully-qualified name
      # now resolves to a *different* class. This is the code-reload case: a
      # reloader (e.g. Zeitwerk in development) redefines the constant, binding a
      # new class object to the name while the old one lingers in the registry.
      # The registry drops superseded classes so only the current definition
      # routes (otherwise the two would look like a route collision).
      #
      # Classes whose name does not resolve to a constant — anonymous classes,
      # or test doubles that stub +.name+ — are never stale. Override for
      # bespoke liveness semantics.
      #
      # @note Uses ActiveSupport's +safe_constantize+, which walks the namespace.
      #   The registry calls this only at route-resolution time (memoized), so
      #   the cost is paid once per registry generation, not per request.
      def stale?
        current = name&.safe_constantize
        !current.nil? && !equal?(current)
      end
    end
  end
end
