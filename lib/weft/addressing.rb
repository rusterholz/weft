# frozen_string_literal: true

require "active_support/core_ext/string/inflections"

module Weft
  # How a rendered thing is found when something needs to reach it. Two address
  # forms share this module: the **route address** (is this class served over
  # HTTP, and at what path) and the **DOM address** (the element id a fragment
  # swaps into). They are orthogonal — a presentational component that never
  # routes still needs an id to be swapped into — and they share one derivation
  # of the stem both are built from.
  #
  # Shared by the base classes that auto-register with {Weft.registry} on
  # definition — {Weft::Component} and {Weft::Page}. Mixed in with +extend+, so
  # these become class methods on those bases and their subclasses, and any
  # individual class may override them. The companion +inferred_routable?+ is
  # defined per base class (its logic differs: components infer from interactive
  # behavior, pages from having a usable path).
  module Addressing
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

    private

    # The name both address forms are built from: the class's own name with
    # its kind suffix removed — unless removing it would leave no usable stem
    # (a bare +Component+, or +Foo::Component+), in which case the name stands
    # whole rather than degenerating into an empty segment.
    #
    # Deliberately opinion-free: it answers "what name do I build an address
    # from," never "should this class have an address." That second question
    # is +routable?+ and the per-class +inferred_routable?+, which keep their
    # own stricter test — a class named for its kind has no meaningful stem of
    # its own, which is a fine reason not to route it and a bad reason to
    # refuse it an id.
    def stem(class_name, suffix)
      trimmed = class_name.to_s.delete_suffix(suffix)
      trimmed.demodulize.empty? ? class_name.to_s : trimmed
    end
  end
end
