#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTransportRTBStarted",false]) exitWith {true};

ITW_CLASH_PlayerTransportRTBStarted = true;
ITW_CLASH_PlayerTransportRTBReady = false;
ITW_CLASH_PlayerTransportRTBVersion = 2;
ITW_CLASH_PlayerTransportRTBCaptureGrace = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportRTBCaptureGrace",180
];
ITW_CLASH_PlayerTransportRTBRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportRTBRadius",500
];

// The home-prime module shares the service-home resolver's live-base answer and
// writes HAL's own START input before native SCargo creates its RTB task.
if (fileExists "ITW_CLASH_PlayerCarrierHome.sqf") then {
    [] execVM "ITW_CLASH_PlayerCarrierHome.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | player-carrier-home-missing | HAL SCargo may fall back to HQ-jitter RTB coordinates";
};

ITW_CLASH_PlayerTransportRTB_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_Log") then {
        ["player-rtb-" + _event,_payload] call ITW_CLASH_PlayerTransport_fnc_Log;
    } else {
        diag_log format ["CLASH PLAYER TRANSPORT RTB | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_PlayerTransportRTB_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId
    };
    str _group
};

ITW_CLASH_PlayerTransportRTB_fnc_CarrierGroup = {
    params ["_carrier"];
    if (isNull _carrier) exitWith {grpNull};
    private _driver = assignedDriver _carrier;
    if (isNull _driver) then {_driver = driver _carrier};
    if (isNull _driver) exitWith {grpNull};
    group _driver
};

ITW_CLASH_PlayerTransportRTB_fnc_IsHumanAirCarrier = {
    params ["_carrier","_carrierGroup"];
    !isNull _carrier
    && {!isNull _carrierGroup}
    && {_carrier isKindOf "Air"}
    && {(units _carrierGroup findIf {isPlayer _x}) >= 0}
};

ITW_CLASH_PlayerTransportRTB_fnc_IsNativeRTBTask = {
    params ["_task"];
    if (_task isEqualTo taskNull) exitWith {false};
    private _description = taskDescription _task;
    if !(_description isEqualType [] && {count _description >= 2}) exitWith {false};
    private _body = toLowerANSI (_description#0);
    private _title = toLowerANSI (_description#1);
    _title == "return to base" || {_body == "return to departure base."}
};

ITW_CLASH_PlayerTransportRTB_fnc_TaskDestinationValid = {
    params ["_position"];
    _position isEqualType []
    && {count _position >= 2}
    && {!(_position isEqualTo [])}
    && {!(_position isEqualTo [0,0,0])}
};

ITW_CLASH_PlayerTransportRTB_fnc_AtDestination = {
    params ["_carrier","_destination"];
    if (isNull _carrier || {
        !([_destination] call ITW_CLASH_PlayerTransportRTB_fnc_TaskDestinationValid)
    }) exitWith {false};

    private _grounded = isTouchingGround _carrier || {
        ((getPosATL _carrier)#2) <= 2
    };
    _grounded && {
        (_carrier distance2D _destination) <= ITW_CLASH_PlayerTransportRTBRadius
    }
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTransportRTBWatch";

    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTransportAuthorityReady",false]
            && {!isNil "ITW_CLASH_PlayerTransport_fnc_GetContract"}
            && {!isNil "BIS_fnc_taskSetState"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_PlayerTransportRTB_fnc_Log;
    };

    ITW_CLASH_PlayerTransportRTBReady = true;
    diag_log format [
        "CLASH BOOT | player-transport-rtb-ready | version=%1 transportOnly=true halRTBAdvisory=true arrivalCompletesTask=true radius=%2 grounded=true cargoUnlinked=true liveHomePrimed=true",
        ITW_CLASH_PlayerTransportRTBVersion,
        ITW_CLASH_PlayerTransportRTBRadius
    ];

    while {!ITW_GameOver} do {
        // Remember only player-flown AIR carriers actually selected by a live
        // HAL_SCargo contract. The short grace survives the contract's physical-
        // unlink retirement long enough for native SCargo to publish its RTB task.
        {
            private _cargoGroup = _x;
            private _contract = _cargoGroup getVariable [
                "ITW_CLASH_PlayerTransportContract",createHashMap
            ];
            if !(_contract isEqualType createHashMap && {count _contract > 0}) then {continue};
            if ((_contract getOrDefault ["source",""]) != "HAL_SCargo") then {continue};

            private _carrier = _contract getOrDefault ["carrier",objNull];
            private _carrierGroup = [_carrier] call
                ITW_CLASH_PlayerTransportRTB_fnc_CarrierGroup;
            if !([_carrier,_carrierGroup] call
                ITW_CLASH_PlayerTransportRTB_fnc_IsHumanAirCarrier
            ) then {continue};

            _carrierGroup setVariable [
                "ITW_CLASH_PlayerTransportRTBEligibleUntil",
                time + ITW_CLASH_PlayerTransportRTBCaptureGrace
            ];
            _carrierGroup setVariable [
                "ITW_CLASH_PlayerTransportRTBCarrier",_carrier
            ];
            _carrierGroup setVariable [
                "ITW_CLASH_PlayerTransportRTBCargoGroup",_cargoGroup
            ];
            _carrierGroup setVariable [
                "ITW_CLASH_PlayerTransportRTBContractId",
                _contract getOrDefault ["id",""]
            ];
        } forEach allGroups;

        private _playerGroups = [];
        {
            private _group = group _x;
            if (!isNull _group) then {_playerGroups pushBackUnique _group};
        } forEach allPlayers;

        {
            private _group = _x;
            private _trackedTask = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBTask",taskNull
            ];
            private _tasks = +(_group getVariable ["HACAddedTasks",[]]);

            // A new HAL task replaces/deletes the old RTB task. Never let an old
            // monitor complete whatever task HAL assigned afterward.
            if !(_trackedTask isEqualTo taskNull) then {
                if !(_trackedTask in _tasks) then {
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
                    _trackedTask = taskNull;
                };
            };

            if (_trackedTask isEqualTo taskNull) then {
                if (time > (_group getVariable [
                    "ITW_CLASH_PlayerTransportRTBEligibleUntil",0
                ])) then {continue};

                private _index = _tasks findIf {
                    [_x] call ITW_CLASH_PlayerTransportRTB_fnc_IsNativeRTBTask
                    && {toUpperANSI (taskState _x) in ["ASSIGNED","CREATED"]}
                    && {[
                        taskDestination _x
                    ] call ITW_CLASH_PlayerTransportRTB_fnc_TaskDestinationValid}
                };
                if (_index < 0) then {continue};

                _trackedTask = _tasks#_index;
                private _destination = +(taskDestination _trackedTask);
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBTask",_trackedTask
                ];
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBDestination",_destination
                ];
                ["armed",[
                    [_group] call ITW_CLASH_PlayerTransportRTB_fnc_GroupId,
                    _group getVariable ["ITW_CLASH_PlayerTransportRTBContractId",""],
                    +_destination
                ]] call ITW_CLASH_PlayerTransportRTB_fnc_Log;
            };

            if (_trackedTask isEqualTo taskNull) then {continue};
            if !(toUpperANSI (taskState _trackedTask) in ["ASSIGNED","CREATED"]) then {
                _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
                _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
                continue
            };

            private _carrier = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBCarrier",objNull
            ];
            if (isNull _carrier || {!alive _carrier}) then {continue};
            private _carrierGroup = [_carrier] call
                ITW_CLASH_PlayerTransportRTB_fnc_CarrierGroup;
            if (_carrierGroup != _group) then {continue};

            // RTB is terminal guidance only after the insertion is physically
            // over. Never succeed it while the contracted infantry still rides.
            private _cargoGroup = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBCargoGroup",grpNull
            ];
            if (!isNull _cargoGroup && {
                (units _cargoGroup findIf {
                    alive _x && {vehicle _x == _carrier}
                }) >= 0
            }) then {continue};

            private _destination = +(_group getVariable [
                "ITW_CLASH_PlayerTransportRTBDestination",[]
            ]);
            if !([_carrier,_destination] call
                ITW_CLASH_PlayerTransportRTB_fnc_AtDestination
            ) then {continue};

            [_trackedTask,"SUCCEEDED",true] call BIS_fnc_taskSetState;
            ["completed",[
                [_group] call ITW_CLASH_PlayerTransportRTB_fnc_GroupId,
                _group getVariable ["ITW_CLASH_PlayerTransportRTBContractId",""],
                typeOf _carrier,
                round (_carrier distance2D _destination),
                round ((getPosATL _carrier)#2)
            ]] call ITW_CLASH_PlayerTransportRTB_fnc_Log;

            _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBEligibleUntil",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBContractId",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBCargoGroup",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBCarrier",nil];
        } forEach _playerGroups;

        sleep 0.5;
    };
};

true
