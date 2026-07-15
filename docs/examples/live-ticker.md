# Live Ticker

A panel of live numbers — a server clock, a drifting gauge — that updates itself every couple of seconds without being asked. The server holds a connection open and pushes fresh renderings down it; the client never polls.

This one has no direct counterpart in [htmx's examples catalog](https://htmx.org/examples/), which doesn't carry a server-sent-events demo — htmx covers SSE through its [SSE extension](https://htmx.org/extensions/sse/) rather than a catalog page. Weft builds on that same extension, and wraps the whole arrangement — the stream endpoint, the connection attributes, the event framing, even loading the extension script — into one declaration: [`pushes every: 2`](../dsl.md#pushes--the-server-sends-updates).

## The components

```ruby
# A drifting gauge: a small random walk that stands in for any live number
# your app can read on demand — active sessions, queue depth, a sensor.
module VisitorGauge
  class << self
    def reading
      @reading = (@reading || 142) + rand(-9..9)
    end
  end
end

class LiveTicker < Weft::Component
  builder_method :live_ticker

  pushes every: 2

  def build(attributes = {})
    super
    para "Server time: #{Time.now.strftime('%H:%M:%S')}"
    para "Visitors right now: #{VisitorGauge.reading}"
  end
end
```

## How it works

**One declaration, both ends of the wire.** `pushes every: 2` does two things at once. Server-side, the Router auto-generates an SSE endpoint for the component at its own path plus a stream suffix — `/_components/live_ticker/_stream` — where it re-renders the component every 2 seconds and pushes the result down the open connection. Client-side, the component renders with the htmx SSE attributes (`hx-ext="sse"`, `sse-connect`, `sse-swap`) already on its wrapper, so the connection opens as soon as the component lands in a page. (The `_stream` suffix is configurable — see [`stream_suffix`](../configuration.md#stream_suffix).)

**Pushed frames fill the component's interior.** Unlike a [`refreshes`](../dsl.md#refreshes--the-client-re-fetches) poll, which replaces the whole component, a pushed frame swaps `innerHTML`: the wrapper element *holds the SSE connection*, so it must persist while its contents are replaced underneath it. That's also why each frame's payload is the component's children only, with no wrapper div.

**Events are named after the component.** Each frame arrives as `event: live-ticker` — the component's DOM id — and the wrapper's `sse-swap="live-ticker"` subscribes to exactly that name. The two are generated from the same value, so they always agree.

**New subscribers get an immediate snapshot.** The first frame is pushed the moment the connection opens, then the 2-second cadence begins. A page that renders the component and connects a beat later doesn't sit stale for one interval — and a dropped connection that reconnects catches up instantly.

**The extension script ships itself.** Pages include the htmx SSE extension automatically when any registered component declares `pushes` — the [`include_sse_ext`](../configuration.md#include_sse_ext) setting, whose `:auto` default means apps without SSE components never ship the extra script and apps with them never have to remember it.

## On the wire

The initial render (or `GET /_components/live_ticker`) — the wrapper carries the connection wiring, and usable content is already inside:

```html
<div id="live-ticker" hx-ext="sse" sse-connect="/_components/live_ticker/_stream"
     sse-swap="live-ticker" hx-swap="innerHTML">
  <p>Server time: 15:39:53</p>
  <p>Visitors right now: 146</p>
</div>
```

The page it sits in has the extension script in its `<head>`, included automatically alongside htmx itself:

```html
<script src="https://unpkg.com/htmx.org@2.0.4" integrity="sha384-…" crossorigin="anonymous"></script>
<script src="https://unpkg.com/htmx-ext-sse@2.2.2/sse.js"></script>
```

Connecting to the stream — here with `curl -N`, held open for seven seconds — answers with SSE headers and then a frame every 2 seconds, the first one immediately:

```
HTTP/1.1 200 OK
content-type: text/event-stream;charset=utf-8
cache-control: no-cache
transfer-encoding: chunked

event: live-ticker
data:   <p>Server time: 15:39:53</p>
data:   <p>Visitors right now: 144</p>

event: live-ticker
data:   <p>Server time: 15:39:55</p>
data:   <p>Visitors right now: 151</p>

event: live-ticker
data:   <p>Server time: 15:39:57</p>
data:   <p>Visitors right now: 159</p>
```

Each multi-line rendering becomes consecutive `data:` lines in one event, per the SSE format; htmx reassembles them and swaps the result into the wrapper.

## Related

- [Progress Bar](progress-bar.md) — the polling counterpart: the client re-fetches on a timer instead of holding a connection.
- [`pushes`](../dsl.md#pushes--the-server-sends-updates) in the DSL reference; [`stream_suffix`](../configuration.md#stream_suffix) and [`include_sse_ext`](../configuration.md#include_sse_ext) in configuration.
- A component with params streams too — its wire state rides the `sse-connect` URL as query parameters, so each subscriber gets frames for *its* instance.
