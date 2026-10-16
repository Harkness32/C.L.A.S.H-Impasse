# C.L.A.S.H. HAL Air Employment Model

Status: **built, not yet run in engine.** Rack profile v1, heli attack v1,
GoAttAir swapped in C.L.A.S.H. HAL Additions, Dual-HAL Checkbook v9.

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
   infantry at any range. Its own `aiAmmoUsageFlags` (`"128 + 64"`) say
   infantry; the seeker says otherwise.
4. **Behaviour.** Impasse sets every spawned vehicle's driver (its leader)
   CARELESS and lifts that with its own waypoints. After the Dual-HAL handoff
   Impasse's writers never run, and HAL only sets behaviour through a waypoint,
   so the CARELESS outlived the handoff (G113 flew a whole SAD CARELESS/YELLOW).

Moving HAL's point outward alone does not work: search-and-destroy completes
once the group sees no enemy near its point, and completion ends HAL's sortie,
so helicopters would go home early. A rocket loadout alone does not either: DAR
has a 400 m AI floor, so a radius-0 point still holds it inside its band.

The fix has to work with whatever rack the helicopter carries, on any modlist.
Nothing below names an airframe or a weapon.

## 2. Authority

| Who | Decides |
|---|---|
| HAL dispatcher | Which group attacks, what target, when (`Busy` set before `RYD_Spawn`) |
| HAL `GoAttAir` (C.L.A.S.H. copy) | Hands helicopter flights to the orbit; the return leg and landing, unchanged |
| `ITW_CLASH_HeliAttack.sqf` | The movement between the order and "come home": centre, ring, legs |
| `ITW_CLASH_RackProfile.sqf` | Nothing: it reads what a vehicle can fire |
| The AI crew | Every shot. Nothing here fires, aims or forces a weapon |

HAL's own sortie rules end the orbit: damage over 0.5, fuel under 0.3, 1200 s,
and an empty rack (HAL counts pylons; this reads the rack). HAL fixes live only
in C.L.A.S.H. HAL Additions; NR6 HAL is never edited.

## 3. The rack profile

`ITW_CLASH_Rack_fnc_Entries` reads `magazinesAllTurrets` on the live vehicle:
one entry per weapon and seat with rounds left, merged across magazines,
`[weapon, ammo, turret, rounds, flags, bands, lock, aim]`. Countermeasures,
smoke, illumination, the laser designator and horns are skipped.

- **Weapon** for a magazine: its `pylonWeapon`, else the turret weapon whose
  `compatibleMagazines` (magazine wells included) holds it.
- **Flags:** the ammo's `aiAmmoUsageFlags` (64 infantry, 128 vehicles, 256 air,
  512 armour), parsed from a number or a text sum. If the ammo has none, its
  `submunitionAmmo`'s; if neither, `hit` 150 or more reads as vehicles and
  armour, otherwise splash reads as infantry and vehicles.
- **Bands:** `minRange` to `maxRange` of every fire mode across every muzzle
  that reaches 50 m or more. A weapon with none falls back to the missile's
  lock distances, then to 50 to 1500 m.
- **Lock:** MANUAL (manual control), ACE (an ACE seeker), IR_LASER, IR, LASER,
  AIR (air-to-air), NONE.
- **Aim:** FIXED for a pylon or the pilot's seat, or a turret that traverses
  under 60 degrees; TURRET otherwise.

**Usable** against a contact type: the entry carries one of the type's bits
(infantry 64; vehicle 128; armour 512; static 128 or 64), and against infantry
its lock is NONE or MANUAL.

### 3.1 Sizing the ring

The helicopter flies a stepped ring of radius R around the centre, 45 degrees a
step. The target sits abeam on each leg; the closest pass is mid-leg, at
R x cos(step/2) (0.92 R at 45 degrees). So a band [lo, hi] covers the whole
ring when lo is at most R x cos(step/2) and R is at most hi.

1. Candidates: for each usable band, lo / cos(step/2) x 1.2, at least 250 m,
   kept if it is within that band's hi.
2. Score each candidate by how many usable weapons have a band covering the ring.
3. Highest score wins; on a tie, the smallest ring. Clamped to 250 to 1500 m.
4. **ORBIT** if any usable weapon is on a TURRET (a gunner can shoot while the
   airframe keeps moving), else **STATION** (only the airframe can aim, so it
   needs to hold and point).

Worked, from the console reads of 2026-10-16 (the gunner line is illustrative):

| Rack | Against | Usable | Ring | Closest pass | Mode | Height |
|---|---|---|---|---|---|---|
| DAGR-M only | Vehicles | 1 | 390 m | 360 m | STATION | 58 m |
| DAGR-M only | Infantry | 0 | none | | | |
| DAGR-M and DAR | Infantry | 1 (DAR) | 520 m | 480 m | STATION | 78 m |
| DAGR-M and DAR | Vehicles | 2 | 520 m | 480 m | STATION | 78 m |
| Gunner gun 0 to 1500 m and DAGR-M | Infantry | 1 | 250 m | 231 m | ORBIT | 50 m |
| Gunner gun 0 to 1500 m and DAGR-M | Vehicles | 2 | 390 m | 360 m | ORBIT | 58 m |

Height over the ring is 0.15 R, between 50 and 150 m.

### 3.2 Other readers

The supports guided pass (`ITW_CLASH_SupportsStrike.sqf` v3) reads through it:
a guided anti-armour missile is a `shotMissile` with a seeker other than NONE or
AIR and the armour bit on the missile or its warhead, and its weapon is
`ITW_CLASH_Rack_fnc_WeaponFor`. Strike keeps its own reader for when the profile
is missing.

## 4. The sortie

`GoAttAir` (C.L.A.S.H. copy) takes the orbit when the flight is all
helicopters, its leader is not a player, and both modules are loaded. Planes,
player leads and a mission without the modules run HAL's original block, line
for line. Variables the original block sets and the tail reads (`_lasT`,
`_cause`, `_timer`, `_alive`) are declared before the branch.

`ITW_CLASH_HeliAttack_fnc_Fly`, after ALiVE's CAS state machine
(`sup_combatsupport` cas.fsm, GPL; the pattern, not its code):

1. **Profile.** Nothing usable against anything: end `rack-empty` at once.
2. **Each lap**, re-read the rack (nothing left: `winchester`) and pick a centre:
   - a contact our side has reported (`ITW_CLASH_Knowledge_fnc_Contacts`) within
     1500 m of HAL's point, uncertainty 300 m or better, that the rack can hit;
     lowest distance plus uncertainty wins (`reported`);
   - else HAL's own point, if the rack can hit what HAL named (`hal-point`);
   - else nothing. On the first lap that means holding one lap at HAL's point on
     whatever ring the rack has (`hal-point-hold`). Two empty laps in a row end
     the sortie: `clear` if it ever had a target, `nothing-to-hit` if not.
3. **Arm** every lap: COMBAT and RED with `setBehaviourStrong`, attack enabled,
   TARGET and AUTOTARGET on, `limitSpeed` and `forceSpeed` cleared (a lift's stay
   low or hot drop can leave them), `flyInHeight` for the ring.
4. **Enter** on the side the flight is already on, then step 45 degrees a leg:
   - ORBIT: `doMove` the leader to the next ring point;
   - STATION: one named search-and-destroy waypoint (COMBAT, RED, completion
     100 m) on the ring point, held 40 s once there.
   A leg ends on arrival (150 m), a 20 s stall (as ALiVE's `unitReadyRemote`),
   or 120 s.
5. **Reveal** to the crew, each leg, HAL's known enemies (`RydHQ_KnEnemies`)
   inside the ring plus 300 m, at 1.5. Nothing the commander does not know.
6. **Hand back:** remove the shot watchers, clear its waypoints, `doFollow`.
   HAL's return leg runs next.

What it deliberately does not take from ALiVE: ground-truth reveal of every
enemy in the radius, forcing CARELESS on ingress, zeroing the other weapons with
`setAmmo`, and `waitUntil aimedAtTarget > 0.8` with no timeout (the value is
effectively binary and the wait can hang), then `fireAtTarget`. Here the crew
fights with the real knowledge picture and its own targeting.

### 4.1 Ends

| Reason | Means | GoAttAir |
|---|---|---|
| `rack-empty` | Nothing on the rack hits anything, from the start | Return leg |
| `winchester` | Out of everything that hits anything | Return leg |
| `clear` | Two laps with nothing to hit, after having had a target | Return leg |
| `nothing-to-hit` | Two laps with nothing to hit, never had one | Return leg |
| `rtb-condition` | Damage over 0.5 or fuel under 0.3 | Return leg |
| `time` | 1200 s | Return leg |
| `lost` | Group, crew or leader's vehicle gone | Not-alive exit |
| `mia` | `RydHQ_MIA` set (a CLASH release, HALUnload, HQReset) | Not-alive exit |
| `break` | `Break` set (CLASH's withdrawal) | Not-alive exit |
| `withdrawing` | `ITW_CLASH_Withdrawing` (GTFO keeps the group HAL-managed and sets only this) | Not-alive exit |
| `released` | `Busy` cleared by someone else | Not-alive exit |

**Retarget, then go home.** When the rack cannot hit what HAL sent it at (the
DAP's DAGR-M against infantry), the sortie looks for a reported contact it can
hit nearby; failing that it holds one lap at HAL's point and goes home. It never
loiters on a target it cannot shoot.

### 4.2 Yielding to another owner

The last five ends mean the group is no longer this sortie's to fly:

- They are checked first, before any sortie limit, every 2 s poll.
- `RydHQ_MIA` is a handshake: the waiter clears it on reading it, and the setter
  (`ITW_CLASH_fnc_BeginRelease`, HALUnload) watches for that. `RYD_Wait` does
  it, so this does too.
- Each leg checks and gives its order in one unscheduled step (`isNil`), so a
  withdrawal that lands between the check and the order is not overwritten.
- The hand-back is unscheduled too, and re-checks: a sortie ending on its own
  terms that was taken since the last poll takes the foreign path. That path
  deletes only waypoints named `clash-heli-attack` and cancels the leader's
  `doMove` only in ORBIT; the new owner's orders stand.
- GoAttAir's not-alive exit issues no waypoint, so no return leg lands on top of
  a withdrawal's move.

Who can take an attack helicopter mid-sortie: CLASH's own withdrawal
(`ITW_CLASH_fnc_StartWithdrawal`: Break, a release with MIA, Busy cleared, then
`ITW_CLASH_fnc_OrderWithdrawal`'s MOVE) for an enemy-managed group HAL lists as
exhausted, and GTFO's (Withdrawing, then the MOVE). Friendly-managed vehicle
crews are excluded from withdrawal candidacy.

### 4.3 The CARELESS handoff

Dual-HAL Checkbook v9 clears Impasse's spawn CARELESS (to AWARE, with
`setBehaviourStrong`, where the group is local) when a field or migrated vehicle
is handed to HAL and is not a transport. Combat mode is left alone. A Checkbook
transport keeps its own doctrine. The orbit arms COMBAT/RED itself each lap, so
it does not depend on this; HAL's other vehicle orders do.

## 5. Telemetry

Through `ITW_CLASH_DualHAL_fnc_Log`, so each line carries `dual-hal-` first.

| Line | Content |
|---|---|
| `CLASH BOOT \| rack-profile-ready` | Version, AI mode reach, turret span, ring bounds, margin |
| `CLASH BOOT \| heli-attack-ready` | Version, retarget radius, uncertainty limit, step, dwell, leg timeout, clear laps, max time, height bounds, modes, `yieldsToOwners=true` |
| `CLASHHALADD \| hal-overrides-applied` | Must list `HAL_GoAttAir` |
| `CLASHHALADD \| goattair-heli` | Group and flight classes, when a sortie takes the orbit |
| `rack-profile` | Once per class and loadout: up to 8 entries as [weapon, flags, bands, lock, aim, rounds], and per type [type, usable, radius, mode] |
| `heli-attack-start`, `-lap` | Group, class, lap, centre source, contact type, centre, radius, mode, height, revealed count, shots by weapon since the last lap |
| `heli-attack-shot` | Each missile and rocket: group, class, weapon, gunner's target class, range, height, speed |
| `heli-attack-end` | Group, reason, laps, seconds, last source, last type |
| `impasse-careless-cleared` | Group, vehicle class, which handoff |

## 6. Tunables

| Setting | Value |
|---|---|
| AI fire mode minimum reach | 50 m |
| Fixed turret span | under 60 degrees |
| Ring margin, bounds | 1.2 over the band's inner edge; 250 to 1500 m |
| Step | 45 degrees |
| Retarget radius | 1500 m from HAL's point |
| Uncertainty limit for a centre | 300 m |
| Arrival, stall, leg timeout | 150 m; under 10 m moved in 20 s; 120 s |
| Station hold | 40 s |
| Laps with nothing before going home | 2 |
| Sortie limits (HAL's) | Damage 0.5, fuel 0.3, 1200 s |
| Height | 0.15 R, 50 to 150 m |
| Reveal | `RydHQ_KnEnemies` within R + 300 m, at 1.5 |
| Poll | 2 s |

## 7. Tradeoffs and limits

- **A gunner-controlled pylon reads FIXED.** Pylons are FIXED whatever seat
  fires them, so a Hellfire on a gunner's seat gives STATION, the more
  conservative stand-off. Correct for rockets and bombs; costs some tempo for
  gunner-guided missiles.
- **A seeker-only rack cannot take an infantry sortie.** By design: the DAP with
  only DAGR-M retargets to vehicles or goes home. HAL will keep sending it at
  infantry; the RPT will show `nothing-to-hit` until the loadout or HAL's
  choice changes.
- **STATION holds a SAD point on the ring.** SAD lets the crew manoeuvre to
  engage, and it may close inside the ring while it does. The 40 s hold and the
  next leg pull it back out.
- **Ring size counts weapons, not damage.** A ring covering two weak weapons
  beats one covering a single strong one. Good enough to keep every weapon out
  of its floor; not a weapon-effect model.
- **Mod configs are trusted.** A mod whose AI modes or flags are wrong gets a
  wrong ring, and the `rack-profile` line shows exactly why.
- **The unarmed Ghost Hawk** is seeded Air-only in HAL's curated lists, so
  autofill skips it for cargo. Separate issue, not changed here.

## 8. To verify in engine

1. `hal-overrides-applied` lists `HAL_GoAttAir`, and each helicopter sortie logs
   `goattair-heli` then `heli-attack-start`.
2. The `rack-profile` line for every armed helicopter on the modlist: bands
   without the 0 to 2 m modes, seekers marked, rings that look sane.
3. Does the DAP with DAGR-M fire on vehicles from a 390 m station, and with DAR
   on infantry from 520 m? Read `heli-attack-shot` ranges against the bands.
4. Does STATION actually make a fixed-weapon helicopter point and shoot, or does
   it still circle the SAD point? If it circles, the next step is a `doWatch` on
   the centre during the hold.
5. A withdrawal or release mid-sortie: `heli-attack-end` with `break`, `mia` or
   `withdrawing`, the withdrawal MOVE still on the group, and no return leg.
6. `impasse-careless-cleared` for vehicles at handoff, and no HAL vehicle group
   still CARELESS after it.

## 9. Deployment

The GoAttAir swap is in the addon, not the mission: refresh the `-mod` folder
for C.L.A.S.H. HAL Additions along with the mission. Without it the mission
still boots both modules (they read and wait) and HAL flies its original SAD.

## 10. Implementation

| File | Owns |
|---|---|
| `ITW_CLASH_RackProfile.sqf` (v1) | Reading racks; ring size and mode; the guided anti-armour test |
| `ITW_CLASH_HeliAttack.sqf` (v1) | The sortie between HAL's order and its return leg |
| `CLASH HAL Additions/.../hal/GoAttAir.sqf` | HAL's GoAttAir plus the helicopter branch |
| `CLASH HAL Additions/.../functions/fnc_overrides.sqf` | `HAL_GoAttAir` among the 10 swaps |
| `ITW_CLASH_DualHALCheckbook.sqf` (v9) | Clearing Impasse's spawn CARELESS at the handoff |
| `ITW_CLASH_SupportsStrike.sqf` (v3) | Guided pass reads through the rack |
| `init.sqf` | Rack profile before Knowledge; heli attack after the supports, only if the rack is ready |
| `ITW_CLASH_DebugPreflight.sqf` | Rows for both modules |

Tests: `tests/test_rack_profile.py` (static contract and a Python mirror of the
ring sizing), `tests/test_heli_attack.py` (the GoAttAir copy keeps every HAL line
in order and adds only the branch, the tail is HAL's, the sortie's stops and
yielding, the withdrawal signals it reads), `tests/test_handoff_careless.py`.
