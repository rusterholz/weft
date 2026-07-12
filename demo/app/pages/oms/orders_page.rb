# frozen_string_literal: true

module Oms
  class OrdersPage < ::ApplicationPage
    self.page_path = "/orders"

    attribute :status
    attribute :page

    def build(attributes = {})
      attributes[:title] ||= "Orders"
      attributes[:current_path] = "/orders"
      super
      div(class: "page-header d-flex justify-content-between align-items-center") do
        h1 "Orders"
        a "New Order", href: "/orders/new", class: "btn btn-sm btn-primary"
      end
      orders_panel(status: attrs.status, page: attrs.page)
    end
  end
end
