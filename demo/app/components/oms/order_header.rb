# frozen_string_literal: true

module Oms
  class OrderHeader < Weft::Component
    builder_method :order_header

    param :order_id

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

      order = Oms::Order.find(params.order_id)

      h1 do
        text_node "Order "
        span(order.id[..7], class: "mono")
        text_node " "
        status_badge order.status
      end
      return if order.status == "fulfilled"

      button "Force Advance", class: "btn btn-sm btn-outline-secondary",
                              action: :advance
    end
  end
end
