# frozen_string_literal: true

require "arbre"

require "weft/context/expansion"
require "weft/context/interception"
require "weft/context/modifiers"
require "weft/context/wiring"

module Weft
  # Arbre::Context subclass that intercepts element creation to expand Weft
  # kwargs into htmx attributes — the kwarg vocabulary and its claim rules
  # live in Context::Expansion.
  #
  # Works at every nesting depth because Arbre instance_evals the top-level
  # block, making the Context the receiver for all insert_tag calls throughout
  # the element tree.
  class Context < Arbre::Context
    include Expansion
    include Interception
    include Modifiers
    include Wiring

    # The render's wire params (query/body/path values), carried on the
    # context so every component in the tree resolves its own declared
    # params at any depth. Assigned before super because Arbre's initialize
    # instance_evals the construction block — the tree builds during super.
    attr_reader :wire_params

    # Request-scoped overlay values — the accumulated verb-block deltas
    # (action callable returns, includes deltas, recovery injections). In
    # the source stack an overlay entry speaks AS the wire for its key:
    # a value overrides the wire's, a nil clears it (resolution falls
    # below). One universe per request; these are its amendments.
    attr_reader :overlays

    # A bag for ROOT components to branch from, standing in for the tree
    # ancestor a root doesn't have — how an OOB companion inherits its
    # primary's bag (rich values included) exactly like a child built in
    # the primary's own build.
    attr_reader :branch_bag

    # The DOM ids this RESPONSE has already spoken for — a Set shared across
    # every context the response builds in, because the primary and each of
    # its companions get their own. An out-of-band swap is addressed by DOM
    # id, so only one fragment per id can land; a root component claims its
    # id as it builds (Component#claim_dom_slot!) and a second claimant
    # abandons its render by throwing SLOT_TAKEN. Absent on renders with
    # nothing to arbitrate, and nothing is claimed then.
    attr_reader :slots

    # Thrown with the contested DOM id when a root loses a slot. Caught by
    # whoever asked for the render; nothing partial reaches the tree, because
    # Arbre adds a tag to its parent only after the build returns.
    SLOT_TAKEN = :weft_slot_taken

    # Two positional parameters are Arbre's own signature; the four keywords
    # are Weft's render-scoped channels, each independently optional. That
    # they have grown to four is a fair signal that they want a render-environment
    # object of their own — a change that would touch every render path and
    # a documented constructor, so it belongs with the lifecycle work, not here.
    def initialize(assigns = {}, helpers = nil, wire_params: nil, overlays: nil, # rubocop:disable Metrics/ParameterLists
                   branch_bag: nil, slots: nil, &)
      @wire_params = wire_params || {}
      @overlays = overlays || {}
      @branch_bag = branch_bag
      @slots = slots
      super(assigns, helpers, &)
    end

    # @api private
    # One-shot register for `receives` hand-offs. Interception stages the
    # extracted kwargs here immediately before Arbre constructs the target
    # (insert_tag → build_tag → new); the new instance consumes them during
    # params assembly. Class-checked so a stale staging can never leak into
    # a different component's bag.
    def stage_received(klass, values)
      @staged_received = [klass, values]
    end

    # @api private
    def take_received!(klass)
      staged_class, values = @staged_received
      return unless staged_class.equal?(klass)

      @staged_received = nil
      values
    end
  end
end
