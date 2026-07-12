# frozen_string_literal: true

module Logistics
  # Simulates pick-and-pack: moves a planned shipment to packed.
  # When all of an order's shipments are packed, moves the order to "shipped".
  module PackShipment
    def self.call(shipment)
      return unless shipment.status == "planned"

      shipment.update!(status: "packed")

      # Check if all sibling shipments are now packed → order is shipped
      siblings = Shipment.for_order(shipment.order_id)
      return unless siblings.all? { |s| s.status == "packed" }

      order = Oms::Order.find(shipment.order_id)
      order.update!(status: "shipped") if order.status == "processing"
    end
  end
end
