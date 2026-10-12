# Hanging helicopters

Status: written 2026-10-11 and 2026-10-12, not flown.

## 1. What was seen

Hark: "very long rpt, tons of helicopters hanging". Run of 2026-10-11 20:23,
mission 2 (20:33 to 23:05), on the build before `213475d`.

Sixteen dual-role helicopters were handed from Impasse to HAL by the field
handoff. HAL gave attack orders to the ones it counts as combat aircraft (the
Ghost Hawks with pylons, the armed Hurons). Eleven never had a waypoint.

| Group | Side | Helicopter | Handed over | Without a waypoint until |
|---|---|---|---|---|
| G242 | enemy | unarmed Ghost Hawk | 21:24 | end of log |
| G304 | BLUFOR | unarmed Ghost Hawk | 21:45 | end of log |
| G379 | enemy | Ghost Hawk, door guns | 22:05 | end of log |
| G252 | BLUFOR | Ghost Hawk, door guns | 21:27 | last logged 22:22 |
| G366 | BLUFOR | unarmed Ghost Hawk | 22:03 | shot down at 48 m, 22:32:56 |
| G461 | enemy | Ghost Hawk, door guns | 22:38 | end of log |
| G504 | BLUFOR | unarmed Ghost Hawk | 22:58 | shot down at 48 m, 23:00:26 |
| G121 | enemy | unarmed Ghost Hawk | 20:53 | shot down at 48 m, 20:55:52 |

The two reconstitution lifts that also hung (G143, G342) are covered by
`docs/RECONSTITUTION_SPAWN_HANDOFF.md`.

## 2. Why

1. `ITW_CLASH_DualHAL_fnc_StageFieldVehicle` moves the aircraft to ground level
   80 to 180 m from the base spawn and gives it no order. Impasse spawned it in
   flight, so the pilot climbs back up and hovers. The three Ghost Hawks lost at
   their staging points were all at 48 m; Hurons were lost at 1 m (11 s after
   staging) and 23 m.
2. The storage lease in `ITW_CLASH_ServiceAuthority.sqf` went only to transport
   deployments: "combat DUAL deployments bypass the lifecycle wrapper
   entirely". Pure transports handed over in the same run were stored about
   four minutes after they arrived (SVC-603477-2, 20:33:42 to 20:38:01).
3. HAL's idle pass leaves out aircraft and non-combat cargo
   (`HQOrders.sqf:494`, `:539`). HAL lands an aircraft only at the end of one of
   its own orders.

## 3. What changed

Hark chose to let HAL decide.

`ITW_CLASH_ServiceAuthority.sqf` v4. After a handoff that was not a transport
deployment, a helicopter's class is checked against HAL's own lists, with the
expression HAL's situation report uses (`HQSitRep.sqf:149`):

- `RHQ_NCAir`, the unarmed subset of `RHQ_Air` (armed means any magazine other
  than flares, `HAC_fnc2.sqf`): non-combat. The crew gets the transport
  doctrine and the transport lease, the same calls a transport deployment gets.
  The lifecycle then stores it after four minutes unclaimed at home and HAL can
  pick it as a carrier meanwhile (the doctrine puts it on `RydHQ_CargoG`).
- `RHQ_Air` only: combat. Nothing changes.
- Neither yet: asked again every 5 s, up to `ITW_CLASH_ServiceAirVerdictWait`
  (600 s).

Log lines: `service-authority-air-verdict-noncombat-leased [group, class, side,
seconds, pool id]`, `-air-verdict-combat`, `-air-verdict-timeout`.

Switch: `ITW_CLASH_ServiceNonCombatAirLease` (default true).

HAL's per-cycle lists (`RydHQ_CombatAv`, `RydHQ_AttackAv`) were not used. They
say who is free this cycle, not what the aircraft is: attack helicopters G119
and G460 first appeared on them 11 and 23 minutes after their handover.

## 4. Door-gun helicopters are transports

Hark, 2026-10-12: "we should strip armed hurons and armed ghosthawks (minus the
stub wing variants) from the dual roles. calling those attack helos is
ridiculous, they can shred a small squad as they insert at BEST." Scope: any
door-gun-only helicopter. Door guns: keep them loaded.

`VehicleArrays.sqf`, Impasse's attack/transport/dual split. Before, any gun,
armed pylon or CAS support entry made a vehicle armed, and armed with enough
seats made it DUAL. Now a helicopter with the seats for either goes to
Transport when:

- nothing at class level fires (no pilot weapons),
- no pylon is armed (stub wings, rocket pods),
- every armed turret is not the copilot's and fires only bullets.

That moves the door-gun Ghost Hawks, the armed Hurons and the unarmed Ghost Hawk
(DUAL in the 2026-10-11 run with flares as its only magazine, so most likely
because its config offers CAS support). The stub-wing Ghost
Hawk keeps an armed pylon and stays DUAL. Attack helicopters are not touched:
the rule only chooses between DUAL and Transport. Both sides, same split. Each
class moved is logged once: `CLASH VEHICLES | door-gun-transport`, and listed in
the boot line `door-gun-transports-ready`.

As transports they take the transport path everywhere: transport doctrine,
the storage lease, stored when idle, picked by HAL as carriers. That also covers
G252, G379 and G461 from the table above.

Impasse empties the magazines of any armed vehicle bought as a transport, at
four places (`ITW_AtkAddVehicle`, the Dual-HAL pre-init wrapper, the hardening
staging wrapper, Checkbook's transport purchase). Each now skips a class on
`ITW_CLASH_DoorGunTransportClasses`, so the door guns stay loaded. CASEVAC and
ground MEDEVAC still disarm whatever they take. The unload owner's run-in flies
CARELESS and BLUE, so gunners hold fire on the drop itself; HAL's own transit
legs fly AWARE.

Switch: `ITW_CLASH_DoorGunHelisAreTransports` (default true).

## 5. Not fixed

- An attack helicopter between tasks still hovers where it is (G119 waited
  11 minutes, G460 15).
- A side whose only DUAL helicopters were door-gun ones now has none. Impasse
  then fills its DUAL helicopter row from fallbacks, the last of which is the
  transport list (`ITW_Ally.sqf`, `ITW_Enemy.sqf`), so door-gun helicopters can
  come back as DUAL there. Not the case in the 2026-10-11 run: both sides had
  the stub-wing Ghost Hawk.
- BLUFOR's staging point at base 3 is within reach of an enemy AA tank: G366,
  G504, the armed Huron G503 and one more Huron were lost within about 150 m
  of [8900,10650].
- No HAL helicopter lift flew after 21:02 in that run. Between 22:35 and 22:49
  the lift dice allowed one squad 26 times and no carrier came. Not
  investigated.
