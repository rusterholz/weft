# frozen_string_literal: true

require "arbre"
require "uri"

require "weft/context"
require "weft/context/interception"
require "weft/context/traversal"
require "weft/dsl/containers"
require "weft/dsl/params"
require "weft/dsl/recoveries"
require "weft/error"
require "weft/page/assets"
require "weft/page/head"
require "weft/registry"
require "weft/registry/eligibility"

module Weft
  # Document shell component. Renders the full HTML skeleton (doctype,
  # head, body); the head surface — the `title` verb and the registered
  # scripts and stylesheets — lives in Page::Head and Page::Assets.
  # Subclass to add application-specific assets and CSS.
  #
  # Pages auto-route via page_path declarations or class-name inference.
  # The Router serves them as full documents at the resolved URL patterns.
  #
  #   class OrderDetailPage < Weft::Page
  #     self.page_path = "/orders/:order_id"
  #     param :order_id
  #   end
  #
  # Subclasses without an explicit page_path auto-infer one from the class
  # name: the demodulized name, snake-cased, with any trailing "Page" suffix
  # stripped (DashboardPage and Dashboard both route at "/dashboard"). Use
  # abstract! to opt out — typical for an intermediate base class that hosts
  # shared assets and helpers but isn't itself a destination.
  class Page < Arbre::Component
    extend Weft::Registry::Eligibility

    include Weft::Context::Interception
    include Weft::DSL::Params
    include Weft::DSL::Recoveries
    include Weft::DSL::Containers
    include Weft::Context::Traversal
    include Assets
    include Head

    # @!method weft_page(*args, &block)
    #   @api private
    #   Arbre builder for the Weft page element. Internal plumbing — authors
    #   subclass Weft::Page and render via the Router; they do not call this.
    builder_method :weft_page

    class << self
      # Class-level page path pattern. Sinatra-style string with :param segments.
      # Bidirectional: forward (interpolate params → URL) and reverse (match request → params).
      #
      #   self.page_path = "/orders/:order_id"
      def page_path
        if instance_variable_defined?(:@page_path)
          @page_path
        elsif superclass.respond_to?(:page_path)
          superclass.page_path
        end
      end

      attr_writer :page_path

      # Resolve the page path by interpolating params into the pattern.
      #   OrderDetailPage.resolve_page_path(order_id: "42") # => "/orders/42"
      def resolve_page_path(params = {})
        pattern = page_path || default_page_path
        pattern.gsub(/:(\w+)/) { params[::Regexp.last_match(1).to_sym] || ":#{::Regexp.last_match(1)}" }
      end

      # Build a redirect URL targeting this page with the given params.
      # Path :param segments interpolate from params; declared-but-not-path
      # params become query string entries. Anything not in the page's
      # declared schema is discarded — never leaks into the URL.
      #
      #   class OrderDetailPage < Weft::Page
      #     self.page_path = "/orders/:order_id"
      #     param :order_id
      #     param :highlight_section
      #   end
      #   OrderDetailPage.redirect_url(order_id: 42, highlight_section: "items", junk: "x")
      #   # => "/orders/42?highlight_section=items"
      def redirect_url(params = {})
        path = resolve_page_path(params)
        query = params.slice(*(self.params.keys - path_param_keys)).compact
        query.empty? ? path : "#{path}?#{::URI.encode_www_form(query)}"
      end

      def path_param_keys
        pattern = page_path || default_page_path
        pattern.scan(/:(\w+)/).flatten.map(&:to_sym)
      end

      # Inferred routability from declared state, ignoring any explicit
      # override. Subclasses fall back to this when they have no override of
      # their own, so an abstract parent does not disable concrete children.
      #
      # A page is inferred-routable if it has an explicit page_path, or if its
      # class name yields a usable default — i.e. the demodulized name has a
      # non-empty stem after stripping any trailing "Page" suffix. The suffix
      # is optional: FooBarPage and BazBar both route. Pages with params
      # are not inferred-routable; they require an explicit page_path (a
      # parameterized route can't be derived from the name; see default_page_path).
      def inferred_routable?
        return true if instance_variable_defined?(:@page_path)
        return false if params.any?

        !name.to_s.delete_suffix("Page").demodulize.empty?
      end

      def inherited(subclass)
        super
        Weft.registry.register_page(subclass)
      end

      # Render this page as a full HTML document outside any Arbre DSL context.
      # The kwargs are pseudo-wire: exactly what a request's query/path params
      # would carry. Used by the Router for full-document responses, and
      # available to users for testing or standalone rendering.
      def render(**wire_params)
        klass = self
        Weft::Context.new({}, nil, wire_params: wire_params) do
          insert_tag(klass)
        end.to_s
      end

      private

      def default_page_path
        if params.any?
          raise Weft::InvalidDefinition,
                "#{name} declares params but no explicit page_path. " \
                "Set self.page_path = \"/your/path/:#{params.keys.first}\""
        end

        stem = name.to_s.delete_suffix("Page")
        if stem.demodulize.empty?
          raise Weft::InvalidDefinition,
                "#{name.inspect} has no resolvable default page_path. " \
                "Either rename the class with a meaningful stem (e.g. DashboardPage), " \
                "set self.page_path = \"/your/path\" explicitly, " \
                "or mark the class abstract! if it isn't meant to route."
        end

        "/#{stem.underscore}"
      end
    end

    # Params resolve at construction (see Weft::Component#initialize) so
    # user build bodies can read them before super — e.g. computing body
    # chrome from a record looked up by param.
    def initialize(*)
      super
      @params = assembled_params if self.class.declared_keys.any?
    end

    def build(attributes = {})
      warn_declared_chrome_collisions(attributes)
      super
      build_head
      @body_el = insert_tag(Arbre::HTML::Body)
    end

    def tag_name
      "html"
    end

    def add_child(child)
      @body_el ? (@body_el << child) : super
    end

    def to_s
      "<!DOCTYPE html>\n#{super}"
    end

    # Gem-default recovery edges. Symbol form defers resolution until
    # error-handling time so reassigning the configuration knob propagates.
    # NotFound declared first so its more-specific match wins over StandardError.
    recovers from: Weft::NotFound, with: :not_found_page
    recovers from: StandardError, with: :error_page
  end
end
