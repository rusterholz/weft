# frozen_string_literal: true

module Delivery
  class DriverAssignmentSection < Weft::Component
    builder_method :driver_assignment_section

    param :driver_id, type: :string

    derives(:driver) { |p| Delivery::Driver.find(p.driver_id) }
    derives(:shipment) { |p| Logistics::Shipment.find_by(id: p.driver.current_shipment_id) }

    refreshes on: "delivery-completed"

    # This section has one action today, so naming it changes nothing — but
    # it says which action the event belongs to, which is what the other two
    # sections are really subscribing to.
    triggers "delivery-completed", on: :complete_delivery

    # `params.shipment` walks the same two-step derivation the build reads:
    # driver from the wire, then that driver's current shipment.
    performs :complete_delivery do |params|
      shipment = params.shipment
      Logistics::CompleteDelivery.call(shipment) if shipment&.status == "in_transit"
    end

    def build(attributes = {})
      super

      if (shipment = params.shipment)
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
