# frozen_string_literal: true

module Delivery
  class DriversPage < ::ApplicationPage
    self.page_path = "/drivers"

    param :page, type: :integer

    title "Drivers"

    def build(attributes = {})
      super
      div(class: "page-header") { h1 "Drivers" }
      drivers_panel
    end

    private

    def current_path = "/drivers"
  end
end
