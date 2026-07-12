# frozen_string_literal: true

require "clockwork"
require_relative "config/environment"

# Quiet AR logging in clockwork — too noisy at DEBUG level
ActiveRecord::Base.logger&.level = Logger::WARN

module Clockwork
  configure do |config|
    config[:logger] = Logger.new($stdout)
    config[:logger].formatter = proc { |_sev, time, _prog, msg| "#{time.strftime('%H:%M:%S')} #{msg}\n" }
  end

  order_interval = Integer(ENV.fetch("ORDER_INTERVAL", 2))
  tick_interval = Integer(ENV.fetch("TICK_INTERVAL", 2))

  every(order_interval, "generate_order") do
    order = Simulation::OrderGenerator.call
    puts "[order] Created Order #{order.id[..7]} for #{order.customer_name} " \
         "(#{order.line_items.size} items)"
  end

  every(tick_interval, "advance_simulation") do
    before = status_snapshot
    Simulation::Tick.call
    after = status_snapshot

    changes = diff_snapshots(before, after)
    if changes.any?
      puts "[tick]  #{changes.join(', ')}"
    else
      puts "[tick]  (no changes)"
    end
  end

  def self.status_snapshot
    {
      orders: Oms::Order.group(:status).count,
      shipments: Logistics::Shipment.group(:status).count,
      drivers_busy: Delivery::Driver.busy.count
    }
  end

  def self.diff_snapshots(before, after) # rubocop:disable Metrics/AbcSize
    changes = []
    %i[orders shipments].each do |kind|
      (before[kind].keys | after[kind].keys).sort.each do |status|
        b = before[kind].fetch(status, 0)
        a = after[kind].fetch(status, 0)
        changes << "#{kind}/#{status}: #{b}→#{a}" if a != b
      end
    end
    b_drv = before[:drivers_busy]
    a_drv = after[:drivers_busy]
    changes << "drivers_busy: #{b_drv}→#{a_drv}" if a_drv != b_drv
    changes
  end
end
