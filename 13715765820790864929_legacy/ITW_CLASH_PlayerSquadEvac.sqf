#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacStarted",false]) exitWith {true};

ITW_CLASH_PlayerSquadEvacStarted = true;
ITW_CLASH_PlayerSquadEvacVersion = 4;
ITW_CLASH_PlayerSquadEvacReady = false;

/*
    Players first for every squad the AI would lift out.

    Hark, 2026-10-27: "when ai calls for MEDEVAC, no matter the cause, players
    get first dibs." The player MEDEVAC job only ever fired for a man who was
    alive above 75% damage or unable to stand, which vanilla AI almost never
    is, while every squad that was actually cut up withdrew and was lifted by
    AI CASEVAC or ground MEDEVAC, which players never saw. This module gives
    that lift to players first, on the CSAR channel.

    The squad behaves exactly as it does for an AI pilot (Hark: "Medevac has
    them withdraw and with a ton of checks before they can radio for pickup,
    that's good behavior we shouldn't reserve just for the AI pickup"):

      - WITHDRAWING: it walks out under GTFO as before. Nothing is offered.
      - RADIO: CASEVAC's own eligibility passes - 60 s into the withdrawal,
        500 m from where it broke contact, clear of the objective, 650 m from
        any enemy, far enough from home, and a landing zone found. That is the
        moment the AI would launch; if a CSAR group is free, the call goes to
        players instead. The squad stops on CASEVAC's landing zone and holds
        there, locked with ITW_CLASH_CASEVAC_State as an AI evac locks it (the
        egress freezes, no foot re-orders), so it no longer walks a route home
        that can lead back into the fight.
      - RESERVED: a player group has it, and a marker keeps AI CASEVAC and
        ground MEDEVAC off the squad. Within 700 m of the landing zone's squad
        the carrier is shown smoke, as an AI pilot is. Contact closing on the
        landing zone aborts as CASEVAC aborts - 450 m, or 150 m once the
        carrier is committed within 800 m - and the squad moves on; it calls
        again from the next safe spot, still for the same player.
      - PICKUP: the carrier is grounded within GatherRadius; the squad walks
        to it and climbs in, as AI CASEVAC's survivors do.
      - EXECUTING: flying them to their rally point, where the mission's own
        withdrawal audit absorbs them and queues the rebuild, exactly as for
        an AI CASEVAC: no second credit path.

    A player who drops it, goes quiet (the dispatcher's own liveness rule) or
    loses the carrier hands the squad back to its walk; with no other player
    free the call goes to the AI, and the squad is not offered to players
    again for the dispatcher's decline cooldown. With nobody free in the first
    place, nothing changes: the AI takes it at the same moment it always did.

    Player side only: AI CASEVAC and ground MEDEVAC keep the enemy's withdrawals.
*/

ITW_CLASH_PlayerSquadEvacEnabled = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacEnabled",true];
ITW_CLASH_PlayerSquadEvacPoll = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacPoll",2];
ITW_CLASH_PlayerSquadEvacChannel = "MEDEVAC";
ITW_CLASH_PlayerSquadEvacKind = "MEDEVAC_SQUAD";
ITW_CLASH_PlayerSquadEvacMarker = "ITW_CLASH_PlayerSquadEvacReservation";
// A grounded carrier this close to the squad leader starts the pickup.
ITW_CLASH_PlayerSquadEvacGatherRadius = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacGatherRadius",300];
// Delivered: within the withdrawal's arrival radius plus this, metres.
ITW_CLASH_PlayerSquadEvacDeliverySlack = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacDeliverySlack",150];
// Grounded at the rally point this long without being absorbed: unload them.
ITW_CLASH_PlayerSquadEvacDeliveryHold = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacDeliveryHold",30];
/*
    Smoke, as AI CASEVAC does it: once the carrier is within CASEVAC's own
    SmokeDistance (700 m), CASEVAC's smoke goes up on the landing zone the
    squad is holding. A player may circle where an AI pilot flies straight in,
    so the smoke goes up again after this many seconds while they are still
    inbound. 0: once, as the AI.
*/
ITW_CLASH_PlayerSquadEvacSmokeRepop = missionNamespace getVariable ["ITW_CLASH_PlayerSquadEvacSmokeRepop",120];
// The squad's own states under a player's evac, read by StillValid and ReturnSquad.
ITW_CLASH_PlayerSquadEvacStates = ["player-lz","player-pickup","player-rtb"];

ITW_CLASH_PlayerSquadEvac_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["squad-evac-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH SQUAD EVAC | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerSquadEvac_fnc_SourceKey = {
    params ["_withdrawalId"];
    ITW_CLASH_PlayerSquadEvacKind + "|" + _withdrawalId
};

ITW_CLASH_PlayerSquadEvac_fnc_Entry = {
    params ["_demand"];
    if (isNil "ITW_CLASH_Withdrawals") exitWith {[]};
    ITW_CLASH_Withdrawals getOrDefault [_demand getOrDefault ["withdrawalId",""],[]]
};

// Is a player group free to take a CSAR call right now?
ITW_CLASH_PlayerSquadEvac_fnc_PlayerAvailable = {
    if (isNil "ITW_CLASH_PlayerTaskGroups") exitWith {false};
    (ITW_CLASH_PlayerTaskGroups findIf {
        !isNull _x && {[_x,ITW_CLASH_PlayerSquadEvacChannel] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob}
    }) >= 0
};

// Does a player hold this withdrawal? Asked by the AI evac gates.
ITW_CLASH_PlayerSquadEvac_fnc_PlayerHolds = {
    params ["_entry"];
    private _group = _entry param [0,grpNull];
    !isNull _group && {(_group getVariable [ITW_CLASH_PlayerSquadEvacMarker,""]) isNotEqualTo ""}
};

ITW_CLASH_PlayerSquadEvac_fnc_Publish = {
    params ["_withdrawalId","_entry","_lz"];
    private _group = _entry#0;
    private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    if (isNull _hq) exitWith {""};
    private _leader = leader _group;
    if (isNull _leader || {!alive _leader}) exitWith {""};
    private _count = {alive _x} count units _group;
    private _name = [_group] call ITW_CLASH_fnc_GroupId;

    private _demandId = [
        ITW_CLASH_PlayerSquadEvacChannel,
        ITW_CLASH_PlayerSquadEvacKind,
        [_withdrawalId] call ITW_CLASH_PlayerSquadEvac_fnc_SourceKey,
        _hq,
        _leader,
        "CSAR: Squad Extraction",
        format [
            "%1 has broken contact with %2 men and is holding for pickup. Landing zone is marked; they pop smoke when you are close. Take every survivor aboard and fly them to the rally point, where they rebuild.",
            _name,_count
        ],
        format ["Any working vehicle with at least %1 seats.",_count],
        +_lz
    ] call ITW_CLASH_PlayerDemand_fnc_Publish;
    if (_demandId isEqualTo "") exitWith {""};

    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    _demand set ["withdrawalId",_withdrawalId];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    _demandId
};

/*
    Take the squad from its foot withdrawal: the same lock CASEVAC applies when
    its aircraft commits, so the egress freezes and no competing MOVE arrives.
*/
ITW_CLASH_PlayerSquadEvac_fnc_HoldSquad = {
    params ["_demandId","_state"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    private _squad = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _squad) exitWith {false};
    _squad setVariable ["ITW_CLASH_CASEVAC_State",_state];
    private _entry = [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_Entry;
    if (_entry isNotEqualTo []) then {
        _entry set [8,time + 1e6];
        ITW_CLASH_Withdrawals set [_demand get "withdrawalId",_entry];
    };
    _demand set ["squadHeld",true];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    true
};

// CASEVAC's staging order leaves an invisible pad on the landing zone.
ITW_CLASH_PlayerSquadEvac_fnc_ClearPad = {
    params ["_squad"];
    if (isNull _squad) exitWith {};
    private _pad = _squad getVariable ["ITW_CLASH_CASEVAC_LZPad",objNull];
    if (!isNull _pad) then {deleteVehicle _pad};
    _squad setVariable ["ITW_CLASH_CASEVAC_LZPad",nil];
};

// Stop on the landing zone and hold there: CASEVAC's own staging order.
ITW_CLASH_PlayerSquadEvac_fnc_HoldAtLz = {
    params ["_demandId","_lz",["_why","radio"]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    private _squad = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _squad || {_lz isEqualTo []}) exitWith {false};
    [_demandId,"player-lz"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldSquad;
    [_squad,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ;
    _demand set ["lz",+_lz];
    _demand set ["smokeAt",-1];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    private _taskId = _demand getOrDefault ["taskId",""];
    if (_taskId isNotEqualTo "") then {[_taskId,_lz] call BIS_fnc_taskSetDestination};
    [_why,[
        _demandId,[_squad] call ITW_CLASH_fnc_GroupId,{alive _x} count units _squad,_lz
    ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
    true
};

/*
    Back to walking, at once. Nobody aboard: a caller with men in the vehicle
    unloads them on the ground first.
*/
ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad = {
    params ["_demandId",["_reason","returned"]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0 || {!(_demand getOrDefault ["squadHeld",false])}) exitWith {false};
    _demand set ["squadHeld",false];
    _demand set ["lz",[]];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    private _squad = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _squad) exitWith {false};
    if ((_squad getVariable ["ITW_CLASH_CASEVAC_State",""]) in ITW_CLASH_PlayerSquadEvacStates) then {
        _squad setVariable ["ITW_CLASH_CASEVAC_State",nil];
    };
    [_squad] call ITW_CLASH_PlayerSquadEvac_fnc_ClearPad;
    private _entry = [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_Entry;
    if (_entry isNotEqualTo [] && {(_entry#5) isNotEqualTo []}) then {
        [_squad,_entry#5,_entry#6,_entry#7] call ITW_CLASH_fnc_OrderWithdrawal;
        _entry set [8,time];
        ITW_CLASH_Withdrawals set [_demand get "withdrawalId",_entry];
    };
    ["returned",[
        _demandId,[_squad] call ITW_CLASH_fnc_GroupId,_reason,{alive _x} count units _squad
    ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
    true
};

/*
    The radio call. True when players own this withdrawal - just now, or
    already - and the AI must leave it alone; false to let the AI decide.

    The check is CASEVAC's own eligibility, unwrapped: the same safety gates,
    the same landing zone, at the same moment the AI would launch. An open
    call nobody is free to take goes to the AI, and the squad is not offered
    to players again for the dispatcher's decline cooldown, so it cannot flap
    between the two.
*/
ITW_CLASH_PlayerSquadEvac_fnc_Radio = {
    params ["_id","_entry"];
    if (!ITW_CLASH_PlayerSquadEvacEnabled) exitWith {false};
    if (_entry isEqualTo [] || {count _entry < 9}) exitWith {false};
    private _squad = _entry#0;
    if (isNull _squad || {isNil "ITW_PlayerSide"} || {side _squad != ITW_PlayerSide}) exitWith {false};

    private _demandId = [[_id] call ITW_CLASH_PlayerSquadEvac_fnc_SourceKey] call
        ITW_CLASH_PlayerDemand_fnc_FindBySourceKey;
    private _owned = false;
    if (_demandId isNotEqualTo "") then {
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (
            (_demand getOrDefault ["state",""]) != "OPEN"
            || {!isNull ([_demandId] call ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup)}
        ) then {
            _owned = true;
        } else {
            [_demandId,"no-player-free"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
            [_demandId,"INVALID","no-player-free"] call ITW_CLASH_PlayerDemand_fnc_SetState;
            _squad setVariable [
                "ITW_CLASH_PlayerSquadEvacRetryAt",
                time + (missionNamespace getVariable ["ITW_CLASH_PlayerDemandDeclineCooldown",120])
            ];
            ["handed-to-ai",[_demandId,[_squad] call ITW_CLASH_fnc_GroupId]] call
                ITW_CLASH_PlayerSquadEvac_fnc_Log;
        };
    };
    if (_demandId isNotEqualTo "") exitWith {_owned};

    if (time < (_squad getVariable ["ITW_CLASH_PlayerSquadEvacRetryAt",0])) exitWith {false};
    if !(call ITW_CLASH_PlayerSquadEvac_fnc_PlayerAvailable) exitWith {false};
    ([_id,_entry] call ITW_CLASH_PlayerSquadEvac_fnc_RadioCheck) params ["_callable","_data"];
    if (!_callable) exitWith {false};
    private _lz = _data param [12,[]];
    if (_lz isEqualTo []) exitWith {false};
    private _newId = [_id,_entry,_lz] call ITW_CLASH_PlayerSquadEvac_fnc_Publish;
    if (_newId isEqualTo "") exitWith {false};
    [_newId,_lz,"radio"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldAtLz
};

/*
    The squad marks itself for the inbound carrier, on the landing zone it is
    holding, or where it stands once it is walking to a carrier already down.
*/
ITW_CLASH_PlayerSquadEvac_fnc_Smoke = {
    params ["_demandId","_vehicle","_squad"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    private _leader = leader _squad;
    if (isNull _vehicle || {isNull _leader}) exitWith {false};
    if !((_squad getVariable ["ITW_CLASH_CASEVAC_State",""]) in ["player-lz","player-pickup"]) exitWith {false};
    private _lz = _demand getOrDefault ["lz",[]];
    private _where = if (_lz isEqualTo []) then {"squad"} else {"lz"};
    if (_lz isEqualTo []) then {_lz = getPosATL _leader};
    if ((_vehicle distance2D _lz) > ITW_CLASH_CASEVAC_SmokeDistance) exitWith {false};
    private _last = _demand getOrDefault ["smokeAt",-1];
    if (_last >= 0 && {
        ITW_CLASH_PlayerSquadEvacSmokeRepop <= 0
        || {time - _last < ITW_CLASH_PlayerSquadEvacSmokeRepop}
    }) exitWith {false};

    private _smoke = createVehicle [ITW_CLASH_CASEVAC_SmokeClass,_lz,[],0,"CAN_COLLIDE"];
    if (!isNull _smoke) then {_smoke setPosATL _lz};
    _demand set ["smokeAt",time];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["smoke",[
        _demandId,[_squad] call ITW_CLASH_fnc_GroupId,_where,_lz,
        round (_vehicle distance2D _lz),_last >= 0
    ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
    true
};

ITW_CLASH_PlayerSquadEvac_fnc_Unload = {
    params ["_vehicle","_men"];
    {
        if (!isNull _x && {alive _x} && {vehicle _x == _vehicle}) then {
            unassignVehicle _x;
            moveOut _x;
        };
    } forEach _men;
};

/*
    RESERVED, every poll. In order: smoke for the carrier; contact closing on
    the landing zone moves the squad on, as CASEVAC aborts; a squad moving on
    calls again from the next safe spot; a carrier grounded nearby gathers the
    squad and loads it.
*/
ITW_CLASH_PlayerSquadEvac_fnc_Prepare = {
    params ["_demandId"];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if ((_demand getOrDefault ["state",""]) != "RESERVED") exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    private _squad = _demand getOrDefault ["targetGroup",grpNull];
    if (isNull _group || {isNull _squad}) exitWith {false};
    private _leader = leader _squad;
    if (isNull _leader) exitWith {false};
    private _taskId = _demand getOrDefault ["taskId",""];
    private _state = _squad getVariable ["ITW_CLASH_CASEVAC_State",""];
    private _lz = _demand getOrDefault ["lz",[]];

    private _vehicle = [_group] call ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
    [_demandId,_vehicle,_squad] call ITW_CLASH_PlayerSquadEvac_fnc_Smoke;

    // Holding the landing zone: CASEVAC's own contact abort, inbound or committed.
    if (_state isEqualTo "player-lz" && {_lz isNotEqualTo []}) then {
        private _committed = !isNull _vehicle
            && {(_vehicle distance2D _lz) <= ITW_CLASH_CASEVAC_CommitDistance};
        private _clearance = if (_committed) then {
            ITW_CLASH_CASEVAC_CommittedAbortClearance
        } else {
            ITW_CLASH_CASEVAC_InboundAbortClearance
        };
        private _contact = [_squad] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
        if (_contact < _clearance) then {
            ["contact-abort",[
                _demandId,[_squad] call ITW_CLASH_fnc_GroupId,round _contact,_clearance,
                if (_committed) then {"committed"} else {"inbound"}
            ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
            [_demandId,"contact-at-lz"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
        };
    };
    _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;

    // Moving on: call again once CASEVAC's checks pass from where they are.
    if !(_demand getOrDefault ["squadHeld",false]) exitWith {
        private _entry = [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_Entry;
        ([_demand get "withdrawalId",_entry] call ITW_CLASH_PlayerSquadEvac_fnc_RadioCheck) params ["_callable","_data"];
        private _newLz = if (_callable) then {_data param [12,[]]} else {[]};
        if (_newLz isNotEqualTo []) then {
            [_demandId,_newLz,"radio-again"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldAtLz;
        } else {
            if (_taskId isNotEqualTo "" && {time >= (_demand getOrDefault ["taskMovedAt",0])}) then {
                _demand set ["taskMovedAt",time + 10];
                ITW_CLASH_PlayerDemands set [_demandId,_demand];
                [_taskId,getPosATL _leader] call BIS_fnc_taskSetDestination;
            };
        };
        false
    };

    private _ready = !isNull _vehicle
        && {[_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity}
        && {[_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer}
        && {(_vehicle distance2D _leader) <= ITW_CLASH_PlayerSquadEvacGatherRadius};
    if (!_ready) exitWith {
        // The carrier lifted before they were aboard: back to the landing zone.
        if (_state isEqualTo "player-pickup") then {
            [units _squad,_demand getOrDefault ["boardingVehicle",objNull],_demand] call
                ITW_CLASH_PlayerDemand_fnc_CancelBoarding;
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
            _lz = _demand getOrDefault ["lzHeld",[]];
            if (_lz isNotEqualTo []) then {
                [_demandId,_lz,"carrier-left-back-to-lz"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldAtLz;
            } else {
                [_demandId,"carrier-left-before-loading"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
            };
        };
        false
    };

    if (_state isNotEqualTo "player-pickup") then {
        _demand set ["lzHeld",+_lz];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
        [_demandId,"player-pickup"] call ITW_CLASH_PlayerSquadEvac_fnc_HoldSquad;
        [_squad] call ITW_CLASH_fnc_ClearGroupWaypoints;
        _squad enableAttack false;
        _squad setCombatMode "BLUE";
        _squad setBehaviourStrong "AWARE";
        _squad setSpeedMode "FULL";
        ["pickup",[
            _demandId,[_squad] call ITW_CLASH_fnc_GroupId,typeOf _vehicle,
            round (_vehicle distance2D _leader),{alive _x} count units _squad
        ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
    };
    _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;

    private _survivors = units _squad select {alive _x};
    if (_survivors isEqualTo []) exitWith {false};
    private _outside = _survivors select {vehicle _x != _vehicle};
    if ((_vehicle emptyPositions "cargo") < count _outside) exitWith {
        if !(_demand getOrDefault ["seatsSaid",false]) then {
            _demand set ["seatsSaid",true];
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
            ["too-few-seats",[
                _demandId,typeOf _vehicle,_vehicle emptyPositions "cargo",count _outside
            ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
        };
        false
    };

    // v3 (Hark, 2026-10-27): they walk over and climb in, as for AI CASEVAC,
    // instead of being put in their seats once all were within 60m.
    _demand set ["boardingVehicle",_vehicle];
    private _aboard = [_survivors,_vehicle,_demand] call ITW_CLASH_PlayerDemand_fnc_BoardOnFoot;
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    if (!_aboard) exitWith {false};

    _squad setVariable ["ITW_CLASH_CASEVAC_State","player-rtb"];
    [_squad] call ITW_CLASH_PlayerSquadEvac_fnc_ClearPad;
    _demand set ["state","EXECUTING"];
    _demand set ["stateAt",time];
    _demand set ["executionVehicle",_vehicle];
    _demand set ["evacuees",+_survivors];
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    ["loaded",[
        _demandId,[_squad] call ITW_CLASH_fnc_GroupId,typeOf _vehicle,count _survivors
    ]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
    ["player-demand-executing",[_demandId,ITW_CLASH_PlayerSquadEvacKind]] call
        ITW_CLASH_PlayerDemand_fnc_Log;
    [_demandId] spawn ITW_CLASH_PlayerSquadEvac_fnc_RunDelivery;
    true
};

/*
    EXECUTING: fly them to the rally point. The withdrawal audit decides when
    they have arrived; this only follows it. The rally point is read from the
    live withdrawal entry each pass, so a moved corridor moves the task.
*/
ITW_CLASH_PlayerSquadEvac_fnc_RunDelivery = {
    params ["_demandId"];
    private _arrivedAt = -1;
    private _done = false;
    while {!_done} do {
        sleep 1;
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0 || {(_demand getOrDefault ["state",""]) != "EXECUTING"}) exitWith {};

        private _group = _demand getOrDefault ["reservedGroup",grpNull];
        private _vehicle = _demand getOrDefault ["executionVehicle",objNull];
        private _evacuees = +(_demand getOrDefault ["evacuees",[]]);
        private _taskId = _demand getOrDefault ["taskId",""];
        private _entry = [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_Entry;
        if (_entry isNotEqualTo [] && {(_entry#5) isNotEqualTo []}) then {
            _demand set ["rallyPoint",+(_entry#5)];
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
        };
        private _rally = _demand getOrDefault ["rallyPoint",[]];
        private _arrival = (missionNamespace getVariable ["ITW_CLASH_WithdrawalArrivalRadius",150])
            + ITW_CLASH_PlayerSquadEvacDeliverySlack;

        if (isNull _vehicle || {!alive _vehicle}) exitWith {
            [_demandId,"carrier-lost"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
            [_demandId,"squad-evac-carrier-lost",false] call ITW_CLASH_PlayerDemand_fnc_Release;
        };

        // The audit absorbed them (or they are all dead): which, is where the
        // carrier is.
        if (_entry isEqualTo []) exitWith {
            _demand set ["squadHeld",false];
            ITW_CLASH_PlayerDemands set [_demandId,_demand];
            if (_rally isNotEqualTo [] && {(_vehicle distance2D _rally) <= _arrival}) then {
                ["delivered",[_demandId,typeOf _vehicle,"absorbed"]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
                [_demandId,"squad-delivered-to-rally-point"] call ITW_CLASH_PlayerDemand_fnc_Complete;
            } else {
                [_demandId,"squad-evac-withdrawal-ended-in-flight",false] call ITW_CLASH_PlayerDemand_fnc_Release;
            };
        };

        if (_taskId isNotEqualTo "" && {_rally isNotEqualTo []}) then {
            [_taskId,_rally] call BIS_fnc_taskSetDestination;
        };
        private _grounded = [_vehicle] call ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer;

        if (!isNull _group && {_group getVariable ["ITW_CLASH_PlayerDemandCancel",false]}) then {
            if (_grounded) then {
                [_vehicle,_evacuees] call ITW_CLASH_PlayerSquadEvac_fnc_Unload;
                [_demandId,"player-canceled"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
                [_demandId,"player-canceled-squad-evac",true] call ITW_CLASH_PlayerDemand_fnc_Release;
                _done = true;
            };
        } else {
            if (_grounded && {_rally isNotEqualTo []} && {(_vehicle distance2D _rally) <= _arrival}) then {
                if (_arrivedAt < 0) then {_arrivedAt = time};
                if (time - _arrivedAt >= ITW_CLASH_PlayerSquadEvacDeliveryHold) then {
                    // At the rally point and not absorbed yet: let them walk the
                    // last metres. The audit takes them on foot.
                    [_vehicle,_evacuees] call ITW_CLASH_PlayerSquadEvac_fnc_Unload;
                    [_demandId,"delivered-on-foot"] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
                    ["delivered",[_demandId,typeOf _vehicle,"unloaded"]] call ITW_CLASH_PlayerSquadEvac_fnc_Log;
                    [_demandId,"squad-delivered-to-rally-point"] call ITW_CLASH_PlayerDemand_fnc_Complete;
                    _done = true;
                };
            } else {
                _arrivedAt = -1;
            };
        };
    };
    true
};

/*
    Every withdrawal of ours, every poll. The AI managers ask the same question
    through their own gates, but only while they have a free slot; this asks it
    regardless, so a call never waits on AI capacity.
*/
ITW_CLASH_PlayerSquadEvac_fnc_Tick = {
    if (!ITW_CLASH_PlayerSquadEvacEnabled || {isNil "ITW_CLASH_Withdrawals"}) exitWith {false};
    {
        [_x,ITW_CLASH_Withdrawals getOrDefault [_x,[]]] call ITW_CLASH_PlayerSquadEvac_fnc_Radio;
    } forEach +(keys ITW_CLASH_Withdrawals);
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerSquadEvac";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.5;
        diag_tickTime >= _deadline
        || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Publish"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_FindBySourceKey"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_SetState"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_StillValid"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_UpdateReserved"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Release"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Complete"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_IsGroundedForTransfer"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_CanAcceptJob"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle"}
            && {!isNil "ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity"}
            && {!isNil "ITW_CLASH_fnc_OrderWithdrawal"}
            && {!isNil "ITW_CLASH_fnc_ClearGroupWaypoints"}
            && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_Eligible"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_OrderLZ"}
            && {!isNil "ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance"}
            && {!isNil "ITW_CLASH_CASEVAC_SmokeDistance"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | WARNING | squad-evac-prerequisites-missing | withdrawing squads stay with AI CASEVAC";
    };
    /*
        Bind outside the dispatcher's own hardening layers. The execution layer
        replaces UpdateReserved outright rather than wrapping it, so a wrapper
        bound before it would be lost. Ground MEDEVAC wraps CASEVAC's gate and
        defines its own; wait for both, briefly, then bind to what exists.
    */
    private _layers = diag_tickTime + 60;
    waitUntil {
        sleep 0.5;
        diag_tickTime >= _layers || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningReady",false]
            && {!isNil "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase"}
        }
    };

    // The radio check is CASEVAC's own air eligibility, under ground MEDEVAC's
    // arbitration: a squad a road vehicle could reach is still the player's.
    ITW_CLASH_PlayerSquadEvac_fnc_RadioCheck = if (isNil "ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase") then {
        ITW_CLASH_CASEVAC_fnc_Eligible
    } else {
        ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase
    };

    // Players first at the AI's own gates: a squad a player holds, or one that
    // is calling now with a player free, is not the AI's.
    ITW_CLASH_PlayerSquadEvac_fnc_CasevacEligibleBase = ITW_CLASH_CASEVAC_fnc_Eligible;
    ITW_CLASH_CASEVAC_fnc_Eligible = {
        params ["_id","_entry"];
        if ([_entry] call ITW_CLASH_PlayerSquadEvac_fnc_PlayerHolds) exitWith {[false,[]]};
        if ([_id,_entry] call ITW_CLASH_PlayerSquadEvac_fnc_Radio) exitWith {[false,[]]};
        _this call ITW_CLASH_PlayerSquadEvac_fnc_CasevacEligibleBase
    };
    private _groundBound = !isNil "ITW_CLASH_GroundMEDEVAC_fnc_Eligible";
    if (_groundBound) then {
        ITW_CLASH_PlayerSquadEvac_fnc_GroundEligibleBase = ITW_CLASH_GroundMEDEVAC_fnc_Eligible;
        ITW_CLASH_GroundMEDEVAC_fnc_Eligible = {
            params ["_id","_entry"];
            if ([_entry] call ITW_CLASH_PlayerSquadEvac_fnc_PlayerHolds) exitWith {[false,[]]};
            if ([_id,_entry] call ITW_CLASH_PlayerSquadEvac_fnc_Radio) exitWith {[false,[]]};
            _this call ITW_CLASH_PlayerSquadEvac_fnc_GroundEligibleBase
        };
    };

    // The reservation layer marks the squad the moment a player takes it, so
    // there is no poll's gap in which an AI asset could claim it too.
    private _markerBound = !isNil "ITW_CLASH_PlayerDemandReservation_fnc_MarkerName";
    if (_markerBound) then {
        ITW_CLASH_PlayerSquadEvac_fnc_MarkerNameBase = ITW_CLASH_PlayerDemandReservation_fnc_MarkerName;
        ITW_CLASH_PlayerDemandReservation_fnc_MarkerName = {
            params ["_kind"];
            if (_kind isEqualTo ITW_CLASH_PlayerSquadEvacKind) exitWith {ITW_CLASH_PlayerSquadEvacMarker};
            _this call ITW_CLASH_PlayerSquadEvac_fnc_MarkerNameBase
        };
    };

    // Every other kind goes straight back to what was there before.
    ITW_CLASH_PlayerSquadEvac_fnc_StillValidBase = ITW_CLASH_PlayerDemand_fnc_StillValid;
    ITW_CLASH_PlayerDemand_fnc_StillValid = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        if ((_demand getOrDefault ["kind",""]) isNotEqualTo ITW_CLASH_PlayerSquadEvacKind) exitWith {
            _this call ITW_CLASH_PlayerSquadEvac_fnc_StillValidBase
        };
        private _state = _demand getOrDefault ["state",""];
        if (_state in ["COMPLETED","INVALID","FAILED"]) exitWith {false};
        private _squad = _demand getOrDefault ["targetGroup",grpNull];
        if (isNull _squad || {({alive _x} count units _squad) == 0}) exitWith {false};
        private _entry = [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_Entry;
        if (_entry isEqualTo [] || {(_entry#0) isNotEqualTo _squad}) exitWith {false};
        if !(_squad getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {false};
        if ((_squad getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {false};
        private _casevac = _squad getVariable ["ITW_CLASH_CASEVAC_State",""];
        // Any AI evac state is the AI's squad; ours, or none, is still the call.
        if (_state == "OPEN") exitWith {
            _casevac in ["","player-lz"]
            && {((units _squad) findIf {alive _x && {vehicle _x != _x}}) < 0}
        };
        _casevac isEqualTo "" || {_casevac in ITW_CLASH_PlayerSquadEvacStates}
    };

    ITW_CLASH_PlayerSquadEvac_fnc_UpdateReservedBase = ITW_CLASH_PlayerDemand_fnc_UpdateReserved;
    ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {};
        if ((_demand getOrDefault ["kind",""]) isNotEqualTo ITW_CLASH_PlayerSquadEvacKind) exitWith {
            _this call ITW_CLASH_PlayerSquadEvac_fnc_UpdateReservedBase
        };
        // Validity, liveness, subscription and owner loss are the dispatcher's.
        _this call ITW_CLASH_PlayerSquadEvac_fnc_UpdateReservedBase;
        _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        private _state = _demand getOrDefault ["state",""];
        if !(_state in ["RESERVED","EXECUTING"]) exitWith {};
        private _squad = _demand getOrDefault ["targetGroup",grpNull];
        if (!isNull _squad) then {_squad setVariable [ITW_CLASH_PlayerSquadEvacMarker,_demandId]};
        if (_state == "RESERVED") then {[_demandId] call ITW_CLASH_PlayerSquadEvac_fnc_Prepare};
    };

    ITW_CLASH_PlayerSquadEvac_fnc_ClearMarker = {
        params ["_demand"];
        private _squad = _demand getOrDefault ["targetGroup",grpNull];
        if (!isNull _squad && {(_squad getVariable [ITW_CLASH_PlayerSquadEvacMarker,""]) == (_demand getOrDefault ["id",""])}) then {
            _squad setVariable [ITW_CLASH_PlayerSquadEvacMarker,nil];
        };
    };

    ITW_CLASH_PlayerSquadEvac_fnc_ReleaseBase = ITW_CLASH_PlayerDemand_fnc_Release;
    ITW_CLASH_PlayerDemand_fnc_Release = {
        params ["_demandId",["_reason","released"]];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if ((_demand getOrDefault ["kind",""]) isEqualTo ITW_CLASH_PlayerSquadEvacKind) then {
            [_demandId,_reason] call ITW_CLASH_PlayerSquadEvac_fnc_ReturnSquad;
            [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_ClearMarker;
        };
        _this call ITW_CLASH_PlayerSquadEvac_fnc_ReleaseBase
    };

    ITW_CLASH_PlayerSquadEvac_fnc_CompleteBase = ITW_CLASH_PlayerDemand_fnc_Complete;
    ITW_CLASH_PlayerDemand_fnc_Complete = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if ((_demand getOrDefault ["kind",""]) isEqualTo ITW_CLASH_PlayerSquadEvacKind) then {
            [_demand] call ITW_CLASH_PlayerSquadEvac_fnc_ClearMarker;
        };
        _this call ITW_CLASH_PlayerSquadEvac_fnc_CompleteBase
    };

    ITW_CLASH_PlayerSquadEvacReady = true;
    diag_log format [
        "CLASH BOOT | squad-evac-ready | version=%1 enabled=%2 channel=%3 kind=%4 gather=%5 boardOnFoot=true boardTimeout=%6 radioCheck=casevac-eligibility holdsAtLz=true contactAbort=%7/%8 commitAt=%9 groundGateBound=%10 hardeningLayers=%11 markerAtReserve=%12 smokeAt=%13m smokeRepop=%14s playerSideOnly=true",
        ITW_CLASH_PlayerSquadEvacVersion,
        ITW_CLASH_PlayerSquadEvacEnabled,
        ITW_CLASH_PlayerSquadEvacChannel,
        ITW_CLASH_PlayerSquadEvacKind,
        ITW_CLASH_PlayerSquadEvacGatherRadius,
        ITW_CLASH_PlayerBoardTimeout,
        ITW_CLASH_CASEVAC_InboundAbortClearance,
        ITW_CLASH_CASEVAC_CommittedAbortClearance,
        ITW_CLASH_CASEVAC_CommitDistance,
        _groundBound,
        missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningReady",false],
        _markerBound,
        ITW_CLASH_CASEVAC_SmokeDistance,
        ITW_CLASH_PlayerSquadEvacSmokeRepop
    ];

    while {!(missionNamespace getVariable ["ITW_GameOver",false])} do {
        sleep ITW_CLASH_PlayerSquadEvacPoll;
        call ITW_CLASH_PlayerSquadEvac_fnc_Tick;
    };
};

true
