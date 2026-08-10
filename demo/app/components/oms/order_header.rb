# frozen_string_literal: true

module Oms
  class OrderHeader < Oms::OrderRegion
    builder_method :order_header

    # Hands the region to the edit form. Blockless: opening the editor has
    # nothing to say about the order that the editor can't work out for
    # itself — it shares this region's derivation, so it arrives knowing how
    # to find the order without being told.
    transfers :edit, to: Oms::EditableOrderHeader

    # Advancing packs or dispatches shipments, so the shipments card is stale
    # after it — but not after an edit. An edit changes the customer name,
    # which the details card shows and the shipments card doesn't. Two
    # companions, two different reasons to ride. (The details card also hears
    # about advances, but by subscribing to the event below rather than by
    # riding along — it isn't part of that response.)
    includes Logistics::ShipmentsCard, on: :advance
    includes Oms::OrderDetailsCard, when: :transferred

    # Two announcements, each mapped to the action that earns it. Advancing
    # moves the order through the pipeline; opening the editor changes who
    # owns this region and nothing else. Without `on:` a single declaration
    # would fire on both, and everything listening for a status change would
    # refetch every time someone clicked Edit.
    triggers "order-updated", on: :advance
    triggers "order-editing", on: :edit

    performs :advance do |params|
      order = params.order
      case order.status
      when "submitted"
        Oms::PrepareOrder.call(order)
      when "processing"
        Logistics::Shipment.for_order(order.id).by_status("planned").each { |s| Logistics::PackShipment.call(s) }
      when "shipped"
        Logistics::Shipment.for_order(order.id).by_status("packed").each { |s| Logistics::DispatchShipment.call(s) }
        Logistics::Shipment.for_order(order.id).by_status("in_transit").each { |s| Logistics::CompleteDelivery.call(s) }
      end
    end

    def build(attributes = {})
      super
      add_class "page-header d-flex justify-content-between align-items-center"

      h1 do
        text_node "Order "
        span(params.order.id[..7], class: "mono")
        text_node " — "
        span params.order.customer_name
        text_node " "
        status_badge params.order.status
      end

      div(class: "d-flex gap-2") do
        button "Edit", class: "btn btn-sm btn-outline-secondary", action: :edit
        next if params.order.status == "fulfilled"

        button "Force Advance", class: "btn btn-sm btn-outline-secondary", action: :advance
      end
    end
  end
end
