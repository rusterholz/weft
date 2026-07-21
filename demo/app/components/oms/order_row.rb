# frozen_string_literal: true

module Oms
  class OrderRow < Weft::Component
    builder_method :order_row

    receives :order

    def build(attributes = {})
      super
      shipment_count = Logistics::Shipment.for_order(params.order.id).count

      td(style: "width:2rem") do
        button "▸", class: "btn btn-sm btn-link p-0",
                    inline_expand: Oms::OrderInlineDetail,
                    with: { order_id: params.order.id },
                    target: "closest tr"
      end
      td(class: "mono") { a params.order.id[..7], href: "/orders/#{params.order.id}" }
      td params.order.customer_name
      td(class: "mono") { text_node params.order.line_items.size.to_s }
      td(class: "mono") { text_node shipment_count.to_s }
      td { status_badge params.order.status }
      td(class: "mono") { text_node params.order.created_at&.strftime("%H:%M:%S") }
    end

    def tag_name
      "tr"
    end
  end
end
