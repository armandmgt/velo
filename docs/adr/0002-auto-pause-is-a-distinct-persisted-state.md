# Pause automatique is a distinct persisted state

Auto-pause does exactly what a manual pause does — freezes temps écoulé, breaks
the distance segment, discards incoming fixes — and differs only in who triggered
it and who is allowed to end it. That difference has to survive a process kill,
because S5/S10 restore an interrupted recording from disk and the restored
recording must know whether to watch for movement or wait for the user. So it is
persisted as a fourth recording state rather than a transient flag layered over
`PAUSED`.

Two specifics that look arbitrary from the code alone:

**The new state is appended at ordinal 3, after `STOPPED`.** Android's
`RecordingState.fromOrdinal` is `entries[value]`, and the iOS Core Data `state`
is the same `Int16` by deliberate design, so inserting the new case next to
`PAUSED` would renumber `STOPPED`, invalidate stored rows on both platforms and
break the cross-platform ordinal alignment the entities are documented to keep.

**Resume triggers on displacement, not on speed.** Entering auto-pause needs ten
consecutive seconds of fixes under `MOVING_SPEED_THRESHOLD` (0.5 m/s, the same
threshold the server uses for durée de déplacement); leaving it needs one fix
more than 15 m from the position where we paused. A stationary phone reports
0.3–0.8 m/s of Doppler noise, straddling that very threshold, so a speed-based
exit flaps at every traffic light. The asymmetry is intentional: a late pause
costs a few seconds of elapsed time, a late resume loses real track.

## Consequences

GPS keeps streaming while auto-paused, since exit detection needs fixes — a long
stop still draws battery. Explicit instructions outrank the detector in both
directions: **Reprendre** while auto-paused disarms it until the rider actually
moves 15 m, and **Pause** while auto-paused converts it to a manual pause that
movement will not undo.
