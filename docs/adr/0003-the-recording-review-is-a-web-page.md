# The recording review is a web page

S13 (#66) built the review/confirm screen shown after **Arrêter** in native
UIKit, on the stated grounds that "a browser / WKWebView cannot programmatically
prefill an `<input type="file">` (hard security boundary), so the recorded GPX
could never be attached to that form." That premise is wrong. What a webview
cannot do is set a file input's *path*; it has been able to attach a
JS-constructed `File` via `new DataTransfer()` since Safari 14.1, and the iOS
deployment target is 17.0 (`native/ios/project.yml`). No missing API stood in
the way — so the review screen becomes the existing web `/activities/new`,
prefilled by the shell, and both native implementations are deleted:
`RecordingReviewViewController` on iOS (#66) and `ReviewBody` / `ReviewControls`
inside `RecordingScreen.kt` on Android (#67).

The shell hands the finished recording to that page as a **handoff** over a
bridge component, and the page performs the upload as an ordinary Turbo form
submit. The device therefore stops POSTing activities altogether:
`ActivityUploader` and `RecordingGPXEncoder` are deleted on both platforms.

Three specifics that look arbitrary from the code alone:

**The handoff carries points, not GPX.** The map, the split list and the upload
all need the same track, so sending an encoded GPX would mean sending the ride
twice in two shapes and keeping a GPX encoder in both Swift and Kotlin. Sending
structured points instead lets one JavaScript encoder serve all three, and it is
the encoder — the thing a silent bug corrupts — that is now written and tested
once rather than twice. The GPX schema it emits is still S0 §2, still proven by
`test/fixtures/files/gpx/native_recording.gpx`.

**The handoff carries precomputed stats anyway.** Deriving them in JavaScript
would be wrong, not merely wasteful: a paused recording drops its fixes, so from
the points alone nothing can distinguish a pause from a GPS dropout, and
therefore nothing can reconstruct temps écoulé. The stats travel because only the
shell can compute them.

**It travels gzipped and base64'd, in one message.** A six-hour ride at ~1 Hz is
around 21,600 points; the bridge's native→web leg inlines its JSON into an
`evaluateJavaScript` source string, and raw that is megabytes. 1 Hz GPS text
compresses roughly ten to one, which puts even the worst realistic ride in the
low hundreds of KB and removes the size cliff without a chunk-reassembly state
machine. `DecompressionStream("gzip")` covers iOS 17 WebKit and the Android
WebView.

## Considered Options

- **Keep the POST native, send only the form values up.** The web page would be
  the UI and `ActivityUploader` would still do the work, preserving the S0 §5
  invariant for free. Rejected: it keeps a native uploader on both platforms and
  makes the web form a decoy that does not submit, which is the kind of thing
  nobody remembers in a year.
- **Upload on Arrêter, then review the created activity.** Cheapest of all, and
  the `name_pending` / `awaiting_name` prompt flow already exists for it.
  Rejected: **Supprimer** would stop meaning "no activity was ever created" and
  become a server-side destroy, which is a different promise to the rider.
- **A separate route for the recording review.** Rejected in favour of one
  `/activities/new` whose review chrome renders only under `hotwire_native_app?`
  — the native branch decides which markup exists, the bridge decides what fills
  it, and the web upload form's HTML stays clean.

## Consequences

**The review screen no longer works offline**, and a ride ends where signal is
worst. When the page cannot load the shell shows a Fermer it otherwise withholds
— the happy path stays terminal, as `hidesBackButton` made it — and the recording
is left in the store. Nothing surfaces it again. That hole is not new: a
`.stopped` session is already invisible to kill recovery, which only looks for
*active* orphans, so today's "Plus tard" on an upload failure strands one the
same way. This decision promotes that edge case to the normal offline path, and
the reliability follow-up owns both halves.

**S0 §5's invariant weakens.** "The on-device DB is the source of truth until the
server confirms 201" held because one native method received the 201 and cleared
the session on the next line. The confirmation now reaches the page, which
reports it back — so a process killed in between leaves a recording that will
upload twice. A `recording_uuid` minted at Arrêter, carried as a hidden field and
unique-indexed server-side, makes the second upload resolve to the first activity
instead of a duplicate. Without it the invariant would be strictly weaker than
before, which is the whole reason the review was native in the first place.

Laps are unaffected and ADR 0001 stands: splits reach the review screen through
the handoff and are injected client-side, so the server still never receives a
tour and no Activity carries one. S0 §4–5 continue to describe a native multipart
upload that no longer happens; per ADR 0001's own advice they are superseded in
place by a new section rather than rewritten, because the fixture-proven shape is
what makes this path safe to change around.
