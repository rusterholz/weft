# frozen_string_literal: true

require "json"

module Weft
  # Metadata for a single component action (declared via `performs` or `transfers`).
  # Knows how to derive its route path and generate htmx attributes.
  #
  # Every Action knows what it `renders` — the component class rendered in the
  # response. For `performs`, that's the declaring class (re-render self).
  # For `transfers`, it's the `to:` class (render something else).
  # The Router always renders `action.renders` — no branching.
  #
  # `target` is the other kind of target — the CSS selector for where the
  # response lands in the DOM (hx-target). Nil means the component's own element.
  class Action
    attr_reader :name, :method, :swap, :target, :renders, :callable

    def initialize(name:, renders:, method: :post, swap: :outer_html, target: nil, callable: nil) # rubocop:disable Metrics/ParameterLists
      @name = name
      @method = method
      @swap = swap
      @target = target
      @renders = renders
      @callable = callable
    end

    SWAP_VALUES = {
      # Semantic names (preferred)
      replace: "outerHTML",
      fill: "innerHTML",
      before: "beforebegin",
      after: "afterend",
      append: "beforeend",
      prepend: "afterbegin",
      remove: "delete",
      # htmx-native names (also accepted)
      outer_html: "outerHTML",
      inner_html: "innerHTML",
      before_begin: "beforebegin",
      after_begin: "afterbegin",
      before_end: "beforeend",
      after_end: "afterend",
      delete: "delete",
      none: "none"
    }.freeze

    TRIGGER_VALUES = {
      click: "click",
      hover: "mouseenter once",
      visible: "revealed",
      input: "input changed delay:300ms"
    }.freeze

    def nameless? = @name.nil?

    # The URL path for this action, given the component's base path.
    def route_path(component_path)
      nameless? ? component_path : "#{component_path}/#{name}"
    end

    # Generate htmx attributes for an element that triggers this action.
    def to_htmx_attrs(component)
      path = route_path(component.class.resolved_component_path)
      {
        "hx-#{method}" => path,
        "hx-target" => target || "##{component.weft_id}",
        "hx-swap" => self.class.resolve_swap(swap),
        "hx-vals" => component.params.to_h.to_json
      }
    end

    # Resolve a swap symbol or string to its htmx value.
    def self.resolve_swap(value)
      SWAP_VALUES.fetch(value, value.to_s)
    end

    # Resolve a trigger symbol or string to its htmx value.
    def self.resolve_trigger(value)
      TRIGGER_VALUES.fetch(value, value.to_s)
    end
  end
end
