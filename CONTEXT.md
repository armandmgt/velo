# Velo

A self-hosted cycling and running activity tracker: a Rails web app, wrapped by
iOS and Android shells that can also record activities natively. French is the
product language, so each term below carries the wording the UI uses.

## Language

### Activities

**Activity**:
A completed outing owned by a user, with a sport, a GPS path and per-second data
points. The unit the web app displays and the only thing that outlives an upload.
_Avoid_: Ride, workout, session

**Data point**:
One per-second sample of an activity — position plus whatever sensors supplied
(speed, cadence, power, heart rate).
_Avoid_: Sample, fix, trackpoint

**Sport**:
What the activity was done by (road bike, gravel, trail run, …). Groups into the
cycling / running / other categories that decide whether stats read as speed or
pace.
_Avoid_: Activity type, discipline

**Durée de déplacement** (moving time):
Time spent actually moving, excluding stationary stretches — segments under
0.5 m/s don't count. The only duration an Activity stores, and the only one the
web shows.
_Avoid_: Active time, elapsed time, duration

### Ingestion

**Source file**:
The FIT or GPX file an Activity was derived from, retained so the Activity can be
re-derived later.
_Avoid_: Fit file (the name is historical — GPX files are stored under it too)

**Track**:
What a Source file yields once read: its points, its summary figures, and the
name and sport the file itself suggests. Not yet an Activity, and independent of
which format it came from — a rider's own name and sport take precedence over
the file's.
_Avoid_: Trace, route (a route is planned, not recorded), path (a path is the
stored geometry of one Activity)

**Ingestion**:
Turning a Source file into an Activity: reading it as a Track and filling in the
figures a rider didn't supply. Covers every origin — an upload, a native
recording, a Strava archive, an iGPSport sync.
_Avoid_: Import (reserved for a Strava archive and for seeding a route from
GPX), sync (reserved for iGPSport), parse (names only the reading half)

### Recording (native shells)

**Recording session**:
One recording attempt living on the phone, from Démarrer to upload or discard.
At most one is ever unfinished. Becomes an Activity only on upload; anything it
knows that the upload doesn't carry is lost at that moment.
_Avoid_: Recording, session, in-progress activity

**Handoff**:
Everything a finished recording session gives the review screen — its track, its
tours, its stats and the sport it was recorded under. Transferred once, in one
direction, when the screen opens. The review screen knows nothing about the ride
beyond its handoff, so whatever a handoff leaves out cannot be recovered later.
_Avoid_: Payload, transfer, export, dump

**Temps écoulé** (elapsed time):
Wall-clock time since the recording started, minus every paused stretch. What
the rider watches tick, and the clock that times a lap. Distinct from durée de
déplacement, which is stricter — a slow crawl adds to elapsed but not to moving.
_Avoid_: Temps, duration, total time

**Tour** (lap):
A stretch of a recording session delimited by the rider tapping Tour. Every
recorded point belongs to exactly one, numbered from 1. Never persisted
server-side: a tour reaches the review screen, but no Activity ever carries one.
_Avoid_: Lap, segment, interval

**Split**:
A tour's own numbers — its distance, its temps écoulé, and its average speed
(pace for running sports). What the lap list shows, while riding and again on the
review screen; never stored on an Activity.
_Avoid_: Lap stats, intermediate time

**Pause automatique** (auto-pause):
A pause the app enters on its own once the rider has stopped moving, and leaves
once they move again. Identical in effect to a manual pause — the clock freezes,
the distance segment breaks, incoming fixes are discarded — and differs only in
who triggered it and who may end it.
_Avoid_: Auto-stop, idle detection, smart pause

### Performance

**Best effort**:
An Activity's fastest stretch over a standard distance (or, with power, its
highest average power over a standard duration). Timed on the wall clock between
the data point where the stretch starts and the one where it ends — stops
included, as in a race. Not temps écoulé, which subtracts pauses, and not durée
de déplacement.
_Avoid_: PR (a PR is a rank a best effort earns), split, record

**Segment**:
A named, directional stretch of road or trail, created from part of an Activity
and shared by every user of the instance. Riding it in reverse is a different
segment.
_Avoid_: Section, climb, route (a route is planned and has no leaderboard)

**Segment effort**:
One pass over a segment within an Activity, timed like a best effort. One
Activity can hold several on the same segment. Private when its Activity is
private or its start or end falls in a hidden part of the map; a private effort
counts for its rider's own PRs but never on the leaderboard.
_Avoid_: Attempt, match, lap

**PR / 2nd / 3rd**:
The rank a best effort or segment effort earns against the rider's own earlier
ones, fixed when its Activity is ingested.
_Avoid_: KOM (a leaderboard title Velo doesn't award), personal best

**Effort score** (score d'effort):
An Activity's training stress — zone-weighted heart-rate time, or TSS when it
has power and the rider has an FTP. Absent when it has neither.
_Avoid_: Relative Effort, Suffer Score, load (load is the curve, not the score)

**Forme** (fitness / fatigue / form):
The rolling curves built from daily effort scores: fitness (~42-day average),
fatigue (~7-day), and form, their difference.
_Avoid_: Freshness, CTL/ATL/TSB in the UI

### Gear

**Gear**:
A bike or a pair of shoes an Activity was done with. May be the default for one
or more sports; retired gear keeps its history but is no longer offered.
_Avoid_: Equipment, kit, bike (as the general term)

**Component**:
A wearing part of a bike — chain, cassette, tire, brake pads — with an install
date and a service interval in km. Replacing it retires the old one.
_Avoid_: Part, consumable

### Map visibility

**Hidden portion**:
The part of an Activity's track that anyone but its owner cannot see — its
first and last metres along the track, anything inside the owner's address
zones, or the whole map. Stats still cover the full Activity.
_Avoid_: Privacy zone (an address zone is one way to create a hidden portion), redaction
