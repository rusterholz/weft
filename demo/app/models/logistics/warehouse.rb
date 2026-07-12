# frozen_string_literal: true

module Logistics
  class Warehouse < ApplicationRecord
    self.table_name = "logistics_warehouses"

    has_many :stock_items,
             class_name: "Logistics::StockItem",
             foreign_key: :warehouse_id,
             inverse_of: :warehouse,
             dependent: :destroy

    has_many :shipments,
             class_name: "Logistics::Shipment",
             foreign_key: :warehouse_id,
             inverse_of: :warehouse

    before_create { self.id ||= SecureRandom.uuid }
  end
end
