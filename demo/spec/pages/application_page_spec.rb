# frozen_string_literal: true

require "spec_helper"

RSpec.describe ApplicationPage, type: :component do
  it "subclasses DropshipUI::Page" do
    expect(described_class.superclass).to eq(DropshipUI::Page)
  end

  it "is marked abstract" do
    expect(described_class).not_to be_routable
  end

  it "inherits the company default title from DropshipUI::Page" do
    html = render_arbre_html { application_page }
    expect(html).to include("<title>Dropship Co.</title>")
  end

  it "renders with the gem-emitted htmx-ext-sse script (registered components push)" do
    html = render_arbre_html { application_page }
    expect(html).to include("htmx-ext-sse")
  end

  it "renders the navbar with all four navigable sections" do
    html = render_arbre_html { application_page }
    expect(html).to include('class="navbar-brand"')
    %w[Dashboard Orders Shipments Drivers].each do |label|
      expect(html).to include(label)
    end
  end

  it "marks the current_path nav link as active" do
    html = render_arbre_html { application_page current_path: "/orders" }
    expect(html).to include('class="nav-link active" href="/orders"')
  end

  it "redirects block content into the main container" do
    html = render_arbre_html { application_page { h1 "Welcome" } }
    expect(html).to match(/container-fluid.*Welcome/m)
  end
end
