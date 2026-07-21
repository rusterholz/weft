# Delete Row

A table of contacts, each row with a Delete button. Clicking it asks the browser's native "Are you sure?", deletes the record on the server, and removes the row from the table.

This is Weft's take on [htmx's delete-row example](https://htmx.org/examples/delete-row/). Their version hoists the htmx attributes onto the `<tbody>` and lets every row inherit them; a Weft row is a component that carries its own wiring, generated from its own declaration. One cosmetic difference: htmx's original fades the row out over a second before removing it — that's a CSS transition plus a swap delay, and their approach carries over unchanged if you want it. This version keeps zero CSS and removes the row immediately.

## The components

```ruby
CONTACT_BOOK = {
  "1" => { name: "Angie MacDowell", email: "angie@macdowell.org", status: "Active" },
  "2" => { name: "Fuqua Tarkenton", email: "fuqua@tarkenton.org", status: "Active" },
  "3" => { name: "Kim Yee",         email: "kim@yee.org",         status: "Inactive" }
}

class ContactRow < Weft::Component
  builder_method :contact_row

  param :contact_id
  receives :contact_id

  dismisses :destroy do |params|
    CONTACT_BOOK.delete(params.contact_id)
    nil
  end

  def tag_name
    "tr"
  end

  def build(attributes = {})
    super
    contact = CONTACT_BOOK[params.contact_id]
    return unless contact

    td contact[:name]
    td contact[:email]
    td contact[:status]
    td do
      button "Delete", action: :destroy, "hx-confirm" => "Are you sure?"
    end
  end
end

class ContactsTable < Weft::Component
  builder_method :contacts_table

  def build(attributes = {})
    super
    table do
      thead { tr { th "Name"; th "Email"; th "Status"; th "" } }
      tbody do
        CONTACT_BOOK.each_key { |id| contact_row(contact_id: id) }
      end
    end
  end
end
```

(The `CONTACT_BOOK` hash stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**The row is the component.** Overriding `tag_name` makes the wrapper a `<tr>`, so each contact renders as a real table row with its own DOM id. The identifying param is declared first because that's where the id comes from — `contact_id` of `"1"` yields `id="contact-row-1"`, which is exactly what the delete needs to target.

**Each row is handed its id, and declares it as a param too.** The table gives every row a *different* `contact_id` (`contact_row(contact_id: id)`), which is a [`receives`](../dsl.md#receives--caller-hand-offs) hand-off — sibling rows each need a distinct value, and the shared params bag that flows down the render tree can't supply per-row differences. Declaring [`param :contact_id`](../dsl.md#how-the-doors-combine) alongside it means the same id also serializes into the row's own route and the Delete button's payload, so `GET /_components/contact_row?contact_id=1` reconstructs the row on its own and the delete targets the right record.

**`dismisses` is the delete-shaped verb.** It's sugar for a `performs` with `method: :delete, swap: :delete` (see [`dismisses`](../dsl.md#dismisses--remove-from-the-dom)): the button wired with `action: :destroy` issues a `DELETE` to the action's route, the callable removes the record, and on success htmx deletes the target element — the row — from the DOM. The row's identity travels automatically: an action button carries the component's params as `hx-vals`. Note there's no non-JavaScript fallback here — plain HTML has no DELETE — which is the nature of the pattern rather than a Weft limitation.

**The confirmation is one raw attribute.** Kwargs Weft doesn't recognize pass straight through to the element, so `"hx-confirm" => "Are you sure?"` lands on the button as-is and htmx shows the browser's native confirm dialog before sending anything. No request fires on Cancel. For the fuller confirm-and-prompt story, see [Browser Dialogs](browser-dialogs.md).

**The dismissal response is rendered, then thrown away.** htmx ignores the response body on a delete swap, but Weft still renders the component once after the callable runs — so `build` must survive the record being gone, hence the `return unless contact` guard (an empty `<tr>` nobody will see). The trailing `nil` in the callable matters for the same reason: `Hash#delete` returns the deleted record, and a hash returned from a callable merges into the params for that final render. If the callable *raises*, Weft overrides the destructive swap (via `HX-Reswap`) so the error rendering appears where the row was, instead of the row silently vanishing.

## On the wire

Each row arrives fully wired — `GET /_components/contact_row?contact_id=1` returns the same fragment the table renders inline:

```html
<tr id="contact-row-1">
  <td>Angie MacDowell</td>
  <td>angie@macdowell.org</td>
  <td>Active</td>
  <td>
    <button hx-confirm="Are you sure?" hx-delete="/_components/contact_row/destroy"
            hx-target="#contact-row-1" hx-swap="delete"
            hx-vals="{&quot;contact_id&quot;:&quot;1&quot;}">Delete</button>
  </td>
</tr>
```

Confirming the dialog sends `DELETE /_components/contact_row/destroy?contact_id=1` (htmx 2 puts DELETE parameters in the query string). The server deletes the record and responds `200` with the guarded, now-empty render — which htmx discards while removing the row:

```html
<tr id="contact-row-1"></tr>
```

Fetching the table again shows two rows; fetching the deleted row's own URL returns the same empty `<tr>`, confirming the record is gone.

## Related

- [Browser Dialogs](browser-dialogs.md) — the confirm/prompt story in full.
- [Edit Row](edit-row.md) — rows that switch into an editable state instead of disappearing.
- [Inline Expansion](inline-expansion.md) — another `tag_name "tr"` component, inserted rather than removed.
- [`dismisses`](../dsl.md#dismisses--remove-from-the-dom) in the DSL reference.
