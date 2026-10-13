# Commander supports, phase 0: two air picture corridor fixes

Commander supports (UAV, airstrike, carpet, airborne) all fly through the air
picture's corridor check. Two defects in that check would have made every
support worse, and both already affect today's HAL lifts, hot drops and
Thunder Runs. This change fixes them and nothing else. No support exists yet.

`ITW_CLASH_AirPicture.sqf` is now version 4.

## 1. Air-loss closures are per side

**Before.** The loss counter was one list for the whole map. Losses stored
position, time, class and weight, but not whose aircraft it was, and
`fnc_LossClosed` took only a position. A BLUFOR helicopter downed by an OPFOR
SAM counted towards closing that area for OPFOR's own lifts too: the side whose
air defence was working got grounded by its own success. A UAV flown into
defended airspace on purpose would have made this routine.

**Now.**

- `fnc_OnKill` works out the losing side with the new `fnc_LossSide`: the side
  of the dead commander's group (a dead man reports civilian, his group still
  has the real side when the kill event fires), falling back to the airframe's
  config side, else `sideUnknown`.
- `fnc_RecordLoss` stores the side at index 4 (weight stays at index 3).
- A trip only weighs losses of the same side. A closed area stores its side at
  index 3, and a re-trip only refreshes that side's area.
- `fnc_LossClosed [position, side]` only returns true for that side's areas.
  `fnc_ClassifyCorridor` passes `side _hq`.
- Fallbacks keep the old behaviour where there is no answer: an area whose
  losses could not be attributed (`sideUnknown`) closes for everyone, and a
  caller that passes no side sees every area. No caller does that today; a test
  enforces it.

## 2. Fighter denial uses the hard-kill tier

**Before.** The helicopter doctrine on `fnc_ThreatTier` says only a fixed-wing
aircraft with four or more air-to-air missiles (HARD_KILL) closes a corridor,
and a CAS jet with a self-defence pair is TOLERATED, fought rather than routed
around. The hard-kill memory (`fnc_DenialKind`) already followed it.
`fnc_ClassifyCorridor` did not: it denied any route within the 6000 m fighter
envelope of any enemy plane carrying any air-to-air missile (`fnc_IsFighter`).
So every enemy CAS jet with a pair closed every HAL lift, hot drop and Thunder
Run route near it for as long as it stayed in the picture.

**Now.**

- New `fnc_DeniesAirspace [veh, rule]`, fixed-wing only.
  - `HARD_KILL` (default): `fnc_ThreatTier` says HARD_KILL.
  - `ANY_AA_MISSILE`: `fnc_IsFighter`, the old rule.
- `fnc_ClassifyCorridor` takes an optional fourth argument, the fighter rule,
  defaulting to `HARD_KILL`.
- The four helicopter callers (cargo dice, Thunder Run air tiers, hot drop,
  HAL unload) pass nothing and get the doctrine.
- ThreatCoverage's provider choice passes `ANY_AA_MISSILE` explicitly. It is
  deciding whether to send a CAS aircraft, where a jet with a pair is still a
  real risk to ours, so its fighter behaviour is unchanged. It does get the
  per-side loss closures.
- `fnc_IsFighter` itself is unchanged; ThreatCoverage still counts our own CAP
  with it.

## What a run should show

- Boot: `air-picture-ready | version=4 ... lossClosuresPerSide=true
  corridorFighterRule=HARD_KILL casFighterRule=ANY_AA_MISSILE`.
- `air-loss`, `loss-below-threshold` and `loss-area-closed` end with the losing
  side (`WEST`, `EAST`, `GUER`, or `UNKNOWN`).
- `recent-losses` refusals for a side only near that side's own losses. An
  `UNKNOWN` on a loss line means the side could not be read and is worth
  reporting.
- `enemy-fighter-corridor` on lifts only with a 4+ missile fighter on the route.
  Expect more lifts and Thunder Runs to fly while enemy CAS jets are about,
  which is the doctrine working, not a regression.

## Not changed

- Loss weights, threshold, radius, window and closure time.
- The denial reason strings (`enemy-fighter-corridor`, `recent-losses`).
- HAL source.

Tests: `tests/test_air_picture_side_losses.py` (in CI). Two pins in
`tests/test_air_picture.py` updated for the new call shape.
