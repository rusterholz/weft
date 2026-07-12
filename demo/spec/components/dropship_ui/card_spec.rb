# frozen_string_literal: true

require "spec_helper"

RSpec.describe DropshipUI::Card, type: :component do
  it "renders with content-card class" do
    component = render_arbre { card title: "Recent" }
    expect(component.class_list).to include("content-card")
  end

  it "shows the title in the header" do
    html = render_arbre_html { card title: "Recent Orders" }
    expect(html).to include("Recent Orders")
  end

  it "shows a link when link_text and link_href are provided" do
    html = render_arbre_html { card title: "Orders", link_text: "View all", link_href: "/orders" }
    expect(html).to include("View all")
    expect(html).to include('href="/orders"')
  end

  it "does not render a link when link_text is absent" do
    html = render_arbre_html { card title: "Orders" }
    expect(html).not_to include("<a")
  end

  it "redirects block content into the body div" do
    html = render_arbre_html { card(title: "Test") { para "Hello" } }
    expect(html).to include("content-card-body")
    expect(html).to match(/content-card-body.*Hello/m)
  end
end
