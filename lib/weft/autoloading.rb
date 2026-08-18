# frozen_string_literal: true

require "active_support/file_update_checker"

require "weft/error"
require "weft/router"

module Weft
  # Zeitwerk-backed autoloading for application code, behind
  # {Weft.configure_autoloading}. Each call builds one Zeitwerk loader over the
  # given paths and eager-loads it immediately — Weft routes from the Registry,
  # which populates via the `inherited` hook, so the classes must exist before
  # the first request (lazy autoload alone would serve an empty route table).
  #
  # With reload: true, a per-request Router hook reloads constants, and
  # Zeitwerk's on_unload callback evicts each outgoing class from the registry
  # as it unloads — the push-model complement to {Registry#evict}, which
  # hand-rolled reloaders call directly.
  module Autoloading
    class << self
      # Loaders created so far, in creation order. @api private
      def loaders
        @loaders ||= []
      end

      def setup(paths:, inflections: {}, reload: false)
        paths = Array(paths)
        validate!(paths, inflections)
        require "zeitwerk"

        loader = build_loader(paths, inflections, reload)
        loader.setup
        loader.eager_load
        install_reload_hook(loader) if reload
        loaders << loader
        loader
      end

      private

      def build_loader(paths, inflections, reload)
        loader = Zeitwerk::Loader.new
        paths.each { |dir| loader.push_dir(dir) }
        loader.inflector.inflect(inflections) unless inflections.empty?
        loader.enable_reloading if reload # must precede setup — Zeitwerk's contract
        loader.on_unload { |_cpath, value, _abspath| Weft.registry.evict(value) }
        loader
      end

      def validate!(paths, inflections)
        raise Weft::InvalidConfiguration, "configure_autoloading requires at least one path" if paths.empty?
        return if inflections.all? { |k, v| k.is_a?(String) && v.is_a?(String) }

        raise Weft::InvalidConfiguration,
              "configure_autoloading inflections must map file basenames to constant names " \
              "(String => String), got #{inflections.inspect}"
      end

      # The dev-mode request hook: when a watched file has changed, reload
      # constants (evicting via on_unload as they unload), eager-load so
      # everything re-registers, then rebind any configuration knob left
      # holding a superseded class.
      #
      # Two guards, both load-bearing under a threaded server:
      #
      # * **Only when something changed.** Reloading on every request unloads
      #   and rediscovers the whole application to find the same code, and it
      #   widens the window below for no reason.
      # * **One at a time.** Zeitwerk's reload is not thread-safe. Without the
      #   lock, a request can be mid-render while a sibling unloads the world
      #   underneath it — the constant it reaches for is briefly undefined, so
      #   it fails with an `uninitialized constant` naming something it never
      #   touched. Concurrent reloads can also leave the loader itself
      #   mid-setup. The check belongs inside the lock too: otherwise every
      #   thread reads "changed" before any of them has reloaded, and they all
      #   pile in.
      def install_reload_hook(loader)
        lock = Mutex.new
        watcher = ActiveSupport::FileUpdateChecker.new([], watched_dirs(loader)) do
          loader.reload
          loader.eager_load
          Weft.configuration.refresh_stale_classes!
        end

        Router.before { lock.synchronize { watcher.execute_if_updated } }
      end

      # Zeitwerk's own root directories, watched for Ruby files.
      def watched_dirs(loader) = loader.dirs.to_h { |dir| [dir, ["rb"]] }
    end
  end
end
