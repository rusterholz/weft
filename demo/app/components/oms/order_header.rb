# frozen_string_literal: true

module Oms
  class OrderHeader < Weft::Component
    builder_method :order_header

    param :order_id, type: :string

    derives(:order) { |p| Oms::Order.find(p.order_id) }

    # Hands the region to the edit form. Blockless: opening the editor has
    # nothing to say about the order, and an action callable can't read this
    # class's `derives` anyway — those are evaluated during a render, so
    # there is no already-loaded order here to pass along.
    transfers :edit, to: Oms::EditableOrderHeader

    # Advancing packs or dispatches shipments, so the shipments card is stale
    # after it — but not after an edit. An edit changes the customer name,
    # which the details card shows and the shipments card doesn't. Two
    # companions, two different reasons to ride.
    includes Logistics::ShipmentsCard, on: :advance
    includes Oms::OrderDetailsCard, when: :transferred

    performs :advance do |params|
      order = Oms::Order.find(params.order_id)
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
