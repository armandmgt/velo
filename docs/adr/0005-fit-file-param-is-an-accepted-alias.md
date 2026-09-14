# `activity[fit_file]` stays an accepted upload parameter alias

The Source file attachment is named `source_file`, and `POST /activities` accepts
the upload under either `activity[source_file]` (canonical) or
`activity[fit_file]` (alias). `source_file` wins when both are sent.

## Why

The attachment was historically called `fit_file` and has always also held GPX;
the name misled internally, which is why code sniffed filenames to work out what
it was holding. Renaming it internally was worth doing.

Renaming the *parameter* alongside it is safe in-repo. Since
[ADR 0003](0003-the-recording-review-is-a-web-page.md) the device no longer POSTs
activities at all — `ActivityUploader` and `RecordingGPXEncoder` are deleted on
both platforms, and a recording is uploaded by the ordinary web form at
`/activities/new`. That form's file input is bound by Stimulus target
(`bridge--recording-review-target="file"`), not by field name, so the recording
review keeps working across the rename without touching the bridge.

What is *not* safe is assuming every install has moved. A build predating ADR
0003 still carries the native uploader and still POSTs `activity[fit_file]`.
Users update mobile apps on their own schedule, or never, and the server cannot
tell which build a request came from. Two permitted keys cost less than a broken
upload on somebody's phone.

## Considered and rejected

- **Rename the parameter outright.** Correct for every client in this repo, and
  wrong for the ones already installed. Rejected on that alone.
- **Keep the attachment named `fit_file` too.** Leaves the misleading name in
  place internally, which is the thing that caused filename sniffing.

## Consequences

`activity_params` permits both keys. S0 §4's field table documents both, though
that section already describes a native multipart upload that ADR 0003 retired —
it stands as the fixture-proven shape of the GPX itself, not as a live contract.

Unlike the situation this alias was first written for, its removal condition is
now knowable in principle: once no pre-ADR-0003 build is in use, the alias is
dead weight. Nothing in the server detects that today, so it stays until someone
establishes it out of band.
