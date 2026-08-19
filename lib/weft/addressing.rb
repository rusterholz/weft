# frozen_string_literal: true

require "digest"
require "securerandom"

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
    # SHA256's hex width — the most a digested identity slot can ask for.
    MAX_DIGEST_LENGTH = 64

    # Marks a slot weft generated from a value rather than rendering the value
    # itself, so the two can never be mistaken for each other. Uppercase is
    # what makes that structural: the sanitizer downcases everything it emits,
    # exotic uppercase included. It has to be a prefix rather than a rule about
    # the token's own alphabet, since an all-digit token carries no case at all.
    DIGEST_MARKER = "D"

    # Marks a slot weft issued from nothing, as DIGEST_MARKER marks one it
    # derived from a value. Disjoint from that marker and from the sanitizer's
    # output alike, so the three kinds of slot can never be read for each other.
    MINT_MARKER = "M"

    MINT_ENTROPY_BYTES = 4
    MINT_FORMAT = /\A#{MINT_MARKER}\h{#{MINT_ENTROPY_BYTES * 2}}\z/

    class << self
      # A token standing in for a component that has no identifying value at
      # all. Issued once, at first render, and carried back over the wire from
      # then on — unlike a digest, there is nothing to recompute it from, so
      # losing it means losing the identity.
      def mint = "#{MINT_MARKER}#{SecureRandom.hex(MINT_ENTROPY_BYTES)}"

      # Whether +value+ is a token this module issued. A mint arrives from the
      # wire, where anything can be typed, so it is checked rather than trusted
      # before it reaches an id attribute.
      def mint?(value) = value.to_s.match?(MINT_FORMAT)

      # An opaque, stable token standing in for +value+ in a DOM address.
      #
      # Reads `inspect`, not `to_s`: `to_s` renders `nil` and `""` identically,
      # and telling those apart is most of what a digested slot is for. SHA256 is
      # truncated rather than used whole so the width becomes a knob — which is
      # what lets a page of a hundred thousand rows buy collision resistance that
      # a page of ten needn't pay for. `String#hash` cannot stand in: it is seeded
      # per process, so it agrees with itself under one worker and disagrees
      # under two.
      def digest(value, length)
        "#{DIGEST_MARKER}#{::Digest::SHA256.hexdigest(value.inspect)[0, length]}"
      end
    end

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
