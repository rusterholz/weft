# frozen_string_literal: true

require "sinatra/base"

require "weft/context"
require "weft/params"
require "weft/params/assembly"
require "weft/request"
require "weft/request/event_frame"

module Weft
  # Rendering a component or page on its own, outside a request weft is
  # serving: in a test, a console, anywhere a string of HTML is wanted.
  module Rendering
    # Render this class as an HTML string, for +request+ with +wire+.
    #
    # +wire+ is a Hash of values as a request would send them, layered over
    # the request's own (a page's route params included), or a Weft::Params,
    # which this class branches from as a child branches its parent's, the
    # request's wire left aside. +request+ is a Weft::Request, a Rack or
    # Sinatra request, a Rack env, or nil for an empty request.
    #
    #   OrderCard.render({ status: "shipped" }, nil)
    #   OrderPage.render({ tab: "items" }, Rack::MockRequest.env_for("/orders/42"))
    def render(wire, request)
      klass = self
      weft_request = Weft::Request.wrap(request)
      root = render_root(wire, weft_request)
      frame = Weft::Request::EventFrame.new(weft_request)
      Weft::Context.new(frame: frame, branch_bag: root) { insert_tag(klass) }.to_s
    end

    private

    def render_root(wire, request)
      return wire if wire.is_a?(Weft::Params)
      raise ArgumentError, "wire must be a Hash or a Weft::Params, got #{wire.inspect}" unless wire.is_a?(Hash)

      own = Sinatra::IndifferentHash[request.send(:universe)].merge(route_params_in(request.path))
      Weft::Params::Assembly.empty(own.merge(wire))
    end

    # The path params this class's route reads out of +path+; none for a
    # class without one.
    def route_params_in(_path) = {}
  end
end
