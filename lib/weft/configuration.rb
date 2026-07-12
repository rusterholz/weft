# frozen_string_literal: true

require "logger"

module Weft
  class Configuration
    DEFAULT_COMPONENT_PATH = ->(klass) { "/_components/#{klass.name.to_s.delete_suffix('Component').underscore}" }
    VALID_HTMX_ERRORS = %i[fragment redirect].freeze
    VALID_INCLUDE_SSE_EXT = [:auto, true, false].freeze
    LOG_LEVELS = {
      debug: Logger::DEBUG, info: Logger::INFO, warn: Logger::WARN,
      error: Logger::ERROR, fatal: Logger::FATAL, unknown: Logger::UNKNOWN
    }.freeze
    private_constant :DEFAULT_COMPONENT_PATH, :VALID_HTMX_ERRORS, :VALID_INCLUDE_SSE_EXT, :LOG_LEVELS

    attr_reader :component_path, :htmx_errors, :include_sse_ext, :log_level, :stream_suffix
    attr_accessor :include_htmx, :auto_reload, :reload_paths, :verbose_error_pages, :router_logging
    attr_writer :error_component, :error_page, :not_found_page, :not_found_component

    # @api private
    # Instantiated internally by {Weft.configuration}. Configure Weft via
    # +Weft.configure { |c| ... }+ rather than constructing this directly.
    def initialize
      @component_path = DEFAULT_COMPONENT_PATH
      @include_htmx = true
      @include_sse_ext = :auto
      @auto_reload = false
      @reload_paths = []
      @router_logging = false
      @verbose_error_pages = true
      @htmx_errors = :fragment
      @log_level = :info
      @stream_suffix = "_stream"
      @static_assets = {}
    end

    def component_path=(value)
      raise ArgumentError, "component_path must be a Proc, got #{value.class}" unless value.is_a?(Proc)

      @component_path = value
    end

    def htmx_errors=(value)
      unless VALID_HTMX_ERRORS.include?(value)
        raise ArgumentError, "htmx_errors must be :fragment or :redirect, got #{value.inspect}"
      end

      @htmx_errors = value
    end

    # Controls when Weft::Page emits the htmx-ext-sse script tag.
    # - :auto (default) -- include only if any registered component declares
    #   `pushes`. Driven by Weft.registry.any_sse_components?.
    # - true            -- always include (escape hatch for lazy autoload or
    #   custom Registry population timing where :auto would miss components).
    # - false           -- never include.
    def include_sse_ext=(value)
      unless VALID_INCLUDE_SSE_EXT.include?(value)
        raise ArgumentError, "include_sse_ext must be :auto, true, or false, got #{value.inspect}"
      end

      @include_sse_ext = value
    end

    def log_level=(value)
      unless LOG_LEVELS.key?(value)
        raise ArgumentError, "log_level must be one of #{LOG_LEVELS.keys.inspect}, got #{value.inspect}"
      end

      @log_level = value
    end

    # The path segment that marks a component's SSE stream endpoint. The leading
    # slash is supplied by Weft, so set the bare segment (e.g. "stream", "sse").
    # It's appended as "<component_path>/<stream_suffix>" on both sides: the
    # client-facing sse-connect URL (Weft::Component#stream_url) and the Router's
    # stream-request routing. Must be a non-empty segment with no slashes.
    def stream_suffix=(value)
      unless value.is_a?(String) && !value.empty? && !value.include?("/")
        raise ArgumentError,
              "stream_suffix must be a non-empty path segment with no slashes — " \
              "Weft adds the leading slash itself (e.g. \"stream\"), got #{value.inspect}"
      end

      @stream_suffix = value
    end

    # Resolves the configured log_level symbol to its Logger severity constant
    # (e.g. :warn -> Logger::WARN). Used by Weft.configure to set logger.level.
    def resolved_log_level
      LOG_LEVELS.fetch(@log_level)
    end

    # Register a directory to serve as static assets at a URL prefix, under
    # a logical bundle name. The bundle name is the stable reference used at
    # call sites (`register_stylesheet "css/app.css", assets: :app`); the
    # root/from pair can be reconfigured (e.g. from env vars in production)
    # without touching call sites.
    #
    # Multi-call: each call adds a {name => {root:, from:}} entry. Raises
    # ArgumentError on duplicate name or duplicate root.
    #
    #   c.static_assets root: "/static", from: File.join(APP_ROOT, "public")
    #   # name: defaults to :default — call sites without an `assets:` kwarg
    #   # implicitly resolve against this bundle.
    #
    #   c.static_assets name: :vendor, root: "/vendor",
    #                   from: File.join(APP_ROOT, "vendor", "assets")
    #
    # Called with no arguments, returns a copy of the registered bundles as a
    # hash (name => {root:, from:}). Used by the apply step and the page-side
    # resolve_asset_url logic.
    def static_assets(name: nil, root: nil, from: nil)
      return @static_assets.transform_values(&:dup) if name.nil? && root.nil? && from.nil?

      register_static_assets_bundle(name: name, root: root, from: from)
    end

    # Lazy defaults — resolved on first read so Weft::Defaults classes load before
    # the Configuration class is required. Assignment sticks.
    def error_component
      @error_component ||= Weft::Defaults::ErrorComponent
    end

    def error_page
      @error_page ||= Weft::Defaults::ErrorPage
    end

    def not_found_page
      @not_found_page ||= Weft::Defaults::NotFoundPage
    end

    def not_found_component
      @not_found_component ||= Weft::Defaults::NotFoundComponent
    end

    private

    def register_static_assets_bundle(name:, root:, from:)
      if root.nil? || from.nil?
        raise ArgumentError,
              "static_assets requires both root: and from: " \
              "(e.g., static_assets root: '/static', from: File.join(APP_ROOT, 'public'))"
      end
      unless root.start_with?("/")
        raise Weft::InvalidConfiguration, "static_assets root must start with '/', got #{root.inspect}"
      end

      bundle_name = (name || :default).to_sym
      normalized_root = normalize_static_assets_root(root)
      check_static_assets_uniqueness!(bundle_name, normalized_root)

      @static_assets[bundle_name] = { root: normalized_root, from: from }
    end

    # Strip a trailing slash so URL building can always `"#{root}/#{path}"`
    # without producing double slashes. "/" is left alone to allow root-mount
    # (though apps typically use a prefix).
    def normalize_static_assets_root(root)
      root == "/" ? root : root.chomp("/")
    end

    def check_static_assets_uniqueness!(name, root)
      if (existing = @static_assets[name])
        raise Weft::InvalidConfiguration,
              "static_assets bundle #{name.inspect} is already registered " \
              "(at root #{existing[:root].inspect}, from #{existing[:from].inspect}); refusing to overwrite"
      end

      conflict = @static_assets.find { |_n, b| b[:root] == root }
      return unless conflict

      raise Weft::InvalidConfiguration,
            "static_assets root #{root.inspect} is already registered (by bundle #{conflict[0].inspect})"
    end
  end
end
