# frozen_string_literal: true

module Oms
  # A DropshipUI::StatCard that queries the order count for a given
  # status. Self-refreshes every 10 seconds; the subclass derives label,
  # value, and accent from the status attr before calling super.
  class OrderStatusCard < DropshipUI::StatCard
    builder_method :order_status_card

    attribute :status

    refreshes every: 10

    def build(attributes = {})
      status = attributes[:status]
      attributes[:label] = status.to_s.capitalize
      attributes[:value] = Oms::Order.where(status: status).count
      attributes[:accent] = status
      super
    end
  end
end
