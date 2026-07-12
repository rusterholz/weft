# frozen_string_literal: true

module Delivery
  class Driver < ApplicationRecord
    self.table_name = "delivery_drivers"

    scope :available, -> { where(current_shipment_id: nil) }
    scope :busy, -> { where.not(current_shipment_id: nil) }
    scope :by_mileage, -> { order(:total_mileage) }

    before_create { self.id ||= SecureRandom.uuid }
  end
end
