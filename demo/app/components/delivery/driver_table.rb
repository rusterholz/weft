# frozen_string_literal: true

module Delivery
  class DriverTable < Weft::Component
    builder_method :driver_table

    def build(attributes = {})
      @drivers = attributes.delete(:drivers) || []
      super
      add_class "table table-data mb-0"

      thead do
        tr { %w[Driver Status Assignment Mileage].each { |c| th c } }
      end
      tbody do
        @drivers.each { |d| driver_row(driver: d) }
      end
    end

    def tag_name
      "table"
    end
  end
end
