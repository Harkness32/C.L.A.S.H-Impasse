# C.L.A.S.H. — Air Threat Overlay (v1)

An optional **read-only ACE self-interaction** for pilots and anyone using the
mission map. It does not modify HAL, COLOSSUS, Thunder Run, corridor gates,
economy, or aircraft assignments.

## Operation

ACE Self Actions → **Show AirThreats** (becomes **Hide AirThreats** while on).
Default: OFF, per client. Markers are local to that client.

- Translucent red ellipse: a recently perceived ground AA position and an
  intentionally conservative estimated reach.
- Hatched red ellipse, **LAST KNOWN**: intelligence older than 120 seconds.
- Icon text includes category and approximate displayed radius in km.
- Marker circles do **not** account for terrain, missile energy, altitude,
  countermeasures, radar horizon or engagement geometry. Space outside a circle
  is **not guaranteed safe**.

## Intelligence and security boundary

On the server, candidates come exclusively from HAL's
`RydHQ_KnEnemies` and AirPicture's existing remembered denial identities.
Their live coordinates are never used. The overlay requires a friendly
observer's `knowsAbout` and `targetKnowledge` position/time, with a
maximum 180-second observation age to refresh the cached position. No
`getPosATL` on an enemy target.

The server maintains per-side snapshots and sends only sanitized arrays to
players whose current side matches the HQ. Clients may neither ask the server
to reveal enemies nor read object references from the reports. The client
accepts network reports only from the server.

The last perceived position persists for 600s (mobile) or 1200s (static).
It is NOT erased merely because the server learns a hull died; that would
leak unobserved kills. The marker naturally expires. Reports are best-effort;
a known AA unit without usable perceived position is intentionally not drawn.

## Weapon envelope

For each HAL-known ground contact, inspect its loaded turret/infantry magazines,
their `CfgAmmo`, and matching `CfgWeapons` firing modes.

- Select the **maximum** plausible AA ammunition/weapon range, not the
  platform's nominal class-based umbrella.
- Values consulted: `missileLockMaxDistance`, `maxRange`, plus
  `maxControlRange` only if the first values are implausibly short.
- For guided ammo with missing or suspicious range configuration, use
  conservative baselines of 8 km or 12 km (radar).
- If HAL explicitly classified the group as `RydHQ_AAthreat`, allow
  newer sensor-based AA without legacy `airLock` flags, and use the same
  conservative unknown-AA fallback if the ammunition data cannot be read.
- Increase by a 25% planning margin and add the observer's uncertainty radius.
  Cap rendering at 60 km against broken or absurd configuration values.
- Never use `maxSpeed * timeToLive` as effective engagement range.

The overlays are **advisory**, not exact kinematic intercept envelopes.
They are specifically meant to avoid an 8 km SAM being represented by an
arbitrary 2 km generic circle.

## Configuration

Mission namespace settings (set before module initialization):

- `ITW_CLASH_AirThreatOverlayPoll`: server scan interval, default 15 s.
- `ITW_CLASH_AirThreatOverlayMobileMemory`: default 600 s.
- `ITW_CLASH_AirThreatOverlayStaticMemory`: default 1200 s.
- `ITW_CLASH_AirThreatOverlayMargin`: default 1.25.

The server portion boots after AirPicture in `init.sqf`. The client portion
boots independently and waits for ACE to provide its interaction functions.
If AirPicture's APIs are absent, the overlay fails open without changing HAL.

## Acceptance tests to run in Arma 3

1. Start with **no discovered AA**. Toggle ON. Map contains no AA circles.
2. Spot a short-range AA gun. Circle appears at the observer's *reported*
   position and has a plausible radius.
3. Spot a missile-armed SAM whose reach exceeds 8 km. The radius must reflect
   its actual configured missiles or conservative fallback — not 1–3.5 km.
4. Drive a spotted mobile AA behind cover. The circle stays at last-known
   position and becomes hatched. It must not follow the hidden vehicle.
5. Destroy the AA without the observing side knowing. Its old warning should
   persist until stale or until a future intelligence policy explicitly
   establishes confirmed destruction.
6. Multiplayer: two opposing players, each sees only their own side's reports;
   one player's toggle must not affect the other. Repeat after respawn.
7. Verify standard C.L.A.S.H. and HAL tasking, helicopter routing, and ETB
   purchase logs remain unchanged when toggling or disabling the overlay.

Source-level checks live in `tests/test_air_threat_overlay.py`.
They do **not** replace Arma 3 or modpack runtime testing.
