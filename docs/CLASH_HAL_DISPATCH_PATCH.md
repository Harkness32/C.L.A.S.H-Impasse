# HAL Dispatch Coverage — CLASH HAL Additions Addon + Checkbook Piping

**Status:** draft, untested in a hosted session
**Supersedes:** an earlier version of this doc described a direct 2-file patch
to `nr6_hal` (`HQOrders.sqf` + `HAC_fnc.sqf`). That approach was abandoned in
favour of the standalone addon described below — `nr6_hal` is unmodified,
byte-for-byte, from vendor.

This covers two separate pieces, built in sequence:

1. **Tactical response** — `CLASH HAL Additions` addon. HAL actively responds
   to the 5 threat categories.
2. **Budget piping** — `ITW_CLASH_HALThreatCoverage.sqf`. When HAL's own force
   pools can't cover one of those categories, request replenishment through
   Checkbook. See "Budget piping" section below.

These two are intentionally independent — neither reads the other's state.
Both read the same public `RydHQ_*` HQ-object variables on their own.

## What this is

A separate addon, `CLASH HAL Additions` (`addons/clash_hal_additions/`), that
gives HAL an active response for five enemy threat categories it already
detects but never counters: `AAInf`, `StaticAA`, `StaticAT`, `Support`,
`Cargo`. (A sixth, `Other`, was dropped — `HQOrders.sqf` declares `_Otherthreat`
but never populates it anywhere; nothing is ever classified into it, so
there is nothing to respond to.)

`AAInf`/`StaticAA`/`StaticAT` already shape HAL's *avoidance* behaviour today
(folded into `RydHQ_AAthreat`/`RydHQ_ATthreat`, which other units check before
engaging nearby). This addon adds active *hunting* of those threats on top of
the avoidance that already existed. `Support`/`Cargo` had zero effect on HAL's
behaviour before this addon.

## Why this needed no changes to nr6_hal at all

Initial approach was a direct patch to `HQOrders.sqf`/`HAC_fnc.sqf` (adding
call sites + switch cases). That's unnecessary. The raw enemy-classification
lists these threat kinds are built from — `RydHQ_EnAAinf`, `RydHQ_EnStaticAA`,
`RydHQ_EnStaticAT`, `RydHQ_EnSupport`, `RydHQ_EnCargo` — are already public
`getVariable` state on the HQ object, populated by HAL's own scanner
independently of `HQOrders.sqf`'s per-tick tallying. A separate addon can read
that state directly and act on it without touching, wrapping, or vendoring a
single line of `nr6_hal`. (`HAL_HQOrders` itself is technically a reassignable
global — `VarInit.sqf:1113` — so a wrap was possible, but reading the
upstream public state directly is simpler and has zero coupling to HAL's
internal call flow or future refactors of `HQOrders.sqf`.)

## Structure

```
CLASH HAL Additions/addons/clash_hal_additions/
  config.cpp                  CfgPatches (requiredAddons: NR6_HAL), CfgFunctions
  functions/fnc_start.sqf     preInit=1 — self-starting, no mission-file hook needed
  functions/fnc_watch.sqf     per-HQ loop, one spawned per active LeaderHQ..LeaderHQH
  functions/fnc_respond.sqf   the response engine (scoring/selection/commit)
```

Fully self-starting: `fnc_start.sqf` runs via `preInit=1`, waits for each
possible HQ slot to come alive, and spawns a watcher per HQ that's actually in
use. No mission `init.sqf` edit, no CLASH bootstrap change, nothing to wire up
— load the addon alongside NR6 HAL and it runs.

## Doctrine choices (unchanged from the original plan)

- **AAInf / StaticAA** responses exclude `airCAS`/`airCAP` — don't fly
  aircraft at a known AA threat. Ground-only: armour, infantry, snipers.
- **StaticAT** excludes armour patterns — don't drive tanks at a known AT gun.
  Leans on CAS air and infantry instead.
- **Support / Cargo** are soft, low-priority raid targets: cars, light armour,
  CAS as an option.

## Known simplifications vs. RYD_Dispatcher

`fnc_respond.sqf` reuses HAL's actual scoring formulas (terrain preference,
AT/AA proximity risk-resignation) and actual helper functions
(`RYD_TerraCognita`, `RYD_DistOrd`, `RYD_CloseEnemyB`, `RYD_AmmoCount`,
`RYD_PointToSecDst`, `RYD_IsNight`, `RYD_GoLaunch`, `RYD_Spawn`) so the *feel*
should match. Two things are simplified, not faithfully reproduced:

- **Pacing.** `RYD_Dispatcher` tracks a per-group `HAC_Attacked` history array
  to adjust how many responders "are enough" over time. This addon uses a
  flat limit of 2 responders per pattern per threat group per pass instead.
  Fine for a first pass; revisit if it under- or over-commits in a hosted
  test.
- **CAS pool.** HAL's internal `_airCAS` is built by merging several force
  lists inside `RYD_Dispatcher` (`RCAS` + `BAirG` + a filtered `AirG`). This
  addon approximates it as `RydHQ_RCAS + RydHQ_BAirG` only — close, not
  byte-identical.
- **No cross-cycle "already handled" tracking.** HAL's own tally loop
  deduplicates against a `Checked<group>` marker per `HQOrders.sqf` cycle.
  This addon re-evaluates the full `RydHQ_En*` list every 20s pass; the
  busy/`Unable`/`AttackAv` checks in `fnc_respond.sqf` prevent double-committing
  a friendly unit, but there's no equivalent of HAL's per-enemy pacing memory.
  Acceptable for now; a per-enemy-group "already responding" flag would be the
  natural follow-up if this proves too chatty in logs.

## Not yet done (addon)

- No hosted-session validation.
- No test coverage under `tests/`.
- `RydxHQ_MARatio`-based "enough" tuning (used by `RYD_Dispatcher` itself) was
  not ported — see pacing note above.

## Budget piping — ITW_CLASH_HALThreatCoverage.sqf

**Precedent, not invention.** This mirrors `ITW_CLASH_HALLogistics.sqf`
exactly, which already does this for `AMMO`/`FUEL`/`REPAIR`: reads HAL's own
public demand state, reads HAL's own public supply pools, and calls
`ITW_CLASH_fnc_RequestCapability` when supply can't cover demand. The one
real difference: `HALLogistics.sqf` gets triggered by wrapping the native
`HAL_SuppAmmo`/`SuppFuel`/`SuppRep` globals, because HAL already decides it
needs those and calls a function to act on it. HAL has no equivalent call for
`AAInf`/`StaticAA`/`StaticAT`/`Support`/`Cargo` — that's the whole gap this
project started from — so this file runs its own poll loop instead of
wrapping anything, on a 20s interval, iterating `ITW_PlayerSide`/
`ITW_EnemySide` via `ITW_CLASH_fnc_GetCommanderForSide` (the same pattern
`HALLogistics.sqf`'s own zero-provider bootstrap loop uses).

**Two capabilities requested, not five.** `AAInf`/`StaticAA`/`Support`/`Cargo`
all use `GROUND_ATTACK_LIGHT` (ground-only, matching the tactical doctrine
that excludes air for these). `StaticAT` uses `CAS_AIRCRAFT` (air, matching
the tactical doctrine that excludes armor for that one). Same reasoning as
the addon's response pools, applied to what gets requested instead of what
gets dispatched.

## ForceGeneration.sqf providers — GROUND_ATTACK_LIGHT / CAS_AIRCRAFT

**The open question from the previous section of this doc was wrong, and
worth recording why.** It asked whether a Checkbook-generated combat asset
would register into HAL correctly. It already does — generically, for every
capability — via `ITW_CLASH_Generation_fnc_RegisterAsset` (`spawn → DualHAL
RegisterGroup → HAL knows the asset → capability-specific pool projection`).
That's not incidental: if `RegisterAsset` returns `false`, `Provider` deletes
the spawned asset and returns `hal-registration-failed` — registration is a
required step in fulfillment, not a side effect. The real gap was narrower:
`RegisterAsset`'s capability-specific switch only had cases for `ARTILLERY`
and `LOGISTICS_*`; nothing projected a new asset into a pool HAL's own
attack-side logic (or `CLASH HAL Additions`) would ever look at. **Same for
`GetPool`** (no classlist source for these two capabilities) **and
`SelectBillingDefs`'s role-bias** (a plain `ARTILLERY`-vs-everything-else
check would have scored these two as needing a transport role — a real
correctness bug, not just a missing case).

Three providers-side changes, all in `ITW_CLASH_ForceGeneration.sqf`:

1. **`GetPool`** — two new cases reading `ITW_CLASH_PlayerGroundAttackLightClasses`/
   `EnemyGroundAttackLightClasses` and `...PlayerCASAircraftClasses`/
   `EnemyCASAircraftClasses` (see `VehicleArrays.sqf` below).
2. **`SelectBillingDefs`** — the role-bias check now treats `ARTILLERY`,
   `GROUND_ATTACK_LIGHT`, and `CAS_AIRCRAFT` all as attack-role capabilities;
   everything else still gets the transport-role bias.
3. **`RegisterAsset`** — two new cases. Both explicitly clear
   `NoAttack`/`NoRecon`/`NoDef` first (via `SetConstraintMembership(...,false)`,
   confirmed to be a real add/remove toggle on both the HQ-scoped and dual-HAL
   global-prefixed lists — the generic path just above the switch adds every
   new asset to all three, which is correct for a support truck and wrong for
   a combat asset). Then:
   - `GROUND_ATTACK_LIGHT` classifies the actually-spawned vehicle via the
     existing `ITW_CLASH_Generation_fnc_ClassKind` helper and routes to
     `RydHQ_LArmorG` (tank-kind, i.e. a tracked Apc) or `RydHQ_CarsG`
     (car-kind, i.e. a wheeled Apc or armed car). No infantry fallback — see
     the classlist correction below, infantry can no longer be spawned here at
     all, so the old `RydHQ_NCrewInfG` default was removed rather than left as
     dead code. `CarsG` is kept as a *defensive* fallback for a kind that
     shouldn't occur, logged when it does.
   - `CAS_AIRCRAFT` routes into `RydHQ_RCAS` (read by both native HAL's
     `RYD_Dispatcher` merge and the addon's `fnc_watch.sqf`) and `RydHQ_AirG`
     (general air bookkeeping) — the same dual-registration shape
     `LOGISTICS_AMMO`/`AIR` already uses for `AmmoDrop`+`AirG`.
4. **Provider registration loop** — both capability names added alongside the
   existing four.

**`VehicleArrays.sqf` — the classlists (revised).** The first version of this
was wrong on both fronts, caught in review before implementation:
`va_pInfClassesForWeights` doesn't belong in a vehicle-billing pipeline that
spawns via `ITW_AtkSpawnVeh` — infantry generation is Impasse's separate
machinery, not this one; and `va_pTankClasses` is MBTs, which isn't what
"light" ground attack means, while `VehicleArrays.sqf` tracks `va_pApcClasses`
as an *explicitly separate* bucket the first pass never queried for (the grep
that found the other `va_*` pools used a regex that didn't include `Apc`).

Corrected source, and better than either of our first proposals: Impasse
already maintains role-tagged `*ClassesAttack`/`*ClassesDual` variants per
physical kind (`va_pApcClassesAttack`, `va_pCarClassesDual`,
`va_pPlaneClassesAttack`, `va_pHeliClassesDual`, etc.), driven by its own
`ITW_ParamAttack*SpawnAdjustment`/`ITW_ParamTransport*SpawnAdjustment`
params — i.e. Impasse already has an authoritative "armed and in the fight"
roster per kind, kept structurally separate from the unarmed-transport
variants. No `weapons[]` config heuristic needed for either capability:
- `GROUND_ATTACK_LIGHT` = `Apc + Car`, Attack+Dual roles only, **explicitly
  minus `va_[pe]AAClasses`** — this isn't precautionary, `VehicleArrays.sqf:420-421`
  and `:425-426` literally push wheeled AA vehicles into `va_[pe]ApcClasses`
  directly, so without the subtraction an AA truck could get bought and
  registered as a ground-attack asset.
- `CAS_AIRCRAFT` = `Plane + Heli`, Attack+Dual roles only.

Both now buy from the same physical-kind/role vocabulary Impasse's own
faction data already encodes, rather than a hand-rolled heuristic guessing at
what "armed" means from raw config fields.

**Not yet done:**
- No hosted-session validation — this is the part of the whole arc most worth
  testing first, since it's the only piece that actually spawns something new.
- No test coverage under `tests/`.
- Still worth a human pass confirming `va_[pe]ApcClassesAttack/Dual` and
  `va_[pe]CarClassesAttack/Dual` are non-empty for this mission's configured
  factions (if a faction has attack-Apc spawning disabled via the
  `SpawnAdjustment` param, `GetPool` will correctly return an empty pool and
  every `GROUND_ATTACK_LIGHT` request will come back `DENIED
  no-affordable-faction-capability` — correct behaviour, but worth knowing
  ahead of a hosted test rather than discovering it there).
- Cooldown (45s per HQ per kind, in `ITW_CLASH_HALThreatCoverage.sqf`) chosen
  by analogy to `HALLogistics.sqf`'s own 45s cooldown, not independently
  tuned.

## Infantry — not a Checkbook capability, an advisory hook into Impasse

**Why this doesn't look like the vehicle capabilities above.** The first
instinct was `INFANTRY_AT`/`INFANTRY_AA` as more `RequestCapability`
providers, matching `GROUND_ATTACK_LIGHT`/`CAS_AIRCRAFT`. Checked against the
real code and that's wrong. HAL doesn't request infantry at all — it
classifies whatever infantry already exists (`HQSitRep.sqf`) into pools
(`RydHQ_NCrewInfG`/`ATInfG`/`AAInfG`) and employs them; there's no
`HAL_Supp*`-shaped call to intercept, because HAL never decides it needs more
infantry in the first place. Meanwhile Impasse already runs its own
continuous, cap-respecting manpower loop (`ITW_Attack.sqf`, "Infantry AI
Spawner", gated on `_activeAiCnt < _maxAiRightNow`) completely independent of
HAL. A second Checkbook-driven infantry spawn path would run *alongside*
that, not replace or extend it — the likely result is unexplained squads
appearing on top of Impasse's normal reinforcement, not a coherent capability
system.

**What actually gets built instead.** Not "buy more infantry" — "when
Impasse is about to build a new squad anyway, let CLASH advise which
template." Verified precisely where that decision happens:
`ITW_Attack.sqf:571-586` builds `_squadTypes` from `CfgGroups` (each entry a
flat array of unit classnames — one whole pre-composed squad), with a 50%
faction-coverage safety valve that empties `_squadTypes` entirely for factions
without well-defined squad templates. Selection was `selectRandom
_squadTypes` (`ITW_Attack.sqf:1006`, pre-patch) — uniform, no bias, matching
"able bodies screaming to the front" exactly.

**`ITW_CLASH_InfantryDemand.sqf`** — new file, no `ForceGeneration.sqf`
involvement at all:
- `ITW_CLASH_fnc_SelectInfantryTemplate` — the advisory function. Given
  `_squadTypes` and `_side`, filters to templates that intersect the active
  demand's vocabulary and picks uniformly among only those. **Revised twice
  in review before this ever ran:**
  - **Vocabulary.** First draft read only `RYD_WS_ATinf_class` (etc.) — HAL's
    static `RHQLibrary.sqf` baseline. HAL's actual live classification is
    `RHQ_ATInf + RYD_WS_ATinf_class - RHQs_ATInf` (`HQSitRep.sqf:119-127`) —
    `RHQ_*`/`RHQs_*` are this mission's own per-faction additions/exclusions
    on top of the baseline, and skipping them would miss exactly the modded
    classes HAL itself accounts for. Also missing: lowercasing. `_squadTypes`
    classnames are stored via `toLowerANSI` (`ITW_Attack.sqf:561`); an
    un-lowercased vocabulary would fail every `arrayIntersect` silently, even
    against a real match.
  - **Selection.** First draft scored every template, gave matching ones a
    5:1 weight via `selectRandomWeighted` across the *whole* pool, then
    unconditionally cleared the demand and logged `demand-fulfilled` —
    meaning a non-matching template could win the roll and still get logged
    (and consumed) as a successful AT pick. Real bug, not style: it directly
    contradicted the one-shot "consumed only on success" design. Fixed by
    dropping weighting entirely — filter to matching templates first
    (`_squadTypes select {count (_x arrayIntersect _vocab) > 0}`), pick
    uniformly among only those, consume the demand only in that branch. The
    5:1-tilt-across-everything approach was solving a problem (don't turn a
    *standing* bias into an all-AT army) that doesn't apply to a one-shot
    request that goes hands-off immediately after firing once.

  Still returns `[]` (meaning "no preference") whenever there's no active
  demand, the demand has expired, HAL isn't installed, or none of
  `_squadTypes`' actual templates contain a matching class — that last case
  still does **not** synthesize a squad Impasse's own faction data doesn't
  support; it respects the same 50% safety-valve philosophy Impasse already
  applies to itself, and logs `demand-no-matching-template` instead, without
  consuming the pending demand.
- One-shot demand, not a standing bias: `ITW_CLASH_InfantryDemand_fnc_SetDemand`
  raises `AT`/`AA` per side; `SelectInfantryTemplate` consumes it (clears it)
  only on a *successful* preferential pick, not on a miss — a demand that
  can't yet be matched stays pending until it expires
  (`ITW_CLASH_InfantryDemandExpirySeconds`, default 120s) rather than being
  thrown away on the first unlucky roll.
- `ITW_CLASH_InfantryDemand_fnc_Evaluate` — the HAL-state watcher, same
  self-contained-poll shape as `HALThreatCoverage.sqf` (reads
  `RydHQ_EnHArmor`/`EnLArmorAT`/`EnAir` and `RydHQ_ATInfG`/`AAInfG` directly,
  30s cadence, no dependency on `HALThreatCoverage` or the addon — same "both
  read the same public state independently" principle as everywhere else in
  this arc).

**The Impasse-side hook (`ITW_Attack.sqf`, replacing the `selectRandom
_squadTypes isNotEqualTo []` branch)** is deliberately tiny and fails open:
calls `ITW_CLASH_fnc_SelectInfantryTemplate` only if it's defined, uses its
result only if non-empty, otherwise falls through to the exact original
`selectRandom _squadTypes`. With `ITW_CLASH_InfantryDemand.sqf` absent, this
is byte-for-byte the original behaviour.

**Not yet done:**
- No hosted-session validation.
- No test coverage under `tests/`.
- `RydHQ_EnMArmor` was checked against a repo-wide search and doesn't exist as
  a public HQ variable — HAL builds a medium-armor taxonomy internally
  (`_MArmor_class`/`_EnMArmor`/`_EnMArmorG`) but never publishes it the way
  `RydHQ_EnHArmor`/`RydHQ_EnLArmorAT` are published. The watcher correctly
  uses only the two confirmed-public ones.
- 120s expiry is a first-pass number, not tuned (weighting itself was removed
  — see above, it wasn't just untuned, it was wrong).
- Doesn't yet cover `RECON` as a live-triggered demand (the vocabulary lookup
  and matching-template selection both support it; nothing in `Evaluate`
  raises one yet).

## Generalizing HALThreatCoverage to HAL's original 9 categories

**The gap:** everything above only covered the 5 categories added this arc.
HAL's original 9 dispatch categories (`Recon`/`ATInf`/`Inf`/`Armor`/`Cars`/
`Art`/`Air`/`Static`/`Naval`) can run their own response pools dry too —
`RydHQ_ATInfG` empty against a real armor push isn't unique to `StaticAT`, it
happens on the plain `Armor` threat path just as easily, and that path
predates this whole arc, so nothing was requesting replenishment for it.

**What generalized for free:** `ITW_CLASH_InfantryDemand.sqf`'s watcher
already reads `RydHQ_EnHArmor`/`RydHQ_EnLArmorAT`/`RydHQ_EnAir` and
`RydHQ_ATInfG`/`RydHQ_AAInfG` directly — raw, category-agnostic HQ state, not
anything scoped to `StaticAT`/`AAInf` specifically. It was already covering
the original `Armor`/`Air` categories' specialist-infantry gap without any
change needed. Worth noting since it would have been easy to assume it
needed the same generalization work as the vehicle side and duplicate
something that was already correct.

**What needed real work: `ITW_CLASH_HALThreatCoverage.sqf`.** Extended the
demand table from 5 entries to 11, each now checking ground and/or air
independently based on what `RYD_Dispatcher`'s actual response pool for that
kind contains (`HAC_fnc.sqf`'s switch, not a guess) — e.g. `ATInf`'s pool is
`SNP+AIR+INF` so it only checks air; `Armor`'s is `AIR+ARM+ARM+INF` so it
checks both. `Air` is handled as its own case below the loop rather than
folded into the generic table, because its real pool is `airCAP+AAInfG`
(`HAC_fnc.sqf`'s `"Air"` case) — a different pool than every other "air"
check here.

**A real gap found while doing this, not just generalized:**
`ForceGeneration.sqf`'s `CAS_AIRCRAFT` case only registered into
`RydHQ_RCAS`. HAL's `Air` threat dispatch draws on `RydHQ_RCAP` specifically
— without also registering there, a `CAS_AIRCRAFT` purchase would never
actually help HAL answer an enemy-air deficit, only a ground-support one.
Fixed by registering into both (same dual-registration shape as
`LOGISTICS_AMMO`/`AIR`'s `AmmoDrop`+`AirG`).

**Deliberately not covered, not an oversight:**
- `Recon` — its pool is `SNP+INF` only, no vehicle capability applies to it.
- `Naval` — its pool is `allNaval` only, and no `NAVAL` capability/provider
  exists. Would need a third vehicle capability end-to-end (classlists,
  `GetPool` case, `SelectBillingDefs` role-bias, `RegisterAsset` routing,
  provider registration) — real, separable scope, not folded into this pass.

## Review pass — 4 fixes before this gets hosted-tested

The first generalization pass above shipped with four real problems, caught
in review before any hosted test (not caught by tracing the code myself the
first time — worth being honest about that).

1. **`_airCAS` was undercounting HAL's real air pool**, which is the *worse*
   failure direction than it sounds: `RYD_Dispatcher` doesn't just read
   `RydHQ_RCAS + RydHQ_BAirG`, it also folds eligible general-purpose
   `RydHQ_AirG` (minus crew/ammo-drop/non-combat exclusions) into both
   `airCAS` and `airCAP` (`HAC_fnc.sqf` ~1354-1362). Reading only the two
   dedicated pools meant this file could see "no CAS available" while HAL
   genuinely had usable attack aircraft sitting in `AirG`, and buy another
   one it didn't need. Fixed with one shared helper
   (`ITW_CLASH_HALThreatCoverage_fnc_EffectiveAirPools`) that reproduces the
   exact merge, used everywhere `airCAS`/`airCAP` are read in this file
   instead of duplicating it inline.
2. **The `Air`/`AIRCAP` check ignored a legitimate existing HAL responder.**
   HAL's real `"Air"` pool is `airCAP + AAInfG` — two alternatives, not one.
   The first pass checked `RydHQ_RCAP` alone; if AA infantry existed and was
   healthy, HAL already had a real answer, but this file would still buy an
   aircraft. The `ITW_CLASH_InfantryDemand.sqf` comment ("AAInfG is covered
   by InfantryDemand already") was answering a different question —
   *replenishing* missing AA infantry isn't the same as *checking whether
   currently-existing* AA infantry already covers the threat. Fixed: now
   requires both `RydHQ_RCAP` and `RydHQ_AAInfG` to be simultaneously
   unusable before requesting anything.
3. **The deepest one: this was a force-diversity maintainer, not a
   "HAL can't cover this" detector.** The generalized table checked ground
   and air *independently* per category and bought whichever was missing —
   meaning any category whose real pool contains both modalities (`Inf`,
   `Armor`, `Cars`, `Art`, `Static`) would demand both be represented at all
   times. A single enemy rifle squad with 6 healthy friendly infantry squads,
   2 sniper teams, and 0 aircraft would still trigger a `CAS_AIRCRAFT`
   purchase, because "air" specifically was empty — even though HAL already
   had a completely legitimate ground answer. That's not "replenish what
   HAL can't cover," it's "keep every response modality topped up," and
   those spend very differently. Rebuilt around the correct question: does
   HAL have *any* usable responder among the buckets this category's real
   `RYD_Dispatcher` pool actually contains? If yes, don't spend at all. Only
   when every relevant bucket is genuinely empty does it request *one*
   capability — for every dual-bucket category that's `CAS_AIRCRAFT`, not
   arbitrarily: `RYD_Dispatcher` weights the `AIR` entry highest (2) in
   every single one of `Inf`/`Armor`/`Cars`/`Art`/`Static`'s real pools, so
   that's the doctrinally-justified pick, not a coin flip.
4. **`UsableGroups` was looser than HAL's actual definition of usable**,
   which is the opposite failure direction from #1/#3 — under-provisioning
   instead of over-purchasing. `alive`/`!Busy`/`!Unable` alone would count a
   dry, non-`AttackAv`, or immobilized group as "coverage," making this file
   think a threat was already answered when HAL genuinely couldn't field
   anything. Added `RydHQ_AttackAv` membership, a real ammo check
   (`RYD_AmmoCount`, the same check `RYD_Dispatcher` itself uses before
   committing a responder), and a movability check for mounted groups.
   Deliberately *not* reproducing `RYD_Dispatcher`'s full stochastic terrain/
   weather/resignation scoring — that's excess fidelity for what this file
   needs to decide, not a shortcut taken by accident.

## A repo-state note that applies to this entire arc, not just this file

Every change across this whole session — the addon, `HALLogistics`-adjacent
files, `ForceGeneration.sqf`'s two new capabilities, `InfantryDemand.sqf`,
this file — was made against a local extraction of the zip uploaded at the
start of the conversation, not against any git-tracked copy of
`opfor-fob-logic`. There was never git or repo access this session; every
file was delivered individually for manual application. If the branch
doesn't yet show these changes, that's why — not a sync issue, a workflow
gap that should have been surfaced explicitly much earlier than it was. This
doc describes the state of the delivered files, not the state of any
particular branch, until someone reconciles the two.

## Checkbook arc — where this leaves things

Closing this arc here, per plan. State of the world:

- **Tactical response** (`CLASH HAL Additions` addon): HAL actively answers
  14 of ~15 populated threat categories (`Other` is dead code in HAL itself,
  never populated — not a gap on our side).
- **Budget piping** (`ITW_CLASH_HALThreatCoverage.sqf`): 12 of those 14 can
  now trigger a Checkbook request when HAL's own pools can't cover them
  (`Recon`/`Naval` excluded, reasons above).
- **Vehicle fulfillment** (`ITW_CLASH_ForceGeneration.sqf`): two capabilities,
  `GROUND_ATTACK_LIGHT` (Apc+Car, Attack/Dual roles) and `CAS_AIRCRAFT`
  (Plane+Heli, Attack/Dual roles, registers into RCAS+RCAP+AirG), both
  correctly billed against Impasse's real ticket economy and correctly
  registered into HAL with the right constraints cleared.
- **Infantry fulfillment** (`ITW_CLASH_InfantryDemand.sqf`): no spend, no
  spawn authority ceded — a one-shot advisory nudge on which existing
  `CfgGroups` squad template Impasse picks next, scored against HAL's own
  live role vocabulary.
- **Everything in this arc is unvalidated in a hosted session.** That's the
  one item that applies to all of it, not just one file, and it's the
  natural next step whenever that's picked back up — probably before any
  further extension (Naval, Recon, tuning the first-pass numbers scattered
  through this doc), since a real playtest is likely to surface something
  none of the code-tracing here would have caught.
