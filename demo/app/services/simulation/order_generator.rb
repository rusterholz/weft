# frozen_string_literal: true

module Simulation
  # Creates a random order with random line items from the catalog.
  module OrderGenerator
    ITEM_CATALOG = %w[
      wireless-mouse usb-c-hub laptop-stand mechanical-keyboard monitor-arm
      webcam headset desk-lamp cable-organizer mouse-pad usb-drive
      power-strip tablet-stylus phone-charger screen-protector
    ].freeze

    CUSTOMERS = [
      "Lena Park", "Marcus Webb", "Sofia Reyes", "Jake Thornton", "Priya Kapoor",
      "Owen McBride", "Nia Okafor", "Ravi Sharma", "Hazel Kim", "Diego Fuentes"
    ].freeze

    def self.call
      customer = CUSTOMERS.sample
      item_types = ITEM_CATALOG.sample(rand(2..6))

      ActiveRecord::Base.transaction do
        order = Oms::Order.create!(
          customer_name: customer,
          address_line_1: "#{rand(100..999)} #{%w[Main Oak Elm Pine Maple].sample} St", # rubocop:disable Naming/VariableNumber
          city: %w[Springfield Riverside Fairview Madison].sample,
          state: "CA",
          zip: format("%05d", rand(90000..99999)),
          lat: rand(-9.0..9.0).round(1),
          lon: rand(-9.0..9.0).round(1)
        )

        item_types.each do |item_type|
          Oms::LineItem.create!(order: order, item_type: item_type, quantity: 1)
        end

        order
      end
    end
  end
end
