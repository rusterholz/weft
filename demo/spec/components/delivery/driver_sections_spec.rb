# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Driver detail sections", type: :component do # rubocop:disable RSpec/DescribeClass
  let(:driver) { Delivery::Driver.create!(name: "Maria Garcia") }

  describe Delivery::DriverHeaderSection do
    it "shows driver name and available badge" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_header_section }
      expect(html).to include("Maria Garcia")
      expect(html).to include("badge-available")
    end

    it "shows busy badge when driver has a shipment" do
      driver.update!(current_shipment_id: "fake-id")
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_header_section }
      expect(html).to include("badge-busy")
    end

    it "includes refresh-on-event attributes" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_header_section }
      expect(html).to include('hx-trigger="delivery-completed from:body"')
      expect(html).to include("hx-get=\"/_components/delivery/driver_header_section?driver_id=#{driver.id}\"")
      expect(html).to include('hx-swap="outerHTML"')
    end
  end

  describe Delivery::DriverAssignmentSection do
    it "shows available message when no shipment" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_assignment_section }
      expect(html).to include("No active assignment")
    end

    it "shows shipment details and complete button when assigned" do
      warehouse = Logistics::Warehouse.create!(name: "West Hub", lat: 1.0, lon: 1.0)
      order = Oms::Order.create!(customer_name: "Test", lat: 1.0, lon: 1.0)
      shipment = Logistics::Shipment.create!(
        order_id: order.id, warehouse: warehouse, status: "in_transit",
        driver_id: driver.id, items: []
      )
      driver.update!(current_shipment_id: shipment.id)
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_assignment_section }
      expect(html).to include(shipment.id[..7])
      expect(html).to include("Complete Delivery")
      expect(html).to include('hx-post="/_components/delivery/driver_assignment_section/complete_delivery"')
    end

    it "includes refresh-on-event listener attributes" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_assignment_section }
      expect(html).to include('hx-trigger="delivery-completed from:body"')
      expect(html).to include("hx-get=\"/_components/delivery/driver_assignment_section?driver_id=#{driver.id}\"")
      expect(html).to include('hx-swap="outerHTML"')
    end
  end

  describe Delivery::DriverHistorySection do
    it "shows empty state when no completed deliveries" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_history_section }
      expect(html).to include("No completed deliveries")
    end

    it "includes refresh-on-event attributes" do
      html = render_weft_html({ driver: driver }, wire: { "driver_id" => driver.id }) { driver_history_section }
      expect(html).to include('hx-trigger="delivery-completed from:body"')
      expect(html).to include("hx-get=\"/_components/delivery/driver_history_section?driver_id=#{driver.id}\"")
      expect(html).to include('hx-swap="outerHTML"')
    end
  end
end
