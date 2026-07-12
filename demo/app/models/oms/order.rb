# frozen_string_literal: true

module Oms
  class Order < ApplicationRecord
    self.table_name = "oms_orders"

    has_many :line_items,
             class_name: "Oms::LineItem",
             foreign_key: :order_id,
             inverse_of: :order,
             dependent: :destroy

    validates :customer_name, presence: true
    validates :lat, :lon, presence: true, numericality: true

    scope :by_status, ->(status) { where(status: status) }

    before_create { self.id ||= SecureRandom.uuid }
  end
end
