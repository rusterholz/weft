# frozen_string_literal: true

module Oms
  class OrdersPage < ::ApplicationPage
    self.page_path = "/orders"

    param :status
    param :page

    def build(attributes = {})
      attributes[:title] ||= "Orders"
      attributes[:current_path] = "/orders"
      super
      div(class: "page-header d-flex justify-content-between align-items-center") do
        h1 "Orders"
        a "New Order", href: "/orders/new", class: "btn btn-sm btn-primary"
      end
      orders_panel
    end
  end
end
