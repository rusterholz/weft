# frozen_string_literal: true

module Oms
  class OrdersPanel < Weft::Component
    builder_method :orders_panel

    PER_PAGE = 25
    FILTER_STATUSES = %w[submitted processing shipped fulfilled].freeze

    param :status
    param :page, default: 1

    # Filter actions — each overrides the status attr and resets to page 1.
    # This is "performs as navigation": no side effects, just state transformation.
    FILTER_STATUSES.each do |s|
      performs(s.to_sym, method: :get) { { status: s, page: 1 } }
    end
    performs(:all, method: :get) { { status: nil, page: 1 } }

    def build(attributes = {})
      super

      scope = Oms::Order.order(created_at: :desc).includes(:line_items)
      scope = scope.where(status: params.status) if params.status.present?
      page_num = [params.page.to_i, 1].max
      total = scope.count
      records = scope.offset((page_num - 1) * PER_PAGE).limit(PER_PAGE)
      filter_label = params.status.present? ? params.status.capitalize : "All"

      render_filters
      card(title: "#{filter_label} Orders (#{total})") do
        order_table orders: records
      end
      pager(page_num: page_num, per_page: PER_PAGE, total: total,
            extra_params: { status: params.status })
    end

    # The page this panel lives on — read by the embedded pager to build
    # push_url, which must survive the panel being re-rendered standalone on
    # pagination (no page in the tree then to introspect).
    def page_class = OrdersPage

    private

    def render_filters
      div(class: "btn-group mb-3", role: "group") do
        render_filter_button("All", action_name: :all, active: params.status.nil?)
        FILTER_STATUSES.each do |s|
          render_filter_button(s.capitalize, action_name: s.to_sym, status_value: s,
                                             active: params.status == s)
        end
      end
    end

    def render_filter_button(label, action_name:, active:, status_value: nil)
      btn_class = "btn btn-sm #{active ? 'btn-primary' : 'btn-outline-secondary'}"
      push_url = status_value ? "/orders?status=#{status_value}" : "/orders"
      button label, action: action_name, class: btn_class, push_url: push_url
    end
  end
end
