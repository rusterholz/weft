# frozen_string_literal: true

require "sinatra/base"
require "uri"

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
    require_relative "router/oob_includes"
    require_relative "router/actions"
    require_relative "router/errors"
    include Streaming
    include OOBIncludes
    include Actions
    include Errors

    set :logging, false
    set :show_exceptions, false
    # In Sinatra's :test environment, raise_errors defaults to true (so test
    # frameworks see exceptions). Weft's own error block must run instead —
    # uncaught route exceptions feed the Page recovers chain.
    set :raise_errors, false
    set :dump_errors, false

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

    # In standalone mode (no downstream Rack app), Sinatra's not_found
    # block fires when no route matched. Walk the Weft::Page recovers chain
    # (default → Weft::Defaults::NotFoundPage). In middleware mode, `pass`
    # falls through to the downstream app — this block doesn't fire.
    not_found do
      content_type :html
      handle_page_chain_failure(Weft::NotFound.new(request.path),
                                originating_page_class: nil)
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

    def filtered_params
      params.except("splat", "captures")
    end

    # Render a component as HTML. inner: true returns children only
    # (for SSE innerHTML swap where the wrapper element must persist).
    def render_component(component_class, inner: false)
      component = build_component_with_wire(component_class, filtered_params)
      inner ? component.content : component.to_s
    rescue StandardError => e
      render_error(component_class, Weft::Resolver.resolve(component_class, filtered_params), e)
    end

    # Build a component instance from the current request params.
    def build_component(component_class)
      build_component_with_wire(component_class, filtered_params)
    end

    # Build a component in a fresh context carrying the wire source; the
    # component resolves its own declared params from it at build. Arbre's
    # builder attributes stay pure chrome — params travel their own channel.
    def build_component_with_wire(component_class, wire_params)
      klass = component_class
      context = Weft::Context.new({}, nil, wire_params: wire_params) { insert_tag(klass) }
      context.children.first
    end

    # Render a Page as a full HTML document. Query/body params and
    # path-extracted params are merged; path params override on key
    # conflicts, matching Sinatra's precedence convention.
    # Page render failures walk the failing Page's recovers chain
    # (B1 / C1 page-context); the gem-default catches StandardError.
    def render_page(page_class, route_params)
      merged_params = filtered_params.merge(route_params)
      klass = page_class
      Weft::Context.new({}, nil, wire_params: merged_params) { insert_tag(klass) }.to_s
    rescue StandardError => e
      handle_page_chain_failure(e,
                                originating_page_class: page_class,
                                originating_params: Weft::Resolver.resolve(page_class, merged_params))
    end

    def htmx_request?
      request.env["HTTP_HX_REQUEST"] == "true"
    end

    # Handle a Weft::Redirect return from a callable or recovers block.
    # htmx requests get HX-Redirect header; traditional requests get 302.
    def handle_redirect(redir)
      if request.env["HTTP_HX_REQUEST"]
        headers["HX-Redirect"] = redir.url
        status 204
        ""
      else
        redirect redir.url
      end
    end

    def apply_trigger_header(component_class)
      events = component_class.trigger_events
      return if events.empty?

      headers["HX-Trigger"] = events.join(", ")
    end
  end
end
