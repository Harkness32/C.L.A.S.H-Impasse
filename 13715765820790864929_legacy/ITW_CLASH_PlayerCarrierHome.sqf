#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerCarrierHomeStarted",false]) exitWith {true};

ITW_CLASH_PlayerCarrierHomeStarted = true;
ITW_CLASH_PlayerCarrierHomeReady = false;
ITW_CLASH_PlayerCarrierHomeVersion = 1;

ITW_CLASH_PlayerCarrierHome_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_ServiceHome_fnc_Log") then {
        ["player-carrier-" + _event,_payload] call ITW_CLASH_ServiceHome_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER CARRIER HOME | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerCarrierHome_fnc_CarrierGroup = {
    params ["_carrier"];
    if (isNull _carrier) exitWith {grpNull};
    private _driver = assignedDriver _carrier;
    if (isNull _driver) then {_driver = driver _carrier};
    if (isNull _driver) exitWith {grpNull};
    group _driver
};

ITW_CLASH_PlayerCarrierHome_fnc_IsPlayerAirCarrier = {
    params ["_carrier","_group"];
    !isNull _carrier
    && {!isNull _group}
    && {_carrier isKindOf "Air"}
    && {(units _group findIf {isPlayer _x}) >= 0}
};

/*
    Transient player carriers are not service-pool assets, but HAL SCargo still
    consumes the same START+str(group) RTB input used by persistent service
    crews. Resolve that input through the existing live Impasse base resolver
    without registering the player vehicle into the service lifecycle.
*/
ITW_CLASH_ServiceHome_fnc_ResolvePlayerCarrier = {
    params ["_group","_carrier",["_reason","hal-scargo-carrier-selected"]];
    if (isNull _group || {isNull _carrier}) exitWith {
        createHashMapFromArray [["status","UNRESOLVED"],["reason","null-carrier"]]
    };
    if !(missionNamespace getVariable ["ITW_CLASH_ServiceHomeResolverReady",false]) exitWith {
        createHashMapFromArray [["status","UNRESOLVED"],["reason","resolver-not-ready"]]
    };
    if (isNil "ITW_CLASH_ServiceHome_fnc_Resolve") exitWith {
        createHashMapFromArray [["status","UNRESOLVED"],["reason","resolver-function-missing"]]
    };

    private _mode = if (_carrier isKindOf "Ship") then {"SEA"} else {
        if (_carrier isKindOf "Air") then {"AIR"} else {"GROUND"}
    };
    private _hint = _carrier getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    if (_hint < 0) then {
        _hint = _group getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    };

    private _entry = createHashMapFromArray [
        ["id","PLAYER-CARRIER-" + str _group],
        ["side",side _group],
        ["mode",_mode],
        ["vehicle",_carrier],
        ["group",_group],
        ["baseHint",_hint]
    ];
    private _resolved = [
        _entry,getPosATL _carrier
    ] call ITW_CLASH_ServiceHome_fnc_Resolve;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {
        ["resolve-failed",[
            str _group,typeOf _carrier,_mode,_reason,
            _resolved getOrDefault ["reason","unknown"]
        ]] call ITW_CLASH_PlayerCarrierHome_fnc_Log;
        _resolved
    };

    private _position = +(_resolved get "position");
    private _baseIndex = _resolved getOrDefault ["baseIndex",-1];
    private _method = _resolved getOrDefault ["method","unknown"];

    if (_baseIndex >= 0 && {!isNil "ITW_CLASH_ServiceHome_fnc_SetBaseHint"}) then {
        [_carrier,_group,_baseIndex,"hal-player-carrier"] call
            ITW_CLASH_ServiceHome_fnc_SetBaseHint;
    };

    // This is the same write-through contract as persistent service-home
    // resolution. HAL SCargo remains the consumer and sole RTB executor.
    _group setVariable ["START" + str _group,+_position];
    _group setVariable ["ITW_CLASH_ServiceHome",+_position];
    _group setVariable ["ITW_CLASH_PlayerCarrierHomeResolvedAt",time];
    _group setVariable ["ITW_CLASH_PlayerCarrierHomeBaseIndex",_baseIndex];

    ["resolved",[
        str _group,typeOf _carrier,_baseIndex,_method,+_position,_reason
    ]] call ITW_CLASH_PlayerCarrierHome_fnc_Log;
    _resolved
};

[] spawn {
    scriptName "ITW_CLASH_PlayerCarrierHomeWatch";

    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTransportAuthorityReady",false]
            && {missionNamespace getVariable ["ITW_CLASH_ServiceHomeResolverReady",false]}
            && {!isNil "ITW_CLASH_ServiceHome_fnc_Resolve"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_PlayerCarrierHome_fnc_Log;
    };

    ITW_CLASH_PlayerCarrierHomeReady = true;
    diag_log format [
        "CLASH BOOT | player-carrier-home-ready | version=%1 playerAirOnly=true liveImpasseBaseResolver=true writesSTART=true servicePoolRegistration=false halRTBExecutor=true",
        ITW_CLASH_PlayerCarrierHomeVersion
    ];

    while {!ITW_GameOver} do {
        {
            private _cargoGroup = _x;
            private _contract = _cargoGroup getVariable [
                "ITW_CLASH_PlayerTransportContract",createHashMap
            ];
            if !(_contract isEqualType createHashMap && {count _contract > 0}) then {continue};
            if ((_contract getOrDefault ["source",""]) != "HAL_SCargo") then {continue};

            private _contractId = _contract getOrDefault ["id",""];
            if (_contractId isEqualTo "") then {continue};
            private _carrier = _contract getOrDefault ["carrier",objNull];
            if (isNull _carrier) then {continue};
            private _carrierGroup = [_carrier] call
                ITW_CLASH_PlayerCarrierHome_fnc_CarrierGroup;
            if !([_carrier,_carrierGroup] call
                ITW_CLASH_PlayerCarrierHome_fnc_IsPlayerAirCarrier
            ) then {continue};

            if ((_carrierGroup getVariable [
                "ITW_CLASH_PlayerCarrierHomeContractId",""
            ]) isEqualTo _contractId) then {continue};
            if (time < (_carrierGroup getVariable [
                "ITW_CLASH_PlayerCarrierHomeRetryAt",0
            ])) then {continue};

            private _resolved = [
                _carrierGroup,_carrier,"hal-scargo-carrier-selected"
            ] call ITW_CLASH_ServiceHome_fnc_ResolvePlayerCarrier;
            if ((_resolved getOrDefault ["status",""]) == "RESOLVED") then {
                _carrierGroup setVariable [
                    "ITW_CLASH_PlayerCarrierHomeContractId",_contractId
                ];
                _carrierGroup setVariable [
                    "ITW_CLASH_PlayerCarrierHomeRetryAt",nil
                ];
            } else {
                _carrierGroup setVariable [
                    "ITW_CLASH_PlayerCarrierHomeRetryAt",time + 5
                ];
            };
        } forEach allGroups;

        sleep 0.25;
    };
};

true
