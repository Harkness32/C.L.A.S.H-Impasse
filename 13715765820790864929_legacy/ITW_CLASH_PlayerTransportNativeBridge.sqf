#include "defines.hpp"

if (!isServer) exitWith {false};
if (isNil "ITW_AllyLoadIntoVehManager" || {isNil "ITW_AllyLoadGrpIntoVeh"}) exitWith {false};

ITW_CLASH_PlayerTransportNativeBridgeVersion = 4;
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
    scriptName "ITW_AllyLoadIntoVehManager_CLASH";
    while {!ITW_GameOver} do {
        {
            private _veh = _x;
            private _pilot = currentPilot _veh;
            if (!isPlayer _pilot && {units group _pilot findIf {isPlayer _x} == -1}) then {continue};
            if (side _pilot != ITW_PlayerSide) then {continue};
            if (speed _veh > 5) then {continue};
            private _vPos = getPosATL _veh;
            private _isWater = surfaceIsWater _vPos;
            if (_isWater && {_vPos#2 > 4.5}) then {continue};
            if (!_isWater && {!(isTouchingGround _veh) && {_vPos#2 > 2}}) then {continue};
            if (!canMove _veh || {fuel _veh == 0}) then {continue};
            if (isPlayer _pilot && {_veh getVariable ["ITW_BlockAllyEntry",false]}) then {continue};
            if !(_veh getVariable ["ITW_reservedGroups",[]] isEqualTo []) then {continue};
            if (_veh getVariable ["ITW_AllyEntryTimeout",0] > time) then {continue};
            if (_veh getVariable ["ITW_AllyCrewEject",false]) then {continue};
            if (_veh getVariable ["SKL_BFC_running",false]) then {continue};

            private _pilotGroup = group _pilot;
            private _halOccupied = !isNull _pilotGroup && {
                _pilotGroup getVariable ["Busy" + str _pilotGroup,false] || {
                    (_pilotGroup getVariable ["ITW_CLASH_PlayerNativeJobId",""]) isNotEqualTo ""
                } || {
                    (_pilotGroup getVariable ["ITW_CLASH_PlayerAmmoJobId",""]) isNotEqualTo ""
                } || {
                    (_pilotGroup getVariable ["ITW_CLASH_PlayerArtilleryJobId",""]) isNotEqualTo ""
                }
            };
            if (_halOccupied) then {
                [_veh,"ITW_CLASH_ProximityBusyLogAt","native-proximity-suppressed-hal-busy-carrier",[
                    if (isNull _pilotGroup) then {"<null>"} else {
                        [_pilotGroup] call ITW_CLASH_PlayerTransport_fnc_GroupId
                    },typeOf _veh,"hal-job-active"
                ],15] call ITW_CLASH_PlayerTransport_fnc_ThrottleLog;
                continue
            };

            private _emptySeats = if (_veh getVariable ["ITW_BlockAllyCrew",true]) then {
                {isNull (_x#5) && {_x#2 >= 0}} count fullCrew [_veh,"",true]
            } else {
                {isNull (_x#5) && {_x#2 >= 0 || {!(_x#3 isEqualTo [])}}} count fullCrew [_veh,"",true]
            };
            if (_emptySeats == 0) then {continue};

            if (isPlayer _pilot && {speed _veh > 6 && {
                _veh getVariable ["ITW_ForceAllyEntry",false] && {ITW_ELEVATION(_vPos) > 6}
            }}) then {
                _veh setVariable ["ITW_ForceAllyEntry",false,true];
            };

            private _objType = if (isPlayer _pilot && {
                _veh getVariable ["ITW_ForceAllyEntry",false]
            }) then {ITW_OWNER_ENEMY} else {ITW_OWNER_CONTESTED};
            private _closestObj = [_vPos,ITW_OWNER_CONTESTED,_objType] call ITW_ObjGetNearest;
            if (_closestObj#ITW_OBJ_POS distance _veh < 1000) then {continue};

            private _onFootAllies = [];
            {
                private _grp = _x;
                private _leader = leader _grp;
                if (
                    !(_grp getVariable ["ITW_Garrison",false])
                    && {!(_grp getVariable ["itwInitGrp",false])}
                    && {vehicle _leader == _leader}
                    && {_leader distance _veh < 250}
                    && {isNull getAttackTarget _leader}
                    && {!fleeing _leader}
                    && {_grp getVariable ["ITW_getInState",-1] == -1}
                ) then {
                    private _contract = [_grp] call ITW_CLASH_PlayerTransport_fnc_GetContract;
                    if (count _contract > 0) then {
                        [_veh,"ITW_CLASH_ProximityContractLogAt","native-proximity-skipped-hal-contract",[
                            [_grp] call ITW_CLASH_PlayerTransport_fnc_GroupId,
                            typeOf _veh,_contract getOrDefault ["id",""],
                            "hal-scargo-owns-physical-execution"
                        ],15] call ITW_CLASH_PlayerTransport_fnc_ThrottleLog;
                    } else {
                        _onFootAllies pushBack [leader _grp distance _veh,_grp];
                    };
                };
            } forEach ITW_AllyGroups;
            if (_onFootAllies isEqualTo []) then {continue};

            _onFootAllies sort true;
            private _groupsToLoad = [];
            {
                private _grp = _x#1;
                private _grpSize = count units _grp;
                if (_grpSize > _emptySeats) then {continue};
                _emptySeats = _emptySeats - _grpSize;
                _groupsToLoad pushBack _grp;
                VAR_SET_OBJ_IDX(_grp,_closestObj#ITW_OBJ_INDEX);
                _grp setVariable ["ITW_getInState",0];
                ITW_DELETE_WAYPOINTS(_grp);
                ["native-proximity-itw-ferry",[
                    [_grp] call ITW_CLASH_PlayerTransport_fnc_GroupId,
                    typeOf _veh,"halContract",false,"halJobManufactured",false
                ]] call ITW_CLASH_PlayerTransport_fnc_Log;
            } forEach _onFootAllies;

            if !(_groupsToLoad isEqualTo []) then {
                _veh setVariable ["ITW_reservedGroups",_groupsToLoad];
                [_veh,_groupsToLoad] spawn ITW_AllyLoadGrpIntoVeh;
            };
        } forEach vehicles;
        sleep 8;
        while {LV_PAUSE} do {sleep 5};
    };
};

ITW_AllyLoadGrpIntoVeh = ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;

ITW_CLASH_AllyTransportFinalizationWindow = false;
private _managerFinal = ["ITW_AllyLoadIntoVehManager"] call SKL_fnc_CompileFinal;
private _loadFinal = ["ITW_AllyLoadGrpIntoVeh"] call SKL_fnc_CompileFinal;

diag_log format [
    "CLASH BOOT | player-transport-native-bridge-ready | version=%1 manager=%2 loader=%3 halPhysicalExecutor=true nativeITWFerryPreserved=true collisionSuppression=true proximityCreatesHALJob=false contractEndUnlockSeparated=true",
    ITW_CLASH_PlayerTransportNativeBridgeVersion,_managerFinal,_loadFinal
];
_managerFinal && _loadFinal