#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SupportsStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Knowledge_fnc_Contacts") exitWith {
    diag_log "CLASH BOOT | WARNING | supports-knowledge-missing | commander supports not started";
    false
};

ITW_CLASH_SupportsStarted = true;
ITW_CLASH_SupportsVersion = 8;
ITW_CLASH_SupportsReady = false;

/*
    Commander supports: the core. See docs/CLASH_CommanderSupports_Model.md.

    COLOSSUS proposes; this file decides whether a proposal may happen and owns
    everything after that. Each COLOSSUS assessment calls fnc_Assess once per
    side. It builds one pool of options - every flavor that passes the hard
    gates against every eligible target, the recon UAV, airborne insertions,
    and SAVE as an option of its own - and makes one weighted pick. The pick is
    a proposal, not a purchase: admission reruns the gates and reserves the
    money and the lane together in one unscheduled block, so two proposals in
    the same frame can never spend the same cash.

    Ownership, stated so a review can hold the file to it:
      - COLOSSUS never reaches in here; it calls fnc_Assess and that is all.
      - Nothing here orders a HAL group. The airborne executor hands a landed
        squad to its commander through the general registration path and gives
        it exactly one native order, issued the way HAL's own dispatcher issues
        it. That is the only HAL write in the whole support stack.
      - Support aircraft and crews never enter a HAL pool. They are stamped
        ITW_CLASH_SupportAsset from the moment they exist.
      - Supports read reported positions from the knowledge layer. A live
        enemy position is never an input to a decision.
      - Money is spent only when a support delivers or its aircraft is lost.

    v2: the objective biases where supports go; it no longer decides which
    enemies exist. Targets are searched across a 2 km influence area around
    each target objective, weighted down with distance from the point, and a
    cluster within reach of our own formations at that objective is weighted
    as if it stood on it. A cluster near two objectives enters the pool once.

    v4: the bomb pass acquires on site, like the guided pass. The ground's
    report brings the jet to the area; the jet's own sensors and crew pick
    what it bombs. A lone vehicle, a lone tank or a pair of riflemen is now
    worth a bomb (its own floor, 1.5), and so is a static once its gunner is
    tracked as a contact too; one rifleman is not.
    Carpet stays for clusters: three contacts or more. BOMB and GUIDED pass
    the pre-spawn check on a contact still believed to exist even after its
    position has gone stale, because they look for it themselves.

    v5 (Hark, 2026-10-17: "supports are just crazy rare"):
      - Strikes about twice as often: bomb and guided cost 10 minutes of
        income (were 20), carpet 20 (was 40), and SAVE pulls half as hard.
      - The guided pass shares the acquiring floor (1.5): it was excluded
        from four lone vehicles in one session, a parked Cheetah among them,
        while the bomb flew at them.
      - A UAV that dies within a minute of reaching its station marks a
        killbox: no UAV goes within 1.5 km of it for 15 minutes. A's UAVs
        died 5 to 10 s after reaching the same spot four times.
      - The bomb pass spawns 6 km out (other jets 4 km), so an acquisition
        has time to become a line the jet can actually fly.

    v6 (second 2026-10-17 run): money stopped being the gate. Both banks
    could afford a bomb from five minutes in and ended with two bombs' worth,
    and nothing was bought: in 27 minutes two clusters came up near a plan
    objective, one a side, and both were DANGER_CLOSE.
      - The guided missile is one precision round, not a stick of bombs: its
        margin past the footprint is DangerMarginGuided (100 m, was 300) and
        DangerMarginGuidedPlayer (200 m, was 500). Bombs and carpet keep the
        wide ones.
      - Every DANGER_CLOSE says how close the nearest friendly was, whether
        it was a player, and the line it crossed (supports-danger-close).

    v7 (Hark, 2026-10-17: "I don't want the commander to have to pick
    between the two"): no drop had ever been bought. The helicopter drop
    cost 36, the C-130 with its vehicle add-on the whole 90 cap, and both
    shared the bank, the pick and the commitment lane with the strikes.
      - Three families, three picks per assessment: strikes and the UAV from
        the main bank as before; paradrops (helicopter, plane) in their own
        DROP lane; vehicle delivery as its own support (VEHICLE_DROP) in its
        own VEHICLE lane, carried inside the aircraft and dropped from it
        (the Blackfish by default, ITW_CLASH_SupportsVehicleCarrierClasses).
        A strike never waits on a drop, and a paradrop never on a vehicle.
      - The two drop families spend a wallet of their own (dropCash), with
        its own income and a cap of one paradrop and one vehicle banked.
        Cadences: helicopter drop 15 minutes, plane drop 25, vehicle 15.
        The main bank's cap falls to its own dearest flavor (carpet), since
        the C-130 no longer sits in it.
      - Bite-back (fnc_BiteBack): when a point a side holds is being taken
        (its Impasse flag is coming down, or the enemy's is going up on it)
        or its defenders are outnumbered, the commander sends a wave from a
        small pot of its own: a helicopter drop of two squads and a vehicle.
        The pot holds one wave and refills in 20 minutes; a point is answered
        once per 20 minutes; never on Impasse's defend-phase point while the
        defend phase runs, so the two counterattacks do not stack.
      - Console tests for every drop and for a wave (ITW_CLASH_SupportsDebug.sqf).

    v8 (Hark, 2026-10-17, the first console tests): no delivery flew. GUER
    fields no cars, so every test was refused NO_VEHICLE_FIT before it
    spawned, and it would have flown its Ghost Hawk (WEST its Huron): the
    side's own carriers came before the Blackfish, which neither side lists.
    The plane drop was NO_AIRCRAFT: neither side lists a troop plane.
      - The carrier: the preferred classes first for both sides, then the
        side's own (Hark: 1A).
      - What is delivered: the side's armed and dual-role cars, then its
        APCs, then its tanks, each only if the engine can carry it at all
        (VehicleTransport >> Cargo >> canBeTransported); the loading itself
        decides the rest (Hark: 2B). A side with nothing that can be carried
        is never offered a delivery (NO_VEHICLE_FIT at the gate), where it
        used to be picked, refused and refunded on every assessment.
      - The plane drop: a side that lists no troop plane flies the preferred
        one (ITW_CLASH_SupportsPlaneTroopClasses, the Blackfish's infantry
        variant) (Hark: 3A).
      - Console strike tests (Hark: "can we build debugs for strike and
        guided as well?"): a context marked test asks the pool's own
        questions without the economic ones. StrikeCandidates takes a point
        in place of an objective's centre and the flavors to ask about, and
        with test skips the price, the denied corridor and the crossing
        count; FlavorGate skips lane, relaunch, cooldown and funds. Danger
        close is asked as always (Hark: 2A). The live path is unchanged.

    Every number below is a placeholder for calibration.
*/

// ------------------------------------------------------------------ switches

ITW_CLASH_SupportsEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsEnabled",true];
/*
    Shadow mode. Everything decides, admits and reserves exactly as it would
    live - money is shadow-spent, cooldowns start and the lane is held for the
    support's nominal duration - but nothing spawns. That keeps the dry run's
    cadence honest: a commander that never spent would pick every assessment.

    v3: live, every flavor on (Hark, 2026-10-16). Set this true from the
    console or init to go back to shadow mode.
*/
ITW_CLASH_SupportsDryRun = missionNamespace getVariable ["ITW_CLASH_SupportsDryRun",false];
ITW_CLASH_SupportsUAVEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsUAVEnabled",true];
ITW_CLASH_SupportsBombEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsBombEnabled",true];
ITW_CLASH_SupportsGuidedEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsGuidedEnabled",true];
ITW_CLASH_SupportsCarpetEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsCarpetEnabled",true];
// Each flavor has its own switch; with one off nothing on its path runs.
ITW_CLASH_SupportsAirborneHeliEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliEnabled",true];
ITW_CLASH_SupportsAirbornePlaneEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneEnabled",true];
ITW_CLASH_SupportsVehicleDropEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropEnabled",true];
// v7: the commander's counterattack waves on points it is losing.
ITW_CLASH_SupportsBiteBackEnabled = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackEnabled",true];

// ------------------------------------------------------------------- economy

ITW_CLASH_SupportsIncomeScale = missionNamespace getVariable ["ITW_CLASH_SupportsIncomeScale",1];
// Intended cadence in minutes. Price = income per minute x cadence, so tuning
// is "how often should this happen", not a hunt for numbers.
ITW_CLASH_SupportsUAVCadence = missionNamespace getVariable ["ITW_CLASH_SupportsUAVCadence",4];
// v5: strikes twice as often (were 20, 20 and 40).
ITW_CLASH_SupportsBombCadence = missionNamespace getVariable ["ITW_CLASH_SupportsBombCadence",10];
ITW_CLASH_SupportsGuidedCadence = missionNamespace getVariable ["ITW_CLASH_SupportsGuidedCadence",10];
ITW_CLASH_SupportsCarpetCadence = missionNamespace getVariable ["ITW_CLASH_SupportsCarpetCadence",20];
// v7: the drop families' cadences, in minutes of the drop wallet's own
// income (were 30 and 50 from the main bank, the plane with the vehicle on
// top at 1.5 times: never once affordable).
ITW_CLASH_SupportsAirborneHeliCadence = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliCadence",15];
ITW_CLASH_SupportsAirbornePlaneCadence = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneCadence",25];
ITW_CLASH_SupportsVehicleDropCadence = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropCadence",15];
// v7: the drop wallet's income against the main bank's.
ITW_CLASH_SupportsDropIncomeScale = missionNamespace getVariable ["ITW_CLASH_SupportsDropIncomeScale",1];
// Holding costs less than taking: the side losing ground holds more.
ITW_CLASH_SupportsHoldingDiscount = missionNamespace getVariable ["ITW_CLASH_SupportsHoldingDiscount",0.75];
// v5: how hard SAVE pulls in the pick, against its 3/2/1/0.5 by bank fill.
ITW_CLASH_SupportsSaveScale = missionNamespace getVariable ["ITW_CLASH_SupportsSaveScale",0.5];

// ------------------------------------------------------------------ cooldowns

ITW_CLASH_SupportsUAVCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsUAVCooldown",0];
ITW_CLASH_SupportsBombCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsBombCooldown",300];
ITW_CLASH_SupportsGuidedCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsGuidedCooldown",300];
ITW_CLASH_SupportsCarpetCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsCarpetCooldown",600];
ITW_CLASH_SupportsAirborneHeliCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliCooldown",600];
ITW_CLASH_SupportsAirbornePlaneCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneCooldown",900];
ITW_CLASH_SupportsVehicleDropCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropCooldown",600];
// One objective is not struck twice inside this, whichever flavor.
ITW_CLASH_SupportsObjectiveCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsObjectiveCooldown",180];

// ---------------------------------------------------------------- targeting

ITW_CLASH_SupportsValueFloor = missionNamespace getVariable ["ITW_CLASH_SupportsValueFloor",2];
// The floor for the flavors that acquire on site (bomb and guided; v4 for the
// bomb, v5 for both). COLOSSUS weights: rifleman 1, vehicle 1.5, tank 3,
// static 0.5. At 1.5 a lone vehicle or tank qualifies, so do two riflemen,
// or a static whose gunner is tracked as well; one rifleman does not.
ITW_CLASH_SupportsValueFloorAcquire = missionNamespace getVariable ["ITW_CLASH_SupportsValueFloorAcquire",1.5];
// v4: carpet is for clusters. Fewer contacts than this and it is not offered.
ITW_CLASH_SupportsCarpetMinContacts = missionNamespace getVariable ["ITW_CLASH_SupportsCarpetMinContacts",3];
ITW_CLASH_SupportsClusterRadius = missionNamespace getVariable ["ITW_CLASH_SupportsClusterRadius",150];
ITW_CLASH_SupportsFootprintBomb = missionNamespace getVariable ["ITW_CLASH_SupportsFootprintBomb",50];
ITW_CLASH_SupportsFootprintCarpet = missionNamespace getVariable ["ITW_CLASH_SupportsFootprintCarpet",60];
ITW_CLASH_SupportsFootprintGuided = missionNamespace getVariable ["ITW_CLASH_SupportsFootprintGuided",50];
// Never bomb a guess: a target whose projected uncertainty exceeds this is out.
// For the flavors that acquire on site it gates only what they would drop on
// the report itself; their own acquisition is not a guess.
ITW_CLASH_SupportsUncertaintyLimit = missionNamespace getVariable ["ITW_CLASH_SupportsUncertaintyLimit",300];
ITW_CLASH_SupportsDangerMargin = missionNamespace getVariable ["ITW_CLASH_SupportsDangerMargin",300];
ITW_CLASH_SupportsDangerMarginPlayer = missionNamespace getVariable ["ITW_CLASH_SupportsDangerMarginPlayer",500];
// v6: one precision missile, not a stick of bombs.
ITW_CLASH_SupportsDangerMarginGuided = missionNamespace getVariable ["ITW_CLASH_SupportsDangerMarginGuided",100];
ITW_CLASH_SupportsDangerMarginGuidedPlayer = missionNamespace getVariable ["ITW_CLASH_SupportsDangerMarginGuidedPlayer",200];
// Friendly aircraft above this are not in the footprint's way.
ITW_CLASH_SupportsDangerAirHeight = missionNamespace getVariable ["ITW_CLASH_SupportsDangerAirHeight",300];
ITW_CLASH_SupportsCorridorPenalty = missionNamespace getVariable ["ITW_CLASH_SupportsCorridorPenalty",0.5];
ITW_CLASH_SupportsAirborneFarForce = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneFarForce",1500];
/*
    v7. Vehicle delivery: the aircraft that carry a vehicle inside, the
    side's own first, these classes preferred among them, and these classes
    when the side lists none (Hark: "let's use the blackfish as the vehicle
    dropper, both sides have it right now"). A carrier is any aircraft whose
    config can carry vehicles (VehicleTransport >> Carrier). The men a
    delivered vehicle brings, for the headroom check.
*/
ITW_CLASH_SupportsVehicleCarrierClasses = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleCarrierClasses",["B_T_VTOL_01_vehicle_F"]];
// v8: the troop plane for a side that lists none of its own.
ITW_CLASH_SupportsPlaneTroopClasses = missionNamespace getVariable ["ITW_CLASH_SupportsPlaneTroopClasses",["B_T_VTOL_01_infantry_F"]];
ITW_CLASH_SupportsVehicleDropCrew = missionNamespace getVariable ["ITW_CLASH_SupportsVehicleDropCrew",3];
/*
    v7. Bite-back. The pot is counted in waves: it holds Cap of them and
    earns one back every Refill minutes. A point it answered is not answered
    again within Cooldown seconds. A flag of ours below FlagFloor counts as
    coming down even on the first look. A wave goes out after a short
    scramble (DelayMin to DelayMax s) with Squads squads by helicopter and
    one vehicle.
*/
ITW_CLASH_SupportsBiteBackCap = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackCap",1];
ITW_CLASH_SupportsBiteBackRefill = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackRefill",20];
ITW_CLASH_SupportsBiteBackCooldown = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackCooldown",1200];
ITW_CLASH_SupportsBiteBackFlagFloor = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackFlagFloor",0.9];
ITW_CLASH_SupportsBiteBackDelayMin = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackDelayMin",15];
ITW_CLASH_SupportsBiteBackDelayMax = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackDelayMax",45];
ITW_CLASH_SupportsBiteBackSquads = missionNamespace getVariable ["ITW_CLASH_SupportsBiteBackSquads",2];
/*
    Objective influence (v2). Full weight inside the objective radius, falling
    linearly to the edge weight at the influence radius, nothing beyond it:
        W(d) = 1 - (1 - edge) x (d - objective radius) / (influence - objective radius)
    A cluster within the threat-proximity distance of one of our ground
    formations committed to that objective is weighted 1 wherever it stands:
    being that close to our people makes it relevant, though it does not prove
    it is shooting at them.
*/
ITW_CLASH_SupportsInfluenceRadius = missionNamespace getVariable ["ITW_CLASH_SupportsInfluenceRadius",2000];
ITW_CLASH_SupportsInfluenceEdge = missionNamespace getVariable ["ITW_CLASH_SupportsInfluenceEdge",0.3];
ITW_CLASH_SupportsThreatProximity = missionNamespace getVariable ["ITW_CLASH_SupportsThreatProximity",1000];

// ------------------------------------------------------------------ timing

ITW_CLASH_SupportsDelayMin = missionNamespace getVariable ["ITW_CLASH_SupportsDelayMin",45];
ITW_CLASH_SupportsDelayMax = missionNamespace getVariable ["ITW_CLASH_SupportsDelayMax",120];
ITW_CLASH_SupportsSpawnDistanceJet = missionNamespace getVariable ["ITW_CLASH_SupportsSpawnDistanceJet",4000];
// v5: the bomb pass starts further out, so what it acquires can still be
// turned onto: at 200 m/s the 4 km start left about 5 s (2026-10-17).
ITW_CLASH_SupportsSpawnDistanceBomb = missionNamespace getVariable ["ITW_CLASH_SupportsSpawnDistanceBomb",6000];
/*
    v5. A UAV lost within KillboxSeconds of reaching its station marks where
    it died as a killbox for its side: no UAV is sent, or retasked, within
    KillboxRadius of it for KillboxDuration seconds.
*/
ITW_CLASH_SupportsUAVKillboxSeconds = missionNamespace getVariable ["ITW_CLASH_SupportsUAVKillboxSeconds",60];
ITW_CLASH_SupportsUAVKillboxRadius = missionNamespace getVariable ["ITW_CLASH_SupportsUAVKillboxRadius",1500];
ITW_CLASH_SupportsUAVKillboxDuration = missionNamespace getVariable ["ITW_CLASH_SupportsUAVKillboxDuration",900];
// sideKey -> [[position, time], ...]
if (isNil "ITW_CLASH_SupportsUAVKillboxes") then {ITW_CLASH_SupportsUAVKillboxes = createHashMap};
ITW_CLASH_SupportsSpawnDistanceSlow = missionNamespace getVariable ["ITW_CLASH_SupportsSpawnDistanceSlow",5000];
// For projecting uncertainty to release only; the aircraft fly at their own.
ITW_CLASH_SupportsSpeedJet = missionNamespace getVariable ["ITW_CLASH_SupportsSpeedJet",110];
ITW_CLASH_SupportsSpeedHeli = missionNamespace getVariable ["ITW_CLASH_SupportsSpeedHeli",60];
ITW_CLASH_SupportsSpeedPlane = missionNamespace getVariable ["ITW_CLASH_SupportsSpeedPlane",80];
// A spawn point is kept this far inside the map edge.
ITW_CLASH_SupportsSpawnMapMargin = missionNamespace getVariable ["ITW_CLASH_SupportsSpawnMapMargin",500];
// Egress: fly on this far past the task, then turn this far toward home.
ITW_CLASH_SupportsEgressSeparation = missionNamespace getVariable ["ITW_CLASH_SupportsEgressSeparation",2000];
ITW_CLASH_SupportsEgressTurn = missionNamespace getVariable ["ITW_CLASH_SupportsEgressTurn",2000];
ITW_CLASH_SupportsLedgerInterval = missionNamespace getVariable ["ITW_CLASH_SupportsLedgerInterval",120];
// How many exclusions one pool line carries before it summarises the rest.
ITW_CLASH_SupportsLogExclusions = missionNamespace getVariable ["ITW_CLASH_SupportsLogExclusions",24];

/*
    The registry: one row per flavor. Weights are coarse, 0 to 3, by the class
    of the target cluster; 0 means physically impossible and nothing else.
      VEH_PARKED  armor or vehicles that are not moving
      VEH_MOVING  armor or vehicles that are
      STATIC_DUG  statics, and infantry that are not moving
      INF_MOVING  infantry that are
      LEAD_ONLY   every member is a lead
*/
ITW_CLASH_SupportsRegistry = createHashMapFromArray [
    ["UAV",createHashMapFromArray [
        ["verb","LOOK"],["routine","ORBIT"],["lane","RECON"],["aircraft","UAV"],
        ["switch","ITW_CLASH_SupportsUAVEnabled"],
        ["cadence","ITW_CLASH_SupportsUAVCadence"],
        ["cooldown","ITW_CLASH_SupportsUAVCooldown"],
        ["fighterRule","HARD_KILL"],["airfield",false],["footprint",0],
        ["nominal",900],["weights",createHashMap]
    ]],
    ["BOMB",createHashMapFromArray [
        ["verb","HIT_POINT"],["routine","STRIKE"],["lane","COMMIT"],["aircraft","JET"],
        ["switch","ITW_CLASH_SupportsBombEnabled"],
        ["cadence","ITW_CLASH_SupportsBombCadence"],
        ["cooldown","ITW_CLASH_SupportsBombCooldown"],
        ["fighterRule","ANY_AA_MISSILE"],["airfield",true],
        ["footprint","ITW_CLASH_SupportsFootprintBomb"],
        ["nominal",120],
        ["weights",createHashMapFromArray [
            ["VEH_PARKED",3],["VEH_MOVING",1],["STATIC_DUG",3],["INF_MOVING",2],["LEAD_ONLY",0]
        ]]
    ]],
    ["GUIDED",createHashMapFromArray [
        ["verb","HIT_POINT"],["routine","STRIKE"],["lane","COMMIT"],["aircraft","JET"],
        ["switch","ITW_CLASH_SupportsGuidedEnabled"],
        ["cadence","ITW_CLASH_SupportsGuidedCadence"],
        ["cooldown","ITW_CLASH_SupportsGuidedCooldown"],
        ["fighterRule","ANY_AA_MISSILE"],["airfield",true],
        ["footprint","ITW_CLASH_SupportsFootprintGuided"],
        ["nominal",120],
        ["weights",createHashMapFromArray [
            ["VEH_PARKED",3],["VEH_MOVING",3],["STATIC_DUG",1],["INF_MOVING",0],["LEAD_ONLY",1]
        ]]
    ]],
    ["CARPET",createHashMapFromArray [
        ["verb","HIT_AREA"],["routine","STRIKE"],["lane","COMMIT"],["aircraft","JET"],
        ["switch","ITW_CLASH_SupportsCarpetEnabled"],
        ["cadence","ITW_CLASH_SupportsCarpetCadence"],
        ["cooldown","ITW_CLASH_SupportsCarpetCooldown"],
        ["fighterRule","ANY_AA_MISSILE"],["airfield",true],
        ["footprint","ITW_CLASH_SupportsFootprintCarpet"],
        ["nominal",150],
        ["weights",createHashMapFromArray [
            ["VEH_PARKED",1],["VEH_MOVING",1],["STATIC_DUG",2],["INF_MOVING",3],["LEAD_ONLY",2]
        ]]
    ]],
    ["AIRBORNE_HELI",createHashMapFromArray [
        ["verb","LAND"],["routine","DROP"],["lane","DROP"],["wallet","DROP"],["aircraft","HELI"],
        ["switch","ITW_CLASH_SupportsAirborneHeliEnabled"],
        ["cadence","ITW_CLASH_SupportsAirborneHeliCadence"],
        ["cooldown","ITW_CLASH_SupportsAirborneHeliCooldown"],
        ["fighterRule","HARD_KILL"],["airfield",false],["footprint",0],
        ["nominal",240],["weights",createHashMap]
    ]],
    ["AIRBORNE_PLANE",createHashMapFromArray [
        ["verb","LAND"],["routine","DROP"],["lane","DROP"],["wallet","DROP"],["aircraft","PLANE"],
        ["switch","ITW_CLASH_SupportsAirbornePlaneEnabled"],
        ["cadence","ITW_CLASH_SupportsAirbornePlaneCadence"],
        ["cooldown","ITW_CLASH_SupportsAirbornePlaneCooldown"],
        ["fighterRule","ANY_AA_MISSILE"],["airfield",true],["footprint",0],
        ["nominal",300],["weights",createHashMap]
    ]],
    // v7: a vehicle, carried inside a VTOL or helicopter and dropped from it.
    // From the rear air base like a helicopter: a VTOL needs no runway.
    ["VEHICLE_DROP",createHashMapFromArray [
        ["verb","DELIVER"],["routine","DROP"],["lane","VEHICLE"],["wallet","DROP"],["aircraft","VIV"],
        ["switch","ITW_CLASH_SupportsVehicleDropEnabled"],
        ["cadence","ITW_CLASH_SupportsVehicleDropCadence"],
        ["cooldown","ITW_CLASH_SupportsVehicleDropCooldown"],
        ["fighterRule","ANY_AA_MISSILE"],["airfield",false],["footprint",0],
        ["nominal",300],["weights",createHashMap]
    ]]
];
ITW_CLASH_SupportsStrikeFlavors = ["BOMB","GUIDED","CARPET"];
// v4: the strike flavors whose jet acquires its own target on site. The
// report brings them to the area and sizes the scan; it is not the aim.
ITW_CLASH_SupportsAcquireFlavors = ["BOMB","GUIDED"];
ITW_CLASH_SupportsDropFlavors = ["AIRBORNE_HELI","AIRBORNE_PLANE"];
// v7: delivery is its own family, with its own lane and its own pick.
ITW_CLASH_SupportsVehicleFlavors = ["VEHICLE_DROP"];

// The one vocabulary every denial uses, so a run reads end to end.
ITW_CLASH_SupportsDenials = [
    "DISABLED","LANE_BUSY","RELAUNCH","COOLDOWN","INSUFFICIENT_FUNDS","NO_AIRCRAFT",
    "NO_GUIDED_WEAPON","NO_AIRFIELD","NO_ORIGIN","NO_CONTACT","TOO_UNCERTAIN",
    "BELOW_FLOOR","ETB_ANSWERING","DANGER_CLOSE","AIR_DENIED","OBJECTIVE_FROZEN",
    "DZ_UNASSESSED","NO_HEADROOM","TARGET_GONE","NO_EXECUTOR","SPAWN_FAILED",
    "CONSOLIDATING","NO_DZ","NO_SQUADS","NOT_CLUSTERED","UAV_KILLBOX",
    "NO_VEHICLE_FIT","DEFEND_PHASE","REFUSED","ADMISSION"
];

ITW_CLASH_SupportsLedgers = createHashMap;
// sideKey -> [contacts inside an influence area, contacts known] at the last
// assessment, to count crossings of the hard influence cutoff.
ITW_CLASH_SupportsInfluenceLast = createHashMap;
// Only decision-level events are spoken by the loud debugger; the pool and
// ledger lines are far too long for chat.
ITW_CLASH_SupportsLoudEvents = [
    "admission","outcome","uav-on-station","uav-ended",
    "strike-released","strike-guided-fired","strike-scan-empty","strike-test-outcome",
    "airborne-released","airborne-handoff","airborne-vehicle-handoff",
    "airborne-vehicle-released","biteback-wave","test-launched"
];
// sideKey -> [position,objective,reason]: where the UAV should be, refreshed
// every assessment without a roll.
ITW_CLASH_SupportsUAVTasks = createHashMap;
ITW_CLASH_SupportsSerial = 0;
// v7: bite-back waves, numbered apart from supports.
ITW_CLASH_SupportsWaveSerial = 0;
ITW_CLASH_SupportsLedgerAt = 0;

// ------------------------------------------------------------------ plumbing

ITW_CLASH_Supports_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["supports-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SUPPORTS | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit" && {_event in ITW_CLASH_SupportsLoudEvents}) then {
        ["supports",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

ITW_CLASH_Supports_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_Supports_fnc_CodeSign = {
    params ["_side"];
    if (isNil "ITW_CLASH_fnc_GetCommanderForSide") exitWith {str _side};
    private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {str _side};
    _hq getVariable ["RydHQ_CodeSign",str _side]
};

ITW_CLASH_Supports_fnc_Row = {
    params ["_flavor"];
    ITW_CLASH_SupportsRegistry getOrDefault [_flavor,createHashMap]
};

ITW_CLASH_Supports_fnc_RowNumber = {
    params ["_flavor","_field",["_default",0]];
    private _value = ([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault [_field,_default];
    if (_value isEqualType "") then {_value = missionNamespace getVariable [_value,_default]};
    if !(_value isEqualType 0) then {_value = _default};
    _value
};

ITW_CLASH_Supports_fnc_Enabled = {
    params ["_flavor"];
    private _row = [_flavor] call ITW_CLASH_Supports_fnc_Row;
    if (count _row == 0) exitWith {false};
    private _on = missionNamespace getVariable [_row get "switch",false];
    _on isEqualTo true
};

// The ETB's own neutral formula, on its own scale: equal for both sides, and
// nothing earned from kills or captures.
ITW_CLASH_Supports_fnc_IncomeRate = {
    private _adjustment = missionNamespace getVariable ["ITW_ParamVehicleSpawnAdjustment",1];
    private _aiCount = missionNamespace getVariable ["ITW_ParamEnemyAiCnt",30];
    TICKETS_PER_MIN * _adjustment * ((_aiCount + 70) / 100) * ITW_CLASH_SupportsIncomeScale
};

// v7: the drop wallet's income, on the main bank's scale.
ITW_CLASH_Supports_fnc_DropIncomeRate = {
    (call ITW_CLASH_Supports_fnc_IncomeRate) * ITW_CLASH_SupportsDropIncomeScale
};

// v7: which wallet a flavor spends from: MAIN, DROP (paradrops and delivery).
ITW_CLASH_Supports_fnc_WalletOf = {
    params ["_flavor"];
    ([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["wallet","MAIN"]
};

// v7: where a wallet's money sits in the ledger. BITE is the bite-back pot,
// counted in waves; TEST is a console test's, which never runs out.
ITW_CLASH_Supports_fnc_WalletKey = {
    params ["_wallet"];
    switch (_wallet) do {
        case "DROP": {"dropCash"};
        case "BITE": {"biteCash"};
        default {"cash"};
    }
};

ITW_CLASH_Supports_fnc_WalletCash = {
    params ["_ledger","_wallet"];
    if (_wallet isEqualTo "TEST") exitWith {1e10};
    _ledger getOrDefault [[_wallet] call ITW_CLASH_Supports_fnc_WalletKey,0]
};

ITW_CLASH_Supports_fnc_WalletCap = {
    params ["_wallet"];
    switch (_wallet) do {
        case "DROP": {call ITW_CLASH_Supports_fnc_DropCap};
        case "BITE": {ITW_CLASH_SupportsBiteBackCap};
        case "TEST": {1e10};
        default {call ITW_CLASH_Supports_fnc_Cap};
    }
};

ITW_CLASH_Supports_fnc_Price = {
    params ["_flavor",["_reason","TAKE"]];
    private _rate = if (([_flavor] call ITW_CLASH_Supports_fnc_WalletOf) isEqualTo "DROP") then {
        call ITW_CLASH_Supports_fnc_DropIncomeRate
    } else {call ITW_CLASH_Supports_fnc_IncomeRate};
    private _price = _rate * ([_flavor,"cadence",10] call ITW_CLASH_Supports_fnc_RowNumber);
    if (_reason isEqualTo "HOLD") then {_price = _price * ITW_CLASH_SupportsHoldingDiscount};
    _price
};

// One big support in the bank, never two: the most expensive enabled flavor
// that spends from it (v7: the main bank's own; the drops have theirs).
ITW_CLASH_Supports_fnc_Cap = {
    private _cap = 0;
    {
        if (([_x] call ITW_CLASH_Supports_fnc_WalletOf) isEqualTo "MAIN" && {[_x] call ITW_CLASH_Supports_fnc_Enabled}) then {
            _cap = _cap max ([_x] call ITW_CLASH_Supports_fnc_Price);
        };
    } forEach (keys ITW_CLASH_SupportsRegistry);
    _cap max ([("UAV")] call ITW_CLASH_Supports_fnc_Price)
};

// v7: the drop wallet holds one paradrop and one vehicle, never more.
ITW_CLASH_Supports_fnc_DropCap = {
    private _paradrop = 0;
    {
        if ([_x] call ITW_CLASH_Supports_fnc_Enabled) then {_paradrop = _paradrop max ([_x] call ITW_CLASH_Supports_fnc_Price)};
    } forEach ITW_CLASH_SupportsDropFlavors;
    private _vehicle = 0;
    {
        if ([_x] call ITW_CLASH_Supports_fnc_Enabled) then {_vehicle = _vehicle max ([_x] call ITW_CLASH_Supports_fnc_Price)};
    } forEach ITW_CLASH_SupportsVehicleFlavors;
    (_paradrop + _vehicle) max 1
};

ITW_CLASH_Supports_fnc_Ledger = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_Supports_fnc_SideKey;
    private _ledger = ITW_CLASH_SupportsLedgers getOrDefault [_key,createHashMap];
    if (count _ledger == 0) then {
        _ledger = createHashMapFromArray [
            ["side",_side],
            ["cash",["UAV"] call ITW_CLASH_Supports_fnc_Price],
            // v7: the drop wallet starts empty; the bite-back pot full.
            ["dropCash",0],
            ["biteCash",ITW_CLASH_SupportsBiteBackCap],
            ["accruedAt",time],
            ["lanes",createHashMapFromArray [
                ["RECON",""],["COMMIT",""],["DROP",""],["VEHICLE",""],["BITE_DROP",""],["BITE_VEHICLE",""]
            ]],
            ["reconBlockedUntil",0],
            ["cooldowns",createHashMap],
            ["supports",createHashMap],
            // v7, bite-back: objective -> [flag ours, phase] at the last look;
            // what it last said per objective, so a held wave is one line.
            ["bitePhases",createHashMap],
            ["biteSaid",createHashMap]
        ];
        ITW_CLASH_SupportsLedgers set [_key,_ledger];
        ["ledger-opened",[
            [_side] call ITW_CLASH_Supports_fnc_CodeSign,
            round (_ledger get "cash"),round (call ITW_CLASH_Supports_fnc_Cap)
        ]] call ITW_CLASH_Supports_fnc_Log;
    };
    _ledger
};

// Income stops at the cap: one big support banked, never two. v7: each
// wallet earns on its own and stops at its own cap.
ITW_CLASH_Supports_fnc_Accrue = {
    params ["_side"];
    private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
    private _elapsed = time - (_ledger get "accruedAt");
    if (_elapsed <= 0) exitWith {false};
    _ledger set ["accruedAt",time];
    {
        _x params ["_key","_cap","_perMinute"];
        private _cash = _ledger getOrDefault [_key,0];
        if (_cash < _cap) then {_ledger set [_key,(_cash + _perMinute * (_elapsed / 60)) min _cap]};
    } forEach [
        ["cash",call ITW_CLASH_Supports_fnc_Cap,call ITW_CLASH_Supports_fnc_IncomeRate],
        ["dropCash",call ITW_CLASH_Supports_fnc_DropCap,call ITW_CLASH_Supports_fnc_DropIncomeRate],
        ["biteCash",ITW_CLASH_SupportsBiteBackCap,1 / (ITW_CLASH_SupportsBiteBackRefill max 1)]
    ];
    true
};

ITW_CLASH_Supports_fnc_OnCooldown = {
    params ["_ledger","_key"];
    time < ((_ledger get "cooldowns") getOrDefault [_key,0])
};

ITW_CLASH_Supports_fnc_ObjectivePos = {
    params ["_index"];
    if (isNil "ITW_Objectives" || {_index < 0} || {_index >= count ITW_Objectives}) exitWith {[]};
    +(ITW_Objectives#_index#ITW_OBJ_POS)
};

ITW_CLASH_Supports_fnc_ObjectiveRadius = {
    missionNamespace getVariable ["ITW_CLASH_ColossusObjectiveRadius",500]
};

// One ownership rule for both layers: COLOSSUS owns it since its v6, and this
// keeps the old body only for a boot where COLOSSUS is missing.
ITW_CLASH_Supports_fnc_HeldBy = {
    params ["_side","_index"];
    if (!isNil "ITW_CLASH_Colossus_fnc_HeldBy") exitWith {
        [_side,_index] call ITW_CLASH_Colossus_fnc_HeldBy
    };
    if (isNil "ITW_ObjContestedOwnerIsFriendly" || {isNil "ITW_PlayerSide"}) exitWith {false};
    private _friendlyOwns = [_index] call ITW_ObjContestedOwnerIsFriendly;
    if (_side isEqualTo ITW_PlayerSide) exitWith {_friendlyOwns};
    !_friendlyOwns
};

// ------------------------------------------------------------------ aircraft

// The faction's own classes for a kind of support aircraft.
ITW_CLASH_Supports_fnc_Classes = {
    params ["_side","_kind"];
    if (_kind isEqualTo "DELIVERY") exitWith {
        private _all = [];
        {_all append _x} forEach ([_side] call ITW_CLASH_Supports_fnc_DeliveryTiers);
        _all
    };
    private _friendly = !isNil "ITW_PlayerSide" && {_side isEqualTo ITW_PlayerSide};
    private _prefix = if (_friendly) then {"va_p"} else {"va_e"};
    private _names = switch (_kind) do {
        case "JET": {[_prefix + "PlaneClassesAttack",_prefix + "PlaneClassesDual"]};
        case "HELI": {[_prefix + "HeliClassesTransport"]};
        case "PLANE": {[_prefix + "PlaneClassesTransport"]};
        case "UAV": {[_prefix + "UavClasses"]};
        case "CAR": {[_prefix + "CarClassesAttack",_prefix + "CarClassesDual"]};
        // v7: whatever the side flies that carries vehicles inside.
        case "VIV": {[_prefix + "PlaneClassesTransport",_prefix + "HeliClassesTransport"]};
        default {[]};
    };
    private _classes = [];
    {
        private _list = missionNamespace getVariable [_x,[]];
        if !(_list isEqualType []) then {continue};
        {
            private _class = if (_x isEqualType []) then {_x param [0,""]} else {_x};
            if (
                _class isEqualType ""
                && {_class isNotEqualTo ""}
                && {isClass (configFile >> "CfgVehicles" >> _class)}
            ) then {_classes pushBackUnique _class};
        } forEach _list;
    } forEach _names;
    switch (_kind) do {
        case "JET";
        case "PLANE": {_classes select {_x isKindOf "Plane"}};
        case "HELI": {_classes select {_x isKindOf "Helicopter"}};
        case "UAV": {
            _classes select {
                _x isKindOf "Air"
                && {getNumber (configFile >> "CfgVehicles" >> _x >> "isUav") == 1}
            }
        };
        case "CAR": {_classes select {_x isKindOf "LandVehicle"}};
        case "VIV": {_classes select {[_x] call ITW_CLASH_Supports_fnc_IsCarrier}};
        default {[]};
    }
};

/*
    v8. What a side can deliver, in the order it is tried: its armed and
    dual-role cars, then its APCs, then its tanks (Hark: "let the loading
    test decide"). Each only if the engine can carry it at all: Vehicle in
    Vehicle needs VehicleTransport >> Cargo >> canBeTransported on the
    cargo, so a class without it would only be spawned to be deleted.
    Returns [cars, APCs, tanks].
*/
ITW_CLASH_Supports_fnc_DeliveryTiers = {
    params ["_side"];
    private _friendly = !isNil "ITW_PlayerSide" && {_side isEqualTo ITW_PlayerSide};
    private _prefix = if (_friendly) then {"va_p"} else {"va_e"};
    ["Car","Apc","Tank"] apply {
        private _kind = _x;
        private _tier = [];
        {
            private _list = missionNamespace getVariable [_prefix + _kind + _x,[]];
            if !(_list isEqualType []) then {continue};
            {
                private _class = if (_x isEqualType []) then {_x param [0,""]} else {_x};
                if (
                    _class isEqualType ""
                    && {_class isNotEqualTo ""}
                    && {isClass (configFile >> "CfgVehicles" >> _class)}
                    && {_class isKindOf "LandVehicle"}
                    && {getNumber (configFile >> "CfgVehicles" >> _class >> "VehicleTransport" >> "Cargo" >> "canBeTransported") == 1}
                ) then {_tier pushBackUnique _class};
            } forEach _list;
        } forEach ["ClassesAttack","ClassesDual"];
        _tier
    }
};

// v7: an aircraft whose config carries vehicles inside (Vehicle in Vehicle).
ITW_CLASH_Supports_fnc_IsCarrier = {
    params ["_class"];
    _class isKindOf "Air"
    && {isClass (configFile >> "CfgVehicles" >> _class >> "VehicleTransport" >> "Carrier")}
};

ITW_CLASH_Supports_fnc_CarrierLoad = {
    params ["_class"];
    getNumber (configFile >> "CfgVehicles" >> _class >> "VehicleTransport" >> "Carrier" >> "maxLoadMass")
};

// Cargo seats a class offers troops.
ITW_CLASH_Supports_fnc_CargoSeats = {
    params ["_class"];
    (([_class,true] call BIS_fnc_crewCount) - ([_class,false] call BIS_fnc_crewCount)) max 0
};

/*
    The aircraft for a flavor, or "" with the reason why not. UAV falls back to
    the side's vanilla Greyhawk; every other flavor follows the faction, as the
    ETB does: a side without the class goes without the flavor.
*/
ITW_CLASH_Supports_fnc_PickClass = {
    params ["_side","_flavor"];
    private _kind = ([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["aircraft",""];
    private _classes = [_side,_kind] call ITW_CLASH_Supports_fnc_Classes;
    switch (_kind) do {
        case "UAV": {
            if (_classes isEqualTo []) then {
                private _fallback = switch (_side) do {
                    case west: {"B_UAV_02_dynamicLoadout_F"};
                    case east: {"O_UAV_02_dynamicLoadout_F"};
                    default {"I_UAV_02_dynamicLoadout_F"};
                };
                if (isClass (configFile >> "CfgVehicles" >> _fallback)) then {_classes = [_fallback]};
            };
            if (_classes isEqualTo []) exitWith {["","NO_AIRCRAFT"]};
            /*
                Fixed-wing first: a faction's UAV list also holds quadcopters
                (the AR-2 Darter on 2026-10-16, sent 5 km out to loiter at
                500 m), which are slow and short-ranged for an overwatch
                orbit. A rotary one only when the faction has nothing else.
            */
            private _fixed = _classes select {_x isKindOf "Plane"};
            if (_fixed isNotEqualTo []) then {_classes = _fixed};
            [selectRandom _classes,""]
        };
        case "JET": {
            if (_classes isEqualTo []) exitWith {["","NO_AIRCRAFT"]};
            if (_flavor isEqualTo "GUIDED") exitWith {
                private _guided = _classes select {
                    !isNil "ITW_CLASH_SupportsStrike_fnc_ClassGuided"
                    && {[_x] call ITW_CLASH_SupportsStrike_fnc_ClassGuided}
                };
                if (_guided isEqualTo []) exitWith {["","NO_GUIDED_WEAPON"]};
                [selectRandom _guided,""]
            };
            [selectRandom _classes,""]
        };
        /*
            v7. The side's own carriers, the preferred classes first in their
            order; else the one that lifts most; else a preferred class the
            side does not list but the game has (both sides fly the
            Blackfish here, Hark 2026-10-17).
            v8: the preferred classes before the side's own carriers (Hark:
            1A). Neither side lists the Blackfish, so v7 flew GUER's Ghost
            Hawk and would have flown WEST's Huron. An empty preferred list
            goes back to the side's own.
        */
        case "VIV": {
            private _preferred = ITW_CLASH_SupportsVehicleCarrierClasses select {
                _x isEqualType "" && {isClass (configFile >> "CfgVehicles" >> _x)} && {[_x] call ITW_CLASH_Supports_fnc_IsCarrier}
            };
            private _own = _preferred select {_x in _classes};
            if (_own isNotEqualTo []) exitWith {[_own#0,""]};
            if (_preferred isNotEqualTo []) exitWith {[_preferred#0,""]};
            if (_classes isNotEqualTo []) exitWith {
                [([_classes,[],{[_x] call ITW_CLASH_Supports_fnc_CarrierLoad},"DESCEND"] call BIS_fnc_sortBy)#0,""]
            };
            ["","NO_AIRCRAFT"]
        };
        case "HELI";
        case "PLANE": {
            private _carriers = _classes select {([_x] call ITW_CLASH_Supports_fnc_CargoSeats) >= 4};
            // v8: a side that lists no troop plane flies the preferred one (Hark: 3A).
            if (_carriers isEqualTo [] && {_kind isEqualTo "PLANE"}) then {
                _carriers = ITW_CLASH_SupportsPlaneTroopClasses select {
                    _x isEqualType ""
                    && {isClass (configFile >> "CfgVehicles" >> _x)}
                    && {_x isKindOf "Plane"}
                    && {([_x] call ITW_CLASH_Supports_fnc_CargoSeats) >= 4}
                };
            };
            if (_carriers isEqualTo []) exitWith {["","NO_AIRCRAFT"]};
            // The roomiest: a packed aircraft is the point.
            private _ranked = [_carriers,[],{[_x] call ITW_CLASH_Supports_fnc_CargoSeats},"DESCEND"] call BIS_fnc_sortBy;
            [_ranked#0,""]
        };
        default {["","NO_AIRCRAFT"]};
    }
};

/*
    Where a support flies from: an owned airfield for fixed-wing, the side's
    rear base for helicopters and the UAV (REAR_AIR: the armour's own rear
    base since 2026-10-17, at its vehicle point).
*/
ITW_CLASH_Supports_fnc_Origin = {
    params ["_side","_flavor","_aim"];
    if (([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["airfield",false]) exitWith {
        if (isNil "ITW_ObjOwnedAirports" || {isNil "ITW_PlayerSide"}) exitWith {[[],"NO_AIRFIELD"]};
        private _airports = (_side isEqualTo ITW_PlayerSide) call ITW_ObjOwnedAirports;
        if !(_airports isEqualType [] && {_airports isNotEqualTo []}) exitWith {[[],"NO_AIRFIELD"]};
        private _ranked = [_airports,[],{_x distance2D _aim},"ASCEND"] call BIS_fnc_sortBy;
        private _airport = +(_ranked#0);
        if (count _airport < 3) then {_airport pushBack 0};
        [_airport,""]
    };
    if (isNil "ITW_CLASH_Generation_fnc_Resolve") exitWith {[[],"NO_ORIGIN"]};
    private _generation = [_side,"SUPPORT_AIR","REAR_AIR",_aim] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) isNotEqualTo "RESOLVED") exitWith {[[],"NO_ORIGIN"]};
    [+(_generation getOrDefault ["origin",[]]),""]
};

/*
    Where an aircraft appears: _distance short of the aim, on the bearing from
    the origin. Always the full distance, so a strike has its run-in even when
    our airfield is next to the target; that point lies beyond the airfield,
    in our own airspace. If it would fall off the map, the bearing is turned
    in 15 degree steps toward the map, up to 90 either way, and only then
    clamped.
*/
ITW_CLASH_Supports_fnc_SpawnPoint = {
    params ["_origin","_aim","_distance"];
    private _bearing = if ((_origin distance2D _aim) > 1) then {_aim getDir _origin} else {0};
    private _margin = ITW_CLASH_SupportsSpawnMapMargin;
    private _limit = worldSize - _margin;
    private _found = [];
    {
        private _point = _aim getPos [_distance,_bearing + _x];
        if ((_point#0) > _margin && {(_point#1) > _margin} && {(_point#0) < _limit} && {(_point#1) < _limit}) exitWith {
            _found = _point;
        };
    } forEach [0,15,-15,30,-30,45,-45,60,-60,75,-75,90,-90];
    if (_found isEqualTo []) then {
        private _point = _aim getPos [_distance,_bearing];
        _found = [((_point#0) max _margin) min _limit,((_point#1) max _margin) min _limit,0];
    };
    _found
};

ITW_CLASH_Supports_fnc_SpawnDistance = {
    params ["_flavor"];
    if (_flavor isEqualTo "BOMB") exitWith {ITW_CLASH_SupportsSpawnDistanceBomb};
    private _kind = ([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["aircraft",""];
    if (_kind isEqualTo "JET") exitWith {ITW_CLASH_SupportsSpawnDistanceJet};
    ITW_CLASH_SupportsSpawnDistanceSlow
};

ITW_CLASH_Supports_fnc_ProjectionSpeed = {
    params ["_flavor"];
    switch (([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["aircraft",""]) do {
        case "JET": {ITW_CLASH_SupportsSpeedJet};
        case "VIV";
        case "PLANE": {ITW_CLASH_SupportsSpeedPlane};
        default {ITW_CLASH_SupportsSpeedHeli};
    }
};

ITW_CLASH_Supports_fnc_Corridor = {
    params ["_hq","_from","_to","_rule"];
    if (isNil "ITW_CLASH_AirPicture_fnc_ClassifyCorridor" || {_from isEqualTo []} || {_to isEqualTo []}) exitWith {
        createHashMapFromArray [["state","COLD"],["reason","corridor-unavailable"]]
    };
    [_hq,_from,_to,_rule] call ITW_CLASH_AirPicture_fnc_ClassifyCorridor
};

// ------------------------------------------------------------------ targets

/*
    Contacts within the cluster radius of each other become one target. Seeds
    are taken in order of worth, so the most valuable contact anchors its
    cluster. Every position here is a reported one.
*/
ITW_CLASH_Supports_fnc_Clusters = {
    params ["_side","_centers","_radius"];
    // One centre or several: contacts within the radius of any of them.
    if (_centers isNotEqualTo [] && {(_centers#0) isEqualType 0}) then {_centers = [_centers]};
    private _items = [];
    {
        _x params ["_key","_record","_status"];
        private _position = _record get "position";
        if ((_centers findIf {(_position distance2D _x) <= _radius}) < 0) then {continue};
        _items pushBack [[_record] call ITW_CLASH_Knowledge_fnc_Worth,_key,_record,_status];
    } forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);
    private _ordered = [_items,[],{-(_x#0)},"ASCEND"] call BIS_fnc_sortBy;

    private _clusters = [];
    private _used = [];
    {
        _x params ["","_seedKey","_seedRecord"];
        if (_seedKey in _used) then {continue};
        private _seed = _seedRecord get "position";
        private _members = _ordered select {
            !((_x#1) in _used)
            && {(((_x#2) get "position") distance2D _seed) <= ITW_CLASH_SupportsClusterRadius}
        };
        {_used pushBack (_x#1)} forEach _members;
        _clusters pushBack ([_seedKey,_members] call ITW_CLASH_Supports_fnc_Cluster);
    } forEach _ordered;
    _clusters
};

ITW_CLASH_Supports_fnc_Cluster = {
    params ["_seedKey","_members"];
    private _worth = 0;
    private _sx = 0;
    private _sy = 0;
    private _weightSum = 0;
    private _best = "LEAD";
    private _vehicles = 0;
    private _allLeads = true;
    private _sums = createHashMapFromArray [
        ["VEH_PARKED",0],["VEH_MOVING",0],["STATIC_DUG",0],["INF_MOVING",0]
    ];
    {
        _x params ["_memberWorth","","_record","_status"];
        _worth = _worth + _memberWorth;
        private _weight = _memberWorth max 0.01;
        private _position = _record get "position";
        _sx = _sx + (_position#0) * _weight;
        _sy = _sy + (_position#1) * _weight;
        _weightSum = _weightSum + _weight;
        if (_status isEqualTo "OBSERVED") then {_best = "OBSERVED"};
        if (_status isEqualTo "FIXED" && {_best isEqualTo "LEAD"}) then {_best = "FIXED"};
        if (_status isNotEqualTo "LEAD") then {_allLeads = false};
        private _class = _record get "class";
        private _moving = _record getOrDefault ["moving",false];
        private _bucket = switch (true) do {
            case (_class in ["VEHICLE","ARMOR"]): {
                _vehicles = _vehicles + 1;
                if (_moving) then {"VEH_MOVING"} else {"VEH_PARKED"}
            };
            case (_class isEqualTo "STATIC"): {"STATIC_DUG"};
            case (_moving): {"INF_MOVING"};
            default {"STATIC_DUG"};
        };
        _sums set [_bucket,(_sums get _bucket) + _weight];
    } forEach _members;

    private _class = "LEAD_ONLY";
    if (!_allLeads) then {
        private _top = -1;
        {
            if (_y > _top) then {_top = _y; _class = _x};
        } forEach _sums;
    };
    createHashMapFromArray [
        ["key",_seedKey],
        ["keys",_members apply {_x#1}],
        ["worth",_worth],
        ["aim",[_sx / (_weightSum max 0.01),_sy / (_weightSum max 0.01),0]],
        ["best",_best],
        ["class",_class],
        ["vehicles",_vehicles],
        ["count",count _members]
    ]
};

/*
    The target as the knowledge layer has it NOW: aim point and uncertainty
    projected _ahead seconds, from the members still not lost. Used at the
    pre-run check and again at release.

    v4: with _held, a member whose position has gone stale (LOST) still counts
    while it is believed to exist. That is for the passes that acquire on
    site: they go and look, so a stale position is where to start looking,
    not a reason to stay home.
*/
ITW_CLASH_Supports_fnc_TargetNow = {
    params ["_side","_keys",["_ahead",0],["_held",false]];
    private _sx = 0;
    private _sy = 0;
    private _weightSum = 0;
    private _r = 0;
    private _alive = 0;
    private _entities = [];
    {
        private _record = [_side,_x] call ITW_CLASH_Knowledge_fnc_Record;
        if (count _record == 0) then {continue};
        if (_held) then {
            if (([_record] call ITW_CLASH_Knowledge_fnc_Existence) <= 0) then {continue};
        } else {
            if (([_record] call ITW_CLASH_Knowledge_fnc_Status) isEqualTo "LOST") then {continue};
        };
        private _weight = ([_record] call ITW_CLASH_Knowledge_fnc_Worth) max 0.01;
        private _position = _record get "position";
        _sx = _sx + (_position#0) * _weight;
        _sy = _sy + (_position#1) * _weight;
        _r = _r + ([_record,_ahead] call ITW_CLASH_Knowledge_fnc_Uncertainty) * _weight;
        _weightSum = _weightSum + _weight;
        _alive = _alive + 1;
        private _entity = _record getOrDefault ["entity",objNull];
        if (!isNull _entity) then {_entities pushBack _entity};
    } forEach _keys;
    if (_alive == 0) exitWith {[[],1e10,0,[]]};
    [[_sx / _weightSum,_sy / _weightSum,0],_r / _weightSum,_alive,_entities]
};

// Mean projected uncertainty of a cluster's members at release.
ITW_CLASH_Supports_fnc_ClusterUncertainty = {
    params ["_side","_cluster","_ahead"];
    ([_side,_cluster get "keys",_ahead] call ITW_CLASH_Supports_fnc_TargetNow) param [1,1e10]
};

// Is an ETB responder of this side already tasked against any of these?
ITW_CLASH_Supports_fnc_ETBAnswering = {
    params ["_hq","_entities"];
    if (isNull _hq || {_entities isEqualTo []}) exitWith {false};
    private _timeout = missionNamespace getVariable ["ITW_CLASH_ThreatCoverageCommitmentTimeout",300];
    ((_hq getVariable ["RydHQ_Friends",[]]) findIf {
        private _group = _x;
        !isNull _group
        && {(_group getVariable ["ITW_CLASH_ThreatCoverageTarget",objNull]) in _entities}
        && {_group getVariable ["Busy" + str _group,false]}
        && {(time - (_group getVariable ["ITW_CLASH_ThreatCoverageCommittedAt",-1e10])) <= _timeout}
    }) >= 0
};

/*
    Our own people, for danger close: everything of ours on foot, in vehicles,
    under canopy, or in an aircraft low enough to be in a footprint's way.
    Our own positions are ours to know; this is no omniscience.
*/
ITW_CLASH_Supports_fnc_Friendlies = {
    params ["_side"];
    private _result = [];
    {
        if (!alive _x) then {continue};
        private _veh = vehicle _x;
        private _position = getPosATL _veh;
        if ((_position#2) > ITW_CLASH_SupportsDangerAirHeight) then {continue};
        private _ownSide = side group _x;
        if (_ownSide isEqualTo civilian) then {continue};
        if (_ownSide isNotEqualTo _side && {!([_ownSide,_side] call BIS_fnc_sideIsFriendly)}) then {continue};
        _result pushBack [_position,isPlayer _x];
    } forEach allUnits;
    _result
};

// v6: the margin past the footprint, by flavor and by whether it is a player.
ITW_CLASH_Supports_fnc_DangerMargin = {
    params [["_flavor",""],["_player",false]];
    if (_flavor isEqualTo "GUIDED") exitWith {
        if (_player) then {ITW_CLASH_SupportsDangerMarginGuidedPlayer} else {ITW_CLASH_SupportsDangerMarginGuided}
    };
    if (_player) then {ITW_CLASH_SupportsDangerMarginPlayer} else {ITW_CLASH_SupportsDangerMargin}
};

ITW_CLASH_Supports_fnc_DangerClose = {
    params ["_friendlies","_aim","_footprint",["_flavor",""]];
    (_friendlies findIf {
        _x params ["_position","_player"];
        (_position distance2D _aim) <= (_footprint + ([_flavor,_player] call ITW_CLASH_Supports_fnc_DangerMargin))
    }) >= 0
};

/*
    v6. The friendly that made it danger close, for the log: the one deepest
    inside its own line. [distance, player, line] or [] when none is inside.
*/
ITW_CLASH_Supports_fnc_DangerWhy = {
    params ["_friendlies","_aim","_footprint",["_flavor",""]];
    private _worst = [];
    private _worstDepth = 0;
    {
        _x params ["_position","_player"];
        private _line = _footprint + ([_flavor,_player] call ITW_CLASH_Supports_fnc_DangerMargin);
        private _distance = _position distance2D _aim;
        private _depth = _line - _distance;
        if (_depth >= 0 && {_worst isEqualTo [] || {_depth > _worstDepth}}) then {
            _worst = [round _distance,_player,round _line];
            _worstDepth = _depth;
        };
    } forEach _friendlies;
    _worst
};

ITW_CLASH_Supports_fnc_DistanceWeight = {
    params ["_distance"];
    private _inner = call ITW_CLASH_Supports_fnc_ObjectiveRadius;
    if (_distance <= _inner) exitWith {1};
    if (_distance > ITW_CLASH_SupportsInfluenceRadius) exitWith {0};
    1 - ((1 - ITW_CLASH_SupportsInfluenceEdge) * (_distance - _inner)
        / ((ITW_CLASH_SupportsInfluenceRadius - _inner) max 1))
};

/*
    Our ground formations committed to an objective, by COLOSSUS's own rule
    (Colossus_fnc_FriendlyStrength): the commander's groups, less the pools it
    would never send, whose leader is on the ground within the committed
    radius. Transports passing through, supply trucks, artillery and special
    forces are not committed to anything. Their own positions are ours to know.
*/
ITW_CLASH_Supports_fnc_Committed = {
    params ["_hq","_center"];
    if (isNull _hq || {_center isEqualTo []}) exitWith {[]};
    private _radius = missionNamespace getVariable ["ITW_CLASH_ColossusCommittedRadius",900];
    private _excluded = (_hq getVariable ["RydHQ_Exhausted",[]])
        + (_hq getVariable ["RydHQ_SupportG",[]])
        + (_hq getVariable ["RydHQ_SpecForG",[]])
        + (_hq getVariable ["RydHQ_ArtG",[]])
        + (_hq getVariable ["RydHQ_NavalG",[]])
        + (_hq getVariable ["RydHQ_CargoOnly",[]])
        + (_hq getVariable ["RydHQ_StaticG",[]]);
    private _positions = [];
    {
        private _group = _x;
        if (isNull _group || {_group in _excluded}) then {continue};
        private _leader = leader _group;
        if (isNull _leader || {!alive _leader}) then {continue};
        private _veh = vehicle _leader;
        if (_veh isKindOf "Air") then {continue};
        private _position = getPosATL _veh;
        if ((_position distance2D _center) > _radius) then {continue};
        _positions pushBack _position;
    } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    _positions
};

/*
    Pressure on one held point: every enemy still believed to exist, at its
    class worth, times its presence in the point's influence area (the share
    of where it could be that lies inside it), times the distance falloff at
    its reported position. Computed per point, so one tank threatening two
    points is pressure on both.
*/
ITW_CLASH_Supports_fnc_Pressure = {
    params ["_side","_center"];
    if (_center isEqualTo []) exitWith {0};
    private _score = 0;
    {
        _x params ["","_record"];
        private _falloff = [(_record get "position") distance2D _center] call ITW_CLASH_Supports_fnc_DistanceWeight;
        if (_falloff <= 0) then {continue};
        private _presence = [_record,_center,ITW_CLASH_SupportsInfluenceRadius] call ITW_CLASH_Knowledge_fnc_Presence;
        _score = _score + ([_record get "class"] call ITW_CLASH_Knowledge_fnc_ClassWorth) * _presence * _falloff;
    } forEach ([_side] call ITW_CLASH_Knowledge_fnc_Held);
    _score
};

/*
    A diagnostic for the hard influence cutoff: contacts known at both of the
    last two assessments that moved into or out of every target's influence
    area. A change of plan objective shows here too.
*/
ITW_CLASH_Supports_fnc_CountCrossings = {
    params ["_context","_clusters"];
    private _side = _context get "side";
    private _sideKey = [_side] call ITW_CLASH_Supports_fnc_SideKey;
    private _inside = createHashMap;
    {
        {_inside set [_x,true]} forEach (_x get "keys");
    } forEach _clusters;
    private _known = createHashMap;
    {_known set [_x#0,true]} forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);
    (ITW_CLASH_SupportsInfluenceLast getOrDefault [_sideKey,[createHashMap,createHashMap]]) params [
        "_lastInside","_lastKnown"
    ];
    private _crossings = 0;
    {
        if (_x in _lastKnown && {(_x in _inside) isNotEqualTo (_x in _lastInside)}) then {
            _crossings = _crossings + 1;
        };
    } forEach (keys _known);
    ITW_CLASH_SupportsInfluenceLast set [_sideKey,[_inside,_known]];
    _context set ["crossings",_crossings];
    _crossings
};

// Impasse's own live count against its own cap: what an airborne drop counts
// against, the same arithmetic Impasse's spawner does (ITW_Attack.sqf).
ITW_CLASH_Supports_fnc_Headroom = {
    params ["_side"];
    if (isNil "ITW_AtkAiCount" || {isNil "ITW_PlayerSide"}) exitWith {0};
    private _max = (_side isEqualTo ITW_PlayerSide) call ITW_AtkAiCount;
    if !(_max isEqualType 0) exitWith {0};
    _max - ({alive _x} count (units _side))
};

// The squad a drop will carry, as Impasse fields them: a living squad's
// archetype, or failing that eight of the faction's own infantry.
ITW_CLASH_Supports_fnc_Template = {
    params ["_side","_hq"];
    private _templates = [];
    {
        private _group = _x;
        if (isNull _group || {side _group isNotEqualTo _side}) then {continue};
        private _alive = (units _group) select {alive _x};
        if (_alive isEqualTo [] || {(_alive findIf {vehicle _x != _x || {!(_x isKindOf "CAManBase")}}) >= 0}) then {continue};
        private _archetype = +(_group getVariable ["ITW_CLASH_Archetype",[]]);
        if (count _archetype >= 4) then {_templates pushBack _archetype};
    } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    if (_templates isNotEqualTo []) exitWith {selectRandom _templates};
    if (isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes") exitWith {[]};
    private _unitTypes = ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) param [1,[]];
    if (_unitTypes isEqualTo []) exitWith {[]};
    private _template = [];
    for "_i" from 1 to 8 do {_template pushBack (selectRandom _unitTypes)};
    _template
};

// ------------------------------------------------------------------- the pool

// Logged once per flavor, objective, target and reason: a flavor that is on
// cooldown is one line, not one per cluster.
ITW_CLASH_Supports_fnc_Exclude = {
    params ["_context","_flavor","_objective","_targetKey","_reason"];
    (_context get "exclusions") pushBackUnique [_flavor,_objective,_targetKey,_reason];
    false
};

/*
    Gates that depend only on the flavor and the ledger, not on a target.
    Returns "" or a denial reason, and caches it for the assessment.
*/
ITW_CLASH_Supports_fnc_FlavorGate = {
    params ["_context","_flavor"];
    private _cache = _context get "flavorGates";
    if (_flavor in _cache) exitWith {_cache get _flavor};
    private _side = _context get "side";
    private _ledger = _context get "ledger";
    private _row = [_flavor] call ITW_CLASH_Supports_fnc_Row;
    // v8: a console test asks none of the economic questions.
    private _test = _context getOrDefault ["test",false];
    private _reason = switch (true) do {
        case !([_flavor] call ITW_CLASH_Supports_fnc_Enabled): {"DISABLED"};
        case (!_test && {((_ledger get "lanes") getOrDefault [_row get "lane",""]) isNotEqualTo ""}): {"LANE_BUSY"};
        case (!_test && {(_row get "lane") isEqualTo "RECON"} && {time < (_ledger get "reconBlockedUntil")}): {"RELAUNCH"};
        case (!_test && {[_ledger,"flavor:" + _flavor] call ITW_CLASH_Supports_fnc_OnCooldown}): {"COOLDOWN"};
        // v8: nothing this side has can be carried, so there is nothing to deliver.
        case ((_row getOrDefault ["aircraft",""]) isEqualTo "VIV" && {([_side,"DELIVERY"] call ITW_CLASH_Supports_fnc_Classes) isEqualTo []}): {"NO_VEHICLE_FIT"};
        case (!_test && {([_ledger,[_flavor] call ITW_CLASH_Supports_fnc_WalletOf] call ITW_CLASH_Supports_fnc_WalletCash) < ([_flavor,"HOLD"] call ITW_CLASH_Supports_fnc_Price)}): {"INSUFFICIENT_FUNDS"};
        default {""};
    };
    if (_reason isEqualTo "") then {
        ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) params ["_class","_why"];
        if (_class isEqualTo "") then {_reason = _why} else {(_context get "classes") set [_flavor,_class]};
    };
    _cache set [_flavor,_reason];
    _reason
};

/*
    The corridor and origin for a flavor to an objective, cached per
    assessment. Returns [state,origin,spawn] or ["",reason].
*/
ITW_CLASH_Supports_fnc_Route = {
    params ["_context","_flavor","_objective","_aim"];
    private _cacheKey = format ["%1|%2",_flavor,_objective];
    private _cache = _context get "routes";
    if (_cacheKey in _cache) exitWith {_cache get _cacheKey};
    private _side = _context get "side";
    ([_side,_flavor,_aim] call ITW_CLASH_Supports_fnc_Origin) params ["_origin","_why"];
    private _result = if (_origin isEqualTo []) then {["",_why]} else {
        private _spawn = [_origin,_aim,[_flavor] call ITW_CLASH_Supports_fnc_SpawnDistance] call
            ITW_CLASH_Supports_fnc_SpawnPoint;
        private _rule = ([_flavor] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["fighterRule","HARD_KILL"];
        private _corridor = [_context get "hq",_spawn,_aim,_rule] call ITW_CLASH_Supports_fnc_Corridor;
        [_corridor getOrDefault ["state","COLD"],_origin,_spawn,_corridor getOrDefault ["reason",""]]
    };
    _cache set [_cacheKey,_result];
    _result
};

ITW_CLASH_Supports_fnc_CorridorFactor = {
    params ["_state"];
    if (_state in ["HOT","CONTESTED"]) exitWith {ITW_CLASH_SupportsCorridorPenalty};
    1
};

// One candidate, with everything admission and the executor will need.
ITW_CLASH_Supports_fnc_Candidate = {
    params ["_family","_flavor","_objective","_reason","_aim","_weight","_route",["_target",createHashMap],["_extra",createHashMap]];
    private _targetKey = _target getOrDefault ["key",""];
    private _candidate = createHashMapFromArray [
        ["family",_family],["flavor",_flavor],["objective",_objective],["reason",_reason],
        ["aim",+_aim],["weight",_weight],["target",_target],
        ["corridor",_route param [0,""]],["origin",_route param [1,[]]],["spawn",_route param [2,[]]],
        ["key",format ["%1|%2|%3|%4",_family,_flavor,[_objective,3] call {
            params ["_n","_width"];
            private _text = str _n;
            while {count _text < _width} do {_text = "0" + _text};
            _text
        },_targetKey]]
    ];
    {_candidate set [_x,_y]} forEach _extra;
    _candidate
};

/*
    Strike candidates against every cluster the target objectives can see.

    One clustering over the union of their influence areas, so a cluster near
    two objectives is one cluster. Each cluster enters the pool once per
    flavor, at the objective that values it most; the gates that do not depend
    on an objective (class, contact, floor, uncertainty, ETB, danger close) are
    applied once. Its run-in is computed from the cluster itself, not from the
    objective's centre.

    v8: a console test (a context marked test) may give a point of its own
    for an objective's centre (a fourth element) and the flavors to ask
    about, and asks none of the economic questions: no price, no denied
    corridor, and the crossing count, which is the assessments' own record,
    is left alone.
*/
ITW_CLASH_Supports_fnc_StrikeCandidates = {
    params ["_context","_targets",["_flavors",ITW_CLASH_SupportsStrikeFlavors]];
    private _side = _context get "side";
    private _hq = _context get "hq";
    private _ledger = _context get "ledger";
    private _test = _context getOrDefault ["test",false];
    private _objectives = [];
    private _centers = [];
    {
        _x params ["_index","_reason","_urgency",["_at",[]]];
        private _center = if (_at isNotEqualTo []) then {[_at#0,_at#1,0]} else {[_index] call ITW_CLASH_Supports_fnc_ObjectivePos};
        if (_center isEqualTo []) then {continue};
        _objectives pushBack [_index,_reason,_urgency,_center,[_hq,_center] call ITW_CLASH_Supports_fnc_Committed];
        _centers pushBack _center;
    } forEach _targets;
    if (_objectives isEqualTo []) exitWith {[]};

    private _clusters = [_side,_centers,ITW_CLASH_SupportsInfluenceRadius] call ITW_CLASH_Supports_fnc_Clusters;
    if (!_test) then {[_context,_clusters] call ITW_CLASH_Supports_fnc_CountCrossings};
    private _result = [];
    {
        private _cluster = _x;
        private _targetKey = _cluster get "key";
        private _class = _cluster get "class";
        private _aim = _cluster get "aim";
        {
            private _flavor = _x;
            private _row = [_flavor] call ITW_CLASH_Supports_fnc_Row;
            private _base = (_row get "weights") getOrDefault [_class,0];
            if (_flavor isEqualTo "GUIDED" && {_class isEqualTo "LEAD_ONLY"}) then {
                _base = if ((_cluster get "vehicles") > 0) then {1} else {0};
            };
            if (_flavor isEqualTo "CARPET" && {_class isEqualTo "VEH_PARKED"} && {(_cluster get "vehicles") >= 3}) then {
                _base = 2;
            };
            // Zero is impossible, not unlikely: no candidate, nothing to log.
            if (_base <= 0) then {continue};

            private _gate = [_context,_flavor] call ITW_CLASH_Supports_fnc_FlavorGate;
            if (_gate isNotEqualTo "") then {
                [_context,_flavor,-1,"",_gate] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            if (_flavor isEqualTo "BOMB" && {!((_cluster get "best") in ["OBSERVED","FIXED"])}) then {
                [_context,_flavor,-1,_targetKey,"NO_CONTACT"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            if (_flavor isEqualTo "CARPET" && {(_cluster get "count") < ITW_CLASH_SupportsCarpetMinContacts}) then {
                [_context,_flavor,-1,_targetKey,"NOT_CLUSTERED"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            private _floor = if (_flavor in ITW_CLASH_SupportsAcquireFlavors) then {
                ITW_CLASH_SupportsValueFloorAcquire
            } else {ITW_CLASH_SupportsValueFloor};
            if ((_cluster get "worth") < _floor) then {
                [_context,_flavor,-1,_targetKey,"BELOW_FLOOR"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };

            // The spawn is always the full distance out, so this is the
            // flight time to the target whichever objective it is struck for.
            private _ahead = ([_flavor] call ITW_CLASH_Supports_fnc_SpawnDistance)
                / ([_flavor] call ITW_CLASH_Supports_fnc_ProjectionSpeed);
            private _r = [_side,_cluster,_ahead] call ITW_CLASH_Supports_fnc_ClusterUncertainty;
            private _footprint = [_flavor,"footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;
            private _multiplier = 1;
            // The bomb and guided passes acquire on site; uncertainty only
            // sizes their scan.
            if !(_flavor in ITW_CLASH_SupportsAcquireFlavors) then {
                if (_r > ITW_CLASH_SupportsUncertaintyLimit) exitWith {_multiplier = -1};
                _multiplier = (_footprint / (_r max 1)) min 1;
            };
            if (_multiplier < 0) then {
                [_context,_flavor,-1,_targetKey,"TOO_UNCERTAIN"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            private _entities = ([_side,_cluster get "keys",0] call ITW_CLASH_Supports_fnc_TargetNow) param [3,[]];
            if ((_cluster get "vehicles") > 0 && {[_hq,_entities] call ITW_CLASH_Supports_fnc_ETBAnswering}) then {
                [_context,_flavor,-1,_targetKey,"ETB_ANSWERING"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            if ([_context get "friendlies",_aim,_footprint,_flavor] call ITW_CLASH_Supports_fnc_DangerClose) then {
                ["danger-close",[
                    _context get "sign",_flavor,_targetKey,"assess",
                    [_context get "friendlies",_aim,_footprint,_flavor] call ITW_CLASH_Supports_fnc_DangerWhy
                ]] call ITW_CLASH_Supports_fnc_Log;
                [_context,_flavor,-1,_targetKey,"DANGER_CLOSE"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };

            // The objective that values this cluster most, among those that
            // can afford it and reach it.
            private _best = [];
            private _bestWeight = 0;
            {
                _x params ["_index","_reason","_urgency","_center","_committed"];
                private _distance = _aim distance2D _center;
                if (_distance > ITW_CLASH_SupportsInfluenceRadius) then {continue};
                if (!_test && {(_ledger get "cash") < ([_flavor,_reason] call ITW_CLASH_Supports_fnc_Price)}) then {
                    [_context,_flavor,_index,"","INSUFFICIENT_FUNDS"] call ITW_CLASH_Supports_fnc_Exclude;
                    continue
                };
                private _route = [_context,_flavor,_index,_center] call ITW_CLASH_Supports_fnc_Route;
                if ((_route#0) isEqualTo "") then {
                    [_context,_flavor,_index,"",_route#1] call ITW_CLASH_Supports_fnc_Exclude;
                    continue
                };
                if (!_test && {(_route#0) isEqualTo "AIR_DENIED"}) then {
                    [_context,_flavor,_index,"","AIR_DENIED"] call ITW_CLASH_Supports_fnc_Exclude;
                    continue
                };
                private _falloff = [_distance] call ITW_CLASH_Supports_fnc_DistanceWeight;
                private _threat = (_committed findIf {(_x distance2D _aim) <= ITW_CLASH_SupportsThreatProximity}) >= 0;
                if (_threat) then {_falloff = 1};
                private _weight = _base * _multiplier * ([_route#0] call ITW_CLASH_Supports_fnc_CorridorFactor)
                    * _urgency * _falloff;
                if (_weight > _bestWeight) then {
                    _bestWeight = _weight;
                    _best = [_index,_reason,_route,_distance,_threat];
                };
            } forEach _objectives;
            if (_best isEqualTo []) then {continue};

            _best params ["_bestIndex","_bestReason","_bestRoute","_bestDistance","_bestThreat"];
            private _spawn = [_bestRoute#1,_aim,[_flavor] call ITW_CLASH_Supports_fnc_SpawnDistance] call
                ITW_CLASH_Supports_fnc_SpawnPoint;
            _result pushBack ([
                "STRIKE",_flavor,_bestIndex,_bestReason,_aim,_bestWeight,
                [_bestRoute#0,_bestRoute#1,_spawn],_cluster,
                createHashMapFromArray [
                    ["uncertainty",_r],["ahead",_ahead],
                    ["distance",round _bestDistance],["threat",_bestThreat]
                ]
            ] call ITW_CLASH_Supports_fnc_Candidate);
        } forEach _flavors;
    } forEach _clusters;
    _result
};

/*
    Airborne candidates at one objective. Taking: the push is short by no more
    than a drop can carry, or our ground force is far away. Holding: urgency
    does the work, and a held point with no anchor is the strongest case.
*/
/*
    Drop candidates for one objective. v7: for the flavors asked for (the
    paradrops, or delivery), each from its own wallet; a delivery carries no
    squads, only the vehicle's crew.
*/
ITW_CLASH_Supports_fnc_DropCandidates = {
    params ["_context","_objective","_reason","_urgency","_entry",["_flavors",ITW_CLASH_SupportsDropFlavors]];
    private _side = _context get "side";
    private _hq = _context get "hq";
    private _center = [_objective] call ITW_CLASH_Supports_fnc_ObjectivePos;
    if (_center isEqualTo []) exitWith {[]};
    private _result = [];
    private _intel = [_side,_center] call ITW_CLASH_Knowledge_fnc_IntelState;
    {
        private _flavor = _x;
        private _gate = [_context,_flavor] call ITW_CLASH_Supports_fnc_FlavorGate;
        if (_gate isNotEqualTo "") then {
            [_context,_flavor,_objective,"",_gate] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        if !(_intel in ["RECENT_CONTACT","RECENTLY_CLEARED"]) then {
            [_context,_flavor,_objective,"","DZ_UNASSESSED"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        private _class = (_context get "classes") getOrDefault [_flavor,""];
        private _delivery = _flavor in ITW_CLASH_SupportsVehicleFlavors;
        private _template = [];
        private _squadSize = 0;
        private _squads = 0;
        if (!_delivery) then {
            private _seats = [_class] call ITW_CLASH_Supports_fnc_CargoSeats;
            _template = _context get "template";
            if (_template isEqualTo []) then {
                _template = [_side,_hq] call ITW_CLASH_Supports_fnc_Template;
                _context set ["template",_template];
            };
            _squadSize = (count _template) min _seats;
            private _cap = if (_flavor isEqualTo "AIRBORNE_PLANE") then {ITW_CLASH_SupportsAirbornePlaneSquads} else {ITW_CLASH_SupportsAirborneHeliSquads};
            _squads = ((floor (_seats / ((count _template) max 1))) max 1) min _cap;
        };
        if (!_delivery && {_squadSize < 4}) then {
            [_context,_flavor,_objective,"","NO_AIRCRAFT"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        if (([_context get "ledger",[_flavor] call ITW_CLASH_Supports_fnc_WalletOf] call ITW_CLASH_Supports_fnc_WalletCash) < ([_flavor,_reason] call ITW_CLASH_Supports_fnc_Price)) then {
            [_context,_flavor,_objective,"","INSUFFICIENT_FUNDS"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        private _need = if (_delivery) then {ITW_CLASH_SupportsVehicleDropCrew} else {_squads * _squadSize};
        if (([_side] call ITW_CLASH_Supports_fnc_Headroom) < _need) then {
            [_context,_flavor,_objective,"","NO_HEADROOM"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        private _route = [_context,_flavor,_objective,_center] call ITW_CLASH_Supports_fnc_Route;
        if ((_route#0) isEqualTo "") then {
            [_context,_flavor,_objective,"",_route#1] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        if ((_route#0) isEqualTo "AIR_DENIED") then {
            [_context,_flavor,_objective,"","AIR_DENIED"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };

        private _weight = 1;
        if (_reason isEqualTo "TAKE") then {
            // Short by more than the best strike could remove?
            private _ratio = missionNamespace getVariable ["ITW_CLASH_ColossusPushRatio",2];
            private _enemy = _entry getOrDefault ["enemyReported",-1];
            if (_enemy < 0) then {_enemy = _entry getOrDefault ["enemy",0]};
            private _wanted = ((_enemy * _ratio) - (_entry getOrDefault ["committed",0])) max 0;
            private _gap = _wanted - (_entry getOrDefault ["available",0]);
            private _bestStrike = 0;
            {
                _bestStrike = _bestStrike max (_x get "worth");
            } forEach ([_side,_center,call ITW_CLASH_Supports_fnc_ObjectiveRadius] call ITW_CLASH_Supports_fnc_Clusters);
            if (_gap > (_bestStrike * _ratio)) then {_weight = _weight + 1};
        };
        // Our nearest ground force is far: the drop gets there first.
        private _nearest = 1e10;
        {
            private _leader = leader _x;
            if (!isNull _leader && {alive _leader} && {!((vehicle _leader) isKindOf "Air")}) then {
                _nearest = _nearest min (_leader distance2D _center);
            };
        } forEach (_hq getVariable ["RydHQ_Friends",[]]);
        if (_nearest > ITW_CLASH_SupportsAirborneFarForce) then {_weight = _weight + 1};
        if (_reason isEqualTo "HOLD" && {_objective in (_context get "unanchored")}) then {_weight = 3};
        _weight = _weight * _urgency * ([_route#0] call ITW_CLASH_Supports_fnc_CorridorFactor);

        _result pushBack ([
            if (_delivery) then {"DELIVER"} else {"LAND"},_flavor,_objective,_reason,_center,_weight,_route,createHashMap,
            createHashMapFromArray [
                ["squads",_squads],["squadSize",_squadSize],["template",+_template],["need",_need],
                ["ahead",((_route#2) distance2D _center) / ([_flavor] call ITW_CLASH_Supports_fnc_ProjectionSpeed)]
            ]
        ] call ITW_CLASH_Supports_fnc_Candidate);
    } forEach _flavors;
    _result
};

// ------------------------------------------------------------- v7: direct

/*
    v7. A context for a decision made outside an assessment (a console test).
    The same fields an assessment's has, as far as admission needs them.
*/
ITW_CLASH_Supports_fnc_MakeContext = {
    params ["_side"];
    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
        [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    if (isNull _hq) exitWith {createHashMap};
    [_side] call ITW_CLASH_Supports_fnc_Accrue;
    createHashMapFromArray [
        ["side",_side],["hq",_hq],["sign",_hq getVariable ["RydHQ_CodeSign","?"]],
        ["ledger",[_side] call ITW_CLASH_Supports_fnc_Ledger],
        ["friendlies",[_side] call ITW_CLASH_Supports_fnc_Friendlies],
        ["flavorGates",createHashMap],["classes",createHashMap],["routes",createHashMap],
        ["exclusions",[]],["unanchored",[]],["template",[]]
    ]
};

/*
    v7. A pick made directly, without a pool: a bite-back wave's part, or a
    console test's. Every physical question a pool asks (the aircraft, its
    origin and route, the squads it can carry), none of the economic ones:
    the caller sets wallet, lane, price and delay. _squads above 0 asks for
    that many squads, each cut to fit. Returns [pick, ""] or [[], reason].
*/
ITW_CLASH_Supports_fnc_DirectPick = {
    params ["_context","_flavor","_objective","_reason",["_squads",-1]];
    private _side = _context get "side";
    private _hq = _context get "hq";
    if !([_flavor] call ITW_CLASH_Supports_fnc_Enabled) exitWith {[[],"DISABLED"]};
    private _center = [_objective] call ITW_CLASH_Supports_fnc_ObjectivePos;
    if (_center isEqualTo []) exitWith {[[],"NO_ORIGIN"]};
    ([_side,_flavor] call ITW_CLASH_Supports_fnc_PickClass) params ["_class","_why"];
    if (_class isEqualTo "") exitWith {[[],_why]};
    (_context get "classes") set [_flavor,_class];
    private _route = [_context,_flavor,_objective,_center] call ITW_CLASH_Supports_fnc_Route;
    if ((_route#0) isEqualTo "") exitWith {[[],_route#1]};

    private _extra = createHashMapFromArray [
        ["ahead",((_route#2) distance2D _center) / ([_flavor] call ITW_CLASH_Supports_fnc_ProjectionSpeed)]
    ];
    private _failed = "";
    if (_flavor in ITW_CLASH_SupportsVehicleFlavors) then {
        if (([_side,"DELIVERY"] call ITW_CLASH_Supports_fnc_Classes) isEqualTo []) then {_failed = "NO_VEHICLE_FIT"};
        _extra set ["need",ITW_CLASH_SupportsVehicleDropCrew];
        _extra set ["squads",0];
        _extra set ["squadSize",0];
    } else {
        private _template = [_side,_hq] call ITW_CLASH_Supports_fnc_Template;
        private _seats = [_class] call ITW_CLASH_Supports_fnc_CargoSeats;
        private _count = if (_squads > 0) then {_squads} else {
            private _cap = if (_flavor isEqualTo "AIRBORNE_PLANE") then {ITW_CLASH_SupportsAirbornePlaneSquads} else {ITW_CLASH_SupportsAirborneHeliSquads};
            ((floor (_seats / ((count _template) max 1))) max 1) min _cap
        };
        // Asked for more squads than fit whole: each is cut so all of them fit.
        private _squadSize = (count _template) min (floor (_seats / (_count max 1)));
        if (_squadSize < ITW_CLASH_SupportsAirborneMinSquadCore) then {_failed = "NO_SQUADS"};
        _extra set ["squads",_count];
        _extra set ["squadSize",_squadSize];
        _extra set ["template",+_template];
        _extra set ["need",_count * _squadSize];
    };
    if (_failed isNotEqualTo "") exitWith {[[],_failed]};
    [([
        if (_flavor in ITW_CLASH_SupportsVehicleFlavors) then {"DELIVER"} else {"LAND"},
        _flavor,_objective,_reason,_center,1,_route,createHashMap,_extra
    ] call ITW_CLASH_Supports_fnc_Candidate),""]
};

// ---------------------------------------------------------- v7: bite-back

/*
    A point's Impasse flag as this side sees it: [ours, phase]. The flag and
    its bar are what every player sees on screen, so reading them is no
    omniscience. A flag Impasse has not set up yet says nothing: [true, 1].
*/
ITW_CLASH_Supports_fnc_FlagState = {
    params ["_side","_index"];
    if (isNil "ITW_Objectives" || {isNil "ITW_PlayerSide"} || {_index < 0} || {_index >= count ITW_Objectives}) exitWith {[true,1]};
    private _entry = ITW_Objectives#_index;
    if (count _entry <= ITW_OBJ_FLAG) exitWith {[true,1]};
    private _flag = _entry#ITW_OBJ_FLAG;
    if (!(_flag isEqualType objNull) || {isNull _flag}) exitWith {[true,1]};
    private _playerFlag = _flag getVariable "ITW_FlagIsPlayer";
    if (isNil "_playerFlag" || {!(_playerFlag isEqualType true)}) exitWith {[true,1]};
    private _phase = _flag getVariable ["ITW_FlagPhase",1];
    if !(_phase isEqualType 0) then {_phase = 1};
    [_playerFlag isEqualTo (_side isEqualTo ITW_PlayerSide),_phase]
};

/*
    Why a held point wants a wave now, or "". Reads its flag against the
    last look (kept in the ledger) and its pressure from this assessment:
      enemy-flag-up  the enemy's flag is going up on a point we still hold
      flag-falling   ours is lower than last time
      flag-down      ours is below FlagFloor and not rising
      unanchored     under pressure with nobody of ours on it
      outnumbered    under pressure, defenders below the contested ratio
    Returns [why, rank, phase, pressure].
*/
ITW_CLASH_Supports_fnc_BiteBackWhy = {
    params ["_context","_index","_targets"];
    private _side = _context get "side";
    private _phases = (_context get "ledger") get "bitePhases";
    ([_side,_index] call ITW_CLASH_Supports_fnc_FlagState) params ["_ours","_phase"];
    private _key = str _index;
    private _was = _phases getOrDefault [_key,[]];
    _phases set [_key,[_ours,_phase]];
    private _wasOurs = _was isNotEqualTo [] && {_was#0};
    private _flagWhy = switch (true) do {
        case (!_ours): {"enemy-flag-up"};
        case (_wasOurs && {_phase < ((_was#1) - 0.001)}): {"flag-falling"};
        case (_phase < ITW_CLASH_SupportsBiteBackFlagFloor && {!_wasOurs || {_phase <= ((_was#1) + 0.001)}}): {"flag-down"};
        default {""};
    };
    private _t = _targets findIf {(_x#0) isEqualTo _index && {(_x#1) isEqualTo "HOLD"}};
    private _urgency = if (_t < 0) then {0} else {(_targets#_t)#2};
    private _pressure = if (_t < 0) then {0} else {(_targets#_t)#4};
    private _why = switch (true) do {
        case (_flagWhy isNotEqualTo ""): {_flagWhy};
        case (_urgency >= 3): {"unanchored"};
        case (_urgency >= 2.5): {"outnumbered"};
        default {""};
    };
    private _rank = switch (_why) do {
        case "enemy-flag-up": {5};
        case "flag-falling": {4.5};
        case "flag-down": {4};
        default {_urgency};
    };
    [_why,_rank,_phase,_pressure]
};

/*
    One wave for the most urgent point this side holds that wants one and
    may have it: the pot holds a wave, its lanes are free, the point was not
    answered within Cooldown, and it is not Impasse's defend-phase point
    while the defend phase runs. A point that wants a wave and may not have
    one says why once, not every assessment.
*/
ITW_CLASH_Supports_fnc_BiteBack = {
    params ["_context","_targets",["_picture",[]]];
    if (!ITW_CLASH_SupportsBiteBackEnabled) exitWith {false};
    private _side = _context get "side";
    private _sign = _context get "sign";
    private _ledger = _context get "ledger";
    private _said = _ledger get "biteSaid";
    if (_picture isEqualTo []) then {_picture = _context getOrDefault ["picture",[]]};
    private _defendFocus = if (isNil "ITW_CLASH_fnc_DefendPhaseObjective") then {-1} else {call ITW_CLASH_fnc_DefendPhaseObjective};
    private _defendRunning = (missionNamespace getVariable ["ITW_defendRunning",false]) isEqualTo true;

    private _wants = [];
    {
        private _index = _x get "objective";
        if (_index < 0 || {!([_side,_index] call ITW_CLASH_Supports_fnc_HeldBy)}) then {continue};
        if (!isNil "ITW_CLASH_fnc_ObjectiveFrozen" && {[_index] call ITW_CLASH_fnc_ObjectiveFrozen}) then {continue};
        ([_context,_index,_targets] call ITW_CLASH_Supports_fnc_BiteBackWhy) params ["_why","_rank","_phase","_pressure"];
        if (_why isEqualTo "") then {
            if ((_said getOrDefault [str _index,""]) isNotEqualTo "") then {_said set [str _index,""]};
            continue
        };
        _wants pushBack [_rank,_index,_why,_phase,_pressure];
    } forEach _picture;
    if (_wants isEqualTo []) exitWith {false};
    _wants = [_wants,[],{-(_x#0)},"ASCEND"] call BIS_fnc_sortBy;

    private _launched = false;
    {
        _x params ["","_index","_why","_phase","_pressure"];
        private _lanes = _ledger get "lanes";
        private _hold = switch (true) do {
            case (_defendRunning && {_index isEqualTo _defendFocus}): {"DEFEND_PHASE"};
            case ([_ledger,"bite:" + str _index] call ITW_CLASH_Supports_fnc_OnCooldown): {"COOLDOWN"};
            case ((_ledger getOrDefault ["biteCash",0]) < 1): {"INSUFFICIENT_FUNDS"};
            case ((_lanes getOrDefault ["BITE_DROP",""]) isNotEqualTo "" || {(_lanes getOrDefault ["BITE_VEHICLE",""]) isNotEqualTo ""}): {"LANE_BUSY"};
            default {""};
        };
        if (_hold isEqualTo "") then {
            _launched = [_context,_index,_why,_phase,_pressure] call ITW_CLASH_Supports_fnc_LaunchWave;
            if (!_launched) then {_hold = "REFUSED"};
        };
        if (_launched) exitWith {_said set [str _index,""]};
        private _line = _why + "|" + _hold;
        if ((_said getOrDefault [str _index,""]) isNotEqualTo _line) then {
            _said set [str _index,_line];
            ["biteback-held",[
                _sign,_index,_why,(round (_phase * 100)) / 100,(round (_pressure * 10)) / 10,_hold,
                (round ((_ledger getOrDefault ["biteCash",0]) * 100)) / 100
            ]] call ITW_CLASH_Supports_fnc_Log;
        };
    } forEach _wants;
    _launched
};

/*
    The wave itself: a helicopter drop of BiteBackSquads squads and one
    vehicle, both to hold the point, out after a short scramble. The pot pays
    one wave, split between the parts that go; a part the side cannot fly
    stays home and costs nothing. A console test (_test) takes no money and
    no cooldown, uses lanes of its own, and skips the map's gates.
*/
ITW_CLASH_Supports_fnc_LaunchWave = {
    params ["_context","_index","_why",["_phase",1],["_pressure",0],["_test",false]];
    private _side = _context get "side";
    private _sign = _context get "sign";
    private _ledger = _context get "ledger";
    ITW_CLASH_SupportsWaveSerial = ITW_CLASH_SupportsWaveSerial + 1;
    private _wave = format ["BB-%1-%2",[_side] call ITW_CLASH_Supports_fnc_SideKey,ITW_CLASH_SupportsWaveSerial];

    private _parts = [];
    private _refused = [];
    {
        _x params ["_flavor","_lane"];
        private _squads = if (_flavor in ITW_CLASH_SupportsVehicleFlavors) then {-1} else {ITW_CLASH_SupportsBiteBackSquads};
        ([_context,_flavor,_index,"HOLD",_squads] call ITW_CLASH_Supports_fnc_DirectPick) params ["_pick","_whyNot"];
        if (_pick isEqualTo []) then {
            _refused pushBack [_flavor,_whyNot];
        } else {
            _parts pushBack [_pick,_lane];
        };
    } forEach [["AIRBORNE_HELI","BITE_DROP"],["VEHICLE_DROP","BITE_VEHICLE"]];
    if (_parts isEqualTo []) exitWith {
        ["biteback-refused",[_sign,_index,_why,_wave,_refused]] call ITW_CLASH_Supports_fnc_Log;
        false
    };
    private _need = 0;
    {_need = _need + ((_x#0) getOrDefault ["need",0])} forEach _parts;
    if (!_test && {([_side] call ITW_CLASH_Supports_fnc_Headroom) < _need}) exitWith {
        ["biteback-refused",[_sign,_index,_why,_wave,[["WAVE","NO_HEADROOM"]]]] call ITW_CLASH_Supports_fnc_Log;
        false
    };

    private _share = 1 / (count _parts);
    private _ids = [];
    {
        _x params ["_pick","_lane"];
        _pick set ["lane",if (_test) then {format ["TEST-%1-%2",_wave,_forEachIndex]} else {_lane}];
        _pick set ["wallet",if (_test) then {"TEST"} else {"BITE"}];
        _pick set ["price",if (_test) then {0} else {_share}];
        _pick set ["delay",ITW_CLASH_SupportsBiteBackDelayMin + random ((ITW_CLASH_SupportsBiteBackDelayMax - ITW_CLASH_SupportsBiteBackDelayMin) max 0)];
        _pick set ["wave",_wave];
        if (_test) then {_pick set ["test",true]};
        _context set ["admitted",""];
        if ([_context,_pick] call ITW_CLASH_Supports_fnc_Admit) then {
            _ids pushBack [_pick get "flavor",_context getOrDefault ["admitted",""]];
        } else {
            _refused pushBack [_pick get "flavor","ADMISSION"];
        };
    } forEach _parts;
    if (_ids isEqualTo []) exitWith {
        ["biteback-refused",[_sign,_index,_why,_wave,_refused]] call ITW_CLASH_Supports_fnc_Log;
        false
    };
    if (!_test) then {
        (_ledger get "cooldowns") set ["bite:" + str _index,time + ITW_CLASH_SupportsBiteBackCooldown];
    };
    ["biteback-wave",[
        _sign,_index,_why,(round (_phase * 100)) / 100,(round (_pressure * 10)) / 10,_wave,_ids,_refused,
        (round ((_ledger getOrDefault ["biteCash",0]) * 100)) / 100,
        if (_test) then {"test"} else {"live"}
    ]] call ITW_CLASH_Supports_fnc_Log;
    true
};

/*
    Where the UAV should be: the plan objective if nobody has looked at it or
    its enemy can no longer be placed, else another objective known only by
    leads, else overwatch of the plan objective. Refreshed every assessment
    without a roll.
*/
// v5. Where this side's UAVs have died on arrival lately.
ITW_CLASH_Supports_fnc_MarkKillbox = {
    params ["_side","_position"];
    private _key = [_side] call ITW_CLASH_Supports_fnc_SideKey;
    isNil {
        private _boxes = (ITW_CLASH_SupportsUAVKillboxes getOrDefault [_key,[]]) select {
            (time - (_x#1)) <= ITW_CLASH_SupportsUAVKillboxDuration
        };
        _boxes pushBack [[_position#0,_position#1,0],time];
        ITW_CLASH_SupportsUAVKillboxes set [_key,_boxes];
    };
    ["uav-killbox",[_key,(_position apply {round _x}) select [0,2],ITW_CLASH_SupportsUAVKillboxDuration]] call
        ITW_CLASH_Supports_fnc_Log;
};

ITW_CLASH_Supports_fnc_InKillbox = {
    params ["_side","_position"];
    if (_position isEqualTo []) exitWith {false};
    private _key = [_side] call ITW_CLASH_Supports_fnc_SideKey;
    ((ITW_CLASH_SupportsUAVKillboxes getOrDefault [_key,[]]) findIf {
        (time - (_x#1)) <= ITW_CLASH_SupportsUAVKillboxDuration
        && {((_x#0) distance2D _position) <= ITW_CLASH_SupportsUAVKillboxRadius}
    }) >= 0
};

ITW_CLASH_Supports_fnc_UAVTask = {
    params ["_side","_planObjective","_objectives"];
    private _planPos = [_planObjective] call ITW_CLASH_Supports_fnc_ObjectivePos;
    // v5: a place this side's UAVs keep dying over is not a task.
    private _planBoxed = [_side,_planPos] call ITW_CLASH_Supports_fnc_InKillbox;
    if (_planBoxed) then {_planPos = []};
    // Where uncertainty keeps the commander from deciding, look there first:
    // nobody has looked, or the enemy seen there can no longer be placed.
    private _planIntel = if (_planPos isEqualTo []) then {""} else {
        [_side,_planPos] call ITW_CLASH_Knowledge_fnc_IntelState
    };
    if (_planIntel isEqualTo "UNOBSERVED") exitWith {[_planPos,_planObjective,"unobserved-plan"]};
    if (_planIntel isEqualTo "STALE_CONTACT") exitWith {[_planPos,_planObjective,"stale-plan"]};
    private _stale = _objectives findIf {
        private _pos = [_x] call ITW_CLASH_Supports_fnc_ObjectivePos;
        _pos isNotEqualTo []
        && {!([_side,_pos] call ITW_CLASH_Supports_fnc_InKillbox)}
        && {([_side,_pos] call ITW_CLASH_Knowledge_fnc_IntelState) isEqualTo "STALE_CONTACT"}
    };
    if (_stale >= 0) exitWith {
        private _index = _objectives#_stale;
        [[_index] call ITW_CLASH_Supports_fnc_ObjectivePos,_index,"stale-contact"]
    };
    if (_planPos isNotEqualTo []) exitWith {[_planPos,_planObjective,"overwatch"]};
    if (_planBoxed) exitWith {[[],_planObjective,"killbox"]};
    [[],-1,"none"]
};

// ------------------------------------------------------------------- assess

/*
    One assessment for one commander, called by COLOSSUS after its order.
*/
ITW_CLASH_Supports_fnc_Assess = {
    params ["_hq","_picture",["_posture","PUSH"],["_plan",createHashMap]];
    if (!ITW_CLASH_SupportsEnabled || {isNull _hq}) exitWith {false};
    private _side = side _hq;
    private _sign = _hq getVariable ["RydHQ_CodeSign","?"];
    private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
    [_side] call ITW_CLASH_Supports_fnc_Accrue;

    private _planObjective = _plan getOrDefault ["objective",-1];
    private _vulnerable = missionNamespace getVariable ["ITW_CLASH_ColossusVulnerable",2];
    private _contested = missionNamespace getVariable ["ITW_CLASH_ColossusContested",0.8];
    private _unanchored = if (isNil "ITW_CLASH_Colossus_fnc_HoldingUnanchored") then {[]} else {
        [_hq] call ITW_CLASH_Colossus_fnc_HoldingUnanchored
    };

    private _context = createHashMapFromArray [
        ["side",_side],["hq",_hq],["sign",_sign],["ledger",_ledger],
        ["friendlies",[_side] call ITW_CLASH_Supports_fnc_Friendlies],
        ["flavorGates",createHashMap],["classes",createHashMap],["routes",createHashMap],
        ["exclusions",[]],["unanchored",_unanchored],["template",[]]
    ];

    // Where supports may go: the plan objective under PUSH, and any held
    // objective under pressure. Pressure is read from REPORTED strength.
    private _targets = [];
    {
        private _entry = _x;
        private _index = _entry get "objective";
        if (!isNil "ITW_CLASH_fnc_ObjectiveFrozen" && {[_index] call ITW_CLASH_fnc_ObjectiveFrozen}) then {
            [_context,"*",_index,"","OBJECTIVE_FROZEN"] call ITW_CLASH_Supports_fnc_Exclude;
            continue
        };
        private _committed = _entry getOrDefault ["committed",0];
        if ([_side,_index] call ITW_CLASH_Supports_fnc_HeldBy) then {
            // Pressure from the point's whole influence area, not just the
            // 500 m around it: a tank down the road shelling the defenders
            // is pressure on the point.
            private _pressure = [_side,[_index] call ITW_CLASH_Supports_fnc_ObjectivePos] call
                ITW_CLASH_Supports_fnc_Pressure;
            if (_pressure <= 0) then {continue};
            private _ratio = _committed / _pressure;
            if (_ratio >= _vulnerable) then {continue};
            private _urgency = switch (true) do {
                case (_index in _unanchored): {3};
                case (_ratio < _contested): {2.5};
                default {1.5};
            };
            _targets pushBack [_index,"HOLD",_urgency,_entry,_pressure];
        } else {
            if (_index isNotEqualTo _planObjective) then {continue};
            if (_posture isEqualTo "CONSOLIDATE") then {
                [_context,"*",_index,"","CONSOLIDATING"] call ITW_CLASH_Supports_fnc_Exclude;
                continue
            };
            _targets pushBack [_index,"TAKE",1,_entry,-1];
        };
    } forEach _picture;

    private _pool = [];
    private _active = _targets select {
        private _index = _x#0;
        if (
            ITW_CLASH_SupportsObjectiveCooldown > 0
            && {[_ledger,"objective:" + str _index] call ITW_CLASH_Supports_fnc_OnCooldown}
        ) then {
            [_context,"*",_index,"","COOLDOWN"] call ITW_CLASH_Supports_fnc_Exclude;
            false
        } else {true};
    };
    _context set ["targets",_active apply {
        [_x#0,_x#1,_x#2,(round ((_x#4) * 10)) / 10]
    }];
    _pool append ([_context,_active] call ITW_CLASH_Supports_fnc_StrikeCandidates);

    // The UAV: where it should be is decided every time; launching it is a
    // candidate like any other.
    private _objectives = (_picture apply {_x get "objective"}) select {
        !([_side,_x] call ITW_CLASH_Supports_fnc_HeldBy) || {_x in (_targets apply {_x#0})}
    };
    private _task = [_side,_planObjective,_objectives] call ITW_CLASH_Supports_fnc_UAVTask;
    ITW_CLASH_SupportsUAVTasks set [[_side] call ITW_CLASH_Supports_fnc_SideKey,_task];
    _task params ["_taskPos","_taskObjective","_taskWhy"];
    if (_taskWhy isEqualTo "killbox") then {
        [_context,"UAV",_taskObjective,"","UAV_KILLBOX"] call ITW_CLASH_Supports_fnc_Exclude;
    };
    if (_taskPos isNotEqualTo []) then {
        private _gate = [_context,"UAV"] call ITW_CLASH_Supports_fnc_FlavorGate;
        if (_gate isEqualTo "" && {(_ledger get "cash") < (["UAV","TAKE"] call ITW_CLASH_Supports_fnc_Price)}) then {
            _gate = "INSUFFICIENT_FUNDS";
        };
        if (_gate isNotEqualTo "") then {
            [_context,"UAV",_taskObjective,"",_gate] call ITW_CLASH_Supports_fnc_Exclude;
        } else {
            private _route = [_context,"UAV",_taskObjective,_taskPos] call ITW_CLASH_Supports_fnc_Route;
            switch (true) do {
                case ((_route#0) isEqualTo ""): {
                    [_context,"UAV",_taskObjective,"",_route#1] call ITW_CLASH_Supports_fnc_Exclude;
                };
                case ((_route#0) isEqualTo "AIR_DENIED"): {
                    [_context,"UAV",_taskObjective,"","AIR_DENIED"] call ITW_CLASH_Supports_fnc_Exclude;
                };
                default {
                    private _weight = switch (_taskWhy) do {
                        case "unobserved-plan";
                        case "stale-plan": {3};
                        case "stale-contact": {1};
                        default {0.5};
                    };
                    _pool pushBack ([
                        "LOOK","UAV",_taskObjective,"TAKE",_taskPos,_weight,_route
                    ] call ITW_CLASH_Supports_fnc_Candidate);
                };
            };
        };
    };

    // Save is an option of its own: one roll decides whether and what.
    private _saveWeight = [_ledger,"MAIN"] call ITW_CLASH_Supports_fnc_SaveWeight;
    _pool pushBack (["SAVE","SAVE",-1,"",[],_saveWeight,["",[],[]]] call ITW_CLASH_Supports_fnc_Candidate);
    [_context,_posture,_planObjective,_pool,"pool"] call ITW_CLASH_Supports_fnc_Decide;

    /*
        v7. The drops decide on their own: a bite-back wave for a point being
        lost first (its own pot and lanes), then one pick among the paradrops
        and one among deliveries, each with its own SAVE, from the drop
        wallet. None of them waits on a strike, or on each other.
    */
    [_context,_targets,_picture] call ITW_CLASH_Supports_fnc_BiteBack;
    {
        _x params ["_flavors","_event"];
        _context set ["exclusions",[]];
        private _drops = [];
        {
            _x params ["_index","_reason","_urgency","_entry"];
            _drops append ([_context,_index,_reason,_urgency,_entry,_flavors] call ITW_CLASH_Supports_fnc_DropCandidates);
        } forEach _active;
        // Nothing offered and nothing refused: nothing to say.
        if (_drops isEqualTo [] && {(_context get "exclusions") isEqualTo []}) then {continue};
        _drops pushBack (["SAVE","SAVE",-1,"",[],[_ledger,"DROP"] call ITW_CLASH_Supports_fnc_SaveWeight,["",[],[]]] call
            ITW_CLASH_Supports_fnc_Candidate);
        [_context,_posture,_planObjective,_drops,_event] call ITW_CLASH_Supports_fnc_Decide;
    } forEach [
        [ITW_CLASH_SupportsDropFlavors,"drop-pool"],
        [ITW_CLASH_SupportsVehicleFlavors,"vehicle-pool"]
    ];
    true
};

// SAVE's pull, by how full the wallet is: 3, 2, 1 and 0.5, times SaveScale.
ITW_CLASH_Supports_fnc_SaveWeight = {
    params ["_ledger","_wallet"];
    private _cap = ([_wallet] call ITW_CLASH_Supports_fnc_WalletCap) max 1;
    private _fill = ([_ledger,_wallet] call ITW_CLASH_Supports_fnc_WalletCash) / _cap;
    ITW_CLASH_SupportsSaveScale * (switch (true) do {
        case (_fill < (1 / 3)): {3};
        case (_fill < (2 / 3)): {2};
        case (_fill < 1): {1};
        default {0.5};
    })
};

// One pool, one roll, one line; a pick that is not SAVE goes to admission.
ITW_CLASH_Supports_fnc_Decide = {
    params ["_context","_posture","_planObjective","_pool",["_event","pool"]];
    ([_pool] call ITW_CLASH_Supports_fnc_Pick) params ["_pick","_draw","_total"];
    [_context,_posture,_planObjective,_pool,_pick,_draw,_total,_event] call ITW_CLASH_Supports_fnc_LogPool;
    if (isNil "_pick" || {(_pick get "family") isEqualTo "SAVE"}) exitWith {false};
    [_context,_pick] call ITW_CLASH_Supports_fnc_Admit
};

/*
    The weighted pick, in a stable order, with its draw returned so any pick
    can be recomputed from the log.
*/
ITW_CLASH_Supports_fnc_Pick = {
    params ["_pool"];
    if (_pool isEqualTo []) exitWith {[nil,0,0]};
    private _ordered = [_pool,[],{_x get "key"},"ASCEND"] call BIS_fnc_sortBy;
    private _total = 0;
    {_total = _total + ((_x get "weight") max 0)} forEach _ordered;
    if (_total <= 0) exitWith {[nil,0,0]};
    private _draw = random _total;
    private _running = 0;
    private _pick = _ordered select ((count _ordered) - 1);
    {
        _running = _running + ((_x get "weight") max 0);
        if (_draw < _running) exitWith {_pick = _x};
    } forEach _ordered;
    [_pick,_draw,_total]
};

ITW_CLASH_Supports_fnc_LogPool = {
    params ["_context","_posture","_planObjective","_pool","_pick","_draw","_total",["_event","pool"]];
    private _ordered = [_pool,[],{_x get "key"},"ASCEND"] call BIS_fnc_sortBy;
    private _entries = _ordered apply {
        private _target = _x get "target";
        [
            _x get "flavor",_x get "objective",_x get "reason",
            _target getOrDefault ["key",""],_target getOrDefault ["class",""],
            _target getOrDefault ["best",""],
            (round ((_x get "weight") * 100)) / 100
        ]
    };
    private _exclusions = _context get "exclusions";
    private _shown = _exclusions select [0,ITW_CLASH_SupportsLogExclusions];
    private _picked = if (isNil "_pick") then {"none"} else {(_pick get "flavor") + "@" + str (_pick get "objective")};
    // v7: the drop pools report the drop wallet.
    private _wallet = if (_event isEqualTo "pool") then {"MAIN"} else {"DROP"};
    [_event,[
        _context get "sign",_posture,_planObjective,
        _picked,(round (_draw * 1000)) / 1000,(round (_total * 1000)) / 1000,
        _entries,_shown,(count _exclusions) - (count _shown),
        round ([_context get "ledger",_wallet] call ITW_CLASH_Supports_fnc_WalletCash),
        _context getOrDefault ["targets",[]],
        _context getOrDefault ["crossings",0]
    ]] call ITW_CLASH_Supports_fnc_Log;
};

// ----------------------------------------------------------------- admission

/*
    The proposal becomes a commitment, or does not. Money, the lane and the
    cooldowns are taken in one unscheduled block: nothing can interleave, so
    two proposals in the same frame can never spend the same cash.
*/
/*
    v7: a pick can carry its own wallet, lane, price, setup delay and test
    flag (a bite-back wave, a console test). Without them it is the flavor's
    row, as before. A pick that brings its own lane is not the flavor's
    ordinary use, so the flavor's cooldown is neither checked nor started.
*/
ITW_CLASH_Supports_fnc_Admit = {
    params ["_context","_pick"];
    private _side = _context get "side";
    private _flavor = _pick get "flavor";
    private _reason = _pick get "reason";
    private _row = [_flavor] call ITW_CLASH_Supports_fnc_Row;
    private _ownLane = "lane" in _pick;
    private _lane = _pick getOrDefault ["lane",_row get "lane"];
    private _wallet = _pick getOrDefault ["wallet",[_flavor] call ITW_CLASH_Supports_fnc_WalletOf];
    private _price = _pick getOrDefault ["price",[_flavor,_reason] call ITW_CLASH_Supports_fnc_Price];
    private _cashKey = [_wallet] call ITW_CLASH_Supports_fnc_WalletKey;
    private _id = "";
    private _denied = "";

    isNil {
        private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
        private _lanes = _ledger get "lanes";
        switch (true) do {
            case ((_lanes getOrDefault [_lane,""]) isNotEqualTo ""): {_denied = "LANE_BUSY"};
            case (!_ownLane && {[_ledger,"flavor:" + _flavor] call ITW_CLASH_Supports_fnc_OnCooldown}): {_denied = "COOLDOWN"};
            case (([_ledger,_wallet] call ITW_CLASH_Supports_fnc_WalletCash) < _price): {_denied = "INSUFFICIENT_FUNDS"};
            default {
                ITW_CLASH_SupportsSerial = ITW_CLASH_SupportsSerial + 1;
                _id = format ["SUP-%1-%2",[_side] call ITW_CLASH_Supports_fnc_SideKey,ITW_CLASH_SupportsSerial];
                if (_wallet isNotEqualTo "TEST") then {
                    _ledger set [_cashKey,(_ledger getOrDefault [_cashKey,0]) - _price];
                };
                _lanes set [_lane,_id];
                private _cooldowns = _ledger get "cooldowns";
                if (!_ownLane) then {
                    _cooldowns set ["flavor:" + _flavor,time + ([_flavor,"cooldown",0] call ITW_CLASH_Supports_fnc_RowNumber)];
                };
                if ((_pick get "objective") >= 0 && {_lane isEqualTo "COMMIT"}) then {
                    _cooldowns set ["objective:" + str (_pick get "objective"),time + ITW_CLASH_SupportsObjectiveCooldown];
                };
            };
        };
    };

    if (_id isEqualTo "") exitWith {
        ["admission",[_context get "sign",_flavor,_pick get "objective","DENIED",_denied]] call
            ITW_CLASH_Supports_fnc_Log;
        false
    };
    // v7: who asked can read back what it got.
    _context set ["admitted",_id];

    private _support = createHashMapFromArray [
        ["id",_id],["side",_side],["hq",_context get "hq"],["sign",_context get "sign"],
        ["flavor",_flavor],["routine",_row get "routine"],["lane",_lane],
        ["objective",_pick get "objective"],["reason",_reason],
        ["aim",_pick get "aim"],["target",_pick get "target"],
        ["origin",_pick get "origin"],["spawn",_pick get "spawn"],
        ["corridor",_pick get "corridor"],
        ["class",(_context get "classes") getOrDefault [_flavor,""]],
        ["price",_price],["wallet",_wallet],["state","RESERVED"],["reservedAt",time],
        ["delay",_pick getOrDefault ["delay",ITW_CLASH_SupportsDelayMin + random ((ITW_CLASH_SupportsDelayMax - ITW_CLASH_SupportsDelayMin) max 0)]],
        ["nominal",[_flavor,"nominal",120] call ITW_CLASH_Supports_fnc_RowNumber],
        ["ahead",_pick getOrDefault ["ahead",0]],
        ["squads",_pick getOrDefault ["squads",0]],
        ["squadSize",_pick getOrDefault ["squadSize",0]],
        ["template",_pick getOrDefault ["template",[]]],
        ["need",_pick getOrDefault ["need",0]],
        ["assets",[]],["groups",[]],["delivered",false],["detail",""],
        ["test",_pick getOrDefault ["test",false]],
        ["wave",_pick getOrDefault ["wave",""]],
        ["dryRun",ITW_CLASH_SupportsDryRun && {!(_pick getOrDefault ["test",false])}]
    ];
    (([_side] call ITW_CLASH_Supports_fnc_Ledger) get "supports") set [_id,_support];

    ["admission",[
        _context get "sign",_flavor,_pick get "objective","RESERVED",_id,
        (round (_price * 10)) / 10,round ([[_side] call ITW_CLASH_Supports_fnc_Ledger,_wallet] call ITW_CLASH_Supports_fnc_WalletCash),
        round (_support get "delay"),_pick get "corridor",
        switch (true) do {
            case (_support get "test"): {"test"};
            case (_support get "dryRun"): {"dry-run"};
            default {"live"};
        },
        _wallet,_lane
    ]] call ITW_CLASH_Supports_fnc_Log;

    [_support] spawn ITW_CLASH_Supports_fnc_Run;
    true
};

// ----------------------------------------------------------------- lifecycle

ITW_CLASH_Supports_fnc_SetState = {
    params ["_support","_state",["_detail",""]];
    private _was = _support get "state";
    _support set ["state",_state];
    ["state",[
        _support get "id",_support get "sign",_support get "flavor",_was,_state,_detail
    ]] call ITW_CLASH_Supports_fnc_Log;
};

/*
    Before anything spawns. Nothing exists yet, so a failure here costs
    nothing: the support is revoked and the money comes back.
*/
ITW_CLASH_Supports_fnc_PreRun = {
    params ["_support"];
    private _side = _support get "side";
    private _objective = _support get "objective";
    private _routine = _support get "routine";
    // v7: a console test flies whatever the map's state; it is a test.
    private _test = _support getOrDefault ["test",false];
    if (!_test && {!isNil "ITW_CLASH_fnc_ObjectiveFrozen"} && {_objective >= 0} && {[_objective] call ITW_CLASH_fnc_ObjectiveFrozen}) exitWith {
        "OBJECTIVE_FROZEN"
    };
    if (_routine isEqualTo "STRIKE") then {
        // A pass that acquires on site goes while the target is believed to
        // exist; the others need a position still good enough to drop on.
        private _acquires = (_support get "flavor") in ITW_CLASH_SupportsAcquireFlavors;
        ([_side,(_support get "target") getOrDefault ["keys",[]],_support get "ahead",_acquires] call
            ITW_CLASH_Supports_fnc_TargetNow) params ["_aim","_r","_alive"];
        if (_alive == 0) exitWith {_support set ["denied","TARGET_GONE"]};
        if (!_acquires && {_r > ITW_CLASH_SupportsUncertaintyLimit}) exitWith {
            _support set ["denied","TOO_UNCERTAIN"]
        };
        private _footprint = [_support get "flavor","footprint",50] call ITW_CLASH_Supports_fnc_RowNumber;
        private _friendlies = [_side] call ITW_CLASH_Supports_fnc_Friendlies;
        if ([_friendlies,_aim,_footprint,_support get "flavor"] call ITW_CLASH_Supports_fnc_DangerClose) exitWith {
            ["danger-close",[
                _support get "sign",_support get "flavor",_support get "id","pre-run",
                [_friendlies,_aim,_footprint,_support get "flavor"] call ITW_CLASH_Supports_fnc_DangerWhy
            ]] call ITW_CLASH_Supports_fnc_Log;
            _support set ["denied","DANGER_CLOSE"]
        };
        _support set ["aim",_aim];
        _support set ["uncertainty",_r];
    };
    if (_routine isEqualTo "DROP" && {!_test}) then {
        private _need = _support getOrDefault ["need",0];
        if (_need <= 0) then {_need = (_support get "squads") * (_support get "squadSize")};
        if (([_side] call ITW_CLASH_Supports_fnc_Headroom) < _need) exitWith {
            _support set ["denied","NO_HEADROOM"]
        };
        if !(([_side,_support get "aim"] call ITW_CLASH_Knowledge_fnc_IntelState) in ["RECENT_CONTACT","RECENTLY_CLEARED"]) exitWith {
            _support set ["denied","DZ_UNASSESSED"]
        };
    };
    if ((_support getOrDefault ["denied",""]) isNotEqualTo "") exitWith {_support get "denied"};
    private _rule = ([_support get "flavor"] call ITW_CLASH_Supports_fnc_Row) getOrDefault ["fighterRule","HARD_KILL"];
    private _corridor = [_support get "hq",_support get "spawn",_support get "aim",_rule] call ITW_CLASH_Supports_fnc_Corridor;
    if (!_test && {(_corridor getOrDefault ["state","COLD"]) isEqualTo "AIR_DENIED"}) exitWith {"AIR_DENIED"};
    _support set ["corridor",_corridor getOrDefault ["state","COLD"]];
    ""
};

ITW_CLASH_Supports_fnc_Run = {
    params ["_support"];
    scriptName "ITW_CLASH_Supports_Run";
    [_support,"DELAY",round (_support get "delay")] call ITW_CLASH_Supports_fnc_SetState;
    sleep (_support get "delay");

    private _why = [_support] call ITW_CLASH_Supports_fnc_PreRun;
    if (_why isNotEqualTo "") exitWith {[_support,"REVOKED",_why] call ITW_CLASH_Supports_fnc_Settle};

    // Shadow mode: the lane is held for what the mission would have taken, so
    // the dry run's cadence is the live cadence. Nothing spawns.
    if (_support get "dryRun") exitWith {
        [_support,"INBOUND","dry-run"] call ITW_CLASH_Supports_fnc_SetState;
        sleep (_support get "nominal");
        [_support,"DRY_RUN","shadow-spent"] call ITW_CLASH_Supports_fnc_Settle;
    };

    [_support,"INBOUND"] call ITW_CLASH_Supports_fnc_SetState;
    private _outcome = ["REVOKED","NO_EXECUTOR"];
    switch (_support get "routine") do {
        case "ORBIT": {
            if (!isNil "ITW_CLASH_SupportsUAV_fnc_Run") then {
                _outcome = [_support] call ITW_CLASH_SupportsUAV_fnc_Run;
            };
        };
        case "STRIKE": {
            if (!isNil "ITW_CLASH_SupportsStrike_fnc_Run") then {
                _outcome = [_support] call ITW_CLASH_SupportsStrike_fnc_Run;
            };
        };
        case "DROP": {
            if (!isNil "ITW_CLASH_SupportsAirborne_fnc_Run") then {
                _outcome = [_support] call ITW_CLASH_Supports_fnc_RunDrop;
            };
        };
    };
    if !(_outcome isEqualType [] && {count _outcome >= 1}) then {_outcome = ["LOST","executor-returned-nothing"]};
    [_support,_outcome#0,_outcome param [1,""]] call ITW_CLASH_Supports_fnc_Settle;
};

// Airborne goes through its own executor; kept as a seam so it can be swapped.
// v7: a delivery is its own run.
ITW_CLASH_Supports_fnc_RunDrop = {
    params ["_support"];
    if ((_support get "flavor") in ITW_CLASH_SupportsVehicleFlavors) exitWith {
        if (isNil "ITW_CLASH_SupportsAirborne_fnc_RunVehicle") exitWith {["REVOKED","NO_EXECUTOR"]};
        [_support] call ITW_CLASH_SupportsAirborne_fnc_RunVehicle
    };
    [_support] call ITW_CLASH_SupportsAirborne_fnc_Run
};

/*
    The end of a support. Money is spent only on delivery or loss: anything
    that ends without delivering, with the aircraft alive, is refunded in full,
    up to the wallet's ceiling. The ceiling means one big support banked,
    never two; a refund that would cross it is clipped, and the clipped amount
    is logged. The cooldown stands either way.
*/
ITW_CLASH_Supports_fnc_Settle = {
    params ["_support","_state",["_detail",""]];
    private _side = _support get "side";
    private _refund = _state in ["REVOKED","BREAKOFF"];
    private _price = _support get "price";
    private _id = _support get "id";
    private _lane = _support get "lane";
    private _cash = 0;
    private _clipped = 0;
    // v7: back to the wallet it came from, up to that wallet's cap.
    private _wallet = _support getOrDefault ["wallet","MAIN"];
    private _cashKey = [_wallet] call ITW_CLASH_Supports_fnc_WalletKey;
    isNil {
        private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
        if (_refund && {_wallet isNotEqualTo "TEST"}) then {
            private _before = _ledger getOrDefault [_cashKey,0];
            private _after = (_before + _price) min (([_wallet] call ITW_CLASH_Supports_fnc_WalletCap) max _before);
            _clipped = (_before + _price) - _after;
            _ledger set [_cashKey,_after];
        };
        private _lanes = _ledger get "lanes";
        if ((_lanes getOrDefault [_lane,""]) isEqualTo _id) then {_lanes set [_lane,""]};
        if (_lane isEqualTo "RECON" && {_state isEqualTo "LOST"}) then {
            _ledger set ["reconBlockedUntil",time + ITW_CLASH_SupportsUAVRelaunch];
        };
        (_ledger get "supports") deleteAt _id;
        _cash = [_ledger,_wallet] call ITW_CLASH_Supports_fnc_WalletCash;
    };
    [_support,_state,_detail] call ITW_CLASH_Supports_fnc_SetState;
    ["outcome",[
        _id,_support get "sign",_support get "flavor",_support get "objective",
        _support get "reason",_state,_detail,
        if (_refund) then {"refunded"} else {"spent"},
        (round (_price * 10)) / 10,round _cash,
        round (time - (_support get "reservedAt")),
        round _clipped,
        _wallet,_support getOrDefault ["wave",""]
    ]] call ITW_CLASH_Supports_fnc_Log;
    true
};

// -------------------------------------------------------- shared flight code

/*
    One support aircraft, in flight, owned by the support from this moment.
    Crewed aircraft come from Impasse's own factory, so the crew is the
    faction's; the UAV brings its own AI crew, joined to a group of the side.
*/
ITW_CLASH_Supports_fnc_SpawnAircraft = {
    params ["_support","_class","_position","_direction","_speed"];
    private _side = _support get "side";
    private _id = _support get "id";
    private _veh = objNull;
    private _group = grpNull;

    if (getNumber (configFile >> "CfgVehicles" >> _class >> "isUav") == 1) then {
        _veh = createVehicle [_class,_position,[],0,"FLY"];
        if (!isNull _veh) then {
            createVehicleCrew _veh;
            private _native = group (driver _veh);
            _group = createGroup [_side,true];
            (crew _veh) joinSilent _group;
            if (!isNull _native && {(units _native) isEqualTo []}) then {deleteGroup _native};
            if ((crew _veh) isEqualTo []) then {deleteVehicle _veh; _veh = objNull};
        };
    } else {
        if (!isNil "ITW_AtkSpawnVeh" && {!isNil "ITW_CLASH_Checkbook_fnc_GetCrewTypes"}) then {
            ([_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes) params [["_crewTypes",[]],["_unitTypes",[]]];
            _veh = [[_class],_crewTypes,_unitTypes,_side,_position,-1] call ITW_AtkSpawnVeh;
            if (!isNull _veh) then {_group = group (driver _veh)};
        };
    };
    if (isNull _veh || {isNull _group}) exitWith {[objNull,grpNull]};

    _veh setDir _direction;
    _veh setPosATL _position;
    _veh setVelocityModelSpace [0,_speed,0];
    [_veh,true] remoteExec ["allowDamage",_veh];

    _veh setVariable ["ITW_CLASH_SupportAsset",_id,true];
    _group setVariable ["ITW_CLASH_SupportAsset",_id];
    // What the lifecycle reservation and FormationAdmission already honour:
    // nobody adopts, admits or re-tasks this crew.
    _group setVariable ["ITW_CLASH_ExcludeHAL",true];
    _group setVariable ["ITW_CLASH_VehicleCrewGroup",true];
    {
        _x setVariable ["ITW_CLASH_SupportAsset",_id,true];
        _x disableAI "TARGET";
        _x disableAI "AUTOTARGET";
        _x disableAI "AUTOCOMBAT";
    } forEach (units _group);
    _group setBehaviourStrong "CARELESS";
    _group setCombatMode "BLUE";
    _group allowFleeing 0;
    _group deleteGroupWhenEmpty true;
    [_group] call ITW_CLASH_Knowledge_fnc_RegisterSensorGroup;

    (_support get "assets") pushBack _veh;
    (_support get "groups") pushBack _group;
    ["aircraft-spawned",[
        _id,_support get "sign",_class,_position apply {round _x},round _direction,
        count (units _group)
    ]] call ITW_CLASH_Supports_fnc_Log;
    [_veh,_group]
};

/*
    No support jet carries air-to-air missiles: it must never read as a fighter
    to the other side's corridor check, and never engage aircraft.
*/
ITW_CLASH_Supports_fnc_StripAirToAir = {
    params ["_veh"];
    if (isNull _veh || {isNil "ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo"}) exitWith {0};
    private _isAirMissile = {
        params ["_magazine"];
        private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
        _ammo isNotEqualTo ""
        && {[_ammo] call ITW_CLASH_AirPicture_fnc_IsAntiAirAmmo}
        && {(toLowerANSI getText (configFile >> "CfgAmmo" >> _ammo >> "simulation")) isEqualTo "shotmissile"}
    };
    private _removed = 0;
    {
        if (_x isNotEqualTo "" && {[_x] call _isAirMissile}) then {
            _veh setPylonLoadout [_forEachIndex + 1,"",true];
            _removed = _removed + 1;
        };
    } forEach (getPylonMagazines _veh);
    {
        _x params ["_magazine","_turret"];
        if ([_magazine] call _isAirMissile) then {
            _veh removeMagazinesTurret [_magazine,_turret];
            _removed = _removed + 1;
        };
    } forEach (magazinesAllTurrets _veh);
    _removed
};

// Countermeasures on a clock, through Thunder Run's own primitives.
ITW_CLASH_Supports_fnc_Flares = {
    params ["_veh","_seconds","_cadence"];
    if (
        isNull _veh
        || {isNil "ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter"}
        || {isNil "ITW_CLASH_ThunderRun_fnc_FireCountermeasure"}
    ) exitWith {false};
    private _emitter = [_veh] call ITW_CLASH_ThunderRun_fnc_FindCountermeasureEmitter;
    if (_emitter isEqualTo []) exitWith {false};
    [_veh,_emitter,_seconds,_cadence] spawn {
        params ["_veh","_emitter","_seconds","_cadence"];
        private _state = createHashMapFromArray [["vehicle",_veh],["countermeasureEmitter",_emitter]];
        private _until = time + _seconds;
        while {time < _until && {alive _veh}} do {
            [_state] call ITW_CLASH_ThunderRun_fnc_FireCountermeasure;
            sleep _cadence;
        };
    };
    true
};

ITW_CLASH_Supports_fnc_Despawn = {
    params ["_veh","_group"];
    if (!isNull _veh) then {
        {deleteVehicle _x} forEach (crew _veh);
        deleteVehicle _veh;
    };
    if (!isNull _group) then {
        {deleteVehicle _x} forEach (units _group);
        deleteGroup _group;
    };
    true
};

// Distance still to fly along a line to a point (positive short of it), and
// how far off that line the aircraft is.
ITW_CLASH_Supports_fnc_AlongCross = {
    params ["_position","_point","_heading"];
    private _range = _position distance2D _point;
    private _angle = (_position getDir _point) - _heading;
    [_range * cos _angle,abs (_range * sin _angle)]
};

/*
    Out and gone.

    Without a support record (the UAV): a far waypoint on the given heading.
    With one (strike and drop): fly on past the task for a short separation,
    turn toward home on whichever side the corridor classifier rates colder
    from the turn point, and go home. Never an about-face over the target.
    Despawned once clear of the task, or at the timeout. An aircraft shot down
    on the way out is left where it falls.
*/
ITW_CLASH_Supports_fnc_Egress = {
    params ["_veh","_group","_from","_heading",["_clear",4000],["_timeout",300],["_support",createHashMap]];
    if (isNull _veh || {!alive _veh}) exitWith {false};
    private _waypoint = {
        params ["_group","_position"];
        private _wp = _group addWaypoint [_position,0];
        _wp setWaypointType "MOVE";
        _wp setWaypointSpeed "FULL";
        _wp setWaypointBehaviour "CARELESS";
        _wp setWaypointCombatMode "BLUE";
        _wp setWaypointCompletionRadius 300;
        _wp
    };
    {deleteWaypoint _x} forEachReversed (waypoints _group);
    private _home = _support getOrDefault ["origin",[]];
    if (_home isEqualTo []) then {
        [_group,_from getPos [_clear + 4000,_heading]] call _waypoint;
    } else {
        private _separation = _from getPos [ITW_CLASH_SupportsEgressSeparation,_heading];
        private _rule = ([_support getOrDefault ["flavor",""]] call ITW_CLASH_Supports_fnc_Row)
            getOrDefault ["fighterRule","HARD_KILL"];
        private _rank = ["COLD","UNKNOWN","CONTESTED","HOT","AIR_DENIED"];
        private _turns = [120,-120] apply {
            private _turn = _separation getPos [ITW_CLASH_SupportsEgressTurn,_heading + _x];
            private _state = ([_support getOrDefault ["hq",grpNull],_turn,_home,_rule] call
                ITW_CLASH_Supports_fnc_Corridor) getOrDefault ["state","COLD"];
            private _score = _rank find _state;
            if (_score < 0) then {_score = 1};
            [_score,_turn,_state]
        };
        // The colder side; the two are mirror images, so a tie is a coin toss.
        private _pick = switch (true) do {
            case (((_turns#0)#0) < ((_turns#1)#0)): {_turns#0};
            case (((_turns#1)#0) < ((_turns#0)#0)): {_turns#1};
            default {selectRandom _turns};
        };
        _pick params ["","_turn","_state"];
        [_group,_separation] call _waypoint;
        [_group,_turn] call _waypoint;
        [_group,_turn getPos [8000,_turn getDir _home]] call _waypoint;
        ["egress",[
            _support getOrDefault ["id",""],_support getOrDefault ["sign",""],
            _state,round _heading
        ]] call ITW_CLASH_Supports_fnc_Log;
    };
    private _deadline = time + _timeout;
    waitUntil {
        sleep 2;
        !alive _veh || {(_veh distance2D _from) > _clear} || {time > _deadline}
    };
    if (!alive _veh) exitWith {false};
    [_veh,_group] call ITW_CLASH_Supports_fnc_Despawn;
    true
};

ITW_CLASH_Supports_fnc_LedgerLog = {
    {
        private _side = _x;
        [_side] call ITW_CLASH_Supports_fnc_Accrue;
        private _ledger = [_side] call ITW_CLASH_Supports_fnc_Ledger;
        private _lanes = _ledger get "lanes";
        ["ledger",[
            [_side] call ITW_CLASH_Supports_fnc_CodeSign,
            round (_ledger get "cash"),
            round (call ITW_CLASH_Supports_fnc_Cap),
            (round ((call ITW_CLASH_Supports_fnc_IncomeRate) * 100)) / 100,
            _lanes getOrDefault ["RECON",""],
            _lanes getOrDefault ["COMMIT",""],
            round (((_ledger get "reconBlockedUntil") - time) max 0),
            // v7: the drop wallet and its lanes, then the bite-back pot (waves).
            round (_ledger getOrDefault ["dropCash",0]),
            round (call ITW_CLASH_Supports_fnc_DropCap),
            _lanes getOrDefault ["DROP",""],
            _lanes getOrDefault ["VEHICLE",""],
            (round ((_ledger getOrDefault ["biteCash",0]) * 100)) / 100,
            _lanes getOrDefault ["BITE_DROP",""],
            _lanes getOrDefault ["BITE_VEHICLE",""]
        ]] call ITW_CLASH_Supports_fnc_Log;
    } forEach _this;
};

// UAV, drop and executor-side tunables the core reads.
ITW_CLASH_SupportsUAVRelaunch = missionNamespace getVariable ["ITW_CLASH_SupportsUAVRelaunch",300];
ITW_CLASH_SupportsAirborneHeliSquads = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneHeliSquads",2];
ITW_CLASH_SupportsAirbornePlaneSquads = missionNamespace getVariable ["ITW_CLASH_SupportsAirbornePlaneSquads",3];
// The executor's own floor for a squad (ITW_CLASH_SupportsAirborneMinSquad), read by a direct pick.
ITW_CLASH_SupportsAirborneMinSquadCore = missionNamespace getVariable ["ITW_CLASH_SupportsAirborneMinSquad",4];

[] spawn {
    scriptName "ITW_CLASH_SupportsLedger";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide"
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_SupportsLedgerInterval;
        if (ITW_CLASH_SupportsEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            _sides call ITW_CLASH_Supports_fnc_LedgerLog;
        };
    };
};

ITW_CLASH_SupportsReady = true;
diag_log format [
    "CLASH BOOT | supports-ready | version=%1 enabled=%2 dryRun=%3 uav=%4 bomb=%5 guided=%6 carpet=%7 airborneHeli=%8 airbornePlane=%9 vehicleDrop=%10 income=%11/min cap=%12 floor=%13 acquireFloor=%22 carpetMinContacts=%23 acquireOnSite=%24 cadence=%25/%26/%27min saveScale=%28 bombSpawn=%29m uavKillbox=%30s/%31m/%32s uncertaintyLimit=%14 danger=%15/%16 dangerGuided=%33/%34 dangerLogged=true dropWallet=%35/min dropCap=%36 dropCadence=%37/%38/%39min carrier=%40 carrierFirst=preferred planeTroop=%46 deliveryTiers=car,apc,tank canBeTransported=true biteBack=%41 biteBackPot=%42wave/%43min biteBackCooldown=%44s biteBackSquads=%45 lanes=RECON,COMMIT,DROP,VEHICLE,BITE_DROP,BITE_VEHICLE picks=strike,drop,vehicle delay=%17-%18 influence=%19m edge=%20 threatProximity=%21m colossusProposesOnly=true refundUnlessDeliveredOrLost=true refundCappedAtCeiling=true fullRunIn=true uavFixedWingFirst=true",
    ITW_CLASH_SupportsVersion,
    ITW_CLASH_SupportsEnabled,
    ITW_CLASH_SupportsDryRun,
    ITW_CLASH_SupportsUAVEnabled,
    ITW_CLASH_SupportsBombEnabled,
    ITW_CLASH_SupportsGuidedEnabled,
    ITW_CLASH_SupportsCarpetEnabled,
    ITW_CLASH_SupportsAirborneHeliEnabled,
    ITW_CLASH_SupportsAirbornePlaneEnabled,
    ITW_CLASH_SupportsVehicleDropEnabled,
    (round ((call ITW_CLASH_Supports_fnc_IncomeRate) * 100)) / 100,
    round (call ITW_CLASH_Supports_fnc_Cap),
    ITW_CLASH_SupportsValueFloor,
    ITW_CLASH_SupportsUncertaintyLimit,
    ITW_CLASH_SupportsDangerMargin,
    ITW_CLASH_SupportsDangerMarginPlayer,
    ITW_CLASH_SupportsDelayMin,
    ITW_CLASH_SupportsDelayMax,
    ITW_CLASH_SupportsInfluenceRadius,
    ITW_CLASH_SupportsInfluenceEdge,
    ITW_CLASH_SupportsThreatProximity,
    ITW_CLASH_SupportsValueFloorAcquire,
    ITW_CLASH_SupportsCarpetMinContacts,
    ITW_CLASH_SupportsAcquireFlavors joinString "/",
    ITW_CLASH_SupportsBombCadence,
    ITW_CLASH_SupportsGuidedCadence,
    ITW_CLASH_SupportsCarpetCadence,
    ITW_CLASH_SupportsSaveScale,
    ITW_CLASH_SupportsSpawnDistanceBomb,
    ITW_CLASH_SupportsUAVKillboxSeconds,
    ITW_CLASH_SupportsUAVKillboxRadius,
    ITW_CLASH_SupportsUAVKillboxDuration,
    ITW_CLASH_SupportsDangerMarginGuided,
    ITW_CLASH_SupportsDangerMarginGuidedPlayer,
    (round ((call ITW_CLASH_Supports_fnc_DropIncomeRate) * 100)) / 100,
    round (call ITW_CLASH_Supports_fnc_DropCap),
    ITW_CLASH_SupportsAirborneHeliCadence,
    ITW_CLASH_SupportsAirbornePlaneCadence,
    ITW_CLASH_SupportsVehicleDropCadence,
    ITW_CLASH_SupportsVehicleCarrierClasses joinString "/",
    ITW_CLASH_SupportsBiteBackEnabled,
    ITW_CLASH_SupportsBiteBackCap,
    ITW_CLASH_SupportsBiteBackRefill,
    ITW_CLASH_SupportsBiteBackCooldown,
    ITW_CLASH_SupportsBiteBackSquads,
    ITW_CLASH_SupportsPlaneTroopClasses joinString "/"
];
true
