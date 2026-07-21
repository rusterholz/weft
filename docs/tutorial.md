# Build your first Weft app

In this tutorial we'll build a small RSVP tracker: a list of events, a detail page per event, a form for RSVPing, and an attendee list that updates live. By the end you'll have written pages, components, a user action with validation, and a polling live update — with no routes file, no controllers, and no JavaScript.

Expect it to take twenty to thirty minutes. You'll need Ruby 3.2 or newer and basic familiarity with Bundler. Every step ends with something you can see working before moving on.

**The steps:**

- [1. Scaffold the project](#1-scaffold-the-project)
- [2. Wire up the app](#2-wire-up-the-app)
- [3. Your first page](#3-your-first-page)
- [4. Some data](#4-some-data)
- [5. The event page](#5-the-event-page)
- [6. Your first component](#6-your-first-component)
- [7. Taking RSVPs](#7-taking-rsvps)
- [8. Going live](#8-going-live)
- [Where to go from here](#where-to-go-from-here)

## 1. Scaffold the project

Create a directory with this shape:

```
rsvp/
├── Gemfile
├── config.ru
├── config/
│   └── environment.rb
└── app/
    ├── components/
    ├── data/
    └── pages/
```

The layout is a convention, not a requirement, but it's the one Weft apps generally follow: `app/pages/` for full-page views, `app/components/` for the interactive pieces that compose into them, and (in our case) `app/data/` for a toy data layer.

The `Gemfile`:

```ruby
source "https://rubygems.org"

gem "weft"
gem "puma"     # a web server
gem "rackup"   # the `rackup` command (split out of Rack itself in Rack 3)
```

Those second two lines matter. Weft runs on Rack, and since Rack 3 the `rackup` command ships as its own gem — without it, `bundle exec rackup` fails with a cryptic `can't find executable rackup for gem rack`. Adding `puma` and `rackup` up front saves you that detour.

```bash
bundle install
```

## 2. Wire up the app

`config.ru` is the whole server story — Weft's Router *is* the Rack app:

```ruby
require_relative "config/environment"

run Weft::Router
```

`config/environment.rb` is where your application loads. Weft doesn't dictate this file, but here's a shape that works:

```ruby
require "bundler/setup"
require "weft"

APP_ROOT = File.expand_path("..", __dir__)

# Load the application: data first, then components, then pages
# (pages compose components). Within each directory, files load
# alphabetically.
%w[data components pages].each do |dir|
  Dir[File.join(APP_ROOT, "app", dir, "*.rb")].sort.each { |file| require file }
end

Weft.configure do |c|
  c.auto_reload = true
  c.reload_paths = [File.join(APP_ROOT, "app", "**", "*.rb")]
end
```

Two things to notice:

- **Loading is just `require`.** Weft discovers your pages and components the moment their classes are defined — there's nothing to register. The directory ordering matters a little: if a component references another class *in its class body* (you'll see `includes AttendeeList` later), the referenced file has to load first. Our data → components → pages ordering plus alphabetical luck covers this tutorial; a growing app eventually wants a real autoloader like Zeitwerk.
- **Turn on `auto_reload` before your first run.** In a moment you'll be editing files and refreshing the browser; with these two settings, your edits apply without restarting the server. (In a real app you'd gate this on an environment check — see [Configuration](configuration.md#auto_reload).)

## 3. Your first page

Create `app/pages/events_page.rb`:

```ruby
class EventsPage < Weft::Page
  def build(attributes = {})
    attributes[:title] = "Upcoming Events"
    super
    h1 "Upcoming Events"
    para "If you can read this in the browser, the app is wired up."
  end
end
```

A page is a class. `build` describes its content using [Arbre](arbre.md)'s HTML builder methods — `h1`, `ul`, `div`, and friends — as plain Ruby. The `super` call renders the document shell around you: doctype, `<head>` with the htmx script, `<body>`. Setting `attributes[:title]` before `super` puts your title in the `<head>`.

Start the server and have a look:

```bash
bundle exec rackup
```

Visit [http://localhost:9292/events](http://localhost:9292/events). You should see the heading and the paragraph.

Nobody told Weft about that URL. The route came from the class name: `EventsPage`, minus the `Page` suffix, snake-cased — `/events`. (The suffix is optional; a class named `Events` routes to the same place. See [Routing](routing.md) for the full derivation rules.)

> **The `p` gotcha — read this before it costs you an hour.** The one HTML tag you *can't* write the obvious way is the paragraph. Ruby's built-in `Kernel#p` (the debugging printer) shadows the `<p>` builder, so this:
>
> ```ruby
> p "If you can read this in the browser, the app is wired up."
> ```
>
> renders no paragraph at all — and the text goes to your *server terminal* instead, courtesy of `Kernel#p`. Nothing errors; the paragraph is just silently missing. Use **`para`** for paragraphs, always.

Two more things worth ten seconds each while the server is up:

- Visit [http://localhost:9292/](http://localhost:9292/) — a styled "Not found" page, for free. Weft ships default error and not-found handling out of the box ([Error handling](error-handling.md)).
- Edit the `para` text and refresh — the change appears without a restart. That's `auto_reload` earning its keep.

## 4. Some data

Weft has no opinions about your data layer — use ActiveRecord, Sequel, an API client, whatever your app needs. For this tutorial, a hash in memory is plenty. Create `app/data/event_store.rb`:

```ruby
# An in-memory store with a couple of seed events. RSVPs live in a
# name => answer hash per event. State resets when the server restarts —
# fine for learning.
module EventStore
  Event = Struct.new(:id, :name, :date, :location, :rsvps)

  EVENTS = {
    "summer-bbq" => Event.new(
      "summer-bbq", "Summer BBQ", "Saturday July 18, 4pm", "Riverside Park",
      { "Priya" => "yes" }
    ),
    "trivia-night" => Event.new(
      "trivia-night", "Trivia Night", "Thursday July 23, 7pm", "The Rusty Anchor",
      {}
    )
  }.freeze

  def self.all = EVENTS.values
  def self.find(id) = EVENTS[id]
end
```

And make `EventsPage` list the real events:

```ruby
class EventsPage < Weft::Page
  def build(attributes = {})
    attributes[:title] = "Upcoming Events"
    super
    h1 "Upcoming Events"
    ul do
      EventStore.all.each do |event|
        li do
          a event.name, href: "/events/#{event.id}"
          text_node " — #{event.date}"
        end
      end
    end
  end
end
```

(`text_node` inserts plain text next to other elements — handy when a line mixes a link and loose text.)

**Restart the server for this one.** `auto_reload` re-runs files it already knows about, but `event_store.rb` is a *new* file — the loader glob ran at boot, before it existed. If you refresh without restarting, you'll get Weft's error page with `uninitialized constant EventsPage::EventStore`, which is your cue. New file → restart; edits to existing files → just refresh.

After the restart, `/events` lists both events as links. They 404 — let's fix that.

## 5. The event page

Create `app/pages/event_page.rb`:

```ruby
class EventPage < Weft::Page
  self.page_path = "/events/:event_id"

  param :event_id

  def build(attributes = {})
    event = EventStore.find(params.event_id)
    raise Weft::NotFound, "no event called #{params.event_id}" unless event

    attributes[:title] = event.name
    super
    h1 event.name
    para "#{event.date} — #{event.location}"
    a "← All events", href: "/events"
  end
end
```

Restart (new file), then click through to an event. Two new ideas here:

**Params are a page's wire state.** `param :event_id` declares that this page is parameterized, and the `page_path` pattern says where the value comes from: `/events/summer-bbq` gives the page `event_id = "summer-bbq"`. A page with params needs an explicit `page_path` — there's no way to derive a parameterized pattern from a class name, and Weft will tell you exactly that if you forget.

One nicety worth calling out: `params` is resolved before `build` runs, so `params.event_id` is available throughout — *including* before `super`. That's what lets us look the event up in time to set the page title, which has to be in place before `super` renders the `<head>`. (The `attributes` hash is a separate thing: it carries the page's shell chrome, like `title`, into `super`.)

**Raising is error handling.** For an unknown event, we `raise Weft::NotFound` and we're done — Weft turns it into a proper 404 response with its default not-found page. Try [http://localhost:9292/events/nope](http://localhost:9292/events/nope). There's a whole family of semantic errors (`Weft::Unprocessable` will appear shortly), and everything about the resulting rendering is customizable — see [Error handling](error-handling.md).

## 6. Your first component

Pages are destinations; **components** are the composable, interactive pieces inside them. Create `app/components/attendee_list.rb`:

```ruby
class AttendeeList < Weft::Component
  builder_method :attendee_list

  param :event_id

  def build(attributes = {})
    super
    event = EventStore.find(params.event_id)
    h2 "Who's coming"
    if event.rsvps.empty?
      para "No RSVPs yet. Be the first!"
    else
      ul do
        event.rsvps.each do |name, answer|
          li "#{name} — #{answer}"
        end
      end
    end
  end
end
```

`builder_method :attendee_list` is the composition idiom: it makes `attendee_list(...)` available as a builder inside any other `build`, just like `h1` and `ul`. Declare one on every component — it's how components nest naturally.

Add it to `EventPage`, before the back-link:

```ruby
    attendee_list
```

Notice there's no `event_id:` here. The component is nested inside a page that already carries `event_id`, and params flow down the render tree — so `attendee_list` inherits it automatically. That inheritance is central to how Weft composes; the [DSL reference](dsl.md#inheritance-and-the-render-tree) has the full picture.

Restart, and the Summer BBQ page shows Priya under "Who's coming".

View the page source and look at the wrapper Weft rendered:

```html
<div id="attendee-list-summer-bbq">
```

That DOM id was derived, not written: the class name, plus the value of the component's **first declared param**. The convention matters — it's how updates land on the right element when several instances share a page — so declare the identifying param first. (A list of attendee *rows*, say, would want `param :name` first, or every row would collide on the same event-derived id.)

One more thing, and it's the heart of Weft. Your component isn't just markup inside the page — it's independently addressable:

```bash
curl "http://localhost:9292/_components/attendee_list?event_id=summer-bbq"
```

That returns the component alone, as an HTML fragment, rendered fresh. Weft routed it automatically, the same way it routed your pages. Everything in the rest of this tutorial — form submissions, live updates — is machinery that fetches components like this and swaps them into the page. See [Routing](routing.md) for the details.

## 7. Taking RSVPs

Now the interactive part. Create `app/components/rsvp_form.rb`:

```ruby
class RSVPForm < Weft::Component
  builder_method :rsvp_form

  param :event_id
  param :name
  param :answer
  param :error_message

  includes AttendeeList

  performs :submit do |params|
    event = EventStore.find(params.event_id)
    name = params.name.to_s.strip
    raise Weft::Unprocessable, "Please tell us your name." if name.empty?

    event.rsvps[name] = params.answer
    nil
  end

  recovers from: Weft::Unprocessable do |_params, error|
    { error_message: error.message }
  end

  def build(attributes = {})
    super
    h2 "RSVP"
    para(params.error_message, style: "color:#b91c1c") if params.error_message
    form(action: :submit) do
      input(type: "hidden", name: "event_id", value: params.event_id)
      label("Your name: ", for: "name")
      input(type: "text", name: "name", id: "name")
      label(" Coming? ", for: "answer")
      select(name: "answer", id: "answer") do
        %w[yes no maybe].each { |ans| option(ans, value: ans) }
      end
      input(type: "submit", value: "Send RSVP")
    end
  end
end
```

Add it to `EventPage` above the attendee list:

```ruby
    rsvp_form
    attendee_list
```

Restart, open Trivia Night, RSVP as yourself — **the attendee list updates without a page reload**, and the form clears. Then try submitting with a blank name: a red message appears in the form, and the list is untouched.

That's a lot from one class. Unpacking it:

**`performs :submit` declares a user action.** The block is the behavior: it receives the component's resolved params, does its work, and whatever it returns directs what renders next — `nil` means "re-render me fresh" (our success path). Weft generates the route for the action; you never wrote one.

**`form(action: :submit)` wires the form to the action.** Look at the rendered HTML:

```html
<form hx-post="/_components/rsvp_form/submit" hx-target="#rsvp-form-trivia-night"
      hx-swap="outerHTML" action="/_components/rsvp_form/submit" method="post">
```

The `hx-*` attributes make the form submit in place. The plain `action` and `method` attributes are there too, so the form still works with JavaScript disabled — it degrades to a normal POST.

**Form fields map to declared params, one to one.** The action block reads `params.name` and `params.answer` because the form has fields named `name` and `answer` *and* the component declares params of the same names. Both halves are needed: declared-but-not-a-field values don't travel (that's why `event_id` rides along as a hidden input — it's part of the component's identity, not something the user types), and field-but-not-declared values are ignored.

**Validation is a raise plus a recovery.** The action raises `Weft::Unprocessable`; the `recovers` declaration catches it, and its block returns extra params to merge into the re-render — here, `error_message`, which `build` displays when present. Note that `error_message` is itself a declared param: recovery data flows through the same schema as everything else. The response even carries a semantically-correct 422 status. See [Error handling](error-handling.md) for how far this system goes.

**`includes AttendeeList` updates the list in the same response.** Submitting the form changes data that *another* component displays. This declaration says: whenever RSVPForm responds to an action, render AttendeeList too, marked so it swaps into its own place in the page (by that derived DOM id — this is why the convention exists). One interaction, two regions updated, zero JavaScript.

## 8. Going live

The attendee list updates when *you* RSVP — but not when someone else does. One line fixes that. In `AttendeeList`, under the param:

```ruby
  refreshes every: 10
```

This edit hot-reloads — no restart. Open the same event in two browser windows, RSVP in one, and within ten seconds the other window's list catches up. The component now polls its own URL (the one you curled in step 6) and swaps itself:

```html
<div id="attendee-list-summer-bbq"
     hx-get="/_components/attendee_list?event_id=summer-bbq"
     hx-trigger="every 10s" hx-swap="outerHTML">
```

Declared once on the class, the behavior is present in the initial page render *and* in every refreshed fragment, so it keeps polling forever. Polling is the simplest live-update verb; `pushes` gives you server-sent events with the same one-line flavor ([The Weft DSL](dsl.md#pushes--the-server-sends-updates)).

## Where to go from here

You've built pages that route themselves, components that compose and self-address, a validated user action with out-of-band updates, and a live-polling list — the core of how Weft apps are put together.

**An exercise, if you're enjoying yourself:** add a "withdraw" button next to each attendee. You'll want a per-attendee component (careful which param you declare first — each row needs its own DOM id), and the `dismisses` verb, which removes a component from the page when its action succeeds. The [DSL reference](dsl.md#dismisses--remove-from-the-dom) has what you need.

**A finishing touch:** the events list living at `/events` leaves `/` as a 404. Give `EventsPage` an explicit home: `self.page_path = "/"`.

**The reference docs**, when you want the full picture:

- [The Weft DSL](dsl.md) — every verb (`transfers`, `pushes`, `dismisses`, `triggers`…), the element kwargs, and the interaction presets (tooltips, modals, lazy loading) this tutorial didn't touch.
- [Arbre: the HTML layer](arbre.md) — the HTML builder underneath every `build` method: its argument conventions, text handling, container patterns, and gotchas beyond `para`.
- [Routing](routing.md) — how paths derive, what's routable, collision detection.
- [Error handling](error-handling.md) — the error family, recovery chains, branding your error pages.
- [Configuration](configuration.md) — every setting, including production concerns like static assets and quieter error pages.
