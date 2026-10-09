# frozen_string_literal: true

require "active_support/core_ext/object/blank"
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
    # Render this class as an HTML string, for +request+ with +wire+, as a
    # builder call with no parent.
    #
    # +wire+ is a Hash of values as a request would send them, layered over
    # the request's own (a page's route params included), or a Weft::Params,
    # which this class branches from as a child branches its parent's, the
    # request's wire left aside. A blank wire is an empty one; anything else
    # is converted with +to_h+. +request+ is a Weft::Request, a Rack or
    # Sinatra request, a Rack env, or nil for an empty request.
    #
    # +kwargs+ and the block are a builder call's: values for the keys this
    # class +receives+, weft's own kwargs, HTML attributes for the wrapper,
    # and content. A block taking no arguments runs where Arbre's builders
    # answer, so a spec can write one inline; one taking arguments goes to
    # +build+. Either way the block's own +self+ is the render's Arbre
    # helpers, so a name nothing in the render answers (a spec's +let+)
    # resolves on it.
    #
    #   OrderCard.render({ status: "shipped" }, nil)
    #   OrderPage.render({ tab: "items" }, Rack::MockRequest.env_for("/orders/42"))
    #   StatCard.render({}, nil, label: "Late", value: 3)
    #   Card.render({}, nil, title: "Totals") { para "42 orders" }
    def render(wire, request, **, &) = render_context(wire, request, **, &).to_s

    # Render as #render does, returning the component itself rather than its
    # HTML, for assertions on the element tree.
    #
    #   card = OrderStatusCard.render_element({}, nil, status: "shipped")
    #   card.class_list # => includes "border-shipped"
    def render_element(wire, request, **, &) = render_context(wire, request, **, &).children.first

    private

    def render_context(wire, request, **kwargs, &block)
      klass = self
      weft_request = Weft::Request.wrap(request)
      root = render_root(wire, weft_request)
      frame = Weft::Request::EventFrame.new(weft_request)
      Weft::Context.new({}, block&.binding&.receiver, frame: frame, branch_bag: root) do
        # Arbre hands a block with parameters to +build+, which passes it the
        # element, and yields any other on its writer's +self+; a spec's +self+
        # has no builders, so only a yielded block moves onto the context.
        content = block
        content = proc { instance_exec(&block) } if block && !block.arity.positive?
        insert_tag(klass, **kwargs, &content)
      end
    end

    def render_root(wire, request)
      return wire if wire.is_a?(Weft::Params)

      own = Sinatra::IndifferentHash[request.send(:universe)].merge(route_params_in(request.path_info))
      Weft::Params::Assembly.empty(own.merge(wire_hash(wire)))
    end

    def wire_hash(wire)
      return {} if wire.blank?
      return wire.to_h if wire.respond_to?(:to_h)

      raise ArgumentError, "wire must be a Hash, a Weft::Params, or convert with to_h, got #{wire.inspect}"
    end

    # The path params this class's route reads out of +path+; none for a
    # class without one.
    def route_params_in(_path) = {}
  end
end
