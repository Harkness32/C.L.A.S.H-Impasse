# Austerity reward HUD

Hark, 2026-10-31: "I'd like to have their point rewards pop up as a plus and a
money tab in the bottom right." Built from concept A on the CLASH Reward HUD
canvas, with the centre-screen text kept small so it never covers anything a
player needs.

## What the player sees

- **The money tab**, bottom right: `CASH $4,250` on a dark panel with an ochre
  top edge. It appears on the first answer from the server. On a reward the
  balance counts up, the amount shows above the tab and the edge lights gold.
- **A kill**: `+25 RIFLEMAN` just under the crosshair, 2.9% of the screen height
  (3.6% for 500 or more). Older ones step down and fade; at most three show.
- **A finished job**: `TASK COMPLETE` over `+1,500`, a quarter of the way down
  the screen, 4.9% of the screen height. Every job reads the same, whatever it
  was (Hark: "it should only say Task Complete").

## Who owns what

| file | job |
|---|---|
| `ITW_CLASH_Austerity.sqf` | Server. Holds every player's cash and pays it. |
| `ITW_CLASH_AusterityClient.sqf` | Client. Draws what the server sends and decides nothing. |
| `dialogs.hpp` | `ITW_CLASH_RewardHud` (the tab) and `ITW_CLASH_RewardPopup` (one popup). |

Set `ITW_CLASH_AusterityEnabled = false` before the server file loads and
nothing is paid and no HUD appears.

## What it pays

These are the draft prices from the 2026-10-27 brainstorm, and they are
untested in play. Every number is a variable at the top of
`ITW_CLASH_Austerity.sqf`.

Jobs pay a flat bonus on completion to everyone on the job, never per head:

| job | bonus |
|---|---|
| Rescue (CSAR or MEDEVAC) | 1,500 |
| Transport | 1,000 |
| Ammo sling | 500 |
| Recon | 300 |
| Artillery | 100 |
| Strike | half the kill's bounty, on top of the bounty: 450 heavy, 190 light, 60 soft |

Kill bounties go to the player who made the kill, or to the commander of an AI
gunner:

| target | bounty | source |
|---|---|---|
| Man | 25 | draft |
| Car | 120 | draft |
| APC, and tracked vehicles filed as neither tank nor APC | 375 | 10% of the draft APC price |
| Tank | 900 | draft |
| Helicopter | 500 | placeholder |
| Plane | 900 | placeholder |
| Static weapon | 60 | placeholder |
| Boat | 120 | placeholder |

A vehicle with nobody aboard pays nothing, because it belongs to no side. So
does anything on the player's side.

## Not done

- **Nothing spends this money.** The base store keeps its own wallet, per side
  and switched off.
- **The wallet is per player, for the session.** Whose money it is (player, squad
  or side) is still undecided; this follows the August proof of concept.
- **No HOT corridor bonus.** The ×1.5 from the draft is not paid or shown yet.
- **Vehicle crews pay as well as the vehicle,** so a tank kill can show the tank
  and each crewman.
