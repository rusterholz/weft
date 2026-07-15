# frozen_string_literal: true

require "bundler/setup"
require "active_record"
require "zeitwerk"
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

# Zeitwerk handles constant autoloading for app/components, app/pages,
# app/models, and app/services. One loader, one mental model — no
# explicit require chains, no Dir.glob ordering. Cross-namespace
# references (e.g. Logistics::ShipmentsCard's `includes Oms::OrderHeader`)
# resolve lazily on first use, so load order is no longer a concern.
loader = Zeitwerk::Loader.new
loader.push_dir(File.join(APP_ROOT, "app", "components"))
loader.push_dir(File.join(APP_ROOT, "app", "pages"))
loader.push_dir(File.join(APP_ROOT, "app", "models"))
loader.push_dir(File.join(APP_ROOT, "app", "services"))

# Acronym: dropship_ui/ → DropshipUI:: (not DropshipUi).
loader.inflector.inflect("dropship_ui" => "DropshipUI")

loader.enable_reloading if APP_ENV == "development"
loader.setup
# Eager-load every app class at boot. The Weft::Registry populates via
# the `inherited` hook on Component/Page, and the Router consults the
# Registry at request time — so the classes must be loaded before any
# request lands. (With lazy autoload alone, the first request would
# hit an empty Registry.)
loader.eager_load

if APP_ENV == "development"
  # Pure-Zeitwerk reload on every dev request. The gem's registry prunes
  # superseded classes automatically — it drops any registered class whose
  # constant has been redefined — so reloading stays consistent (collision
  # detection doesn't trip on a reloaded class) and the registry doesn't
  # accumulate stale entries. A more efficient unload-hook integration (evict
  # on Zeitwerk's on_unload, no per-request scan) is planned for the v0.2
  # gem-side Zeitwerk integration.
  Weft::Router.before { loader.reload && loader.eager_load }
end

# Demo-defined Weft preset registrations. Not autoloaded — pure
# side-effect code that runs once at boot.
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
