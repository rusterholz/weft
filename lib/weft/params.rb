# frozen_string_literal: true

require "weft/dsl/sandbox"
require "weft/error"

module Weft
  # Value object representing a component's resolved input bag.
  # Provides method-style access with a clear collision-resolution rule:
  # declared param names win, then the underlying Hash API is available
  # for any name not declared as a param.
  #
  # One exception, and it is a defect rather than a rule: a name this class
  # defines as a real method (`branch_data`, `to_h`, `key?`) never reaches
  # method_missing, so declaring it as a param shadows the declaration instead
  # of winning. `branch_data` is the one that matters — it has no business
  # occupying the adopter's namespace, and answers with weft's internal hash
  # rather than erroring.
  #
  # Entries may be lazy: a `derives` declaration registers a Thunk that runs
  # when its key is first read, and never runs if the key goes unread. The
  # outcome settles on the Thunk rather than in the bag, so every bag holding
  # that Thunk sees it — one derivation, one answer, per request. `to_h` and
  # delegated Hash-API calls materialize every remaining thunk first — the
  # eager escape hatch.
  #
  # Action callables receive a ready-made instance (the sole argument to a
  # +performs+/+transfers+ block); you don't construct these yourself:
  #
  #   params.status   # => "shipped"  (declared param)
  #   params.count    # => 42         (declared param — wins over Hash#count)
  #   params[:status] # => "shipped"  (explicit hash access)
  #   params.select { ... }           # delegates to the underlying hash (materializes)
  #   params.to_h     # => the underlying hash (explicit escape hatch; materializes)
  class Params
    # @api private
    # A registered-not-yet-run derivation, and the memo of how it turned out.
    # The outcome settles exactly once: a result is remembered as {#value}, a
    # failure as {#error} and re-raised from every later read. Nothing is ever
    # reattempted, so a derivation cannot answer two different ways within one
    # request — which is the point, since a block may query, and a second query
    # can disagree with the first.
    #
    # Because the memo lives here rather than in the forcing bag, branches that
    # share a Thunk share its outcome. Branches that must NOT share one are
    # given an unforced copy at branch time; see {Assembly}.
    class Thunk
      # Distinguishes "resolved to nothing" from "not yet run". A derivation
      # may legitimately produce nil or false, so neither can stand for absence.
      UNSET = Object.new.freeze
      private_constant :UNSET

      # Failures worth remembering. StandardError is the ordinary case;
      # ScriptError is here because an outcome that escapes unrecorded gets
      # RE-RUN on the next read — a failed autoload or an abstract method would
      # otherwise reintroduce double execution by the least-expected door.
      # Signals, Interrupt, SystemExit and NoMemoryError deliberately pass
      # through: the host is going down, and that is not a derivation result.
      RECOVERABLE_ERRORS = [StandardError, ScriptError].freeze
      private_constant :RECOVERABLE_ERRORS

      attr_reader :block

      # The bag this derivation belongs to — the one its declaring component
      # resolved at construction, which is what its `build` reads. Set once, by
      # the Assembly that introduced the thunk; an inherited thunk keeps the
      # home it was given, which is what makes a shared derivation answer with
      # the declarer's value rather than the first reader's.
      #
      # Deliberately not the reading bag: a declaring component with two
      # companions whose blocks return different deltas could only see one of
      # them, leaving the other's universe inconsistent and the winner decided
      # by render order. Seeing neither is the only symmetric answer.
      attr_accessor :home

      def initialize(block, contextual: false)
        @block = block
        @contextual = contextual
        @home = nil
        @value = UNSET
        @error = UNSET
      end

      # Whether this derivation belongs to the bag reading it rather than to
      # the one that declared it. A contextual thunk is copied into each branch
      # that inherits it, so no two branches share an outcome.
      def contextual? = @contextual

      # A fresh, unforced twin for a branch to own.
      def unforced_copy = self.class.new(@block, contextual: @contextual)

      # The exception this derivation raised, or nil if it hasn't failed.
      def error = @error.equal?(UNSET) ? nil : @error

      # Whether the outcome has settled, either way.
      def forced? = !@value.equal?(UNSET) || !@error.equal?(UNSET)

      # The derivation's result, running the block once if it hasn't run.
      # It runs against {#home} when there is one; +reading_bag+ covers a thunk
      # assembled by nobody, which only a hand-built bag produces.
      def value(reading_bag = nil)
        raise @error unless @error.equal?(UNSET)
        return @value unless @value.equal?(UNSET)

        force(@home || reading_bag)
      end

      private

      def force(reading_bag)
        @value = Weft::DSL::Sandbox.run(reading_bag, &@block)
      rescue *RECOVERABLE_ERRORS => e
        @error = e
        raise
      end
    end

    # @api private
    # Constructed internally (components self-resolve via the source stack;
    # the Router wraps bags for action callables and recovery blocks).
    # +defaults+ are the declaring class's own fallbacks, consulted when a
    # read finds nothing. They are never stored as values, so they never ride
    # a branch: a default belongs to whoever declared it, and a component
    # deeper in the tree — or downstream of a hand-off — falls back to its
    # own, not to the one above it.
    # +owner+ is the class the bag was assembled for, carried so that a read
    # finding nothing can say why instead of naming this class at the adopter.
    # +overlay+ is the accumulated verb-block delta this bag carries. It is kept
    # apart from +data+ rather than merged into it because the two travel
    # differently: data demotes to "inherited" when a branch crosses into
    # another component's declarations, while the overlay persists at its own
    # rung all the way down. A bag that held only the merged result could not
    # express the difference, and every operation on it would silently lose one.
    def initialize(data, defaults: {}, owner: nil, overlay: {})
      @data = data
      @defaults = defaults
      @owner = owner
      @overlay = overlay
      @forcing = []
    end

    # This bag with +values+ layered on — the non-crossing branch: same
    # declarations, same defaults, a delta on top. Nothing materializes;
    # untouched thunks stay lazy and keep their homes, so a derivation never
    # adopts one block's delta when a sibling supplied a different one.
    #
    # The delta lands in two places because it does two jobs, and they are not
    # the same job. Its VALUES go to the data, which is what this bag answers
    # with. The whole delta goes to the overlay, which is what the next crossing
    # branch applies at its own rung — nils included, since a nil is an
    # instruction to suppress a wire value rather than a value itself, and
    # writing one into the data would destroy the very entry that resolution is
    # supposed to fall through to.
    #
    # An empty delta answers with this same instance. That identity is safe only
    # because a bag has no writers — a read forces a Thunk, which memoizes on the
    # Thunk rather than here — so sharing one can never surprise the other holder.
    def %(delta) # rubocop:disable Naming/BinaryOperatorParameterName
      return self if delta.empty?

      self.class.new(@data.merge(delta.compact), defaults: @defaults, owner: @owner,
                                                 overlay: @overlay.merge(delta))
    end

    # @api private
    # A branchable snapshot for the inheritance axis. A thunk rides as itself,
    # carrying whatever outcome it has settled on, so a descendant inherits the
    # derivation rather than repeating it — including when that outcome was
    # nil, which is an answer rather than an absence.
    #
    # Plain nils still don't ride: there, nil means "no source had this key"
    # and must not shadow a descendant's own defaults.
    def branch_data
      @data.compact
    end

    # nil means no source had this key — so the read falls to the declared
    # fallback, exactly as it falls past a nil at any other level of the stack.
    #
    # The overlay is deliberately NOT consulted here. A read asks what THIS bag
    # resolved, and the answer already accounts for the delta: assembly ranked it
    # at level 2 while composing the data, and `%` wrote its values straight in.
    # Consulting it again would re-apply level 2 on top of the finished result —
    # which a component's own hand-off, at level 1, is entitled to outrank.
    def [](key)
      value = @data[key]
      value = force!(key, value) if value.is_a?(Thunk)
      value.nil? ? @defaults[key] : value
    end

    def key?(key)
      @data.key?(key) || @defaults.key?(key)
    end

    def respond_to_missing?(name, include_private = false)
      key?(name) || @data.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, **kwargs, &block)
      return self[name] if bare_read?(name, args, kwargs, block)

      lazy = lazy_hash_answer(name, args, kwargs, block)
      return lazy unless lazy.nil?

      return materialized.public_send(name, *args, **kwargs, &block) if @data.respond_to?(name)

      super
    rescue NoMethodError => e
      raise unless unreachable_handoff?(name, e)

      raise Weft::UnreachableHandoff, unreachable_handoff_message(name), e.backtrace, cause: e
    end

    private

    # Hash-API answers that need no derivation run, or not every one. They live
    # here rather than as real methods so that a param declared with the same
    # name still wins at bare_read? above — a real method would never reach
    # method_missing, which is how `overlay` and `branch_data` came to shadow
    # the declarations they collide with.

    # nil means "not one of these" — safe as a sentinel because `keys` always
    # answers an Array and `any?` always a boolean.
    def lazy_hash_answer(name, args, kwargs, block)
      return unless args.empty? && kwargs.empty?

      case name
      when :keys then lazy_keys if block.nil?
      when :any? then lazy_any?(&block) if block
      end
    end

    # Every key the bag can answer for. A thunk occupies its key whether or not
    # it has run, so this costs nothing and works on a bag whose derivation
    # already failed.
    def lazy_keys = @data.keys | @defaults.keys

    # Forces one key at a time and stops at the first truthy yield, so a
    # satisfied `any?` never pays for the rest of the bag — and never trips
    # over a derivation it did not need. The pair is yielded as an array, which
    # is what Hash does, so one- and two-argument blocks both read naturally.
    def lazy_any?
      lazy_keys.each { |key| return true if yield([key, self[key]]) }
      false
    end

    # A declared key asked for as a plain attribute. Anything carrying
    # arguments or a block means something else and belongs to the Hash API.
    def bare_read?(name, args, kwargs, block)
      key?(name) && args.empty? && kwargs.empty? && !block
    end

    # A key whose only door is `receives` and which declared no fallback: a
    # call site is its sole possible source, and this bag was assembled where
    # none exists. Anything else — an undeclared name, a typo — keeps raising
    # NoMethodError, which is what it is.
    def unreachable_handoff?(name, error)
      return false if @owner.nil? || error.name != name || key?(name)

      meta = @owner.received_params[name]
      !meta.nil? && !meta.key?(:default)
    end

    def unreachable_handoff_message(name)
      "#{@owner.name} has not been built here, so nothing handed #{name.inspect} in — a " \
        "receives value comes from the call site that builds the component. Give " \
        "#{name.inspect} a default:, or a source that needs no caller: param #{name.inspect} " \
        "if it can ride a URL, derives(#{name.inspect}) { ... } if the server can fetch it"
    end

    # The bag as a plain hash: every thunk run, every unsupplied key standing
    # at its declared fallback.
    def materialized
      @defaults.merge(resolved_data) { |_key, fallback, value| value.nil? ? fallback : value }
    end

    # @api private
    # Every key whose derivation has been forced and failed, mapped to what it
    # raised. Only outcomes that have actually settled appear: an unforced
    # derivation might yet succeed, so reporting it would be a guess.
    #
    # Private on purpose. A real public method never reaches method_missing, so
    # it would shadow a param an adopter declared with the same name — the
    # defect this avoids. Weft reaches it with `send`; a private method called
    # with an explicit receiver still routes through method_missing, so the
    # adopter's declaration keeps winning.
    #
    # Needs no registry of its own: a thunk is one object across every bag that
    # inherits it, so a failure anywhere in a lineage is visible everywhere it
    # reaches, by identity.
    def derivation_errors
      @data.each_with_object({}) do |(key, entry), errors|
        errors[key] = entry.error if entry.is_a?(Thunk) && entry.error
      end
    end

    # @api private
    # The other half of what a crossing branch takes from this bag: the overlay,
    # which arrives still outranking the crossed-into class's own wire, at level
    # 2, where {#branch_data} arrives as "inherited" at level 4. Splitting them
    # is the whole reason a bag holds an overlay slot.
    #
    # Private, and reached with +send+, for the same reason {#derivation_errors}
    # is: a real public method never sees method_missing, so it would shadow a
    # param an adopter declared with the same name.
    def overlay_slot = @overlay

    # Ask a thunk for its outcome, with this bag as the block's argument
    # (derivations chain by reading sibling keys). The memo lives on the Thunk,
    # not here, so the entry stays a Thunk and every bag holding that same
    # instance sees the outcome. The in-flight list turns circular derivations
    # into a clear error instead of a stack overflow.
    def force!(key, thunk)
      if @forcing.include?(key)
        raise Weft::InvalidUsage,
              "circular derivation: #{(@forcing + [key]).join(' -> ')} " \
              "(a derives block may not read its own key)"
      end

      @forcing << key
      begin
        thunk.value(self)
      ensure
        @forcing.pop
      end
    end

    # @data with every thunk resolved to its outcome. Read through +[]+ so the
    # circular guard and the declared fallbacks apply exactly as they do to a
    # single read.
    def resolved_data
      @data.each_key.to_h { |key| [key, self[key]] }
    end
  end
end
