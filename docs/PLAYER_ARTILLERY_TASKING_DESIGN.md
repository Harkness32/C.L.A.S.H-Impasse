# Player Artillery Tasking V1

## Decision

C.L.A.S.H. allows an opted-in player group operating a deployed, player-garage
artillery asset to fulfill an automatic HAL fire mission.

- **HAL** owns reconnaissance, threat evaluation, target selection, and the
  decision that a fire mission is required.
- **C.L.A.S.H.** removes human batteries from HAL's direct-fire executor,
  validates the human provider, creates the player task, and audits the result.
- **ITW** remains responsible for the garage asset and its generation/deployment
  geography.
- **The player** chooses the firing position, aims the weapon, and fires every
  round.

The feature is mode-neutral. It records completion events but awards no money.
Supremacy therefore receives the task without economic behavior. A later
economic mode may consume the completion event.

## HAL hook

NR6 HAL's automatic artillery path is:

1. RYD_CFF receives HAL's artillery pool, known enemies, friendly groups, and
   commander.
2. RYD_CFF_TGT chooses a target from HAL's known-enemy state.
3. RYD_ArtyMission validates ammunition and range and chooses a battery.
4. RYD_CFF_FFE ultimately issues doArtilleryFire.

C.L.A.S.H. wraps RYD_CFF.

- Human groups are always removed from the arguments passed to native
  RYD_CFF; HAL can never directly operate a player weapon.
- If an eligible human battery exists, HAL's own RYD_CFF_TGT selects the
  target.
- Native RYD_ArtyMission is called against one eligible human group to
  validate range, ammunition type, and available round count.
- C.L.A.S.H. converts the approved result into a human task.
- If no human provider can fulfill the mission, native RYD_CFF receives the
  remaining AI batteries and behaves normally.

This is a hook, not a parallel artillery commander.

## Eligibility contract

A player artillery provider must satisfy every condition:

- the group used HAL's native task opt-in;
- the group is not Unable, lifecycle-reserved, HAL-busy, or already assigned;
- at least one player occupies a gunner seat;
- the vehicle advertises Artillery support and has usable artillery magazines;
- the vehicle carries the server-visible ITW_CLASH_PlayerGarageAsset flag;
- garage deployment state is DEPLOYED; and
- the vehicle is outside the resolved rear-generation sanctuary.

An editor-placed gun, stolen AI battery, or untagged vehicle is not a paid player
provider. This preserves the garage-capital contract.

## Fire-mission state

ASSIGNED -> ACTIVE -> COMPLETED

Failure branches:

- player denies the task: CANCELED;
- vehicle/provider is lost: FAILED;
- no authorized salvo is completed before timeout: FAILED;
- too few impacts land inside the target area: FAILED.

Assignment locks:

- player group;
- participant UID/name roster;
- artillery vehicle;
- HAL target position;
- accepted artillery magazine classes;
- authorized round count;
- completion radius and required impact count.

The group and battery are marked busy until the task reaches a terminal state.

## V1 fire policy

V1 supports **HE only**.

- HAL provides a fixed target point from its current reconnaissance state.
- Danger-close targets are rejected when living friendly units are within the
  configured exclusion radius.
- The player receives no movement waypoint and may choose any legal firing
  position outside the rear sanctuary.
- The authorized salvo is capped even if HAL or a vehicle advertises a larger
  amount.
- Completion requires the full authorized salvo to resolve and at least the
  configured fraction of impacts to fall within the target radius.
- Extra rounds are recorded but never advance completion or future payment.

Smoke, illumination, guided ammunition, counter-battery, and explicit
danger-close authorization are later mission classes, not silent V1 fallbacks.

## Impact observation

The player client that owns the artillery vehicle installs a local Fired
handler for the assigned job.

1. The handler accepts only the locked vehicle and magazines.
2. The firing report activates the task and records the firing position.
3. The client follows the projectile until it terminates and reports the last
   observed position.
4. The server validates caller ownership, locked participant UID, vehicle,
   magazine, shot identifier, and authorized round count.
5. The server decides whether the impact is inside the HAL target area.

The completion authority remains server-side. Client reports are treated as
observations and cannot change a job outside its locked contract.

## Interdiction seam

The first authorized round emits:

ARTILLERY_FIRING_POSITION_EMITTED

and sets ITW_CLASH_ArtilleryEmission on the firing vehicle.

This does **not** reveal the battery to the enemy or inject it into enemy HAL
knowledge. It is an auditable evidence seam for a later counter-battery/SOF
interdiction layer, which must still apply enemy reconnaissance and knowledge
rules.

## Completion event

Successful validation publishes:

ARTILLERY_MISSION_COMPLETED

The payload contains the immutable participants, provider, target, ammunition,
authorized rounds, resolved rounds, on-target impacts, and outcome.

- Supremacy has no consumer and performs no payout.
- The economic mode may later pay the locked roster once per mission ID.
- Payment must never be calculated per shell or per kill.

## Configuration

| Variable | Default | Purpose |
|---|---:|---|
| ITW_CLASH_PlayerArtilleryMissionRadius | 200 m | Authorized impact area |
| ITW_CLASH_PlayerArtilleryDangerCloseRadius | 300 m | V1 friendly exclusion |
| ITW_CLASH_PlayerArtilleryTaskTimeout | 900 s | Assignment timeout |
| ITW_CLASH_PlayerArtilleryMaxRounds | 8 | Maximum ordered salvo |
| ITW_CLASH_PlayerArtilleryImpactRatio | 0.67 | Required on-target fraction |

## Fail-open behavior

- A missing or failed player provider falls back to HAL's native AI battery
  path.
- AI-only batteries always use native RYD_CFF.
- Human batteries are never passed to native RYD_CFF, including when opted
  out, preventing involuntary player fire control.
- The wrapper does not create enemy knowledge, change target priorities, choose
  firing positions, or debit ITW resources.
