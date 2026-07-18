# frozen_string_literal: true

module Oms
  # A DropshipUI::Card that shows the most recent orders. Subclasses Card
  # so "this is a kind of card" is structural Ruby — no extra wrapper div;
  # the header readers are overridden instead of handed over.
  class RecentOrdersCard < DropshipUI::Card
    builder_method :recent_orders_card

    refreshes every: 10

    def build(attributes = {})
      super
      order_table orders: Oms::Order.order(created_at: :desc).limit(10).includes(:line_items)
    end

    private

    def card_title = "Recent Orders"
    def link_text = "View all"
    def link_href = "/orders"
  end
end
