# frozen_string_literal: true

module Weft
  class Router
    # SSE streaming slice of the Router. Handles `/component_path/<stream_suffix>`
    # requests (stream_suffix defaults to "_stream") for components declaring
    # `pushes every:`, opening a long-lived
    # connection that emits formatted `event:`/`data:` frames on the
    # declared cadence.
    #
    # Depends on Router internals: `build_component`, `render_oob_includes`,
    # `pass`, `content_type`, `headers`, `stream`.
    module Streaming
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
        interval = component_class.push_config[:every]
        klass = component_class

        stream :keep_open do |out|
          # New subscribers get an immediate state snapshot, then the regular
          # cadence — sleep only kicks in from the second frame onward. The flag
          # flips before the push (not after a *successful* one) so a persistently
          # failing push still throttles on the interval instead of busy-looping.
          after_first = false
          loop do
            sleep interval if after_first
            after_first = true
            push_component_event(out, klass)
          rescue Errno::EPIPE, IOError
            break
          rescue StandardError => e
            Weft.logger.error("SSE push error for #{klass.name}: #{e.message}")
          end
        end
      end

      def push_component_event(out, component_class)
        component = build_component(component_class)
        html = component.content + render_oob_includes(component_class, component.attrs)
        out << format_sse_event(component.weft_id, html)
      end

      def format_sse_event(event_name, html)
        sse_data = html.each_line.map { |line| "data: #{line.chomp}" }.join("\n")
        "event: #{event_name}\n#{sse_data}\n\n"
      end
    end
  end
end
