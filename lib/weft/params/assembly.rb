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
    #   1. handoff   a caller staged a value for this component (`receives`)
    #   2. overlay    a verb block earlier in this request returned the key
    #   3. own wire   the request supplied it and this class declares it
    #   4. inherited  the bag this one branched from had it
    #   5. derivation this class declares one (registered lazily, never run here)
    #   6. default    the declaration's own fallback
    #
    # The overlay speaks *as* the wire: its value replaces the wire's for that
    # key, and an explicit nil clears — masking the wire so resolution falls
    # below it. A derivation always "produces" (a thunk is never nil), so a
    # same-key default sits unreachable behind one. A nil handoff clears in the
    # same spirit but from the other end: it steps aside, and resolution
    # continues at this class's own wire.
    #
    # Levels 1, 2 and 4 all arrive on the bag being branched from, and the split
    # is the point: its data demotes to inherited, while its overlay and its
    # handoffs keep their own rungs the whole way down. A handoff accumulates
    # as it descends — a nearer call site's values merge over an ancestor's, per
    # key — which is what lets four cards from one collection each hand their own
    # value to the badge inside them. Nothing passes an overlay in from outside:
    # a call site that wants one applies it to the bag first (`bag % delta`),
    # which is also what keeps the two rungs from carrying the same delta at once.
    class Assembly
      class << self
        def call(...) = new(...).bag

        # The state a request composes before any component of its own exists —
        # what the first verb block sees. No caller and no enclosing build have
        # run, so the handoff door isn't merely unsatisfied, it isn't there.
        # A declared default still answers — a fallback belongs to the class,
        # not to the door, and writing it a second time as a `defines` would
        # only invite the two copies to drift. A key that declared none has
        # nowhere to come from: reading it raises {Weft::UnreachableHandoff}.
        def for_request(component_class, wire_source)
          call(component_class, wire_source, handoffs: nil)
        end

        # One-time shadowing warnings, keyed [kind, class, key]. Set#add? races
        # just double-warn; harmless.
        def warned = @warned ||= Set.new
      end

      # +branched_from+ is the bag this one inherits: a tree ancestor's during
      # a render, the state already composed at the top of a request. Passing
      # +handoffs: nil+ says the door does not exist (see .for_request);
      # an empty hash says it exists and nobody staged anything.
      # +violations+ is reported, never raised on: assembling is reading, and
      # the error path assembles too. Construction is where a component commits
      # to the values, so construction is where the refusal belongs — which is
      # also what leaves a *populated* bag for recovery to redraw from.
      attr_reader :violations

      def initialize(component_class, wire_source, handoffs: {}, branched_from: nil)
        @component_class = component_class
        @handoffs = !handoffs.nil?
        @received = inherited_handoffs(branched_from).merge(handoffs || {})
        @overlays = branched_from ? branched_from.send(:overlay_slot) : {}
        resolution = Weft::Resolver.resolution(component_class, wire_source)
        @wire = resolution.coerced
        @violations = resolution.violations
        @inherited = branched_from ? branch_copies(branched_from.send(:branch_data)) : {}
      end

      # The overlay rides onto the new bag as well as being consulted here, and
      # both are load-bearing: consulting it ranks the delta above this class's
      # own wire, and carrying it is what lets the same delta outrank the wire of
      # every class below. Data, by contrast, is spent — it arrives as inherited
      # and leaves as this bag's own.
      def bag
        data = @inherited.dup
        keys.each { |key| data[key] = stack_value(key) }
        report_shadowed_derivations(data)
        adopt_thunks(data, Weft::Params.new(data, defaults: declared_defaults,
                                                  owner: @component_class, overlay: @overlays,
                                                  handoff: @received))
      end

      private

      # The handoffs already in force for the subtree this branch lands in.
      # A nearer call site's staging merges over these, so the innermost
      # `insert_tag` wins per key while keys nobody nearer mentioned keep the
      # ancestor's value.
      def inherited_handoffs(branched_from)
        branched_from ? branched_from.send(:handoff_slot) : {}
      end

      # What crosses the branch. A contextual thunk crosses as an unforced
      # twin, so no two branches ever share its outcome; everything else
      # crosses as itself, carrying whatever it has settled on.
      #
      # Copying here — at branch time — rather than when a thunk is forced is
      # what makes it independent of read order. Copy-on-force would let a bag
      # that read early hand its memo to anything branching from it afterwards,
      # which is the behavior this replaces.
      def branch_copies(inherited)
        inherited.transform_values do |entry|
          entry.is_a?(Weft::Params::Thunk) && entry.contextual? ? entry.unforced_copy : entry
        end
      end

      # Give this assembly's own thunks a home, so a shared derivation answers
      # with the value its declaring component sees rather than whichever
      # branch happens to read it first. Only homeless thunks are adopted:
      # an inherited one already belongs to the bag that introduced it, and
      # that is precisely what must not be overwritten here.
      def adopt_thunks(data, bag)
        data.each_value do |entry|
          entry.home = bag if entry.is_a?(Weft::Params::Thunk) && entry.home.nil?
        end
        bag
      end

      def keys
        return @component_class.declared_keys if @handoffs

        @component_class.declared_keys - handoff_only_keys
      end

      # Keys whose only door is `receives`. A dual key is declared on another
      # door too, so it stands on its own without a caller.
      def handoff_only_keys
        @component_class.received_params.keys - @component_class.params.keys -
          @component_class.derived_params.keys
      end

      # An overriding derivation is consulted before the inherited value, so
      # this class's declaration claims the key for its own subtree. Everything
      # above `inherited` is untouched: a wire value still wins, and so does a
      # verb block's overlay, which speaks as the wire.
      def stack_value(key)
        return @received[key] unless @received[key].nil?

        wire_level = @overlays.key?(key) ? @overlays[key] : @wire[key]
        levels = overriding?(key) ? [wire_level, derived_thunk(key)] : [wire_level, @inherited[key], derived_thunk(key)]
        levels.find { |v| !v.nil? }
      end

      def overriding?(key) = @component_class.derived_params[key]&.[](:override) || false

      # Fallbacks, not values: they ride on the bag rather than in it, so a
      # key nobody supplied reads as this class's default without becoming
      # something this class hands to anyone downstream. Spans every declared
      # key rather than only the ones this bag holds an entry for — which is
      # what carries a handoff's fallback onto the paths where the door
      # itself is absent.
      def declared_defaults
        @component_class.declared_keys.filter_map { |key| declared_default(key) }.to_h
      end

      def derived_thunk(key)
        meta = @component_class.derived_params[key]
        Weft::Params::Thunk.new(meta[:block], contextual: meta[:contextual]) if meta
      end

      # The wire door's default wins for dual keys — its meta always carries
      # one, and the wire door sits above the handoff's fallback in the stack.
      # Which is also why only `receives` can declare a *nil* fallback: a
      # param's meta cannot tell a written nil from an unwritten one, and a
      # handoff's can, so the two doors answer separately.
      def declared_default(key)
        if (wire_meta = @component_class.params[key])
          [key, wire_meta[:default]] unless wire_meta[:default].nil?
        else
          handoff_default(key)
        end
      end

      def handoff_default(key)
        meta = @component_class.received_params[key]
        [key, meta[:default]] if meta&.key?(:default)
      end

      # A declared derivation that never runs, said once per (class, key).
      #
      # Only the overlay case is worth saying anything about. Being shadowed
      # by an ancestor's own derivation is the intended fallback idiom —
      # derive for the standalone render, inherit the richer value when
      # nested — and it is a fact about *this* render, not about the class:
      # the same component's block runs when it answers its own refresh. It
      # is also free, since an unrun derivation is a thunk nobody forced.
      def report_shadowed_derivations(data)
        @component_class.derived_params.each do |key, meta|
          next unless @received[key].nil? && @wire[key].nil?

          warn_overlaid_derivation(key, meta) unless @overlays[key].nil?
        end
        data
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
