# Value Select

Two selects, where the first drives the second: pick a car make, and the model select repopulates with that make's models — no page reload, no hand-written JavaScript.

This is Weft's take on [htmx's cascading-selects example](https://htmx.org/examples/value-select/), with one structural difference. Their server returns bare `<option>` tags that swap into the model select's interior; a Weft component brings its own wrapper element, so here the model select *is* the component — changing the make fetches a fresh `<select>` and swaps it into a stable slot.

## The components

```ruby
CAR_MODELS = {
  "audi"   => %w[A1 A4 A6],
  "toyota" => %w[Landcruiser Tacoma Yaris],
  "bmw"    => %w[325i 325ix X5]
}.freeze

class ModelSelect < Weft::Component
  builder_method :model_select

  param :make, default: "audi"

  def build(attributes = {})
    super
    set_attribute :name, "model"
    CAR_MODELS.fetch(params.make).each do |model|
      option model, value: model.downcase
    end
  end

  def tag_name
    "select"
  end
end
```

The make select needs no component of its own — it's plain markup in the page, with the Weft wiring as kwargs:

```ruby
class CarsPage < Weft::Page
  def build(attributes = {})
    super
    div do
      label "Make ", for: "make"
      select name: "make", id: "make",
             loads: ModelSelect, trigger: "change", swap: :fill, target: "#models" do
        option "Audi",   value: "audi"
        option "Toyota", value: "toyota"
        option "BMW",    value: "bmw"
      end
    end
    div do
      label "Model "
      span id: "models" do
        model_select(make: "audi")
      end
    end
  end
end
```

(The `CAR_MODELS` hash stands in for your data layer, as usual.)

## How it works

**The select's own value is the parameter.** The [`loads:`](../dsl.md#loads) kwarg generates a GET to `ModelSelect`'s route with *no* query string — and htmx completes it at request time: per [its parameter rules](https://htmx.org/docs/#parameters), the element that causes a request includes its own `name=value`. Changing the select to Toyota therefore sends `GET /_components/model_select?make=toyota`, and the component's declared `make` param picks the parameter up on the server (see [Params](../dsl.md#params)). That inclusion is htmx client-side behavior — you won't see it in any rendered attribute — so if the models ever fail to repopulate, the first thing to check is that the triggering select still has its `name`.

**Keep the URL clean of `with:`.** Baking `with: { make: ... }` into the URL would freeze the value at render time, fighting the live selection htmx appends. In page markup, simply omitting `with:` does the right thing. Inside a *component's* `build`, though, an omitted `with:` defaults to that component's current params — pass an explicit `with: {}` there to keep the live value as the only parameter.

**The component is the `<select>` itself.** Overriding `tag_name` (an [Arbre-layer move](../arbre.md#inside-build-the-component-contract)) makes the wrapper element a `<select>` rather than the default `<div>`, so the fetched fragment drops into the form as a real form control. Note that its `name` attribute is set inside `build` rather than at the call site: a fragment fetched over the wire is rebuilt from its declared params alone, so any wrapper attribute the pattern depends on belongs in `build`. And its DOM id derives from the `make` value, changing with every swap — which is why the make select targets the stable `#models` slot with `swap: :fill` instead of chasing the select by id.

**`trigger: "change"` is spelled out for clarity.** It's also htmx's default trigger for a `<select>`, which is why the original htmx example omits it; keeping it explicit costs one kwarg and makes the interaction readable at the call site.

## On the wire

The initial render of the two selects:

```html
<select name="make" id="make" hx-get="/_components/model_select"
        hx-swap="innerHTML" hx-target="#models" hx-trigger="change">
  <option value="audi">Audi</option>
  <option value="toyota">Toyota</option>
  <option value="bmw">BMW</option>
</select>
...
<span id="models">
  <select id="model-select-audi" name="model">
    <option value="a1">A1</option>
    <option value="a4">A4</option>
    <option value="a6">A6</option>
  </select>
</span>
```

Choosing Toyota sends `GET /_components/model_select?make=toyota`, which returns the fresh select:

```html
<select id="model-select-toyota" name="model">
  <option value="landcruiser">Landcruiser</option>
  <option value="tacoma">Tacoma</option>
  <option value="yaris">Yaris</option>
</select>
```

— and htmx fills `#models` with it. With no `make` parameter at all, the param's default renders the Audi list; parameters the component doesn't declare are simply ignored.

## Related

- [Click to Edit](click-to-edit.md) — the same `loads:` machinery swapping whole UI states instead of one control.
- [`loads:`](../dsl.md#loads) and [`trigger:`](../dsl.md#trigger) in the DSL reference; [Params](../dsl.md#params) for how parameters become `params`.
- The [`live_search:` shorthand](../dsl.md#shorthands) is this same fetch-into-a-slot pattern, triggered by typing instead of selecting.
