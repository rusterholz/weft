# frozen_string_literal: true

require "spec_helper"

# The order header brings the shipments card along when it advances an order.
# While the simulated feed outage is active that card cannot render — and the
# advance still happened. This pins the response that says so.
RSpec.describe "Order header advance with a failing companion", type: :request do
  subject(:response) do
    weft_post("/_components/oms/order_header/advance", params: { "order_id" => order.id })
  end

  let(:order) do
    Oms::Order.create!(customer_name: "Acme Corp", lat: 0.0, lon: 0.0, status: "processing")
  end

  def oob_ids(body) = body.scan(/id="([^"]+)"[^>]*hx-swap-oob/).flatten

  before do
    warehouse = Logistics::Warehouse.create!(name: "West Hub", lat: 1.0, lon: 1.0)
    Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned", items: [])
    Logistics::ShipmentFeedOutage.toggle! unless Logistics::ShipmentFeedOutage.active?
    allow(Weft.logger).to receive(:error)
  end

  after { Logistics::ShipmentFeedOutage.toggle! if Logistics::ShipmentFeedOutage.active? }

  it "reports the success the action actually was" do
    expect(response.status).to eq(200)
  end

  it "commits the advance rather than rolling the response back over it" do
    expect { response }.to change { Logistics::Shipment.for_order(order.id).by_status("packed").count }.by(1)
  end

  it "renders the header itself, updated" do
    expect(response.body).to include(%(id="oms-order-header-#{order.id}"))
    expect(response.body).to include("Acme Corp")
  end

  it "puts the failure in the shipments card's own slot, and nowhere else" do
    expect(oob_ids(response.body)).to eq(["logistics-shipments-card-#{order.id}"])
  end

  it "shows the app's branded error inside that slot" do
    expect(response.body).to include("Something went wrong")
    expect(response.body).to include("shipments feed is unavailable")
  end

  it "still announces the advance — the action is what the event is about" do
    expect(response.headers["HX-Trigger"]).to eq("order-updated")
  end

  it "names the failing companion and its declaration site in the log" do
    response
    expect(Weft.logger).to have_received(:error).
      with(/Logistics::ShipmentsCard companion declared at .+order_header\.rb:\d+ failed to render/)
  end
end
