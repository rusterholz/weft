# frozen_string_literal: true

require "weft/error"

module Weft
  # Registry for named interaction presets. Each preset is a bundle of
  # trigger/swap/target defaults that Context expands via loads:.
  #
  # Shipped presets are registered at the bottom of this file. Users will be
  # able to register custom presets in v1.x via the same API.
  module Presets
    # Weft's own element-kwarg vocabulary (keep in sync with
    # Context::Expansion's grammar; :prompt reserved ahead of its arrival).
    # A preset by one of these names would shadow the expansion grammar.
    RESERVED_KWARGS = %i[action navigate loads trigger push_url swap target with confirm prompt].freeze

    # HTML attribute names a preset would shadow: a registered preset claims
    # its kwarg whenever the value is a Class or String, so `title: "..."`
    # would stop rendering the HTML attribute. Global attributes plus the
    # commonly-passed per-element ones.
    HTML_ATTRIBUTE_NAMES = %i[
      accesskey autocapitalize autofocus class contenteditable dir draggable enterkeyhint
      hidden id inert inputmode lang nonce popover role slot spellcheck style tabindex
      title translate
      href src alt name value type placeholder disabled readonly required checked selected
      multiple method rel download media width height
    ].freeze

    class << self
      # Register a named interaction preset.
      #
      #   Weft::Presets.register :tooltip, trigger: :hover, swap: :fill
      def register(name, **defaults)
        validate_name!(name)
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

      def validate_name!(name)
        if RESERVED_KWARGS.include?(name)
          raise Weft::InvalidDefinition,
                "cannot register preset #{name.inspect} — it is Weft's own element-kwarg vocabulary"
        end
        return unless HTML_ATTRIBUTE_NAMES.include?(name)

        Weft.logger.warn "preset #{name.inspect} shadows the HTML attribute of the same name — " \
                         "elements passing a Class or String value for #{name}: will expand as this " \
                         "preset instead of rendering the attribute"
      end

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
# click_once, not click: the inserted detail lands after the trigger element,
# so a repeat click would insert a second copy.
Weft::Presets.register :inline_expand,   trigger: :click_once, swap: :after
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

# Reopen_stream is retry's sibling for closed SSE streams (same URL value,
# usually :retry_url). Targeting the enclosing sse-swap wrapper — the element
# left behind after the Router closes a stream — means the fresh render
# replaces it wholesale, and its new sse-connect attribute makes htmx open a
# fresh EventSource: live updates resume with a full attempts budget.
Weft::Presets.register :reopen_stream,   trigger: :click, swap: :outer_html, target: "closest [sse-swap]"
