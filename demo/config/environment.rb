# frozen_string_literal: true

require "bundler/setup"
require "active_record"
require "yaml"
require "logger"

APP_ENV = ENV.fetch("APP_ENV", "development")
APP_ROOT = File.expand_path("..", __dir__)

# Database
db_config = YAML.load_file(File.join(__dir__, "database.yml"), aliases: true)
ActiveRecord::Base.establish_connection(db_config[APP_ENV])

if APP_ENV == "development"
  ActiveRecord::Base.logger = Logger.new($stdout)
  ActiveRecord::Base.logger.level = Logger::DEBUG
end

require "weft"

# Weft's gem-managed Zeitwerk loader owns constant autoloading for the app
# dirs — no explicit require chains, no Dir.glob ordering; cross-namespace
# references (e.g. Logistics::ShipmentsCard's `includes Oms::OrderHeader`)
# resolve lazily on first use. It eager-loads on the spot (Weft routes from
# its Registry, populated as classes load), which is why this call precedes
# everything below that references app constants. With reload: true,
# constants reload every dev request; the gem evicts unloaded classes from
# its registry and rebinds class-valued config knobs — so Weft declarations
# belong in class bodies, never in run-once boot files like this one.
Weft.configure_autoloading(
  paths: %w[components pages models services].map { |dir| File.join(APP_ROOT, "app", dir) },
  # Acronym: dropship_ui/ → DropshipUI:: (not DropshipUi).
  inflections: { "dropship_ui" => "DropshipUI" },
  reload: APP_ENV == "development"
)

# Demo-defined Weft preset registrations. Not autoloaded — pure
# side-effect code that runs once at boot (and never re-runs on reload).
require File.join(__dir__, "presets")

# Wire branded error/not-found pages. The gem-default recovers entries on
# Weft::Component and Weft::Page use Symbol form (`with: :error_component`
# etc.) and resolve through Weft.configuration at error-handling time — so
# reassigning these knobs propagates everywhere without re-declaration on
# user classes. Demonstrates the simplest customization path.
Weft.configure do |c|
  c.error_component = ErrorComponent
  c.error_page = ErrorPage
  c.not_found_page = NotFoundPage
  c.static_assets root: "/static", from: File.join(APP_ROOT, "public")
end
