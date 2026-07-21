# frozen_string_literal: true

module Delivery
  class DriverRow < Weft::Component
    builder_method :driver_row

    receives :driver

    def build(attributes = {})
      super

      td { a params.driver.name, href: "/drivers/#{params.driver.id}" }
      td do
        if params.driver.current_shipment_id
          status_badge "busy"
        else
          status_badge "available"
        end
      end
      td(class: "mono") do
        if (shipment_id = params.driver.current_shipment_id)
          tooltip(content: Logistics::ShipmentSummary, with: { shipment_id: shipment_id }) do
            a shipment_id[..7], href: "/shipments/#{shipment_id}"
          end
        else
          span("—", class: "text-muted")
        end
      end
      td(class: "mono") { text_node format("%.1f", params.driver.total_mileage) }
    end

    def tag_name
      "tr"
    end
  end
end
