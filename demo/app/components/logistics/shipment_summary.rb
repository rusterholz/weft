# frozen_string_literal: true

module Logistics
  # Tooltip content: cross-domain shipment summary (the driver tooltip's
  # entry point — Delivery → Logistics → OMS). Auto-routes at
  # /_components/logistics/shipment_summary?shipment_id=...
  class ShipmentSummary < Weft::Component
    builder_method :shipment_summary

    param :shipment_id

    def build(attributes = {})
      super
      shipment = Logistics::Shipment.find(params.shipment_id)
      order = Oms::Order.find_by(id: shipment.order_id)

      if order.nil?
        div { text_node "Order not found." }
      else
        dl(class: "mb-0") do
          dt "Order"
          dd(class: "mono") { text_node order.id[..7] }
          dt "Customer"
          dd { text_node order.customer_name }
          dt "Destination"
          dd { text_node [order.city, order.state].compact.join(", ") }
          dt "Items"
          dd do
            text_node((shipment.items || []).map { |i| "#{i['type']} (#{i['qty']})" }.join(", "))
          end
        end
      end
    end
  end
end
