# frozen_string_literal: true

module Logistics
  class ShipmentsPanel < Weft::Component
    builder_method :shipments_panel

    PER_PAGE = 25

    param :page, default: 1

    def build(attributes = {})
      super

      scope = Logistics::Shipment.order(created_at: :desc).includes(:warehouse)
      page_num = [params.page.to_i, 1].max
      total = scope.count
      records = scope.offset((page_num - 1) * PER_PAGE).limit(PER_PAGE)

      card(title: "All Shipments (#{total})") do
        shipment_table shipments: records
      end
      pager(page_num: page_num, per_page: PER_PAGE, total: total)
    end

    # The page this panel lives on — read by the embedded pager for push_url.
    def page_class = ShipmentsPage
  end
end
