# frozen_string_literal: true

module Logistics
  # Assigns a driver and moves a packed shipment to in_transit.
  # If no driver is available, does nothing (will retry on the next tick).
  module DispatchShipment
    def self.call(shipment)
      return unless shipment.status == "packed"

      driver = Delivery::Driver.available.by_mileage.first
      return unless driver

      ActiveRecord::Base.transaction do
        driver.update!(current_shipment_id: shipment.id)
        shipment.update!(status: "in_transit", driver_id: driver.id)
      end
    end
  end
end
