# frozen_string_literal: true

module Oms
  # A DropshipUI::StatCard that queries the order count for a given
  # status. Self-refreshes every 10 seconds. The status is a dual-source
  # key: embedded cards get it handed at the call site, and it serializes
  # as a wire param so the refresh reconstructs it standalone.
  class OrderStatusCard < DropshipUI::StatCard
    builder_method :order_status_card

    param :status
    receives :status

    refreshes every: 10

    private

    def stat_label = params.status.to_s.capitalize
    def stat_value = Oms::Order.where(status: params.status).count
    def stat_accent = params.status
  end
end
