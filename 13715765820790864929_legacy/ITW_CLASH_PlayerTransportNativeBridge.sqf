#include "defines.hpp"

if (!isServer) exitWith {false};
if (isNil "ITW_AllyLoadIntoVehManager" || {isNil "ITW_AllyLoadGrpIntoVeh"}) exitWith {false};

ITW_CLASH_PlayerTransportNativeBridgeVersion = 6;
ITW_CLASH_PlayerTransport_fnc_NativeLoadIntoVehManager = ITW_AllyLoadIntoVehManager;
ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh = ITW_AllyLoadGrpIntoVeh;

/*
    HAL_SCargo is a complete transport executor, not merely a carrier selector:
    it reserves the carrier, moves it to pickup, assigns cargo seats, waits for
    embarkation, owns the transport leg and owns terminal cleanup/RTB. Therefore
    C.L.A.S.H. observes and protects that lifecycle but never starts a second
    physical GET IN / GET OUT executor for the same HAL request.
*/

// Active HAL requests are retired by the passive SCargo-state monitor below.
// Do not make a live pickup disappear merely because a wall-clock lease elapsed.
ITW_CLASH_PlayerTransport_fnc_GetContract = {
    params ["_group"];
    if (isNull _group) exitWith {createHashMap};
    private _contract = _group getVariable [
        "ITW_CLASH_PlayerTransportContract",createHashMap
    ];
    if !(_contract isEqualType createHashMap) exitWith {createHashMap};
    private _state = _contract getOrDefault ["state",""];
    private _active = _state in ["HAL_DEMAND","HAL_ASSIGNED","EMBARKED"];
    if (!_active && {(_contract getOrDefault ["expiresAt",0]) < time}) exitWith {
        _group setVariable ["ITW_CLASH_PlayerTransportContract",nil];
        createHashMap
    };
    _contract
};

ITW_CLASH_PlayerTransport_fnc_CargoAboardCarrier = {
    params ["_group","_carrier"];
    if (isNull _group || {isNull _carrier}) exitWith {false};
    (units _group findIf {
        alive _x && {vehicle _x == _carrier}
    }) >= 0
};

/*
    HAL planning arrays are lossy metadata. A live ferry retask lock is an
    authority invariant, so it must be continuously asserted just like service
    quarantine. Preserve ApplyRetaskLock's original ownership ledger: this
    reconciler only restores missing memberships and never rewrites
    ITW_CLASH_TransportRetaskOwned.
*/
ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock = {
    params ["_group",["_source","reconcile"]];
    if (isNull _group) exitWith {false};

    if !(_group getVariable ["ITW_CLASH_TransportRetaskLock",false]) then {
        if (!isNil "ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock") then {
            [_group] call ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock;
        };
    };
    if !(_group getVariable ["ITW_CLASH_TransportRetaskLock",false]) exitWith {false};

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {grpNull};
    if (isNull _hq) exitWith {false};

    private _changed = [];
    {
        private _name = _x;
        private _members = +(_hq getVariable [_name,[]]);
        if !(_group in _members) then {
            _members pushBackUnique _group;
            _hq setVariable [_name,_members];
            _changed pushBack _name;
        };
    } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];

    if (_changed isNotEqualTo []) then {
        private _contract = _group getVariable [
            "ITW_CLASH_PlayerTransportContract",createHashMap
        ];
        ["hal-retask-lock-reconciled",[
            [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
            if (_contract isEqualType createHashMap) then {
                _contract getOrDefault ["id",""]
            } else {""},
            if (_contract isEqualType createHashMap) then {
                _contract getOrDefault ["state",""]
            } else {""},
            _source,+_changed
        ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    };
    true
};

// Contract retirement and retask-lock retirement are separate events. HAL can
// clear CargoCheckPending immediately after embarkation; that is not permission
// to expose embarked infantry to attack/recon/defense planning. If a contract
// end is observed while any living cargo remains linked to the carrier, retain
// both the contract and lock and complete retirement only after physical unlink.
ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract = {
    params ["_group","_contractId",["_reason","hal-scargo-ended"]];
    if (isNull _group) exitWith {false};
    private _contract = _group getVariable [
        "ITW_CLASH_PlayerTransportContract",createHashMap
    ];
    if !(_contract isEqualType createHashMap && {count _contract > 0}) exitWith {false};
    if ((_contract getOrDefault ["id",""]) isNotEqualTo _contractId) exitWith {false};

    private _state = _contract getOrDefault ["state",""];
    private _carrier = _contract getOrDefault ["carrier",objNull];
    private _destination = +(_contract getOrDefault ["destination",[]]);
    private _aboard = [_group,_carrier] call
        ITW_CLASH_PlayerTransport_fnc_CargoAboardCarrier;

    if (_aboard) exitWith {
        _contract set ["endDeferredAt",time];
        _contract set ["endDeferredReason",_reason];
        _contract set ["expiresAt",time + ITW_CLASH_PlayerTransportContractLifetime];
        _group setVariable ["ITW_CLASH_PlayerTransportContract",_contract];

        private _deferredId = _group getVariable [
            "ITW_CLASH_PlayerTransportEndDeferredContractId",""
        ];
        if (_deferredId isNotEqualTo _contractId) then {
            _group setVariable [
                "ITW_CLASH_PlayerTransportEndDeferredContractId",_contractId
            ];
            [_group,_carrier,_contractId,_reason] spawn {
                params ["_group","_carrier","_contractId","_reason"];
                scriptName "ITW_CLASH_PlayerTransportDeferredEnd";
                waitUntil {
                    sleep 0.5;
                    if (isNull _group) exitWith {true};
                    private _current = _group getVariable [
                        "ITW_CLASH_PlayerTransportContract",createHashMap
                    ];
                    if !(_current isEqualType createHashMap && {count _current > 0}) exitWith {true};
                    if ((_current getOrDefault ["id",""]) isNotEqualTo _contractId) exitWith {true};
                    [_group,"deferred-unlink-watch"] call
                        ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock;
                    !([_group,_carrier] call
                        ITW_CLASH_PlayerTransport_fnc_CargoAboardCarrier)
                };
                if (isNull _group) exitWith {};

                private _current = _group getVariable [
                    "ITW_CLASH_PlayerTransportContract",createHashMap
                ];
                if !(_current isEqualType createHashMap && {count _current > 0}) exitWith {
                    _group setVariable ["ITW_CLASH_PlayerTransportEndDeferredContractId",nil];
                };
                if ((_current getOrDefault ["id",""]) isNotEqualTo _contractId) exitWith {
                    _group setVariable ["ITW_CLASH_PlayerTransportEndDeferredContractId",nil];
                };

                _group setVariable ["ITW_CLASH_PlayerTransportEndDeferredContractId",nil];
                [_group,_contractId,_reason + ":physical-unlink"] call
                    ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract;
            };
        };

        ["hal-contract-end-deferred-embarked",[
            _contractId,
            [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
            _state,_reason,
            if (isNull _carrier) then {"<none>"} else {typeOf _carrier},
            +_destination
        ]] call ITW_CLASH_PlayerTransport_fnc_Log;
        true
    };

    _group setVariable ["ITW_CLASH_PlayerTransportEndDeferredContractId",nil];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_ClearRetaskLock") then {
        [_group] call ITW_CLASH_PlayerTransport_fnc_ClearRetaskLock;
    };
    _group setVariable ["ITW_CLASH_PlayerTransportContract",nil];

    ["hal-contract-ended",[
        _contractId,
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
        _state,_reason,
        if (isNull _carrier) then {"<none>"} else {typeOf _carrier},
        +_destination
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    true
};

ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract = {
    params ["_group","_contractId"];
    if (isNull _group || {_contractId isEqualTo ""}) exitWith {};

    private _pendingKey = "CargoCheckPending" + str _group;
    private _assignedKey = "AssignedCargo" + str _group;
    private _sawPending = false;
    private _lastCarrier = objNull;
    private _startedAt = time;
    private _hardDeadline = time + 1800;
    private _reason = "hal-scargo-ended";

    while {true} do {
        sleep 0.5;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            _reason = "cargo-group-lost";
        };

        private _contract = _group getVariable [
            "ITW_CLASH_PlayerTransportContract",createHashMap
        ];
        if !(_contract isEqualType createHashMap && {count _contract > 0}) exitWith {
            _reason = "contract-cleared-externally";
        };
        if ((_contract getOrDefault ["id",""]) isNotEqualTo _contractId) exitWith {
            _reason = "contract-replaced";
        };

        [_group,"active-contract-watch"] call
            ITW_CLASH_PlayerTransport_fnc_EnsureRetaskLock;

        private _pending = _group getVariable [_pendingKey,false];
        if (_pending) then {_sawPending = true};
        private _carrier = _group getVariable [_assignedKey,objNull];

        if (!isNull _carrier && {_carrier != _lastCarrier}) then {
            _lastCarrier = _carrier;
            private _carrierGroup = group assignedDriver _carrier;
            if (isNull _carrierGroup) then {_carrierGroup = group driver _carrier};
            _contract set ["carrier",_carrier];
            _contract set ["carrierGroup",_carrierGroup];
            _contract set ["state","HAL_ASSIGNED"];
            _contract set ["assignedAt",time];
            _contract set ["expiresAt",time + ITW_CLASH_PlayerTransportContractLifetime];
            _group setVariable ["ITW_CLASH_PlayerTransportContract",_contract];
            ["hal-carrier-selected",[
                _contractId,
                [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
                typeOf _carrier,
                !isNull currentPilot _carrier && {isPlayer currentPilot _carrier},
                if (isNull _carrierGroup) then {"<null>"} else {
                    [_carrierGroup] call ITW_CLASH_PlayerTransport_fnc_GroupId
                },
                +(_contract getOrDefault ["destination",[]])
            ]] call ITW_CLASH_PlayerTransport_fnc_Log;
        };

        if (!isNull _carrier && {vehicle leader _group == _carrier} && {
            (_contract getOrDefault ["state",""]) != "EMBARKED"
        }) then {
            _contract set ["state","EMBARKED"];
            _contract set ["embarkedAt",time];
            _contract set ["expiresAt",time + ITW_CLASH_PlayerTransportContractLifetime];
            _group setVariable ["ITW_CLASH_PlayerTransportContract",_contract];
            ["hal-contract-embarked",[
                _contractId,
                [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
                typeOf _carrier,
                +(_contract getOrDefault ["destination",[]])
            ]] call ITW_CLASH_PlayerTransport_fnc_Log;
        };

        if (_sawPending && {!_pending}) exitWith {
            _reason = "hal-scargo-pending-cleared";
        };
        if (!_sawPending && {time - _startedAt > 15} && {
            isNull _carrier && {!(_group getVariable ["CargoChosen",false])}
        }) exitWith {
            _reason = "hal-scargo-no-assignment";
        };
        if (time >= _hardDeadline) exitWith {
            _reason = "hal-scargo-monitor-timeout";
        };
    };

    if (_reason isNotEqualTo "contract-replaced") then {
        [_group,_contractId,_reason] call
            ITW_CLASH_PlayerTransport_fnc_EndObservedHALContract;
    };
};

ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand = {
    params ["_group","_hq","_destination",["_mode","AUTO"]];
    if (isNull _group || {isNull _hq} || {_destination isEqualTo []}) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};
    if (_group getVariable ["itwDelivery",false]) exitWith {false};

    private _existing = [_group] call ITW_CLASH_PlayerTransport_fnc_GetContract;
    if (count _existing > 0) exitWith {true};

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
        ["carrierGroup",grpNull],
        ["source","HAL_SCargo"]
    ];
    _group setVariable ["ITW_CLASH_PlayerTransportContract",_contract];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock") then {
        [_group] call ITW_CLASH_PlayerTransport_fnc_ApplyRetaskLock;
    };

    ["hal-demand-observed",[
        _id,
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
        _hq getVariable ["RydHQ_CodeSign","?"],
        toUpperANSI _mode,+_destination,
        round (leader _group distance2D _destination),
        "hal-owns-physical-execution"
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    [_group,_id] spawn ITW_CLASH_PlayerTransport_fnc_MonitorObservedHALContract;
    true
};

ITW_CLASH_PlayerTransport_fnc_AcquireDeliveryBase = ITW_CLASH_PlayerTransport_fnc_Acquire;
ITW_CLASH_PlayerTransport_fnc_Acquire = {
    params ["_group",["_vehicle",objNull],["_reason","player-ferry-boarding"]];
    if (isNull _group) exitWith {false};
    if (_group getVariable ["itwDelivery",false]) exitWith {
        _this call ITW_CLASH_PlayerTransport_fnc_AcquireDeliveryBase
    };

    private _contract = [_group] call ITW_CLASH_PlayerTransport_fnc_GetContract;
    ["native-proximity-rejected",[
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId,
        if (isNull _vehicle) then {"<none>"} else {typeOf _vehicle},
        if (count _contract > 0) then {
            "hal-scargo-owns-physical-execution"
        } else {
            "no-hal-transport-contract"
        },
        if (count _contract > 0) then {_contract getOrDefault ["id",""]} else {""}
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;
    false
};

ITW_CLASH_PlayerTransport_fnc_ThrottleLog = {
    params ["_veh","_key","_event","_payload",["_seconds",15]];
    if (isNull _veh) exitWith {false};
    private _next = _veh getVariable [_key,0];
    if (time < _next) exitWith {false};
    _veh setVariable [_key,time + _seconds];
    [_event,_payload] call ITW_CLASH_PlayerTransport_fnc_Log;
    true
};

ITW_AllyLoadIntoVehManager = {
    scriptName "ITW_AllyLoadIntoVehManager_CLASH_DISABLED";

    /*
        Native Impasse proximity ferry is intentionally disabled under C.L.A.S.H.

        Baseline Impasse scans player-crewed transports parked near a FOB,
        automatically selects nearby infantry, orders them aboard, and then asks
        the player to carry them within TRANSPORT_DROP_MAX_DIST of an objective.
        That creates unsolicited transport jobs outside HAL's employment
        authority and conflicts directly with the explicit HAL transport menu.

        HAL_SCargo remains the sole commander transport executor. Existing
        native loading code is preserved below for compatibility with any
        already-established/explicit lifecycle, but this ambient scanner never
        manufactures a pickup from player proximity.
    */
    ["native-proximity-ferry-disabled",[
        "hal-scargo-sole-dispatch",
        "no-unsolicited-player-pickup",
        TRANSPORT_DROP_MAX_DIST
    ]] call ITW_CLASH_PlayerTransport_fnc_Log;

    waitUntil {
        sleep 30;
        missionNamespace getVariable ["ITW_GameOver",false]
    };
};
ITW_AllyLoadGrpIntoVeh = ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;

ITW_CLASH_AllyTransportFinalizationWindow = false;
private _managerFinal = ["ITW_AllyLoadIntoVehManager"] call SKL_fnc_CompileFinal;
private _loadFinal = ["ITW_AllyLoadGrpIntoVeh"] call SKL_fnc_CompileFinal;

diag_log format [
    "CLASH BOOT | player-transport-native-bridge-ready | version=%1 manager=%2 loader=%3 halPhysicalExecutor=true nativeITWFerryPreserved=false ambientProximityFerry=false unsolicitedPlayerPickup=false collisionSuppression=true proximityCreatesHALJob=false contractEndUnlockSeparated=true retaskLockReconciled=true",
    ITW_CLASH_PlayerTransportNativeBridgeVersion,_managerFinal,_loadFinal
];
_managerFinal && _loadFinal