# frozen_string_literal: true

module Oms
  class OrderDetailPage < ::ApplicationPage
    self.page_path = "/orders/:order_id"

    param :order_id, type: :string

    derives(:order) { |p| Oms::Order.includes(:line_items).find(p.order_id) }

    title { |p| "Order #{p.order.id[..7]}" }

    def build(attributes = {})
      super

      order_header
      order_details_card
      render_line_items_card(params.order)
      return unless Logistics::Shipment.for_order(params.order.id).any?

      shipments_card
      outage_switch
    end

    private

    def current_path = "/orders"

    def render_line_items_card(order)
      card(title: "Line Items (#{order.line_items.size})", class: "mb-3") do
        table(class: "table table-data mb-0") { render_line_items_table(order.line_items) }
      end
    end

    def render_line_items_table(line_items)
      thead { tr { %w[Item Qty].each { |c| th c } } }
      tbody do
        line_items.each do |li|
          tr do
            td li.item_type
            td(class: "mono") { text_node li.quantity.to_s }
          end
        end
      end
    end
  end
end
