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

    # The delivery this tree renders for: its wire universe, which every
    # component projects through its own declarations at any depth, and the
    # slot register roots claim their DOM ids from. Assigned before super
    # because Arbre's initialize instance_evals the construction block — the
    # tree builds during super.
    attr_reader :frame

    # A bag for ROOT components to branch from, standing in for the tree
    # ancestor a root doesn't have — how an OOB companion inherits its
    # primary's bag (rich values included) exactly like a child built in
    # the primary's own build.
    attr_reader :branch_bag

    # @api private
    # Every DOM id this render has emitted, at any depth, mapped to the class
    # that emitted it — the register behind the duplicate-id warning.
    #
    # Deliberately separate from the frame's slots, which span a whole delivery and
    # tracks ROOT components only, because it exists to catch precisely what
    # slots cannot see: chrome nested inside a wrapper, colliding silently.
    def dom_ids_seen
      @dom_ids_seen ||= {}
    end

    # Thrown with the contested DOM id when a root loses a slot. Caught by
    # whoever asked for the render; nothing partial reaches the tree, because
    # Arbre adds a tag to its parent only after the build returns.
    SLOT_TAKEN = :weft_slot_taken

    # Two channels: the delivery-wide frame and this root's lineage. Arbre's
    # own assigns and helpers are passed empty: a bare name resolving from
    # assigns would be an undeclared, unranked params channel beside the bag.
    def initialize(frame:, branch_bag: nil, &)
      @frame = frame
      @branch_bag = branch_bag
      super({}, nil, &)
    end

    # @api private
    # One-shot register for `receives` handoffs. Interception stages the
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
