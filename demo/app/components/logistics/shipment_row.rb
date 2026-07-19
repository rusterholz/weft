# frozen_string_literal: true

module Logistics
  class ShipmentRow < Weft::Component
    builder_method :shipment_row

    receives :shipment

    def build(attributes = {})
      super
      driver = Delivery::Driver.find_by(id: params.shipment.driver_id)

      td(class: "mono") { a params.shipment.id[..7], href: "/shipments/#{params.shipment.id}" }
      td params.shipment.warehouse.name
      td(class: "mono") do
        tooltip(content: Logistics::ShipmentManifest, with: { shipment_id: params.shipment.id }) do
          text_node params.shipment.item_count.to_s
        end
      end
      td { driver ? a(driver.name, href: "/drivers/#{driver.id}") : span("—", class: "text-muted") }
      td { status_badge params.shipment.status }
    end

    def tag_name
      "tr"
    end
  end
end
