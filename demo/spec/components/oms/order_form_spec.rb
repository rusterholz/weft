# frozen_string_literal: true

require "spec_helper"

RSpec.describe Oms::OrderForm, type: :component do
  def rendered(attrs = {})
    klass = described_class
    render_weft_html { insert_tag(klass, **attrs) }
  end

  it "renders a form with the magical action: :create expansion" do
    html = rendered
    expect(html).to include('hx-post="/_components/oms/order_form/create"')
    expect(html).to include('action="/_components/oms/order_form/create"')
    expect(html).to include('method="post"')
  end

  it "renders inputs for each customer-detail attribute" do
    html = rendered
    expect(html).to include('name="customer_name"')
    expect(html).to include('name="address_line_1"')
    expect(html).to include('name="city"')
    expect(html).to include('name="state"')
    expect(html).to include('name="zip"')
  end

  it "renders one input per item in the order generator catalog" do
    html = rendered
    Simulation::OrderGenerator::ITEM_CATALOG.each do |item|
      expect(html).to include(%(name="items[#{item}]"))
    end
  end

  it "renders the error_message banner when one is provided" do
    html = rendered(error_message: "Something went wrong")
    expect(html).to include("Something went wrong")
    expect(html).to include("alert-danger")
  end

  it "omits the error banner when no error_message is set" do
    html = rendered
    expect(html).not_to include("alert-danger")
  end
end
