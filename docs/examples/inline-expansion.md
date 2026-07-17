# Inline Expansion

A compact row with a disclosure control. Clicking it fetches the row's detail from the server and inserts it directly beneath — the list stays a list, and depth appears exactly where the reader asked for it.

There's no counterpart for this in the htmx examples catalog; `inline_expand:` is Weft-native sugar over the same [`loads:`](../dsl.md#loads) machinery as the other presets. It's the pattern for master-detail tables where the detail is cheap to want and expensive to preload for every row.

## The components

```ruby
ORDERS = {
  "1001" => { customer: "Ada Lovelace",       total: "$120.00", items: ["Brass gears (x12)", "Punch cards (x100)"] },
  "1002" => { customer: "Grace Hopper",       total: "$45.50",  items: ["Nanosecond wire (x3)"] },
  "1003" => { customer: "Katherine Johnson",  total: "$310.25", items: ["Slide rule", "Graph paper (x20)"] }
}.freeze

class OrderItemsRow < Weft::Component
  builder_method :order_items_row

  param :order_id

  def tag_name
    "tr"
  end

  def build(attributes = {})
    super
    order = ORDERS.fetch(params.order_id)
    td colspan: 4 do
      strong "Items: "
      text_node order[:items].join(", ")
    end
  end
end

class OrdersTable < Weft::Component
  builder_method :orders_table

  def build(attributes = {})
    super
    table do
      thead { tr { th ""; th "Order"; th "Customer"; th "Total" } }
      tbody do
        ORDERS.each do |id, order|
          tr do
            td do
              button "▸", inline_expand: OrderItemsRow, with: { order_id: id },
                          target: "closest tr", trigger: "click once"
            end
            td id
            td order[:customer]
            td order[:total]
          end
        end
      end
    end
  end
end
```

(The `ORDERS` hash stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**The detail arrives *after* the trigger's row.** [`inline_expand:`](../dsl.md#presets) presets trigger `:click` and swap `:after` (htmx's `afterend`); the call site supplies the target. `target: "closest tr"` walks up from the button to its row, so the fetched component is inserted as the next sibling row — which is why `OrderItemsRow` overrides `tag_name` to render as a `<tr>`. A `colspan` spanning the table's columns lets the detail breathe across the full width.

**`trigger: "click once"` guards against double insertion.** The preset's `:click` fires on *every* click — left alone, a second click would insert a second copy of the detail row. The `trigger:` kwarg overrides the preset with htmx's raw trigger grammar, and `once` caps the interaction at a single firing. (There's currently no semantic symbol for "click once" the way `:hover` bakes in `mouseenter once`, so the raw string is the honest spelling.)

**Expansion, not a toggle.** Once expanded, the row stays expanded — this preset opens, it doesn't close. When you need collapse, give the detail component the behavior: a [`dismisses`](../dsl.md#dismisses--remove-from-the-dom) verb and a "Hide" button inside `OrderItemsRow` remove it from the DOM server-consistently. (The one-shot button does remain spent after that; a fully re-armable open/close control is a two-state component pair, as in [Click to Edit](click-to-edit.md).)

## On the wire

The initial render — each order row carries its wired disclosure button:

```html
<tr>
  <td>
    <button hx-get="/_components/order_items_row?order_id=1001" hx-swap="afterend"
            hx-target="closest tr" hx-trigger="click once">▸</button>
  </td>
  <td>1001</td>
  <td>Ada Lovelace</td>
  <td>$120.00</td>
</tr>
```

Clicking issues `GET /_components/order_items_row?order_id=1001`, and the response slots in beneath the row:

```html
<tr id="order-items-row-1001">
  <td colspan="4"><strong>Items: </strong>Brass gears (x12), Punch cards (x100)</td>
</tr>
```

## Related

- [Tooltip](tooltip.md) — the other Weft-native preset: hover-driven detail loaded into a bubble instead of a row.
- [Click to Edit](click-to-edit.md) — two-state rows that swap in place rather than expanding.
- The [presets table](../dsl.md#presets) and [trigger values](../dsl.md#trigger-values) in the DSL reference.
