# frozen_string_literal: true

module Oms
  # Takes a submitted order and prepares it for shipping:
  # 1. Finds warehouses that stock the needed items
  # 2. Plans shipments (greedy nearest-warehouse assignment)
  # 3. Creates Shipment records and decrements stock
  # 4. Moves order to "processing"
  module PrepareOrder
    def self.call(order)
      return unless order.status == "submitted"

      items_needed = order.line_items.map { |li| { type: li.item_type, qty: li.quantity } }
      plan = plan_shipments(items_needed)
      return if plan.empty?

      ActiveRecord::Base.transaction do
        plan.each do |warehouse_id, items|
          Logistics::Shipment.create!(
            order_id: order.id,
            warehouse_id: warehouse_id,
            status: "planned",
            items: items
          )
          decrement_stock!(warehouse_id, items)
        end
        order.update!(status: "processing")
      end
    end

    # Greedy assignment: for each item, pick the nearest warehouse that has stock.
    # Returns { warehouse_id => [{ type:, qty: }] }
    def self.plan_shipments(items_needed) # rubocop:disable Metrics/AbcSize
      warehouses = Logistics::Warehouse.includes(:stock_items).to_a
      assignment = Hash.new { |h, k| h[k] = [] }

      items_needed.each do |item|
        warehouse = warehouses.find do |w|
          stock = w.stock_items.find { |si| si.item_type == item[:type] }
          stock && stock.quantity >= item[:qty]
        end
        next unless warehouse

        assignment[warehouse.id] << item
      end

      assignment
    end
    private_class_method :plan_shipments

    def self.decrement_stock!(warehouse_id, items)
      items.each do |item|
        stock = Logistics::StockItem.find_by!(warehouse_id: warehouse_id, item_type: item[:type])
        stock.update!(quantity: stock.quantity - item[:qty])
      end
    end
    private_class_method :decrement_stock!
  end
end
