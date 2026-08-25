# Player Artillery Tasking V1 Certification

Run on a dedicated server with at least two player clients, both HAL commanders,
valid front/rear generation nodes, one player-garage artillery vehicle, one AI
artillery battery, and RPT logging enabled.

Use the commit SHA under test in the RPT archive name.

## 1. Boot

Pass criteria:

- existing player-task, garage, force-generation, and dual-HAL modules start;
- RPT contains player-artillery-tasks-ready;
- boot summary reports playerArtillery=true;
- no undefined-variable, type, remote-execution, or script errors reference the
  new module;
- both HAL commanders continue to initialize exactly once.

## 2. Garage provenance and deployment

1. Spawn/purchase artillery through the player garage.
2. Do not board it.
3. Confirm it remains pending and cannot advertise as a provider.
4. Board it and allow deployment.

Pass criteria:

- the vehicle moves to the existing interstitial artillery generation zone;
- state becomes DEPLOYED;
- ITW_CLASH_PlayerGarageAsset and owner UID are public on the vehicle;
- the vehicle is outside the rear sanctuary;
- an editor-placed copy of the same class remains ineligible.

## 3. Opt-in boundary

1. Operate the deployed artillery with HAL tasking disabled.
2. Permit HAL to discover a valid enemy target.
3. Enable HAL tasking through the native context action.

Pass criteria:

- disabled player artillery never receives a mission;
- HAL never issues doArtilleryFire to the human battery;
- enabling the native toggle makes the battery eligible without granting High
  Command;
- only the garage-tagged, deployed asset is accepted.

## 4. Successful HE mission

1. Let HAL select an enemy from its known-enemy set.
2. Accept the assigned mission.
3. Fire exactly the ordered HE salvo at the marked area.

Pass criteria:

- target originates from RYD_CFF_TGT;
- range/ammunition validation uses native RYD_ArtyMission;
- player chooses the firing position;
- the first authorized shot changes the job to ACTIVE;
- every authorized projectile produces one resolved report;
- the complete salvo and required impact ratio produce one
  ARTILLERY_MISSION_COMPLETED;
- the locked group roster is preserved;
- task becomes SUCCEEDED;
- group and battery busy flags clear;
- no economy payout occurs.

## 5. Inaccurate mission

Fire the complete authorized salvo outside the target radius.

Pass criteria:

- impacts are recorded as off-target;
- the mission becomes FAILED after the full salvo resolves;
- no completion event is emitted;
- provider busy state clears.

## 6. Excess and wrong ammunition

Test separately:

- fire more than the authorized number of HE rounds;
- fire smoke, illumination, or another unapproved magazine.

Pass criteria:

- extra HE produces ARTILLERY_ROUND_EXCESS and does not advance completion;
- unapproved ammunition is ignored by the mission observer;
- no per-round or per-kill reward seam is emitted.

## 7. Cancellation and loss

Test separately:

- use HAL's native Deny action before firing;
- destroy the artillery vehicle while assigned;
- disconnect all locked participants;
- allow the mission to time out.

Pass criteria:

- Deny produces CANCELED;
- vehicle/provider loss and timeout produce FAILED;
- client event handlers are removed;
- HAL/group/battery busy flags clear;
- the AI artillery path remains available afterward.

## 8. Danger close

Cause HAL's selected target to be inside the configured friendly exclusion
radius.

Pass criteria:

- no player mission is created;
- RPT contains danger-close-denied;
- V1 never silently authorizes danger-close fire;
- native AI behavior may continue only through the untouched AI battery path.

## 9. AI fallback

Test with:

- player opted out;
- player busy;
- player vehicle outside range;
- player vehicle out of ammunition;
- no player artillery present.

Pass criteria:

- human groups are removed from native RYD_CFF;
- eligible AI batteries still fire through native RYD_CFF_FFE;
- no player-task failure blocks later AI missions;
- enemy-side AI artillery remains behaviorally symmetric.

## 10. Interdiction evidence

Observe the first authorized player round.

Pass criteria:

- ARTILLERY_FIRING_POSITION_EMITTED is recorded once;
- firing vehicle receives ITW_CLASH_ArtilleryEmission;
- the event does not directly modify enemy RydHQ_EnArtG, known-enemy lists, or
  SOF targets;
- enemy action still requires ordinary reconnaissance/knowledge.

## 11. Multi-crew and locality

1. Use separate player driver and gunner.
2. Change vehicle locality by exchanging driver seats before the mission.

Pass criteria:

- exactly one local Fired observer is active at a time;
- caller validation accepts a locked participant in the assigned crew;
- shots are not duplicated across clients;
- clearing the job removes the observer on the owning client.

## RPT acceptance gate

The branch passes only if:

- every job ID reaches exactly one terminal state;
- every shot ID is accepted at most once;
- player weapons are never fired by HAL;
- AI artillery remains native;
- no task is created from enemy omniscience or garage purchase knowledge;
- no repeated assignment storm occurs;
- no Supremacy currency or payout code exists in this patch.
