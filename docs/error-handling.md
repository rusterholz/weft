# Error handling

In a component-oriented UI, an error is part of the interface. When one component's render or action raises, the right outcome is usually a visible error state *in that component's place* — not a dead button, not a blank region, and certainly not a whole-page crash. Weft's error handling is built around that idea: exceptions map to renderable fallbacks through a declarative chain, with sensible defaults at every level, so an unhandled error always lands somewhere visible.

Two layers cooperate to make this work. On the server, the Router catches errors and renders a recovery target instead. On the client, `Weft::Page` configures htmx to swap error responses into the page (by default htmx discards them) — which is why a failing component shows its error box right where the component was.

**In this document:**

- [The error classes](#the-error-classes)
- [The `recovers` chain](#the-recovers-chain) — matching, targets, blocks, and [the built-in edges](#the-built-in-edges)
- [What happens when something raises](#what-happens-when-something-raises) — including [where failure-prone work belongs](#where-the-work-that-can-fail-belongs) and [when a companion fails](#when-a-companion-fails)
- [Error handling on live streams](#error-handling-on-live-streams)
- [Auto-injected recovery params](#auto-injected-recovery-params)
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

Raise these from your `build` methods and action callables to communicate outcomes with the right status semantics: `raise Weft::NotFound` when a record lookup comes up empty, `raise Weft::Unprocessable` when validation fails. They're a convenience, not a requirement — your code can keep raising its own vocabulary (`ActiveRecord::RecordNotFound`, a domain error) and let a `recovers` edge [declare what it means](#the-recovers-chain) with `status:`. An error that's neither a `Weft::HTTPError` nor mapped by such an edge is treated as status 500.

A separate branch of the family reports *your* mistakes to you, raised at definition or configuration time rather than during request handling: `Weft::InvalidConfiguration` (a bad value inside `Weft.configure`), `Weft::InvalidDefinition` (a bad class-body declaration, including route collisions), and `Weft::InvalidUsage` (a bad call at render time). These are meant to fail loudly during development, not to be recovery targets.

## The `recovers` chain

Components and pages declare how they handle errors with `recovers`:

```ruby
class OrderEditor < Weft::Component
  recovers from: Weft::Unprocessable do |params, error|
    { error_message: error.message }
  end
  recovers from: Weft::Unauthorized, with: LoginPage
  recovers from: ActiveRecord::RecordNotFound, with: NotFoundCard, status: 404
end
```

Each declaration is an edge: *when this kind of error escapes me, render that instead.* The pieces:

**`from:`** decides whether an edge matches a given exception. It accepts:


- a **Class** — matches that exception class and its subclasses (`from: Weft::HTTPError` catches the whole status-bearing family);
- an **Integer** — matches by HTTP status (`from: 404`);
- a **Range** — matches statuses in the range (`from: 500..599`);
- an **Array** of any of the above — matches if any element does.

**`with:`** names the recovery target — what renders in place of the failure. It accepts a component or page class, or a symbol naming a [configuration knob](configuration.md#the-four-fallback-targets) (`with: :error_component`), resolved at error-handling time so reconfiguration propagates. Omitted, it defaults to the declaring class itself — "on this error, re-render me" — which pairs naturally with a block that adjusts params.

**`status:`** declares what a matched error *means* on the wire. Weft's own error classes carry their status with them, but your app's errors don't need translating into Weft's — recover from them directly and let the edge supply the semantics, as the `ActiveRecord::RecordNotFound` edge above does: the response status and the auto-injected `:status_code` param both follow it, so the branded rendering is a genuine 404. Without it, a recovered non-`Weft::HTTPError` reports as 500. Only error statuses (400–599) are assignable; an invalid value raises `Weft::InvalidUsage` at declaration time.

**The block**, if given, receives `(params, error)` — plus the exception — and returns a hash merged into the params the recovery target renders with (returned keys win). It's for *carrying information onto the error rendering*, like the validation messages above; it never returns HTML.

The `params` it gets are **the state the request had reached when it broke**, with every door open: wire values, derivations, defines. If the failure was in an action callable, that's what the callable was reading; if the callable succeeded and the *render* failed, it's that plus whatever the callable returned; and a companion's recovery block sees what its own `build` saw, its companion block's delta included. A derivation the failed code had already forced is still forced, so reading it in the recovery block costs nothing — and one it hadn't will run now, which is worth remembering if it's the kind of lookup that can fail twice.

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

**In component context** — a fragment render or an action — the Router walks the failing component's chain and renders the matched target as a fragment, with the response status taken from the exception (`Weft::HTTPError#status`, else 500). On the client, the fragment swaps in where the component's response would have gone, so the error appears exactly where the problem is. If the matched target is a *page* class, the recovery becomes a redirect to that page instead (`HX-Redirect` for htmx requests, 302 otherwise) — the `with: LoginPage` pattern above.

One wrinkle worth knowing: for actions with a destructive swap (`dismisses`, or any `performs` with `swap: :delete`), a successful response removes the element — which would make an error invisible. Weft overrides the swap on error responses (via `HX-Reswap`) so the error rendering replaces the component instead of vanishing with it. The replacement also arrives correctly shaped: recovery fragments adopt the failing component's wrapper tag (via `:component_tag`, below), so a failed delete on a table row produces an error *row* the table can legally contain.

**In page context** — a full-document render, or a request no route matched — the Router walks the page's chain (for routing misses, the base `Weft::Page` chain, which lands on the not-found page). A traditional request gets the recovery page as a complete document; an htmx request gets just the page's body content, since the document shell is already on the client.

**If the recovery itself raises** — a bug in your error component, say — Weft stops walking and emits a minimal hardcoded error rendering, logging the recovery failure and surfacing the *original* error. There is always a floor; error handling never recurses into itself.

Whatever renders, it wears the **failing component's DOM id**. A recovery fragment stands in the failed component's place, and an out-of-band swap addressed anywhere else would land on the wrong element — or on none. You don't opt into this and can't forget it; Weft stamps the id on every recovery fragment it produces.

### Where the work that can fail belongs

Two Weft surfaces can raise, and they are not equivalent. An action callable — `performs`, `transfers`, `dismisses` — is where your app *does* something: writes, external calls, state changes. A `build` method is where it *describes* something.

**Put the fallible work in the callable and keep `build` free of side effects.** The reason will be familiar from any MVC framework: by the time rendering begins, whatever the action committed is already committed. A failure inside the callable can still be reported as a failure of the whole operation; a failure during rendering can only be reported after the fact — which is why Rails rolls back a controller error but not a view error.

Weft leans into that split rather than papering over it. An action that raises produces an error *response*; a fragment that raises produces an error *fragment*, and everything around it stands. The more your `build` methods are pure descriptions of state, the more that second case is a display problem rather than a correctness one.

### When a companion fails

A component can bring [companions](dsl.md#brings--companions-in-the-same-response) along with a response — other fragments that went stale and ride back on the same request. **A companion is a courtesy, not a contract:** if one raises, the response still belongs to the component the request was about.

So the primary render, the status, and the `HX-*` headers are all untouched. The failing companion walks *its own* `recovers` chain, and the result is delivered as a companion in that companion's own DOM slot — the error appears exactly where that fragment would have been and nowhere else, while the rest of the response arrives as though nothing happened. This is what makes an action with side effects honest: a companion that breaks *after* your callable has written to the database can no longer turn a committed change into a reported failure.

Two wrinkles worth knowing:

- **Recovery edges that point at a page class are skipped here**, and the walk continues to the next match. A fragment riding inside a successful response has no business navigating away from it.
- **If the chain yields nothing, or the recovery render itself raises**, that companion is dropped and the failure is logged with the class and the `brings` declaration site that brought it along. The rest of the response is unaffected either way.

Companion failures on a [live stream](#error-handling-on-live-streams) behave the same, with one addition: they don't count against the stream's attempts budget. The budget measures the *stream's* health, and a companion's trouble says nothing about it.

## Error handling on live streams

A failing SSE push walks the same `recovers` chain as any other component-context failure, with three stream-shaped differences:

- **Component targets only.** A stream can't redirect, so an entry whose target is a page class is skipped and the walk continues to the next match. The gem-default `StandardError` edge sits at the bottom of every chain, so a failing push always finds an error component to render (unless you've deliberately reconfigured that default away).
- **Frames mirror normal pushes.** The recovery component's *content* is pushed under the failing component's event name and swaps into the persistent wrapper's interior, exactly like a healthy frame. The recovery component's own wrapper never ships — so on this path, put the error box and its styling on inner elements (the gem defaults do).
- **Failure is budgeted.** Consecutive failed pushes count against an attempts budget — the [`push_attempts`](configuration.md#push_attempts) setting (default 3), or per component with `pushes every: ..., attempts: ...`. A successful push resets the count. When the budget runs out, Weft pushes the final recovery frame, then a close event that the wrapper's `sse-close` attribute tells htmx to honor: the browser closes the EventSource and does not reconnect. The stream ends server-side too; the rest of the page is untouched.

The countdown is visible to your error components through the `:attempts_remaining` auto-injected param (below): it reaches 0 on the final frame — the moment to offer a resume affordance. The [`reopen_stream:` preset](dsl.md#presets) makes that a one-liner: `button "Resume live updates", reopen_stream: @params.retry_url` re-fetches the component whole, and the fresh render carries a fresh `sse-connect`, so the stream reopens with a full budget.

If the recovery render itself raises, that frame is skipped (and the failure still counts) — streams share the no-recursion floor with every other error path.

## Auto-injected recovery params

A recovery target usually wants context: what failed, where, with what status. The Router offers six values, delivered as **request overlays**: a component reads each by *declaring a param of that name*. The declaration is the opt-in — anything not declared is never read — and because overlays reach the whole recovery render, a component *nested inside* your branded error page can declare and read them too (a shared error-detail partial reading `:exception` itself, say). Recovery redirect URLs stay schema-gated and carry only the redirect-safe values the destination declares, so nothing rides a URL uninvited.

| Param | Value |
| --- | --- |
| `:exception` | The exception object itself. |
| `:request_path` | The path of the failing request. |
| `:status_code` | The resolved HTTP status (the exception's, or 500). |
| `:component_tag` | The failing component's wrapper tag name. |
| `:retry_url` | A GET URL that re-renders the failing component with its current params. |
| `:attempts_remaining` | On a live stream: failed pushes left before the stream closes. Absent elsewhere. |

So a custom error component opts in by declaration:

```ruby
class MyApp::ErrorComponent < Weft::Component
  abstract!

  param :exception
  param :retry_url

  def build(attributes = {})
    super
    add_class "weft-error"
    div { text_node "Something went wrong." }
    div @params.exception.message if Weft.configuration.verbose_error_pages
    button "Retry", retry: @params.retry_url if @params.retry_url
  end
end
```

Notes on the individual values:

- **These six names are reserved** on any class used as a recovery target. Declaring a param with one of these names *means* "inject the recovery value here" — so don't reuse them for your own data on error components, or on any component/page reachable through a `recovers` edge.
- **DOM identity is not among them**, because it isn't optional. Weft stamps the failing component's id onto every recovery fragment, so simultaneous failures each swap into their own slot rather than colliding, and a recovery target that has never heard of any of this still lands correctly.
- **`:component_tag`** keeps swaps *valid*: return it from your error component's `tag_name` (the gem's defaults do) and a failure inside a `<tr>` or `<li>` component produces a fragment its surroundings can legally contain, instead of a `<div>` forced somewhere divs can't go. Weft reads the tag without re-running the failed construction; when a component computes its tag from instance state, the value falls back to absent and the target renders with its own default tag.
- **`:retry_url`** feeds the [`retry:` preset](dsl.md#presets): one button attribute, and the user can re-request the failed component in place. For a failed *action*, the URL renders the underlying component's view — a fresh look, not a replay of the failed action. On a stream's final frame it feeds [`reopen_stream:`](dsl.md#presets) the same way.
- **`:attempts_remaining`** is also the push-path context signal: non-nil only when rendering a recovery frame for a live stream. Its presence lets one error component serve both paths — the gem default renders its request shape when it's nil and its stream shape otherwise.
- When a recovery resolves to a **redirect** (page target from component context), only `:request_path` and `:status_code` travel — the others have no meaning in a URL.
- Keep the `weft-error` CSS class on custom error components: it's the DOM marker the `retry:` preset targets, and a useful styling hook besides.

## Presentation settings

Two configuration settings shape how the built-in fallbacks present; both are covered in detail in [Configuration](configuration.md#error-handling):

- [`verbose_error_pages`](configuration.md#verbose_error_pages) — whether the gem defaults show exception class/message and the failing path (turn off in production).
- [`htmx_errors`](configuration.md#htmx_errors) — whether htmx-request errors falling through to the gem defaults render in place (`:fragment`) or navigate to the error page (`:redirect`). Your own `recovers` edges are never affected, and 404s always render in place.
