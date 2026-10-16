# C.L.A.S.H. HAL Air Employment Model

Status: **built; v1 and v2 run in engine on 2026-10-16, v3 not yet.** Rack
profile v4, heli attack v3, GoAttAir swapped in C.L.A.S.H. HAL Additions,
Dual-HAL Checkbook v9.

How a HAL attack helicopter flies its sortie, and how any C.L.A.S.H. layer
learns what a vehicle can actually shoot. Every number here is a placeholder
for calibration.

## 1. The problem

Run of 2026-10-15: stub-wing Ghost Hawks (`B_Heli_Transport_01_pylons_F`, the
MH-80 DAP from Game Update 2.22) sent by HAL flew tight circles 15 to 200 m from
the infantry they were sent at. They committed to a turn, pitched up hard,
doubled back, and never set up a run. Four things combined:

1. **HAL's waypoint.** `GoAttAir.sqf` gives the flight one search-and-destroy
   waypoint, radius 0, on the target's position, and waits on `RYD_Wait`. The
   sortie ends when that waypoint completes or after 120 stationary ticks.
2. **The weapon's floor.** The DAP's only weapon was DAGR-M. The AI picks a fire
   mode whose `minRange` to `maxRange` brackets the target distance; the
   DAGR-M's AI modes are Far_AI 600 to 5000 m and Medium_AI 300 to 3000 m. Its
   Burst and LoalDistance modes reach 2 m: those are kept for players. Inside
   300 m the AI has no mode to fire.
3. **The seeker.** DAGR-M locks IR and laser and has no manual control. Men give
   no IR return and nobody lases for a HAL aircraft, so it cannot be fired at
   infantry at any range.
4. **Behaviour.** Impasse sets every spawned vehicle's driver (its leader)
   CARELESS and lifts that with its own waypoints. After the Dual-HAL handoff
   Impasse's writers never run, so the CARELESS outlived the handoff.

### 1.1 What v1 and v2 taught (2026-10-16)

v1 held a search-and-destroy point on a 390 m ring with combat mode RED
("STATION"). The B side's DAP (G63):

| Time | What it did |
|---|---|
| 3:24:48 | Sortie starts: HAL's point, a vehicle; 390 m ring |
| 3:24:49 to 3:29:01 | Both ring legs end on the 120 s timeout: it never reached a station point |
| 3:27:43 to 3:27:56 | Four DAGR-M at a Rooikat from 2.7 down to 1.6 km at 265 km/h; the Rooikat (G25) dies at 3:27:56 |
| 3:28:17 to 3:29:38 | Five DAGR-M at a Panther from 342 to 685 m, at 25 to 250 km/h, 56 to 61 m up: circling it |
| 3:29:54 | Main rotor destroyed; crew survives; the crew remnant cleanup takes the group, the sortie hands back as `released` |

The run-in was right. Then search-and-destroy with RED ("engage at will")
handed movement to the AI's own engagement logic, which left the ring and
knife-fought the nearest vehicle: the same mechanism as HAL's radius-0 point.

v2 replaced the station with attack runs: straight in from 2.9 km to a 600 m
break point, then out to the next ingress point 60 degrees round. Hark's
reading in engine: good for attack helicopters with chin guns (those orbit),
but the DAP still passed over targets and flew broad, wide circles between its
two points. A fixed-weapon airframe needs to stop and point, not pass.

v3 keeps the ring for gunners and replaces runs with **point at**: detect
something, get far, point at, point at, point at, break off, detect something.
The crew pulls the trigger; the routine only turns the nose, to help it acquire.

The fix has to work with whatever rack the helicopter carries, on any modlist.
Nothing below names an airframe or a weapon.

## 2. Authority

| Who | Decides |
|---|---|
| HAL dispatcher | Which group attacks, what target, when (`Busy` set before `RYD_Spawn`) |
| HAL `GoAttAir` (C.L.A.S.H. copy) | Hands helicopter flights to the sortie; the return leg and landing, unchanged |
| `ITW_CLASH_HeliAttack.sqf` | The movement between the order and "come home": a ring, or firing positions and where the nose points |
| `ITW_CLASH_RackProfile.sqf` | Nothing: it reads what a vehicle can fire and sizes the geometry |
| The AI crew | Every shot. Nothing here fires or forces a weapon |

HAL's own sortie rules end the sortie: damage over 0.5, fuel under 0.3, 1200 s,
an empty rack (HAL counts pylons; this reads the rack), and a crippled airframe
(`canMove` false: a lost rotor can leave overall damage low). HAL fixes live
only in C.L.A.S.H. HAL Additions; NR6 HAL is never edited.

## 3. The rack profile

`ITW_CLASH_Rack_fnc_Entries` reads `magazinesAllTurrets` on the live vehicle:
one entry per weapon and seat with rounds left, merged across magazines,
`[weapon, ammo, turret, rounds, flags, bands, lock, aim]`. Countermeasures,
smoke, illumination, the laser designator and horns are skipped.

- **Weapon** for a magazine: its `pylonWeapon`, else the turret weapon whose
  `compatibleMagazines` (magazine wells included) holds it.
- **Flags:** the ammo's `aiAmmoUsageFlags` (64 infantry, 128 vehicles, 256 air,
  512 armour), parsed from a number or a text sum, **together with its
  warhead's** (`submunitionAmmo`, text or the first class of an array). The
  DAGR-M's own flags are 64 + 128 and its armour bit is on its warhead; v1 read
  the warhead only when the missile had none. If neither says anything, `hit`
  150 or more reads as vehicles and armour, otherwise as infantry and vehicles.
- **Bands:** `minRange` to `maxRange` of every fire mode across every muzzle
  that reaches 50 m or more. A weapon with none falls back to the missile's
  lock distances, then to 50 to 1500 m.
- **Lock:** MANUAL (manual control), ACE (an ACE seeker), IR_LASER, IR, LASER,
  AIR (air-to-air), NONE. Only missiles, rockets and submunition carriers
  guide; a bullet or shell is NONE whatever its config says (v4). v3 read
  `airLock` on bullets as an air-to-air seeker, so on 2026-10-16 the Pawnee's
  M134 and the Blackfoot's 20 mm did not count against infantry: on a gun,
  `airLock` only means it may shoot at aircraft.
- **Aim:** FIXED for a pylon or the pilot's seat, or a turret that traverses
  under 60 degrees; TURRET otherwise.

**Usable** against a contact type: the entry carries one of the type's bits
(infantry 64; vehicle 128; armour 512; static 128 or 64), and against infantry
its lock is NONE or MANUAL.

Per type the profile is `[usable count, ring radius, mode, standoff]`.

### 3.1 Mode

**ORBIT** if any usable weapon is on a TURRET (a gunner can shoot while the
airframe keeps moving round), else **POINT** (only the airframe can aim). The
sortie flies ORBIT if any type on its rack does.

### 3.2 Standoff (POINT)

How far out to hover and point: as far as the weapons stay effective.

- If any usable weapon is guided (lock other than NONE), the set is the guided
  ones and the cap is 2 km; otherwise all of them and the cap is 1 km
  (unguided rockets scatter past it).
- Standoff = the smallest of (cap, each weapon's reach / 1.2), but never inside
  any weapon's floor x 1.2.
- With a guided weapon aboard its distance wins; rockets and guns join in if
  they reach.

### 3.3 Ring (ORBIT)

The helicopter flies a stepped ring of radius R around the centre, 45 degrees a
step. The closest pass is mid-leg, at R x cos(step/2) (0.92 R at 45 degrees). So
a band [lo, hi] covers the whole ring when lo is at most R x cos(step/2) and R
is at most hi.

1. Candidates: for each usable band, lo / cos(step/2) x 1.2, at least 250 m,
   kept if it is within that band's hi.
2. Score each candidate by how many usable weapons have a band covering the ring.
3. Highest score wins; on a tie, the smallest ring. Clamped to 250 to 1500 m.

### 3.4 Worked

From the console reads of 2026-10-16 (the gun lines are illustrative):

| Rack | Against | Usable | Mode | Geometry | Height |
|---|---|---|---|---|---|
| DAGR-M only | Vehicles or armour | 1 | POINT | Standoff 2000 m | 150 m |
| DAGR-M only | Infantry | 0 | none | | |
| DAGR-M and DAR | Infantry | 1 (DAR) | POINT | Standoff 1000 m | 150 m |
| DAGR-M and DAR | Vehicles | 2 | POINT | Standoff 2000 m (DAGR-M's) | 150 m |
| Fixed gun pod 0 to 500 m | Vehicles | 1 | POINT | Standoff 417 m | 63 m |
| Gunner gun 0 to 1500 m and DAGR-M | Infantry | 1 | ORBIT | Ring 250 m | 50 m |

Height is 0.15 x (standoff, or ring radius), between 50 and 150 m.

### 3.5 Other readers

The supports guided pass (`ITW_CLASH_SupportsStrike.sqf` v3) reads through it:
a guided anti-armour missile is a `shotMissile` with a seeker other than NONE or
AIR and the armour bit in its flags (missile or warhead), and its weapon is
`ITW_CLASH_Rack_fnc_WeaponFor`. Strike keeps its own reader for when the profile
is missing.

## 4. The sortie

`GoAttAir` (C.L.A.S.H. copy) takes this path when the flight is all
helicopters, its leader is not a player, and both modules are loaded. Planes,
player leads and a mission without the modules run HAL's original block, line
for line. Variables the original block sets and the tail reads (`_lasT`,
`_cause`, `_timer`, `_alive`) are declared before the branch.

Both modes **arm** at every pass or position: COMBAT with
`setBehaviourStrong`, combat mode YELLOW (fire at will, keep to the route),
attack off (`enableAttack false`), TARGET and AUTOTARGET on, `limitSpeed` and
`forceSpeed` cleared, `flyInHeight` for the geometry. Both **reveal** to the
crew, each pass or position, HAL's known enemies (`RydHQ_KnEnemies`) near the
centre, at 1.5. Nothing the commander does not know.

### 4.1 ORBIT (gunners)

Unchanged from v2. Each lap re-reads the rack and picks a centre: a contact our
side has reported within 1500 m of HAL's point, uncertainty 300 m or better,
that the rack can hit (`reported`); else HAL's point if the rack can hit what
HAL named (`hal-point`); else one lap at HAL's point (`hal-point-hold`). Then
`doMove` the leader round the ring, 45 degrees a step, entering on the near
side; a step ends on arrival (150 m), a 20 s stall, or 120 s. Two laps with
nothing to hit end the sortie. Each lap logs how close it came
(`heli-attack-flown`).

### 4.2 POINT (fixed weapons)

A loop over firing positions:

1. **Detect.** Pick the centre as ORBIT does (`reported` or `hal-point`),
   reveal the commander's knowledge there, then list what the crew knows of
   within 1500 m of it that the rack can hit (`targets`, enemies only):
   - where the crew thinks each one is (`targetKnowledge`), never the true
     position;
   - a sighting older than 120 s is dropped; a target revealed but not yet
     seen by the crew itself is kept, because pointing at it is how the crew
     comes to see it;
   - ranked HAL's own target first, then armour, vehicles, statics, men, each
     nearest first.
2. **Nothing found: look.** Fly to the farthest standoff on our side of the
   centre, watch the centre, and wait up to 20 s for the crew to find
   something. Two looks with nothing, and the sortie ends (`clear` if it ever
   had a target, `nothing-to-hit` if not).
3. **Get far.** A firing position at the standoff from the best target, from
   the side the helicopter is on, trying that bearing and 30 and 60 degrees
   either side. First choice is one that sees the target over the terrain from
   the hover height (`terrainIntersectASL`). Next is one with fewest other known
   enemies within 600 m, so it is not parked over another target. Last is the
   smallest turn. It flies there and stops: a move under 1.5 km is capped at
   120 km/h, so it turns tight and stops sharp; a longer one runs at the
   airframe's own speed, like the v1 run-in that shot well. Watch and target
   are cleared before every move, so it flies where it is going.
4. **Point at, up to three times.** Each point-at takes the best target it has
   not pointed at yet from here (or the best again):
   - the pilot and any gunner `doWatch` and `doTarget` it;
   - if the nose is not within 8 degrees after 1.5 s, the **yaw assist** turns
     the airframe (4.3);
   - it is done once on target and held 8 s, or 2 s after the crew's first
     shot, or when it never comes on within 8 s;
   - out early when the target dies, the crew loses it, or the aircraft is
     hit or has a missile inbound (`Hit` and `IncomingMissile` handlers).
     A hit or missile ends the position at once.
   The crew pulls the trigger. Nothing here fires.
5. **Break off.** The next position is a hop of about 700 m to the side at the
   same standoff (a 20 degree step at 2 km, the 40 degree cap at 1 km),
   alternating sides: a zig-zag across the target's front. The hop's straight
   line never comes inside 0.9 of the standoff, so it never passes over. Then
   detect again.

### 4.3 The yaw assist

Heading only. While a helicopter hovers on a firing position (under 40 km/h,
over 5 m up) and its nose has not come round:

- every frame, one mission handler sets its yaw rate to 2 x the heading error
  in radians, capped at 0.8 rad/s (about 46 degrees a second), with
  `setAngularVelocityModelSpace` on the up axis;
- pitch and roll rates are left to the flight model, and so is the shot;
- an entry lapses 1.5 s after the point-at last renewed it, so a dead script
  cannot leave an aircraft turning;
- local aircraft only, where angular velocity is simulated.

The sign is the engine's convention. Under the right-hand rule, positive about
the up axis turns left, so a target to the right needs negative (the default,
-1). If a turn ever opens the error by more than 10 degrees within 1.5 s, the
point-at flips the sign once for every sortie after, and logs
`heli-attack-yaw-sign-flipped`.

Native first: if the AI pilot turns onto a `doTarget` for its own weapons, the
assist never engages, and `heli-attack-engage` shows `assisted false`.

### 4.4 Ends

| Reason | Means | GoAttAir |
|---|---|---|
| `rack-empty` | Nothing on the rack hits anything, from the start | Return leg |
| `winchester` | Out of everything that hits anything | Return leg |
| `clear` | Two laps or looks with nothing to hit, after having had a target | Return leg |
| `nothing-to-hit` | Two laps or looks with nothing to hit, never had one | Return leg |
| `rtb-condition` | Damage over 0.5, fuel under 0.3, or the airframe cannot move | Return leg |
| `time` | 1200 s | Return leg |
| `lost` | Group, crew or leader's vehicle gone | Not-alive exit |
| `mia` | `RydHQ_MIA` set (a CLASH release, HALUnload, HQReset) | Not-alive exit |
| `break` | `Break` set (CLASH's withdrawal) | Not-alive exit |
| `withdrawing` | `ITW_CLASH_Withdrawing` (GTFO keeps the group HAL-managed and sets only this) | Not-alive exit |
| `released` | `Busy` cleared by someone else (G63: the crew remnant cleanup) | Not-alive exit |

### 4.5 Yielding to another owner

The last five ends mean the group is no longer this sortie's to fly:

- They are checked first, before any sortie limit, every poll.
- `RydHQ_MIA` is a handshake: the waiter clears it on reading it, and the setter
  (`ITW_CLASH_fnc_BeginRelease`, HALUnload) watches for that. `RYD_Wait` does
  it, so this does too.
- Every move is checked and ordered in one unscheduled step (`isNil`), so a
  withdrawal that lands between the check and the order is not overwritten.
- The hand-back is unscheduled too, and re-checks: a sortie ending on its own
  terms that was taken since the last poll takes the foreign path. That path
  leaves the group's waypoints and attack setting alone and only cancels the
  leader's `doMove`. Neither mode places waypoints of its own any more.
- On both paths, what is ours goes: watch and target, the speed cap, the yaw
  assist and the event handlers.
- GoAttAir's not-alive exit issues no waypoint, so no return leg lands on top of
  a withdrawal's move.

### 4.6 The CARELESS handoff

Dual-HAL Checkbook v9 clears Impasse's spawn CARELESS (to AWARE, with
`setBehaviourStrong`, where the group is local) when a field or migrated vehicle
is handed to HAL and is not a transport. On 2026-10-16 it fired on every field
handoff, both sides. Checkbook-bought artillery keeps its CARELESS by decision:
it fires and scoots regardless.

## 5. Telemetry

Through `ITW_CLASH_DualHAL_fnc_Log`, so each line carries `dual-hal-` first.

| Line | Content |
|---|---|
| `CLASH BOOT \| rack-profile-ready` | Version, AI mode reach, turret span, ring bounds, margin, guided and unguided standoff caps, `modes=ORBIT,POINT warheadFlags=true` |
| `CLASH BOOT \| heli-attack-ready` | Version, retarget radius, uncertainty limit, ring step, clear passes, max time, height bounds, `modes=ORBIT,POINT`, point-ats, alignment, assist delay, hold, hop, hop speed, yaw gain, rate and sign, `crewFires=true yieldsToOwners=true` |
| `CLASHHALADD \| hal-overrides-applied` | Must list `HAL_GoAttAir` |
| `CLASHHALADD \| goattair-heli` | Group and flight classes, when a sortie takes this path |
| `rack-profile` | Once per class and loadout: up to 8 entries as [weapon, flags, bands, lock, aim, rounds], and per type [type, usable, ring radius, mode, standoff] |
| `heli-attack-start` | ORBIT: group, class, lap, source, type, HAL's target type, centre, mode, radius, height, revealed. POINT: group, class, mode, HAL's target type, HAL's point, [type, standoff] for each usable type |
| `heli-attack-pass`, `-flown` | ORBIT, each lap: as start; then closest to the centre, speed and height then, seconds, shots by weapon |
| `heli-attack-look` | POINT, nothing found: group, look count, source, centre, standoff, bearing, line of sight, whether the crew found something, seconds |
| `heli-attack-engage` | POINT, each firing position: group, position number, target class, source, standoff, distance on arrival, bearing, line of sight, other enemies near, the point-ats as [class, seconds to come on or -1, assisted, shots, alive after, why], why it left, seconds, shots by weapon |
| `heli-attack-yaw-sign-flipped` | The assist's sign learned: group, new sign, error when it began, error after |
| `heli-attack-shot` | Each missile and rocket: group, class, weapon, gunner's target class, range, height, speed |
| `heli-attack-end` | Group, reason, laps or positions, seconds, last source, last type, shots since the last line |
| `impasse-careless-cleared` | Group, vehicle class, which handoff |

## 6. Tunables

| Setting | Value |
|---|---|
| AI fire mode minimum reach | 50 m |
| Fixed turret span | under 60 degrees |
| Margin | 1.2 over a band's edge |
| Standoff caps | guided 2000 m, unguided 1000 m |
| Ring bounds, step | 250 to 1500 m, 45 degrees |
| Ring arrival, stall, leg timeout | 150 m; under 10 m moved in 20 s; 120 s |
| Retarget radius | 1500 m from HAL's point |
| Uncertainty limit for a centre | 300 m |
| Laps or looks with nothing before going home | 2 |
| Point-ats per position | 3 |
| On target, wait, hold | 8 degrees; 8 s; 8 s, or 2 s after a shot |
| Assist after | 1.5 s |
| Hop, step cap | 700 m, 40 degrees |
| Hop speed, far | 120 km/h for moves under 1500 m |
| Position arrival, slowest average | 120 m, 12 m/s |
| Look wait | 20 s |
| Sighting age | 120 s (revealed, unseen targets kept) |
| Clear radius around a firing position | 600 m |
| Yaw gain, cap, speed limit, sign | 2 per radian, 0.8 rad/s, 40 km/h, -1 |
| Sortie limits (HAL's) | Damage 0.5, fuel 0.3, 1200 s |
| Height | 0.15 x standoff or ring radius, 50 to 150 m |
| Poll | 2 s (0.5 s while pointing) |

## 7. Tradeoffs and limits

- **A hover is a target.** POINT hovers at 2 km for up to about 50 s a position
  (three point-ats of up to 16 s; less when the crew shoots).
  That is outside most vehicle MGs; AA (a Cheetah, MANPADS) still reaches it, and
  the hit and missile handlers are what get it moving. Speed protected the runs;
  distance and short dwell protect the hover.
- **The yaw assist overrides the yaw rate, not the pilot.** If the AI pilot
  wants another heading at the same time the two can fight, and the airframe
  may wobble. Native first keeps that to cases where the AI would not turn.
  Pitch is never touched, so unguided rockets still depend on the AI's own
  aim; lock-on missiles only need the nose round.
- **Pointing only helps acquisition.** The crew may still hold fire on a target
  it is pointed at; the `engage` line's shots per point-at shows how often.
- **Unguided weapons fire from far.** The AI's own bands decide when it shoots:
  DAR's Far_AI mode reaches 3200 m. The 1 km standoff limits how far out it is
  asked to point, not what the AI chooses.
- **A gunner-controlled pylon reads FIXED.** Pylons are FIXED whatever seat
  fires them. A chin-turret attack helicopter with pylons orbits (its gun is a
  TURRET), which is what plays well (Hark, 2026-10-16).
- **A seeker-only rack cannot take an infantry sortie.** By design: the DAP with
  only DAGR-M looks for vehicles near HAL's point or goes home.
- **Mod configs are trusted.** A mod whose AI modes or flags are wrong gets the
  wrong geometry, and the `rack-profile` line shows exactly why.

## 8. To verify in engine

1. `rack-profile` for the DAP: every type POINT, standoff 2000; ARMOR usable.
2. `heli-attack-engage`: distance on arrival near 2000 m, line of sight true,
   and for each point-at whether the nose came on, how fast, and whether the
   assist did it.
3. If any `engage` shows `assisted true` with the nose never coming on, or a
   `yaw-sign-flipped` line: the assist sign or gain needs a look.
4. Shots per point-at, and the targets' fate. Compare with v1's run-in: four
   DAGR-M from 2.7 to 1.6 km and a kill.
5. The zig-zag: consecutive `engage` bearings about 20 degrees apart,
   alternating, and no pass over a target (watch it, or read the arrival
   distances).
6. A hit or missile mid-position: the point-at's why is `threat` and the next
   position follows.
7. A withdrawal or release mid-sortie: `heli-attack-end` with `break`, `mia` or
   `withdrawing`, the withdrawal MOVE still on the group, and no return leg.

## 9. Deployment

The GoAttAir swap is in the addon, not the mission: refresh the `-mod` folder
for C.L.A.S.H. HAL Additions along with the mission when the addon changes.
Without it the mission still boots both modules (they read and wait) and HAL
flies its original SAD.

## 10. Implementation

| File | Owns |
|---|---|
| `ITW_CLASH_RackProfile.sqf` (v4) | Reading racks (missile and warhead flags; only missiles, rockets and carriers guide); mode; ring and standoff; the guided anti-armour test |
| `ITW_CLASH_HeliAttack.sqf` (v3) | The sortie between HAL's order and its return leg: the ring, or point at; the yaw assist |
| `CLASH HAL Additions/.../hal/GoAttAir.sqf` | HAL's GoAttAir plus the helicopter branch |
| `CLASH HAL Additions/.../functions/fnc_overrides.sqf` | `HAL_GoAttAir` among the 10 swaps |
| `ITW_CLASH_DualHALCheckbook.sqf` (v9) | Clearing Impasse's spawn CARELESS at the handoff |
| `ITW_CLASH_SupportsStrike.sqf` (v3) | Guided pass reads through the rack |
| `init.sqf` | Rack profile before Knowledge; heli attack after the supports, only if the rack is ready |
| `ITW_CLASH_DebugPreflight.sqf` | Rows for both modules |

Tests: `tests/test_rack_profile.py` (static contract; Python mirrors of the flag
union, ring sizing and standoff), `tests/test_heli_attack.py` (the GoAttAir copy
keeps every HAL line in order and adds only the branch, the tail is HAL's; no
search-and-destroy or waypoints of its own, the mode choice, detect ranking and
crew-only knowledge, firing positions, the hop geometry, the point-at and its
ends, the yaw assist's limits and sign, the hand-back, the withdrawal signals it
reads), `tests/test_handoff_careless.py`.
