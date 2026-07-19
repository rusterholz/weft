# frozen_string_literal: true

module Oms
  # Inline order detail row, inserted via hx-swap="afterend" on an order table row.
  # Dismissable via the close button — no raw JS needed.
  class OrderInlineDetail < Weft::Component
    builder_method :order_inline_detail

    param :order_id

    derives(:order) { |p| Oms::Order.includes(:line_items).find(p.order_id) }
    derives(:shipments) { |p| Logistics::Shipment.for_order(p.order.id).includes(:warehouse) }

    dismisses :close

    def tag_name
      "tr"
    end

    def build(attributes = {})
      super
      add_class "order-detail"

      td(colspan: "7", style: "background:#f8fafc; padding:1rem 1.5rem") do
        render_header_row
        render_details_dl
        render_shipments_line if params.shipments.any?
        render_details_link
      end
    end

    private

    def render_header_row
      div(class: "d-flex justify-content-between align-items-start mb-2") do
        div do
          strong "#{params.order.customer_name} "
          status_badge params.order.status
        end
        button "×", class: "btn btn-sm btn-outline-secondary py-0",
                    action: :close
      end
    end

    def render_details_dl
      dl(class: "row mb-0", style: "font-size:0.8rem") do
        dt("Address", class: "col-sm-2 text-muted")
        dd([params.order.address_line_1, params.order.city, params.order.state,
            params.order.zip].compact.join(", "), class: "col-sm-4")
        dt("Items", class: "col-sm-1 text-muted")
        dd(params.order.line_items.map { |li| "#{li.item_type} (#{li.quantity})" }.join(", "),
           class: "col-sm-5")
      end
    end

    def render_shipments_line
      div(style: "font-size:0.8rem; margin-top:0.5rem") do
        strong "Shipments: "
        params.shipments.each_with_index do |s, i|
          text_node ", " if i.positive?
          a(s.id[..7], href: "/shipments/#{s.id}", class: "mono")
          text_node " "
          status_badge s.status
        end
      end
    end

    def render_details_link
      div(class: "mt-2") do
        a "View full details →", href: "/orders/#{params.order.id}",
                                 class: "text-decoration-none", style: "font-size:0.8rem"
      end
    end
  end
end
