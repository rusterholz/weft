# Active Search

A search box that filters a result list as the user types. Each (debounced) keystroke asks the server for matches, and the results region is refilled with the answer — search-as-you-type with all the logic living server-side.

This is Weft's take on [htmx's active-search example](https://htmx.org/examples/active-search/), searching the same kind of small contact directory by name or email. One preset detail differs and is worth stating precisely: Weft's `live_search:` preset fires on `input changed delay:300ms` — the `input` event, debounced by 300 milliseconds — where htmx's published example uses `keyup changed delay:500ms`. If you want htmx's exact timing (or any other), the `trigger:` kwarg overrides the preset, as shown below.

## The components

```ruby
PEOPLE = [
  { name: "Venus Grimes",    email: "vgrimes@example.org" },
  { name: "Kandy Kane",      email: "kandy@example.org" },
  { name: "Antonia Benitez", email: "abenitez@example.org" },
  { name: "Dewayne Sharp",   email: "dsharp@example.org" },
  { name: "Nathan Grimes",   email: "ngrimes@example.org" },
  { name: "Mia Chandler",    email: "mchandler@example.org" },
  { name: "Leland Ortega",   email: "lortega@example.org" },
  { name: "Saanvi Rao",      email: "srao@example.org" }
].freeze

class ContactResults < Weft::Component
  builder_method :contact_results

  param :q, default: ""

  def build(attributes = {})
    super
    matches = search(params.q)
    if matches.empty?
      para "No one matches “#{params.q}”."
    else
      table do
        thead { tr { th "Name"; th "Email" } }
        tbody do
          matches.each { |person| tr { td person[:name]; td person[:email] } }
        end
      end
    end
  end

  private

  def search(query)
    q = query.strip.downcase
    PEOPLE.select { |person| "#{person[:name]} #{person[:email]}".downcase.include?(q) }
  end
end

class ContactSearch < Weft::Component
  builder_method :contact_search

  def build(attributes = {})
    super
    h3 "Search the directory"
    input type: "search", name: "q", placeholder: "Begin typing to search...",
          live_search: ContactResults, target: "#search-results"
    div id: "search-results" do
      contact_results(q: "")
    end
  end
end
```

(The `PEOPLE` array stands in for your data layer — in a real app, `search` becomes a scoped query.)

## How it works

**The input's `name` is the search parameter.** [`live_search:`](../dsl.md#presets) presets trigger `:input` and swap `:fill`; the call site supplies the target. Notice that the generated URL below carries no query string — htmx includes the triggering input's own `name`/value with the request, which is how the typed text travels. The two halves must agree: the input says `name: "q"`, and `ContactResults` declares `param :q` to receive it. An empty default keeps the blank-box case (matching everyone) working.

**Debounced by the preset, adjustable at the call site.** The `:input` semantic trigger expands to `input changed delay:300ms`: fire on input events, only when the value actually changed, at most once per 300ms lull. To reproduce htmx's example exactly, override it in place — the preset's request, swap, and target are all kept:

```ruby
input type: "search", name: "q",
      live_search: ContactResults, target: "#search-results",
      trigger: "keyup changed delay:500ms"
```

**Results refill a stable container.** The `:fill` swap replaces the *contents* of `#search-results`, so the container div persists across searches while a fresh `ContactResults` lands inside it each time. Pre-rendering `contact_results(q: "")` in the container means the page starts with the full directory rather than an empty pane — the initial state and every subsequent state are the same component.

**The whole result set re-renders per search.** No row diffing, no client-side state: each request returns the complete table (or the "no matches" paragraph) for that query. At search-box scale this is the simple, correct trade.

## On the wire

The initial render — the wired input, and the container holding the unfiltered component:

```html
<input type="search" name="q" placeholder="Begin typing to search..."
       hx-get="/_components/contact_results" hx-swap="innerHTML"
       hx-target="#search-results" hx-trigger="input changed delay:300ms"/>
<div id="search-results">
  <div id="contact-results-">
    <table>…all eight people…</table>
  </div>
</div>
```

(That `id="contact-results-"` is the component's DOM id — dasherized class name plus first param value, which here is the empty string.)

Typing "grimes" settles into `GET /_components/contact_results?q=grimes`:

```html
<div id="contact-results-grimes">
  <table>
    <thead><tr><th>Name</th><th>Email</th></tr></thead>
    <tbody>
      <tr><td>Venus Grimes</td><td>vgrimes@example.org</td></tr>
      <tr><td>Nathan Grimes</td><td>ngrimes@example.org</td></tr>
    </tbody>
  </table>
</div>
```

And a query with no matches (`GET /_components/contact_results?q=zz`) returns the friendly empty state:

```html
<div id="contact-results-zz">
  <p>No one matches “zz”.</p>
</div>
```

## Related

- [Tabs](tabs.md) — the same fill-a-stable-container shape, driven by clicks instead of keystrokes.
- The [presets table](../dsl.md#presets) and [trigger values](../dsl.md#trigger-values) in the DSL reference.
- The [tutorial](../tutorial.md) covers the pairing of form field names with declared params in depth.
