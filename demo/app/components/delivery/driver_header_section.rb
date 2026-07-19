# frozen_string_literal: true

module Delivery
  class DriverHeaderSection < Weft::Component
    builder_method :driver_header_section

    param :driver_id

    derives(:driver) { |p| Delivery::Driver.find(p.driver_id) }

    refreshes on: "delivery-completed"

    def build(attributes = {})
      super
      add_class "page-header d-flex justify-content-between align-items-center"

      h1 do
        text_node "#{params.driver.name} "
        if params.driver.current_shipment_id
          status_badge "busy"
        else
          status_badge "available"
        end
      end
      div(class: "mono", style: "font-size:0.875rem; color:#64748b") do
        text_node "#{format('%.1f', params.driver.total_mileage)} mi"
      end
    end
  end
end
