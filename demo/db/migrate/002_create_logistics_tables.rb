# frozen_string_literal: true

class CreateLogisticsTables < ActiveRecord::Migration[8.0]
  def change
    create_table :logistics_warehouses, id: :string, force: :cascade do |t|
      t.string :name, null: false
      t.string :address_line_1
      t.string :city
      t.string :state
      t.string :zip
      t.decimal :lat, precision: 5, scale: 1, null: false
      t.decimal :lon, precision: 5, scale: 1, null: false
    end

    create_table :logistics_stock_items, id: :string, force: :cascade do |t|
      t.string :warehouse_id, null: false
      t.string :item_type, null: false
      t.integer :quantity, default: 0, null: false
      t.index :warehouse_id
      t.index %i[warehouse_id item_type], unique: true
    end

    create_table :logistics_shipments, id: :string, force: :cascade do |t|
      t.string :order_id, null: false
      t.string :warehouse_id, null: false
      t.string :driver_id
      t.string :status, default: "planned", null: false
      t.json :items
      t.timestamps
      t.index :order_id
      t.index :warehouse_id
    end
  end
end
