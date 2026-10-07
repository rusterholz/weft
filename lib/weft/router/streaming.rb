# frozen_string_literal: true

module Weft
  class Router
    # SSE streaming slice of the Router. Handles `/component_path/<stream_suffix>`
    # requests (stream_suffix defaults to "_stream") for components declaring
    # `pushes every:`, opening a long-lived
    # connection that emits formatted `event:`/`data:` frames on the
    # declared cadence.
    #
    # Push failures route through the component's recovers chain (component
    # targets only — see Errors#render_push_recovery) and count against an
    # attempts budget; when it runs out, the CLOSE_EVENT frame tells the
    # client to stop reconnecting and the connection closes.
    #
    # Depends on Router internals: `build_root`, `root_bag`,
    # `weft_request`, `new_frame`, `render_push_companions`, `render_push_recovery`,
    # `pass`, `content_type`, `headers`, `stream`.
    module Streaming
      # SSE event name that tells htmx-ext-sse to close the EventSource and
      # stop reconnecting; every pushing component's wrapper names it in its
      # sse-close attribute (Component#apply_push_attrs).
      CLOSE_EVENT = "weft:close"

      private

      def handle_stream_request(path)
        component_path = path.delete_suffix("/#{Weft.configuration.stream_suffix}")
        component_class = Weft.registry.lookup(component_path)

        if component_class&.push_config&.key?(:every)
          stream_component(component_class)
        else
          pass
        end
      end

      def stream_component(component_class)
        content_type "text/event-stream"
        headers "Cache-Control" => "no-cache"
        klass = component_class
        # The block outlives the route, so it holds the request that opened
        # the stream rather than asking for one later.
        opener = weft_request

        stream :keep_open do |out|
          run_push_loop(out, klass, request: opener)
          # Both exits — dead client and exhausted attempts — are final, so
          # close explicitly: under :keep_open, merely returning from this
          # block does not end the response (observed on Puma as the block
          # re-running and the countdown restarting on a live connection).
          out.close
        end
      end

      # New subscribers get an immediate state snapshot, then the regular
      # cadence — sleep only kicks in from the second frame onward — unless
      # the component declared `immediate: false`, which pre-arms the sleep.
      # The flag flips before the push (not after a *successful* one) so a
      # persistently failing push still throttles on the interval instead of
      # busy-looping.
      def run_push_loop(out, klass, request: weft_request)
        interval = klass.push_config[:every]
        attempts = push_attempts(klass)
        after_first = !klass.push_config.fetch(:immediate, true)
        failures = 0
        loop do
          sleep interval if after_first
          after_first = true
          frame = new_frame(request)
          push_component_event(out, klass, frame)
          failures = 0
        rescue Errno::EPIPE, IOError
          break
        rescue StandardError => e
          failures += 1
          break unless push_failure_frames(out, klass, e, frame, failures: failures, attempts: attempts)
        end
      end

      def push_attempts(klass) = klass.push_config[:attempts] || Weft.configuration.push_attempts

      def push_component_event(out, component_class, frame = new_frame)
        root = root_bag(component_class, frame.request)
        component = build_root(component_class, frame, branch_bag: root)
        html = component.content + render_push_companions(component_class, component.params, frame)
        out << format_sse_event(component.weft_dom_id, html)
      end

      # A failure cycle's frames: the recovery fragment (when the chain yields
      # a component target) and, once the attempts budget is spent, the close
      # event that tells the client to stop reconnecting. Returns false when
      # the stream is done — budget exhausted or the client vanished mid-write.
      def push_failure_frames(out, component_class, error, frame, failures:, attempts:)
        Weft.logger.error("SSE push error for #{component_class.name}: #{error.message}")
        remaining = attempts - failures
        push_recovery_frame(out, component_class, error, remaining, frame)
        return true if remaining.positive?

        Weft.logger.error(
          "SSE stream for #{component_class.name} closed after #{attempts} consecutive failed pushes"
        )
        out << format_sse_event(CLOSE_EVENT, "")
        false
      rescue Errno::EPIPE, IOError
        false
      end

      # Resolve, render, write. The event name is recomputed from the class and
      # its assembled bag — the failed build left no instance to ask — and is
      # the slot the recovery fills in the failed push's frame. Any
      # render-path StandardError is logged and swallowed: the failure already
      # counts against the budget, and the close logic must still run.
      def push_recovery_frame(out, component_class, error, attempts_remaining, frame)
        state = root_bag(component_class)
        slot = component_class.weft_dom_id_for(state)
        html = render_push_recovery(component_class, state, error,
                                    attempts_remaining: attempts_remaining, frame: frame || new_frame, fills: slot)
        out << format_sse_event(slot, html) if html
      rescue Errno::EPIPE, IOError
        raise
      rescue StandardError => e
        Weft.logger.error("Push recovery render failed: #{e.class}: #{e.message}")
      end

      def format_sse_event(event_name, html)
        sse_data = html.each_line.map { |line| "data: #{line.chomp}" }.join("\n")
        sse_data = "data: " if sse_data.empty? # dataless SSE events are never dispatched
        "event: #{event_name}\n#{sse_data}\n\n"
      end
    end
  end
end
