#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALTransportAudioStarted",false]) exitWith {true};

ITW_CLASH_HALTransportAudioStarted = true;
ITW_CLASH_HALTransportAudioReady = false;
ITW_CLASH_HALTransportAudioVersion = 1;

ITW_CLASH_HALTransportAudio_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_Log") then {
        ["audio-" + _event,_payload] call ITW_CLASH_PlayerTransport_fnc_Log;
    } else {
        diag_log format ["CLASH HAL TRANSPORT AUDIO | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALTransportAudio_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_PlayerTransport_fnc_GroupId
    };
    str _group
};

ITW_CLASH_HALTransportAudio_fnc_Emit = {
    params ["_group","_carrier","_phase","_contractId"];
    if (isNull _group || {isNull _carrier}) exitWith {false};

    private _nearbyPlayers = allPlayers select {
        alive _x && {_carrier distance _x < 20}
    };
    private _pilot = currentPilot _carrier;

    switch (_phase) do {
        case "BOARD_START": {
            if (!isNil "ITW_AllyRadioMsg" && {_nearbyPlayers isNotEqualTo []}) then {
                ["bStart",_carrier] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
            };
            if (!isNull _pilot) then {
                [leader _group,localize "STR_ITW_ALLY_WeAreBoarding"] remoteExec ["sideChat",_pilot];
            };
        };
        case "BOARD_END": {
            if (!isNil "ITW_AllyRadioMsg" && {_nearbyPlayers isNotEqualTo []}) then {
                ["bEnd",_carrier] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
            };
            if (!isNull _pilot) then {
                [leader _group,localize "STR_ITW_ALLY_WeAreIn"] remoteExec ["sideChat",_pilot];
            };
        };
        default {};
    };

    [toLowerANSI _phase,[
        _contractId,
        [_group] call ITW_CLASH_HALTransportAudio_fnc_GroupId,
        typeOf _carrier,
        count _nearbyPlayers,
        if (isNull _pilot) then {"<none>"} else {name _pilot}
    ]] call ITW_CLASH_HALTransportAudio_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_HALTransportAudioWatch";

    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 0.1;
        diag_tickTime >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_PlayerTransportAuthorityReady",false]
            && {!isNil "ITW_CLASH_PlayerTransport_fnc_GetContract"}
            && {!isNil "ITW_AllyRadioMsg"}
        }
    };

    if (diag_tickTime >= _deadline) exitWith {
        ["bind-timeout",[]] call ITW_CLASH_HALTransportAudio_fnc_Log;
    };

    ITW_CLASH_HALTransportAudioReady = true;
    diag_log format [
        "CLASH BOOT | hal-transport-audio-ready | version=%1 passive=true nativeRadio=true soleExecutor=HAL_SCargo",
        ITW_CLASH_HALTransportAudioVersion
    ];

    while {!ITW_GameOver} do {
        {
            private _group = _x;
            private _contract = _group getVariable [
                "ITW_CLASH_PlayerTransportContract",createHashMap
            ];
            if !(_contract isEqualType createHashMap && {count _contract > 0}) then {continue};
            if ((_contract getOrDefault ["source",""]) != "HAL_SCargo") then {continue};

            private _contractId = _contract getOrDefault ["id",""];
            if (_contractId isEqualTo "") then {continue};
            private _carrier = _contract getOrDefault ["carrier",objNull];
            if (isNull _carrier) then {continue};

            private _trackedId = _group getVariable ["ITW_CLASH_HALTransportAudioContractId",""];
            if (_trackedId != _contractId) then {
                _group setVariable ["ITW_CLASH_HALTransportAudioContractId",_contractId];
                _group setVariable ["ITW_CLASH_HALTransportAudioBoardStart",false];
                _group setVariable ["ITW_CLASH_HALTransportAudioBoardEnd",false];
            };

            private _aliveUnits = units _group select {alive _x};
            if (_aliveUnits isEqualTo []) then {continue};

            private _boardStart = _group getVariable ["ITW_CLASH_HALTransportAudioBoardStart",false];
            private _boardEnd = _group getVariable ["ITW_CLASH_HALTransportAudioBoardEnd",false];
            private _assignedToCarrier = (_aliveUnits findIf {
                assignedVehicle _x == _carrier || {vehicle _x == _carrier}
            }) >= 0;
            private _state = _contract getOrDefault ["state",""];

            // HAL SCargo calls assignAsCargo only after the carrier has reached
            // the pickup phase. This is the passive equivalent of Impasse's
            // former bStart hook without issuing any GET IN command ourselves.
            if (!_boardStart && {_assignedToCarrier} && {_state == "HAL_ASSIGNED"}) then {
                [_group,_carrier,"BOARD_START",_contractId] call
                    ITW_CLASH_HALTransportAudio_fnc_Emit;
                _group setVariable ["ITW_CLASH_HALTransportAudioBoardStart",true];
                _boardStart = true;
            };

            // The transport observer marks EMBARKED from HAL's real physical
            // state. Emit the native completion cue once and do not alter HAL.
            if (!_boardEnd && {_state == "EMBARKED"}) then {
                [_group,_carrier,"BOARD_END",_contractId] call
                    ITW_CLASH_HALTransportAudio_fnc_Emit;
                _group setVariable ["ITW_CLASH_HALTransportAudioBoardEnd",true];
            };
        } forEach allGroups;

        sleep 0.5;
    };
};

true
