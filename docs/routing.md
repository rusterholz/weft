# Routing

Weft has no routes file. Defining a `Weft::Component` or `Weft::Page` subclass registers it, and `Weft::Router` serves it: components as HTML fragments at derived paths, pages as full documents at their declared patterns, actions and SSE streams at paths derived from their components. This document is the reference for how those routes come to be — and how to control the parts you sometimes need to.

**In this document:**

- [Mounting the Router](#mounting-the-router)
- [Component routes](#component-routes), including [action routes](#action-routes) and [stream endpoints](#stream-endpoints)
- [Page routes](#page-routes)
- [What routes — and what doesn't](#what-routes--and-what-doesnt), including [`abstract!` and `routable!`](#abstract-and-routable) and [routable vs. render target](#routable-vs-render-target)
- [Collision detection](#collision-detection)
- [Code reloading](#code-reloading)

## Mounting the Router

`Weft::Router` is Rack middleware. It serves the requests it recognizes and passes the rest through:

```ruby
# config.ru — alongside an existing app
use Weft::Router
run MyApp

# config.ru — standalone, Weft is the whole app
run Weft::Router
```

In standalone mode there is no downstream app, so unmatched requests render the configured not-found page instead (see [Error handling](error-handling.md)).

One prerequisite worth knowing: registration happens when a class is *defined* (via Ruby's `inherited` hook), so your component and page files must be loaded before the first request. If you use an autoloader, eager-load these directories at boot.

## Component routes

Every routable component is addressable at a GET route that renders it as an HTML fragment — the mechanism behind `refreshes`, `navigate:`, `loads:`, and the shorthands, and equally usable directly (`curl` it; you'll get the component's HTML).

The path derives from the class name: strip a trailing `Component` if present, snake-case what's left, prefix `/_components/`. Namespaces become path segments.

| Class | Route |
| --- | --- |
| `OrdersPanel` | `/_components/orders_panel` |
| `OrdersPanelComponent` | `/_components/orders_panel` |
| `Oms::OrderHeader` | `/_components/oms/order_header` |

The suffix-stripping means `OrdersPanel` and `OrdersPanelComponent` are the same route — pick whichever naming style your app prefers, consistently. The `/_components/` prefix keeps the fragment namespace visibly separate from your page URLs; the leading underscore marks it as infrastructure.

Attributes arrive as query parameters (`/_components/orders_panel?status=shipped&page=2`) and resolve through the component's declared schema — undeclared parameters are ignored, and declared ones are type-coerced from their defaults (see [Attributes](dsl.md#attributes)).

To change the path for one class, set `component_path` on it — a string, or a proc receiving the class:

```ruby
class OrdersPanel < Weft::Component
  self.component_path = "/api/panels/orders"
end
```

The setting is inherited by subclasses (handy on an abstract base for a whole family). To change the convention app-wide instead, replace the [`component_path` configuration proc](configuration.md#component_path).

### Action routes

Actions declared with `performs`/`transfers`/`dismisses` route under their component's path:

- **Named actions** get a subpath: `performs :advance` on `Oms::OrderHeader` routes at `POST /_components/oms/order_header/advance`.
- **Nameless actions** route at the component's own path, distinguished by HTTP method: `performs(method: :delete)` answers `DELETE /_components/oms/order_header`. A nameless GET action intercepts the component's render route itself.

The HTTP method comes from the declaration's `method:` kwarg (default `:post`); the Router answers GET, POST, PUT, DELETE, and PATCH.

### Stream endpoints

A component declaring `pushes` also gets an SSE endpoint at its path plus the stream suffix — by default, `/_components/order_feed/_stream`. The component's rendered `sse-connect` URL and the Router's stream handling both derive from the same [`stream_suffix` setting](configuration.md#stream_suffix), so they can't drift apart. The suffix's leading underscore keeps stream endpoints from ever colliding with a nested component path, since path segments derived from Ruby class names can't begin with an underscore.

## Page routes

Pages route as full HTML documents at people-facing URLs — no prefix, no derivation from fragments. A page declares its pattern with `page_path`, Sinatra-style, with `:param` segments mapping to attributes:

```ruby
class OrderDetailPage < Weft::Page
  self.page_path = "/orders/:order_id"
  attribute :order_id
end
```

A request for `/orders/42` renders the page with `attrs.order_id == "42"`. Path parameters merge with query and body parameters (path wins on conflicts), and the combined set resolves through the page's attribute schema like any other wire state.

The pattern is bidirectional — it also builds URLs. `Weft.redirect(OrderDetailPage, order_id: 42)` interpolates the attrs into the pattern, and `OrderDetailPage.redirect_url(order_id: 42, highlight: "items")` additionally turns declared-but-not-in-path attrs into a query string (undeclared keys are discarded, never leaked into URLs).

Pages without an explicit `page_path` infer one from the class name: demodulized, snake-cased, with a trailing `Page` stripped if present — `DashboardPage` and `Dashboard` both route at `/dashboard`. Two edges of the inference to know:

- A page with **attributes** must declare `page_path` explicitly — a parameterized pattern can't be guessed from a name, so Weft raises with the pattern it suggests rather than inventing one.
- A page named such that nothing usable remains after stripping (`Admin::Page`) also raises, with the remediation options spelled out.

## What routes — and what doesn't

Registration and routability are separate ideas. *Every* `Weft::Component` and `Weft::Page` subclass registers; whether it gets a route is inferred from what it declares:

- A **component** is routable when it declares interactive behavior: any attribute, action, `refreshes`, or `pushes`. A purely presentational component — just a `build` method — registers but is never served; there's nothing to address it *for*.
- A **page** is routable when it has a usable path: an explicit `page_path`, or a name the default can be derived from (and no attributes, per the edge above).

### `abstract!` and `routable!`

When the inference gets it wrong, override it — per class, in either direction:

```ruby
class ApplicationPage < Weft::Page
  abstract!            # shared assets and recoveries; not itself a destination
end
```

`abstract!` marks a class non-routable no matter what it declares; `routable!` forces the opposite. The override applies only to the class that declares it — subclasses of an abstract base infer (or declare) their own routability, so the common pattern of an abstract `ApplicationPage`/`ApplicationComponent` with concrete routable children just works.

### Routable vs. render target

"Routable" means *addressable at its own GET URL* — and that is orthogonal to being a **render target**. Verbs with transfer semantics (`transfers to:`, `recovers with:`) render their target on the server, inside an in-flight response; the target class needs attributes to render with, but no route of its own. Weft's own default error components work exactly this way: they're `abstract!`, unreachable by URL, and rendered constantly.

Navigation-semantic wiring (`refreshes`, `navigate:`, `loads:`, shorthands) *does* need its target addressable — and here the inference has a gap to watch. Declaring `refreshes` makes a component routable, but being the *target* of another component's `loads:` or shorthand kwarg confers nothing: a target with no attributes and no verbs of its own quietly stays off the route table, and the element wired to load it gets a not-found response at interaction time. Most real targets declare attributes and route on their own; for a purely presentational one, declare `routable!` explicitly. Where you'll reach for `abstract!` is the opposite case: a transfer target that declares attributes (so it can render) but should never be an endpoint — declare it abstract and it carries attributes for rendering while staying off the route table.

## Collision detection

Distinct classes can resolve to the same route — two same-named classes in different namespaces under a custom `component_path` proc, a page pattern matching a component path, a class named such that suffix-stripping collides with a sibling. Rather than letting one silently shadow the other, Weft validates the whole route table on the first request: every routable component's path, each component's reserved stream endpoint, and every routable page pattern. Any duplicate raises `Weft::InvalidDefinition` naming both parties:

```
Route collision on "/_components/orders_panel": component Oms::OrdersPanel and
component Admin::OrdersPanel resolve to the same route. Rename one class, set an
explicit component_path/page_path, or mark one abstract! if it should not route.
```

The same validation rejects malformed paths (anything that isn't a string beginning with `/`) from a misbehaving custom proc. Validation runs once and is memoized; registering a new class re-arms it. Non-routable classes occupy no route and can never collide.

## Code reloading

Development-mode reloaders redefine constants, which would strand the *old* class object in Weft's registry — and a stale twin at the same path would read as a route collision. Weft prunes superseded registrations automatically: at route-resolution time it drops any registered class whose name no longer resolves to that same class object. The sweep is memoized per registry generation, so production pays it once, ever.

This works with any reloading setup — [`auto_reload`](configuration.md#auto_reload), or your own Zeitwerk `reload` hook. `Weft.registry.clear` is the explicit full-reset primitive if your integration wants to rebuild registration from scratch.
