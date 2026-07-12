# frozen_string_literal: true

module Delivery
  class DriverRow < Weft::Component
    builder_method :driver_row

    def build(attributes = {})
      @driver = attributes.delete(:driver)
      super

      td { a @driver.name, href: "/drivers/#{@driver.id}" }
      td do
        if @driver.current_shipment_id
          status_badge "busy"
        else
          status_badge "available"
        end
      end
      td(class: "mono") do
        if @driver.current_shipment_id
          tooltip(content: Logistics::ShipmentSummary, with: { shipment_id: @driver.current_shipment_id }) do
            a @driver.current_shipment_id[..7], href: "/shipments/#{@driver.current_shipment_id}"
          end
        else
          span("\u2014", class: "text-muted")
        end
      end
      td(class: "mono") { text_node format("%.1f", @driver.total_mileage) }
    end

    def tag_name
      "tr"
    end
  end
end
