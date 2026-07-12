# Updating Other Content

A form adds a contact, and a contacts table elsewhere on the page — outside the form, not enclosing it, not enclosed by it — updates in the same interaction. One submit, two regions refreshed.

This is Weft's take on [htmx's update-other-content example](https://htmx.org/examples/update-other-content/), which uses the same scenario: a table of contacts with an add-contact form below it. htmx's page is really an essay weighing four manual solutions — expanding the target, out-of-band swaps, event triggers, and a path-dependencies extension — each with its own wiring to write and trade-offs to hold in your head. Weft collapses the choice to declarations: `includes ContactsTable` on the form covers the common case in one line, and a `triggers`/`refreshes on:` pair covers the decoupled case in two. [The full four-way mapping is below.](#htmxs-four-solutions-mapped)

## The components

```ruby
ADDRESS_BOOK = [
  { name: "Joe Smith", email: "joe@smith.org" }
]

class ContactsTable < Weft::Component
  builder_method :contacts_table

  def build(attributes = {})
    super
    table do
      thead { tr { th "Name"; th "Email" } }
      tbody do
        ADDRESS_BOOK.each { |contact| tr { td contact[:name]; td contact[:email] } }
      end
    end
  end
end

class NewContactForm < Weft::Component
  builder_method :new_contact_form

  attribute :name
  attribute :email

  includes ContactsTable

  performs :add do |attrs|
    ADDRESS_BOOK << { name: attrs.name, email: attrs.email }
    { name: nil, email: nil }
  end

  def build(attributes = {})
    super
    h3 "Add a contact"
    form(action: :add) do
      label("Name ", for: "name")
      input(type: "text", name: "name", id: "name")
      label(" Email ", for: "email")
      input(type: "email", name: "email", id: "email")
      input(type: "submit", value: "Add Contact")
    end
  end
end
```

And the page that places them side by side:

```ruby
class ContactsPage < Weft::Page
  def build(attributes = {})
    attributes[:title] = "Contacts"
    super
    h1 "Contacts"
    contacts_table
    new_contact_form
  end
end
```

(`ADDRESS_BOOK` stands in for your data layer, as usual.)

## How it works

**`includes` declares the relationship once, in the class body.** [`includes ContactsTable`](../dsl.md#includes--companions-in-the-same-response) means: whenever this form responds to an action, render the table too, marked out-of-band. htmx receives one response containing two fragments — the re-rendered form swaps into the form's place as usual, and the table fragment, carrying `hx-swap-oob="true"`, is routed to its own DOM slot by id (`#contacts-table`). One request, one response, two regions updated. This is htmx's out-of-band solution with the response construction, the OOB attribute, and the id bookkeeping all handled for you.

**The included component needs no route.** In this variant `ContactsTable` declares no attributes and no verbs, so it isn't independently addressable — `GET /_components/contacts_table` answers 404 — and that's fine: it renders inside the page and travels inside the form's responses. Companions only need to *render* (see [routing](../routing.md#routable-vs-render-target)).

**The callable resets the form.** An action callable's return value directs the re-render ([the callable contract](../dsl.md#the-callable-contract)): returning a hash merges it into the attrs. Returning `{ name: nil, email: nil }` clears the just-submitted values, so the form comes back empty after each add — htmx's reset-the-form problem solved server-side, with no `hx-on` handler. (It also keeps the component's derived DOM id, which is built from the first attribute's value, stable across renders.)

**Form fields pair with declared attributes.** The form declares `name` and `email` so the submitted fields reach the callable as `attrs.name` and `attrs.email` — the same pairing as every Weft form (covered in depth in [the tutorial](../tutorial.md#7-taking-rsvps)). And since `form(action: :add)` also emits plain `action`/`method` attributes, the add still works without JavaScript; only the tableside update needs htmx.

## The decoupled variant

`includes` is directional: the form knows the table exists. Sometimes it shouldn't — the reacting components may be many, elsewhere, or someone else's. Then the form *announces* and interested components *listen*:

```ruby
class ContactsTable < Weft::Component
  # …exactly as before, plus one declaration:
  refreshes on: "contact-added"
end

class NewContactForm < Weft::Component
  # …exactly as before, but in place of `includes ContactsTable`:
  triggers "contact-added"
end
```

[`triggers`](../dsl.md#triggers--announce-to-the-rest-of-the-page) stamps every action response from the form with an `HX-Trigger: contact-added` header; htmx fires that as an event on the page body. [`refreshes on:`](../dsl.md#refreshes--the-client-re-fetches) wires the table's wrapper to listen for it (`from:body`) and re-fetch its own route. The two components never mention each other — any number of components can subscribe to `"contact-added"` without the form changing at all. The trade: each listener re-fetches itself, so a submit costs one extra GET per listener (and the table must now be routable, which its `refreshes` declaration itself ensures).

**Choosing between them:** reach for `includes` when the form naturally knows what it changes — everything arrives in the same response, zero extra requests. Reach for `triggers` when the reactions should be open-ended or the components shouldn't know about each other.

## htmx's four solutions, mapped

| htmx's solution | In Weft |
| --- | --- |
| 1. Expand the target | Still available — wrap both regions in one component and re-render it whole — but rarely needed once the next two are declarations. |
| 2. Out-of-band responses | `includes ContactsTable` on the form. |
| 3. Triggering events | `triggers "contact-added"` on the form, `refreshes on: "contact-added"` on the table. |
| 4. Path dependencies (extension) | Not needed — solutions 2 and 3 as declarations cover both coupling directions without an extension. |

## On the wire

The initial page render — two independent regions, and in this variant the table wrapper carries no wiring at all:

```html
<div id="contacts-table">
  <table>…Joe Smith…</table>
</div>
<div id="new-contact-form">
  <h3>Add a contact</h3>
  <form hx-post="/_components/new_contact_form/add" hx-target="#new-contact-form"
        hx-swap="outerHTML" action="/_components/new_contact_form/add" method="post">
    …
  </form>
</div>
```

Submitting `POST /_components/new_contact_form/add` with `name=Angie MacDowell&email=angie@macdowell.org` returns one response holding both fragments — the emptied form, then the table marked out-of-band, new row included:

```html
<div id="new-contact-form">
  <h3>Add a contact</h3>
  <form hx-post="/_components/new_contact_form/add" hx-target="#new-contact-form"
        hx-swap="outerHTML" action="/_components/new_contact_form/add" method="post">
    …fresh, empty fields…
  </form>
</div>
<div id="contacts-table" hx-swap-oob="true">
  <table>
    <thead><tr><th>Name</th><th>Email</th></tr></thead>
    <tbody>
      <tr><td>Joe Smith</td><td>joe@smith.org</td></tr>
      <tr><td>Angie MacDowell</td><td>angie@macdowell.org</td></tr>
    </tbody>
  </table>
</div>
```

In the decoupled variant, the same submit instead answers with the form alone plus the event header:

```
HTTP/1.1 200 OK
content-type: text/html;charset=utf-8
hx-trigger: contact-added
```

…and the table, whose wrapper rendered as

```html
<div id="contacts-table" hx-get="/_components/contacts_table"
     hx-trigger="contact-added from:body" hx-swap="outerHTML">
```

hears the event and issues `GET /_components/contacts_table`, which returns the fresh table with both rows.

## Related

- [Click to Edit](click-to-edit.md) — the form-fields-pair-with-attributes pattern this example builds on.
- [`includes`](../dsl.md#includes--companions-in-the-same-response), [`triggers`](../dsl.md#triggers--announce-to-the-rest-of-the-page), and [`refreshes`](../dsl.md#refreshes--the-client-re-fetches) in the DSL reference.
- `includes` accepts `on: :action_name` to scope a companion to one action, and a block to map the primary component's attrs onto the companion's — see [the DSL reference](../dsl.md#includes--companions-in-the-same-response).
