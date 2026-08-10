# frozen_string_literal: true

require "spec_helper"

# The demo's first request-level spec. Component specs can show what a class
# renders; only a whole response shows who owns it — which companions ride
# along, which stay home, and what status comes back.
RSpec.describe "Order header edit round trip", type: :request do
  let(:order) do
    Oms::Order.create!(customer_name: "Acme Corp", lat: 0.0, lon: 0.0, status: "processing")
  end

  def oob_ids(body) = body.scan(/id="([^"]+)"[^>]*hx-swap-oob/).flatten

  describe "POST the edit transfer" do
    subject(:response) { weft_post("/_components/oms/order_header/edit", params: { "order_id" => order.id }) }

    it "answers with the editor, not the header that declared the action" do
      expect(response.status).to eq(200)
      expect(response.body).to include(%(id="oms-editable-order-header-#{order.id}"))
      expect(response.body).not_to include(%(id="oms-order-header-#{order.id}"))
    end

    it "prefills the form from the order the header handed over" do
      expect(response.body).to include('value="Acme Corp"')
    end

    it "carries no companions — the editor declares none, and the header's are not consulted" do
      expect(oob_ids(response.body)).to be_empty
    end

    # Opening the editor runs no callable, so the only load is the editor's
    # own derive. Contrast the save leg below, where one load serves three.
    it "loads the order exactly once" do
      selects = count_selects("oms_orders") { response }
      expect(selects).to eq(1)
    end

    it "announces the hand-off, and only the hand-off" do
      expect(response.headers["HX-Trigger"]).to eq("order-editing")
    end
  end

  describe "POST the save transfer" do
    subject(:response) do
      weft_post("/_components/oms/editable_order_header/save",
                params: { "order_id" => order.id, "customer_name" => "Globex" })
    end

    it "answers with the read-only header, showing the new name" do
      expect(response.status).to eq(200)
      expect(response.body).to include(%(id="oms-order-header-#{order.id}"))
      expect(response.body).to include("Globex")
      expect(order.reload.customer_name).to eq("Globex")
    end

    it "brings the details card along out of band, because it shows the name too" do
      expect(oob_ids(response.body)).to include("oms-order-details-card-#{order.id}")
      expect(response.body).to include("Globex").twice
    end

    it "leaves the shipments card home — its inclusion is filtered to :advance" do
      expect(oob_ids(response.body)).not_to include("logistics-shipments-card-#{order.id}")
    end

    it "shares one loaded order across the callable, the header, and the companion" do
      selects = count_selects("oms_orders") { response }
      expect(selects).to eq(1)
    end
  end

  describe "POST the save transfer with a blank name" do
    subject(:response) do
      weft_post("/_components/oms/editable_order_header/save",
                params: { "order_id" => order.id, "customer_name" => "   " })
    end

    it "comes back 422 with the editor still in place and the complaint shown" do
      expect(response.status).to eq(422)
      expect(response.body).to include(%(id="oms-editable-order-header-#{order.id}"))
      expect(response.body).to include("Customer name can&#39;t be blank")
      expect(order.reload.customer_name).to eq("Acme Corp")
    end

    it "keeps what the user typed rather than reverting the field" do
      expect(response.body).to include('value="   "')
    end
  end

  describe "POST the cancel transfer" do
    subject(:response) do
      weft_post("/_components/oms/editable_order_header/cancel", params: { "order_id" => order.id })
    end

    it "hands the region back to the header, unchanged" do
      expect(response.status).to eq(200)
      expect(response.body).to include(%(id="oms-order-header-#{order.id}"))
      expect(response.body).to include("Acme Corp")
    end

    it "still refreshes the details card — `when: :transferred` names the arrival, not the reason" do
      expect(oob_ids(response.body)).to include("oms-order-details-card-#{order.id}")
    end
  end

  describe "POST the header's own advance action" do
    subject(:response) { weft_post("/_components/oms/order_header/advance", params: { "order_id" => order.id }) }

    it "re-renders the header itself and brings the shipments card" do
      expect(response.status).to eq(200)
      expect(response.body).to include(%(id="oms-order-header-#{order.id}"))
      expect(oob_ids(response.body)).to include("logistics-shipments-card-#{order.id}")
    end

    it "leaves the details card home — its inclusion is filtered to transfer arrivals" do
      expect(oob_ids(response.body)).not_to include("oms-order-details-card-#{order.id}")
    end

    # The details card subscribes to this event, which is how it hears about
    # a status change it wasn't included in. It must not hear about an edit.
    it "announces the status change, and only the status change" do
      expect(response.headers["HX-Trigger"]).to eq("order-updated")
    end

    # The callable reads the same `derives(:order)` the header renders from,
    # so the order is loaded once for the whole response rather than once by
    # the action and again by the render it precedes.
    it "loads the order once for the callable and the re-render together" do
      selects = count_selects("oms_orders") { response }
      expect(selects).to eq(1)
    end
  end
end
