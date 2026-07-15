# frozen_string_literal: true

module Delivery
  class DriverDetailPage < ::ApplicationPage
    self.page_path = "/drivers/:driver_id"

    param :driver_id

    def build(attributes = {})
      driver = Delivery::Driver.find(attributes[:driver_id])
      attributes[:title] ||= driver.name
      attributes[:current_path] = "/drivers"
      super

      driver_header_section(driver_id: driver.id)
      driver_assignment_section(driver_id: driver.id)
      driver_history_section(driver_id: driver.id)
    end
  end
end
