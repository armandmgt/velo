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

**Entering is slow, leaving is eager.** Entering auto-pause needs ten consecutive
seconds of fixes under `MOVING_SPEED_THRESHOLD` (0.5 m/s, the same threshold the
server uses for durée de déplacement), and the fixes really must be consecutive:
a hole in the stream leaves two isolated slow readings with an unobserved span
between them, so a gap wider than a few seconds restarts the run rather than
counting as stillness. A fix whose speed CoreLocation could not measure (-1)
breaks the run too — only positive evidence pauses a recording.

Leaving takes either 15 m of displacement from where we paused **or** a measured
speed of 2 m/s, whichever comes first. Displacement is the primary test because a
stationary phone reports 0.3–0.8 m/s of Doppler noise, straddling the entry
threshold, so keying the exit on *that* threshold would flap at every traffic
light. But displacement alone is not enough: a paused recording drops its fixes,
so waiting to cover 15 m silently discards the first seconds of the rider pulling
away — about 15 m of track and distance per stop, which on a city ride with 25
junctions is a few hundred metres of missing route. 2 m/s (~7 km/h) sits far above
the noise band while catching a rider within a second or two of setting off.

The asymmetry throughout is intentional: a late pause costs a few seconds of
elapsed time, a late resume loses real track.

## Consequences

GPS keeps streaming while auto-paused, since exit detection needs fixes — a long
stop still draws battery. Explicit instructions outrank the detector in both
directions: **Reprendre** while auto-paused disarms it until the rider actually
moves 15 m, and **Pause** while auto-paused converts it to a manual pause that
movement will not undo.
