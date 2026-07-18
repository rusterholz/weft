# frozen_string_literal: true

module Logistics
  class ShipmentTable < Weft::Component
    builder_method :shipment_table

    receives :shipments, default: []

    def build(attributes = {})
      super
      add_class "table table-data mb-0"

      thead do
        tr { %w[Shipment Warehouse Items Driver Status].each { |c| th c } }
      end
      tbody do
        params.shipments.each { |s| shipment_row(shipment: s) }
      end
    end

    def tag_name
      "table"
    end
  end
end
