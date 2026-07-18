# frozen_string_literal: true

module Delivery
  class DriverDetailPage < ::ApplicationPage
    self.page_path = "/drivers/:driver_id"

    param :driver_id

    def build(attributes = {})
      driver = Delivery::Driver.find(params.driver_id)
      attributes[:title] ||= driver.name
      super

      driver_header_section
      driver_assignment_section
      driver_history_section
    end

    private

    def current_path = "/drivers"
  end
end
