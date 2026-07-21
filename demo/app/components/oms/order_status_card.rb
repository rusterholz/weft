# frozen_string_literal: true

module Oms
  # A DropshipUI::StatCard that queries the order count for a given
  # status. Self-refreshes every 10 seconds. The status is a dual-source
  # key (handed when embedded, wire-borne on refresh); the card face
  # derives from it.
  class OrderStatusCard < DropshipUI::StatCard
    builder_method :order_status_card

    param :status
    receives :status

    derives(:label) { |p| p.status.to_s.capitalize }
    derives(:value) { |p| Oms::Order.where(status: p.status).count }
    derives(:accent, &:status)

    refreshes every: 10
  end
end
