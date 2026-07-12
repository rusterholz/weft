# frozen_string_literal: true

module Oms
  class OrderDetailPage < ::ApplicationPage
    self.page_path = "/orders/:order_id"

    attribute :order_id

    def build(attributes = {})
      order = Oms::Order.includes(:line_items).find(attributes[:order_id])
      attributes[:title] ||= "Order #{order.id[..7]}"
      attributes[:current_path] = "/orders"
      super

      order_header(order_id: order.id)
      render_details_card(order)
      render_line_items_card(order)
      shipments_card(order_id: order.id) if Logistics::Shipment.for_order(order.id).any?
    end

    private

    def render_details_card(order)
      card(title: "Details", class: "mb-3") do
        dl(class: "row mb-0", style: "font-size:0.875rem") do
          [
            ["Customer", order.customer_name],
            ["Address", [order.address_line_1, order.city, order.state, order.zip].compact.join(", ")],
            ["Created", order.created_at&.strftime("%Y-%m-%d %H:%M:%S")]
          ].each do |label_text, value|
            dt(label_text, class: "col-sm-3 text-muted")
            dd(value.to_s, class: "col-sm-9")
          end
        end
      end
    end

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
