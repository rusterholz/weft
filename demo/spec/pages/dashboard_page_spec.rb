# frozen_string_literal: true

require "spec_helper"

RSpec.describe DashboardPage, type: :component do
  it "auto-routes at /" do
    expect(described_class.page_path).to eq("/")
    expect(described_class).to be_routable
  end

  it "inherits from the app's ApplicationPage" do
    expect(described_class.superclass).to eq(ApplicationPage)
  end

  def rendered
    klass = described_class
    render_weft_html { insert_tag(klass) }
  end

  it "renders the dashboard heading" do
    expect(rendered).to include("Dashboard")
  end

  it "renders stat cards for each order status" do
    html = rendered
    %w[Submitted Processing Shipped Fulfilled].each do |label|
      expect(html).to include(label)
    end
  end

  it "renders the recent orders card" do
    expect(rendered).to include("Recent Orders")
  end

  it "renders the navbar from ApplicationPage" do
    html = rendered
    expect(html).to include("Dropship Co.")
    expect(html).to include('href="/orders"')
  end
end
