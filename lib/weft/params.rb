# frozen_string_literal: true

module Weft
  # Value object representing a component's resolved wire params.
  # Provides method-style access with a clear collision-resolution rule:
  # declared param names win, then the underlying Hash API is available
  # for any name not declared as a param.
  #
  # Action callables receive a ready-made instance (the sole argument to a
  # +performs+/+transfers+ block); you don't construct these yourself:
  #
  #   params.status   # => "shipped"  (declared param)
  #   params.count    # => 42         (declared param — wins over Hash#count)
  #   params[:status] # => "shipped"  (explicit hash access)
  #   params.select { ... }           # delegates to the underlying hash
  #   params.to_h     # => the underlying hash (explicit escape hatch)
  class Params
    # Build a Params instance by extracting declared keys from a raw
    # params hash, applying defaults for missing keys. Does not mutate
    # the raw hash.
    #
    #   schema = { status: { default: "pending" }, count: { default: 0 } }
    #   raw    = { status: "shipped", class: "big" }
    #   Weft::Params.extract_from(raw, using: schema)
    #   # => Params{ status: "shipped", count: 0 }
    def self.extract_from(raw, using:)
      data = using.to_h do |name, meta|
        [name, raw.fetch(name, meta[:default])]
      end
      new(data)
    end

    # @api private
    # Constructed internally (see {.extract_from} and the Router's resolver).
    def initialize(data)
      @data = data
    end

    def [](key)
      @data[key]
    end

    def key?(key)
      @data.key?(key)
    end

    def to_h
      @data
    end

    def respond_to_missing?(name, include_private = false)
      @data.key?(name) || @data.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, **kwargs, &block)
      if @data.key?(name) && args.empty? && kwargs.empty? && !block
        @data[name]
      elsif @data.respond_to?(name)
        @data.public_send(name, *args, **kwargs, &block)
      else
        super
      end
    end
  end
end
