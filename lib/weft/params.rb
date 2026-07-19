# frozen_string_literal: true

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
    def initialize(data, provenance = {})
      @data = data
      @provenance = provenance
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

    def [](key)
      value = @data[key]
      value.is_a?(Thunk) ? force!(key, value) : value
    end

    def key?(key)
      @data.key?(key)
    end

    def to_h
      materialize!
      @data
    end

    def respond_to_missing?(name, include_private = false)
      @data.key?(name) || @data.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, **kwargs, &block)
      if @data.key?(name) && args.empty? && kwargs.empty? && !block
        self[name]
      elsif @data.respond_to?(name)
        materialize!
        @data.public_send(name, *args, **kwargs, &block)
      else
        super
      end
    end

    private

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
        @data[key] = Weft::DSL::VOID.instance_exec(self, &thunk.block)
      ensure
        @forcing.pop
      end
    end

    def materialize!
      @data.each_key { |key| self[key] }
    end
  end
end
