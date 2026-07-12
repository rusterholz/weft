# frozen_string_literal: true

module Simulation
  # Restocks any warehouse stock items that have dropped to zero.
  # Sets them back to a modest quantity so the simulation can keep flowing.
  # In the real app this would be purchasing/receiving — here it's just
  # keeping the demo alive.
  module Restock
    RESTOCK_QUANTITY = 10

    def self.call
      Logistics::StockItem.where("quantity <= 0").find_each do |stock|
        stock.update!(quantity: RESTOCK_QUANTITY)
      end
    end
  end
end
