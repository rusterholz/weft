# frozen_string_literal: true

require "weft/dsl/sandbox"
require "weft/error"

module Weft
  # Value object representing a component's resolved input bag.
  # Provides method-style access with a clear collision-resolution rule:
  # declared param names win, then the underlying Hash API is available
  # for any name not declared as a param.
  #
  # Entries may be lazy: a `derives` declaration registers a Thunk that runs
  # (at most once per bag) when its key is first read, and never runs if the
  # key goes unread. `to_h` and delegated Hash-API calls materialize every
  # remaining thunk first — the eager escape hatch.
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
    # A registered-not-yet-run derivation. Immutable, so branch copies may
    # share it: forcing replaces the entry in the forcing bag only, which is
    # what gives copy-on-branch memoization its semantics.
    class Thunk
      attr_reader :block

      def initialize(block)
        @block = block
      end
    end

    # @api private
    # Constructed internally (components self-resolve via the source stack;
    # the Router wraps bags for action callables and recovery blocks).
    # +provenance+ maps derives-born keys to their block's source_location —
    # retained through forcing so divergence stays detectable.
    # +defaults+ are the declaring class's own fallbacks, consulted when a
    # read finds nothing. They are never stored as values, so they never ride
    # a branch: a default belongs to whoever declared it, and a component
    # deeper in the tree — or downstream of a hand-off — falls back to its
    # own, not to the one above it.
    def initialize(data, provenance = {}, defaults: {})
      @data = data
      @provenance = provenance
      @defaults = defaults
      @forcing = []
    end

    # @api private
    attr_reader :provenance

    # @api private
    # A branchable snapshot for the inheritance axis: forced values and
    # still-lazy thunks both ride (thunks are shared objects — forcing
    # happens per bag, which is what makes the memo copy-on-branch); nils
    # don't ride (nil means "nobody had it" and must not shadow a
    # descendant's own defaults).
    def branch_data
      @data.compact
    end

    # @api private
    # A same-bag copy with +values+ overlaid at their keys. Unlike
    # to_h-then-merge, nothing materializes: untouched thunks stay lazy, nil
    # entries stay resolved-absent, provenance rides. The plain-context
    # hand-off fallback lands received values through this.
    def overlay(values)
      self.class.new(@data.merge(values), @provenance, defaults: @defaults)
    end

    # nil means no source had this key — so the read falls to the declared
    # fallback, exactly as it falls past a nil at any other level of the stack.
    def [](key)
      value = @data[key]
      value = force!(key, value) if value.is_a?(Thunk)
      value.nil? ? @defaults[key] : value
    end

    def key?(key)
      @data.key?(key) || @defaults.key?(key)
    end

    def to_h = materialized

    def respond_to_missing?(name, include_private = false)
      key?(name) || @data.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, **kwargs, &block)
      if key?(name) && args.empty? && kwargs.empty? && !block
        self[name]
      elsif @data.respond_to?(name)
        materialized.public_send(name, *args, **kwargs, &block)
      else
        super
      end
    end

    private

    # The bag as a plain hash: every thunk run, every unsupplied key standing
    # at its declared fallback.
    def materialized
      materialize!
      @defaults.merge(@data) { |_key, fallback, value| value.nil? ? fallback : value }
    end

    # Run a thunk with the bag as its argument (derivations chain by reading
    # sibling keys) and memoize the result in place. A failed derivation is
    # not memoized — like RSpec's let, it reruns if read again. The in-flight
    # list turns circular derivations into a clear error instead of a stack
    # overflow.
    def force!(key, thunk)
      if @forcing.include?(key)
        raise Weft::InvalidUsage,
              "circular derivation: #{(@forcing + [key]).join(' -> ')} " \
              "(a derives block may not read its own key)"
      end

      @forcing << key
      begin
        @data[key] = Weft::DSL::Sandbox.run(self, &thunk.block)
      ensure
        @forcing.pop
      end
    end

    def materialize!
      @data.each_key { |key| self[key] }
    end
  end
end
