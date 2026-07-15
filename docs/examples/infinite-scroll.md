# Infinite Scroll

A table that grows as you read it: when the last visible row scrolls into view, the next page of rows is fetched and appended after it — no button, no page numbers, no end-of-page cliff until the data genuinely runs out.

This is Weft's take on [htmx's infinite-scroll example](https://htmx.org/examples/infinite-scroll/), and the mechanism is the same: the final row of each batch carries a `revealed` trigger, and each response ends with the next trigger row. Where htmx's server returns a loose fragment of `<tr>`s, a Weft component renders one wrapper element — so here each batch is a `<tbody>`, appended as a sibling of the last. HTML happily allows a table multiple `<tbody>` elements, which makes it the natural chunk unit for growing tables.

## The components

```ruby
DIRECTORY = (1..42).map { |n| { name: "Contact #{n}", email: "contact#{n}@example.org" } }.freeze

class ContactRows < Weft::Component
  builder_method :contact_rows

  PER_PAGE = 10

  param :page, default: 1

  def tag_name
    "tbody"
  end

  def build(attributes = {})
    super
    rows = DIRECTORY[(params.page - 1) * PER_PAGE, PER_PAGE]
    rows.each_with_index do |contact, index|
      if index == rows.size - 1 && more_pages?
        tr(infinite_scroll: ContactRows, with: { page: params.page + 1 }, target: "closest tbody") do
          td contact[:name]; td contact[:email]
        end
      else
        tr { td contact[:name]; td contact[:email] }
      end
    end
  end

  private

  def more_pages?
    params.page * PER_PAGE < DIRECTORY.size
  end
end

class ContactDirectory < Weft::Component
  builder_method :contact_directory

  def build(attributes = {})
    super
    h3 "Contact directory"
    table do
      thead { tr { th "Name"; th "Email" } }
      contact_rows(page: 1)
    end
  end
end
```

(The `DIRECTORY` array stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**The last row is the sentinel.** [`infinite_scroll:`](../dsl.md#shorthands) presets trigger `:visible` and swap `:after`; the call site adds the target. Placed on the final `tr` of a batch, it means: when this row scrolls into view, fetch the next batch and insert it after the closest `tbody`. The trigger expands to htmx's `revealed`, which fires once per element — each sentinel row does its job exactly one time.

**`target: "closest tbody"` keeps the table valid.** The fetched component is a whole `<tbody>` (that's the `tag_name` override), and swapping it `afterend` of the *row* would nest table sections illegally. Aiming the swap at the closest `tbody` instead makes each batch a sibling section — the shape HTML already sanctions for row grouping. This is why the preset leaves the target to you: only the call site knows what the insertion point should be.

**The chain stops itself.** The sentinel wiring is only rendered while `more_pages?` holds. The final batch is just rows — nothing left to trigger, nothing fetched past the end of the data.

**`page` travels as wire state.** `param :page, default: 1` makes each batch independently addressable (`/_components/contact_rows?page=3`) and coerces the URL string to an Integer, since the default is one. The `ContactDirectory` wrapper, by contrast, declares nothing — it's plain composition and renders only as part of a page.

## On the wire

The initial render (or `GET /_components/contact_rows?page=1`) — nine plain rows, then the sentinel:

```html
<tbody id="contact-rows-1">
  <tr><td>Contact 1</td><td>contact1@example.org</td></tr>
  <!-- … -->
  <tr hx-get="/_components/contact_rows?page=2" hx-swap="afterend"
      hx-target="closest tbody" hx-trigger="revealed">
    <td>Contact 10</td><td>contact10@example.org</td>
  </tr>
</tbody>
```

Scrolling that row into view issues `GET /_components/contact_rows?page=2`, whose response is the next `<tbody>` — appended after the first, ending in its own sentinel pointing at `page=3`. The last batch (`GET /_components/contact_rows?page=5`) contains only plain rows:

```html
<tbody id="contact-rows-5">
  <tr><td>Contact 41</td><td>contact41@example.org</td></tr>
  <tr><td>Contact 42</td><td>contact42@example.org</td></tr>
</tbody>
```

## Related

- [Click to Load](click-to-load.md) — the same batch-by-batch growth, but on the reader's explicit request.
- [Lazy Loading](lazy-loading.md) — the `:visible` trigger deferring a single section instead of paginating many.
- The [shorthands table](../dsl.md#shorthands) and [targets](../dsl.md#targets) in the DSL reference.
