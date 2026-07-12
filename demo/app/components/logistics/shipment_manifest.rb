# frozen_string_literal: true

module Logistics
  # Tooltip content: line items in a shipment. Auto-routes at
  # /_components/logistics/shipment_manifest?shipment_id=...
  class ShipmentManifest < Weft::Component
    builder_method :shipment_manifest

    attribute :shipment_id

    def build(attributes = {})
      super
      shipment = Logistics::Shipment.find(attrs.shipment_id)
      items = shipment.items || []
      if items.empty?
        div { text_node "No items in this shipment." }
      else
        dl(class: "mb-0") do
          items.each do |item|
            dt(class: "mono") { text_node item["type"].to_s }
            dd(class: "mono") { text_node "× #{item['qty']}" }
          end
        end
      end
    end
  end
end
