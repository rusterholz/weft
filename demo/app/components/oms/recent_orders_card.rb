# frozen_string_literal: true

module Oms
  # A DropshipUI::Card that shows the most recent orders. Subclasses Card
  # so "this is a kind of card" is structural Ruby — no extra wrapper div;
  # the header values are statically defined into the bag, where Card's
  # readers find them.
  class RecentOrdersCard < DropshipUI::Card
    builder_method :recent_orders_card

    defines title: "Recent Orders", link_text: "View all", link_href: "/orders"

    refreshes every: 10

    def build(attributes = {})
      super
      order_table orders: Oms::Order.order(created_at: :desc).limit(10).includes(:line_items)
    end
  end
end
