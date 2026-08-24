#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTransportAuthorityStarted",false]) exitWith {true};

ITW_CLASH_PlayerTransportAuthorityStarted = true;
ITW_CLASH_PlayerTransportAuthorityVersion = 4;
ITW_CLASH_PlayerTransportAuthorityReady = false;
ITW_CLASH_PlayerTransportContractSerial = 0;
ITW_CLASH_PlayerTransportContractLifetime = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportContractLifetime",360
];
ITW_CLASH_PlayerTransportDropRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportDropRadius",800
];

ITW_CLASH_PlayerTransport_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["player-transport-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TRANSPORT | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTransport_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
    };
    str _group
};

ITW_CLASH_PlayerTransport_fnc_GetContract = {
    params ["_group"];
    if (isNull _group) exitWith {createHashMap};
    private _contract = _group getVariable [
        "ITW_CLASH_PlayerTransportContract",createHashMap
    ];
    if !(_contract isEqualType createHashMap) exitWith {createHashMap};
    if ((_contract getOrDefault ["expiresAt",0]) < time) exitWith {
        _group setVariable ["ITW_CLASH_PlayerTransportContract",nil];
        createHashMap
    };
    _contract
};

ITW_CLASH_PlayerTransport_fnc_GetContractDestination = {
    params ["_group",["_vehicle",objNull]];
    private _contract = [_group] call ITW_CLASH_PlayerTransport_fnc_GetContract;
    if (count _contract == 0) exitWith {[]};
    private _carrier = _contract getOrDefault ["carrier",objNull];
    if (!isNull _vehicle && {!isNull _carrier} && {_carrier != _vehicle}) exitWith {[]};
    +(_contract getOrDefault ["destination",[]])
};

// V4's native bridge replaces this function synchronously before HAL can call
// SCargo. Keep this definition as a fail-open recorder if that bridge fails to
// load; it does not select or command a carrier.
ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand = {
    params ["_group","_hq","_destination",["_mode","AUTO"]];
    if (isNull _group || {isNull _hq} || {_destination isEqualTo []}) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};
    if (_group getVariable ["itwDelivery",false]) exitWith {false};

    ITW_CLASH_PlayerTransportContractSerial = ITW_CLASH_PlayerTransportContractSerial + 1;
    private _id = format [
        "HAL-TRANSPORT-%1-%2",
        round (diag_tickTime * 1000),ITW_CLASH_PlayerTransportContractSerial
    ];
    private _contract = createHashMapFromArray [
        ["id",_id],
        ["cargo",_group],
        ["hq",_hq],
        ["destination",+_destination],
        ["mode",toUpperANSI _mode],
        ["state","HAL_DEMAND"],
        ["createdAt",time],
        ["expiresAt",time + ITW_CLASH_PlayerTransportContractLifetime],
        ["carrier",objNull],
        ["source","HAL_SCargo"]
    ];
    _group setVariable ["ITW_CLASH_PlayerTransportContract",_contract];
    ["hal-demand-observed",[
        _id,[_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
        _hq getVariable ["RydHQ_CodeSign","?"],toUpperANSI _mode,+_destination
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    true
};

ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (isNull _hq) exitWith {false};

    private _owned = [];
    {
        private _name = _x;
        private _members = +(_hq getVariable [_name,[]]);
        if !(_group in _members) then {
            _members pushBackUnique _group;
            _hq setVariable [_name,_members];
            _owned pushBack _name;
        };
    } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
    _group setVariable ["ITW_CLASH_TransportRetaskOwned",_owned];
    _group setVariable ["ITW_CLASH_TransportRetaskLock",true];
    true
};

ITW_CLASH_PlayerTransport_fnc_ClearRetaskLock = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    private _owned = +(_group getVariable ["ITW_CLASH_TransportRetaskOwned",[]]);
    if (!isNull _hq) then {
        {
            private _members = +(_hq getVariable [_x,[]]);
            _hq setVariable [_x,_members - [_group]];
        } forEach _owned;
    };
    _group setVariable ["ITW_CLASH_TransportRetaskOwned",nil];
    _group setVariable ["ITW_CLASH_TransportRetaskLock",nil];
    true
};

// This authority path is retained only for standing native Impasse delivery
// squads. HAL SCargo cargo never enters it after the v2 native bridge is loaded.
ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL = {
    params ["_group",["_reason","itw-transport-lease"]];
    if (isNull _group) exitWith {false};

    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        ITW_CLASH_DualHALBLUFORGroups = ITW_CLASH_DualHALBLUFORGroups - [_group];
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        ITW_CLASH_DualHALOPFORExtraGroups = ITW_CLASH_DualHALOPFORExtraGroups - [_group];
    };

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (!isNull _hq) then {
        private _included = +(_hq getVariable ["RydHQ_Included",[]]);
        _included = _included - [_group];
        _hq setVariable ["RydHQ_Included",_included];
        if (!isNil "ITW_CLASH_BLUFORHQ" && {_hq == ITW_CLASH_BLUFORHQ}) then {RydHQB_Included = +_included};
        if (!isNil "ITW_CLASH_HALHQ" && {_hq == ITW_CLASH_HALHQ}) then {RydHQ_Included = +_included};
    };

    _group setVariable ["Break",true];
    _group setVariable ["ITW_CLASH_AuthorityHold",true];
    _group setVariable ["ITW_CLASH_TransportAuthorityLease",true];
    _group setVariable ["ITW_CLASH_Authority","ITW_TRANSPORT"];
    _group setVariable ["ITW_CLASH_AuthorityReason",_reason];
    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {call ITW_CLASH_DualHAL_fnc_SyncIncluded};
    true
};

ITW_CLASH_PlayerTransport_fnc_Acquire = {
    params ["_group",["_vehicle",objNull],["_reason","player-ferry-boarding"]];
    if (isNull _group) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};
    if !(_group getVariable ["itwDelivery",false]) exitWith {false};

    private _already = _group getVariable ["ITW_CLASH_TransportAuthorityLease",false];
    if (!_already) then {
        _group setVariable ["ITW_CLASH_TransportPreviousUnable",_group getVariable ["Unable",false]];
        _group setVariable ["ITW_CLASH_TransportPreviousBUnable",_group getVariable ["BUnable",false]];
        _group setVariable ["ITW_CLASH_TransportPreviousBreak",_group getVariable ["Break",false]];
    };
    _group setVariable ["ITW_CLASH_TransportLeaseMode","ITW_DELIVERY"];
    _group setVariable ["Unable",true,true];
    _group setVariable ["BUnable",true,true];
    [_group,_reason] call ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL;
    true
};

ITW_CLASH_PlayerTransport_fnc_ReserveDelivery = {
    params ["_group",["_reason","itw-delivery-pool"]];
    if (isNull _group) exitWith {false};
    _group setVariable ["itwDelivery",true];
    [_group,objNull,_reason] call ITW_CLASH_PlayerTransport_fnc_Acquire
};

ITW_CLASH_PlayerTransport_fnc_Release = {
    params ["_group",["_reason","player-ferry-released"]];
    if (isNull _group) exitWith {false};
    if !(_group getVariable ["ITW_CLASH_TransportAuthorityLease",false]) exitWith {false};
    if (_group getVariable ["itwDelivery",false]) exitWith {false};
    if ((_group getVariable ["ITW_getInState",-1]) in [0,1]) exitWith {false};
    if (_group getVariable ["ITW_CLASH_TransportPhysicalUnloadPending",false]) exitWith {false};

    private _participants = +(_group getVariable ["ITW_CLASH_TransportParticipants",[]]);
    private _vehicle = _group getVariable ["ITW_CLASH_TransportCarrier",objNull];
    _group setVariable ["Break",_group getVariable ["ITW_CLASH_TransportPreviousBreak",false]];
    _group setVariable ["Unable",_group getVariable ["ITW_CLASH_TransportPreviousUnable",false],true];
    _group setVariable ["BUnable",_group getVariable ["ITW_CLASH_TransportPreviousBUnable",false],true];
    _group setVariable ["ITW_CLASH_AuthorityHold",nil];
    _group setVariable ["ITW_CLASH_Authority",nil];
    _group setVariable ["ITW_CLASH_AuthorityReason",nil];
    _group setVariable ["ITW_CLASH_TransportAuthorityLease",nil];
    _group setVariable ["ITW_CLASH_TransportLeaseMode",nil];
    _group setVariable ["ITW_CLASH_TransportCarrier",nil,true];
    _group setVariable ["ITW_CLASH_TransportCarrierGroup",nil];
    _group setVariable ["ITW_CLASH_TransportParticipants",nil];
    _group setVariable ["ITW_CLASH_TransportPhysicalUnloadPending",nil];
    _group setVariable ["ITW_CLASH_TransportPreviousUnable",nil];
    _group setVariable ["ITW_CLASH_TransportPreviousBUnable",nil];
    _group setVariable ["ITW_CLASH_TransportPreviousBreak",nil];

    ["itw-delivery-lease-released",[
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
        if (isNull _vehicle) then {"<none>"} else {typeOf _vehicle},
        _reason,_participants
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    true
};

// Observe HAL's actual cargo request before its untouched native dispatcher runs.
// This records strategic cargo+destination intent; it never selects a carrier.
[] spawn {
    scriptName "ITW_CLASH_PlayerTransportHALDemandBinder";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_CheckbookCargoHookReady",false]
            && {!isNil "HAL_SCargo"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["hal-demand-bind-timeout",[]] call ITW_CLASH_PlayerTransport_fnc_Log;
    };

    ITW_CLASH_PlayerTransport_fnc_SCargoBase = HAL_SCargo;
    HAL_SCargo = {
        private _requester = _this param [0,grpNull];
        private _hq = _this param [1,grpNull];
        private _destination = _this param [2,[]];
        private _withdraw = _this param [3,false];
        private _requestAir = _this param [4,false];
        private _requestGround = _this param [5,false];
        if (!isNull _requester && {!isNull _hq} && {_destination isNotEqualTo []} && {!_withdraw}) then {
            private _mode = if (_requestAir) then {"AIR"} else {
                if (_requestGround) then {"GROUND"} else {"AUTO"}
            };
            [_requester,_hq,_destination,_mode] call
                ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand;
        };
        _this call ITW_CLASH_PlayerTransport_fnc_SCargoBase
    };
    ["hal-demand-observer-ready",[]] call ITW_CLASH_PlayerTransport_fnc_Log;
};

// Replace and finalize exactly the two deferred native Impasse physical ferry
// functions before ITW_Start can launch ITW_AllyInit.
private _nativeBridgeReady = false;
if (fileExists "ITW_CLASH_PlayerTransportNativeBridge.sqf") then {
    _nativeBridgeReady = call compile preprocessFileLineNumbers
        "ITW_CLASH_PlayerTransportNativeBridge.sqf";
};
if !(_nativeBridgeReady isEqualTo true) then {
    ITW_CLASH_AllyTransportFinalizationWindow = false;
    ["ITW_AllyLoadIntoVehManager"] call SKL_fnc_CompileFinal;
    ["ITW_AllyLoadGrpIntoVeh"] call SKL_fnc_CompileFinal;
    diag_log "CLASH BOOT | WARNING | player-transport-native-bridge-failed | baseline ferry finalized";
};

if (fileExists "ITW_CLASH_PlayerTaskStateHardening.sqf") then {
    [] execVM "ITW_CLASH_PlayerTaskStateHardening.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | player-task-state-hardening-missing | employment admission remains v1";
};

ITW_CLASH_PlayerTransportAuthorityReady = _nativeBridgeReady isEqualTo true;
diag_log format [
    "CLASH BOOT | player-transport-authority-ready | version=%1 halSCargoSoleExecutor=true observerOnly=true retaskLock=true nativeBridge=%2 proximityCollisionGuard=true",
    ITW_CLASH_PlayerTransportAuthorityVersion,
    ITW_CLASH_PlayerTransportAuthorityReady
];
ITW_CLASH_PlayerTransportAuthorityReady