# frozen_string_literal: true

module DropshipUI
  # Lazy-loaded hover tooltip. Wraps a trigger element (the visible content
  # the user hovers over) and a popover whose content is fetched via the
  # tooltip: shorthand on the first hover. The content is a Weft::Component
  # class; the wire attrs go through `with:`.
  #
  # Usage:
  #   tooltip(content: Logistics::ShipmentManifest, with: { shipment_id: id }) do
  #     text_node "3 items"
  #   end
  #
  # The block content is the visible trigger. The popover content loads
  # asynchronously on the first mouseenter on the wrap.
  class Tooltip < Weft::Component
    builder_method :tooltip
    adds_children_to :@trigger_container

    def build(attributes = {})
      content_class = attributes.delete(:content)
      content_with = attributes.delete(:with) || {}
      super
      add_class "weft-tooltip-wrap"

      # Build trigger container and popover as siblings. Assign the
      # @trigger_container ivar LAST so that add_child doesn't redirect
      # the popover into the trigger during build.
      trigger = span(class: "weft-tooltip-trigger")

      div(class: "weft-tooltip",
          tooltip: content_class,
          with: content_with,
          target: :self,
          trigger: "mouseenter once from:closest .weft-tooltip-wrap") do
        span(class: "text-muted") { text_node "Loading…" }
      end

      @trigger_container = trigger
    end

    # Use a div with display:inline-block so we can legitimately host
    # block-level content (dl/dt/dd) inside the popover.
    def tag_name
      "div"
    end
  end
end
