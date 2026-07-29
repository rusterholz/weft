# frozen_string_literal: true

module Logistics
  # Toggle for the simulated shipments-feed outage. A self-rerendering
  # control: the toggle action flips the flag and the round-trip re-renders
  # this switch, while the streaming ShipmentsCard above degrades and
  # recovers on its own push cadence.
  class OutageSwitch < Weft::Component
    builder_method :outage_switch

    performs :toggle do |_params|
      Logistics::ShipmentFeedOutage.toggle!
    end

    def build(attributes = {})
      super
      add_class "mb-3"

      if Logistics::ShipmentFeedOutage.active?
        span("Outage active", class: "badge-status badge-busy", style: "margin-right:0.5rem")
        button "End outage", class: "btn btn-sm btn-outline-secondary", action: :toggle
      else
        button "Simulate shipments outage", class: "btn btn-sm btn-outline-secondary", action: :toggle,
                                            confirm: "Break the live shipments feed for every viewer?"
      end
    end
  end
end
