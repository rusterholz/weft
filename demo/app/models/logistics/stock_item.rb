# frozen_string_literal: true

module Logistics
  class StockItem < ApplicationRecord
    self.table_name = "logistics_stock_items"

    belongs_to :warehouse, class_name: "Logistics::Warehouse", inverse_of: :stock_items

    before_create { self.id ||= SecureRandom.uuid }
  end
end
