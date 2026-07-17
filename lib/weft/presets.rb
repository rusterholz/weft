# frozen_string_literal: true

module Weft
  # Registry for named interaction presets. Each preset is a bundle of
  # trigger/swap/target defaults that Context expands via loads:.
  #
  # Shipped presets are registered at the bottom of this file. Users will be
  # able to register custom presets in v1.x via the same API.
  module Presets
    class << self
      # Register a named interaction preset.
      #
      #   Weft::Presets.register :tooltip, trigger: :hover, swap: :fill
      def register(name, **defaults)
        registry[name] = defaults
      end

      # Look up a registered preset by name. Returns the defaults hash or nil.
      def lookup(name)
        registry[name]
      end

      # All registered preset names.
      def registered
        registry.keys
      end

      private

      def registry
        @registry ||= {}
      end
    end
  end
end

# Shipped interaction presets — each bundles the htmx wiring for a common
# hypermedia interaction pattern. Adding one is a single line; Context dispatch
# + loads: expansion handles the rest.

Weft::Presets.register :tooltip,         trigger: :hover, swap: :fill
Weft::Presets.register :inline_expand,   trigger: :click, swap: :after
Weft::Presets.register :lazy,            trigger: :visible, swap: :fill, target: :self
Weft::Presets.register :modal,           trigger: :click, swap: :fill
Weft::Presets.register :load_more,       trigger: :click, swap: :replace, target: :self
Weft::Presets.register :infinite_scroll, trigger: :visible, swap: :after
Weft::Presets.register :live_search,     trigger: :input, swap: :fill
Weft::Presets.register :tabs,            trigger: :click, swap: :fill

# Retry is the odd one out: its value is a URL (the failing component's own GET
# URL, injected as the :retry_url recovery param), not a target Class. It ships a
# concrete hx-target so error components never hand-write htmx — outerHTML-swapping
# the enclosing .weft-error box replaces the whole error display with the fresh
# component. Callers override target: for a differently-classed container.
Weft::Presets.register :retry,           trigger: :click, swap: :outer_html, target: "closest .weft-error"
