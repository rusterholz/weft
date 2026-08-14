# frozen_string_literal: true

module Logistics
  # SSE-powered shipments card for an order detail page. Pushes updated
  # shipment data every 5 seconds. OOB-swaps the order header alongside
  # each push so the status badge and advance button stay current.
  # The title derives from the shipment count, feeding Card's inherited
  # header reader through the bag.
  class ShipmentsCard < DropshipUI::Card
    builder_method :shipments_card

    param :order_id, type: :string

    # The outage check makes this the demo's push-recovery exercise: while
    # the drill is active, every push fails and the stream walks the recovers
    # chain (gem default → app ErrorComponent) instead of updating.
    derives(:shipments) do |p|
      Logistics::ShipmentFeedOutage.check!
      Logistics::Shipment.for_order(p.order_id).includes(:warehouse)
    end
    derives(:title) { |p| "Shipments (#{p.shipments.size})" }

    pushes every: 5
    brings Oms::OrderHeader

    def build(attributes = {})
      super
      shipment_table shipments: params.shipments
    end
  end
end
