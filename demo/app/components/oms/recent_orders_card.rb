# frozen_string_literal: true

module Oms
  # A DropshipUI::Card that shows the most recent orders. Subclasses Card
  # so "this is a kind of card" is structural Ruby — no extra wrapper div.
  class RecentOrdersCard < DropshipUI::Card
    builder_method :recent_orders_card

    refreshes every: 10

    def build(attributes = {})
      attributes[:title] = "Recent Orders"
      attributes[:link_text] = "View all"
      attributes[:link_href] = "/orders"
      super
      order_table orders: Oms::Order.order(created_at: :desc).limit(10).includes(:line_items)
    end
  end
end
