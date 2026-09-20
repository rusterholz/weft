# frozen_string_literal: true

require "rack/mock"

# Drives the demo through Weft::Router the way a browser does. Component
# specs render a class in isolation; only a real request shows a whole
# response — the primary render, its out-of-band companions, the status,
# and the HX-* headers together.
#
# Rack::MockRequest ships inside rack, which the demo already depends on
# via Sinatra, so this needs no extra gem.
module RequestHelper
  # Whatever Weft doesn't recognize falls through to the app behind the
  # middleware, exactly as it does in config.ru.
  PASS_THROUGH = ->(_env) { [404, { "content-type" => "text/plain" }, ["passed through"]] }

  def weft_get(path, params: {}, headers: {}) = weft_request(:get, path, params, headers)
  def weft_post(path, params: {}, headers: {}) = weft_request(:post, path, params, headers)

  # SELECTs against one table during a block — the cheap way to pin that a
  # rich value rode an overlay instead of being fetched again downstream.
  #
  # Schema introspection is excluded, and that exclusion is load-bearing:
  # SQLite reads sqlite_master on first touch of a table, naming that table
  # in the query, so counting it makes the result depend on whether some
  # earlier example already warmed the schema. An example that reports 1 in
  # file order then reports 3 run on its own, which reads as a regression.
  def count_selects(table)
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      next if sql.include?("sqlite_master")

      count += 1 if sql.match?(/\ASELECT\b/i) && sql.include?(table)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  private

  # An empty params hash is omitted rather than passed along, and that is not
  # tidiness: given :params at all, Rack::MockRequest parses the query string
  # in order to merge them, so a query weft is meant to refuse as unparseable
  # would raise in the harness before the router ever saw the request.
  def weft_request(method, path, params, headers)
    app = Weft::Router.new(PASS_THROUGH)
    opts = { "HTTP_HX_REQUEST" => "true" }.merge(headers)
    opts[:params] = params if params.any?
    Rack::MockRequest.new(app).public_send(method, path, opts)
  end
end
