#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTransportAuthorityStarted",false]) exitWith {true};

ITW_CLASH_PlayerTransportAuthorityStarted = true;
ITW_CLASH_PlayerTransportAuthorityVersion = 2;

ITW_CLASH_PlayerTransport_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["player-transport-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TRANSPORT | %1 | %2",_event,_payload];
    };
};

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
    } else {
        grpNull
    };
    if (isNull _hq) exitWith {false};

    private _included = +(_hq getVariable ["RydHQ_Included",[]]);
    _included = _included - [_group];
    _hq setVariable ["RydHQ_Included",_included];

    if (!isNil "ITW_CLASH_BLUFORHQ" && {_hq == ITW_CLASH_BLUFORHQ}) then {
        RydHQB_Included = +_included;
    };
    if (!isNil "ITW_CLASH_HALHQ" && {_hq == ITW_CLASH_HALHQ}) then {
        RydHQ_Included = +_included;
    };

    _group setVariable ["Break",true];
    _group setVariable ["ITW_CLASH_AuthorityHold",true];
    _group setVariable ["ITW_CLASH_TransportAuthorityLease",true];
    _group setVariable ["ITW_CLASH_Authority","ITW_TRANSPORT"];
    _group setVariable ["ITW_CLASH_AuthorityReason",_reason];

    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {
        call ITW_CLASH_DualHAL_fnc_SyncIncluded;
    };
    true
};

ITW_CLASH_PlayerTransport_fnc_Acquire = {
    params ["_group",["_vehicle",objNull],["_reason","player-ferry-boarding"]];
    if (isNull _group) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};

    private _alreadyLeased = _group getVariable [
        "ITW_CLASH_TransportAuthorityLease",false
    ];
    if (!_alreadyLeased) then {
        _group setVariable [
            "ITW_CLASH_TransportPreviousUnable",
            _group getVariable ["Unable",false]
        ];
        _group setVariable [
            "ITW_CLASH_TransportPreviousBUnable",
            _group getVariable ["BUnable",false]
        ];
        _group setVariable [
            "ITW_CLASH_TransportPreviousBreak",
            _group getVariable ["Break",false]
        ];
    };

    private _carrierGroup = grpNull;
    if (!isNull _vehicle) then {
        private _pilot = currentPilot _vehicle;
        if (!isNull _pilot) then {_carrierGroup = group _pilot};
    };
    private _participants = [];
    if (!isNull _carrierGroup) then {
        _participants = (units _carrierGroup select {isPlayer _x}) apply {
            [getPlayerUID _x,name _x]
        };
    };

    _group setVariable ["ITW_CLASH_TransportCarrier",_vehicle,true];
    _group setVariable ["ITW_CLASH_TransportCarrierGroup",_carrierGroup];
    _group setVariable ["ITW_CLASH_TransportParticipants",_participants];
    _group setVariable ["Unable",true,true];
    _group setVariable ["BUnable",true,true];

    [_group,_reason] call ITW_CLASH_PlayerTransport_fnc_RemoveFromHAL;

    if (!_alreadyLeased) then {
        ["lease-acquired",[
            if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId
            } else {str _group},
            if (isNull _vehicle) then {"<delivery-pool>"} else {typeOf _vehicle},
            _reason,
            _participants
        ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    };
    true
};

ITW_CLASH_PlayerTransport_fnc_ReserveDelivery = {
    params ["_group",["_reason","itw-delivery-pool"]];
    if (isNull _group) exitWith {false};

    // This flag must exist before ITW_AtkAddInfantryGroup. The Dual-HAL
    // admission predicate already treats itwDelivery as lifecycle-reserved.
    _group setVariable ["itwDelivery",true];
    [_group,objNull,_reason] call ITW_CLASH_PlayerTransport_fnc_Acquire
};

ITW_CLASH_PlayerTransport_fnc_Release = {
    params ["_group",["_reason","player-ferry-released"]];
    if (isNull _group) exitWith {false};
    if !(_group getVariable ["ITW_CLASH_TransportAuthorityLease",false]) exitWith {false};

    // A standing delivery squad stays under ITW until it is physically dropped
    // away from its source base. State 0/1 means boarding or embarked.
    if (_group getVariable ["itwDelivery",false]) exitWith {false};
    if ((_group getVariable ["ITW_getInState",-1]) in [0,1]) exitWith {false};
    if (_group getVariable [
        "ITW_CLASH_TransportPhysicalUnloadPending",false
    ]) exitWith {false};

    private _participants = +(_group getVariable [
        "ITW_CLASH_TransportParticipants",[]
    ]);
    private _vehicle = _group getVariable [
        "ITW_CLASH_TransportCarrier",objNull
    ];

    _group setVariable ["ITW_CLASH_TransportAuthorityLease",nil];
    _group setVariable ["ITW_CLASH_AuthorityHold",nil];
    _group setVariable ["ITW_CLASH_TransportCarrier",nil,true];
    _group setVariable ["ITW_CLASH_TransportCarrierGroup",nil];
    _group setVariable ["ITW_CLASH_TransportParticipants",nil];
    _group setVariable ["ITW_CLASH_TransportPhysicalUnloadPending",nil];
    _group setVariable [
        "Break",
        _group getVariable ["ITW_CLASH_TransportPreviousBreak",false]
    ];
    _group setVariable ["ITW_CLASH_Authority",nil];
    _group setVariable ["ITW_CLASH_AuthorityReason",nil];
    _group setVariable [
        "Unable",
        _group getVariable ["ITW_CLASH_TransportPreviousUnable",false],
        true
    ];
    _group setVariable [
        "BUnable",
        _group getVariable ["ITW_CLASH_TransportPreviousBUnable",false],
        true
    ];
    _group setVariable ["ITW_CLASH_TransportPreviousUnable",nil];
    _group setVariable ["ITW_CLASH_TransportPreviousBUnable",nil];
    _group setVariable ["ITW_CLASH_TransportPreviousBreak",nil];

    private _registered = false;
    if (!isNil "ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup" && {
        !isNil "ITW_CLASH_DualHAL_fnc_RegisterGroup"
    } && {
        [_group] call ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup
    }) then {
        _registered = [
            _group,"player-transport-delivered"
        ] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
    };

    ["lease-released",[
        if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") then {
            [_group] call ITW_CLASH_DualHAL_fnc_GroupId
        } else {str _group},
        if (isNull _vehicle) then {"<none>"} else {typeOf _vehicle},
        _reason,
        _registered,
        _participants
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;

    if (
        _reason == "player-ferry-delivered"
        && {_participants isNotEqualTo []}
        && {!isNil "ITW_CLASH_PlayerTasks_fnc_RecordEvent"}
    ) then {
        ["TRANSPORT_DELIVERED",createHashMapFromArray [
            ["cargoGroup",_group],
            ["vehicle",_vehicle],
            ["participants",_participants],
            ["completedAt",time]
        ]] call ITW_CLASH_PlayerTasks_fnc_RecordEvent;
    };

    if (!isNil "ITW_CLASH_DualHAL_fnc_SyncIncluded") then {
        call ITW_CLASH_DualHAL_fnc_SyncIncluded;
    };
    true
};

// Start player employment admission before PlayerTaskSupport is compiled. The
// hardening script waits for support primitives, so this creates an early
// watcher without changing transport authority itself.
if (fileExists "ITW_CLASH_PlayerTaskStateHardening.sqf") then {
    [] execVM "ITW_CLASH_PlayerTaskStateHardening.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | player-task-state-hardening-missing | employment admission remains v1";
};

ITW_CLASH_PlayerTransportAuthorityReady = true;
diag_log format [
    "CLASH BOOT | player-transport-authority-ready | version=%1 deliveryPreReserved=true boardingLease=true physicalRelease=true nativeITWTransport=true earlyPlayerAdmissionWatcher=true",
    ITW_CLASH_PlayerTransportAuthorityVersion
];
true
