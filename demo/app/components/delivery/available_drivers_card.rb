# frozen_string_literal: true

module Delivery
  # A DropshipUI::StatCard that shows available driver count. Self-refreshes
  # every 10 seconds.
  class AvailableDriversCard < DropshipUI::StatCard
    builder_method :available_drivers_card

    refreshes every: 10

    def build(attributes = {})
      attributes[:label] = "Drivers"
      attributes[:value] = "#{Delivery::Driver.available.count}/#{Delivery::Driver.count}"
      attributes[:accent] = "available"
      super
    end
  end
end
