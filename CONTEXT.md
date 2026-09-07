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

### Recording (native shells)

**Recording session**:
One recording attempt living on the phone, from Démarrer to upload or discard.
At most one is ever unfinished. Becomes an Activity only on upload; anything it
knows that the upload doesn't carry is lost at that moment.
_Avoid_: Recording, session, in-progress activity

**Temps écoulé** (elapsed time):
Wall-clock time since the recording started, minus every paused stretch. What
the rider watches tick, and the clock that times a lap. Distinct from durée de
déplacement, which is stricter — a slow crawl adds to elapsed but not to moving.
_Avoid_: Temps, duration, total time

**Tour** (lap):
A stretch of a recording session delimited by the rider tapping Tour. Every
recorded point belongs to exactly one, numbered from 1. Device-local: laps are
not uploaded and never appear on an Activity.
_Avoid_: Lap, segment, interval

**Split**:
A tour's own numbers — its distance, its temps écoulé, and its average speed
(pace for running sports). What the lap list shows; not stored on an Activity.
_Avoid_: Lap stats, intermediate time

**Pause automatique** (auto-pause):
A pause the app enters on its own once the rider has stopped moving, and leaves
once they move again. Identical in effect to a manual pause — the clock freezes,
the distance segment breaks, incoming fixes are discarded — and differs only in
who triggered it and who may end it.
_Avoid_: Auto-stop, idle detection, smart pause
