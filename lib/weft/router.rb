# frozen_string_literal: true

require "sinatra/base"
require "uri"

require "weft/context"
require "weft/error"
require "weft/params/assembly"
require "weft/request"
require "weft/request/event_frame"

module Weft
  # Rack middleware that auto-generates routes for Weft::Components.
  #
  # GET routes render components as HTML fragments (partial rendering).
  # POST/PUT/DELETE/PATCH routes invoke component actions declared via
  # `performs` or `transfers`, then render the action's target component.
  #
  # Usage:
  #   # Middleware (coexists with any Rack app)
  #   use Weft::Router
  #
  #   # Standalone
  #   run Weft::Router
  class Router < Sinatra::Base
    # Behavior slices live under Weft::Router::*. Required inside the class
    # body so each slice's reopened `class Router` finds the Sinatra::Base
    # superclass already declared.
    require_relative "router/streaming"
    require_relative "router/companions"
    require_relative "router/actions"
    require_relative "router/errors"
    include Streaming
    include Companions
    include Actions
    include Errors

    set :logging, false
    set :show_exceptions, false
    # In Sinatra's :test environment, raise_errors defaults to true (so test
    # frameworks see exceptions). Weft's own error block must run instead —
    # uncaught route exceptions feed the Page recovers chain.
    set :raise_errors, false
    set :dump_errors, false

    # Every response weft answers carries its request's id, unless something
    # already set one. A response passed downstream is that app's to label.
    after do
      headers["X-Request-Id"] ||= weft_request.id unless @weft_forwarded
    end

    # GET: render a component, invoke a nameless GET action, or stream SSE
    get "/*" do
      path = "/#{params['splat'].first}"

      if stream_request?(path)
        handle_stream_request(path)
      else
        handle_get_request(path)
      end
    end

    # POST/PUT/DELETE/PATCH: invoke named or nameless actions
    %i[post put delete patch].each do |http_method|
      send(http_method, "/*") do
        path = "/#{params['splat'].first}"
        result = resolve_action(path, http_method)

        if result
          content_type :html
          handle_action(*result)
        else
          pass
        end
      end
    end

    # Both error registrations are exception-keyed, never status-keyed: an
    # error(404)/not_found handler fires on response *status* after every
    # dispatch — custom recovery bodies return normally, no exception
    # recorded — and would overwrite them with the default chain's output.
    # Exception keys only fire when Sinatra itself raises.

    # Routing miss in standalone mode: Sinatra raises Sinatra::NotFound
    # after the final `pass` (middleware mode forwards downstream instead).
    # Translate and walk the default Weft::Page chain. The exact-class key
    # is load-bearing: Sinatra dispatches exact keys across all superclasses
    # before walking the exception hierarchy, and Sinatra::Base registers
    # its own development-mode `error NotFound` ("doesn't know this ditty")
    # that must be shadowed here — StandardError below wouldn't be reached.
    error Sinatra::NotFound do
      content_type :html
      handle_page_chain_failure(Weft::NotFound.new(request.path),
                                originating_page_class: nil)
    end

    # A request nothing could parse. Sinatra raises this the first time
    # anything reads `params` — which is the route handler above, before any
    # component or page has been resolved — so the recovery is routed by path
    # alone. Exact-class key for the same reason as NotFound.
    error Sinatra::BadRequest do
      weft_request.send(:unreadable!)
      content_type :html
      handle_unreadable_request(env["sinatra.error"])
    end

    # Catch any error escaping a route handler and walk the Weft::Page
    # chain. Covers full-document Page render failures that escape
    # render_page's own rescue (and any direct user-raised errors).
    error StandardError do
      e = env["sinatra.error"]
      content_type :html
      handle_page_chain_failure(e, originating_page_class: nil)
    end

    private

    # This exchange's request, one object for every frame it renders.
    def weft_request = @weft_request ||= Weft::Request.wrap(request)

    # A request passed downstream still has its id settled and written to the
    # env, where the app behind reads it; only the response goes unlabeled.
    def forward
      @weft_forwarded = true
      weft_request
      super
    end

    # A GET targets a component's SSE stream endpoint when its path ends with
    # "/<stream_suffix>" (default "/_stream"). See Streaming slice.
    def stream_request?(path)
      path.end_with?("/#{Weft.configuration.stream_suffix}")
    end

    def handle_get_request(path)
      # Action resolution handles both named (/component/action_name)
      # and nameless (/component with actions[[nil, :get]]) GET actions.
      result = resolve_action(path, :get)
      if result
        content_type :html
        return handle_action(*result)
      end

      # No action matched — render the component directly if it exists and is routable.
      component_class = Weft.registry.lookup(path)
      if component_class&.routable?
        content_type :html
        return render_component(component_class)
      end

      # Try page routes (pattern match against registered page paths).
      page_match = Weft.registry.match_page(path)
      if page_match
        content_type :html
        return render_page(*page_match)
      end

      pass
    end

    # Everything the client sent, as the request sources it: computed once,
    # and carried by every bag the exchange branches.
    def request_universe = weft_request.send(:universe)

    # The request's root bag: what a recovery with no originating bag starts
    # from, and what every root crosses from.
    def request_earth = weft_request.send(:earth)

    # A root's own bag: a crossing from the request's earth into its class,
    # with no hand-off door, since no call site exists to hand anything over.
    def root_bag(component_class, request = weft_request)
      Weft::Params::Assembly.call(component_class, branched_from: request.send(:earth), handoffs: nil)
    end

    # A frame for one delivery of the exchange's request. A recovery renders
    # in the frame of the delivery it ships in.
    def new_frame(request = weft_request) = Weft::Request::EventFrame.new(request)

    # Render a component as HTML. inner: true returns children only
    # (for SSE innerHTML swap where the wrapper element must persist).
    def render_component(component_class, inner: false)
      state = root_bag(component_class)
      frame = new_frame
      component = build_root(component_class, frame, branch_bag: state)
      inner ? component.content : component.to_s
    rescue StandardError => e
      render_error(component_class, state, e, frame: frame)
    end

    # Build a component as the root of a fresh tree, branching +branch_bag+:
    # the bag the delivery assembled, or one a verb block or a primary has
    # already composed (an OOB companion's). Arbre's builder attributes stay
    # pure chrome — params travel their own channel. `fills` is the slot a
    # recovery stands in for: the root wears and claims that id.
    def build_root(component_class, frame, branch_bag:, fills: nil)
      klass = component_class
      Weft::Context.new(frame: frame, branch_bag: branch_bag, fills: fills) { insert_tag(klass) }.children.first
    end

    # Render a Page as a full HTML document. The route's path params join the
    # request's universe, outranking a query value of the same name.
    # Page render failures walk the failing Page's recovers chain
    # (B1 / C1 page-context); the gem-default catches StandardError.
    def render_page(page_class, route_params)
      weft_request.send(:record_route_params, route_params)
      root = root_bag(page_class)
      frame = new_frame
      klass = page_class
      Weft::Context.new(frame: frame, branch_bag: root) { insert_tag(klass) }.to_s
    rescue StandardError => e
      handle_page_chain_failure(e,
                                originating_page_class: page_class,
                                originating_params: root,
                                originating_frame: frame)
    end

    def htmx_request? = weft_request.htmx?

    # Handle a Weft::Redirect return from a callable or recovers block.
    # htmx requests get HX-Redirect header; traditional requests get 302.
    def handle_redirect(redir)
      if htmx_request?
        headers["HX-Redirect"] = redir.url
        status 204
        ""
      else
        redirect redir.url
      end
    end

    def apply_announcement_header(component_class, action_name)
      events = component_class.announced_events(action_name)
      return if events.empty?

      headers["HX-Trigger"] = events.join(", ")
    end
  end
end
