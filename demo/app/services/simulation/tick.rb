# frozen_string_literal: true

module Simulation
  # One "advance the world" pass. Finds entities at each lifecycle stage
  # and advances them one step. Called by clockwork on each tick.
  #
  # Each stage processes a limited batch to avoid doing too much in one tick
  # and to create a visible pipeline effect.
  module Tick
    BATCH_SIZE = 3

    def self.call
      # Process in reverse-lifecycle order so downstream stages clear first,
      # making room for upstream entities to advance.
      Restock.call
      complete_deliveries
      dispatch_shipments
      pack_shipments
      prepare_orders
    end

    def self.complete_deliveries
      Logistics::Shipment.by_status("in_transit").limit(BATCH_SIZE).each do |shipment|
        Logistics::CompleteDelivery.call(shipment)
      end
    end
    private_class_method :complete_deliveries

    def self.dispatch_shipments
      Logistics::Shipment.by_status("packed").limit(BATCH_SIZE).each do |shipment|
        Logistics::DispatchShipment.call(shipment)
      end
    end
    private_class_method :dispatch_shipments

    def self.pack_shipments
      Logistics::Shipment.by_status("planned").limit(BATCH_SIZE).each do |shipment|
        Logistics::PackShipment.call(shipment)
      end
    end
    private_class_method :pack_shipments

    def self.prepare_orders
      Oms::Order.by_status("submitted").limit(BATCH_SIZE).each do |order|
        Oms::PrepareOrder.call(order)
      end
    end
    private_class_method :prepare_orders
  end
end
