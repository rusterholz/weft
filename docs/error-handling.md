# Error handling

In a component-oriented UI, an error is part of the interface. When one component's render or action raises, the right outcome is usually a visible error state *in that component's place* — not a dead button, not a blank region, and certainly not a whole-page crash. Weft's error handling is built around that idea: exceptions map to renderable fallbacks through a declarative chain, with sensible defaults at every level, so an unhandled error always lands somewhere visible.

Two layers cooperate to make this work. On the server, the Router catches errors and renders a recovery target instead. On the client, `Weft::Page` configures htmx to swap error responses into the page (by default htmx discards them) — which is why a failing component shows its error box right where the component was.

**In this document:**

- [The error classes](#the-error-classes)
- [The `recovers` chain](#the-recovers-chain) — matching, targets, blocks, and [the built-in edges](#the-built-in-edges)
- [What happens when something raises](#what-happens-when-something-raises)
- [Auto-injected recovery attributes](#auto-injected-recovery-attributes)
- [Presentation settings](#presentation-settings)

## The error classes

Weft ships a small semantic hierarchy rooted at `Weft::Error`:

| Class | Status | Meaning |
| --- | --- | --- |
| `Weft::Error` | — | Abstract root. Never raised directly; `rescue Weft::Error` catches the whole family. |
| `Weft::HTTPError` | — | Abstract intermediate for errors that carry an HTTP status. |
| `Weft::NotFound` | 404 | The thing addressed doesn't exist. |
| `Weft::Unauthorized` | 401 | Authentication required. |
| `Weft::Forbidden` | 403 | Authenticated, but not allowed. |
| `Weft::Unprocessable` | 422 | The request was understood but can't be acted on — validation failures, mostly. |
| `Weft::InternalError` | 500 | An explicit "we broke" signal. |

Raise these from your `build` methods and action callables to communicate outcomes with the right status semantics: `raise Weft::NotFound` when a record lookup comes up empty, `raise Weft::Unprocessable` when validation fails. Errors that aren't `Weft::HTTPError`s — an unrescued `ActiveRecord::RecordNotFound`, a `NoMethodError` — are treated as status 500.

A separate branch of the family reports *your* mistakes to you, raised at definition or configuration time rather than during request handling: `Weft::InvalidConfiguration` (a bad value inside `Weft.configure`), `Weft::InvalidDefinition` (a bad class-body declaration, including route collisions), and `Weft::InvalidUsage` (a bad call at render time). These are meant to fail loudly during development, not to be recovery targets.

## The `recovers` chain

Components and pages declare how they handle errors with `recovers`:

```ruby
class OrderEditor < Weft::Component
  recovers from: Weft::Unprocessable do |attrs, error|
    { error_message: error.message }
  end
  recovers from: Weft::Unauthorized, with: LoginPage
end
```

Each declaration is an edge: *when this kind of error escapes me, render that instead.* The pieces:

**`from:`** decides whether an edge matches a given exception. It accepts:


- a **Class** — matches that exception class and its subclasses (`from: Weft::HTTPError` catches the whole status-bearing family);
- an **Integer** — matches by HTTP status (`from: 404`);
- a **Range** — matches statuses in the range (`from: 500..599`);
- an **Array** of any of the above — matches if any element does.

**`with:`** names the recovery target — what renders in place of the failure. It accepts a component or page class, or a symbol naming a [configuration knob](configuration.md#the-four-fallback-targets) (`with: :error_component`), resolved at error-handling time so reconfiguration propagates. Omitted, it defaults to the declaring class itself — "on this error, re-render me" — which pairs naturally with a block that adjusts attrs.

**The block**, if given, receives `(attrs, error)` — the same resolved attrs an action callable sees, plus the exception — and returns a hash merged into the attrs the recovery target renders with (returned keys win). It's for *carrying information onto the error rendering*, like the validation messages above; it never returns HTML.

Edges are consulted in a defined order: a class's own declarations first (in declaration order), then its ancestors' — so subclass declarations beat inherited ones, and within a class, first match wins. Put more-specific edges before catch-alls.

### The built-in edges

`Weft::Component` and `Weft::Page` each ship two edges, which is why error handling works before you've declared anything:

```ruby
# on Weft::Component
recovers from: Weft::NotFound, with: :not_found_component
recovers from: StandardError, with: :error_component

# on Weft::Page
recovers from: Weft::NotFound, with: :not_found_page
recovers from: StandardError, with: :error_page
```

The symbols resolve through `Weft.configuration`, so [reassigning those knobs](configuration.md#the-four-fallback-targets) rebrands the defaults app-wide. Because these live on the base classes, any edge you declare on your own class takes precedence.

## What happens when something raises

**In component context** — a fragment render, an action, an SSE frame — the Router walks the failing component's chain and renders the matched target as a fragment, with the response status taken from the exception (`Weft::HTTPError#status`, else 500). On the client, the fragment swaps in where the component's response would have gone, so the error appears exactly where the problem is. If the matched target is a *page* class, the recovery becomes a redirect to that page instead (`HX-Redirect` for htmx requests, 302 otherwise) — the `with: LoginPage` pattern above.

One wrinkle worth knowing: for actions with a destructive swap (`dismisses`, or any `performs` with `swap: :delete`), a successful response removes the element — which would make an error invisible. Weft overrides the swap on error responses (via `HX-Reswap`) so the error rendering replaces the component instead of vanishing with it.

**In page context** — a full-document render, or a request no route matched — the Router walks the page's chain (for routing misses, the base `Weft::Page` chain, which lands on the not-found page). A traditional request gets the recovery page as a complete document; an htmx request gets just the page's body content, since the document shell is already on the client.

**If the recovery itself raises** — a bug in your error component, say — Weft stops walking and emits a minimal hardcoded error rendering, logging the recovery failure and surfacing the *original* error. There is always a floor; error handling never recurses into itself.

Errors during SSE pushes don't kill the stream: the frame is skipped, the error logged, and pushing resumes on the next interval.

## Auto-injected recovery attributes

A recovery target usually wants context: what failed, where, with what status. The Router offers five values, injected **schema-gated**: each is passed only if the target *declares an attribute of that name*. Declaring the attribute is the opt-in; anything not declared is never injected, so nothing leaks into renders (or URLs) uninvited.

| Attribute | Value |
| --- | --- |
| `:exception` | The exception object itself. |
| `:request_path` | The path of the failing request. |
| `:status_code` | The resolved HTTP status (the exception's, or 500). |
| `:component_id` | The failing component's DOM id. |
| `:retry_url` | A GET URL that re-renders the failing component with its current attrs. |

So a custom error component opts in by declaration:

```ruby
class MyApp::ErrorComponent < Weft::Component
  abstract!

  attribute :exception
  attribute :retry_url

  def build(attributes = {})
    super
    add_class "weft-error"
    div { text_node "Something went wrong." }
    div @attrs.exception.message if Weft.configuration.verbose_error_pages
    button "Retry", retry: @attrs.retry_url if @attrs.retry_url
  end
end
```

Notes on the individual values:

- **These five names are reserved** on any class used as a recovery target. Declaring an attribute with one of these names *means* "inject the recovery value here" — so don't reuse them for your own data on error components, or on any component/page reachable through a `recovers` edge.
- **`:component_id`** preserves DOM identity: render your error wrapper with it as the element id (the gem's defaults do) and the error lands under the failing component's original id — so multiple simultaneous failures each swap into their own slot rather than colliding.
- **`:retry_url`** feeds the [`retry:` shorthand](dsl.md#shorthands): one button attribute, and the user can re-request the failed component in place. For a failed *action*, the URL renders the underlying component's view — a fresh look, not a replay of the failed action.
- When a recovery resolves to a **redirect** (page target from component context), only `:request_path` and `:status_code` travel — the others have no meaning in a URL.
- Keep the `weft-error` CSS class on custom error components: it's the DOM marker the `retry:` shorthand targets, and a useful styling hook besides.

## Presentation settings

Two configuration settings shape how the built-in fallbacks present; both are covered in detail in [Configuration](configuration.md#error-handling):

- [`verbose_error_pages`](configuration.md#verbose_error_pages) — whether the gem defaults show exception class/message and the failing path (turn off in production).
- [`htmx_errors`](configuration.md#htmx_errors) — whether htmx-request errors falling through to the gem defaults render in place (`:fragment`) or navigate to the error page (`:redirect`). Your own `recovers` edges are never affected, and 404s always render in place.

> **v0.1 limitation:** custom `recovers from: Weft::NotFound` declarations are not yet reliably honored — the gem-default not-found rendering can take over the response. To customize not-found presentation in v0.1, assign the [`not_found_page` / `not_found_component` knobs](configuration.md#the-four-fallback-targets), which are fully supported. First-class custom `NotFound` recoveries land in v0.2.
