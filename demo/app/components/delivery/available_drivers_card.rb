# frozen_string_literal: true

module Delivery
  # A DropshipUI::StatCard that shows available driver count. Self-refreshes
  # every 10 seconds.
  class AvailableDriversCard < DropshipUI::StatCard
    builder_method :available_drivers_card

    derives(:label) { |_p| "Drivers" }
    derives(:value) { |_p| "#{Delivery::Driver.available.count}/#{Delivery::Driver.count}" }
    derives(:accent) { |_p| "available" }

    refreshes every: 10
  end
end
