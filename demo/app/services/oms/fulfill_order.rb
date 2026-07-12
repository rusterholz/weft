# frozen_string_literal: true

module Oms
  # Checks if all shipments for an order are delivered; if so, marks fulfilled.
  module FulfillOrder
    def self.call(order)
      return unless order.status == "shipped"

      shipments = Logistics::Shipment.for_order(order.id)
      return if shipments.empty?
      return unless shipments.all? { |s| s.status == "delivered" }

      order.update!(status: "fulfilled")
    end
  end
end
