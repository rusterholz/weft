# Weft

**Component-oriented hypermedia for Ruby.**

Weft lets you write your application in terms of its interface: components declare their structure, their data, and their interactive behaviors, and the framework derives the routing, request handling, and client-side wiring automatically.

```ruby
class DeliveryStatus < Weft::Component
  param :delivery_id, type: :integer

  derives(:delivery) { |params| Delivery.find(params.delivery_id) }

  performs(:cancel) { |params| CancelDelivery.call(params.delivery) }

  refreshes every: 5.seconds

  def build(attributes = {})
    super
    add_class "delivery-status"

    span "Delivery ##{params.delivery_id}"
    div(class: "delivery-detail") do
      progress_bar value: params.delivery.progress_percent, max: 100
      span "Arriving #{params.delivery.eta}"
      button "Cancel", action: :cancel if params.delivery.cancellable?
    end
  end
end
```

That's a complete, interactive UI component. The cancel button invokes a service and re-renders the result; the card polls for fresh state every 5 seconds. There's no routes file, no controller, no custom JavaScript — just Ruby describing what the UI is and what it does. The UI is the source of truth; the plumbing is implied.

Here is everything that renders — htmx wiring and all:

```html
<div id="delivery-status-4471" hx-get="/_components/delivery_status?delivery_id=4471"
     hx-trigger="every 5s" hx-swap="outerHTML" class="delivery-status">
  <span>Delivery #4471</span>
  <div class="delivery-detail">
    <div id="progress-bar" class="progress">
      <div class="progress-fill" style="width: 62%"></div>
    </div>
    <span>Arriving today, 4:15 PM</span>
    <button hx-post="/_components/delivery_status/cancel" hx-target="#delivery-status-4471"
            hx-swap="outerHTML" hx-vals="{&quot;delivery_id&quot;:4471}">Cancel</button>
  </div>
</div>
```

Every attribute above was derived from those four declarations: the routes (`GET /_components/delivery_status` for the component, `POST /_components/delivery_status/cancel` for the action), the DOM id that keeps this delivery individually addressable, the polling on the wrapper, and the button's whole request — where the response lands, how it swaps, and which params ride along with it. `progress_bar` is a child component with declarations of its own, rendered inline, wrapper and all.

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
| v0.1.0 | First usable release: the verb DSL, auto-routing with collision detection, interaction presets, SSE, error recovery, full documentation set | Shipped |
| v0.2.0 | The inputs model: four declared doors into `params`, typed wire params, values flowing down the render tree, one-call app loading, self-healing streams, brandable 404s | **Current** |
| v0.3 | The request–response lifecycle: how a request is addressed, carried, observed, and composed into a response | Next |

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

The call you'll want on day one is `Weft.configure_autoloading` — it puts Zeitwerk in charge of loading your app's directories, and with `reload: true` your edits (new files and deletions included) apply without restarting the server:

```ruby
Weft.configure_autoloading(
  paths: [File.expand_path("app/components", __dir__),
          File.expand_path("app/pages", __dir__)],
  reload: ENV.fetch("RACK_ENV", "production") == "development"
)
```

Gem-level settings live on its sibling, `Weft.configure` — static asset bundles, error presentation, routing overrides, logging — all in [the configuration reference](docs/configuration.md).

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

Bug reports and pull requests are welcome on GitHub at https://github.com/rusterholz/weft. The [development guide](docs/development.md) covers setup, the test suites, and the release process. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Weft project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
