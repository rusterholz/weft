# frozen_string_literal: true

require "spec_helper"

# A shipments card streams live updates. When a push fails, the stream sends
# the app's error component into the card's slot instead, and that error names
# the card that went quiet, so a page streaming several says which one stopped.
RSpec.describe "A shipments card whose live updates fail", type: :request do
  let(:order) { Oms::Order.create!(customer_name: "Acme", lat: 0.0, lon: 0.0, status: "processing") }

  def first_push
    weft_stream_events("/_components/logistics/shipments_card/_stream", params: { order_id: order.id }).first
  end

  before { allow(Weft.logger).to receive(:error) }

  context "when the shipment feed is down" do
    around do |example|
      Logistics::ShipmentFeedOutage.toggle! unless Logistics::ShipmentFeedOutage.active?
      example.run
    ensure
      Logistics::ShipmentFeedOutage.toggle! if Logistics::ShipmentFeedOutage.active?
    end

    it "says live updates were interrupted and will be retried" do
      expect(first_push).to match(/live updates interrupted/i)
      expect(first_push).to include("Retrying")
    end

    it "falls back to the plain wording, since the card's title is what failed" do
      expect(first_push).not_to include("Shipments (")
    end
  end

  context "when a shipment can't be rendered" do
    before do
      warehouse = Logistics::Warehouse.create!(name: "W1", lat: 0.0, lon: 0.0)
      Logistics::Shipment.create!(order_id: order.id, warehouse: warehouse, status: "planned")
      warehouse.delete
    end

    it "names the card by its own title" do
      expect(first_push).to include("Shipments (1) — interrupted")
    end
  end
end
