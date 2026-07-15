# frozen_string_literal: true

module Logistics
  # SSE-powered shipments card for an order detail page. Pushes updated
  # shipment data every 5 seconds. OOB-swaps the order header alongside
  # each push so the status badge and advance button stay current.
  class ShipmentsCard < DropshipUI::Card
    builder_method :shipments_card

    param :order_id
    pushes every: 5
    includes Oms::OrderHeader

    def build(attributes = {})
      shipments = Logistics::Shipment.for_order(attributes[:order_id]).includes(:warehouse)
      attributes[:title] = "Shipments (#{shipments.size})"
      super
      shipment_table shipments: shipments
    end
  end
end
