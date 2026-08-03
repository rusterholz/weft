# frozen_string_literal: true

module Oms
  # The order's customer and address, as a card of its own so it can ride
  # an out-of-band swap: editing the customer name on the header lands here
  # too (`includes Oms::OrderDetailsCard, when: :transferred`). Its own
  # `derives` only fires on a standalone render — as a companion it inherits
  # the order the header already loaded.
  class OrderDetailsCard < DropshipUI::Card
    builder_method :order_details_card

    param :order_id, type: :string

    derives(:order) { |p| Oms::Order.find(p.order_id) }

    def build(attributes = {})
      super
      # Carried on the component, not the call site, so the out-of-band
      # swap keeps the spacing the page render had.
      add_class "mb-3"

      dl(class: "row mb-0", style: "font-size:0.875rem") do
        rows.each do |label_text, value|
          dt(label_text, class: "col-sm-3 text-muted")
          dd(value.to_s, class: "col-sm-9")
        end
      end
    end

    private

    def card_title = "Details"

    def rows
      order = params.order
      [["Customer", order.customer_name],
       ["Address", [order.address_line_1, order.city, order.state, order.zip].compact.join(", ")],
       ["Created", order.created_at&.strftime("%Y-%m-%d %H:%M:%S")]]
    end
  end
end
