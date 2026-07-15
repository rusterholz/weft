# Progress Bar

A Start button kicks off a background job, a progress bar advances as the server reports the work getting done, and a Restart button appears when it finishes — the whole lifecycle driven by one polling component.

This is Weft's take on [htmx's progress-bar example](https://htmx.org/examples/progress-bar/), with the same ARIA-annotated bar and the same smooth CSS-transition movement. htmx builds it from three hand-wired pieces — a start button, a polling wrapper, and an `HX-Trigger`-based handoff to stop the polling. In Weft it's one component with two declarations: `performs :start` for the kickoff, `refreshes every: 1` for the watching.

## The components

```ruby
# A fake background job: each status check advances the work by 20 points.
# Stands in for reading real progress from your job layer — a Sidekiq
# status hash, an ActiveJob progress record, whatever your app uses.
module FakeJob
  class << self
    def start!
      @state = "running"
      @progress = 0
    end

    # Report the current status, then advance the fake work so the next
    # check sees more of it done.
    def check
      snapshot = { state: state, progress: progress }
      advance if state == "running"
      snapshot
    end

    def state = @state ||= "idle"
    def progress = @progress ||= 0

    private

    def advance
      @progress += 20
      @state = "complete" if @progress >= 100
    end
  end
end

class JobMonitor < Weft::Component
  builder_method :job_monitor

  refreshes every: 1

  performs :start do |_params|
    FakeJob.start!
    nil
  end

  def build(attributes = {})
    super
    job = FakeJob.check
    case job[:state]
    when "idle"
      button "Start Job", action: :start
    when "running"
      h3 "Running", id: "pblabel"
      progress_bar(job[:progress])
    else
      h3 "Complete", id: "pblabel"
      progress_bar(100)
      button "Restart Job", action: :start
    end
  end

  private

  def progress_bar(percent)
    div class: "progress", role: "progressbar", "aria-valuemin": "0",
        "aria-valuemax": "100", "aria-valuenow": percent.to_s,
        "aria-labelledby": "pblabel",
        style: "max-width:20rem; background:#e5e7eb; border-radius:4px" do
      div class: "progress-bar",
          style: "width:#{percent}%; height:1.25rem; background:#2563eb; " \
                 "border-radius:4px; transition:width 1s linear"
    end
  end
end
```

## How it works

**One component renders the whole lifecycle.** `build` checks the job and renders whichever state it finds: a Start button, the advancing bar, or the finished bar with its Restart affordance. Because [`refreshes every: 1`](../dsl.md#refreshes--the-client-re-fetches) puts the polling wiring on the component's wrapper element, every poll replaces the component wholesale (`outerHTML`) — so the UI moves between states with no extra plumbing. When the server flips the job to complete, the next poll simply renders the completed state.

**Starting is an ordinary action.** The Start and Restart buttons both wire to [`performs :start`](../dsl.md#performs--user-initiated-actions), whose callable kicks the fake job and ends with `nil` — the re-render after the action shows the freshly started bar at 0%. htmx's version needs the start response to *establish* the polling wrapper; in Weft the wiring is declared on the class, so it's already present in every rendering, initial page included.

**The bar is just a styled div, meaningfully annotated.** The outer div carries `role="progressbar"` with `aria-valuenow`/`-valuemin`/`-valuemax` (mirroring htmx's markup), and the inner div's inline `width` is the percentage. The `transition: width 1s linear` matches the 1-second poll cadence, so the bar glides continuously instead of jumping — the same trick as htmx's "smooth" variant.

**Progress advances on each check.** `FakeJob.check` reports the current status and then moves the fake work forward, so five polls walk the bar 0 → 20 → 40 → 60 → 80 → done. In your app, `check` becomes a read of real job progress and the cadence stops being lockstep — the component doesn't care either way.

**One honest limitation:** the refresh wiring is class-level and unconditional in this release, so the completed (and idle) states keep polling once per second even though nothing will change until someone clicks Restart. htmx's original stops polling at 100% via an `HX-Trigger` handoff; Weft currently has no per-render way to switch the timer off.

## On the wire

The initial render (or `GET /_components/job_monitor`) — note the polling wiring already on the wrapper:

```html
<div id="job-monitor" hx-get="/_components/job_monitor" hx-trigger="every 1s" hx-swap="outerHTML">
  <button hx-post="/_components/job_monitor/start" hx-target="#job-monitor"
          hx-swap="outerHTML" hx-vals="{}">Start Job</button>
</div>
```

Clicking Start issues `POST /_components/job_monitor/start`, and the response is the running state at 0%:

```html
<div id="job-monitor" hx-get="/_components/job_monitor" hx-trigger="every 1s" hx-swap="outerHTML">
  <h3 id="pblabel">Running</h3>
  <div class="progress" role="progressbar" aria-valuemin="0" aria-valuemax="100"
       aria-valuenow="0" aria-labelledby="pblabel"
       style="max-width:20rem; background:#e5e7eb; border-radius:4px">
    <div class="progress-bar" style="width:0%; height:1.25rem; background:#2563eb; border-radius:4px; transition:width 1s linear"></div>
  </div>
</div>
```

Each poll — `GET /_components/job_monitor`, once per second — returns the same shape further along (`aria-valuenow="20"`, `width:20%`, then 40, 60, 80…). The fifth poll finds the job complete:

```html
<div id="job-monitor" hx-get="/_components/job_monitor" hx-trigger="every 1s" hx-swap="outerHTML">
  <h3 id="pblabel">Complete</h3>
  <div class="progress" role="progressbar" aria-valuemin="0" aria-valuemax="100"
       aria-valuenow="100" aria-labelledby="pblabel"
       style="max-width:20rem; background:#e5e7eb; border-radius:4px">
    <div class="progress-bar" style="width:100%; height:1.25rem; background:#2563eb; border-radius:4px; transition:width 1s linear"></div>
  </div>
  <button hx-post="/_components/job_monitor/start" hx-target="#job-monitor"
          hx-swap="outerHTML" hx-vals="{}">Restart Job</button>
</div>
```

Restart POSTs the same `:start` action and the cycle begins again. (The completed fragment still carries `hx-trigger="every 1s"` — the limitation noted above, visible on the wire.)

## Related

- [Live Ticker](live-ticker.md) — when the server should *push* updates instead of being polled.
- [`refreshes`](../dsl.md#refreshes--the-client-re-fetches) and [`performs`](../dsl.md#performs--user-initiated-actions) in the DSL reference.
- htmx's original polls every 600ms — `refreshes every: 0.6` expresses exactly that. This example keeps a 1-second cadence and matches the bar's `transition` duration to it.
