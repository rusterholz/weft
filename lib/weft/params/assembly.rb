# frozen_string_literal: true

require "weft/params"
require "weft/resolver"

module Weft
  class Params
    # Composes a params bag from every source that can supply one. The single
    # place that knows the source stack — components call it at construction
    # for their own bag, and the Router calls it at the top of a request for
    # the bag it hands the first verb block.
    #
    # The stack, top wins. `nil` never wins a level: it means that source
    # didn't have the key.
    #
    #   1. hand-off   a caller staged a value for this component (`receives`)
    #   2. overlay    a verb block earlier in this request returned the key
    #   3. own wire   the request supplied it and this class declares it
    #   4. inherited  the bag this one branched from had it
    #   5. derivation this class declares one (registered lazily, never run here)
    #   6. default    the declaration's own fallback
    #
    # The overlay speaks *as* the wire: its value replaces the wire's for that
    # key, and an explicit nil clears — masking the wire so resolution falls
    # below it. A derivation always "produces" (a thunk is never nil), so a
    # same-key default sits unreachable behind one.
    class Assembly
      class << self
        def call(...) = new(...).bag

        # The state a request composes before any component of its own exists —
        # what the first verb block sees. No caller and no enclosing build have
        # run, so the hand-off door isn't merely unsatisfied, it isn't there:
        # a `receives`-only key is absent, declared default and all. Dual it
        # with a `param` or a `defines` to make the key visible here.
        def for_request(component_class, wire_source)
          call(component_class, wire_source, hand_offs: nil)
        end

        # One-time shadowing warnings, keyed [kind, class, key]. Set#add? races
        # just double-warn; harmless.
        def warned = @warned ||= Set.new
      end

      # +branched_from+ is the bag this one inherits: a tree ancestor's during
      # a render, the state already composed at the top of a request. Passing
      # +hand_offs: nil+ says the door does not exist (see .for_request);
      # an empty hash says it exists and nobody staged anything.
      def initialize(component_class, wire_source, hand_offs: {}, overlays: {}, branched_from: nil)
        @component_class = component_class
        @received = hand_offs || {}
        @hand_offs = !hand_offs.nil?
        @overlays = overlays
        @wire = Weft::Resolver.resolve_present(component_class, wire_source)
        @inherited = branched_from ? branched_from.branch_data : {}
        @upstream_provenance = branched_from ? branched_from.provenance : {}
      end

      def bag
        data = @inherited.dup
        keys.each { |key| data[key] = stack_value(key) }
        report_shadowed_derivations(data)
        Weft::Params.new(data, provenance, defaults: declared_defaults)
      end

      private

      def keys
        return @component_class.declared_keys if @hand_offs

        @component_class.declared_keys - hand_off_only_keys
      end

      # Keys whose only door is `receives`. A dual key is declared on another
      # door too, so it stands on its own without a caller.
      def hand_off_only_keys
        @component_class.received_params.keys - @component_class.params.keys -
          @component_class.derived_params.keys
      end

      def stack_value(key)
        return @received[key] unless @received[key].nil?

        wire_level = @overlays.key?(key) ? @overlays[key] : @wire[key]
        [wire_level, @inherited[key], derived_thunk(key)].find { |v| !v.nil? }
      end

      # Fallbacks, not values: they ride on the bag rather than in it, so a
      # key nobody supplied reads as this class's default without becoming
      # something this class hands to anyone downstream.
      def declared_defaults
        keys.filter_map { |key| [key, default_for(key)] unless default_for(key).nil? }.to_h
      end

      def derived_thunk(key)
        meta = @component_class.derived_params[key]
        Weft::Params::Thunk.new(meta[:block]) if meta
      end

      # The wire door's default wins for dual keys — its meta always carries
      # one, and the wire door sits above the hand-off's fallback in the stack.
      def default_for(key)
        wire_meta = @component_class.params[key]
        return wire_meta[:default] if wire_meta

        @component_class.received_params[key]&.[](:default)
      end

      # Where the derivation in force for each key was declared — a map of
      # declarations, not of values. It tracks what *would* run, so it
      # survives the value being forced, and survives another source winning
      # the key outright: a derivation that lost is still a derivation
      # someone downstream can collide with. The nearest upstream declaration
      # wins, since its value is the one that would be inherited.
      def provenance
        declared = @upstream_provenance.dup
        @component_class.derived_params.each do |key, meta|
          declared[key] ||= meta[:source_location]
        end
        declared
      end

      # Two ways a declared derivation ends up dead, each said once per
      # (class, key). Neither is an error — both are shapes a component can
      # legitimately want — but both mean a block someone wrote never runs,
      # which is better heard than discovered.
      def report_shadowed_derivations(data)
        @component_class.derived_params.each do |key, meta|
          next unless @received[key].nil? && @wire[key].nil?

          warn_upstream_derivation(key, meta) unless @inherited[key].nil?
          warn_overlaid_derivation(key, meta) unless @overlays[key].nil?
        end
        data
      end

      # An inherited value won and was itself derived by a *different* block.
      # A shared proc (one derivation mixed into many classes) is agreement,
      # not divergence; values inherited through other doors carry no
      # derivation provenance and stay silent.
      def warn_upstream_derivation(key, meta)
        upstream = @upstream_provenance[key]
        return if upstream.nil? || upstream == meta[:source_location]
        return unless warn_once?(:upstream, key)

        Weft.logger.warn(
          "#{@component_class.name}: inherited #{key.inspect} (derived at #{upstream.join(':')}) " \
          "shadows this class's own derivation (#{meta[:source_location].join(':')}) — the " \
          "ancestor's value wins. Use distinct keys or share one derivation if that isn't intended."
        )
      end

      # A verb block earlier in this request returned the key. An overlay
      # speaks as the wire, so it outranks the derivation entirely — which is
      # exactly how a callable hands a record it already loaded to the render
      # below it, and also how a derivation quietly stops running.
      def warn_overlaid_derivation(key, meta)
        return unless warn_once?(:overlaid, key)

        Weft.logger.warn(
          "#{@component_class.name}: #{key.inspect} arrived from a verb block in this request and " \
          "outranks this class's own derivation (#{meta[:source_location].join(':')}), which will " \
          "not run. Return a different key, or drop the derivation if the block is its only source."
        )
      end

      def warn_once?(kind, key) = self.class.warned.add?([kind, @component_class, key])
    end
  end
end
