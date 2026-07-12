# frozen_string_literal: true

module Logistics
  class Shipment < ApplicationRecord
    self.table_name = "logistics_shipments"

    belongs_to :warehouse, class_name: "Logistics::Warehouse", inverse_of: :shipments

    scope :for_order, ->(order_id) { where(order_id: order_id) }
    scope :by_status, ->(status) { where(status: status) }

    before_create { self.id ||= SecureRandom.uuid }

    def item_count
      (items || []).sum { |i| i["qty"] || 1 }
    end
  end
end
