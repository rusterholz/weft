# frozen_string_literal: true

module Oms
  # The order header's edit state. `Oms::OrderHeader` hands this class
  # responsibility for the region via `transfers :edit`, and this class hands
  # it back on save or cancel. The two reference each other in their class
  # bodies, which is fine in both load orders: `class Oms::OrderHeader`
  # defines the constant before its body runs, so whichever loads first, the
  # other resolves to a class object that `transfers` only needs to store.
  class EditableOrderHeader < Weft::Component
    builder_method :editable_order_header

    param :order_id, type: :string
    param :customer_name, type: :string
    param :error_message, type: :string

    derives(:order) { |p| Oms::Order.find(p.order_id) }

    transfers :save, to: Oms::OrderHeader do |params|
      order = Oms::Order.find(params.order_id)
      order.update!(customer_name: params.customer_name.to_s.strip)
      { order: order }
    end

    transfers :cancel, to: Oms::OrderHeader

    # `status:` declares what this edge means on the wire — the declaration
    # site's call, not a fallback. ActiveRecord::RecordInvalid carries no
    # status of its own and would otherwise report 500; naming 422 here says
    # both branches of the array mean the same thing.
    recovers from: [ActiveRecord::RecordInvalid, Weft::Unprocessable], status: 422 do |_params, error|
      { error_message: error.message }
    end

    def build(attributes = {})
      super
      add_class "page-header"

      para(params.error_message, class: "text-danger mb-2", style: "font-size:0.875rem") if params.error_message
      form(action: :save, class: "d-flex align-items-center gap-2") do
        input type: "hidden", name: "order_id", value: params.order_id
        label "Customer", for: "customer_name", class: "text-muted", style: "font-size:0.875rem"
        input type: "text", name: "customer_name", id: "customer_name", class: "form-control form-control-sm",
              style: "max-width:18rem", value: current_name
        input type: "submit", value: "Save", class: "btn btn-sm btn-primary"
        button "Cancel", type: "button", class: "btn btn-sm btn-outline-secondary", action: :cancel
      end
    end

    private

    # What the user typed wins over the stored value, so a rejected save
    # doesn't silently discard their edit.
    def current_name = params.customer_name || params.order.customer_name
  end
end
