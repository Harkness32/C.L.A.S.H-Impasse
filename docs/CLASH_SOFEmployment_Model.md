# C.L.A.S.H. SOF Employment Model (v1 proposal)

> Special forces are the only formation C.L.A.S.H. and Impasse both decline to
> employ. This document says why that happened, what to give them instead, and
> in what order to build it.

Status: proposal, partly built. Shipped: the raid threshold in §2.3
(`ITW_CLASH_HALNativeSFFix.sqf` v6) and the JTAC in §5 and §6.1
(`ITW_CLASH_SupportsJTAC.sqf` v1, supports v10).

---

## 1. Why this was proposed

SOF in this mission are not underpowered or badly tuned. They are **structurally
idle**, because three exclusions stack, and each one was reasonable on its own.

### 1.1 The three exclusions

**HAL withholds them.** `RydHQ_SpecForG` is HAL's own list, built inside
`HAC_fnc2.sqf:485` from HAL's `_SpecForcheck` and republished at `:545`.
Membership withholds a group from HAL's attack, defense, capture and reserve
tasking, applies `_cowF - 0.8` against conventional use (`HAC_fnc2.sqf:875`),
and subtracts it from the infantry pool at `TaskInitNR6.sqf:353`.

**C.L.A.S.H. bars them from ground.** `ITW_CLASH_SOFDoctrine.sqf` wraps
`ITW_CLASH_fnc_SelectAnchorGroup` and `ITW_CLASH_fnc_AuditAnchors` so a
positively identified SOF formation is never eligible for an objective anchor,
and an existing SOF anchor is demoted. This is deliberate doctrine:
conventional infantry holds ground, SOF screens and raids.

**Their one native mission cannot find a target.** HAL's SF raid routine aims
at enemy commanders. Both commanders in this mission are ghosts:

| | BLUFOR | OPFOR |
| --- | --- | --- |
| created | `ITW_CLASH_DualHALCheckbook.sqf:530` | `ITW_CLASH.sqf:2807` |
| class | `B_officer_F` at `ITW_Bases#0` | officer at a held objective |
| damage | `allowDamage false` | `allowDamage false`, `itw_dmgBlocked` |
| visible | `hideObjectGlobal true` | `hideObjectGlobal true` |
| simulated | `enableSimulationGlobal false` | `enableSimulationGlobal false` |

`RydHQInit.sqf:233` and `:246` put both into `RydxHQ_AllLeaders`, so the raid
loop does iterate them — but a target is only accepted if its group is in
`_knownEG`, which `HAC_fnc2.sqf:265` builds from `knowsAbout >= 0.05`. Nothing
ever knows about an invisible, unsimulated officer at a rear base.

So the commander target list is always empty and HAL takes its own fallbacks:
artillery at half chance, then statics at a third. **HAL's entire
commander-decapitation layer is inert here by construction**, and the same is
true of the `_HQFactor = 20` weighting those leaders carry at
`HAC_fnc.sqf:2624`.

### 1.2 Neither parent system will adopt them

HAL's SOF semantics are about the enemy's command, which C.L.A.S.H. removed as
a target on purpose so a lucky patrol cannot end a campaign. Impasse has no SOF
concept at all — it generates squads and takes places.

`docs/OWNERSHIP_CONTRACT.md` already names the gap: C.L.A.S.H. owns
*"compatibility and lifecycle state neither system natively understands."*
SOF employment is exactly that, and it has no owner today.

### 1.3 What the caps are, and are not

`ITW_CLASH_SOFMaxShare` (0.25) and `ITW_CLASH_SOFMinTeams` (4) are **not a
reserve**. They are read in one place, `ITW_CLASH_SOF_fnc_SideSlot`, to compute
a permission ceiling:

```sqf
_cap = (ITW_CLASH_SOFMinTeams max (floor (ITW_CLASH_SOFMaxShare * _total)))
       min (floor (_total / 2));
```

A group that looks like SOF with no slot free is set `_isSOF = false`, logged
`sof-doctrine-held-conventional`, and fights as line infantry. Nothing is
spawned and nothing is held back. `SOFMinTeams` only raises the ceiling on
forces under about 16 groups, so a smaller side can still accumulate the four
teams HAL's raid arithmetic wants.

Consequence for planning: **scrubbing `SOFMinTeams` frees no units.** It lowers
how many groups wear SOF identity, which makes more of them anchor-eligible and
conventionally tasked, and makes HAL raids rarer rather than more common.

---

## 2. HAL's raid arithmetic, for the record

### 2.1 The gate

`RYD_StatusQuo`, `HAC_fnc2.sqf:1165-1251`:

```
entry:   ((Circumspection + Fineness)/2 + 0.1) > random 1.2     // 50% at 0.5/0.5
count:   _SFcount = free SOF (not Busy/Unable/Resting) - RydHQ_SFBodyGuard
chance:  40 + 60*Activity                                        // 70 at 0.5
         halved if no known enemy commander (artillery targets)
         thirded if only statics
         +25 at night
         + ((2 * _SFcount) - 8/(0.75 + Recklessness/2)) * 20
         / (1 + times this target was already raided)
         clamped to [_SFcount, 85 + _SFcount]
roll:    random 100 < _chance
```

### 2.2 What that means

At the stock Recklessness of 0.5 the subtrahend is exactly 8, so the team term
is zero at four free teams and −120 at one:

| free teams | team term | chance, day, commander target |
| --- | --- | --- |
| 1 | −120 | clamped to 1 → ~1% |
| 2 | −80 | ~2% |
| 3 | −40 | 30% |
| 4 | 0 | 70% |
| 5 | +40 | 85+ |

Four teams is the real threshold, and it is **arithmetic, not a setting**.
`RydHQ_Recklessness` shifts the break-even only from 4.0 to 3.2 across its whole
0–1 range, and it steers 65 other HAL decisions including whether SF will engage
an armour target at all on the line after the roll.

### 2.3 What shipped

`ITW_CLASH_HALNativeSFFix.sqf` v6 adds a fifth all-or-none source edit to the
`RYD_StatusQuo` patch list:

```
"(8/(0.75 + ((_HQ getVariable [""RydHQ_Recklessness"",0.5])/2)))"
  →  "(2 * ITW_CLASH_SOFRaidTeams)"
```

`ITW_CLASH_SOFRaidTeams` defaults to 1: the penalty is zero as soon as one team
is free, extra teams are still worth +40 each, and launching marks the team Busy
so concurrency throttles itself. The boot line prints `raidTeamThreshold=`.

Note the ceiling this does **not** lift: with commanders unreachable, HAL still
halves the chance for artillery targets and thirds it for statics.

---

## 3. The model

> SOF are the only formation that changes what the commander can **see and
> buy**, rather than only what dies.

Everything in the C.L.A.S.H. decision stack runs on contacts.
`ITW_CLASH_Knowledge.sqf` builds them from `RydHQ_KnEnemies`; COLOSSUS and the
supports cluster and classify them; the strike flavors weight them by class;
the air threat overlay draws only what was perceived. It is a real intelligence
economy with prices, uncertainty and decay.

It has exactly one deliberate supplier: the UAV support. Everything else is
HAL's units happening to look at things.

SOF are the one formation that could mint that currency on purpose — on foot, in
cover, persistent, where a UAV is shot down and sees nothing under trees. That
is the role: **the ground sensor and the precision ground effector of the
knowledge economy.** The anchor exclusion stops being a restriction and becomes
the reason they are free to do it.

### 3.1 Authority

- **C.L.A.S.H. owns SOF employment.** It is the third decider alongside HAL's
  tasking and the supports' proposals, for the reason in §1.2.
- **HAL still owns everything it owns now.** Its native raid routine is left in
  place; this model does not replace it, and does not require it to work.
- **The siting decision is C.L.A.S.H.'s. The shot is the AI's.** See §4.1.
- **A team under a C.L.A.S.H. task is lifecycle-reserved**, the way a CASEVAC,
  a reconstitution transit and a CSAR crew are, so HAL cannot retask it
  mid-mission.
- **Nothing here spawns SOF.** Identity is detected from the spawn archetype and
  config; teams come from the faction's own order of battle, or from a
  deliberate purchase (§6.2), never from this module.

### 3.2 The one lesson that shapes everything

`ITW_CLASH_HeliAttack.sqf` v5, after the second 2026-10-17 run:

> every point-at came nose on and none fired, **0 shots in 25 aims (0 in 32
> since v3)** … an assigned target the crew has not seen is one it will not fire
> at, and the order kept it from switching to one it could.

Its conclusion: *"The crew chooses again. Nothing here assigns or watches a
target … A reveal still tells the crew where to look, but is never a target."*

**Therefore: C.L.A.S.H. controls position, briefs with `reveal`, and never
assigns a target.** This applies to an AT team on a hill exactly as it applied
to a Ghost Hawk, and it is why §4 is about siting rather than about shooting.

---

## 4. Behaviours

### 4.1 Overwatch — one behaviour, two postures

Both postures are *occupy ground with line of sight to X and stay there*. They
differ only in engagement rules and in what success means.

**Recon Overwatch.** Combat mode BLUE, `enableAttack false`, prone, sited far
enough back that a patrol does not trip over it. Success is **contacts**: the
team's own `knowsAbout` flows into `RydHQ_KnEnemies` and the clusters that
COLOSSUS and the strike flavors have been starving for start to exist. A recon
team in a firefight has stopped producing the thing it was sent for.

**AT Overwatch.** Sited within AT reach of an armour axis with real line of
sight. Briefed with `reveal`, never assigned a target. Success is armour killed
or deterred.

Explicitly **not** required in v1:

- *Displacement after firing.* An airframe gets an off-ramp because it is
  expensive and reusable; a two-man team is neither. When the launchers are dry
  the team is infantry on a hill with eyes, which is the recon posture — the
  behaviour degrades into the other one for free.
- *Ammunition as a balance lever.* Two missiles that kill two tanks is a good
  trade and should be allowed to be one. The team is cheap to kill if the enemy
  finds it, and finding it is the enemy's problem.

The failure mode worth engineering against is not fragility. It is **never
getting to shoot**, which is what `HeliAttack` measured. Log shots and kills per
post from day one, so a post that fires nothing reads as a siting problem rather
than bad luck.

### 4.2 JTAC — terminal control

The supports model admits its own limitation:
`ITW_CLASH_SupportsAcquireFlavors = ["BOMB","GUIDED"]`, *"the strike flavors
whose jet acquires its own target on site. The report brings them to the area
and sizes the scan; it is not the aim."*

A JTAC is the only thing that can change that premise, and `reveal` is already
sanctioned for exactly this case. `ITW_CLASH_HALThreatCoverage_fnc_Brief` uses
level 2 because it is *"the same brief a group would get for standing near the
contact"* — which is literally what a controller with eyes on is.

JTAC behaviours, in build order of value:

1. **Terminal control.** Reveal the cluster to the inbound crew and keep
   refreshing while the flight runs in, because knowledge decays.
2. **Keep the contact warm.** Staleness is modelled everywhere. A controller on
   station means the pass arrives at where the target *is*, and unlocks the
   flavors that refuse stale reports.
3. **Danger close.** The friendly footprint is 50 m (bomb, guided) and 60 m
   (carpet) plus a larger `DangerMargin` when a player is near. A controller on
   station is grounds for reducing that margin — a *permission*, not a damage
   bonus.
4. **Battle damage assessment.** Nothing confirms a strike worked; the contact
   decays and COLOSSUS may pay to re-kill wreckage. A controller calling it dead
   can feed `Supports_fnc_Exclude`, which the UAV killbox already uses.
5. **Laser designation.** The authentic version, and the last one. There is no
   laser mechanic anywhere in the mission today; AI behaviour against a spot
   depends on LGB carriage, continuous designation and pilot willingness, and
   that costs a live run to learn.

### 4.3 Counter-battery hunt

`ITW_CLASH_CounterBattery.sqf` earns a side a fix the honest way — by being
shelled within 400 m of its own people — with an error radius that tightens from
450 m to 120 m over four observed rounds and a 900 s fix life. Its own words:
*"a fix is deliberately a lead rather than a target — what consumes it decides
what to do about it. It observes and publishes. It never tasks, fires or buys
anything."*

Nothing consumes it. Meanwhile `ITW_CLASH_ArtilleryScoot.sqf` moves every gun
after six rounds, 250–600 m, specifically so *"a battery that displaces leaves a
stale fix behind."*

A team sent to the error box is the third party: the lead becomes an observed
contact, the scoot no longer defeats it, and the battery dies to the team or to
a guided pass. **Shelled → fix → team → contact → silence**, across four systems
that already exist.

### 4.4 Air defence hunt

Killing an SPAA or a MANPADS team changes `Supports_fnc_CorridorFactor` and
re-opens a corridor for friendly air, including CSAR.

Note the payoff is **felt, not seen**: `docs/AIR_THREAT_OVERLAY.md` deliberately
does not erase a marker when the server learns the hull died, because that would
leak unobserved kills. The ellipse expires on its own.

### 4.5 Player-facing

- A requested post ("eyes on that ridge") through the existing player task
  request channel.
- **Insertion as a TRANSPORT job**: carry a named team to a named post. A better
  job than ferrying a generic squad, because the player knows what the team is
  for and will see the consequence on their own map.

---

## 5. JTAC limits

The agreed position, and the reasoning, so it is not re-litigated.

### 5.1 Uncapped per team, because myopic

COLOSSUS picks from every cluster the side knows about across every objective's
influence area; uncapped it would strike continuously and forever, which is why
its supports are priced. A JTAC picks from one cone of terrain. Its scarcity is
already in the world rather than in the ledger, and charging money on top
double-counts the same constraint.

A JTAC also **consumes its own pool**: strike the battery it watches and the
cone is empty until it displaces. COLOSSUS never runs out of targets.

**These are one decision, not two: uncapped *because* myopic.** The uncap is
justified exactly as far as the sight gate is strict, so the two must be written
and reviewed together.

### 5.2 Its own clock, its own lane (decided 2026-10-27)

Hark: COLOSSUS is the supreme commander and calls supports from the whole
picture; a JTAC is a team on the ground calling what it sees. **A split, not one
pool.** The JTAC is strike only (bomb and guided), never generates or directs
forces, and runs on its own clock: **one call per side every 10 minutes**,
shared by every team of that side. COLOSSUS keeps its own pacing (per-flavor
cooldowns and the wallets), untouched.

- **Its own lane (`JTAC`).** A JTAC call never waits on a COLOSSUS strike and
  never blocks one. The cost is that two jets can be over one area at once.
- **No COLOSSUS cooldowns either way.** It neither reads nor starts the flavor
  cooldowns, and a JTAC call has no objective, so the 180 s per-objective
  cooldown is not started: a JTAC call never locks COLOSSUS off a point.
- **Free.** A `FREE` wallet that holds and costs nothing.

At this cadence extra teams buy **coverage, not throughput**: they make it
likelier that something worth the one call is in view when the clock opens. A
team that cannot call is still working; its contacts are what let the
commander's own strikes find anything.

### 5.3 The best option wins

Each poll the JTAC looks at every cluster a settled team can see and takes the
best option outright, by class weight × the cluster's worth × the corridor.
With one call in ten minutes, teams compete on target quality: a team watching
a battery beats a team watching a parked truck.

### 5.4 Limits kept

- **`fighterRule` (`ANY_AA_MISSILE`).** The jet will not enter a live missile
  envelope whoever called it. This keeps the AA-hunt role (§4.4) meaningful.
- **The target gates.** `BELOW_FLOOR` (worth 1.5, the acquiring floor),
  `NO_CONTACT` (bomb needs OBSERVED or FIXED) and `ETB_ANSWERING`. Free calls still cannot bomb one
  rifleman, and each refusal is counted in `supports-jtac-held`.
- **A settling period.** A team must hold its ground (within 50 m) for 60 s
  before it can call, so it cannot crest a ridge and call at once.
- **Danger close at 150 m (decided 2026-10-27).** A controller with eyes on is
  the reason a strike may come closer: a JTAC's call has one margin past the
  footprint, `ITW_CLASH_SupportsDangerMarginJTAC` (150 m), for every flavor and
  every friendly, players included, at every check from the call to the last
  release check. The same day COLOSSUS's bomb and guided passes moved to one
  150 m margin too (`ITW_CLASH_SupportsDangerMarginPrecision`); only the carpet
  keeps 300 m (500 m from a player). A bomb may now land 200 m from a player.
- **Eyes at launch.** Before the jet spawns, the core asks the calling team again
  whether it still sees the target; if not, the call is revoked (`NO_SIGHT`).

Not yet built: **billing on airframe loss** (calling is free; losing the jet
should be charged to the main bank, or the uncap removes the only consequence
for calling into AA), and the **terminal-control reveal** while the jet runs in.

### 5.5 The invariant that holds the balance up

> A JTAC may change a contact's **status, position and age**. It may never
> change a cluster's **count or worth**, and it may only ever reveal what it can
> itself see.

Status matters because promoting a contact to `OBSERVED` satisfies bomb's
`NO_CONTACT` gate. Worth matters because `fnc_Cluster` sums worth per member,
and `BELOW_FLOOR` is the gate that actually stops a lone man being struck — it
must stay an exclusion and never become a weight.

The distortion to watch for is the opposite of the obvious one: fresh
observation shrinks `ClusterUncertainty`, which feeds a multiplier, so a
controller parked on a *qualifying but trivial* target could out-compete a
valuable one whose report has gone stale. If that shows up in a run, let worth
dominate freshness in the weighting rather than touching the floors.

---

## 6. Execution

### 6.1 JTAC (built: `ITW_CLASH_SupportsJTAC.sqf` v1, supports v10)

**Its own routine, like bite-back.** A poll every 10 s per side, outside
COLOSSUS's 60 s assessment. When the side's JTAC clock and lane are free, it
clusters every contact within range of a settled controller, keeps the
clusters a controller can see, runs the strike pipeline's own gates on each
(bomb, guided), and admits the best through `Supports_fnc_Admit` with its own
lane (`JTAC`), the `FREE` wallet and the calling team. The strike itself is the
existing executor: the jet acquires on site as every bomb and guided pass does.

**Controllers** are groups on HAL's own `RydHQ_SpecForG` list (the recon
bridge adds C.L.A.S.H.'s SOF to it), with a living leader on foot, not
withdrawing, settled for 60 s.

**The sight test**, cheapest first:

1. the reported position within 2000 m of the controller's leader
2. the team's **own** sighting of a member, no older than 30 s: its own men's
   `targetKnowledge`, never the commander's or another group's report, and a
   revealed-but-unseen target does not count
3. `terrainIntersectASL`, then `lineIntersectsSurfaces` (VIEW), from the leader's
   eyes to where the team saw it

A cluster no team sees reports how close any came: `out-of-range`, `not-seen`
or `no-los`.

Not yet: a lifecycle reservation so HAL cannot retask a controller mid-call
(today a team that leaves revokes at `NO_SIGHT`), the reveal from the poll, and
airframe billing.

### 6.2 What a run should answer

1. `supports-jtac-held`: when the clock is open and nothing is called, why. If
   `not-seen` and `no-los` dominate, teams are not where the enemy is — the
   siting question (§4.1) comes before anything else.
2. `supports-jtac-call`: how often a side calls, from how far, at what. Does the
   best option look like what you would have called?
3. The existing strike outcomes for JTAC ids (lane `JTAC` in `admission`):
   does the pass connect, and how many revoke at `NO_SIGHT`?
4. Then the reveal A/B and airframe billing.

### 6.3 Adjacent tracks, deliberately separate

- **Hunter-killer teams through the Emerging Threats Budget.**
  `ITW_CLASH_Generation_fnc_ETBQualifiesProfile` already defines purchasable
  capabilities proven from config (`GROUND_ANTI_ARMOR`, `ANTI_ARMOR_CAS`,
  `CAP_AIRCRAFT`, `SPAA`), with a class check before the buy and a vehicle check
  after, providers looked up by need, and combat purchases tasked on arrival.
  `ANTI_ARMOR_TEAM` and `MANPADS_TEAM` are two more rows qualified against an
  infantry template. Copy `SPAA`'s discipline exactly — it requires
  `antiAir && !antiArmor`, because *"an IFV with an incidental AA ability does
  not qualify: it is an armor answer HAL would send forward"* — or a team with
  both will be pulled forward as armour cover and lose its AA job. Open question: a
  team has no `vehDef`, so billing and retirement need deciding.
- **Artillery call for fire.** Harder than air, not easier: the only
  `doArtilleryFire` in the mission is in a vendored third-party script, so there
  is no fire-mission seam, and a new one would have to coexist with HAL's own
  artillery tasking, `ArtilleryScoot` and `CounterBattery`. Air first.
- **Reveal-on-call.** A side struck repeatedly should earn a fix on the
  *spotter*, mirroring `CounterBattery`. This is the counterplay that makes an
  enemy JTAC fair and produces the SOF-versus-SOF hunt. Not yet decided.

### 6.4 Ideas considered and dropped

- **Airfield watch.** Support aircraft do not exist until a support runs;
  `airfield: true` only resolves the spawn origin to an owned airfield via
  `ITW_ObjOwnedAirports`. Nothing is parked to observe or bomb, and *owning* the
  strip is conventional capture work that SOF are barred from.
- **Anchor denial.** The anchor slot clears when the anchoring group dies,
  whoever killed it, so this reduces to sending four men at a defended
  objective. No mechanic only SOF can reach.
- **Corridor interdiction.** Reconstitution moves by air lift or spawns forward.
  There is no stream of road traffic to ambush, and an AT team cannot engage a
  transport in flight.

---

## 7. Verification

**Static**, in the house style (`tests/test_supports_jtac.py` for the JTAC):

- the clock is read before any work and started only on admission
- a JTAC pick carries its own lane, the `FREE` wallet and no objective, and
  reads no COLOSSUS gate or cooldown
- the sight test is the team's own `targetKnowledge`, cheapest first, and is
  asked again before the jet spawns (`NO_SIGHT`)
- the target floors are still exclusions, not weights
- nothing in the JTAC assigns, watches or reveals a target

**Live.** The `supports-jtac-held` counts are the tuning instrument: every
refusal is counted by reason, so after one run you count them rather than
guessing.

| dominant reason | what it means |
| --- | --- |
| `not-seen`, `no-los` | teams are not where the enemy is: a siting problem (§4.1) |
| `out-of-range` | the enemy is beyond 2 km of any settled team |
| `BELOW_FLOOR` | teams see only lone riflemen |
| `DANGER_CLOSE` | teams are too close to what they see, or our own troops are in it |

Plus, per post: shots fired and kills, so a post that never fires is diagnosed
rather than mourned.

---

## 8. Open decisions

1. **Scrub `ITW_CLASH_SOFMinTeams`?** It frees no units (§1.3). Setting it to 0
   lowers how many groups wear SOF identity, which makes more of them
   conventionally useful and HAL raids rarer. Decide alongside how many teams
   this model wants reserved for C.L.A.S.H. tasks.
2. **Keep HAL's native raid?** It now fires at one free team (§2.3) but can only
   reach artillery and statics at halved and thirded odds. Keep both and read
   the RPT for which actually fires.
3. **Reveal-on-call**, §6.3.
4. **Does the SOF cap count a bought team?** §6.3.
5. ~~**Danger-close reduction** with a controller on station.~~ Decided
   2026-10-27: 150 m past the footprint for every JTAC call (§5.4).
