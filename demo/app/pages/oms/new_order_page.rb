# frozen_string_literal: true

module Oms
  class NewOrderPage < ::ApplicationPage
    self.page_path = "/orders/new"

    def build(attributes = {})
      attributes[:title] ||= "New Order"
      super
      div(class: "page-header") { h1 "New Order" }

      card(title: "Create Order") do
        order_form
      end
    end

    private

    def current_path = "/orders"
  end
end
