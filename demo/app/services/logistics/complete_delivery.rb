# frozen_string_literal: true

module Logistics
  # Completes a delivery: marks shipment delivered, releases the driver,
  # and checks if the order is now fully fulfilled.
  module CompleteDelivery
    def self.call(shipment)
      return unless shipment.status == "in_transit"

      ActiveRecord::Base.transaction do
        release_driver!(shipment)
        shipment.update!(status: "delivered")
      end

      # Check fulfillment outside the transaction — not critical path
      order = Oms::Order.find(shipment.order_id)
      Oms::FulfillOrder.call(order)
    end

    def self.release_driver!(shipment)
      return unless shipment.driver_id

      driver = Delivery::Driver.find(shipment.driver_id)
      return unless driver.current_shipment_id == shipment.id

      mileage = rand(5.0..50.0).round(2)
      driver.update!(current_shipment_id: nil, total_mileage: driver.total_mileage + mileage)
    end
    private_class_method :release_driver!
  end
end
