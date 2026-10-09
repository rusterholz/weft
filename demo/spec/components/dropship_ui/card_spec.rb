# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::Card, type: :component do
  let(:greeting) { "Hello" }

  it "renders with content-card class" do
    card = described_class.render_element({}, nil, title: "Recent")
    expect(card.class_list).to include("content-card")
  end

  it "shows the title in the header" do
    html = described_class.render({}, nil, title: "Recent Orders")
    expect(html).to include("Recent Orders")
  end

  it "shows a link when link_text and link_href are provided" do
    html = described_class.render({}, nil, title: "Orders", link_text: "View all", link_href: "/orders")
    expect(html).to include("View all")
    expect(html).to include('href="/orders"')
  end

  it "does not render a link when link_text is absent" do
    html = described_class.render({}, nil, title: "Orders")
    expect(html).not_to include("<a")
  end

  it "redirects block content into the body div" do
    html = described_class.render({}, nil, title: "Test") { para greeting }
    expect(html).to include("content-card-body")
    expect(html).to match(/content-card-body.*Hello/m)
  end
end
