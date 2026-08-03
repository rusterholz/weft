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
  def count_selects(table)
    count = 0
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql].to_s.match?(/\ASELECT\b/i) && payload[:sql].include?(table)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  private

  def weft_request(method, path, params, headers)
    app = Weft::Router.new(PASS_THROUGH)
    Rack::MockRequest.new(app).public_send(method, path, { params: params, "HTTP_HX_REQUEST" => "true" }.merge(headers))
  end
end
