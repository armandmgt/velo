# Activity ingestion stops before persistence

`ActivityIngestion` turns a Source file into a populated, unsaved Activity and
stops there. It owns format dispatch, extraction and the normalisation defaults
(`start_time` / `end_time` / `active_time` / `location` fallbacks) that the two
importers used to each write for themselves. It deliberately does **not** own
deduplication, saving, or attaching the source — those stay with each caller.

## Why the seam is here and not wider

Dispatch and normalisation were duplicated for no reason: three call sites derived
the `.gpx` / `.fit` decision three different ways, and the direct-upload path
skipped the normalisation both importers applied. That is genuine duplication and
belongs behind one interface.

Persistence is different. The three callers dedupe on three incompatible rules —
Strava on `(start_time, end_time, distance)`, iGPSport on a same-day ±500 m
pre-filter *and* again on exact `start_time` after parsing, direct upload not at
all. Those rules encode three different beliefs about what "the same ride" means.
Collapsing them behind one interface would have meant picking a winner and
silently changing import behaviour inside a refactor, where a regression and an
intended change look identical in the diff.

## Consequences worth knowing

The three deduplication rules survive this refactor untouched, and so does the
duplicated `{ imported:, skipped:, failed:, errors: }` result hash in both
importers. That is deliberate, not an oversight. Unifying deduplication is worth
doing — as its own change, with its own decision about which rule is correct.

An architecture review looking at this code will suggest widening the seam to
absorb persistence. That suggestion is reasonable and was considered; it is
declined until the deduplication question is settled on its own terms.
