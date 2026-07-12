# Bulk Update

A table of team members, each row with an Activate checkbox; one submit applies every change at once, and a status line reports how many members were activated and deactivated.

This is Weft's take on [htmx's bulk-update example](https://htmx.org/examples/bulk-update/), with one structural difference. Their form posts the checkboxes and swaps a toast message into a separate slot, leaving the table as the user left it; in Weft the whole roster is one component, so the submit re-renders it from server state — the checkboxes come back showing what was actually saved, with the status line beneath them.

## The components

```ruby
TEAM_MEMBERS = {
  "1" => { name: "Joe Smith",       email: "joe@smith.org",       active: true },
  "2" => { name: "Angie MacDowell", email: "angie@macdowell.org", active: true },
  "3" => { name: "Fuqua Tarkenton", email: "fuqua@tarkenton.org", active: true },
  "4" => { name: "Kim Yee",         email: "kim@yee.org",         active: false }
}.freeze

class MemberRoster < Weft::Component
  builder_method :member_roster

  attribute :active_ids, default: []
  attribute :status

  performs :update, target: "#member-roster" do |attrs|
    checked = attrs.active_ids
    activated = deactivated = 0
    TEAM_MEMBERS.each do |id, member|
      active = checked.include?(id)
      activated += 1 if active && !member[:active]
      deactivated += 1 if !active && member[:active]
      member[:active] = active
    end
    { status: "Activated #{activated} and deactivated #{deactivated} members." }
  end

  def build(attributes = {})
    super
    set_attribute :id, "member-roster"
    form(action: :update) do
      table do
        thead { tr { th "Name"; th "Email"; th "Active" } }
        tbody do
          TEAM_MEMBERS.each do |id, member|
            tr do
              td member[:name]
              td member[:email]
              td do
                if member[:active]
                  input type: "checkbox", name: "active_ids[]", value: id, checked: "checked"
                else
                  input type: "checkbox", name: "active_ids[]", value: id
                end
              end
            end
          end
        end
      end
      input type: "submit", value: "Bulk Update"
    end
    para attrs.status if attrs.status
  end
end
```

(The `TEAM_MEMBERS` hash stands in for your data layer — swap in ActiveRecord or whatever your app uses.)

## How it works

**Bracket naming turns the checkboxes into one array.** Every checkbox shares the name `active_ids[]`, and Rack's parameter parsing folds those into a single array under the bracket-less key — so the component's declared `active_ids` attribute receives `["1", "2", "4"]`, and the callable reads it as `attrs.active_ids`. The values arrive as strings, which is why the data stub's keys are strings too. Checkboxes the user leaves unchecked simply aren't in the submission; that's the whole trick of the pattern.

**The `default: []` is load-bearing.** When *no* boxes are checked, the browser sends no `active_ids` parameter at all, and the attribute falls back to its default. An empty array makes that case mean "deactivate everyone" — and guarantees the callable always has a real array to call `include?` on, rather than `nil`.

**The callable diffs, then reports through its return value.** It compares each member's stored state against the submitted array, counts the flips, and writes the new state. Returning a hash merges it into the attrs for the re-render (see [the callable contract](../dsl.md#the-callable-contract)), so `{ status: "Activated 1 and deactivated 1 members." }` is how the count reaches the status line — `attrs.status` is `nil` on a fresh render and the paragraph only appears after an update.

**An array can't anchor a DOM id.** Weft derives a component's DOM id from its first declared attribute — perfect when that's a record id, unusable when it's an array (`id="member-roster-[]"` is not a selector htmx can target). So this component pins its own identity: `set_attribute :id, "member-roster"` fixes the wrapper's id inside `build`, and `performs :update, target: "#member-roster"` points the action's swap at that same anchor. Both live server-side, so every re-rendered fragment carries the same stable wiring.

**The checkboxes tell the truth after the write.** `build` renders each checkbox from the data store, not from the submitted attrs — the response reflects what was actually saved. And since `form(action: :update)` also emits plain `action`/`method` attributes, the whole thing degrades to a normal POST without JavaScript.

## On the wire

The initial render (or `GET /_components/member_roster`) — the form wired to the action, one row per member:

```html
<div id="member-roster">
  <form hx-post="/_components/member_roster/update" hx-target="#member-roster"
        hx-swap="outerHTML" action="/_components/member_roster/update" method="post">
    <table>
      <thead>...</thead>
      <tbody>
        <tr>
          <td>Joe Smith</td>
          <td>joe@smith.org</td>
          <td><input type="checkbox" name="active_ids[]" value="1" checked="checked"/></td>
        </tr>
        ...
        <tr>
          <td>Kim Yee</td>
          <td>kim@yee.org</td>
          <td><input type="checkbox" name="active_ids[]" value="4"/></td>
        </tr>
      </tbody>
    </table>
    <input type="submit" value="Bulk Update"/>
  </form>
</div>
```

Unchecking Fuqua, checking Kim, and submitting sends `POST /_components/member_roster/update` with the body `active_ids[]=1&active_ids[]=2&active_ids[]=4`. The response is the same component, re-rendered from the updated store — Fuqua's box now unchecked, Kim's checked — ending with:

```html
    <input type="submit" value="Bulk Update"/>
  </form>
  <p>Activated 1 and deactivated 1 members.</p>
</div>
```

Submitting with every box unchecked sends an empty body; the default kicks in and the response reports `Activated 0 and deactivated 3 members.`

## Related

- [Click to Edit](click-to-edit.md) — the basics of pairing form fields with declared attributes.
- [Delete Row](delete-row.md) and [Edit Row](edit-row.md) — acting on table rows one at a time instead of all at once.
- [`performs`](../dsl.md#performs--user-initiated-actions) and [the callable contract](../dsl.md#the-callable-contract) in the DSL reference.
