# frozen_string_literal: true

module Logistics
  class ShipmentRow < Weft::Component
    builder_method :shipment_row

    def build(attributes = {})
      @shipment = attributes.delete(:shipment)
      super

      driver = Delivery::Driver.find_by(id: @shipment.driver_id)

      td(class: "mono") { a @shipment.id[..7], href: "/shipments/#{@shipment.id}" }
      td @shipment.warehouse.name
      td(class: "mono") do
        tooltip(content: Logistics::ShipmentManifest, with: { shipment_id: @shipment.id }) do
          text_node @shipment.item_count.to_s
        end
      end
      td { driver ? a(driver.name, href: "/drivers/#{driver.id}") : span("\u2014", class: "text-muted") }
      td { status_badge @shipment.status }
    end

    def tag_name
      "tr"
    end
  end
end
