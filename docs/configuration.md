# Configuration

Weft configures itself with sensible defaults — a new app needs no configuration at all. When you do want to change something, every gem-level setting lives on a single configuration object, set inside a `Weft.configure` block:

```ruby
Weft.configure do |c|
  c.log_level = :debug
  c.static_assets root: "/static", from: File.join(APP_ROOT, "public")
end
```

Call `Weft.configure` from your boot file (typically `config/environment.rb`), after `require "weft"` and before the first request. Settings are validated as they're assigned, so a typo'd value raises immediately at boot rather than misbehaving later. After the block runs, Weft applies any side effects the new settings imply (mounting static asset routes, enabling the reloader, setting the logger level). Calling `Weft.configure` more than once is fine — each call re-applies these side effects idempotently.

Every setting, at a glance:

| Setting | Default | Purpose |
| --- | --- | --- |
| [`auto_reload`](#auto_reload) | `false` | Enable code reloading on the Router during development. |
| [`reload_paths`](#reload_paths) | `[]` | Files the reloader should watch, as glob patterns. |
| [`router_logging`](#router_logging) | `false` | Request logging on the Router. |
| [`log_level`](#log_level) | `:info` | Severity threshold for `Weft.logger`. |
| [`include_htmx`](#include_htmx) | `true` | Pages include the htmx script automatically. |
| [`include_sse_ext`](#include_sse_ext) | `:auto` | Pages include the htmx SSE extension when needed. |
| [`static_assets`](#static_assets) | none | Serve a directory of files at a URL prefix. |
| [`component_path`](#component_path) | derives `/_components/<name>` | How a component class maps to its route. |
| [`stream_suffix`](#stream_suffix) | `"_stream"` | Path segment for SSE stream endpoints. |
| [`error_component`](#the-four-fallback-targets) | `Weft::Defaults::ErrorComponent` | Fragment rendered when a component fails. |
| [`error_page`](#the-four-fallback-targets) | `Weft::Defaults::ErrorPage` | Document rendered when a page fails. |
| [`not_found_component`](#the-four-fallback-targets) | `Weft::Defaults::NotFoundComponent` | Fragment rendered for a component-context 404. |
| [`not_found_page`](#the-four-fallback-targets) | `Weft::Defaults::NotFoundPage` | Document rendered for an unmatched route. |
| [`verbose_error_pages`](#verbose_error_pages) | `true` | Fallback renderings show exception details. |
| [`htmx_errors`](#htmx_errors) | `:fragment` | How htmx requests present fallback errors. |

## Development

### `auto_reload`

Default: `false`.

When `true`, Weft registers `Sinatra::Reloader` on `Weft::Router`, so code changes are picked up without restarting the server. Off by default; flip it on however you detect development mode:

```ruby
Weft.configure do |c|
  c.auto_reload = (ENV.fetch("RACK_ENV", "production") == "development")
  c.reload_paths = [File.expand_path("app/**/*.rb", __dir__)]
end
```

The reloader is registered once, the first time a `Weft.configure` call sees `auto_reload` set to `true` — it can't be unregistered afterward, and `reload_paths` entries added in later `configure` calls won't be picked up. Set both together, as above.

`auto_reload` suits apps that don't already have a reloading story. If your app manages its own constant loading with Zeitwerk, you may prefer to drive reloading yourself (`loader.reload` in a `Weft::Router.before` block) and leave this off. Either way, Weft's registry tolerates reloading: when a class is redefined, the stale registration is pruned automatically (see [Routing](routing.md)).

### `reload_paths`

Default: `[]`.

Glob patterns added to the reloader's watch list. Without this, `Sinatra::Reloader` only watches files where Weft defines its own routes — meaning edits to *your* components and pages would go unnoticed. Point it at your application code:

```ruby
c.reload_paths = [
  File.expand_path("app/**/*.rb", __dir__),
  File.expand_path("config/**/*.rb", __dir__)
]
```

Only meaningful alongside `auto_reload = true`, and must be set in the same `configure` call (or an earlier one).

### `router_logging`

Default: `false`.

When `true`, enables Sinatra's request logging on `Weft::Router`, so each request the Router serves is logged in the usual access-log format. Useful in development, or temporarily in production when debugging.

### `log_level`

Default: `:info`.

The severity threshold applied to `Weft.logger`. Any standard `Logger` severity symbol works: `:debug`, `:info`, `:warn`, `:error`, `:fatal`, `:unknown`.

`Weft.logger` itself is assignable. It defaults to a `$stdout` logger — the unified activity-and-error stream a twelve-factor deployment expects — but you can point it anywhere:

```ruby
Weft.logger = Rails.logger
```

Assign your logger *before* calling `Weft.configure`; the configure step applies `log_level` to whatever logger is current at that moment (mutating its `level`).

## Pages and assets

### `include_htmx`

Default: `true`.

`Weft::Page` automatically includes the htmx script in its `<head>`, loaded from a CDN at a version pinned by the gem, with a subresource-integrity hash. This is what makes a freshly generated page interactive with zero setup.

Set it to `false` to take control of htmx delivery yourself — for example, to self-host the file or bundle it with other scripts. You're then responsible for getting htmx onto the page (`register_script` on your base page class is the natural spot).

### `include_sse_ext`

Default: `:auto`.

Controls whether `Weft::Page` also includes the htmx SSE extension script, which components declaring `pushes` need for their live connections. Three values:

- `:auto` — include it only if some registered component declares `pushes`. The right answer for almost everyone: apps with no SSE components don't ship the extra script, and apps with them don't need to remember it.
- `true` — always include it. An escape hatch for setups where components load lazily and might not be registered yet when the first page renders, so `:auto` would miss them.
- `false` — never include it. Pair with self-hosting, as with `include_htmx`.

### `static_assets`

Default: none configured.

Registers a directory to be served at a URL prefix — Weft's minimal answer to serving your CSS, JavaScript, and images without a separate file-server layer:

```ruby
Weft.configure do |c|
  c.static_assets root: "/static", from: File.join(APP_ROOT, "public")
end
```

With that in place, a request for `/static/css/app.css` serves `public/css/app.css` (GET and HEAD only, with content-type and freshness headers handled for you, and path-traversal attempts rejected).

Unlike the other settings, `static_assets` is a method, not an assignment, and it can be called multiple times to register multiple *bundles* — each a named root/directory pair:

```ruby
c.static_assets root: "/static", from: File.join(APP_ROOT, "public")   # the :default bundle
c.static_assets name: :vendor, root: "/vendor", from: VENDOR_DIR
```

Bundle names are the stable reference used by pages. When a page registers an asset by bare relative path, the path resolves against a bundle's root — the one named by the `assets:` kwarg, or the `:default` bundle when the kwarg is omitted:

```ruby
class ApplicationPage < Weft::Page
  register_stylesheet "css/app.css"                  # → /static/css/app.css
  register_script "charts.js", assets: :vendor        # → /vendor/charts.js
  register_stylesheet "https://cdn.example.com/x.css" # absolute — used as-is
end
```

This indirection is the point of naming bundles: call sites reference a logical name, and the physical root and directory can be reconfigured (say, from environment variables in production) without touching any page class. Absolute URLs (`http://`, `https://`, `//`, or a leading `/`) always pass through unchanged; combining one with an `assets:` kwarg raises, since the kwarg would have no effect.

Any extra kwargs on `register_script` render as attributes on the emitted `<script>` tag — `defer: true`, `type: "module"`, and notably the subresource-integrity pair for third-party CDN scripts:

```ruby
register_script "https://cdn.example.com/widgets.js",
                integrity: "sha384-…", crossorigin: "anonymous"
```

(The htmx core and SSE-extension scripts Weft includes itself are integrity-pinned the same way.)

Registering a duplicate bundle name, or a second bundle at the same root, raises `Weft::InvalidConfiguration` — bundles are declared once, at boot.

## Routing

These two settings shape the URLs Weft generates. The full routing model — what gets a route, how collisions are detected, how pages route — lives in [Routing](routing.md).

### `component_path`

Default: a proc deriving `/_components/<name>`.

Maps a component class to its route path. The value must be a proc; it receives the class and returns the path string. The default strips a trailing `Component` from the class name, snake-cases what's left, and prefixes `/_components/` — so `OrdersPanelComponent` (or plain `OrdersPanel`) routes at `/_components/orders_panel`, and a namespaced `Admin::OrdersPanel` routes at `/_components/admin/orders_panel`.

Replace it to change the convention app-wide:

```ruby
c.component_path = ->(klass) { "/partials/#{klass.name.underscore}" }
```

For a one-off exception, don't reconfigure the gem — set `self.component_path = "/somewhere/else"` (a string or a proc) on the individual class instead. The class-level setting wins over this knob.

### `stream_suffix`

Default: `"_stream"`.

The path segment marking a component's SSE stream endpoint. A component declaring `pushes` gets its stream served at `<component path>/<stream_suffix>` — by default, `/_components/order_feed/_stream`. The setting is used on both sides of the connection: it's baked into the `sse-connect` URL the component renders, and it's how the Router recognizes stream requests.

Set a bare path segment — no slashes; Weft supplies the separator. The default's leading underscore keeps stream endpoints out of the namespace of derived component paths (which, coming from Ruby class names, never begin with an underscore).

## Error handling

Four settings name the fallback render targets Weft uses when something raises and no user-declared `recovers` entry intercepts it; two more shape how those fallbacks present. The full story — error classes, `recovers` chains, auto-injected attributes — lives in [Error handling](error-handling.md).

### The four fallback targets

| Setting | Default | Rendered when… |
| --- | --- | --- |
| `error_component` | `Weft::Defaults::ErrorComponent` | a component render or action raises |
| `error_page` | `Weft::Defaults::ErrorPage` | a full-document page render raises |
| `not_found_component` | `Weft::Defaults::NotFoundComponent` | `Weft::NotFound` is raised in a component context |
| `not_found_page` | `Weft::Defaults::NotFoundPage` | no route matches, or a page raises `Weft::NotFound` |

Assign your own subclasses to brand these app-wide:

```ruby
Weft.configure do |c|
  c.error_component = MyApp::ErrorComponent
  c.not_found_page = MyApp::NotFoundPage
end
```

The gem's built-in recovery chain resolves these settings at error-handling time, not at boot — so reassigning a knob propagates everywhere immediately, without re-declaring `recovers` on your classes. When one class needs different behavior than the rest of the app, declare an explicit `recovers` on it instead of reconfiguring the gem; see [Error handling](error-handling.md).

### `verbose_error_pages`

Default: `true`.

When `true`, the gem-default fallbacks show diagnostic detail: the error component displays the exception class and message, and the not-found component displays the requested path. Set it to `false` in production deploys to render the same fallbacks with generic text instead.

This setting is honored by the `Weft::Defaults` classes. If you assign custom fallback targets, honoring it is up to your implementations — check `Weft.configuration.verbose_error_pages` where you'd reveal detail.

### `htmx_errors`

Default: `:fragment`.

How errors present when the failing request came from htmx *and* the error fell through to a gem-default fallback target:

- `:fragment` — swap the error rendering into the failing element's place in the page. The error is visible exactly where the problem is; the rest of the page keeps working.
- `:redirect` — send the client to the error page instead (via an `HX-Redirect` header), abandoning the current page. Some apps prefer a full-page failure posture over patchwork error states.

Two carve-outs to know about: explicit `recovers` targets you declare are never overridden — this setting only governs the gem-default fallthrough — and `Weft::NotFound` is exempt, so a missing record renders as an in-place not-found fragment even under `:redirect`.
