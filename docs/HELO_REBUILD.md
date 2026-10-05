# Helicopters: what is actually wrong, and the smallest build that fixes it

Status: proposal. Nothing here is built. Written after run8, the fourth bad
helicopter run.

Hark's spec, verbatim:

> how fucking hard is it to have helos that have their chalk get teleported
> in, they fly to their obj, and depending on ITW's settings, they either
> paradrop or dont. and add special system, when going into a hotzone, they'll
> invoke a HOTDROP instead!

That is four requirements. Three of them are already built. The reason it
doesn't work is not any of the three.

---

## 1. The fault

### 1.1 The air-unload decision exists in seven places and C.L.A.S.H. patched two

Stock NR6 HAL decides how an air-lifted squad gets out with one line, and that
line is **byte-identical in seven order files**:

```sqf
if (((group (assigneddriver _AV)) in (_HQ getVariable ["RydHQ_AirG",[]])) and (_unitG in (_HQ getVariable ["RydHQ_NCrewInfG",[]]))) then {_sts = ["true","(vehicle this) land 'GET OUT';deletewaypoint [(group this), 0]"]};
```

| File | Line | Forked into the C.L.A.S.H. addon? | Air unload fixed? |
|---|---|---|---|
| `GoAttInf.sqf` | 487 | yes | **yes** |
| `GoRecon.sqf` | 540 | yes | **yes** |
| `GoCapture.sqf` | 510 | yes | no |
| `GoRest.sqf` | 427 | yes | no |
| `GoAttSniper.sqf` | 205 | no | no |
| `GoFlank.sqf` | 424 | no | no |
| `GoSFAttack.sqf` | 549 | no | no |

`GoCapture` is the zone-capture order. It is the most common air insertion in
this mission, it is a file C.L.A.S.H. **already forks** (`fnc_overrides.sqf`
swaps nine HAL globals), and it still runs the stock line: land, kick them out,
and because nothing ever issues `land "NONE"`, sit there.

So "helos are still landing" is not a mystery and not a race. Five of seven
unload sites were never touched, two of them in files already open in front of
us. A capture lift behaves exactly as it did before any of this week's work.

The only difference between the seven lines is a trailing `\r` — NR6 ships
CRLF, and `HALCargoDiceFix.sqf:339` already normalises that before matching.
**One anchor covers all seven.**

### 1.2 Two systems fly one helicopter

`HotDrop` is a complete parallel executor: it claims an airframe, runs its own
`INGRESS -> POPUP -> DROP -> EGRESS` loop with its own `doMove` calls, and
hands back. HAL's `SCargo` is also a complete executor for the same airframe.
Run8 measured both running at once on one Littlebird: 487 m of 1684 m in four
minutes, every phase ending on its 120 s timeout rather than an arrival.

`9022d64` added a `Busy` interlock so HotDrop declines a carrier HAL is already
flying. That stops the collision; it does not make HotDrop useful, because
*every* HAL troop lift sets `Busy`. HotDrop is now a 733-line module that
correctly declines almost everything.

### 1.3 A map-wide sweep for airframes to claim

HotDrop's poll is `vehicles select {isKindOf "Helicopter" && alive && alt <= 3
&& crew != []}`. That is every helicopter on the map sitting on the ground,
not HAL's transports. Its ownership guard read `ITW_CLASH_CASEVAC_State` off the
carrier's crew group, a variable that only ever lives on the casualty's squad,
so the guard could not fire — fixed in `63b0fda` by asking
`ITW_CLASH_DualHAL_fnc_IsLifecycleReserved`, which is the module that reads the
markers CASEVAC actually sets. The sweep is the reason that guard had to be
right rather than merely present.

### 1.4 What is already built and working

- **Chalk teleport at base.** `HALCargoDiceFix_fnc_BaseEmbark`. Run8 confirmed
  it fires ("chalk teleport and helo landed"). No work needed.
- **The paradrop itself.** `HALParadrop_fnc_Execute`, plus `fnc_ReleaseCarrier`
  which is the one thing in the codebase that issues `land "NONE"` after a
  drop.
- **The corridor classifier.** `AirPicture`, with `COLD / CONTESTED / HOT /
  AIR_DENIED / UNKNOWN`.
- **`ITW_ParamHelisUnload` handling.** `HALParadrop_fnc_ShouldUse` already
  honours 0 (land only), 100 (chute only), 777 (random) and biases the mixed
  modes.

Every piece of Hark's spec exists except the thing that connects them, and the
connector was installed in two of seven sockets.

---

## 2. Target: one owner per question

| Question | Owner | Change |
|---|---|---|
| Does this squad ride at all? | HAL (`SCargo`) | none |
| Does it walk to the aircraft or get teleported? | `HALCargoDiceFix_fnc_BaseEmbark` | none |
| Where does the aircraft fly? | HAL | none |
| Who flies it? | **HAL, only** | HotDrop stops flying |
| How does the squad get out? | **`ITW_CLASH_HALUnload`** (new) | all seven sites |
| Executing a chute drop | `HALParadrop_fnc_Execute` | none |
| Letting the carrier leave | `HALParadrop_fnc_ReleaseCarrier` | none |

Nothing in this plan adds a state machine, a move marker, or a second
`doMove`. HAL keeps the aircraft for the whole flight. C.L.A.S.H. answers one
question, at the moment the aircraft arrives.

---

## 3. The build

### Step 1 — `ITW_CLASH_HALUnload.sqf`: one anchor, seven sites

A runtime patch in the established house pattern (`preprocessFileLineNumbers`
-> normalise CRLF -> all-or-nothing text swap -> `compile`), replacing the
stock statement with:

```sqf
_sts = ["true","[group this, vehicle this] call ITW_CLASH_HALUnload_fnc_Unload"]
```

Two details that matter:

- **Read from the path the loaded code came from.** `fnc_overrides.sqf`
  compiles nine globals from `\clash_hal_additions\hal\`. Patching
  `RYD_Path + "HAL\GoCapture.sqf"` and installing the result would silently
  throw away the addon's other fixes to that file. `fnc_overrides` should
  record the source path per global, and the patch picks per file.
- **Assert the anchor count.** One hit per file, seven files. A HAL update that
  changes the line fails the patch loudly and leaves stock behaviour, as
  `HALCargoDiceFix` does today.

**Then revert the hand-edits in the addon's `GoAttInf.sqf` and `GoRecon.sqf`
back to the stock line** so the anchor matches there too. Their `_clashPara*`
decision block (~60 lines each, duplicated) moves into `fnc_Unload`. That
retires two forked-file divergences rather than adding five more.

This step alone is why captures land. It is testable in one run.

### Step 2 — `fnc_Mode`: the three-way, decided when the waypoint fires

```
ITW_ParamHelisUnload == 0            -> LAND
ITW_ParamHelisUnload == 100          -> PARADROP
otherwise                            -> ShouldUse bias (heavy cargo, threat)
then, corridor at the DESTINATION:
  HOT | AIR_DENIED | UNKNOWN         -> force HOT_PARADROP, never land
  CONTESTED                          -> force PARADROP
  COLD                              -> leave the above decision alone
```

Decided **at the waypoint, not at waypoint-build time.** This is the single
most important line in the plan. Every helicopter bug this week was a
build-time evaluation that was wrong by the time it mattered:

- `_clashParaAboard` read occupancy ~390 lines before the squad finished
  boarding, leaving `_sts` at its default `deletewaypoint`, so nobody got out
  at all.
- The corridor cannot be classified at build time — it is a route, and there
  is no route until there is a destination.
- The origin guard exists because the drop had to discover at execution time
  that it was still sitting where it boarded.

`UNKNOWN -> never land` is Hark's own rule from the Littlebird losses, and it
belongs here rather than in a separate module.

### Step 3 — `fnc_Unload`: three branches, one release

```
LAND:         land "GET OUT"  ->  ReleaseCarrier
PARADROP:     HALParadrop_fnc_Execute  ->  (releases internally)
HOT_PARADROP: low ingress + pop-up + flare cadence + drop  ->  ReleaseCarrier
```

`HOT_PARADROP` reuses HotDrop's *numbers and flares*, not its executor: no
claim, no phase loop, no handback, no cooldown, no `doMove`. It is the paradrop
branch with the hot-drop height profile and `fnc_Flare`, run from the same
waypoint statement, on an aircraft HAL still owns.

Every branch ends in a release. One owner of `land "NONE"`, which retires the
sticky-landing class of bug instead of patching each site that hits it.

Fail-open: if `ITW_CLASH_HALUnload_fnc_Unload` is missing or throws, the
statement must still reach `deletewaypoint`. A waypoint statement that throws
leaves the waypoint in place — that is how `aee1341` got written.

### Step 4 — HotDrop stops being an executor

Delete: `fnc_Run` (~190 lines), `fnc_Claim`, `fnc_SetPhase`, `fnc_Handback`,
`fnc_PutOut`, `fnc_Consider`, the poll loop, the cooldown map, the `Busy`
interlock, the lifecycle guards. Roughly 420 of 733 lines.

Keep as a profile library for Step 3: `fnc_Flare`, `fnc_CargoGroup`,
`fnc_Aboard`, `fnc_Destination`, and the height/radius settings.

Deleting the sweep retires the medical and reconstitution exposure rather than
guarding it, and removes the only code path in the mission that takes an
aircraft away from whoever was already flying it.

### Step 5 — make the RPT answer the question in one grep

One line per lift at the unload: `group | aircraft | order file | param |
corridor | mode | result`. Today answering "did anything paradrop this run?"
takes four greps across three modules and a guess about which order file ran.

### Step 6 — prove the things that must not move

Logistics and medical are not in this change, and the tests should say so
rather than leaving it to be re-litigated next run:

- Supply runs cannot enter base embark: gated `not (_withdraw) and not
  (_request) and not (_emptyV)` at `HALCargoDiceFix.sqf:383`.
- `SCargo.sqf:755`'s own `land 'GET OUT'` is the transport's drop-off, not an
  order file's, and is out of scope for Step 1's anchor.
- CASEVAC releases its own landings (`SendHeliHome` issues `land "NONE"`
  before the egress waypoint) and deletes its airframes.
- GroundMEDEVAC has no aircraft at all.
- Thunder Run's four modules are untouched.

---

## 4. Tests required

- The anchor matches exactly seven files, once each — the whole plan rests on
  this, so it is asserted against HAL's real source.
- Patch is all-or-nothing: a missing anchor in any file leaves every file
  stock.
- Forked files are patched from the addon path, not `RYD_Path`.
- `fnc_Mode` truth table: 0, 100, 777, mixed x five corridor states x heavy
  and light cargo.
- `UNKNOWN` never yields `LAND`.
- `ITW_ParamHelisUnload == 0` yields `LAND` in **every** corridor state (the
  mission setting wins; C.L.A.S.H. biases mixed modes only).
- Every branch of `fnc_Unload` reaches a release.
- The waypoint statement reaches `deletewaypoint` on every path including a
  thrown call.
- The decision is read at execution time: no `_clashPara*` local survives into
  the replacement statement.
- HotDrop exports no executor after Step 4, and nothing calls the deleted
  functions.
- The six no-move contracts in Step 6.

## 5. Sequencing and cost

Steps 1-3 are one mechanism and should ship together: ~350 lines added, ~120
removed from two forked HAL files. **Step 1 is the fix for what Hark is
actually seeing** — a capture lift today runs stock HAL.

Step 4 ships after one green run, so a bad result can be bisected against a
HotDrop that still exists. ~420 lines deleted.

Step 5 can ride with 1-3; it is thirty lines and it is how the next run gets
diagnosed in one pass instead of four.
