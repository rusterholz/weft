# frozen_string_literal: true

class CreateDeliveryTables < ActiveRecord::Migration[8.0]
  def change
    create_table :delivery_drivers, id: :string, force: :cascade do |t|
      t.string :name, null: false
      t.string :current_shipment_id
      t.decimal :total_mileage, precision: 8, scale: 2, default: 0.0, null: false
    end
  end
end
