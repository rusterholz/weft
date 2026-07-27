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

      # Same switch as {abstract!}, named for the other reason to flip it:
      # "I rely on state I can only receive, not reconstruct — my parent must
      # hand it to me every time, so serving me standalone makes no sense."
      alias dependent! abstract!

      # Force this class to be routable, even if its declared state would
      # otherwise make it non-routable. Does not percolate to subclasses.
      def routable!
        @routable_explicit = true
      end
    end
  end
end
