# frozen_string_literal: true

module Oms
  # Inline order detail row, inserted via hx-swap="afterend" on an order table row.
  # Dismissable via the close button — no raw JS needed.
  class OrderInlineDetail < Weft::Component
    builder_method :order_inline_detail

    attribute :order_id

    dismisses :close

    def tag_name
      "tr"
    end

    def build(attributes = {})
      super
      add_class "order-detail"

      order = Oms::Order.includes(:line_items).find(attrs.order_id)
      shipments = Logistics::Shipment.for_order(order.id).includes(:warehouse)

      td(colspan: "7", style: "background:#f8fafc; padding:1rem 1.5rem") do
        div(class: "d-flex justify-content-between align-items-start mb-2") do
          div do
            strong "#{order.customer_name} "
            status_badge order.status
          end
          button "\u00D7", class: "btn btn-sm btn-outline-secondary py-0",
                           action: :close
        end
        dl(class: "row mb-0", style: "font-size:0.8rem") do
          dt("Address", class: "col-sm-2 text-muted")
          dd([order.address_line_1, order.city, order.state, order.zip].compact.join(", "),
             class: "col-sm-4")
          dt("Items", class: "col-sm-1 text-muted")
          dd(order.line_items.map { |li| "#{li.item_type} (#{li.quantity})" }.join(", "),
             class: "col-sm-5")
        end
        if shipments.any?
          div(style: "font-size:0.8rem; margin-top:0.5rem") do
            strong "Shipments: "
            shipments.each_with_index do |s, i|
              text_node ", " if i.positive?
              a(s.id[..7], href: "/shipments/#{s.id}", class: "mono")
              text_node " "
              status_badge s.status
            end
          end
        end
        div(class: "mt-2") do
          a "View full details \u2192", href: "/orders/#{order.id}",
                                        class: "text-decoration-none", style: "font-size:0.8rem"
        end
      end
    end
  end
end
