# frozen_string_literal: true

class CreateOmsTables < ActiveRecord::Migration[8.0]
  def change
    create_table :oms_orders, id: :string, force: :cascade do |t|
      t.string :customer_name, null: false
      t.string :address_line_1
      t.string :city
      t.string :state
      t.string :zip
      t.decimal :lat, precision: 5, scale: 1, null: false
      t.decimal :lon, precision: 5, scale: 1, null: false
      t.string :status, default: "submitted", null: false
      t.timestamps
    end

    create_table :oms_line_items, id: :string, force: :cascade do |t|
      t.string :order_id, null: false
      t.string :item_type, null: false
      t.integer :quantity, default: 1, null: false
      t.index :order_id
    end
  end
end
