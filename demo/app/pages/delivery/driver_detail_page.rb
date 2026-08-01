# frozen_string_literal: true

module Delivery
  class DriverDetailPage < ::ApplicationPage
    self.page_path = "/drivers/:driver_id"

    param :driver_id, type: :string

    derives(:driver) { |p| Delivery::Driver.find(p.driver_id) }

    title { |p| p.driver.name }

    def build(attributes = {})
      super

      driver_header_section
      driver_assignment_section
      driver_history_section
    end

    private

    def current_path = "/drivers"
  end
end
