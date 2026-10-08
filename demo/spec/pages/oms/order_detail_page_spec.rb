# frozen_string_literal: true

require "rack/mock_request"
require "spec_helper"

RSpec.describe Oms::OrderDetailPage, type: :component do
  let(:order) do
    Oms::Order.create!(customer_name: "Alice", lat: 0.0, lon: 0.0,
                       city: "Springfield", state: "CA", zip: "90210")
  end

  before do
    Oms::LineItem.create!(order: order, item_type: "widget", quantity: 3)
  end

  it "auto-routes at /orders/:order_id" do
    expect(described_class.page_path).to eq("/orders/:order_id")
    expect(described_class).to be_routable
  end

  def rendered = described_class.render({}, Rack::MockRequest.env_for("/orders/#{order.id}"))

  it "renders the order header and customer details" do
    html = rendered
    expect(html).to include(order.id[..7])
    expect(html).to include("Alice")
    expect(html).to include("Springfield")
  end

  it "renders the line items table" do
    html = rendered
    expect(html).to include("Line Items (1)")
    expect(html).to include("widget")
    expect(html).to match(/<td[^>]*>3</)
  end

  # A well-formed uuid that addresses nothing. It has to be well-formed to
  # reach the lookup at all: `type: :uuid` refuses a value that is not a uuid
  # before any query happens, which is the separate claim below.
  it "raises ActiveRecord::RecordNotFound for a well-formed id matching no order" do
    expect { described_class.render({}, Rack::MockRequest.env_for("/orders/00000000-0000-4000-8000-000000000000")) }.
      to raise_error(ActiveRecord::RecordNotFound)
  end

  # The other half, and a different failure entirely: this one never reaches
  # the database. "not a uuid" and "a uuid nobody has" are distinct answers,
  # and conflating them sends an unreadable request to the lookup to find out.
  it "refuses an id that is not a uuid at all, before any lookup" do
    expect { described_class.render({}, Rack::MockRequest.env_for("/orders/wombat")) }.
      to raise_error(Weft::InvalidParamValue, /wombat/)
  end
end
