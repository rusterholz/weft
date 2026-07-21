# frozen_string_literal: true

module Delivery
  class DriversPanel < Weft::Component
    builder_method :drivers_panel

    PER_PAGE = 25

    param :page, default: 1

    def build(attributes = {})
      super

      scope = Delivery::Driver.by_mileage
      page_num = [params.page.to_i, 1].max
      total = scope.count
      records = scope.offset((page_num - 1) * PER_PAGE).limit(PER_PAGE)

      card(title: "Driver Roster (#{total})") do
        driver_table drivers: records
      end
      pager(page_num: page_num, per_page: PER_PAGE, total: total)
    end

    # The page this panel lives on — read by the embedded pager for push_url.
    def page_class = DriversPage
  end
end
