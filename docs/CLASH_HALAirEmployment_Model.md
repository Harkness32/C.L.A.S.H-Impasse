# C.L.A.S.H. HAL Air Employment Model

Status: **built; v1 run in engine on 2026-10-16, v2 not yet.** Rack profile
v2, heli attack v2, GoAttAir swapped in C.L.A.S.H. HAL Additions, Dual-HAL
Checkbook v9.

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

### 1.1 What v1 taught (run of 2026-10-16)

v1 held a search-and-destroy point on a 390 m ring with combat mode RED
("STATION"). The B side's DAP (G63):

| Time | What it did |
|---|---|
| 3:24:48 | Sortie starts: HAL's point, a vehicle; 390 m ring |
| 3:24:49 to 3:29:01 | Both ring legs end on the 120 s timeout: it never reached a station point |
| 3:27:43 to 3:27:56 | Four DAGR-M at a Rooikat from 2.7 down to 1.6 km at 265 km/h; the Rooikat (G25) dies at 3:27:56 |
| 3:28:17 to 3:29:38 | Five DAGR-M at a Panther from 342 to 685 m, at 25 to 250 km/h, 56 to 61 m up: circling it |
| 3:29:54 | Main rotor destroyed; crew survives; the crew remnant cleanup takes the group, the sortie hands back as `released` |

The run-in was exactly right: a straight line at speed, targets entering the
forward arc at long range, fire-and-forget. Then search-and-destroy with RED
("engage at will") handed movement to the AI's own engagement logic, which left
the ring and knife-fought the nearest vehicle. That is the same mechanism as
HAL's radius-0 point; moving the point 390 m out changed nothing once the
helicopter was in contact. v2 repeats the run-in instead.

The fix has to work with whatever rack the helicopter carries, on any modlist.
Nothing below names an airframe or a weapon.

## 2. Authority

| Who | Decides |
|---|---|
| HAL dispatcher | Which group attacks, what target, when (`Busy` set before `RYD_Spawn`) |
| HAL `GoAttAir` (C.L.A.S.H. copy) | Hands helicopter flights to the sortie; the return leg and landing, unchanged |
| `ITW_CLASH_HeliAttack.sqf` | The movement between the order and "come home": centre, runs or ring |
| `ITW_CLASH_RackProfile.sqf` | Nothing: it reads what a vehicle can fire and sizes the geometry |
| The AI crew | Every shot. Nothing here fires, aims or forces a weapon |

HAL's own sortie rules end the sortie: damage over 0.5, fuel under 0.3, 1200 s,
and an empty rack (HAL counts pylons; this reads the rack). v2 adds a crippled
airframe (`canMove` false): a lost rotor can leave overall damage low. HAL fixes
live only in C.L.A.S.H. HAL Additions; NR6 HAL is never edited.

## 3. The rack profile

`ITW_CLASH_Rack_fnc_Entries` reads `magazinesAllTurrets` on the live vehicle:
one entry per weapon and seat with rounds left, merged across magazines,
`[weapon, ammo, turret, rounds, flags, bands, lock, aim]`. Countermeasures,
smoke, illumination, the laser designator and horns are skipped.

- **Weapon** for a magazine: its `pylonWeapon`, else the turret weapon whose
  `compatibleMagazines` (magazine wells included) holds it.
- **Flags:** the ammo's `aiAmmoUsageFlags` (64 infantry, 128 vehicles, 256 air,
  512 armour), parsed from a number or a text sum, **together with its
  warhead's** (`submunitionAmmo`, text or the first class of an array). v1 read
  the warhead only when the missile had none: the DAGR-M's own flags are 64 +
  128 and its armour bit is on its warhead, so v1 profiled the DAP ARMOR 0 while
  the AI fired DAGR-M at a Panther. If neither says anything, `hit` 150 or more
  reads as vehicles and armour, otherwise as infantry and vehicles.
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

### 3.1 Mode

**ORBIT** if any usable weapon is on a TURRET (a gunner can shoot while the
airframe keeps moving round), else **RUN** (only the airframe can aim, so it has
to fly at the target).

### 3.2 Sizing a run

Per weapon, its floor is its lowest band edge and its reach its highest.

- **Break** (the closest the run comes): the highest floor x 1.2, at least
  600 m, but never more than the shortest reach / 1.2, so the shortest-reaching
  weapon can still fire before the break.
- **Ingress** (where a run starts): the farthest reach, capped at 2500 m, plus a
  400 m lead-in to line up; at most 3000 m; always at least break + 400 m.

### 3.3 Sizing a ring (ORBIT)

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
| DAGR-M only | Vehicles or armour | 1 | RUN | In from 2900 m, break 600 m | 90 m |
| DAGR-M only | Infantry | 0 | none | | |
| DAGR-M and DAR | Infantry | 1 (DAR) | RUN | In from 2900 m, break 600 m | 90 m |
| DAGR-M and DAR | Vehicles | 2 | RUN | In from 2900 m, break 600 m | 90 m |
| Fixed gun pod 0 to 500 m and DAGR-M | Vehicles | 2 | RUN | In from 2900 m, break 417 m | 63 m |
| Gunner gun 0 to 1500 m and DAGR-M | Infantry | 1 | ORBIT | Ring 250 m | 50 m |

Height is 0.15 x (break, or ring radius), between 50 and 150 m.

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

`ITW_CLASH_HeliAttack_fnc_Fly` flies **passes**: a run (RUN) or a lap of the
ring (ORBIT).

1. **Profile.** Nothing usable against anything: end `rack-empty` at once.
2. **Each pass**, re-read the rack (nothing left: `winchester`) and pick a centre:
   - a contact our side has reported (`ITW_CLASH_Knowledge_fnc_Contacts`) within
     1500 m of HAL's point, uncertainty 300 m or better, that the rack can hit;
     lowest distance plus uncertainty wins (`reported`);
   - else HAL's own point, if the rack can hit what HAL named (`hal-point`);
   - else nothing. On the first pass that means one pass at HAL's point on
     whatever geometry the rack has (`hal-point-hold`). Two empty passes in a row
     end the sortie: `clear` if it ever had a target, `nothing-to-hit` if not.
3. **Arm** every pass: COMBAT with `setBehaviourStrong`, **combat mode YELLOW**
   (fire at will, keep to the route), **attack off** (`enableAttack false`),
   TARGET and AUTOTARGET on, `limitSpeed` and `forceSpeed` cleared (a lift's stay
   low or hot drop can leave them), `flyInHeight` for the pass. v1 used RED and
   attack on, which let the pilot leave its route to chase.
4. **A run** (RUN): from the side the helicopter is on now, so no run starts
   with an overflight.
   - Two move waypoints, COMBAT and YELLOW: the break point on the radial toward
     the centre (completion 200 m, so it flies through it without slowing), then
     the next ingress point 60 degrees round (completion 400 m).
   - The AI fires as targets come into its forward arc, as it did on the infill.
   - The way out never comes closer to the centre than the break point while
     cos(offset) is at most break / ingress: at 60 degrees, while the ingress
     point is at least twice as far out as the break (2900 m against 600 m for
     the DAP, which would only cut back in past about 78 degrees).
   - The run ends at the ingress point (400 m), on a 20 s stall, or when it has
     averaged under 20 m/s over its path.
5. **A lap** (ORBIT): `doMove` the leader round the ring, 45 degrees a step,
   entering on the near side; a step ends on arrival (150 m), a 20 s stall (as
   ALiVE's `unitReadyRemote`), or 120 s.
6. **Reveal** to the crew, each leg, HAL's known enemies (`RydHQ_KnEnemies`)
   within the ingress distance (RUN) or the ring (ORBIT) plus 300 m, at 1.5.
   Nothing the commander does not know.
7. **Measure** each pass: the closest it came to the centre, its speed and
   height then, the time, and the shots by weapon (`heli-attack-flown`). A run
   whose closest is well inside its break is a run the AI left to close in.
8. **Hand back:** remove the shot watchers, clear its waypoints, `doFollow`,
   and put attack back as it was before the sortie. HAL's return leg runs next.

Not taken from ALiVE's CAS machine (`sup_combatsupport` cas.fsm, GPL; the
pattern only): ground-truth reveal of every enemy in the radius, forcing
CARELESS on ingress, zeroing the other weapons with `setAmmo`, and
`waitUntil aimedAtTarget > 0.8` with no timeout (the value is effectively
binary and the wait can hang), then `fireAtTarget`. Here the crew fights with
the real knowledge picture and its own targeting.

### 4.1 Ends

| Reason | Means | GoAttAir |
|---|---|---|
| `rack-empty` | Nothing on the rack hits anything, from the start | Return leg |
| `winchester` | Out of everything that hits anything | Return leg |
| `clear` | Two passes with nothing to hit, after having had a target | Return leg |
| `nothing-to-hit` | Two passes with nothing to hit, never had one | Return leg |
| `rtb-condition` | Damage over 0.5, fuel under 0.3, or the airframe cannot move | Return leg |
| `time` | 1200 s | Return leg |
| `lost` | Group, crew or leader's vehicle gone | Not-alive exit |
| `mia` | `RydHQ_MIA` set (a CLASH release, HALUnload, HQReset) | Not-alive exit |
| `break` | `Break` set (CLASH's withdrawal) | Not-alive exit |
| `withdrawing` | `ITW_CLASH_Withdrawing` (GTFO keeps the group HAL-managed and sets only this) | Not-alive exit |
| `released` | `Busy` cleared by someone else (G63: the crew remnant cleanup) | Not-alive exit |

**Retarget, then go home.** When the rack cannot hit what HAL sent it at (the
DAP's DAGR-M against infantry), the sortie looks for a reported contact it can
hit nearby; failing that it flies one pass at HAL's point and goes home. The
start line says what HAL sent it at, so a hold can be read.

### 4.2 Yielding to another owner

The last five ends mean the group is no longer this sortie's to fly:

- They are checked first, before any sortie limit, every 2 s poll.
- `RydHQ_MIA` is a handshake: the waiter clears it on reading it, and the setter
  (`ITW_CLASH_fnc_BeginRelease`, HALUnload) watches for that. `RYD_Wait` does
  it, so this does too.
- Each leg checks and gives its orders in one unscheduled step (`isNil`), so a
  withdrawal that lands between the check and the order is not overwritten.
- The hand-back is unscheduled too, and re-checks: a sortie ending on its own
  terms that was taken since the last poll takes the foreign path. That path
  deletes only waypoints named `clash-heli-attack`, cancels the leader's
  `doMove` only in ORBIT, and leaves attack as the new owner set it.
- GoAttAir's not-alive exit issues no waypoint, so no return leg lands on top of
  a withdrawal's move.

### 4.3 The CARELESS handoff

Dual-HAL Checkbook v9 clears Impasse's spawn CARELESS (to AWARE, with
`setBehaviourStrong`, where the group is local) when a field or migrated vehicle
is handed to HAL and is not a transport. On 2026-10-16 it fired on all 39 field
handoffs, both sides, and HAL's waypoints then moved those groups through SAFE
and COMBAT. Checkbook-bought artillery keeps its CARELESS by decision: it fires
and scoots regardless (B's MLRS did both).

## 5. Telemetry

Through `ITW_CLASH_DualHAL_fnc_Log`, so each line carries `dual-hal-` first.

| Line | Content |
|---|---|
| `CLASH BOOT \| rack-profile-ready` | Version, AI mode reach, turret span, ring bounds, margin, run break minimum, opening cap, lead-in, ingress cap, `warheadFlags=true` |
| `CLASH BOOT \| heli-attack-ready` | Version, retarget radius, uncertainty limit, ring step, run offset, leg timeout, clear passes, max time, height bounds, `modes=ORBIT,RUN combatMode=YELLOW attack=false noSAD=true yieldsToOwners=true` |
| `CLASHHALADD \| hal-overrides-applied` | Must list `HAL_GoAttAir` |
| `CLASHHALADD \| goattair-heli` | Group and flight classes, when a sortie takes this path |
| `rack-profile` | Once per class and loadout: up to 8 entries as [weapon, flags, bands, lock, aim, rounds], and per type [type, usable, ring radius, mode, run break, run ingress] |
| `heli-attack-start`, `-pass` | Group, class, pass, centre source, contact type, HAL's target type, centre, mode, break or ring radius, ingress (-1 for ORBIT), height, revealed count |
| `heli-attack-flown` | After each pass: group, pass, mode, the run's radial, break or ring radius, closest to the centre, speed (km/h) and height then, seconds, shots by weapon |
| `heli-attack-shot` | Each missile and rocket: group, class, weapon, gunner's target class, range, height, speed |
| `heli-attack-end` | Group, reason, passes, seconds, last source, last type, shots since the last pass |
| `impasse-careless-cleared` | Group, vehicle class, which handoff |

## 6. Tunables

| Setting | Value |
|---|---|
| AI fire mode minimum reach | 50 m |
| Fixed turret span | under 60 degrees |
| Margin | 1.2 over a band's edge |
| Run break | at least 600 m |
| Run opening cap, lead-in, ingress cap | 2500 m, 400 m, 3000 m |
| Run offset | 60 degrees |
| Run arrival, slowest average | 400 m, 20 m/s |
| Ring bounds, step | 250 to 1500 m, 45 degrees |
| Ring arrival, stall, leg timeout | 150 m; under 10 m moved in 20 s; 120 s |
| Retarget radius | 1500 m from HAL's point |
| Uncertainty limit for a centre | 300 m |
| Passes with nothing before going home | 2 |
| Sortie limits (HAL's) | Damage 0.5, fuel 0.3, 1200 s |
| Height | 0.15 x break or ring radius, 50 to 150 m |
| Reveal | `RydHQ_KnEnemies` within ingress or ring + 300 m, at 1.5 |
| Poll | 2 s |

## 7. Tradeoffs and limits

- **Speed is the protection, not range.** A 600 m break is still inside a
  vehicle HMG's reach. A run spends about 20 s inside 1.5 km; v1 spent minutes
  hovering there. AA (a Cheetah, MANPADS) reaches past any break.
- **YELLOW and attack off are the engine's levers, not a guarantee.** That they
  keep an AI helicopter leader on its line is the reading of how the two modes
  work; `heli-attack-flown`'s closest distance is the check.
- **Unguided weapons fire from far.** The run opens where the AI's own bands
  open: DAR's Far_AI mode reaches 3200 m, so rockets may go at infantry from
  2.5 km. The AI's choice, from the config.
- **A gunner-controlled pylon reads FIXED.** Pylons are FIXED whatever seat
  fires them, so a Hellfire on a gunner's seat gives a RUN. A chin-turret
  attack helicopter with pylons orbits (its gun is a TURRET).
- **A seeker-only rack cannot take an infantry sortie.** By design: the DAP with
  only DAGR-M retargets to vehicles or goes home.
- **Ring size counts weapons, not damage.** Good enough to keep every weapon out
  of its floor; not a weapon-effect model.
- **Mod configs are trusted.** A mod whose AI modes or flags are wrong gets the
  wrong geometry, and the `rack-profile` line shows exactly why.

## 8. To verify in engine

1. `rack-profile` for the DAP: ARMOR now 1, every type RUN with break 600 and
   ingress 2900.
2. `heli-attack-flown`: closest distance near the break (600 m) on every run,
   at speed. Closest well inside it means the AI still leaves the line.
3. `heli-attack-shot` ranges: shots across the run, from about 2.7 km in to the
   break, as on the v1 infill.
4. Whether YELLOW costs shots: the run-in fired four DAGR-M under RED; compare
   shots per run.
5. A withdrawal or release mid-sortie: `heli-attack-end` with `break`, `mia` or
   `withdrawing`, the withdrawal MOVE still on the group, and no return leg.
6. The A side's DAP hold: what HAL sent it at (the start line now says).

## 9. Deployment

The GoAttAir swap is in the addon, not the mission: refresh the `-mod` folder
for C.L.A.S.H. HAL Additions along with the mission. Without it the mission
still boots both modules (they read and wait) and HAL flies its original SAD.

## 10. Implementation

| File | Owns |
|---|---|
| `ITW_CLASH_RackProfile.sqf` (v2) | Reading racks (missile and warhead flags); mode; run and ring geometry; the guided anti-armour test |
| `ITW_CLASH_HeliAttack.sqf` (v2) | The sortie between HAL's order and its return leg: runs or a ring |
| `CLASH HAL Additions/.../hal/GoAttAir.sqf` | HAL's GoAttAir plus the helicopter branch |
| `CLASH HAL Additions/.../functions/fnc_overrides.sqf` | `HAL_GoAttAir` among the 10 swaps |
| `ITW_CLASH_DualHALCheckbook.sqf` (v9) | Clearing Impasse's spawn CARELESS at the handoff |
| `ITW_CLASH_SupportsStrike.sqf` (v3) | Guided pass reads through the rack |
| `init.sqf` | Rack profile before Knowledge; heli attack after the supports, only if the rack is ready |
| `ITW_CLASH_DebugPreflight.sqf` | Rows for both modules |

Tests: `tests/test_rack_profile.py` (static contract; Python mirrors of the flag
union, ring sizing and run sizing), `tests/test_heli_attack.py` (the GoAttAir
copy keeps every HAL line in order and adds only the branch, the tail is HAL's;
no search-and-destroy, two-waypoint runs, YELLOW and attack off, the measured
pass, stops and yielding, the withdrawal signals it reads, the way out never
cutting inside the break), `tests/test_handoff_careless.py`.
