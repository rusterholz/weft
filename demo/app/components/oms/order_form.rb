# frozen_string_literal: true

module Oms
  # Order creation form. Renders as a Weft component so the submit flow
  # is a `performs :create` callable + `Weft::Redirect` to Oms::OrderDetailPage.
  # Form fields map 1:1 to declared attributes; the items field is a
  # hash of item_type => quantity (browsers submit items[#{type}] as nested
  # params; Sinatra hands it back as a hash).
  class OrderForm < Weft::Component
    builder_method :order_form

    param :customer_name
    param :address_line_1 # rubocop:disable Naming/VariableNumber
    param :city
    param :state
    param :zip
    # Complex param types (Hash, Array) get first-class support in
    # v1.x. For v0.x the Resolver passes hashes through unchanged so
    # nested form fields like items[widget]=2 land here as a hash.
    param :items
    param :error_message

    performs :create do |params|
      items = (params.items || {}).select { |_, qty| qty.to_i.positive? }
      raise Weft::Unprocessable, "Please select at least one item." if items.empty?

      order = ActiveRecord::Base.transaction do
        o = Oms::Order.create!(
          customer_name: params.customer_name,
          address_line_1: params.address_line_1, # rubocop:disable Naming/VariableNumber
          city: params.city,
          state: params.state,
          zip: params.zip,
          lat: rand(-9.0..9.0).round(1),
          lon: rand(-9.0..9.0).round(1)
        )
        items.each do |item_type, qty|
          Oms::LineItem.create!(order: o, item_type: item_type, quantity: qty.to_i)
        end
        o
      end
      Weft.redirect(Oms::OrderDetailPage, order_id: order.id)
    end

    recovers(from: [ActiveRecord::RecordInvalid, Weft::Unprocessable]) do |_params, error|
      { error_message: error.message }
    end

    def build(attributes = {})
      super
      catalog = Simulation::OrderGenerator::ITEM_CATALOG

      div(class: "alert alert-danger") { text_node params.error_message } if params.error_message

      form(action: :create) do
        div(class: "row") do
          div(class: "col-md-6") { customer_fields }
          div(class: "col-md-6") { items_fields(catalog) }
        end

        div(class: "mt-3") do
          input(type: "submit", value: "Create Order", class: "btn btn-primary")
          a "Cancel", href: "/orders", class: "btn btn-link"
        end
      end
    end

    private

    def customer_fields
      div(class: "mb-3") do
        label("Customer Name", for: "customer_name", class: "form-label")
        input(type: "text", name: "customer_name", id: "customer_name",
              class: "form-control", required: "required")
      end
      div(class: "mb-3") do
        label("Address", for: "address_line_1", class: "form-label")
        input(type: "text", name: "address_line_1", id: "address_line_1", class: "form-control")
      end
      div(class: "row") do
        div(class: "col-md-6 mb-3") do
          label("City", for: "city", class: "form-label")
          input(type: "text", name: "city", id: "city", class: "form-control")
        end
        div(class: "col-md-3 mb-3") do
          label("State", for: "state", class: "form-label")
          input(type: "text", name: "state", id: "state", class: "form-control", value: "CA")
        end
        div(class: "col-md-3 mb-3") do
          label("ZIP", for: "zip", class: "form-label")
          input(type: "text", name: "zip", id: "zip", class: "form-control")
        end
      end
    end

    def items_fields(catalog)
      label("Items (set quantity to include)", class: "form-label")
      div(class: "row g-2") do
        catalog.each do |item|
          div(class: "col-6") do
            div(class: "input-group input-group-sm") do
              span(item.tr("-", " ").capitalize, class: "input-group-text flex-grow-1")
              input(type: "number", name: "items[#{item}]", min: "0", max: "99",
                    value: "0", class: "form-control", style: "max-width:4rem")
            end
          end
        end
      end
    end
  end
end
