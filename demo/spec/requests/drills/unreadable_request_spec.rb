# frozen_string_literal: true

require "spec_helper"

# One step further out than the unreadable-id drill next to it: there a value
# arrived and a declared type refused it, here the query string never became
# keys and values at all. Nothing can be handed back to a form, because
# nothing was read — but it is still the caller's mistake, so it is still a
# 400 rather than the 500 a server fault would report.
#
# Driven through the whole router because the claim is about the status and
# about which page answers, and neither is visible from a component render.
RSpec.describe "unreadable requests", type: :request do
  queries = { "invalid %-encoding" => "q=%", "conflicting param shapes" => "a[]=1&a[b]=2" }.freeze

  queries.each do |description, query|
    it "answers 400 for a query string with #{description}" do
      response = weft_get("/orders?#{query}")

      expect(response.status).to eq(400)
    end
  end

  it "renders the branded page rather than falling to the safety net" do
    response = weft_get("/orders?q=%", headers: { "HTTP_HX_REQUEST" => "false" })

    expect(response.body).to include("Dropship")
    expect(response.body).not_to include("Internal error")
  end

  it "reports the failure as weft's own vocabulary, not the substrate's" do
    body = weft_get("/orders?q=%").body

    expect(body).to include("Weft::UnreadableRequest")
    expect(body).not_to include("Sinatra::BadRequest")
  end

  it "offers the drill on the drills page" do
    body = weft_get("/drills").body

    expect(body).to include("Branded 400 — unreadable request")
  end
end
