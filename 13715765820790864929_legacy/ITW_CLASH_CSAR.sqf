#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CSARStarted",false]) exitWith {true};

/*
    A downed crew is player work.

    ITW_CLASH_CrewRemnantCleanup quarantines the crew of a vehicle that can no
    longer be used, holds it for the grace period, and deletes it once no player
    is near. Those men are the most natural rescue mission a battlefield
    produces, so while a player is ticked for the work this module asks cleanup
    to keep one, walks it away from the wreck, and decides whether a pickup
    would be a reasonable thing to offer.

    Two boundaries keep it free when nobody wants it:

      - No subscribed player group means no claim, no order, no state. A crew
        lives and dies on cleanup's own schedule, exactly as it does today, and
        a claim is given back the moment the last subscriber goes.
      - Nothing here writes ITW_CLASH_Withdrawals or sets
        ITW_CLASH_Withdrawing. That registry is where AI CASEVAC and ground
        MEDEVAC get their work, so an AI aircraft is never sent for a downed
        crew. Cleanup drops a stale GTFO entry for the same reason (v3).

    Ownership: cleanup is still the only thing that deletes a crew. This module
    sets a flag it reads as a hold and takes it off again when it is done.

    A mission is published only once the crew is clear and there is somewhere
    to land, and once it exists nothing here expires it. A rescue ends when the
    men are home, when the crew is gone, when the player cancels, or when the
    player group does - never on a clock.
*/

ITW_CLASH_CSARStarted = true;
ITW_CLASH_CSARVersion = 4;
ITW_CLASH_CSARReady = false;
ITW_CLASH_CSARPoll = missionNamespace getVariable ["ITW_CLASH_CSARPoll",5];
// The employment channel a player ticks for this work. MEDEVAC carries both
// casualty evacuation and crew recovery; the menu presents it as CSAR.
ITW_CLASH_CSARChannel = "MEDEVAC";
/*
    Its own demand kind, on that channel.

    The channel is what a player ticked, so the dispatcher's own machinery -
    finding a willing group, the task, the reservation, decline and cancel -
    needs nothing new. The kind is separate because the survivor rules are not
    the casualty rules: a downed pilot is unhurt, and every medical test in the
    dispatcher asks whether a man is a severe casualty.

    The delivery distance is the dispatcher's own, read at use time, so a
    rescue lands home where a casualty run lands. Pickup is the squad evac's
    (v3): a casualty is carried aboard where it lies, a downed crew walks
    over and climbs in.
*/
ITW_CLASH_CSARKind = "CSAR_CREW";
// The squad evac's pickup distance: survivors walk to a carrier grounded
// within GatherRadius and climb in.
ITW_CLASH_CSARGatherRadius = missionNamespace getVariable ["ITW_CLASH_CSARGatherRadius",300];
/*
    A claim that never becomes offerable is handed back rather than held for the
    rest of the mission, so unresolved crews cannot accumulate.

    This is not a deadline on a rescue. It only runs while no mission exists for
    the crew; once a player holds the job, nothing in this module expires it.
*/
ITW_CLASH_CSARClaimCeiling = missionNamespace getVariable [
    "ITW_CLASH_CSARClaimCeiling",900
];
ITW_CLASH_CSAROrderCooldown = missionNamespace getVariable [
    "ITW_CLASH_WithdrawalOrderCooldown",30
];
ITW_CLASH_CSARCrews = [];

ITW_CLASH_CSAR_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["csar-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH CSAR | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_CSAR_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    [_group] call ITW_CLASH_DualHAL_fnc_GroupId
};

ITW_CLASH_CSAR_fnc_Find = {
    params ["_group"];
    ITW_CLASH_CSARCrews findIf {(_x get "group") isEqualTo _group}
};

/*
    Is anyone ticked for this work?

    Willingness only. Whether a particular group is free to take the job is the
    dispatcher's question, asked when a mission is published; a CSAR player
    already carrying another assignment should not stop a crew from escaping.
*/
ITW_CLASH_CSAR_fnc_HasSubscriber = {
    if (isNil "ITW_CLASH_PlayerTaskGroups") exitWith {false};
    (ITW_CLASH_PlayerTaskGroups findIf {
        private _candidate = _x;
        !isNull _candidate
        && {((units _candidate) findIf {alive _x && {isPlayer _x}}) >= 0}
        && {[_candidate,ITW_CLASH_CSARChannel] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed}
    }) >= 0
};

/*
    On the ground, every one of them.

    This is what keeps an ejected pilot out of it while the canopy is still
    open: a man under a parachute reports the parachute from `vehicle`, not
    himself. No ejection event handler, so a modded ejection cannot break it,
    and it is the same test CASEVAC's own gate applies before it commits.
*/
ITW_CLASH_CSAR_fnc_OnFoot = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _alive = units _group select {alive _x};
    _alive isNotEqualTo [] && {(_alive findIf {vehicle _x != _x}) < 0}
};

/*
    GetObjectiveClearance measures against one objective, and a crew that has
    lost its vehicle no longer has an objective of its own. The one it went down
    beside is the one a pickup should stay clear of.
*/
ITW_CLASH_CSAR_fnc_NearestObjective = {
    params ["_pos"];
    if (isNil "ITW_Objectives" || {_pos isEqualTo []}) exitWith {-1};
    private _best = -1;
    private _bestDistance = 1e10;
    {
        private _distance = (_pos distance2D (_x#ITW_OBJ_POS)) - (_x#ITW_OBJ_SIZE);
        if (_distance < _bestDistance) then {
            _bestDistance = _distance;
            _best = _forEachIndex;
        };
    } forEach ITW_Objectives;
    _best
};

/*
    Walk them out, with the mission's own withdrawal primitives.

    GetEgressPoint resolves a rear corridor from the live zone picture, and
    OrderWithdrawal is the order itself: waypoints cleared, enableAttack false,
    combat mode BLUE, AWARE, full speed. Self-defence only, which is the whole
    of the behaviour a surviving crew needs, already written and already flown
    by GTFO. The source string is prefixed so an RPT reader can tell a crew
    escape from a HAL withdrawal.
*/
ITW_CLASH_CSAR_fnc_OrderEscape = {
    params ["_group"];
    if (isNull _group) exitWith {[]};
    private _resolved = [_group,-1] call ITW_CLASH_fnc_GetEgressPoint;
    if (_resolved isEqualTo []) exitWith {[]};
    _resolved params ["_destination","_egressObjective","_source"];
    if (_destination isEqualTo []) exitWith {[]};
    if !([
        _group,_destination,_egressObjective,"csar-" + str _source
    ] call ITW_CLASH_fnc_OrderWithdrawal) exitWith {[]};
    +_destination
};

/*
    The question CASEVAC already answers for a withdrawing squad: is this a
    reasonable place to send an aircraft?

    Same helpers and the same five numbers, so there is one definition of
    battlefield safety and CSAR cannot drift from it. Cheap tests first, the
    map-wide enemy scan and the landing-zone search last.

    Enemy distance is server-side truth, including enemies HAL has never seen.
    That is used to decide whether offering the mission is reasonable, never to
    steer the crew around what they cannot see.
*/
ITW_CLASH_CSAR_fnc_Gate = {
    params ["_entry"];
    private _group = _entry get "group";
    private _measure = [-1,-1,-1];
    if (isNull _group) exitWith {[false,"gone",_measure,[]]};
    if !([_group] call ITW_CLASH_CSAR_fnc_OnFoot) exitWith {[false,"mounted",_measure,[]]};
    if (time - (_entry get "onFootAt") < ITW_CLASH_CASEVAC_MinWithdrawalTime) exitWith {
        [false,"settling",_measure,[]]
    };

    private _moved = (leader _group) distance2D (_entry get "origin");
    _measure set [0,round _moved];
    if (_moved < ITW_CLASH_CASEVAC_MinDisengageDistance) exitWith {
        [false,"distance",_measure,[]]
    };

    private _objectiveClear = [
        _group,_entry get "objective"
    ] call ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance;
    _measure set [2,round (_objectiveClear min 9999)];
    if (_objectiveClear < ITW_CLASH_CASEVAC_ObjectiveClearance) exitWith {
        [false,"objective",_measure,[]]
    };

    private _enemy = [_group] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
    _measure set [1,round (_enemy min 9999)];
    if (_enemy < ITW_CLASH_CASEVAC_EnemyClearance) exitWith {
        [false,"enemy",_measure,[]]
    };

    private _destination = _entry get "destination";
    if (_destination isEqualTo []) exitWith {[false,"corridor",_measure,[]]};
    private _lz = [_group,_destination] call ITW_CLASH_CASEVAC_fnc_FindLZ;
    if (_lz isEqualTo []) exitWith {[false,"lz",_measure,[]]};

    [true,"clear",_measure,+_lz]
};

ITW_CLASH_CSAR_fnc_Release = {
    params ["_group",["_reason","released"]];
    private _id = [_group] call ITW_CLASH_CSAR_fnc_GroupId;
    private _index = [_group] call ITW_CLASH_CSAR_fnc_Find;
    if (_index >= 0) then {ITW_CLASH_CSARCrews deleteAt _index};
    // The hold goes back to cleanup, which deletes the crew on its own terms.
    if (!isNull _group) then {_group setVariable ["ITW_CLASH_CSAR",nil]};
    ["released",[_id,_reason]] call ITW_CLASH_CSAR_fnc_Log;
    true
};

ITW_CLASH_CSAR_fnc_Claim = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _veh = _group getVariable ["ITW_CLASH_CrewVehicle",objNull];
    private _origin = getPosATL leader _group;

    // Asked for, not taken: cleanup reads this flag as a hold and remains the
    // only thing that deletes the crew.
    _group setVariable ["ITW_CLASH_CSAR",true];

    private _entry = createHashMapFromArray [
        ["group",_group],
        ["class",if (isNull _veh) then {"<null>"} else {typeOf _veh}],
        ["origin",+_origin],
        ["onFootAt",time],
        ["objective",[_origin] call ITW_CLASH_CSAR_fnc_NearestObjective],
        ["destination",[]],
        ["state","ESCAPING"],
        ["lz",[]],
        ["reason",""],
        ["orderedAt",-1e6]
    ];
    ITW_CLASH_CSARCrews pushBack _entry;

    private _destination = [_group] call ITW_CLASH_CSAR_fnc_OrderEscape;
    if (_destination isNotEqualTo []) then {
        _entry set ["destination",+_destination];
        _entry set ["orderedAt",time];
    };

    ["claimed",[
        [_group] call ITW_CLASH_CSAR_fnc_GroupId,
        {alive _x} count units _group,
        _entry get "class",
        _entry get "objective",
        _destination
    ]] call ITW_CLASH_CSAR_fnc_Log;
    true
};

ITW_CLASH_CSAR_fnc_Escaping = {
    params ["_entry"];
    private _group = _entry get "group";

    ([_entry] call ITW_CLASH_CSAR_fnc_Gate) params [
        "_passed","_reason","_measure","_lz"
    ];

    if (_passed) exitWith {
        _entry set ["lz",+_lz];
        _entry set ["state","HOLDING"];
        _entry set ["reason",_reason];
        // Escape, then hold: the staging order CASEVAC uses for its own
        // survivors, so the crew waits on a pad instead of walking away from
        // the player coming for it.
        if (!isNil "ITW_CLASH_CASEVAC_fnc_OrderLZ") then {
            [_group,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ;
        };
        ["eligible",[
            [_group] call ITW_CLASH_CSAR_fnc_GroupId,
            {alive _x} count units _group,
            _measure#0,_measure#1,_measure#2,_lz
        ]] call ITW_CLASH_CSAR_fnc_Log;
        true
    };

    if (time - (_entry get "orderedAt") >= ITW_CLASH_CSAROrderCooldown) then {
        private _destination = [_group] call ITW_CLASH_CSAR_fnc_OrderEscape;
        if (_destination isNotEqualTo []) then {
            _entry set ["destination",+_destination];
            _entry set ["orderedAt",time];
        };
    };

    // Logged when the answer changes, not every pass: the point is to be able
    // to read why a crew has not become offerable, not to fill the RPT.
    if (_reason isNotEqualTo (_entry get "reason")) then {
        _entry set ["reason",_reason];
        ["waiting",[
            [_group] call ITW_CLASH_CSAR_fnc_GroupId,
            _reason,_measure#0,_measure#1,_measure#2
        ]] call ITW_CLASH_CSAR_fnc_Log;
    };
    false
};

ITW_CLASH_CSAR_fnc_SourceKey = {
    params ["_group"];
    ITW_CLASH_CSARKind + "|" + str _group
};

// The live mission for this crew, or "" when there is none. Asked rather than
// stored: the dispatcher owns mission state, and a demand that completed,
// invalidated or failed is not one this module should still be counting on.
ITW_CLASH_CSAR_fnc_DemandId = {
    params ["_group"];
    if (isNull _group || {isNil "ITW_CLASH_PlayerDemand_fnc_FindBySourceKey"}) exitWith {""};
    [[_group] call ITW_CLASH_CSAR_fnc_SourceKey] call
        ITW_CLASH_PlayerDemand_fnc_FindBySourceKey
};

ITW_CLASH_CSAR_fnc_DemandState = {
    params ["_demandId"];
    if (_demandId isEqualTo "") exitWith {""};
    ([_demandId] call ITW_CLASH_PlayerDemand_fnc_Get) getOrDefault ["state",""]
};

/*
    Publish, now that the crew is clear and there is somewhere to land.

    ApplySuppression has no array for this kind, which is correct: HAL does not
    own this crew any more, so there is no native request to suppress while a
    player works it.
*/
ITW_CLASH_CSAR_fnc_Publish = {
    params ["_entry"];
    private _group = _entry get "group";
    if (isNil "ITW_CLASH_PlayerDemand_fnc_Publish") exitWith {""};
    if !(missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]) exitWith {""};
    private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    if (isNull _hq) exitWith {""};
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) exitWith {""};

    private _class = _entry get "class";
    private _display = getText (configFile >> "CfgVehicles" >> _class >> "displayName");
    if (_display isEqualTo "") then {_display = _class};

    private _demandId = [
        ITW_CLASH_CSARChannel,
        ITW_CLASH_CSARKind,
        [_group] call ITW_CLASH_CSAR_fnc_SourceKey,
        _hq,
        _leader,
        "CSAR: Downed Crew",
        format [
            "Downed %1 crew, on foot and clear of the wreck. Location is marked. Land near them; they walk over and board. Bring every survivor back to a friendly base.",
            _display
        ],
        "Any working vehicle with seats for every survivor.",
        +(_entry get "lz")
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    if (_demandId isEqualTo "") exitWith {""};

    _entry set ["state","OFFERED"];
    ["offered",[
        [_group] call ITW_CLASH_CSAR_fnc_GroupId,
        _demandId,
        {alive _x} count units _group,
        _display,
        _entry get "lz"
    ]] call ITW_CLASH_CSAR_fnc_Log;
    _demandId
};

/*
    Recovered, and that is all.

    No vehicle back, no replacement men, no credit: the crew was rescued for
    its own sake and a rescue is not an economy. The hold goes back to cleanup,
    which removes the men once no player is standing next to them.
*/
ITW_CLASH_CSAR_fnc_Recovered = {
    params ["_crew"];
    if (isNull _crew) exitWith {false};
    ["recovered",[
        [_crew] call ITW_CLASH_CSAR_fnc_GroupId,
        {alive _x} count units _crew
    ]] call ITW_CLASH_CSAR_fnc_Log;
    [_crew,"recovered"] call ITW_CLASH_CSAR_fnc_Release
};

// On foot and alive. A man already in the rescue vehicle is aboard, not waiting.
ITW_CLASH_CSAR_fnc_Survivors = {
    params ["_demand"];
    private _crew = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _crew) exitWith {[]};
    units _crew select {alive _x && {vehicle _x == _x}}
};

/*
    Load them, with the dispatcher's own transfer rules.

    The medical path cannot be reused as it stands: its evacuee selection, its
    validity test and its delivery all ask ITW_CLASH_PlayerDemand_fnc_
    IsSevereCasualty, and a rescued pilot is unhurt. The grounded vehicle, the
    capacity test and the walk-in boarding are the dispatcher's.
*/
ITW_CLASH_CSAR_fnc_StartExecution = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "RESERVED"}) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    if (isNull _group) exitWith {false};

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    private _crew = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _crew) exitWith {false};
    // On foot or already in this carrier; a man in any other vehicle is not ours.
    private _men = units _crew select {
        alive _x && {vehicle _x == _x || {vehicle _x == _vehicle}}
    };
    private _survivors = [_demand] call ITW_CLASH_CSAR_fnc_Survivors;
    /*
        v3 (Hark, 2026-10-27): "polaris crew do not want to get in". v2 loaded
        only when every survivor already stood inside the dispatcher's 35m
        casualty radius and never told them to move, then put them straight
        into their seats. A carrier grounded within GatherRadius now has them
        walk over and climb in, the way AI CASEVAC boards its survivors.
    */
    private _ready = !isNull _vehicle
        && {[_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity}
        && {[_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer}
        && {_men isNotEqualTo []}
        && {(_vehicle emptyPositions "cargo") >= count _survivors}
        && {(_men findIf {_x distance2D _vehicle <= ITW_CLASH_CSARGatherRadius}) >= 0};
    if (!_ready) exitWith {
        if (_demand getOrDefault ["boarding",false]) then {
            _demand set ["boarding",false];
            [_survivors,_demand getOrDefault ["boardingVehicle",objNull],_demand] call
                ITW_CLASH_PlayerDemand_fnc_CancelBoarding;
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
        };
        false
    };
    _demand set ["boarding",true];
    _demand set ["boardingVehicle",_vehicle];
    private _aboard = [_men,_vehicle,_demand] call ITW_CLASH_PlayerDemand_fnc_BoardOnFoot;
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    if (!_aboard) exitWith {false};
    _survivors = _men select {alive _x};

    _demand set ["state","EXECUTING"];
    _demand set ["stateAt",time];
    _demand set ["executionVehicle",_vehicle];
    _demand set ["evacuees",+_survivors];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["loaded",[
        _demandId,typeOf _vehicle,count _survivors
    ]] call ITW_CLASH_CSAR_fnc_Log;
    ["player-demand-executing",[_demandId,ITW_CLASH_CSARKind]] call
        ITW_CLASH_PlayerDemand_fnc_Log;

    [_demandId] spawn ITW_CLASH_CSAR_fnc_RunDelivery;
    true
};

/*
    Fly them home.

    The destination is resolved against live base ownership every pass, not
    cached, so a base lost mid-flight moves the task rather than stranding it.
    No clock: only the carrier being lost, the player cancelling, or the men
    being on the ground at a friendly base ends this.
*/
ITW_CLASH_CSAR_fnc_RunDelivery = {
    params ["_demandId"];
    while {true} do {
        sleep 1;
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "EXECUTING"}) exitWith {};

        private _group = _demand getOrDefault ["reservedGroup",grpNull];
        private _vehicle = _demand getOrDefault ["executionVehicle",objNull];
        private _survivors = +(_demand getOrDefault ["evacuees",[]]);
        private _taskId = _demand getOrDefault ["taskId",""];
        private _crew = _demand getOrDefault ["targetGroup",grpNull];

        if (isNull _group || {isNull _vehicle} || {!alive _vehicle}) exitWith {
            [_demandId,"csar-carrier-lost",false] call ITW_CLASH_PlayerDemand_fnc_Release;
        };

        if (_group getVariable ["ITW_CLASH_PlayerDemandCancel",false]) then {
            if ([_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer) exitWith {
                {
                    if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
                        unassignVehicle _x;
                        moveOut _x;
                    };
                } forEach _survivors;
                [_demandId,"player-canceled-csar",true] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
            continue;
        };

        private _resolved = createHashMap;
        if (!isNil "ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup") then {
            _resolved = [_group,_vehicle,"player-csar"] call
                ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup;
        };
        if ((_resolved getOrDefault ["status",""]) != "RESOLVED") then {continue};
        private _home = +(_resolved get "position");
        if (_taskId isNotEqualTo "") then {
            [_taskId,_home] call BIS_fnc_taskSetDestination;
        };
        if (_vehicle distance2D _home > ITW_CLASH_PlayerDemandMedevacHomeRadius) then {continue};
        if !([_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer) then {continue};

        {
            if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
                unassignVehicle _x;
                moveOut _x;
            };
        } forEach _survivors;
        sleep 0.5;
        if ((_survivors findIf {
            !isNull _x && {alive _x} && {vehicle _x == _vehicle}
        }) >= 0) then {continue};

        [_demandId,"crew-recovered-at-friendly-home"] call
            ITW_CLASH_PlayerDemand_fnc_Complete;
        [_crew] call ITW_CLASH_CSAR_fnc_Recovered;
        break;
    };
    true
};

ITW_CLASH_CSAR_fnc_Offered = {
    params ["_entry"];
    private _group = _entry get "group";
    private _demandId = [_group] call ITW_CLASH_CSAR_fnc_DemandId;
    // The dispatcher ended it - invalidated, failed, or completed by a path
    // other than the delivery above. Either way the crew is cleanup's again.
    if (_demandId isEqualTo "") exitWith {
        [_group,"mission-ended"] call ITW_CLASH_CSAR_fnc_Release
    };
    false
};

ITW_CLASH_CSAR_fnc_Tick = {
    if (!ITW_CLASH_CSARReady || {isNil "ITW_CLASH_CrewRemnantQuarantined"}) exitWith {false};

    private _wanted = call ITW_CLASH_CSAR_fnc_HasSubscriber;

    {
        private _group = _x;
        private _index = [_group] call ITW_CLASH_CSAR_fnc_Find;
        if (_index < 0) then {continue};
        private _entry = ITW_CLASH_CSARCrews#_index;

        if (isNull _group || {({alive _x} count units _group) == 0}) then {
            [_group,"crew-lost"] call ITW_CLASH_CSAR_fnc_Release;
            continue
        };
        private _demandId = [_group] call ITW_CLASH_CSAR_fnc_DemandId;
        private _accepted = ([_demandId] call ITW_CLASH_CSAR_fnc_DemandState)
            in ["RESERVED","EXECUTING"];

        /*
            Nobody is ticked for the work any more.

            A rescue a player has actually taken is left alone: it is their job
            until something happens to it. Anything short of that is handed
            back, and the hold goes first so an open mission ends through the
            dispatcher's own validity test rather than a second rule here.
        */
        if (!_wanted && {!_accepted}) then {
            [_group,"no-subscriber"] call ITW_CLASH_CSAR_fnc_Release;
            if (_demandId isNotEqualTo "") then {
                [_demandId,"csar-no-subscriber",false] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
            continue
        };

        if (
            (_entry get "state") isEqualTo "ESCAPING"
            && {time - (_entry get "onFootAt") > ITW_CLASH_CSARClaimCeiling}
        ) then {
            [_group,"never-offerable"] call ITW_CLASH_CSAR_fnc_Release;
            continue
        };

        switch (_entry get "state") do {
            case "ESCAPING": {[_entry] call ITW_CLASH_CSAR_fnc_Escaping};
            case "HOLDING": {[_entry] call ITW_CLASH_CSAR_fnc_Publish};
            case "OFFERED": {[_entry] call ITW_CLASH_CSAR_fnc_Offered};
        };
    } forEach (ITW_CLASH_CSARCrews apply {_x get "group"});

    if (!_wanted) exitWith {true};

    {
        private _group = _x;
        if (isNull _group) then {continue};
        if (([_group] call ITW_CLASH_CSAR_fnc_Find) >= 0) then {continue};
        if (isNil "ITW_PlayerSide" || {side _group != ITW_PlayerSide}) then {continue};
        if !([_group] call ITW_CLASH_CSAR_fnc_OnFoot) then {continue};
        // Somebody else's crew: a CASEVAC, a ground MEDEVAC, reconstitution
        // transit, a recovery or an Impasse delivery. Cleanup's own test, so
        // this cannot drift from the list the deleter honours.
        if ([_group] call ITW_CLASH_CrewRemnant_fnc_IsReserved) then {continue};
        [_group] call ITW_CLASH_CSAR_fnc_Claim;
    } forEach +ITW_CLASH_CrewRemnantQuarantined;

    true
};

[] spawn {
    scriptName "ITW_CLASH_CSAR";
    // CASEVAC and cleanup are execVM'd, so their functions appear after this
    // file is read. Wait for the ones this module calls rather than assuming
    // boot order, and stay off the battlefield entirely if they never arrive.
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.5;
        diag_tickTime >= _deadline
        || {
            !isNil "ITW_CLASH_CrewRemnantQuarantined"
            && {!isNil "ITW_CLASH_CrewRemnant_fnc_IsReserved"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_FindLZ"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance"}
            && {!isNil "ITW_CLASH_fnc_GetEgressPoint"}
            && {!isNil "ITW_CLASH_fnc_OrderWithdrawal"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_IsSubscribed"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Publish"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StillValid"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_UpdateReserved"}
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | WARNING | csar-prerequisites-missing | downed crews keep the cleanup lifecycle";
    };

    /*
        Extend the dispatcher, do not edit it.

        Both wrappers hand every other kind straight back to what was there
        before, which is also how ITW_CLASH_PlayerDemandAmmoValidityHardening
        extends the same two functions, so the order the two files bind in does
        not matter.
    */
    ITW_CLASH_CSAR_fnc_StillValidBase = ITW_CLASH_PlayerDemand_fnc_StillValid;
    ITW_CLASH_PlayerDemand_fnc_StillValid = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        if ((_demand getOrDefault ["kind",""]) isNotEqualTo ITW_CLASH_CSARKind) exitWith {
            _this call ITW_CLASH_CSAR_fnc_StillValidBase
        };
        if ((_demand getOrDefault ["state",""]) in ["COMPLETED","INVALID","FAILED"]) exitWith {false};

        /*
            A rescue is valid while there is a crew to rescue, and nothing else.

            Without a case of its own the base predicate falls through to
            `default {true}`, and an open mission would outlive the men it was
            published for. There is deliberately no clock here: only the crew
            being gone, the hold being given up, or the recovery finishing.
        */
        private _crew = _demand getOrDefault ["targetGroup",grpNull];
        if (isNull _crew) exitWith {false};
        if (({alive _x} count units _crew) == 0) exitWith {false};
        if !(_crew getVariable ["ITW_CLASH_CSAR",false]) exitWith {false};
        true
    };

    ITW_CLASH_CSAR_fnc_UpdateReservedBase = ITW_CLASH_PlayerDemand_fnc_UpdateReserved;
    ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {};
        if ((_demand getOrDefault ["kind",""]) isNotEqualTo ITW_CLASH_CSARKind) exitWith {
            _this call ITW_CLASH_CSAR_fnc_UpdateReservedBase
        };
        private _state = _demand getOrDefault ["state",""];
        if !(_state in ["RESERVED","EXECUTING"]) exitWith {};

        if !([_demandId] call ITW_CLASH_PlayerDemand_fnc_StillValid) exitWith {
            [_demandId,"underlying-demand-invalidated",false] call
                ITW_CLASH_PlayerDemand_fnc_Release
        };
        // Any living human in the group keeps the job; none releases it. The
        // dispatcher's rule, so a death or a disconnect needs no policy here.
        private _group = _demand getOrDefault ["reservedGroup",grpNull];
        if !([_group] call ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive) exitWith {
            [_demandId,"player-group-unavailable",false] call
                ITW_CLASH_PlayerDemand_fnc_Release
        };

        if (_state isEqualTo "RESERVED") then {
            private _nextLog = _demand getOrDefault ["lastPreparingLogAt",0];
            if (time >= _nextLog) then {
                _demand set ["lastPreparingLogAt",time + 30];
                ITW_CLASH_PlayerDemands set [_demandId,_demand];
                ["player-demand-preparing",[
                    _demandId,
                    [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                    _demand getOrDefault ["requirement",""]
                ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            };
            [_demandId] call ITW_CLASH_CSAR_fnc_StartExecution;
        };
    };

    ITW_CLASH_CSARReady = true;
    diag_log format [
        "CLASH BOOT | csar-ready | version=%1 poll=%2 channel=%3 claimCeiling=%4 playerSideOnly=true writesWithdrawals=false aiDispatch=false publishesMission=true missionDeadline=none gather=%5 boardOnFoot=true",
        ITW_CLASH_CSARVersion,
        ITW_CLASH_CSARPoll,
        ITW_CLASH_CSARChannel,
        ITW_CLASH_CSARClaimCeiling,
        ITW_CLASH_CSARGatherRadius
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_CSARPoll;
        call ITW_CLASH_CSAR_fnc_Tick;
    };

    diag_log "CLASH BOOT | csar-stopped";
};

true
