# frozen_string_literal: true

module Oms
  class LineItem < ApplicationRecord
    self.table_name = "oms_line_items"

    belongs_to :order, class_name: "Oms::Order", inverse_of: :line_items

    before_create { self.id ||= SecureRandom.uuid }
  end
end
