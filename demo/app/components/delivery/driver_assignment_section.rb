# frozen_string_literal: true

module Delivery
  class DriverAssignmentSection < Weft::Component
    builder_method :driver_assignment_section

    param :driver_id

    derives(:driver) { |p| Delivery::Driver.find(p.driver_id) }
    derives(:shipment) { |p| Logistics::Shipment.find_by(id: p.driver.current_shipment_id) }

    refreshes on: "delivery-completed"
    triggers "delivery-completed"

    performs :complete_delivery do |params|
      driver = Delivery::Driver.find(params.driver_id)
      shipment = Logistics::Shipment.find_by(id: driver.current_shipment_id)
      Logistics::CompleteDelivery.call(shipment) if shipment&.status == "in_transit"
    end

    def build(attributes = {})
      super
      shipment = params.shipment

      if shipment
        card(title: "Current Assignment", class: "mb-3") do
          dl(class: "row mb-0", style: "font-size:0.875rem") do
            dt("Shipment", class: "col-sm-3 text-muted")
            dd(class: "col-sm-9") do
              a shipment.id[..7], href: "/shipments/#{shipment.id}", class: "mono"
              text_node " "
              status_badge shipment.status
            end
            dt("Order", class: "col-sm-3 text-muted")
            dd(class: "col-sm-9") do
              tooltip(content: Logistics::ShipmentSummary, with: { shipment_id: shipment.id }) do
                a shipment.order_id[..7], href: "/orders/#{shipment.order_id}", class: "mono"
              end
            end
            dt("Warehouse", class: "col-sm-3 text-muted")
            dd(shipment.warehouse&.name || "\u2014", class: "col-sm-9")
          end
          if shipment.status == "in_transit"
            div(class: "p-3 pt-0") do
              button "Complete Delivery", class: "btn btn-sm btn-primary",
                                          action: :complete_delivery
            end
          end
        end
      else
        card(title: "Current Assignment", class: "mb-3") do
          div(class: "text-muted", style: "padding:1rem; font-size:0.875rem") do
            text_node "No active assignment \u2014 driver is available."
          end
        end
      end
    end
  end
end
