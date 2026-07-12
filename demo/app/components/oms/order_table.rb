# frozen_string_literal: true

module Oms
  class OrderTable < Weft::Component
    builder_method :order_table

    def build(attributes = {})
      @orders = attributes.delete(:orders) || []
      super
      add_class "table table-data mb-0"

      thead do
        tr do
          th ""
          %w[Order Customer Items Shipments Status Created].each { |c| th c }
        end
      end
      tbody do
        @orders.each { |o| order_row(order: o) }
      end
    end

    def tag_name
      "table"
    end
  end
end
