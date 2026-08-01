# frozen_string_literal: true

module Logistics
  class ShipmentsPage < ::ApplicationPage
    self.page_path = "/shipments"

    param :page, type: :integer

    title "Shipments"

    def build(attributes = {})
      super
      div(class: "page-header") { h1 "Shipments" }
      shipments_panel
    end

    private

    def current_path = "/shipments"
  end
end
