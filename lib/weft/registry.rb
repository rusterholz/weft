# frozen_string_literal: true

module Weft
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
    def initialize
      @components = Set.new
      @pages = Set.new
      @path_index = nil
      @sse_present = nil
      @routes_validated = false
    end

    def register(component_class)
      @components.add(component_class)
      @path_index = nil
      @routes_validated = false
    end

    # No @path_index invalidation: pages aren't indexed there (see the class
    # comment above). Pages *do* participate in collision detection, so the
    # route-validation memo is cleared.
    def register_page(page_class)
      @pages.add(page_class)
      @routes_validated = false
    end

    # Empty the registry. Provided as an explicit reset hook for app-level
    # reload integrations and for tests; ordinary reloading is handled
    # automatically (superseded classes are pruned — see stale-class handling
    # in validate_routes!).
    def clear
      @components.clear
      @pages.clear
      @path_index = nil
      @sse_present = nil
      @routes_validated = false
    end

    def pages
      @pages.to_a
    end

    # Match a request path against registered page patterns.
    # Non-routable pages (abstract bases, classes without a resolvable path)
    # are skipped. Returns [page_class, extracted_params] or nil.
    def match_page(path)
      validate_routes!
      @pages.each do |page_class|
        next unless page_class.routable?

        params = match_pattern(resolved_page_pattern(page_class), path)
        return [page_class, params] if params
      end
      nil
    end

    def lookup(path)
      validate_routes!
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

    # Drop classes whose constant has been redefined out from under them (the
    # code-reload case — see Weft::Registry::Eligibility#stale?). Without this, a
    # reloaded class and its stale predecessor resolve to the same path and look
    # like a route collision. Runs once per registry generation via
    # validate_routes!; @path_index is rebuilt only if a component was removed.
    def prune_stale!
      @path_index = nil if @components.reject!(&:stale?)
      @pages.reject!(&:stale?)
    end

    # Build the effective-route table across every routable component (its base
    # path plus its reserved stream-suffix tail) and routable page (its resolved
    # pattern), and raise Weft::InvalidDefinition on any duplicate — component vs
    # component, page vs page, or component vs page — or any malformed path.
    # Memoized per registry generation (cleared when a class registers), so it
    # runs once at first request and is a no-op thereafter. Routability gates
    # everything: abstract!/non-routable classes derive no path and never collide.
    def validate_routes!
      return if @routes_validated

      prune_stale!
      seen = {}
      routable_components.each do |klass|
        base = klass.resolved_component_path
        add_route!(seen, base, klass, :component)
        add_route!(seen, "#{base}/#{Weft.configuration.stream_suffix}", klass, :stream)
      end
      routable_pages.each { |klass| add_route!(seen, resolved_page_pattern(klass), klass, :page) }
      @routes_validated = true
    end

    def add_route!(seen, path, klass, kind)
      validate_route_shape!(path, klass, kind)
      if (existing = seen[path])
        raise Weft::InvalidDefinition, collision_message(path, existing, [klass, kind])
      end

      seen[path] = [klass, kind]
    end

    # Tier-B well-formedness guard: a resolved route must be a non-empty string
    # beginning with "/" (an explicit "/" homepage is fine). Catches garbage from
    # custom/inherited component_path or page_path procs.
    def validate_route_shape!(path, klass, kind)
      return if path.is_a?(String) && path.start_with?("/")

      raise Weft::InvalidDefinition,
            "#{route_label(klass, kind)} resolves to #{path.inspect}, which is not a valid route: " \
            "a route must be a non-empty string beginning with \"/\"."
    end

    def collision_message(path, existing, incoming)
      "Route collision on #{path.inspect}: #{route_label(*existing)} and " \
        "#{route_label(*incoming)} resolve to the same route. Rename one class, " \
        "set an explicit component_path/page_path, or mark one abstract! if it should not route."
    end

    def route_label(klass, kind)
      case kind
      when :stream then "the SSE stream endpoint of component #{klass.name}"
      when :page then "page #{klass.name}"
      else "component #{klass.name}"
      end
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
