# Click to Edit

A read-only view of a record with an Edit button. Clicking swaps an editable form into its place; saving — or canceling — swaps the read-only view back. No page navigation, and no JavaScript beyond what Weft already ships.

This is Weft's take on [htmx's click-to-edit example](https://htmx.org/examples/click-to-edit/), and the shape is the same: the UI moves between two states, and each state is a server-rendered fragment. In Weft, each state is simply a component.

## The components

```ruby
CONTACTS = {
  "1" => { first_name: "Joe", last_name: "Blow", email: "joe@blow.com" }
}.freeze

class ContactCard < Weft::Component
  builder_method :contact_card

  attribute :contact_id

  def build(attributes = {})
    super
    contact = CONTACTS.fetch(attrs.contact_id)
    div { strong "First Name: "; text_node contact[:first_name] }
    div { strong "Last Name: ";  text_node contact[:last_name] }
    div { strong "Email: ";      text_node contact[:email] }
    button "Click To Edit",
           loads: ContactEditor, with: { contact_id: attrs.contact_id },
           swap: :replace, target: self
  end
end

class ContactEditor < Weft::Component
  builder_method :contact_editor

  attribute :contact_id
  attribute :first_name
  attribute :last_name
  attribute :email

  transfers :save, to: ContactCard do |attrs|
    CONTACTS.fetch(attrs.contact_id).merge!(
      first_name: attrs.first_name, last_name: attrs.last_name, email: attrs.email
    )
    nil
  end

  def build(attributes = {})
    super
    contact = CONTACTS.fetch(attrs.contact_id)
    form(action: :save) do
      input(type: "hidden", name: "contact_id", value: attrs.contact_id)
      div do
        label("First Name ", for: "first_name")
        input(type: "text", name: "first_name", id: "first_name", value: contact[:first_name])
      end
      div do
        label("Last Name ", for: "last_name")
        input(type: "text", name: "last_name", id: "last_name", value: contact[:last_name])
      end
      div do
        label("Email ", for: "email")
        input(type: "text", name: "email", id: "email", value: contact[:email])
      end
      input(type: "submit", value: "Submit")
      button "Cancel", type: "button",
             loads: ContactCard, with: { contact_id: attrs.contact_id },
             swap: :replace, target: self
    end
  end
end
```

(The `CONTACTS` hash stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**Reads and writes get different verbs.** Opening the editor changes nothing on the server, so the Edit button is a [`loads:`](../dsl.md#loads) — a plain GET that fetches the editor component and swaps it over the card (`swap: :replace`). Cancel is the same thing pointed back at the card. Saving *does* change something, so it's a [`transfers`](../dsl.md#transfers--actions-that-render-something-else): a POST that runs the write, then renders the card — the natural "what you see after saving" — in the editor's place.

**`target: self` pins the swap to the component.** Inside `build`, `self` is the component instance, and a component reference as a `target:` resolves to its DOM id. Each fragment replaces the whole card/editor element, wherever it sits in the page.

**The two components reference each other — without a cycle.** `transfers :save, to: ContactCard` runs in the class body, so `ContactCard` must already be defined; but `loads: ContactEditor` isn't evaluated until render. Defining the display component first therefore breaks the loop with no forward-declaration tricks. This ordering trick generalizes to any two-state component pair.

**Form fields pair with declared attributes.** The editor declares `first_name`, `last_name`, and `email` so its fields reach the save callable as `attrs.first_name` and friends — and `contact_id` rides along as a hidden input, because it's part of the component's identity rather than something the user edits. (This pairing is covered in depth in [the tutorial](../tutorial.md#7-taking-rsvps).)

**It still works without JavaScript.** `form(action: :save)` emits plain `action`/`method` attributes alongside the htmx wiring, so the save degrades to a normal POST. Note `type: "button"` on Cancel — inside a form, a bare `<button>` is a submit button.

## On the wire

The initial render (or `GET /_components/contact_card?contact_id=1`):

```html
<div id="contact-card-1">
  <div><strong>First Name: </strong>Joe</div>
  <div><strong>Last Name: </strong>Blow</div>
  <div><strong>Email: </strong>joe@blow.com</div>
  <button hx-get="/_components/contact_editor?contact_id=1"
          hx-swap="outerHTML" hx-target="#contact-card-1">Click To Edit</button>
</div>
```

Clicking Edit fetches the editor; its form is wired to the save action, with the non-JS fallback visible:

```html
<form hx-post="/_components/contact_editor/save" hx-target="#contact-editor-1"
      hx-swap="outerHTML" action="/_components/contact_editor/save" method="post">
```

Submitting `POST /_components/contact_editor/save` with the edited fields returns the updated card — `<div id="contact-card-1">…Joseph…</div>` — which replaces the editor. The next fetch of the card confirms the write stuck.

## Related

- [Edit Row](edit-row.md) — this same pattern applied per-row in a table.
- [`loads:`](../dsl.md#loads) and [`transfers`](../dsl.md#transfers--actions-that-render-something-else) in the DSL reference.
- htmx's original uses a RESTful `PUT`; if you prefer that, `transfers :save, to: ContactCard, method: :put` does exactly what you'd hope.
