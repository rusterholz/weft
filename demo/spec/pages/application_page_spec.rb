# frozen_string_literal: true

require "spec_helper"

RSpec.describe ApplicationPage, type: :component do
  it "subclasses DropshipUI::Page" do
    expect(described_class.superclass).to eq(DropshipUI::Page)
  end

  it "is marked abstract" do
    expect(described_class).not_to be_routable
  end

  it "maps ActiveRecord::RecordNotFound to the branded NotFoundPage as a 404" do
    entry = described_class.recovery_for(ActiveRecord::RecordNotFound.new("nope"))
    # A Class target (not the gem-default's Symbol knob indirection) proves the
    # explicit declaration; status: supplies the wire semantics AR's error lacks.
    expect(entry[:with]).to eq(NotFoundPage)
    expect(entry[:status]).to eq(404)
  end

  it "inherits the company default title from DropshipUI::Page" do
    html = render_arbre_html { application_page }
    expect(html).to include("<title>Dropship Co.</title>")
  end

  it "renders with the gem-emitted htmx-ext-sse script (registered components push)" do
    html = render_arbre_html { application_page }
    expect(html).to include("htmx-ext-sse")
  end

  it "renders the navbar with all five navigable sections" do
    html = render_arbre_html { application_page }
    expect(html).to include('class="navbar-brand"')
    ["Dashboard", "Orders", "Shipments", "Drivers", "Error Drills"].each do |label|
      expect(html).to include(label)
    end
  end

  it "marks the current_path nav link as active" do
    page_class = Class.new(described_class) do
      def self.name = "NavStubPage"
      def current_path = "/orders"
    end
    html = render_arbre_html { insert_tag(page_class) }
    expect(html).to include('class="nav-link active" href="/orders"')
  end

  it "redirects block content into the main container" do
    html = render_arbre_html { application_page { h1 "Welcome" } }
    expect(html).to match(/container-fluid.*Welcome/m)
  end
end
