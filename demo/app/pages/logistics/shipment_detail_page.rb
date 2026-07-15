# frozen_string_literal: true

module Logistics
  class ShipmentDetailPage < ::ApplicationPage
    self.page_path = "/shipments/:shipment_id"

    param :shipment_id

    def build(attributes = {})
      shipment = Logistics::Shipment.includes(:warehouse).find(attributes[:shipment_id])
      attributes[:title] ||= "Shipment #{shipment.id[..7]}"
      attributes[:current_path] = "/shipments"
      super
      order = Oms::Order.find(shipment.order_id)
      driver = Delivery::Driver.find_by(id: shipment.driver_id)

      render_header(shipment)
      render_details_card(shipment, order, driver)
      render_items_card(shipment.items || [])
    end

    private

    def render_header(shipment)
      div(class: "page-header") do
        h1 do
          text_node "Shipment "
          span(shipment.id[..7], class: "mono")
          text_node " "
          status_badge shipment.status
        end
      end
    end

    def render_details_card(shipment, order, driver) # rubocop:disable Metrics/AbcSize
      card(title: "Details", class: "mb-3") do
        dl(class: "row mb-0", style: "font-size:0.875rem") do
          render_dl_row("Order") { a order.id[..7], href: "/orders/#{order.id}", class: "mono" }
          render_dl_row("Warehouse", shipment.warehouse.name)
          render_dl_row("Driver") { render_driver_value(driver) }
          render_dl_row("Status", shipment.status)
          render_dl_row("Created", shipment.created_at&.strftime("%Y-%m-%d %H:%M:%S"))
        end
      end
    end

    def render_dl_row(label, value = nil, &)
      dt(label, class: "col-sm-3 text-muted")
      if block_given?
        dd(class: "col-sm-9", &)
      else
        dd(value.to_s, class: "col-sm-9")
      end
    end

    def render_driver_value(driver)
      driver ? a(driver.name, href: "/drivers") : span("—", class: "text-muted")
    end

    def render_items_card(items)
      card(title: "Items (#{items.size})") do
        table(class: "table table-data mb-0") { render_items_table_body(items) }
      end
    end

    def render_items_table_body(items)
      thead { tr { %w[Item Qty].each { |c| th c } } }
      tbody do
        items.each do |item|
          tr do
            td(item["type"].to_s)
            td(class: "mono") { text_node item["qty"].to_s }
          end
        end
      end
    end
  end
end
