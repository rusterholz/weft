# frozen_string_literal: true

module Delivery
  class DriverHistorySection < Weft::Component
    builder_method :driver_history_section

    param :driver_id

    derives(:driver) { |p| Delivery::Driver.find(p.driver_id) }
    derives(:completed) do |p|
      Logistics::Shipment.where(driver_id: p.driver.id, status: "delivered").
        order(updated_at: :desc).limit(10)
    end

    refreshes on: "delivery-completed"

    def build(attributes = {})
      super

      card(title: "Delivery History (#{params.completed.size})") do
        if params.completed.any?
          table(class: "table table-data mb-0") do
            thead do
              tr { %w[Shipment Order Warehouse].each { |c| th c } }
            end
            tbody do
              params.completed.each do |s|
                tr do
                  td(class: "mono") { a s.id[..7], href: "/shipments/#{s.id}" }
                  td(class: "mono") { a s.order_id[..7], href: "/orders/#{s.order_id}" }
                  td(s.warehouse&.name || "\u2014")
                end
              end
            end
          end
        else
          div(class: "text-muted", style: "padding:1rem; font-size:0.875rem") do
            text_node "No completed deliveries yet."
          end
        end
      end
    end
  end
end
