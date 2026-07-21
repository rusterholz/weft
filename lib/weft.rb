# frozen_string_literal: true

require "logger"

require "active_support"
require "active_support/core_ext/integer/time"
require "active_support/core_ext/string/inflections"
require "arbre"

require "weft/error"
require "weft/params"
require "weft/dsl/params"
require "weft/dsl/sandbox"
require "weft/dsl/recoveries"
require "weft/dsl/triggers"
require "weft/dsl/inclusions"
require "weft/dsl/updates"
require "weft/dsl/actions"
require "weft/dsl/containers"
require "weft/configuration"
require "weft/registry"
require "weft/registry/eligibility"
require "weft/action"
require "weft/component"
require "weft/context"
require "weft/resolver"
require "weft/page"
require "weft/redirect"
require "weft/router"
require "weft/version"

# Component-oriented hypermedia for Ruby.
module Weft
  class << self
    attr_writer :logger

    # Weft's process-wide logger. In standalone mode this defaults to a $stdout
    # Logger at the configured log_level (:info by default) — modeling the
    # unified activity+error stream a 12-factor Rails container emits under
    # RAILS_LOG_TO_STDOUT, so deployments aggregate it like any other web
    # container. When mounted in Rails, set +Weft.logger = Rails.logger+ and
    # this default never applies. Weft.configure applies log_level to it.
    def logger
      @logger ||= Logger.new($stdout)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def registry
      @registry ||= Registry.new
    end

    def configure
      yield configuration
      apply_configuration
    end

    # Convenience wrapper for Weft::Redirect.to.
    def redirect(target, **params)
      Redirect.to(target, **params)
    end

    # Register a named interaction preset. Delegates to Weft::Presets.
    #
    #   Weft.register_preset :tooltip, trigger: :hover, swap: :fill
    def register_preset(name, **defaults)
      Presets.register(name, **defaults)
    end

    # Look up a registered preset by name. Delegates to Weft::Presets.
    def preset(name)
      Presets.lookup(name)
    end

    private

    # Apply side-effects from the current Weft.configuration. Called by
    # Weft.configure after the user block yields. Safe to call multiple
    # times — each apply step is idempotent.
    def apply_configuration
      logger.level = configuration.resolved_log_level
      Router.set(:logging, configuration.router_logging)
      enable_auto_reload! if configuration.auto_reload && !@auto_reload_applied
      apply_static_assets!
    end

    def enable_auto_reload!
      require "sinatra/reloader"
      Router.register(Sinatra::Reloader)
      configuration.reload_paths.each { |path| Router.also_reload(path) }
      @auto_reload_applied = true
    end

    def apply_static_assets!
      @mounted_static_bundles ||= Set.new
      configuration.static_assets.each do |name, bundle|
        next if @mounted_static_bundles.include?(name)

        mount_static_assets_route(bundle[:root], bundle[:from])
        @mounted_static_bundles << name
      end
    end

    # Mount a Sinatra before-filter that serves files under `from` at the URL
    # prefix `root`. send_file handles content-type/etag/halt; the expand-
    # path containment check rejects path-traversal attempts (e.g.
    # /static/../../etc/passwd resolves outside `from` and returns 404).
    def mount_static_assets_route(root, from)
      expanded_from = File.expand_path(from)
      Router.before "#{root}/*" do
        next unless request.get? || request.head?

        requested = File.expand_path(params[:splat].first, expanded_from)
        halt 404 unless requested.start_with?("#{expanded_from}/") && File.file?(requested)

        send_file requested
      end
    end
  end
end

require "weft/presets"
require "weft/defaults"
