#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTransportRTBStarted",false]) exitWith {true};

ITW_CLASH_PlayerTransportRTBStarted = true;
ITW_CLASH_PlayerTransportRTBReady = false;
ITW_CLASH_PlayerTransportRTBVersion = 3;
ITW_CLASH_PlayerTransportRTBCaptureGrace = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportRTBCaptureGrace",180
];
ITW_CLASH_PlayerTransportRTBRadius = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportRTBRadius",350
];
ITW_CLASH_PlayerTransportRTBStopTimeout = missionNamespace getVariable [
    "ITW_CLASH_PlayerTransportRTBStopTimeout",120
];
ITW_CLASH_PlayerTransportRTBPoll = 0.5;

// The home-prime module shares the service-home resolver's live-base answer and
// causes the resolver itself to write HAL's START input before native SCargo
// creates either terminal RTB task.
if (fileExists "ITW_CLASH_PlayerCarrierHome.sqf") then {
    [] execVM "ITW_CLASH_PlayerCarrierHome.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | player-carrier-home-missing | HAL SCargo may fall back to HQ-jitter RTB coordinates";
};

ITW_CLASH_PlayerTransportRTB_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_Log") then {
        ["rtb-" + _event,_payload] call ITW_CLASH_PlayerTransport_fnc_Log;
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

ITW_CLASH_PlayerTransportRTB_fnc_TaskShape = {
    params ["_task"];
    if (_task isEqualTo taskNull) exitWith {"UNKNOWN"};
    private _description = taskDescription _task;
    if !(_description isEqualType [] && {count _description >= 2}) exitWith {"UNKNOWN"};
    private _title = toLowerANSI (_description#1);
    if (_title == "abort pick up, rtb") exitWith {"ABORT"};
    if (_title == "return to base") exitWith {"DELIVERY"};
    "UNKNOWN"
};

ITW_CLASH_PlayerTransportRTB_fnc_IsNativeRTBTask = {
    params ["_task"];
    if (_task isEqualTo taskNull) exitWith {false};
    private _description = taskDescription _task;
    if !(_description isEqualType [] && {count _description >= 2}) exitWith {false};
    private _body = toLowerANSI (_description#0);
    private _shape = [_task] call ITW_CLASH_PlayerTransportRTB_fnc_TaskShape;
    _shape in ["ABORT","DELIVERY"] || {_body == "return to departure base."}
};

ITW_CLASH_PlayerTransportRTB_fnc_TaskDestinationValid = {
    params ["_position"];
    _position isEqualType []
    && {count _position >= 2}
    && {!(_position isEqualTo [])}
    && {!(_position isEqualTo [0,0,0])}
};

ITW_CLASH_PlayerTransportRTB_fnc_CargoUnlinked = {
    params ["_cargoGroup","_carrier"];
    if (isNull _cargoGroup || {isNull _carrier}) exitWith {true};
    (units _cargoGroup findIf {
        alive _x && {vehicle _x == _carrier}
    }) < 0
};

ITW_CLASH_PlayerTransportRTB_fnc_LandedStopped = {
    params ["_carrier"];
    if (isNull _carrier) exitWith {false};
    ((getPosATL _carrier)#2) < 1 && {abs speed _carrier < 0.5}
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
        "CLASH BOOT | player-transport-rtb-ready | version=%1 transportOnly=true halRTBAdvisory=true abortAndDelivery=true arrivalCompletesTask=true radius=%2 altitudeLt1=true speedLt0_5=true cargoUnlinked=true stoppedTimeout=%3 liveHomePrimed=true",
        ITW_CLASH_PlayerTransportRTBVersion,
        ITW_CLASH_PlayerTransportRTBRadius,
        ITW_CLASH_PlayerTransportRTBStopTimeout
    ];

    while {!ITW_GameOver} do {
        // Remember player-flown AIR carriers selected by a live HAL_SCargo
        // contract. The grace survives both aborted pickups and physical-unlink
        // retirement long enough for native SCargo to publish either RTB task.
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

            // RYD_AddTask deletes the previous HAL task when another is created.
            // Never let an old monitor complete a task HAL has already replaced.
            if !(_trackedTask isEqualTo taskNull) then {
                if !(_trackedTask in _tasks) then {
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBStoppedSeconds",nil];
                    _group setVariable ["ITW_CLASH_PlayerTransportRTBTaskShape",nil];
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
                private _shape = [_trackedTask] call
                    ITW_CLASH_PlayerTransportRTB_fnc_TaskShape;
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBTask",_trackedTask
                ];
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBDestination",_destination
                ];
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBStoppedSeconds",0
                ];
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBTaskShape",_shape
                ];
                ["armed",[
                    _group getVariable ["ITW_CLASH_PlayerTransportRTBContractId",""],
                    _shape,+_destination
                ]] call ITW_CLASH_PlayerTransportRTB_fnc_Log;
            };

            if (_trackedTask isEqualTo taskNull) then {continue};
            if !(toUpperANSI (taskState _trackedTask) in ["ASSIGNED","CREATED"]) then {
                _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
                _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
                _group setVariable ["ITW_CLASH_PlayerTransportRTBStoppedSeconds",nil];
                _group setVariable ["ITW_CLASH_PlayerTransportRTBTaskShape",nil];
                continue
            };

            private _carrier = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBCarrier",objNull
            ];
            if (isNull _carrier || {!alive _carrier}) then {continue};
            private _carrierGroup = [_carrier] call
                ITW_CLASH_PlayerTransportRTB_fnc_CarrierGroup;
            if (_carrierGroup != _group) then {continue};

            private _cargoGroup = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBCargoGroup",grpNull
            ];
            private _cargoUnlinked = [_cargoGroup,_carrier] call
                ITW_CLASH_PlayerTransportRTB_fnc_CargoUnlinked;
            if (!_cargoUnlinked) then {continue};

            // Match HAL's disabled intent: the timeout counter accrues only
            // while the carrier is effectively stopped. It is deliberately not
            // reset by later movement, matching SCargo's original _timer logic.
            private _stoppedSeconds = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBStoppedSeconds",0
            ];
            if (abs speed _carrier < 0.5) then {
                _stoppedSeconds = _stoppedSeconds + ITW_CLASH_PlayerTransportRTBPoll;
                _group setVariable [
                    "ITW_CLASH_PlayerTransportRTBStoppedSeconds",_stoppedSeconds
                ];
            };

            private _destination = +(_group getVariable [
                "ITW_CLASH_PlayerTransportRTBDestination",[]
            ]);
            private _distance = if (_destination isEqualTo []) then {-1} else {
                _carrier distance2D _destination
            };
            private _landed = [_carrier] call
                ITW_CLASH_PlayerTransportRTB_fnc_LandedStopped;
            private _atHome = _distance >= 0 && {
                _distance <= ITW_CLASH_PlayerTransportRTBRadius
            };
            private _method = "";
            if (_landed && {_atHome}) then {
                _method = "landed";
            } else {
                if (_stoppedSeconds >= ITW_CLASH_PlayerTransportRTBStopTimeout) then {
                    _method = "timeout";
                };
            };
            if (_method isEqualTo "") then {continue};

            // HAL's disabled block unconditionally transitioned the RTB task to
            // SUCCEEDED after either normal arrival or its 120-second stop
            // timeout. Preserve that intended terminal behavior; C.L.A.S.H.
            // supplies only the missing task-state assertion, never movement.
            [_trackedTask,"SUCCEEDED",true] call BIS_fnc_taskSetState;
            private _contractId = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBContractId",""
            ];
            private _shape = _group getVariable [
                "ITW_CLASH_PlayerTransportRTBTaskShape","UNKNOWN"
            ];
            ["completed",[
                _contractId,
                "method=" + _method,
                if (_distance < 0) then {-1} else {round _distance},
                _shape
            ]] call ITW_CLASH_PlayerTransportRTB_fnc_Log;

            if (!isNil "ITW_CLASH_PlayerTasks_fnc_SyncAll") then {
                call ITW_CLASH_PlayerTasks_fnc_SyncAll;
            };

            _group setVariable ["ITW_CLASH_PlayerTransportRTBTask",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBDestination",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBStoppedSeconds",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBTaskShape",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBEligibleUntil",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBContractId",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBCargoGroup",nil];
            _group setVariable ["ITW_CLASH_PlayerTransportRTBCarrier",nil];
        } forEach _playerGroups;

        sleep ITW_CLASH_PlayerTransportRTBPoll;
    };
};

true
