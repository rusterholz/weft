# frozen_string_literal: true

module Weft
  # Registry for named interaction shorthands. Each shorthand is a preset of
  # trigger/swap/target defaults that Context expands via loads:.
  #
  # Shipped presets are registered at the bottom of this file. Users will be
  # able to register custom shorthands in v1.x via the same API.
  module Shorthands
    class << self
      # Register a named interaction shorthand.
      #
      #   Weft::Shorthands.register :tooltip, trigger: :hover, swap: :fill
      def register(name, **defaults)
        registry[name] = defaults
      end

      # Look up a registered shorthand by name. Returns the defaults hash or nil.
      def lookup(name)
        registry[name]
      end

      # All registered shorthand names.
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

# Shipped interaction shorthands. Adding a new one is one line.
# The mechanism (Context dispatch + loads: expansion) handles the rest.
#
# NOTE: "shorthand" naming is provisional — may be renamed to "pattern"
# or similar after evaluation (Mission 29).

Weft::Shorthands.register :tooltip,         trigger: :hover, swap: :fill
Weft::Shorthands.register :inline_expand,   trigger: :click, swap: :after
Weft::Shorthands.register :lazy,            trigger: :visible, swap: :fill, target: :self
Weft::Shorthands.register :modal,           trigger: :click, swap: :fill
Weft::Shorthands.register :load_more,       trigger: :click, swap: :replace, target: :self
Weft::Shorthands.register :infinite_scroll, trigger: :visible, swap: :after
Weft::Shorthands.register :live_search,     trigger: :input, swap: :fill
Weft::Shorthands.register :tabs,            trigger: :click, swap: :fill

# Retry is the odd one out: its value is a URL (the failing component's own GET
# URL, injected as the :retry_url recovery attr), not a target Class. It ships a
# concrete hx-target so error components never hand-write htmx — outerHTML-swapping
# the enclosing .weft-error box replaces the whole error display with the fresh
# component. Callers override target: for a differently-classed container.
Weft::Shorthands.register :retry,           trigger: :click, swap: :outer_html, target: "closest .weft-error"
