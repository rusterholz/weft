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

    def initialize(assigns = {}, helpers = nil, wire_params: nil, &)
      @wire_params = wire_params || {}
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
