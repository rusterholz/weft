# frozen_string_literal: true

module Delivery
  # A DropshipUI::StatCard that shows available driver count. Self-refreshes
  # every 10 seconds.
  class AvailableDriversCard < DropshipUI::StatCard
    builder_method :available_drivers_card

    refreshes every: 10

    private

    def stat_label = "Drivers"
    def stat_value = "#{Delivery::Driver.available.count}/#{Delivery::Driver.count}"
    def stat_accent = "available"
  end
end
