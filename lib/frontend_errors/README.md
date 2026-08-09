# FrontendErrors

Reports browser errors through `Rails.error`.

Uncaught JavaScript exceptions, unhandled promise rejections, Stimulus controller
errors and Turbo failures are captured in the browser, posted to a mounted
engine, and handed to `ActiveSupport::ErrorReporter`. Whatever the host has
subscribed — Solid Errors, Sentry, a plain logger — records them on the same path
as server-side errors. The gem itself depends on no particular backend.

## Why the backtraces are readable

With importmap + Propshaft there is no bundling and no minification, so a line
number in a served asset matches the source file exactly — no source maps
required. Frames are resolved back through the Propshaft digest
(`application-abc12345.js` → `application.js`) and re-emitted in Ruby's backtrace
shape:

```
/rails/app/javascript/controllers/map_controller.js:42:in `connect'
```

Backends that parse Ruby backtraces then treat those frames as application code
and show the surrounding source. Frames that can't be resolved (CDN scripts,
extensions, inline handlers) pass through verbatim.

Because the file part of that format can't contain a colon and a trailing
`:column` breaks the match, columns are dropped from the frame and reported in
the context instead.

## Install

```ruby
gem "frontend_errors"
```

Mount the engine and add the config tag to your layout:

```ruby
# config/routes.rb
mount FrontendErrors::Engine, at: "/frontend_errors"
```

```erb
<%# app/views/layouts/application.html.erb, in <head> %>
<%= frontend_errors_tag %>
```

Start the reporter before your own code, so it's listening when that code runs:

```js
// app/javascript/application.js
import { start } from "frontend_errors"
start()
```

And hook Stimulus, which otherwise swallows every controller error into
`console.error`:

```js
// app/javascript/controllers/application.js
import { installStimulusErrorHandler } from "frontend_errors"

const application = Application.start()
installStimulusErrorHandler(application)
```

## Configuration

```ruby
# config/initializers/frontend_errors.rb
FrontendErrors.context = -> {
  { user_id: Current.user&.id }
}
```

| Option | Default | |
|---|---|---|
| `base_controller_class` | `"::ActionController::Base"` | Superclass of the ingest controller. Deliberately not the host's `ApplicationController`: the endpoint has to work without a session so errors on sign-in pages are captured. |
| `context` | `-> { {} }` | Lambda `instance_exec`'d in the controller; returns extra flat context. Has access to `request`, `cookies`, … |
| `allowed_context_keys` | url, referrer, viewport, identifier, frame_id, method, status | Client-supplied context keys to keep. Strings or symbols. |
| `rate_limit_to` / `rate_limit_within` | `30` / `1.minute` | Per-IP limit on the endpoint. |
| `max_body_bytes` | `64.kilobytes` | Larger requests get a 413. |
| `max_reports_per_request` | `20` | |
| `max_reports_per_page` | `10` | Browser-side budget, reset on each Turbo visit. |
| `max_message_length` | `500` | |
| `max_frames` | `30` | |
| `message_filters` | uuids, urls, digests | Applied before reporting — see below. |
| `log_reports` | `nil` (on outside production) | Log every report, which is how you see the pipeline work in an environment with no subscriber. |

### Context

Two sources are merged. `FrontendErrors.context` is server-derived and
unrestricted — put identity there. Anything the browser sends is filtered
through `allowed_context_keys`, since the endpoint is unauthenticated; extend it
with whatever your own instrumentation reports:

```ruby
FrontendErrors.allowed_context_keys += %w[activity_id]
```

Values are coerced to short scalars whatever the list says, and **server-derived
context is merged last**, so a client can never overwrite a key the server
resolved for it — including one you add to the allowlist yourself.

### Message normalisation

Backends commonly fingerprint on the message — Solid Errors hashes
`exception_class + message + severity + source` — so an id or URL inside the text
would split one recurring bug across an unbounded number of groups.
`message_filters` collapses those before reporting.

### What arrives at the subscriber

- **Exception class** — `JS::TypeError`, `JS::UnhandledRejection`, … built per
  JavaScript error name so the backend's grouping stays legible. Names are
  allowlisted and the registry is capped, since the value comes from the client.
- **Source** — `javascript.window`, `javascript.promise`, `javascript.stimulus`,
  `javascript.turbo`, so capture sites don't group together.
- **Severity** — `:error`, except Turbo failures which are `:warning`.
- **Context** — url, referrer, viewport, column, user agent, plus whatever
  `FrontendErrors.context` adds and a small allowlist of per-source detail
  (Stimulus identifier, Turbo frame id).

## Endpoint exposure

`POST` to the mounted path is unauthenticated and CSRF-exempt: errors on the
sign-in page are worth having, and `navigator.sendBeacon` — the only transport
that survives a closing page — can't set a CSRF header. It is therefore bounded
on every axis: per-IP rate limit, body size, reports per request, message length,
and the generated exception-class registry. If the noise ever outweighs the
coverage, set `base_controller_class` to a controller that requires a session and
accept losing pre-login errors.
