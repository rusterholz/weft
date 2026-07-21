# frozen_string_literal: true

# Operations dashboard: stat cards across all three domains plus the
# recent-orders feed. Cross-domain composition, so lives at the app
# top level rather than under any one domain namespace.
class DashboardPage < ApplicationPage
  self.page_path = "/"

  def build(attributes = {})
    super

    div(class: "page-header") { h1 "Dashboard" }

    div(class: "row g-3 mb-4") do
      %w[submitted processing shipped fulfilled].each do |status|
        div(class: "col") do
          order_status_card status: status
        end
      end
      div(class: "col") do
        available_drivers_card
      end
    end

    recent_orders_card
  end
end
