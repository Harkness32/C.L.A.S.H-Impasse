#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerDemandReservationHardeningStarted",false]) exitWith {true};

ITW_CLASH_PlayerDemandReservationHardeningStarted = true;
ITW_CLASH_PlayerDemandReservationHardeningReady = false;
ITW_CLASH_PlayerDemandReservationHardeningVersion = 1;

ITW_CLASH_PlayerDemandLivenessWindow = missionNamespace getVariable [
    "ITW_CLASH_PlayerDemandLivenessWindow",600
];
ITW_CLASH_PlayerDemandProgressDistance = missionNamespace getVariable [
    "ITW_CLASH_PlayerDemandProgressDistance",50
];
ITW_CLASH_PlayerDemandDeclineCooldown = missionNamespace getVariable [
    "ITW_CLASH_PlayerDemandDeclineCooldown",120
];
ITW_CLASH_PlayerDemandBounceLimit = missionNamespace getVariable [
    "ITW_CLASH_PlayerDemandBounceLimit",3
];
ITW_CLASH_PlayerDemandAIFallbackWindow = missionNamespace getVariable [
    "ITW_CLASH_PlayerDemandAIFallbackWindow",120
];

ITW_CLASH_PlayerDemandReservation_fnc_GroupKey = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    str _group
};

ITW_CLASH_PlayerDemandReservation_fnc_MarkerName = {
    params ["_kind"];
    switch (_kind) do {
        case "LOGISTICS_AMMO": {"ITW_CLASH_PlayerAmmoDemandReservation"};
        case "MEDEVAC_SEVERE": {"ITW_CLASH_PlayerMedevacDemandReservation"};
        default {""};
    }
};

ITW_CLASH_PlayerDemandReservation_fnc_IsCapable = {
    params ["_demand","_group"];
    if (isNull _group) exitWith {false};
    switch (_demand getOrDefault ["kind",""]) do {
        case "LOGISTICS_AMMO": {
            !isNull ([_group] call ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle)
        };
        case "MEDEVAC_SEVERE": {
            private _vehicle = [_group] call
                ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
            !isNull _vehicle && {
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity
            }
        };
        case "TRANSPORT": {
            private _vehicle = [_group] call
                ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
            !isNull _vehicle && {
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity
            }
        };
        case "ARTILLERY": {
            private _vehicle = [_group] call
                ITW_CLASH_PlayerTasks_fnc_GetEmploymentVehicle;
            !isNull _vehicle && {
                [_vehicle] call ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability
            }
        };
        default {true};
    }
};

ITW_CLASH_PlayerDemandReservation_fnc_ProgressSample = {
    params ["_demand","_group"];
    if (isNull _group) exitWith {[[],"<none>",false]};
    private _leader = leader _group;
    if (isNull _leader) exitWith {[[],"<none>",false]};
    private _vehicle = vehicle _leader;
    private _vehicleSig = if (_vehicle == _leader) then {"<foot>"} else {
        format ["%1|%2",typeOf _vehicle,str _vehicle]
    };
    [
        getPosATL _leader,
        _vehicleSig,
        [_demand,_group] call ITW_CLASH_PlayerDemandReservation_fnc_IsCapable
    ]
};

ITW_CLASH_PlayerDemandReservation_fnc_RecordProgress = {
    params ["_demandId",["_force",false],["_reason","sample"]];
    private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
    if (count _demand == 0) exitWith {false};
    private _group = _demand getOrDefault ["reservedGroup",grpNull];
    if (isNull _group) exitWith {false};

    private _sample = [_demand,_group] call
        ITW_CLASH_PlayerDemandReservation_fnc_ProgressSample;
    _sample params ["_pos","_vehicleSig","_capable"];
    if (_pos isEqualTo []) exitWith {false};

    private _previousPos = +(_demand getOrDefault ["progressPos",[]]);
    private _previousVehicle = _demand getOrDefault ["progressVehicle","<none>"];
    private _previousCapable = _demand getOrDefault ["progressCapable",false];
    private _moved = _previousPos isNotEqualTo [] && {
        _previousPos distance2D _pos >= ITW_CLASH_PlayerDemandProgressDistance
    };
    private _vehicleChanged = _previousVehicle isNotEqualTo _vehicleSig;
    private _capabilityChanged = _previousCapable isNotEqualTo _capable;
    private _progressed = _force || {_previousPos isEqualTo []} || {_moved} || {
        _vehicleChanged || {_capabilityChanged}
    };

    _demand set ["progressPos",+_pos];
    _demand set ["progressVehicle",_vehicleSig];
    _demand set ["progressCapable",_capable];
    if (_progressed) then {
        _demand set ["lastProgressAt",time];
        _demand set ["lastProgressReason",_reason];
        ["player-demand-progress",[
            _demandId,
            [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
            _reason,_vehicleSig,_capable,+_pos
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
    };
    ITW_CLASH_PlayerDemands set [_demandId,_demand];
    _progressed
};

[] spawn {
    scriptName "ITW_CLASH_PlayerDemandReservationHardeningBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerDemandDispatchReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_PlayerDemandExecutionHardeningReady",false]}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Reserve"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_Release"}
            && {!isNil "ITW_CLASH_PlayerDemand_fnc_UpdateReserved"}
            && {!isNil "HAL_SuppAmmo"}
            && {!isNil "HAL_SuppMed"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        diag_log "CLASH BOOT | player-demand-reservation-hardening-bind-timeout | demand layer remains fail-open";
    };

    // Demand ownership lives on C.L.A.S.H.-owned group markers, not the native
    // ASupportedG / SupportedG arrays that HQSitRepB periodically rewrites.
    ITW_CLASH_PlayerDemand_fnc_ApplySuppression = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
        if (isNull _targetGroup) exitWith {false};
        private _kind = _demand getOrDefault ["kind",""];
        private _marker = [_kind] call
            ITW_CLASH_PlayerDemandReservation_fnc_MarkerName;
        if (_marker isEqualTo "") exitWith {true};

        private _current = _targetGroup getVariable [_marker,""];
        if (_current isNotEqualTo "" && {_current isNotEqualTo _demandId}) exitWith {
            ["player-demand-suppression-conflict",[
                _demandId,_kind,
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                _marker,_current
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            false
        };

        _targetGroup setVariable [_marker,_demandId];
        _demand set ["suppressionMarker",_marker];
        _demand set ["suppressionArray",""];
        _demand set ["suppressionOwned",true];
        _demand set ["suppressionAssertedAt",time];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
        ["player-demand-suppression-asserted",[
            _demandId,_kind,_marker,
            [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        true
    };

    ITW_CLASH_PlayerDemand_fnc_RestoreSuppression = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
        private _marker = _demand getOrDefault ["suppressionMarker",""];
        private _owned = _demand getOrDefault ["suppressionOwned",false];
        if (_owned && {_marker isNotEqualTo ""} && {!isNull _targetGroup}) then {
            if ((_targetGroup getVariable [_marker,""]) == _demandId) then {
                _targetGroup setVariable [_marker,nil];
            };
        };
        if (_marker isNotEqualTo "") then {
            ["player-demand-native-restored",[
                _demandId,_marker,
                if (isNull _targetGroup) then {"<null>"} else {
                    [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
                },_owned
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };
        _demand set ["suppressionMarker",""];
        _demand set ["suppressionArray",""];
        _demand set ["suppressionOwned",false];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
        true
    };

    ITW_CLASH_PlayerDemandReservation_fnc_EnsureSuppression = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {false};
        private _kind = _demand getOrDefault ["kind",""];
        private _marker = [_kind] call
            ITW_CLASH_PlayerDemandReservation_fnc_MarkerName;
        if (_marker isEqualTo "") exitWith {true};
        private _targetGroup = _demand getOrDefault ["targetGroup",grpNull];
        if (isNull _targetGroup) exitWith {false};
        private _current = _targetGroup getVariable [_marker,""];
        if (_current == _demandId) exitWith {true};
        if (_current isNotEqualTo "") exitWith {false};
        private _ok = [_demandId] call ITW_CLASH_PlayerDemand_fnc_ApplySuppression;
        if (_ok) then {
            ["player-demand-suppression-repaired",[
                _demandId,_kind,_marker,
                [_targetGroup] call ITW_CLASH_PlayerDemand_fnc_GroupId
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        };
        _ok
    };

    ITW_CLASH_PlayerDemandReservation_fnc_ReserveBase =
        ITW_CLASH_PlayerDemand_fnc_Reserve;
    ITW_CLASH_PlayerDemand_fnc_Reserve = {
        params ["_demandId","_group"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0 || {isNull _group}) exitWith {false};
        if (time < (_demand getOrDefault ["playerOfferSuppressedUntil",0])) exitWith {false};

        private _cooldowns = _demand getOrDefault ["declineCooldowns",createHashMap];
        if !(_cooldowns isEqualType createHashMap) then {_cooldowns = createHashMap};
        private _groupKey = [_group] call ITW_CLASH_PlayerDemandReservation_fnc_GroupKey;
        if (time < (_cooldowns getOrDefault [_groupKey,0])) exitWith {
            ["player-demand-decline-cooldown",[
                _demandId,
                [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                _cooldowns getOrDefault [_groupKey,0]
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            false
        };

        private _ok = _this call ITW_CLASH_PlayerDemandReservation_fnc_ReserveBase;
        if (!_ok) exitWith {false};
        _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        _demand set ["declineCooldowns",_cooldowns];
        _demand set ["lastProgressAt",time];
        _demand set ["progressPos",[]];
        _demand set ["progressVehicle","<none>"];
        _demand set ["progressCapable",false];
        ITW_CLASH_PlayerDemands set [_demandId,_demand];
        [_demandId,true,"reservation-created"] call
            ITW_CLASH_PlayerDemandReservation_fnc_RecordProgress;
        true
    };

    ITW_CLASH_PlayerDemandReservation_fnc_FindDispatchGroupBase =
        ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup;
    ITW_CLASH_PlayerDemand_fnc_FindDispatchGroup = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {grpNull};
        if (time < (_demand getOrDefault ["playerOfferSuppressedUntil",0])) exitWith {grpNull};
        private _channel = _demand getOrDefault ["channel",""];
        private _cooldowns = _demand getOrDefault ["declineCooldowns",createHashMap];
        if !(_cooldowns isEqualType createHashMap) then {_cooldowns = createHashMap};
        private _found = grpNull;
        {
            if (isNull _x) then {continue};
            private _groupKey = [_x] call ITW_CLASH_PlayerDemandReservation_fnc_GroupKey;
            if (time < (_cooldowns getOrDefault [_groupKey,0])) then {continue};
            if ([_x,_channel] call ITW_CLASH_PlayerTasks_fnc_CanAcceptJob) exitWith {
                _found = _x;
            };
        } forEach +ITW_CLASH_PlayerTaskGroups;
        _found
    };

    ITW_CLASH_PlayerDemandReservation_fnc_ReleaseBase =
        ITW_CLASH_PlayerDemand_fnc_Release;
    ITW_CLASH_PlayerDemand_fnc_Release = {
        params ["_demandId",["_reason","released"],["_declined",false]];
        private _before = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _before == 0) exitWith {false};
        private _group = _before getOrDefault ["reservedGroup",grpNull];
        private _beforeState = _before getOrDefault ["state",""];

        if (_declined && {!isNull _group}) then {
            private _cooldowns = _before getOrDefault ["declineCooldowns",createHashMap];
            if !(_cooldowns isEqualType createHashMap) then {_cooldowns = createHashMap};
            private _groupKey = [_group] call ITW_CLASH_PlayerDemandReservation_fnc_GroupKey;
            _cooldowns set [_groupKey,time + ITW_CLASH_PlayerDemandDeclineCooldown];
            _before set ["declineCooldowns",_cooldowns];
            ITW_CLASH_PlayerDemands set [_demandId,_before];
        };

        // The legacy declinedGroups list was permanent. Hardening owns re-entry
        // with timed per-demand cooldowns instead, so never feed the permanent
        // decline flag into the old release implementation.
        private _ok = [_demandId,_reason,false] call
            ITW_CLASH_PlayerDemandReservation_fnc_ReleaseBase;
        if (!_ok) exitWith {false};

        private _after = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if ((_after getOrDefault ["state",""]) == "OPEN" && {
            _beforeState in ["RESERVED","EXECUTING"]
        }) then {
            private _bounce = (_after getOrDefault ["bounceCount",0]) + 1;
            private _total = (_after getOrDefault ["bounceTotal",0]) + 1;
            _after set ["bounceCount",_bounce];
            _after set ["bounceTotal",_total];
            ["player-demand-bounced",[
                _demandId,_reason,_bounce,_total,
                if (isNull _group) then {"<null>"} else {
                    [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId
                }
            ]] call ITW_CLASH_PlayerDemand_fnc_Log;

            if (_bounce >= ITW_CLASH_PlayerDemandBounceLimit) then {
                private _until = time + ITW_CLASH_PlayerDemandAIFallbackWindow;
                _after set ["playerOfferSuppressedUntil",_until];
                _after set ["bounceCount",0];
                ["player-demand-ai-fallback-window",[
                    _demandId,_until,ITW_CLASH_PlayerDemandAIFallbackWindow,_total
                ]] call ITW_CLASH_PlayerDemand_fnc_Log;
            };
            ITW_CLASH_PlayerDemands set [_demandId,_after];
        };
        true
    };

    ITW_CLASH_PlayerDemandReservation_fnc_UpdateReservedBase =
        ITW_CLASH_PlayerDemand_fnc_UpdateReserved;
    ITW_CLASH_PlayerDemand_fnc_UpdateReserved = {
        params ["_demandId"];
        private _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
        if (count _demand == 0) exitWith {};
        private _state = _demand getOrDefault ["state",""];
        if !(_state in ["RESERVED","EXECUTING"]) exitWith {};
        private _group = _demand getOrDefault ["reservedGroup",grpNull];
        private _channel = _demand getOrDefault ["channel",""];

        if !([_demandId] call ITW_CLASH_PlayerDemandReservation_fnc_EnsureSuppression) exitWith {
            [_demandId,"suppression-marker-conflict",false] call
                ITW_CLASH_PlayerDemand_fnc_Release;
        };

        if (_state == "RESERVED") then {
            if !([_group] call ITW_CLASH_PlayerDemand_fnc_HumanGroupAlive) exitWith {
                [_demandId,"player-group-unavailable",false] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
            if !([_group,_channel] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed) exitWith {
                [_demandId,"player-unsubscribed-channel",true] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
            if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {
                [_demandId,"player-authority-hold",false] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };

            [_demandId,false,"preparation-progress"] call
                ITW_CLASH_PlayerDemandReservation_fnc_RecordProgress;
            _demand = [_demandId] call ITW_CLASH_PlayerDemand_fnc_Get;
            private _lastProgress = _demand getOrDefault ["lastProgressAt",time];
            if (time - _lastProgress >= ITW_CLASH_PlayerDemandLivenessWindow) exitWith {
                ["player-demand-liveness-expired",[
                    _demandId,
                    [_group] call ITW_CLASH_PlayerDemand_fnc_GroupId,
                    time - _lastProgress,
                    _demand getOrDefault ["progressVehicle","<none>"],
                    _demand getOrDefault ["progressCapable",false]
                ]] call ITW_CLASH_PlayerDemand_fnc_Log;
                [_demandId,"preparation-liveness-expired",true] call
                    ITW_CLASH_PlayerDemand_fnc_Release;
            };
        } else {
            // Once physical execution starts, the specialist remains terminal
            // authority. Unsubscribing requests a safe specialist cancel; it
            // does not delete the demand out from underneath the executor.
            if (!isNull _group && {
                !([_group,_channel] call ITW_CLASH_PlayerTasks_fnc_IsSubscribed)
            }) then {
                _group setVariable ["ITW_CLASH_PlayerDemandCancel",true,true];
                if ((_demand getOrDefault ["kind",""]) == "LOGISTICS_AMMO") then {
                    _group setVariable ["ITW_CLASH_PlayerAmmoJobCancel",true,true];
                };
            };
        };

        [_demandId] call ITW_CLASH_PlayerDemandReservation_fnc_UpdateReservedBase;
    };

    ITW_CLASH_PlayerDemandReservation_fnc_ReservedGroupsForHQ = {
        params ["_hq","_kind"];
        private _groups = [];
        {
            private _demand = [_x] call ITW_CLASH_PlayerDemand_fnc_Get;
            if (count _demand == 0) then {continue};
            if ((_demand getOrDefault ["kind",""]) != _kind) then {continue};
            if ((_demand getOrDefault ["hq",grpNull]) != _hq) then {continue};
            if !((_demand getOrDefault ["state",""]) in ["RESERVED","EXECUTING"]) then {continue};
            private _group = _demand getOrDefault ["targetGroup",grpNull];
            if (isNull _group) then {continue};
            private _marker = [_kind] call
                ITW_CLASH_PlayerDemandReservation_fnc_MarkerName;
            if ((_group getVariable [_marker,""]) != (_demand getOrDefault ["id",""])) then {continue};
            _groups pushBackUnique _group;
        } forEach (keys ITW_CLASH_PlayerDemands);
        _groups
    };

    // Suppression is scoped to the native support scan. The long-lived ledger
    // marker is authoritative; HAL's Ex* array is only an input snapshot for
    // this synchronous call and is restored exactly afterward.
    ITW_CLASH_PlayerDemandReservation_fnc_SuppAmmoBase = HAL_SuppAmmo;
    HAL_SuppAmmo = {
        private _hq = _this param [0,grpNull];
        if (isNull _hq) exitWith {
            _this call ITW_CLASH_PlayerDemandReservation_fnc_SuppAmmoBase
        };
        private _reserved = [_hq,"LOGISTICS_AMMO"] call
            ITW_CLASH_PlayerDemandReservation_fnc_ReservedGroupsForHQ;
        if (_reserved isEqualTo []) exitWith {
            _this call ITW_CLASH_PlayerDemandReservation_fnc_SuppAmmoBase
        };

        private _before = +(_hq getVariable ["RydHQ_ExReAmmo",[]]);
        private _scoped = +_before;
        {_scoped pushBackUnique _x} forEach _reserved;
        _hq setVariable ["RydHQ_ExReAmmo",_scoped];
        ["player-demand-native-scan-excluded",[
            "LOGISTICS_AMMO",
            _hq getVariable ["RydHQ_CodeSign","?"],
            _reserved apply {[_x] call ITW_CLASH_PlayerDemand_fnc_GroupId}
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        private _result = _this call
            ITW_CLASH_PlayerDemandReservation_fnc_SuppAmmoBase;
        _hq setVariable ["RydHQ_ExReAmmo",_before];
        ["player-demand-native-scan-restored",[
            "LOGISTICS_AMMO",_hq getVariable ["RydHQ_CodeSign","?"],count _before
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        _result
    };

    ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase = HAL_SuppMed;
    HAL_SuppMed = {
        private _hq = _this param [0,grpNull];
        if (isNull _hq) exitWith {
            _this call ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase
        };
        private _reserved = [_hq,"MEDEVAC_SEVERE"] call
            ITW_CLASH_PlayerDemandReservation_fnc_ReservedGroupsForHQ;
        if (_reserved isEqualTo []) exitWith {
            _this call ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase
        };

        private _before = +(_hq getVariable ["RydHQ_ExMedic",[]]);
        private _scoped = +_before;
        {_scoped pushBackUnique _x} forEach _reserved;
        _hq setVariable ["RydHQ_ExMedic",_scoped];
        ["player-demand-native-scan-excluded",[
            "MEDEVAC_SEVERE",
            _hq getVariable ["RydHQ_CodeSign","?"],
            _reserved apply {[_x] call ITW_CLASH_PlayerDemand_fnc_GroupId}
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        private _result = _this call
            ITW_CLASH_PlayerDemandReservation_fnc_SuppMedBase;
        _hq setVariable ["RydHQ_ExMedic",_before];
        ["player-demand-native-scan-restored",[
            "MEDEVAC_SEVERE",_hq getVariable ["RydHQ_CodeSign","?"],count _before
        ]] call ITW_CLASH_PlayerDemand_fnc_Log;
        _result
    };

    ITW_CLASH_PlayerDemandReservationHardeningReady = true;
    diag_log format [
        "CLASH BOOT | player-demand-reservation-hardening-ready | version=%1 markers=true continuousAssert=%2 liveness=%3 declineCooldown=%4 bounceLimit=%5 aiFallback=%6 ammoExclusion=call-scoped medExclusion=call-scoped sitrepArraysNotAuthority=true",
        ITW_CLASH_PlayerDemandReservationHardeningVersion,
        ITW_CLASH_PlayerDemandPoll,
        ITW_CLASH_PlayerDemandLivenessWindow,
        ITW_CLASH_PlayerDemandDeclineCooldown,
        ITW_CLASH_PlayerDemandBounceLimit,
        ITW_CLASH_PlayerDemandAIFallbackWindow
    ];
};

true