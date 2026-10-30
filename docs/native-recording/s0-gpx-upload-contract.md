# S0 — GPX-on-device upload contract

**Status:** Decided. Foundation spike for recording activities natively in the iOS and Android apps.

This document fixes the contract between the native recorders (iOS/Android) and
the Rails server **before** any native code is written. It is the single source
of truth for the wire format and the upload/navigation flow. No native code is
introduced by this spike.

---

## 1. Decision summary

- The native recorders serialize an on-device recording to **GPX 1.1** and
  upload it through the **existing** `POST /activities` endpoint. No FIT
  encoder, no new ingestion pipeline.
- The server already routes a `.gpx` upload to `GpxExtractor`
  (`Activity#parse_gpx_file`), which builds the `Activity` + `ActivityDataPoint`
  records, derives distance / elevation / moving time / speed, and reverse
  geocodes the start point. The device emits **positions + time + sensors
  only**; all summary metrics are computed server-side.
- Sport is chosen on the device and sent as the authoritative
  **`activity[sport]`** form param. A best-effort `<trk><type>` is also emitted
  for GPX self-containedness, but the param wins.
- For navigation, `POST /activities` now answers **`Accept: application/json`**
  with `201 Created`, a `Location` header, and a `{ "id", "url" }` body so a
  non-Turbo native client can jump straight to the activity. The HTML/Turbo
  redirect behavior is unchanged.

### Why GPX (recap)

`RubyFit` is decode-only (no encoder in-repo). `GpxExtractor` already parses
`<trkpt>` time/ele plus the Garmin `TrackPointExtension` `<hr>`/`<cad>` and a
`<power>` element, and computes distance, elevation gain, moving time, speed
(Hampel-filtered) and the PostGIS path. So GPX gets us to a working upload with
near-zero new server code — versus writing and maintaining a FIT encoder in both
Swift and Kotlin.

---

## 2. GPX schema the apps MUST emit

A single track (`<trk>`) with a single segment (`<trkseg>`). Reference fixture:
[`test/fixtures/files/gpx/native_recording.gpx`](../../test/fixtures/files/gpx/native_recording.gpx),
proven to round-trip by `test/lib/gpx_extractor_test.rb`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx creator="Velo iOS" version="1.1"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
 <metadata>
  <time>2026-06-25T08:00:00Z</time>
 </metadata>
 <trk>
  <name>Sortie enregistrée sur le téléphone</name>
  <type>cycling</type>
  <trkseg>
   <trkpt lat="48.8566000" lon="2.3522000">
    <ele>35.0</ele>
    <time>2026-06-25T08:00:00Z</time>
    <extensions>
     <gpxtpx:TrackPointExtension>
      <gpxtpx:hr>112</gpxtpx:hr>
      <gpxtpx:cad>84</gpxtpx:cad>
     </gpxtpx:TrackPointExtension>
     <power>180</power>
    </extensions>
   </trkpt>
   <!-- … one <trkpt> per recorded sample (≈1 Hz) … -->
  </trkseg>
 </trk>
</gpx>
```

### Namespaces

- Root default namespace: `http://www.topografix.com/GPX/1/1` (GPX 1.1).
- `gpxtpx` → `http://www.garmin.com/xmlschemas/TrackPointExtension/v1`.
- **Prefixes are cosmetic for ingestion.** `GpxExtractor` calls
  `Nokogiri::XML::Document#remove_namespaces!`, so the parser matches on
  *local element names* (`hr`, `cad`, `power`, `ele`, `time`). Emit the standard
  namespaces anyway, for interoperability with other GPX tools (Strava, Garmin).

### Track metadata

| Element        | Meaning                                                                 | Required |
| -------------- | ----------------------------------------------------------------------- | -------- |
| `<trk><name>`  | Activity name. Fallback only — overridden by `activity[name]` param.    | optional |
| `<trk><type>`  | Sport hint, see §3. Fallback only — overridden by `activity[sport]`.    | optional |

Both are applied with `||=` against any value already set from the upload
params, so the params always win.

### Per-track-point fields

| Field                                     | Type / unit                          | Required | Notes                                                                 |
| ----------------------------------------- | ------------------------------------ | -------- | --------------------------------------------------------------------- |
| `lat`, `lon` (attributes)                 | decimal degrees, WGS84               | **yes**  | A point missing lat, lon, **or** `<time>` is dropped on import.        |
| `<time>`                                  | **UTC ISO 8601 with `Z`**            | **yes**  | Parsed and normalized to UTC. Emit `Z`, not a local offset.           |
| `<ele>`                                   | meters                               | no       | Elevation gain derived server-side with a 3 m noise threshold.         |
| `<extensions>/…/<hr>` (gpxtpx)            | integer, bpm                         | no       | Heart rate.                                                            |
| `<extensions>/…/<cad>` (gpxtpx)           | rpm (cycling) / spm (run)            | no       | Cadence.                                                              |
| `<extensions>/<power>`                    | watts                                | no       | Strava-style `<power>` element, sibling of `TrackPointExtension`.      |

### Units & conventions

- **Distance and speed are NOT emitted by the device.** The server computes
  distance (meters, Haversine between successive points) and per-point speed
  (m/s), then runs speed through a Hampel filter (`SpeedFilter`) to drop GPS
  spikes and derive `max_speed`. Sending device speed would be ignored.
- `<ele>` in meters; `<time>` in UTC. `<hr>` integer bpm; `<cad>` and `<power>`
  numeric.
- Sample at ~1 Hz. Pauses are inferred server-side: gaps longer than 30 s do not
  count toward moving time, and segments slower than 0.5 m/s are treated as
  stopped. The device does **not** need to emit explicit pause markers; if the
  recorder pauses, simply stop emitting points until it resumes.

---

## 3. Sport selection: UX surface and mapping

**UX decision:** the sport is chosen on the device (native picker on the
recording start screen), defaulting to the user's last-used sport. It is **not**
inferred from GPX after the fact.

**Wire mapping decision:** the device sends the chosen sport as the authoritative
**`activity[sport]`** param (one of the 14 enum values below) **and** emits a
best-effort `<trk><type>` for GPX self-containedness. The controller sets `sport`
from the param before `GpxExtractor` runs, and the extractor only fills `sport`
when it is still blank (`||=`), so the param always wins. This matters for
`workout`, which has **no** `<trk><type>` mapping and therefore *must* travel via
the param.

`Activity` sport enum ⇄ canonical `<trk><type>` to emit:

| `activity[sport]` (enum) | `<trk><type>` to emit | Maps back via `GPX_SPORT_MAP`? |
| ------------------------ | --------------------- | ------------------------------ |
| `bike`                   | `cycling`             | yes                            |
| `mountain_bike_ride`     | `mountainbiking`      | yes                            |
| `gravel_ride`            | `gravelbiking`        | yes                            |
| `virtual_ride`           | `virtualride`         | yes                            |
| `e_bike_ride`            | `ebiking`             | yes                            |
| `run`                    | `running`             | yes                            |
| `trail_run`              | `trailrunning`        | yes                            |
| `virtual_run`            | `virtualrunning`      | yes                            |
| `walk`                   | `walking`             | yes                            |
| `hike`                   | `hiking`              | yes                            |
| `alpine_ski`             | `alpineski`           | yes                            |
| `nordic_ski`             | `nordicski`           | yes                            |
| `swim`                   | `swimming`            | yes                            |
| `workout`                | *(omit — no mapping)* | no — rely on the param         |

`GpxExtractor::GPX_SPORT_MAP` normalizes the incoming `<type>` with
`downcase.delete(" -_")`, so `cycling`, `Cycling`, `mountain_biking`,
`mountain biking`, and `mountainbiking` all match. An unrecognized `<type>`
falls back to `:bike` — another reason to always send the explicit param.

---

## 4. Upload contract (HTTP)

```
POST /activities
Content-Type: multipart/form-data
Accept: application/json
Cookie: session_id=<signed cookie shared with the Hotwire Native webview>
```

Multipart form fields (note the `activity[…]` nesting — same `params.expect`
shape as the web form):

| Field                   | Required | Notes                                                                                          |
| ----------------------- | -------- | ---------------------------------------------------------------------------------------------- |
| `activity[source_file]` | **yes**  | The GPX bytes. `ActivityIngestion` dispatches on the *filename*: an `original_filename` ending in `.gpx` is read by `GpxExtractor`, anything else by `FitExtractor`. **The uploaded part's filename MUST end in `.gpx`.** |
| `activity[fit_file]`    | alias    | Accepted alias for `activity[source_file]`, named `fit_file` even for GPX, historically. No client in this repo sends it since ADR 0003 retired the native uploader, but builds predating that change still do. If both are sent, `source_file` wins. See ADR 0005. |
| `activity[sport]`       | **yes**  | One of the 14 enum values (§3). Authoritative.                                                  |
| `activity[name]`        | optional | Overrides `<trk><name>`. If neither is present the activity is unnamed (see naming note below). |
| `activity[description]` | optional | Free text.                                                                                     |
| `activity[visibility]`  | optional | `private` (default) \| `shareable` \| `public`.                                                |

Exactly one of `activity[source_file]` / `activity[fit_file]` is required.

**Authentication:** the native HTTP request reuses the signed `session_id`
cookie that the Hotwire Native webview already holds (set httponly,
`same_site: :lax` by the `Authentication` concern). No token endpoint is needed.
Auth is independent of the Rails session, so CSRF strategy does not affect it.

**CSRF (action item for the upload PR):** CSRF protection is on by default
(`config.load_defaults 8.1`). The Turbo web form satisfies it via the page's
`<meta name="csrf-token">`; a native HTTP request originating *outside* the
webview has no such token and would be rejected in production. Recommended
minimal change in the upload PR — exempt only the JSON format, leaving the HTML
form fully protected (mirrors `ConfigurationsController#skip_forgery_protection`,
which already exempts the native config endpoints):

```ruby
# app/controllers/activities_controller.rb
protect_from_forgery with: :exception, unless: -> { request.format.json? }
```

This is safe here because authentication rides the dedicated signed `session_id`
cookie rather than the CSRF-bearing Rails session. It is **not** applied in this
spike PR (security-relevant; belongs with the client that needs it).

**Naming:** if you want the upload to land directly named, send `activity[name]`
(or `<trk><name>`). Otherwise the activity is created and the existing
"awaiting name" prompt flow applies on next view.

---

## 5. Navigation contract

Implemented in this PR. `POST /activities` is now format-aware:

**Success (`Accept: application/json`):**

```
HTTP/1.1 201 Created
Location: https://<host>/activities/123
Content-Type: application/json

{ "id": 123, "url": "https://<host>/activities/123" }
```

The native recorder, on a successful upload, loads `url` in the Hotwire Native
webview (pushing the activity show page onto the nav stack) and dismisses the
native recording screen.

**Validation failure (`Accept: application/json`):**

```
HTTP/1.1 422 Unprocessable Content
Content-Type: application/json

{ "errors": ["Sport doit être rempli(e)", "..."] }
```

The device surfaces these to the user (e.g. an alert) and keeps the recording so
it can be retried — the on-device DB is the source of truth until the server
confirms `201`.

**HTML/Turbo (unchanged):** still a `302` redirect to the activity (web upload
form behavior is untouched).

> Note: the bare `302` from the HTML path *also* carries a `Location` header, so
> a client that disables redirect-following could read it there. We went with an
> explicit JSON `201` instead: it is decoupled from Turbo/HTML behavior, returns
> a proper created status, and gives structured validation errors.

---

## 6. What this spike delivers vs. defers

**Delivered here (server-only, no native code):**

- The fixed GPX schema above + a reference fixture.
- Server-side tests proving a device-style GPX round-trips through
  `GpxExtractor` (per-point hr/cad/power, `<type>`→sport, distance, path,
  timestamps, persistence) and that the JSON create returns `201 {id,url}` /
  `422 {errors}`.
- The `format.json` navigation response on `POST /activities`.

**Deferred to the native upload work:**

- The native recorders themselves (UIKit / Jetpack Compose), on-device DB,
  permissions, recording UI, GPX serialization.
- The CSRF exemption one-liner in §4 (lands with the client that needs it).
- BLE sensors (HR/cadence/power straps) — the schema already has slots for them.

---

## 7. Superseded: the device no longer uploads

**Added with [ADR 0003](../adr/0003-the-recording-review-is-a-web-page.md).
§§1–3 stand unchanged. §§4–5 no longer describe the live path.**

The review screen is now the web `/activities/new`, prefilled by the shell over
the `recording-review` bridge component. The shell hands over structured points
and the *page* builds the GPX and submits the form, so:

- **§4 (upload contract).** The multipart `POST /activities` still happens, but
  it is an ordinary Turbo form submission from the review page — CSRF comes from
  the page's `<meta name="csrf-token">`, not from the cookie-only native request
  §4 describes. The form fields are unchanged, plus one addition:
  `activity[recording_uuid]`, an idempotency key minted at Arrêter and stored
  behind a unique index on `(user_id, recording_uuid)`. A replayed upload
  resolves to the activity already created instead of duplicating the ride.
  This is what restores §5's invariant (below).
- **§5 (navigation contract).** The `201 { id, url }` / `422 { errors }` JSON
  responses still exist and are still tested, but **no client calls them today**.
  They are kept deliberately: the deferred offline queue
  (uploading recordings made without a connection) is a native POST and
  will want this contract back, along with the CSRF exemption in
  `ActivitiesController`. The HTML path (302 → activity) is what the review page
  actually follows.
- **§5's invariant.** *"The on-device DB is the source of truth until the server
  confirms `201`"* held because one native method received the 201 and cleared
  the session on the next line. The confirmation now reaches the *page*, which
  reports it back over the bridge — so a process killed in between leaves a
  recording that would upload twice. `activity[recording_uuid]` is what makes
  that second upload harmless.

**§2 is untouched and is now enforced in one place.** `RecordingGPXEncoder.swift`
and `RecordingGpxEncoder.kt` are deleted; the sole encoder is
`app/javascript/controllers/lib/gpx_encoder.js`, pinned byte-for-byte to
`test/fixtures/files/gpx/native_recording.gpx` by
`test/system/recording_review_test.rb` — the same fixture `GpxExtractorTest`
round-trips through the server, so both halves of the contract are held to one
artifact.
