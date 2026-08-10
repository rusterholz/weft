# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::EditableOrderHeader, type: :component do
  let(:order) { Oms::Order.create!(customer_name: "Acme Corp", lat: 0.0, lon: 0.0, status: "submitted") }

  def render_editor(wire: { "order_id" => order.id }, assigns: { order: order })
    render_weft_html(assigns, wire: wire) { editable_order_header }
  end

  it "prefills the customer name from the order" do
    expect(render_editor).to include('value="Acme Corp"')
  end

  it "echoes what the user typed back instead of the stored name" do
    html = render_editor(wire: { "order_id" => order.id, "customer_name" => "Typed Co" })
    expect(html).to include('value="Typed Co"')
  end

  it "wires the form to the save action with the order id riding along" do
    html = render_editor
    expect(html).to include('hx-post="/_components/oms/editable_order_header/save"')
    expect(html).to include(%(name="order_id"))
    expect(html).to include(%(name="customer_name"))
  end

  it "hands the region back to the read-only header on save and on cancel" do
    expect(described_class.actions[%i[save post]].renders).to eq(Oms::OrderHeader)
    expect(described_class.actions[%i[cancel post]].renders).to eq(Oms::OrderHeader)
  end

  it "writes the new name" do
    run_action(described_class, :save, order_id: order.id, customer_name: "Globex")

    expect(order.reload.customer_name).to eq("Globex")
  end

  it "refuses a blank name" do
    expect do
      run_action(described_class, :save, order_id: order.id, customer_name: "  ")
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(order.reload.customer_name).to eq("Acme Corp")
  end

  it "recovers a validation failure as a 422 carrying the message" do
    entry = described_class.recovery_for(ActiveRecord::RecordInvalid.new(Oms::Order.new))
    expect(entry[:status]).to eq(422)
    expect(entry[:block]).not_to be_nil
  end

  it "shows the error message when a recovery hands one back" do
    html = render_editor(wire: { "order_id" => order.id, "error_message" => "Customer name can't be blank" })
    expect(html).to include("Customer name can&#39;t be blank")
  end
end
