# Edit Row

A table where each row can switch into an editable state: Edit swaps the row for a row of inputs, Save writes the changes and swaps the display row back, Cancel backs out without saving.

This is Weft's take on [htmx's edit-row example](https://htmx.org/examples/edit-row/) — the [click-to-edit](click-to-edit.md) pattern applied per row. Two honest differences: their version uses hyperscript to enforce editing one row at a time, while here each row is its own independent component pair — several rows can be in edit mode at once, and one-at-a-time is app policy this example doesn't impose. And where their editor gathers its inputs with `hx-include="closest tr"`, this version leans on plain HTML instead.

## The components

```ruby
PEOPLE = {
  "1" => { name: "Joe Smith",       email: "joe@smith.org" },
  "2" => { name: "Angie MacDowell", email: "angie@macdowell.org" },
  "3" => { name: "Fuqua Tarkenton", email: "fuqua@tarkenton.org" }
}.freeze

class PersonRow < Weft::Component
  builder_method :person_row

  param :person_id

  def tag_name
    "tr"
  end

  def build(attributes = {})
    super
    person = PEOPLE.fetch(params.person_id)
    td person[:name]
    td person[:email]
    td do
      button "Edit", loads: PersonRowEditor, with: { person_id: params.person_id },
                     swap: :replace, target: self
    end
  end
end

class PersonRowEditor < Weft::Component
  builder_method :person_row_editor

  param :person_id
  param :name
  param :email

  transfers :save, to: PersonRow do |params|
    PEOPLE.fetch(params.person_id).merge!(name: params.name, email: params.email)
    nil
  end

  def tag_name
    "tr"
  end

  def build(attributes = {})
    super
    person = PEOPLE.fetch(params.person_id)
    save_form = "save-person-#{params.person_id}"
    td { input type: "text", name: "name", value: person[:name], form: save_form }
    td { input type: "text", name: "email", value: person[:email], form: save_form }
    td do
      form(action: :save, id: save_form) do
        input type: "hidden", name: "person_id", value: params.person_id
        input type: "submit", value: "Save"
        button "Cancel", type: "button",
               loads: PersonRow, with: { person_id: params.person_id },
               swap: :replace, target: self
      end
    end
  end
end

class PeopleTable < Weft::Component
  builder_method :people_table

  def build(attributes = {})
    super
    table do
      thead { tr { th "Name"; th "Email"; th "" } }
      tbody do
        PEOPLE.each_key { |id| person_row(person_id: id) }
      end
    end
  end
end
```

(The `PEOPLE` hash stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**It's click-to-edit, once per row.** Both components render as `<tr>` (the `tag_name` override), with the identifying param declared first so each carries a usable DOM id. Entering edit mode changes nothing on the server, so Edit is a [`loads:`](../dsl.md#loads) — a GET that fetches the editor row and replaces the display row (`swap: :replace, target: self`). Saving is a [`transfers`](../dsl.md#transfers--actions-that-render-something-else): the write runs, then the *display* row renders in the editor's place. Cancel is the Edit button's mirror image, pointed back at `PersonRow`. As in click-to-edit, defining the display component first lets `transfers :save, to: PersonRow` resolve in the editor's class body, while `loads: PersonRowEditor` waits until render.

**A form can't wrap table cells — so the cells point at the form.** HTML won't allow a `<form>` to span `<td>`s inside a row, which is the structural puzzle of this pattern. htmx's original solves it with `hx-include="closest tr"`; here plain HTML does the same job: the form lives in the last cell, and the name and email inputs associate with it from their own cells via the standard [`form` attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input#form). Form-associated elements are part of the form's submission set, so both htmx's payload *and* the no-JavaScript fallback submission include all three fields — nothing about the association needs scripting.

**Rows edit independently.** Each row is a self-contained component pair with its own ids (`person-row-2`, `person-row-editor-2`, `save-person-2`), so opening one editor doesn't disturb another. If your app wants only one row editable at a time, that's a policy to enforce on top of this pattern, not something the components themselves impose.

## On the wire

Each display row arrives wired (`GET /_components/person_row?person_id=1` returns the same fragment the table renders):

```html
<tr id="person-row-1">
  <td>Joe Smith</td>
  <td>joe@smith.org</td>
  <td>
    <button hx-get="/_components/person_row_editor?person_id=1"
            hx-swap="outerHTML" hx-target="#person-row-1">Edit</button>
  </td>
</tr>
```

Clicking Edit fetches the editor row — note the `form` attributes tying the scattered inputs to the form in the last cell, and the non-JS fallback on the form itself:

```html
<tr id="person-row-editor-1">
  <td><input type="text" name="name" value="Joe Smith" form="save-person-1"/></td>
  <td><input type="text" name="email" value="joe@smith.org" form="save-person-1"/></td>
  <td>
    <form id="save-person-1" hx-post="/_components/person_row_editor/save"
          hx-target="#person-row-editor-1" hx-swap="outerHTML"
          action="/_components/person_row_editor/save" method="post">
      <input type="hidden" name="person_id" value="1"/>
      <input type="submit" value="Save"/>
      <button type="button" hx-get="/_components/person_row?person_id=1"
              hx-swap="outerHTML" hx-target="#person-row-editor-1">Cancel</button>
    </form>
  </td>
</tr>
```

Submitting `POST /_components/person_row_editor/save` with the edited fields returns the updated display row, which replaces the editor:

```html
<tr id="person-row-1">
  <td>Joe B. Smith</td>
  <td>joe.smith@example.com</td>
  ...
</tr>
```

Only the params `PersonRow` itself declares travel into that render — the editor's `name` and `email` were consumed by the save and play no part in the row's element.

## Related

- [Click to Edit](click-to-edit.md) — the same two-state pattern on a standalone card, where a form can simply wrap its fields.
- [Delete Row](delete-row.md) — rows that leave the table instead of switching state.
- [`loads:`](../dsl.md#loads) and [`transfers`](../dsl.md#transfers--actions-that-render-something-else) in the DSL reference.
