# frozen_string_literal: true

module Delivery
  # A DropshipUI::StatCard that shows available driver count. Self-refreshes
  # every 10 seconds. The face splits by nature: label and accent are
  # static (defines); the count is computed per render (derives).
  class AvailableDriversCard < DropshipUI::StatCard
    builder_method :available_drivers_card

    defines label: "Drivers", accent: "available"
    derives(:value) { |_p| "#{Delivery::Driver.available.count}/#{Delivery::Driver.count}" }

    refreshes every: 10
  end
end
