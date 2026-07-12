# frozen_string_literal: true

module Logistics
  class ShipmentsPage < ::ApplicationPage
    self.page_path = "/shipments"

    attribute :page

    def build(attributes = {})
      attributes[:title] ||= "Shipments"
      attributes[:current_path] = "/shipments"
      super
      div(class: "page-header") { h1 "Shipments" }
      shipments_panel(page: attrs.page)
    end
  end
end
