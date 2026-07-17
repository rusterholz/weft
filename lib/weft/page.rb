# frozen_string_literal: true

require "uri"

module Weft
  # Document shell component. Renders the full HTML skeleton (doctype,
  # head, body) with registered scripts and stylesheets. Subclass to
  # add application-specific assets and CSS.
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
  class Page < Arbre::Component # rubocop:disable Metrics/ClassLength
    extend Weft::Registry::Eligibility

    include Weft::Context::Interception
    include Weft::DSL::Params
    include Weft::DSL::Recoveries
    include Weft::DSL::Containers

    # @!method weft_page(*args, &block)
    #   @api private
    #   Arbre builder for the Weft page element. Internal plumbing — authors
    #   subclass Weft::Page and render via the Router; they do not call this.
    builder_method :weft_page

    HTMX_SRC = "https://unpkg.com/htmx.org@2.0.4"
    HTMX_ATTRS = {
      integrity: "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+",
      crossorigin: "anonymous"
    }.freeze
    HTMX_SSE_SRC = "https://unpkg.com/htmx-ext-sse@2.2.2/sse.js"
    HTMX_SSE_ATTRS = {
      integrity: "sha384-fw+eTlCc7suMV/1w/7fr2/PmwElUIt5i82bi+qTiLXvjRXZ2/FkiTNA/w0MhXnGI",
      crossorigin: "anonymous"
    }.freeze

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

      # Register a stylesheet to include in the page head.
      #
      # Absolute URLs (http(s)://, protocol-relative //, leading /) render as-is.
      # Bare-relative paths resolve against a static_assets bundle: either the
      # one named via `assets:`, or the :default bundle if one is configured.
      # When neither applies, the path passes through unchanged and the browser
      # resolves it relative to the current page URL.
      #
      #   register_stylesheet "https://cdn.example.com/bootstrap.css"
      #   register_stylesheet "css/app.css"                   # resolves against :default
      #   register_stylesheet "tailwind/tw.css", assets: :vendor
      def register_stylesheet(href, assets: nil)
        own_stylesheets << { href: href, assets: assets }
      end

      # Register a script to include in the page head. Same resolution rules
      # as register_stylesheet. Additional kwargs become HTML attributes on
      # the <script> tag.
      #
      #   register_script "https://cdn.example.com/app.js", defer: "defer"
      #   register_script "js/app.js"                         # resolves against :default
      #   register_script "vendor/x.js", assets: :vendor, defer: "defer"
      def register_script(src, assets: nil, **html_attrs)
        own_scripts << { src: src, attrs: html_attrs, assets: assets }
      end

      # Register a block of inline CSS to include in the page head.
      # Each registered string emits as its own <style> tag (subclasses
      # add on top of their parent's contributions; nothing replaces).
      #
      #   register_inline_css <<~CSS
      #     .card { padding: 1rem; }
      #   CSS
      def register_inline_css(css)
        own_inline_css << css
      end

      # All registered stylesheets (own + inherited).
      def stylesheets
        if superclass.respond_to?(:stylesheets)
          superclass.stylesheets + own_stylesheets
        else
          own_stylesheets.dup
        end
      end

      # All registered scripts (own + inherited).
      def scripts
        if superclass.respond_to?(:scripts)
          superclass.scripts + own_scripts
        else
          own_scripts.dup
        end
      end

      # All registered inline CSS blocks (own + inherited).
      def inline_css
        if superclass.respond_to?(:inline_css)
          superclass.inline_css + own_inline_css
        else
          own_inline_css.dup
        end
      end

      private

      def own_stylesheets
        @own_stylesheets ||= []
      end

      def own_scripts
        @own_scripts ||= []
      end

      def own_inline_css
        @own_inline_css ||= []
      end

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
    # user build bodies can read them before super — e.g. deriving the
    # page title from a record looked up by param.
    def initialize(*)
      super
      @params = resolved_wire_params if self.class.params.any?
    end

    def build(attributes = {})
      warn_declared_chrome_collisions(attributes)
      @page_title = attributes.delete(:title) || "Weft"
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

    private

    def build_head
      insert_tag(Arbre::HTML::Head) do
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        title { text_node @page_title }
        render_assets
        render_htmx_config
      end
    end

    def render_assets
      render_stylesheets
      render_htmx_script if Weft.configuration.include_htmx
      render_sse_script if include_sse_ext?
      render_scripts
      render_inline_css
    end

    def render_stylesheets
      self.class.stylesheets.each do |entry|
        link href: resolve_asset_url(entry[:href], assets: entry[:assets]), rel: "stylesheet"
      end
    end

    def render_scripts
      self.class.scripts.each do |entry|
        script(src: resolve_asset_url(entry[:src], assets: entry[:assets]), **entry[:attrs])
      end
    end

    # Resolve a registered asset path to a final URL.
    #
    # - Absolute URLs (http(s)://, //, /) pass through unchanged. Passing an
    #   `assets:` kwarg alongside an absolute URL raises — the kwarg is only
    #   meaningful for relative paths, and accepting it silently would train
    #   callers to attach it everywhere "just in case."
    # - Bare-relative paths with an explicit `assets: :name` resolve against
    #   that bundle's root. Unknown bundle names raise with a list of
    #   configured names.
    # - Bare-relative paths without an `assets:` kwarg resolve against the
    #   :default bundle if one is configured; otherwise they pass through and
    #   the browser interprets them relative to the current page URL.
    def resolve_asset_url(path, assets: nil)
      return resolve_absolute_asset_url(path, assets) if absolute_asset_url?(path)

      resolve_relative_asset_url(path, assets)
    end

    def resolve_absolute_asset_url(path, assets)
      raise_absolute_with_assets_kwarg!(path, assets) if assets

      path
    end

    def resolve_relative_asset_url(path, assets)
      bundles = Weft.configuration.static_assets
      target = assets&.to_sym || (bundles.key?(:default) ? :default : nil)
      return path unless target

      bundle = bundles[target]
      raise_unknown_assets_bundle!(path, target, bundles) unless bundle

      "#{bundle[:root]}/#{path}"
    end

    def absolute_asset_url?(path)
      path.start_with?("http://", "https://", "//", "/")
    end

    def raise_absolute_with_assets_kwarg!(path, assets)
      raise Weft::InvalidUsage,
            "static asset #{path.inspect}: assets: #{assets.inspect} " \
            "is only meaningful for relative paths (absolute URLs render as-is)"
    end

    def raise_unknown_assets_bundle!(path, target, bundles)
      raise Weft::InvalidUsage,
            "static asset #{path.inspect} references assets bundle #{target.inspect}, " \
            "but no such bundle is configured. Configured bundles: #{bundles.keys.inspect}"
    end

    def render_inline_css
      self.class.inline_css.each { |css| style { text_node css.html_safe } }
    end

    def render_htmx_script
      script src: HTMX_SRC, **HTMX_ATTRS
    end

    def render_sse_script
      script src: HTMX_SSE_SRC, **HTMX_SSE_ATTRS
    end

    # Resolve the include_sse_ext configuration into a boolean. :auto defers
    # to the Registry; true/false short-circuit it.
    def include_sse_ext?
      case Weft.configuration.include_sse_ext
      when true then true
      when false then false
      else Weft.registry.any_sse_components?
      end
    end

    def render_htmx_config
      script do
        text_node htmx_config_js.html_safe
      end
    end

    def htmx_config_js
      <<~JS
        htmx.config.responseHandling = [
          {code: "204", swap: false},
          {code: "[23]..", swap: true},
          {code: "[45]..", swap: true, error: true}
        ];
      JS
    end

    # Gem-default recovery edges. Symbol form defers resolution until
    # error-handling time so reassigning the configuration knob propagates.
    # NotFound declared first so its more-specific match wins over StandardError.
    recovers from: Weft::NotFound, with: :not_found_page
    recovers from: StandardError, with: :error_page
  end
end
