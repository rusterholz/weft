# frozen_string_literal: true

require "spec_helper"

# "No such record" and "that is not an id" are different answers, and only one
# of them needs the database to find out. A declared `type: :uuid` refuses the
# second before any lookup runs.
#
# Driven through the whole router rather than a component render, because the
# claim is about the STATUS as well as the body — and because the error path
# re-resolves the same malformed wire hash while reporting the failure, which
# is exactly where a strict coercion could have raised a second time on top of
# the first and masked it.
routes = { "/orders" => "order", "/shipments" => "shipment", "/drivers" => "driver" }.freeze

RSpec.describe "unreadable ids", type: :request do
  # Well-formed and guaranteed absent — it has to be well-formed to reach the
  # lookup at all, which is the whole distinction under test.
  let(:absent_uuid) { "ffffffff-ffff-ffff-ffff-ffffffffffff" }

  routes.each do |base, noun|
    it "answers 400 for a #{noun} id that is not a uuid" do
      response = weft_get("#{base}/wombat")

      expect(response.status).to eq(400)
    end

    it "answers 404 for a well-formed #{noun} id matching no record" do
      response = weft_get("#{base}/#{absent_uuid}")

      expect(response.status).to eq(404)
    end
  end

  it "renders a branded page for the refusal rather than falling to the safety net" do
    response = weft_get("/orders/wombat")

    expect(response.body).to include("Dropship")
    expect(response.body).not_to include("Internal error")
  end

  it "offers both drills on the drills page" do
    body = weft_get("/drills").body

    expect(body).to include("Branded 404 — missing record")
    expect(body).to include("Branded 400 — unreadable id")
  end
end
