# Lazy Loading

A placeholder that fills itself with real content the moment it scrolls into view. Expensive sections — big queries, slow aggregations — stay out of the initial render, and the page arrives fast.

This is Weft's take on [htmx's lazy-load example](https://htmx.org/examples/lazy-load/), where a graph is fetched only when revealed. The shape is identical: a lightweight placeholder carries the wiring, and the server renders the heavy part on demand. In Weft, the heavy part is simply a component.

## The components

```ruby
QUARTERLY_REVENUE = {
  2025 => { "Q1" => "$418,200", "Q2" => "$473,900", "Q3" => "$391,400", "Q4" => "$512,750" }
}.freeze

class RevenueTable < Weft::Component
  builder_method :revenue_table

  attribute :year, default: 2025

  def build(attributes = {})
    super
    table do
      thead { tr { th "Quarter"; th "Revenue" } }
      tbody do
        QUARTERLY_REVENUE.fetch(attrs.year).each do |quarter, amount|
          tr { td quarter; td amount }
        end
      end
    end
  end
end

class AnnualReport < Weft::Component
  builder_method :annual_report

  attribute :year, default: 2025

  def build(attributes = {})
    super
    h2 "#{attrs.year} annual report"
    para "Commentary, highlights, and everything else the reader scrolls through " \
         "before the numbers. The revenue table below is expensive to produce, " \
         "so it loads only when it comes into view."
    div lazy: RevenueTable, with: { year: attrs.year } do
      para "Loading revenue…"
    end
  end
end
```

(The `QUARTERLY_REVENUE` hash stands in for your data layer — in real life this is the query you'd rather not run on every page view.)

## How it works

**The placeholder is an ordinary element with one extra kwarg.** [`lazy:`](../dsl.md#shorthands) is a preset over the [`loads:`](../dsl.md#loads) machinery: trigger `:visible`, swap `:fill`, target `:self`. When the div scrolls into view, fetch `RevenueTable` and swap it into the div's interior. Because trigger, swap, *and* target all have an obvious right answer here, the call site needs nothing beyond the component class and its attrs.

**The div's children are the loading state.** Because the swap is `:fill` (`innerHTML`), the placeholder element itself survives; only its contents — the "Loading revenue…" paragraph — are replaced by the fetched component. Whatever you put in the block is what users see until the content arrives.

**`:visible` means once.** The semantic trigger expands to htmx's `revealed`, which fires a single time when the element first enters the viewport. The wrapper keeps its wiring after the swap, but no re-fetch loop follows.

**`with:` passes the wire state along.** The placeholder hands its own `year` down to the loaded component (`with: { year: attrs.year }`), and the value travels in the URL — visible below. If you omit `with:`, the enclosing component's attrs are passed by default.

## On the wire

The initial render (or `GET /_components/annual_report?year=2025`) contains the placeholder, wired and waiting:

```html
<div id="annual-report-2025">
  <h2>2025 annual report</h2>
  <p>Commentary, highlights, and everything else the reader scrolls through …</p>
  <div hx-get="/_components/revenue_table?year=2025" hx-swap="innerHTML"
       hx-target="this" hx-trigger="revealed">
    <p>Loading revenue…</p>
  </div>
</div>
```

Scrolling it into view issues `GET /_components/revenue_table?year=2025`, and the response fills the placeholder:

```html
<div id="revenue-table-2025">
  <table>
    <thead><tr><th>Quarter</th><th>Revenue</th></tr></thead>
    <tbody>
      <tr><td>Q1</td><td>$418,200</td></tr>
      <tr><td>Q2</td><td>$473,900</td></tr>
      <!-- … -->
    </tbody>
  </table>
</div>
```

## Related

- [Infinite Scroll](infinite-scroll.md) — the same `:visible` trigger, used repeatedly to grow a table page by page.
- [Click to Load](click-to-load.md) — deferred loading where the user asks for more, instead of scrolling to it.
- The [shorthands table](../dsl.md#shorthands) and the [trigger values](../dsl.md#trigger-values) in the DSL reference.
