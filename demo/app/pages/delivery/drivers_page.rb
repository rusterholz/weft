# frozen_string_literal: true

module Delivery
  class DriversPage < ::ApplicationPage
    self.page_path = "/drivers"

    param :page

    def build(attributes = {})
      attributes[:title] ||= "Drivers"
      attributes[:current_path] = "/drivers"
      super
      div(class: "page-header") { h1 "Drivers" }
      drivers_panel
    end
  end
end
