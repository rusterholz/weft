# frozen_string_literal: true

require "weft/registry/validation"

module Weft
  class << self
    # The process-wide registry. Defined here rather than in the gem root
    # because registration happens at class-definition time (the `inherited`
    # hooks on Component and Page call this), so any file that defines a
    # subclass needs the accessor resolvable at load.
    def registry
      @registry ||= Registry.new
    end
  end

  # Stores registered Weft::Component and Weft::Page classes for the Router
  # to consume at request time.
  #
  # Components and Pages are stored separately because their lookup costs
  # differ:
  #
  # - **Components** route at static paths (derived from the class name).
  #   Stored in `@components`; looked up via `@path_index`, a lazily-built
  #   hash keyed on the resolved path. O(1) lookup, invalidated when new
  #   components register.
  #
  # - **Pages** route at user-declared patterns that may include `:param`
  #   segments (e.g. `/orders/:order_id`). Stored in `@pages`; matched by
  #   walking the set and pattern-matching each `page_path` against the
  #   request path. O(n) match, but n is typically small (one entry per
  #   user-declared Page).
  #
  # Because pages aren't in `@path_index`, `register_page` does not
  # invalidate it. Unifying the two storage shapes would force pages-without-
  # params into the linear walk OR invent two parallel code paths; keeping
  # them separate is the simplest honest answer.
  class Registry
    include Validation

    def initialize
      @components = Set.new
      @pages = Set.new
      @path_index = nil
      @sse_present = nil
      @registrations_validated = false
    end

    def register(component_class)
      @components.add(component_class)
      @path_index = nil
      @registrations_validated = false
    end

    # No @path_index invalidation: pages aren't indexed there (see the class
    # comment above). Pages *do* participate in collision detection, so the
    # route-validation memo is cleared.
    def register_page(page_class)
      @pages.add(page_class)
      @registrations_validated = false
    end

    # Empty the registry. The evict-everything reset for hand-rolled reload
    # integrations and for tests; per-class eviction is #evict.
    def clear
      @components.clear
      @pages.clear
      @path_index = nil
      @sse_present = nil
      @registrations_validated = false
    end

    # Remove one class from the registry, invalidating route lookup so a fresh
    # same-path registration serves cleanly. This is the reload-eviction
    # primitive: Weft.configure_autoloading wires it to Zeitwerk's on_unload
    # callback, and hand-rolled reloaders should call it (or #clear) as classes
    # unload. Safe to call with any object — non-registered classes (models,
    # service objects) fall through untouched. Returns true if evicted.
    def evict(klass) # rubocop:disable Naming/PredicateMethod -- a command with a did-evict status return
      return false unless @components.delete?(klass) || @pages.delete?(klass)

      @path_index = nil
      @sse_present = nil
      @registrations_validated = false
      true
    end

    def pages
      @pages.to_a
    end

    # Match a request path against registered page patterns.
    # Non-routable pages (abstract bases, classes without a resolvable path)
    # are skipped. Returns [page_class, extracted_params] or nil.
    def match_page(path)
      validate_registrations!
      @pages.each do |page_class|
        next unless page_class.routable?

        params = match_pattern(resolved_page_pattern(page_class), path)
        return [page_class, params] if params
      end
      nil
    end

    def lookup(path)
      validate_registrations!
      path_index[path]
    end

    def components
      @components.to_a
    end

    # True if any registered component declares `pushes` (i.e. participates in
    # SSE streaming). Used by Weft::Page to decide whether to emit the
    # htmx-ext-sse script tag automatically. One-way memoized: recomputed while
    # still false, so components registered after an earlier render are picked
    # up; once true it sticks, so the typical load-everything-then-serve pattern
    # pays no steady-state recompute cost.
    def any_sse_components?
      return true if @sse_present

      @sse_present = @components.any?(&:push_config)
    end

    private

    # Routable components only — non-routable components register but are never
    # served, so they don't occupy a route (and must not shadow one in the index).
    def path_index
      @path_index ||= routable_components.to_h { |klass| [klass.resolved_component_path, klass] }
    end

    def routable_components
      @components.select(&:routable?)
    end

    def routable_pages
      @pages.select(&:routable?)
    end

    def resolved_page_pattern(page_class)
      page_class.page_path || page_class.send(:default_page_path)
    end

    # Match a Sinatra-style pattern against a path.
    # Returns a hash of extracted params, or nil if no match.
    def match_pattern(pattern, path)
      pattern_parts = pattern.split("/")
      path_parts = path.split("/")
      return nil unless pattern_parts.length == path_parts.length

      params = {}
      pattern_parts.zip(path_parts).each do |pat, val|
        if pat.start_with?(":")
          params[pat[1..].to_sym] = val
        elsif pat != val
          return nil
        end
      end
      params
    end
  end
end
