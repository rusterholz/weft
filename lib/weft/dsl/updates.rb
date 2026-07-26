# frozen_string_literal: true

module Weft
  module DSL
    # Mixin for classes that declare live-update behavior — polling and
    # event-driven refreshes (`refreshes`) and SSE push streams (`pushes`).
    # Included into Weft::Component.
    module Updates
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declare that this component refreshes automatically.
        #
        #   refreshes every: 10.seconds          # polling
        #   refreshes on: "delivery-completed"   # event-driven
        #   refreshes every: 10, on: "updated"   # both
        #
        # Generates hx-get, hx-trigger, hx-swap on the wrapper element.
        # Multiple calls accumulate into a single hx-trigger value.
        # Fractional intervals render in htmx's millisecond syntax.
        def refreshes(every: nil, on: nil)
          if every
            ms = interval_in_ms(every, :refreshes)
            own_refresh_triggers << ((ms % 1000).zero? ? "every #{ms / 1000}s" : "every #{ms}ms")
          end
          own_refresh_triggers << "#{on} from:body" if on
        end

        # Declare that this component pushes updates via SSE.
        #
        #   pushes every: 5.seconds                  # server pushes on interval
        #   pushes every: 5.seconds, attempts: 5     # custom failure budget
        #   pushes every: 5.seconds, immediate: false # wait a full interval first
        #
        # Generates hx-ext="sse", sse-connect, sse-swap, sse-close on the
        # wrapper element. The Router auto-generates a streaming endpoint at
        # /component_path/_stream (the suffix is the stream_suffix config knob).
        # `attempts:` overrides Weft.configuration.push_attempts — consecutive
        # failed pushes tolerated before the Router closes the stream.
        # `immediate:` defaults to true (new subscribers get a state snapshot
        # right away); `immediate: false` opts back into polling-cadence
        # semantics — first frame after one interval — for components whose
        # current state would mislead a fresh subscriber.
        #
        # Future: pushes on: "event-name" for event-driven server push (v1.0).
        def pushes(every: nil, attempts: nil, immediate: nil)
          @push_config = {}
          if every
            ms = interval_in_ms(every, :pushes)
            @push_config[:every] = (ms % 1000).zero? ? ms / 1000 : ms / 1000.0
          end
          @push_config[:attempts] = validated_attempts(attempts) if attempts
          # nil-guarded, not truthiness: `immediate: false` must persist.
          @push_config[:immediate] = immediate unless immediate.nil?
        end

        # Push configuration (own or inherited). Returns nil if no pushes declared.
        def push_config
          if instance_variable_defined?(:@push_config)
            @push_config
          elsif superclass.respond_to?(:push_config)
            superclass.push_config
          end
        end

        # All declared refresh triggers (own + inherited).
        def refresh_triggers
          if superclass.respond_to?(:refresh_triggers)
            superclass.refresh_triggers | own_refresh_triggers
          else
            own_refresh_triggers.dup
          end
        end

        private

        def own_refresh_triggers
          @own_refresh_triggers ||= []
        end

        # A budget below one failed push makes no sense — the stream would
        # close before its first recovery frame; rather than raise
        # mid-declaration, clamp and say so.
        def validated_attempts(attempts)
          return attempts if attempts.is_a?(Integer) && attempts >= 1

          Weft.logger.warn(
            "#{name} declares `pushes attempts: #{attempts.inspect}`, not a positive integer; using 1"
          )
          1
        end

        # htmx's smallest expressible interval is 1ms; rather than emit an
        # "every 0s" that polls flat-out, round up and say so.
        def interval_in_ms(every, verb)
          ms = (every.to_f * 1000).round
          return ms if ms.positive?

          Weft.logger.warn(
            "#{name} declares `#{verb} every: #{every.inspect}`, below the 1ms floor; using 1ms"
          )
          1
        end
      end
    end
  end
end
