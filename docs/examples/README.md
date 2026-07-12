# Examples

If you've ever thought *"this button should be right here, and pressing it should just do the thing"* — that's the instinct Weft is built around. Each example on these pages starts from something a user should be able to do, and shows the component that does it: the markup, the behavior, and the server-side logic in one place, because in Weft they *are* one place.

Every example is complete and self-contained — a small data stub stands in for your real data layer, and the code shown is the code that ran. The "On the wire" sections quote real captured requests and responses, so you can see exactly what travels.

## The catalog

| Example | What it shows |
| --- | --- |
| [Click to Edit](click-to-edit.md) | Swap a read-only view for an edit form in place — `loads:` + `transfers` |
| [Edit Row](edit-row.md) | The same pattern per table row |
| [Delete Row](delete-row.md) | Remove a row with a confirmation — `dismisses` |
| [Bulk Update](bulk-update.md) | One form updating many rows — `performs` + array params |
| [Inline Validation](inline-validation.md) | Per-field validation as the user types — `performs` + `recovers` |
| [File Upload](file-upload.md) | Multipart upload through a component action |
| [Reset User Input](reset-user-input.md) | Clearing a form after submit — free in Weft |
| [Click to Load](click-to-load.md) | Load the next page of rows on demand — `load_more:` |
| [Lazy Loading](lazy-loading.md) | Defer expensive content until it's visible — `lazy:` |
| [Infinite Scroll](infinite-scroll.md) | Rows that keep coming as you scroll — `infinite_scroll:` |
| [Inline Expansion](inline-expansion.md) | Expand a row's detail in place — `inline_expand:` |
| [Active Search](active-search.md) | Search-as-you-type — `live_search:` |
| [Value Select](value-select.md) | Cascading selects — one select repopulating another |
| [Tabs](tabs.md) | Server-driven tab panes — `tabs:` |
| [Tooltip](tooltip.md) | Lazy-loaded hover detail — `tooltip:` |
| [Modal Dialog](modal-dialog.md) | Open a modal, close it, no JavaScript — `modal:` + `dismisses` |
| [Browser Dialogs](browser-dialogs.md) | Native confirm/prompt guards on actions |
| [Keyboard Shortcuts](keyboard-shortcuts.md) | Key-driven actions via `trigger:` |
| [Progress Bar](progress-bar.md) | A job-runner progress bar — `refreshes every:` |
| [Live Ticker](live-ticker.md) | Server-pushed updates over SSE — `pushes every:` |
| [Updating Other Content](updating-other-content.md) | One action updating several regions — `includes` + `triggers` |

## Coming from htmx?

This catalog deliberately covers the ground of [htmx's examples](https://htmx.org/examples/) — if you know a pattern from there, its Weft answer is here. Three of the pages above (Tooltip, Inline Expansion, Live Ticker) have no htmx counterpart; everything in htmx's catalog maps as follows:

| htmx example | Weft's answer |
| --- | --- |
| Click To Edit | [Click to Edit](click-to-edit.md) |
| Bulk Update | [Bulk Update](bulk-update.md) |
| Click To Load | [Click to Load](click-to-load.md) |
| Delete Row | [Delete Row](delete-row.md) |
| Edit Row | [Edit Row](edit-row.md) |
| Lazy Loading | [Lazy Loading](lazy-loading.md) |
| Inline Validation | [Inline Validation](inline-validation.md) |
| Infinite Scroll | [Infinite Scroll](infinite-scroll.md) |
| Active Search | [Active Search](active-search.md) |
| Progress Bar | [Progress Bar](progress-bar.md) |
| Value Select | [Value Select](value-select.md) |
| File Upload | [File Upload](file-upload.md) — the upload itself; the JS-driven progress meter is out of scope |
| Preserving File Inputs | not ported — a browser constraint htmx works around with custom JS; re-select files after a failed submit |
| Reset User Input | [Reset User Input](reset-user-input.md) |
| Dialogs — Browser | [Browser Dialogs](browser-dialogs.md) |
| Dialogs — UIKit | see [Modal Dialog](modal-dialog.md); CSS-framework integrations are future work |
| Dialogs — Bootstrap | same |
| Dialogs — Custom | [Modal Dialog](modal-dialog.md) — and Weft's needs no hyperscript |
| Tabs (HATEOAS) | [Tabs](tabs.md) |
| Tabs (JavaScript) | [Tabs](tabs.md) — the server-driven variant *is* the Weft way |
| Keyboard Shortcuts | [Keyboard Shortcuts](keyboard-shortcuts.md) |
| Sortable (drag & drop) | not ported — requires Sortable.js; client-side JS integration is outside this catalog's scope |
| Updating Other Content | [Updating Other Content](updating-other-content.md) — declarative, where htmx offers four manual options |
| Confirm (custom dialog) | not ported — requires sweetalert2; the no-JS answer is [Browser Dialogs](browser-dialogs.md) |
| Async Authentication | not ported — client-side token handling, outside this catalog's scope |
| Web Components | not ported — shadow-DOM integration, outside this catalog's scope |
| Animations | not ported yet — htmx's swap/settle CSS classes work unchanged under Weft |
| moveBefore() | not ported — experimental browser API |

## Where these fit

The examples show *patterns*; the mechanics behind them live in the reference docs — [the DSL](../dsl.md) for every verb and kwarg, [Routing](../routing.md) for how components get their URLs, [Error handling](../error-handling.md) for the recovery machinery, and [Arbre](../arbre.md) for the HTML layer itself. New to Weft entirely? Start with [the tutorial](../tutorial.md).
