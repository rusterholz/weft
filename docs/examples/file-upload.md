# File Upload

A file input, an Upload button, and a list of everything uploaded so far. The file travels through a component action like any other form submission, and the component re-renders with the list grown by one.

This is Weft's take on [htmx's file-upload example](https://htmx.org/examples/file-upload/), covering the upload itself; their JavaScript-driven progress meter is out of scope here — that part is hand-written JS even in htmx's own catalog.

## The components

```ruby
UPLOADED_REPORTS = []

class ReportUploader < Weft::Component
  builder_method :report_uploader

  attribute :document

  performs :upload do |attrs|
    file = attrs.document
    if file.is_a?(Hash) && file[:tempfile]
      UPLOADED_REPORTS << { name: file[:filename], size: file[:tempfile].size }
    end
    { document: nil }
  end

  def build(attributes = {})
    super
    form(action: :upload, enctype: "multipart/form-data") do
      input type: "file", name: "document"
      input type: "submit", value: "Upload"
    end
    if UPLOADED_REPORTS.any?
      h3 "Uploaded"
      ul do
        UPLOADED_REPORTS.each { |doc| li "#{doc[:name]} (#{doc[:size]} bytes)" }
      end
    end
  end
end
```

(The `UPLOADED_REPORTS` array stands in for wherever your app actually puts files — storage service, attachment library, what have you.)

## How it works

**One HTML attribute makes it multipart.** `enctype: "multipart/form-data"` isn't Weft vocabulary — it passes through to the `<form>` untouched, and it does double duty there: htmx honors a form's native enctype when it builds the request, and the no-JS fallback submit needs the same attribute anyway. Leave it off and the request still fires, but as an ordinary urlencoded POST whose file field has collapsed to the string `"[object File]"` — nothing a server can use. (htmx also has an `hx-encoding` attribute; it's only needed to force multipart from something other than a form.)

**The file arrives through a declared attribute.** The `document` attribute receives whatever the server's multipart parsing produces — under Sinatra, a hash carrying `:filename`, `:type`, and a `:tempfile` ready to read. The callable checks for that shape before storing, which quietly covers the other case too: submitting with no file chosen sends `document=` (an empty string), the `is_a?(Hash)` guard skips it, and the re-render is a no-op.

**Returning `{ document: nil }` is load-bearing.** A callable's returned hash merges into the attrs for the re-render ([the callable contract](../dsl.md#the-callable-contract)) — and this one uses that to *clear* the file param rather than add anything. Weft derives a component's DOM id from its first declared attribute, and a tempfile-toting multipart hash in that slot would smear itself across the wrapper's id and every piece of htmx wiring derived from it. Cleared, the component comes back as plain `#report-uploader`: same id, same wiring, fresh empty file input.

## On the wire

The initial render (or `GET /_components/report_uploader`) — the enctype sits as a plain HTML attribute beside the htmx wiring and the no-JS fallback:

```html
<div id="report-uploader">
  <form enctype="multipart/form-data" hx-post="/_components/report_uploader/upload"
        hx-target="#report-uploader" hx-swap="outerHTML"
        action="/_components/report_uploader/upload" method="post">
    <input type="file" name="document"/>
    <input type="submit" value="Upload"/>
  </form>
</div>
```

Choosing a file and pressing Upload sends a genuine multipart body — this one captured from htmx in a browser:

```
POST /_components/report_uploader/upload
Content-Type: multipart/form-data; boundary=----WebKitFormBoundarySSp7J2ErxcZUwkP2

------WebKitFormBoundarySSp7J2ErxcZUwkP2
Content-Disposition: form-data; name="document"; filename="browser-note.txt"
Content-Type: text/plain

hello from a real browser
------WebKitFormBoundarySSp7J2ErxcZUwkP2--
```

The response is the component re-rendered, upload duly listed:

```html
  <h3>Uploaded</h3>
  <ul>
    <li>browser-note.txt (25 bytes)</li>
  </ul>
</div>
```

The endpoint doesn't care where the multipart came from — a no-JS browser submit or `curl -F "document=@q3-report.txt" …` lands the same way. And the cautionary baseline: the identical browser submit *without* the enctype attribute arrives as `document=%5Bobject%20File%5D`, and nothing is stored.

## Related

- [Reset User Input](reset-user-input.md) — the same clear-it-in-the-return move, there to keep text fields empty.
- [Inline Validation](inline-validation.md) — rejecting a bad submission with a `422` instead of quietly ignoring it.
- [`performs`](../dsl.md#performs--user-initiated-actions) and [the callable contract](../dsl.md#the-callable-contract) in the DSL reference.
