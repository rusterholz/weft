# frozen_string_literal: true

module Weft
  # Value object returned from action callables to trigger navigation
  # instead of re-rendering. The Router detects Redirect returns and
  # sends HX-Redirect (htmx) or 302 (traditional form).
  #
  # Preferred form accepts a Page subclass:
  #   Weft::Redirect.to(OrderDetailPage, order_id: order.id)
  #
  # String path fallback:
  #   Weft::Redirect.to("/orders/#{order.id}")
  #
  # Convenience wrapper:
  #   Weft.redirect(OrderDetailPage, order_id: order.id)
  class Redirect
    attr_reader :target, :attrs

    # @api private
    # Use {Redirect.to} (or {Weft.redirect}) — +new+ is private.
    def initialize(target, **attrs)
      @target = target
      @attrs = attrs
    end

    # Resolve the redirect URL.
    # Page targets: interpolate attrs into page_path pattern.
    # String targets: use as-is.
    def url
      case @target
      when String
        @target
      else
        @target.resolve_page_path(@attrs)
      end
    end

    # Primary constructor.
    def self.to(target, **attrs)
      new(target, **attrs)
    end

    private_class_method :new
  end
end
