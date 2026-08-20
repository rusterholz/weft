# frozen_string_literal: true

require "weft/error"

module Weft
  class Registry
    # Validation slice of the Registry. What has to hold across the registered
    # set *as a whole* rather than of any one class: that no two classes claim
    # one route, and that no two derive one DOM id base.
    #
    # Together because they share a pass and a memo — the registry invalidates
    # once when a class registers, and both re-run at the next request rather
    # than on every registration.
    #
    # Depends on Registry internals: `@components`, `routable_components`,
    # `routable_pages`, and `resolved_page_pattern`.
    module Validation
      private

      # Everything that has to hold across the registered set as a whole, in one
      # memoized pass (cleared when a class registers), so it runs at first
      # request and is a no-op thereafter. Routes first: a pair colliding on both
      # a route and an id base is more actionably reported as the route.
      def validate_registrations!
        return if @registrations_validated

        validate_routes!
        validate_id_bases!
        @registrations_validated = true
      end

      # Build the effective-route table across every routable component (its base
      # path plus its reserved stream-suffix tail) and routable page (its resolved
      # pattern), and raise Weft::InvalidDefinition on any duplicate — component vs
      # component, page vs page, or component vs page — or any malformed path.
      # Routability gates everything here: abstract!/non-routable classes derive
      # no path and never collide.
      def validate_routes!
        seen = {}
        routable_components.each do |klass|
          warn_dependent_receives!(klass)
          base = klass.resolved_component_path
          add_route!(seen, base, klass, :component)
          add_route!(seen, "#{base}/#{Weft.configuration.stream_suffix}", klass, :stream)
        end
        routable_pages.each { |klass| add_route!(seen, resolved_page_pattern(klass), klass, :page) }
      end

      # Two components whose names derive one DOM id base can put two fragments
      # at one address, and since M17 that drops a companion rather than merely
      # duplicating an id. Deliberately NOT routability-gated, unlike the route
      # check above: a component that never routes still has to swap into the
      # right slot, so a non-routable class beside a routable one was the gap.
      #
      # Pages are absent because they have no DOM identity to collide over.
      #
      # Two exemptions, both provably safe rather than merely conventional. A
      # component identifying by a block does not derive its id from the base at
      # all. A `unique!` component carries a mint per instance, so a shared base
      # yields `foo-Maaaa` beside `foo-Mbbbb` — distinct however many render.
      def validate_id_bases!
        seen = {}
        @components.each do |klass|
          next if klass.name.nil? || klass.identity_block || klass.unique?

          base = klass.weft_dom_id_base
          if (existing = seen[base])
            raise Weft::InvalidDefinition, id_base_collision_message(base, existing, klass)
          end

          seen[base] = klass
        end
      end

      # A routable component with a required hand-off it cannot reconstruct
      # standalone will raise on every refresh (nothing hands the value over).
      # Defaulted hand-offs are exempt (declaring a default explicitly opts
      # into standalone renders falling back to it), as are dual keys — a wire
      # param or a derives supplies the standalone value. Runs once per
      # registry generation, alongside route validation.
      def warn_dependent_receives!(klass)
        required = klass.received_params.reject { |_, meta| meta.key?(:default) }.keys
        undualed = required - klass.params.keys - klass.derived_params.keys
        return if undualed.empty?

        Weft.logger.warn(
          "#{klass.name} is routable but depends on hand-offs it cannot reconstruct standalone " \
          "(#{undualed.map(&:inspect).join(', ')}) — a refresh will raise without them. " \
          "Mark the class dependent!, or declare a derives or wire param dual for the key."
        )
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

      # Two same-named class objects at one route is the signature of code
      # reloading without eviction — say so, rather than suggesting a rename.
      def collision_message(path, existing, incoming)
        if existing[0].name == incoming[0].name
          "Route collision on #{path.inspect}: two class objects named #{existing[0].name} " \
            "are registered — usually a code reloading setup that never evicts. Evict classes " \
            "as they unload (Weft.registry.evict, e.g. from a Zeitwerk on_unload callback), " \
            "or reset with Weft.registry.clear before each reload."
        else
          "Route collision on #{path.inspect}: #{route_label(*existing)} and " \
            "#{route_label(*incoming)} resolve to the same route. Rename one class, " \
            "set an explicit component_path/page_path, or mark one abstract! if it should not route."
        end
      end

      def id_base_collision_message(base, existing, incoming)
        if existing.name == incoming.name
          "DOM id collision on #{base.inspect}: two class objects named #{existing.name} are " \
            "registered — usually a code reloading setup that never evicts. Evict classes as they " \
            "unload (Weft.registry.evict, e.g. from a Zeitwerk on_unload callback), or reset with " \
            "Weft.registry.clear before each reload."
        else
          "DOM id collision on #{base.inspect}: components #{existing.name} and #{incoming.name} " \
            "derive the same id base, so instances of the two can resolve to one DOM id. An " \
            "out-of-band swap is addressed by DOM id, so only one fragment would land — rename one " \
            "class, declare `unique!` on one, or give one an `identifies_by` block."
        end
      end

      def route_label(klass, kind)
        case kind
        when :stream then "the SSE stream endpoint of component #{klass.name}"
        when :page then "page #{klass.name}"
        else "component #{klass.name}"
        end
      end
    end
  end
end
