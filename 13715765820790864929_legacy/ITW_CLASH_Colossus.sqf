#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ColossusStarted",false]) exitWith {true};

ITW_CLASH_ColossusStarted = true;
ITW_CLASH_ColossusVersion = 4;
ITW_CLASH_ColossusReady = false;

/*
    COLOSSUS - the strategy layer. Version 0: it states intent and does nothing.

    Every other layer of this stack has an owner. Impasse sets the map and the
    baseline army; the Checkbook and the ETB buy on demand; HAL fights; the
    sustainment layer keeps the army alive. Strategy has had no owner at all -
    HAL's own Big Boss is off and does not fit Impasse's zone model - so the war
    is a slugfest: every HAL cycle, whatever groups happen to be free get sent,
    they arrive one at a time and they die one at a time.

    This is the first half of fixing that, and deliberately the harmless half.
    It builds the thing that does not exist yet: a GROUND PICTURE. For each
    contested objective, what the commander knows of the enemy there against
    what it has itself. That is what turns "point B looks weak" into a number,
    and nothing can plan without it.

    What it does NOT do, in v0 and by design: give an order. It never writes a
    HAL pool, never moves a group, never buys anything. It logs the push it
    WOULD commit and leaves the war alone. A strategic layer stacked on top of
    an execution layer that still drops orders would make every plan look bad,
    so the picture ships first and gets read against a real run before anything
    acts on it.

    The kill criterion, stated up front: if COLOSSUS ever issues an order to a
    group or duplicates HAL's dispatcher, it has failed and should be deleted.
    It says what the commander wants. Other layers decide what to do about it.

    ---------------------------------------------------------------------------
    For v1 (hold, stage, release), the levers are verified and recorded here so
    the next session does not have to re-derive them:

      HOLD   RydHQ_Garrison is the lever, NOT RydHQ_NoAttack. The capture pool
             at HQOrders.sqf:778 subtracts Garrison, Exhausted, SupportG,
             NavalG, SpecForG, AmmoDrop, CargoOnly, AOnly and ROnly - but it
             does not subtract NoAttack. Only the wide-attack pool at
             HQOrders.sqf:1038 subtracts both. A group held with NoAttack alone
             would still be pulled into a capture.
      STAGE  Garrison is also what makes HAL dig a group in where it already
             stands (HAL/Garrison.sqf:41), so moving a group to the forward FOB
             and then adding it to Garrison stages it there. That is the same
             mechanism ITW_CLASH_FOBAirDefence.sqf already uses successfully.
      RELEASE Remove from Garrison and clear both "Garrisoned<group>" and
             "NOGarrisoned<group>", then set RydHQ_Obj to the target in the same
             cycle. HAL's own tactics take it from there.
    ---------------------------------------------------------------------------
*/

ITW_CLASH_ColossusEnabled = missionNamespace getVariable ["ITW_CLASH_ColossusEnabled",true];
// v0 is advisory. This exists so v1 can be gated separately and so a run can
// prove the picture before anything acts on it.
// Now false: COLOSSUS issues the ATTACK/DEFEND order. Set it true to put the
// layer back to observation only - that reverts the whole change in one
// variable, and the parity layer's own ternary resumes ownership of the order.
ITW_CLASH_ColossusAdvisoryOnly = missionNamespace getVariable ["ITW_CLASH_ColossusAdvisoryOnly",false];
ITW_CLASH_ColossusPoll = missionNamespace getVariable ["ITW_CLASH_ColossusPoll",60];
// How near an objective a unit has to be to count as contesting it.
ITW_CLASH_ColossusObjectiveRadius = missionNamespace getVariable ["ITW_CLASH_ColossusObjectiveRadius",500];
// Our own groups within this of an objective are already committed there.
ITW_CLASH_ColossusCommittedRadius = missionNamespace getVariable ["ITW_CLASH_ColossusCommittedRadius",900];
/*
    Strength weights. A rifle squad is the unit of account; everything else is
    priced against it. Armour counts for three because an unanswered tank
    decides an objective on its own, and a static counts for less than a squad
    because it cannot follow up.
*/
ITW_CLASH_ColossusWeightInfantry = missionNamespace getVariable ["ITW_CLASH_ColossusWeightInfantry",1];
ITW_CLASH_ColossusWeightArmor = missionNamespace getVariable ["ITW_CLASH_ColossusWeightArmor",3];
ITW_CLASH_ColossusWeightVehicle = missionNamespace getVariable ["ITW_CLASH_ColossusWeightVehicle",1.5];
ITW_CLASH_ColossusWeightStatic = missionNamespace getVariable ["ITW_CLASH_ColossusWeightStatic",0.5];
// The force ratio a push is planned around. Attacking a prepared position at
// parity is how an army is fed into a meat grinder one group at a time.
ITW_CLASH_ColossusPushRatio = missionNamespace getVariable ["ITW_CLASH_ColossusPushRatio",2];
/*
    Consolidation.

    A commander that is drastically outnumbered across the theatre should not
    be feeding objectives one group at a time - that is the slugfest COLOSSUS
    exists to name. When the enemy it knows about outweighs everything it could
    send by this much, the posture becomes CONSOLIDATE: mass first, push after.

    Two thresholds, not one, so the posture does not flap between assessments
    while the ratio sits on the line. It enters consolidation at the higher
    figure and only leaves below the lower one.

    Measured across the whole theatre rather than per objective, because the
    per-objective numbers already drive the push ranking. This is the question
    the ranking cannot answer: whether to be pushing at all.
*/
ITW_CLASH_ColossusConsolidateAt = missionNamespace getVariable [
    "ITW_CLASH_ColossusConsolidateAt",1.5
];
ITW_CLASH_ColossusReleaseAt = missionNamespace getVariable [
    "ITW_CLASH_ColossusReleaseAt",1.1
];
// Verdict thresholds, as our strength over theirs.
ITW_CLASH_ColossusVulnerable = missionNamespace getVariable ["ITW_CLASH_ColossusVulnerable",2];
ITW_CLASH_ColossusContested = missionNamespace getVariable ["ITW_CLASH_ColossusContested",0.8];

/*
    How long an order holds before COLOSSUS may change it again.

    The posture already has hysteresis, but feasibility does not: a commander
    one group short of sufficient would flip ATTACK/DEFEND on alternate
    assessments. An army that changes its mind every minute reads worse than
    one that is simply wrong, so the order sits for at least this long.
*/
ITW_CLASH_ColossusOrderDwell = missionNamespace getVariable [
    "ITW_CLASH_ColossusOrderDwell",120
];

/*
    Concentration: making the chosen objective the appetising one.

    HAL does not score objectives, so there is no weight to bias. In
    SimpleMode - which C.L.A.S.H. sets - HQOrders.sqf:328 takes the candidate
    list, sorts it by DISTANCE from the commander, and truncates it:

        _toRecon = _objectives - _taken;
        _toRecon = [_toRecon,(leader _HQ),250000] call RYD_DistOrdD;
        if (MaxSimpleObjs < count _toRecon) then {_toRecon resize MaxSimpleObjs};

    So "I want this attacked" has exactly two honest expressions: be in the
    candidate set, and have no rivals in it. Reordering the list does nothing
    because RYD_DistOrdD re-sorts it.

    This is deliberately NOT a second writer. The candidate globals have one
    owner each already - ITW_CLASH_fnc_MirrorObjectives for commander A and the
    dual-HAL mirror pass for commander B - and those owners consult the
    function below before they write. COLOSSUS stays a pure opinion: no
    waypoint, no claim, no global of its own, and no state machine racing HAL
    for the same units.
*/
ITW_CLASH_ColossusConcentrate = missionNamespace getVariable [
    "ITW_CLASH_ColossusConcentrate",true
];
ITW_CLASH_ColossusConcentrateMax = missionNamespace getVariable [
    "ITW_CLASH_ColossusConcentrateMax",1
];
// Do not concentrate on a new objective while ground already held has no
// anchor. Concentration cannot strip HAL's defence, but it can starve the
// anchor refill of the groups it needs.
ITW_CLASH_ColossusRequireAnchored = missionNamespace getVariable [
    "ITW_CLASH_ColossusRequireAnchored",true
];

ITW_CLASH_ColossusPictures = createHashMap;
// side key -> the last plan, so the mirror writers can ask what this
// commander wants without recomputing the picture on their own clock.
ITW_CLASH_ColossusPlans = createHashMap;

ITW_CLASH_Colossus_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["colossus-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH COLOSSUS | %1 | %2",_event,_payload];
    };
    if (!isNil "ITW_CLASH_LoudDebug_fnc_Emit") then {
        ["colossus",_event,_payload] call ITW_CLASH_LoudDebug_fnc_Emit;
    };
};

/*
    What one unit is worth. Read from the vehicle, like every other
    classification in C.L.A.S.H., so a modded faction prices correctly: armour
    that can kill armour is the expensive thing, a static is cheap because it
    cannot exploit, and a man is the unit of account.
*/
ITW_CLASH_Colossus_fnc_Worth = {
    params ["_unit"];
    if (isNull _unit || {!alive _unit}) exitWith {0};
    private _veh = vehicle _unit;
    if (_veh isEqualTo _unit) exitWith {ITW_CLASH_ColossusWeightInfantry};
    if (_veh isKindOf "StaticWeapon") exitWith {ITW_CLASH_ColossusWeightStatic};
    if (_veh isKindOf "Air") exitWith {0};
    if (!isNil "ITW_CLASH_AirPicture_fnc_IsArmoredThreat" && {
        [_veh] call ITW_CLASH_AirPicture_fnc_IsArmoredThreat
    }) exitWith {ITW_CLASH_ColossusWeightArmor};
    ITW_CLASH_ColossusWeightVehicle
};

// Enemy strength at an objective, counted from what this commander KNOWS.
// Nothing here looks at the enemy's real order of battle.
ITW_CLASH_Colossus_fnc_EnemyStrength = {
    params ["_hq","_position"];
    private _score = 0;
    private _counted = [];
    {
        private _unit = _x;
        if (isNull _unit || {!alive _unit}) then {continue};
        private _veh = vehicle _unit;
        if (_veh in _counted) then {continue};
        if ((getPosATL _veh) distance2D _position > ITW_CLASH_ColossusObjectiveRadius) then {continue};
        _counted pushBack _veh;
        _score = _score + ([_unit] call ITW_CLASH_Colossus_fnc_Worth);
    } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
    [_score,count _counted]
};

// Our own strength already at an objective, and what is free to be sent.
ITW_CLASH_Colossus_fnc_FriendlyStrength = {
    params ["_hq","_position"];
    private _committed = 0;
    private _available = 0;
    private _availableGroups = 0;
    private _attackAv = _hq getVariable ["RydHQ_AttackAv",[]];
    // Everything the commander would not send anyway is out of the reckoning.
    private _excluded = (_hq getVariable ["RydHQ_Exhausted",[]])
        + (_hq getVariable ["RydHQ_SupportG",[]])
        + (_hq getVariable ["RydHQ_SpecForG",[]])
        + (_hq getVariable ["RydHQ_ArtG",[]])
        + (_hq getVariable ["RydHQ_NavalG",[]])
        + (_hq getVariable ["RydHQ_CargoOnly",[]])
        + (_hq getVariable ["RydHQ_StaticG",[]]);

    {
        private _group = _x;
        if (isNull _group || {_group in _excluded}) then {continue};
        private _leader = leader _group;
        if (isNull _leader || {!alive _leader}) then {continue};
        private _worth = 0;
        {
            _worth = _worth + ([_x] call ITW_CLASH_Colossus_fnc_Worth);
        } forEach ((units _group) select {alive _x});
        if (_worth <= 0) then {continue};

        if ((getPosATL (vehicle _leader)) distance2D _position <= ITW_CLASH_ColossusCommittedRadius) then {
            _committed = _committed + _worth;
        } else {
            if (_group in _attackAv && {!(_group getVariable ["Busy" + str _group,false])}) then {
                _available = _available + _worth;
                _availableGroups = _availableGroups + 1;
            };
        };
    } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    [_committed,_available,_availableGroups]
};

ITW_CLASH_Colossus_fnc_Verdict = {
    params ["_friendly","_enemy"];
    if (_enemy <= 0) exitWith {if (_friendly > 0) then {"OPEN"} else {"EMPTY"}};
    private _ratio = _friendly / _enemy;
    if (_ratio >= ITW_CLASH_ColossusVulnerable) exitWith {"VULNERABLE"};
    if (_ratio >= ITW_CLASH_ColossusContested) exitWith {"CONTESTED"};
    "HELD"
};

/*
    The picture for one commander: every contested objective, what is known to
    be there, what we have there, what is free to send, and what a push would
    cost at the planned force ratio.
*/
ITW_CLASH_Colossus_fnc_Picture = {
    params ["_hq"];
    if (isNull _hq || {isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds"}) exitWith {[]};
    private _picture = [];
    {
        private _index = _x;
        if (_index < 0 || {isNil "ITW_Objectives"} || {_index >= count ITW_Objectives}) then {continue};
        private _position = +(ITW_Objectives#_index#ITW_OBJ_POS);
        if (_position isEqualTo []) then {continue};

        ([_hq,_position] call ITW_CLASH_Colossus_fnc_EnemyStrength) params ["_enemy","_enemyCount"];
        ([_hq,_position] call ITW_CLASH_Colossus_fnc_FriendlyStrength) params [
            "_committed","_available","_availableGroups"
        ];
        private _verdict = [_committed,_enemy] call ITW_CLASH_Colossus_fnc_Verdict;
        // What taking it would want, over and above what is already there.
        private _wanted = ((_enemy * ITW_CLASH_ColossusPushRatio) - _committed) max 0;

        _picture pushBack createHashMapFromArray [
            ["objective",_index],
            ["position",_position],
            ["enemy",_enemy],
            ["enemyCount",_enemyCount],
            ["committed",_committed],
            ["available",_available],
            ["availableGroups",_availableGroups],
            ["verdict",_verdict],
            ["wanted",_wanted],
            ["sufficient",_available >= _wanted],
            ["at",time]
        ];
    } forEach (call ITW_CLASH_Generation_fnc_ActiveObjectiveIds);
    _picture
};

// The public read, for anything that later wants to plan against it.
ITW_CLASH_Colossus_fnc_Read = {
    params ["_side"];
    ITW_CLASH_ColossusPictures getOrDefault [toUpperANSI str _side,[]]
};

/*
    The theatre, not an objective: everything this commander knows about against
    everything it could field. Counted once per vehicle and once per group, so
    neither side is double counted the way summing the per-objective numbers
    would, since a unit within range of two objectives appears in both.
*/
ITW_CLASH_Colossus_fnc_Theatre = {
    params ["_hq"];
    private _enemy = 0;
    private _counted = [];
    {
        private _unit = _x;
        if (isNull _unit || {!alive _unit}) then {continue};
        private _veh = vehicle _unit;
        if (_veh in _counted) then {continue};
        _counted pushBack _veh;
        _enemy = _enemy + ([_unit] call ITW_CLASH_Colossus_fnc_Worth);
    } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);

    private _excluded = (_hq getVariable ["RydHQ_Exhausted",[]])
        + (_hq getVariable ["RydHQ_SupportG",[]])
        + (_hq getVariable ["RydHQ_SpecForG",[]])
        + (_hq getVariable ["RydHQ_ArtG",[]])
        + (_hq getVariable ["RydHQ_NavalG",[]])
        + (_hq getVariable ["RydHQ_CargoOnly",[]])
        + (_hq getVariable ["RydHQ_StaticG",[]]);
    private _friendly = 0;
    {
        private _group = _x;
        if (isNull _group || {_group in _excluded}) then {continue};
        {
            _friendly = _friendly + ([_x] call ITW_CLASH_Colossus_fnc_Worth);
        } forEach ((units _group) select {alive _x});
    } forEach (_hq getVariable ["RydHQ_Friends",[]]);

    [_enemy,_friendly,count _counted]
};

/*
    Mass first, or push now.

    Hysteresis is the whole point of holding the previous posture: without it a
    commander sitting on the threshold would consolidate and release on
    alternate assessments and never do either.
*/
ITW_CLASH_Colossus_fnc_Posture = {
    params ["_hq","_enemy","_friendly"];
    private _was = _hq getVariable ["ITW_CLASH_ColossusPosture","PUSH"];
    // Nothing known, or nothing left to send: no case for consolidating.
    if (_enemy <= 0 || {_friendly <= 0}) exitWith {["PUSH",0]};
    private _ratio = _enemy / _friendly;
    private _posture = if (_was isEqualTo "CONSOLIDATE") then {
        if (_ratio < ITW_CLASH_ColossusReleaseAt) then {"PUSH"} else {"CONSOLIDATE"}
    } else {
        if (_ratio >= ITW_CLASH_ColossusConsolidateAt) then {"CONSOLIDATE"} else {"PUSH"}
    };
    [_posture,_ratio]
};

/*
    Where to mass. The objective the commander already holds most strongly, so
    consolidating means thickening a position rather than abandoning everything
    and starting again somewhere new.
*/
ITW_CLASH_Colossus_fnc_RallyPoint = {
    params ["_picture"];
    if (_picture isEqualTo []) exitWith {createHashMap};
    private _ranked = [_picture,[],{-(_x get "committed")},"ASCEND"] call BIS_fnc_sortBy;
    _ranked#0
};

/*
    The recommendation. In v0 this is the whole output: the objective worth
    pushing, what it would take, and whether the force exists to do it. It is
    logged and published, and nothing reads it yet.
*/
ITW_CLASH_Colossus_fnc_Recommend = {
    params ["_hq","_picture",["_posture","PUSH"],["_ratio",0]];
    if (_picture isEqualTo []) exitWith {createHashMap};

    // Outnumbered across the theatre: thicken what we already hold instead of
    // naming the next objective to feed groups into one at a time.
    if (_posture isEqualTo "CONSOLIDATE") exitWith {
        private _rally = [_picture] call ITW_CLASH_Colossus_fnc_RallyPoint;
        private _plan = createHashMapFromArray [
            ["posture","CONSOLIDATE"],
            ["objective",_rally get "objective"],
            ["verdict",_rally get "verdict"],
            ["enemy",_rally get "enemy"],
            ["committed",_rally get "committed"],
            ["available",_rally get "available"],
            ["ratio",_ratio],
            ["feasible",false],
            ["at",time]
        ];
        ["would-consolidate",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            _rally get "objective",
            _rally get "verdict",
            round ((_ratio * 100) / 100),
            round (_rally get "committed"),
            round (_rally get "available"),
            _rally get "availableGroups"
        ]] call ITW_CLASH_Colossus_fnc_Log;
        _plan
    };

    // The softest objective we could actually mass against, not the nearest.
    private _ranked = [_picture,[],{
        private _entry = _x;
        private _score = _entry get "enemy";
        if !(_entry get "sufficient") then {_score = _score + 1000};
        _score
    },"ASCEND"] call BIS_fnc_sortBy;
    private _best = _ranked#0;

    private _plan = createHashMapFromArray [
        ["posture","PUSH"],
        ["objective",_best get "objective"],
        ["verdict",_best get "verdict"],
        ["enemy",_best get "enemy"],
        ["committed",_best get "committed"],
        ["wanted",_best get "wanted"],
        ["available",_best get "available"],
        ["feasible",_best get "sufficient"],
        ["at",time]
    ];

    ["would-push",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        _best get "objective",
        _best get "verdict",
        round (_best get "enemy"),
        round (_best get "committed"),
        round (_best get "wanted"),
        round (_best get "available"),
        _best get "availableGroups",
        if (_best get "sufficient") then {"force-available"} else {"short"}
    ]] call ITW_CLASH_Colossus_fnc_Log;
    _plan
};

/*
    The global HAL actually reads for this commander's order.

    RydHQ_Order is not a decision HAL makes - HQSitRep copies it from a
    mission-level global every cycle, so writing only the group variable is
    undone on the next pass whenever that global is set. Commander A reads the
    unlettered name, every other commander reads its own CodeSign suffix
    (RydHQInit.sqf:235 onward assigns the signs; HQSitRep.sqf:493 and its
    lettered siblings read the globals).
*/
ITW_CLASH_Colossus_fnc_OrderGlobal = {
    params ["_hq"];
    private _sign = toUpperANSI (_hq getVariable ["RydHQ_CodeSign","A"]);
    if (_sign isEqualTo "A") exitWith {"RydHQ_Order"};
    "RydHQ" + _sign + "_Order"
};

/*
    ATTACK or DEFEND, from the picture rather than from a count of flags.

    What this replaces, in ITW_CLASH_CommanderParity.sqf, was:

        if ((count _held) < (count _active)) then {"ATTACK"} else {"DEFEND"}

    which never looked at the enemy at all. Holding every active objective is
    not a reason to stop fighting, and in run4 it meant one side defended for
    88 consecutive assessments while COLOSSUS was reporting an objective
    VULNERABLE with the force available to take it.

    Three cases, and the third is the one that matters:
      - CONSOLIDATE: outnumbered across the theatre, so mass rather than push.
      - PUSH with the force for the objective: attack.
      - PUSH but short: DEFEND. Attacking while short is what feeds groups in
        one at a time, which is the trickle this is meant to stop, not cause.
*/
ITW_CLASH_Colossus_fnc_OrderFor = {
    params ["_posture","_plan"];
    if (count _plan == 0) exitWith {""};
    if (_posture isEqualTo "CONSOLIDATE") exitWith {"DEFEND"};
    if (_plan getOrDefault ["feasible",false]) exitWith {"ATTACK"};
    "DEFEND"
};

/*
    Write the order, or explain why not. Advisory mode is the kill switch: with
    ITW_CLASH_ColossusAdvisoryOnly true this logs what it would have done and
    changes nothing, which is how v0 through v2 shipped.
*/
ITW_CLASH_Colossus_fnc_Commit = {
    params ["_hq","_posture","_plan"];
    private _order = [_posture,_plan] call ITW_CLASH_Colossus_fnc_OrderFor;
    if (_order isEqualTo "") exitWith {false};

    private _sign = _hq getVariable ["RydHQ_CodeSign","?"];
    private _current = _hq getVariable ["RydHQ_Order","ATTACK"];
    if (ITW_CLASH_ColossusAdvisoryOnly) exitWith {
        if !(_order isEqualTo _current) then {
            ["would-order",[_sign,_current,_order,_posture,_plan getOrDefault ["objective",-1]]] call
                ITW_CLASH_Colossus_fnc_Log;
        };
        false
    };

    if (_order isEqualTo _current) exitWith {false};
    private _changedAt = _hq getVariable ["ITW_CLASH_ColossusOrderAt",-1e10];
    if (time - _changedAt < ITW_CLASH_ColossusOrderDwell) exitWith {
        ["order-held",[_sign,_current,_order,round (ITW_CLASH_ColossusOrderDwell - (time - _changedAt))]] call
            ITW_CLASH_Colossus_fnc_Log;
        false
    };

    private _global = [_hq] call ITW_CLASH_Colossus_fnc_OrderGlobal;
    missionNamespace setVariable [_global,_order];
    publicVariable _global;
    _hq setVariable ["RydHQ_Order",_order];
    _hq setVariable ["ITW_CLASH_ColossusOrderAt",time];

    ["order",[
        _sign,_current,_order,_posture,
        _plan getOrDefault ["objective",-1],
        _plan getOrDefault ["verdict",""],
        round (_plan getOrDefault ["enemy",0]),
        round (_plan getOrDefault ["available",0]),
        _global
    ]] call ITW_CLASH_Colossus_fnc_Log;
    true
};

/*
    Which mirror in this list stands for that objective index.

    Commander B's mirrors are C.L.A.S.H.'s own objects and carry the index
    directly. Commander A's are Impasse's real objective flags, so they are
    matched against ITW_Objectives instead. Returns objNull when the objective
    is not in this commander's list at all, which is a legitimate answer - a
    held or out-of-zone objective is not a candidate.
*/
ITW_CLASH_Colossus_fnc_ResolveMirror = {
    params ["_mirrors","_index"];
    if (_index < 0 || {_mirrors isEqualTo []}) exitWith {objNull};

    private _found = objNull;
    {
        if ((_x getVariable ["ITW_CLASH_ObjectiveIndex",-1]) isEqualTo _index) exitWith {
            _found = _x;
        };
    } forEach _mirrors;
    if (!isNull _found) exitWith {_found};

    if (isNil "ITW_Objectives" || {_index >= count ITW_Objectives}) exitWith {objNull};
    private _objective = ITW_Objectives#_index;
    if (count _objective <= ITW_OBJ_FLAG) exitWith {objNull};
    private _flag = _objective#ITW_OBJ_FLAG;
    if (isNull _flag || {!(_flag in _mirrors)}) exitWith {objNull};
    _flag
};

/*
    The candidate list this commander should actually be offered.

    Returns [mirrors, maxObjectives]. A maxObjectives of -1 means "no opinion":
    the caller keeps its own list and its own default, which is exactly the
    pre-COLOSSUS behaviour. Every reason to decline is a reason the caller is
    better off unmodified, and each one is logged.

    The observation gate is the important one. COLOSSUS reads RydHQ_KnEnemies,
    so an objective with no known enemy reads EMPTY - and EMPTY does not mean
    undefended, it means nobody has looked. Concentrating an entire side onto
    an unobserved objective is how an army gets fed into something nobody
    scouted, so an unobserved choice declines rather than concentrates.
*/
/*
    Is any ground this commander already holds without an anchor?

    Concentration cannot leave a captured objective undefended - HAL's defence
    reads RydHQ_Taken, not the candidate list, and an anchored group is leashed
    to its position by HAC_fnc.sqf:1593 - but it CAN starve the anchor refill,
    because the refill and the attack draw on the same free groups. The result
    is ground that HAL routes defenders past but nothing actually holds, which
    is the VACANT state objective 3 sat in for an entire run.

    So the rule is: take the next objective once the last one is held properly,
    not before. This reads the anchor registries rather than keeping its own
    record, and the two commanders genuinely have separate ones.

    Fails open. If the registry for this commander cannot be read, the answer
    is "nothing unanchored" and concentration proceeds, because a missing
    reader is not evidence of an undefended objective.
*/
ITW_CLASH_Colossus_fnc_HoldingUnanchored = {
    params ["_hq"];
    if (isNull _hq) exitWith {[]};

    private _isB = !isNil "ITW_CLASH_BLUFORHQ" && {_hq isEqualTo ITW_CLASH_BLUFORHQ};
    private _held = [];
    private _registry = createHashMap;

    if (_isB) then {
        if (isNil "ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives") exitWith {};
        _held = call ITW_CLASH_CommanderParity_Anchor_fnc_HeldObjectives;
        _registry = missionNamespace getVariable [
            "ITW_CLASH_CommanderParity_AnchorGroups",createHashMap
        ];
    } else {
        if (isNil "ITW_CLASH_fnc_GetHeldObjectives") exitWith {};
        _held = call ITW_CLASH_fnc_GetHeldObjectives;
        _registry = missionNamespace getVariable ["ITW_CLASH_AnchorGroups",createHashMap];
    };

    private _unanchored = [];
    {
        private _index = _x#0;
        /*
            A locked objective needs no anchor.

            This gate exists because a freshly taken objective is vulnerable
            and concentrating off it loses it (b9d90d1). While Impasse's
            capture lock holds, it is not vulnerable - nobody can move its
            phase at all - so the reason for the hold is absent and
            concentration should proceed. Same fact the anchor audit acts on,
            read from the same predicate.
        */
        if (!isNil "ITW_CLASH_fnc_ObjectiveLocked" && {
            [_index] call ITW_CLASH_fnc_ObjectiveLocked
        }) then {continue};
        private _entry = _registry getOrDefault [str _index,[]];
        private _anchor = if (_entry isEqualTo []) then {grpNull} else {_entry#0};
        if (isNull _anchor || {({alive _x} count units _anchor) == 0}) then {
            _unanchored pushBack _index;
        };
    } forEach _held;
    _unanchored
};

ITW_CLASH_Colossus_fnc_Concentrate = {
    params ["_hq","_mirrors"];
    private _pass = [_mirrors,-1];
    if (isNull _hq || {_mirrors isEqualTo []}) exitWith {_pass};
    if (!ITW_CLASH_ColossusConcentrate) exitWith {_pass};
    if (ITW_CLASH_ColossusAdvisoryOnly) exitWith {_pass};

    private _sign = _hq getVariable ["RydHQ_CodeSign","?"];
    private _plan = ITW_CLASH_ColossusPlans getOrDefault [toUpperANSI str (side _hq),createHashMap];
    private _decline = {
        params ["_reason"];
        ["concentrate-declined",[_sign,_reason]] call ITW_CLASH_Colossus_fnc_Log;
        _pass
    };

    if (count _plan == 0) exitWith {["no-picture"] call _decline};
    if ((_plan getOrDefault ["posture","PUSH"]) isEqualTo "CONSOLIDATE") exitWith {
        ["consolidating"] call _decline
    };
    if (!(_plan getOrDefault ["feasible",false])) exitWith {["short-of-force"] call _decline};

    // Hold what we took before reaching for the next one.
    if (ITW_CLASH_ColossusRequireAnchored) then {
        private _unanchored = [_hq] call ITW_CLASH_Colossus_fnc_HoldingUnanchored;
        if (_unanchored isNotEqualTo []) exitWith {
            ["concentrate-declined",[_sign,"holding-unanchored",_unanchored]] call
                ITW_CLASH_Colossus_fnc_Log;
            _pass
        };
    };

    private _index = _plan getOrDefault ["objective",-1];
    private _mirror = [_mirrors,_index] call ITW_CLASH_Colossus_fnc_ResolveMirror;
    if (isNull _mirror) exitWith {["objective-not-a-candidate"] call _decline};

    // Unobserved is not undefended. See the note above.
    if (
        !isNil "ITW_CLASH_AirPicture_fnc_Observed"
        && {!([_hq,getPosATL _mirror] call ITW_CLASH_AirPicture_fnc_Observed)}
    ) exitWith {["objective-unobserved"] call _decline};

    ["concentrate",[
        _sign,_index,
        _plan getOrDefault ["verdict",""],
        count _mirrors,
        ITW_CLASH_ColossusConcentrateMax
    ]] call ITW_CLASH_Colossus_fnc_Log;
    [[_mirror],ITW_CLASH_ColossusConcentrateMax]
};

ITW_CLASH_Colossus_fnc_Assess = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _picture = [_hq] call ITW_CLASH_Colossus_fnc_Picture;
    ITW_CLASH_ColossusPictures set [toUpperANSI str (side _hq),_picture];

    {
        ["objective",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            _x get "objective",
            _x get "verdict",
            round (_x get "enemy"),
            _x get "enemyCount",
            round (_x get "committed"),
            round (_x get "available")
        ]] call ITW_CLASH_Colossus_fnc_Log;
    } forEach _picture;

    ([_hq] call ITW_CLASH_Colossus_fnc_Theatre) params ["_enemy","_friendly","_contacts"];
    ([_hq,_enemy,_friendly] call ITW_CLASH_Colossus_fnc_Posture) params ["_posture","_ratio"];
    private _was = _hq getVariable ["ITW_CLASH_ColossusPosture","PUSH"];
    _hq setVariable ["ITW_CLASH_ColossusPosture",_posture];
    // Said on the change, not every assessment: the posture is stable by design
    // and repeating it each minute would bury the moment it moved.
    if !(_posture isEqualTo _was) then {
        ["posture",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            _was,_posture,
            round (_ratio * 100) / 100,
            round _enemy,round _friendly,_contacts
        ]] call ITW_CLASH_Colossus_fnc_Log;
    };

    private _plan = [_hq,_picture,_posture,_ratio] call ITW_CLASH_Colossus_fnc_Recommend;
    // Carry the posture on the plan so the mirror writers need only the plan.
    if (count _plan > 0) then {_plan set ["posture",_posture]};
    ITW_CLASH_ColossusPlans set [toUpperANSI str (side _hq),_plan];
    [_hq,_posture,_plan] call ITW_CLASH_Colossus_fnc_Commit;
    true
};

[] spawn {
    scriptName "ITW_CLASH_Colossus";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_fnc_GetCommanderForSide"
            && {missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_ColossusEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (!isNull _hq) then {
                    [_hq] call ITW_CLASH_Colossus_fnc_Assess;
                };
            } forEach _sides;
        };
        sleep ITW_CLASH_ColossusPoll;
    };
};

ITW_CLASH_ColossusReady = true;
diag_log format [
    "CLASH BOOT | colossus-ready | version=%1 advisoryOnly=%2 poll=%3 objectiveRadius=%4 pushRatio=%5 weights=inf%6/armor%7/veh%8/static%9 consolidateAt=%10 releaseAt=%11 postures=PUSH,CONSOLIDATE ordersIssued=%12 orderDwell=%13 concentrate=%14/%15 requireAnchored=%16 halPoolsUntouched=true",
    ITW_CLASH_ColossusVersion,
    ITW_CLASH_ColossusAdvisoryOnly,
    ITW_CLASH_ColossusPoll,
    ITW_CLASH_ColossusObjectiveRadius,
    ITW_CLASH_ColossusPushRatio,
    ITW_CLASH_ColossusWeightInfantry,
    ITW_CLASH_ColossusWeightArmor,
    ITW_CLASH_ColossusWeightVehicle,
    ITW_CLASH_ColossusWeightStatic,
    ITW_CLASH_ColossusConsolidateAt,
    ITW_CLASH_ColossusReleaseAt,
    if (ITW_CLASH_ColossusAdvisoryOnly) then {"none-advisory"} else {"attack-defend"},
    ITW_CLASH_ColossusOrderDwell,
    ITW_CLASH_ColossusConcentrate,
    ITW_CLASH_ColossusConcentrateMax,
    ITW_CLASH_ColossusRequireAnchored
];
true
