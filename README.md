# Weft

**Component-oriented hypermedia for Ruby.**

Weft lets you write your application in terms of its interface: components declare their structure, their data, and their interactive behaviors, and the framework derives the routing, request handling, and client-side wiring automatically.

```ruby
class DeliveryStatus < Weft::Component
  param :delivery_id

  refreshes every: 5.seconds

  performs :cancel do |params|
    delivery = Delivery.find(params.delivery_id)
    CancelDelivery.call(delivery)
  end

  def build(attributes = {})
    super
    delivery = Delivery.find(params.delivery_id)
    div(class: "delivery-status") do
      progress value: delivery.progress, max: 100
      button "Cancel", action: :cancel if delivery.cancelable?
      span "Arriving #{delivery.eta}"
    end
  end
end
```

That's a complete, interactive UI component. It polls for updates every 5 seconds. The cancel button invokes a service and re-renders the result. There's no routes file, no controller, no custom JavaScript — just Ruby describing what the UI is and what it does. The UI is the source of truth; the plumbing is implied.

Weft is built on [Arbre](https://github.com/activeadmin/arbre) for HTML generation and [htmx](https://htmx.org) for hypermedia interactions. It runs standalone as a lightweight Sinatra-backed server, or mounts as middleware inside any existing Rack app. No build step, no npm, no hydration — just Ruby, HTML, and HTTP.

### The verbs

Components declare their dynamic behaviors with verbs:

| Verb | What it does |
|------|-------------|
| `refreshes every: 5.seconds` | Client re-fetches on a timer |
| `refreshes on: "event"` | Client re-fetches when a page event fires |
| `pushes every: 5.seconds` | Server streams re-renders over SSE |
| `performs :name` | User-initiated action: runs your callable, re-renders |
| `transfers :name, to: Other` | Action that renders a different component in this one's place |
| `dismisses :name` | Action that removes the component from the DOM |
| `triggers "event"` | Announces this component's actions to the rest of the page |
| `includes Other` | Companion components ride along in action responses, out-of-band |
| `recovers from: Err, with: Fallback` | Declares what renders when something raises |

Elements get their own vocabulary — `action:`, `loads:`, `trigger:` kwargs and interaction presets like `tooltip:`, `modal:`, `lazy:`, `infinite_scroll:` — all covered in [the DSL reference](docs/dsl.md).

## Documentation

- **[Build your first Weft app](docs/tutorial.md)** — the tutorial: empty directory to a working app with pages, components, a validated form action, and live updates.
- **[Examples](docs/examples/README.md)** — twenty-one worked patterns with captured wire traffic. Coming from htmx? This catalog deliberately covers the ground of htmx's own examples.
- **[The Weft DSL](docs/dsl.md)** — every verb, element kwarg, and interaction preset.
- **[How params flow](docs/params.md)** — the data lifecycle: a request comes in, each component pulls what it needs through `param`/`receives`/`derives`/`defines`, and renders with enough of its own wire state to refresh or act on its own.
- **[Application patterns](docs/app-patterns.md)** — the app around the components: service objects, databases, background jobs, authentication, CSRF, assets, and testing.
- **[Arbre: the HTML layer](docs/arbre.md)** — the HTML builder inside every `build` method, in depth.
- **[Routing](docs/routing.md)** — how classes become URLs, what's routable, and collision detection.
- **[Error handling](docs/error-handling.md)** — the error classes, recovery chains, and branding your error pages.
- **[Configuration](docs/configuration.md)** — every setting.

## Roadmap & Availability

| Version | Features | Status |
|---------|---------|--------|
| v0.1.0 | First usable release: the verb DSL, auto-routing with collision detection, interaction presets, SSE, error recovery, full documentation set | **Current** |
| v0.2 | Attribute hydration (resolver reification), child-component ergonomics, SSE error recovery, Zeitwerk integration | Next |

## Installation

Weft requires Ruby 3.2 or newer. Add it to your Gemfile:

```ruby
gem "weft"
```

Then run:

```bash
bundle install
```

## Usage

Weft mounts into your Rack app in one of two shapes, depending on whether Weft is the entire application or just a part of one.

### Standalone — Weft is the app

For a fully Weft-powered application, run `Weft::Router` as the Rack app itself:

```ruby
# config.ru
require_relative "config/environment"   # loads your components and pages

run Weft::Router
```

Components and pages auto-route based on their class declarations: components serve HTML fragments under `/_components/<name>`, pages serve full documents at their `page_path` (or a name-derived default). If two routable classes would resolve to the same path, Weft raises on the first request, naming both. [Routing](docs/routing.md) has the full story, and [the tutorial](docs/tutorial.md) walks through a working `config/environment.rb`.

### As middleware — alongside an existing app

For adding Weft to an existing Rack app (Sinatra, Rails, anything Rack), mount it as middleware. Unmatched paths fall through to your downstream app:

```ruby
# config.ru
require_relative "config/environment"
require_relative "app"   # your existing application

use Weft::Router
run MyApp
```

### Configuration

`Weft.configure` exposes gem-level settings — the two you'll want on day one are the development reloader flags:

```ruby
Weft.configure do |c|
  c.auto_reload = (ENV.fetch("RACK_ENV", "production") == "development")
  c.reload_paths = [File.expand_path("app/**/*.rb", __dir__)]
end
```

Everything else — static asset bundles, error presentation, routing overrides, logging — is in [the configuration reference](docs/configuration.md).

### Customizing error and not-found pages

Assign your own fallback classes once, and every recovery path uses them:

```ruby
Weft.configure do |c|
  c.error_component = MyApp::ErrorComponent
  c.not_found_page = MyApp::NotFoundPage
end
```

Per-class `recovers` declarations override the app-wide fallbacks where you need finer grain. [Error handling](docs/error-handling.md) covers the error classes, the recovery chain, and the attributes your fallback pages can receive.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rusterholz/weft. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Weft project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
