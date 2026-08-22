#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_CASEVAC_LZPadFixStarted",false]) exitWith {};
ITW_CLASH_CASEVAC_LZPadFixStarted = true;
ITW_CLASH_CASEVAC_LZPadFixVersion = 2;
ITW_CLASH_CASEVAC_InfantryRallyOffset = 30;

waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_CASEVAC_AirOpsFixVersion" && {
        !isNil "ITW_CLASH_CASEVAC_fnc_OrderHeliLZ" && {
            !isNil "ITW_CLASH_CASEVAC_fnc_OrderLZ" && {
                !isNil "ITW_CLASH_CASEVAC_fnc_Log"
            }
        }
    }
};

ITW_CLASH_CASEVAC_fnc_OrderLZ_V1Base = ITW_CLASH_CASEVAC_fnc_OrderLZ;
ITW_CLASH_CASEVAC_fnc_OrderHeliLZ_V1Base = ITW_CLASH_CASEVAC_fnc_OrderHeliLZ;

ITW_CLASH_CASEVAC_fnc_OrderLZ = {
    params ["_group","_lz"];
    if (isNull _group || {_lz isEqualTo []}) exitWith {false};

    private _oldPad = _group getVariable ["ITW_CLASH_CASEVAC_LZPad",objNull];
    if (!isNull _oldPad) then {deleteVehicle _oldPad};

    private _pad = createVehicle ["Land_HelipadEmpty_F",_lz,[],0,"CAN_COLLIDE"];
    if (isNull _pad) exitWith {[_group,_lz] call ITW_CLASH_CASEVAC_fnc_OrderLZ_V1Base};
    _pad setPosATL _lz;

    private _heli = _group getVariable ["ITW_CLASH_CASEVAC_Heli",objNull];
    _group setVariable ["ITW_CLASH_CASEVAC_LZPad",_pad];
    if (!isNull _heli) then {
        _heli setVariable ["ITW_CLASH_CASEVAC_LZPad",_pad];
        _heli setVariable ["ITW_CLASH_CASEVAC_Group",_group];
    };

    private _leaderPos = getPosATL leader _group;
    private _rallyBearing = _lz getDir _leaderPos;
    private _rally = _lz getPos [ITW_CLASH_CASEVAC_InfantryRallyOffset,_rallyBearing];
    if (count _rally < 3) then {_rally pushBack 0};
    _rally set [2,0];
    _group setVariable ["ITW_CLASH_CASEVAC_Rally",+_rally];

    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "AWARE";
    _group setSpeedMode "FULL";

    private _wp = _group addWaypoint [_rally,8];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 8;

    ["lz-pad-created",[
        [_group] call ITW_CLASH_fnc_GroupId,_lz,_rally,
        ITW_CLASH_CASEVAC_InfantryRallyOffset
    ]] call ITW_CLASH_CASEVAC_fnc_Log;
    true
};

ITW_CLASH_CASEVAC_fnc_OrderHeliLZ = {
    params ["_heli","_crewGroup","_lz"];
    private _routed = [_heli,_crewGroup,_lz] call ITW_CLASH_CASEVAC_fnc_OrderHeliLZ_V1Base;
    if (!_routed || {isNull _heli} || {!alive _heli}) exitWith {_routed};

    private _pad = _heli getVariable ["ITW_CLASH_CASEVAC_LZPad",objNull];
    if (isNull _pad) exitWith {_routed};

    private _wait = ITW_CLASH_CASEVAC_BoardingTimeout + 30;
    private _accepted = _heli landAt [_pad,"GetIn",_wait,true];
    ["lz-pad-landat",[typeOf _heli,getPosATL _pad,_accepted,_wait]] call ITW_CLASH_CASEVAC_fnc_Log;

    if !(_heli getVariable ["ITW_CLASH_CASEVAC_LZPadPinStarted",false]) then {
        _heli setVariable ["ITW_CLASH_CASEVAC_LZPadPinStarted",true];
        [_heli,_pad] spawn {
            params ["_heli","_pad"];
            private _successLogged = false;
            while {!isNull _heli && {alive _heli} && {!isNull _pad}} do {
                private _group = _heli getVariable ["ITW_CLASH_CASEVAC_Group",grpNull];
                if (isNull _group) exitWith {};
                private _state = _group getVariable ["ITW_CLASH_CASEVAC_State",""];

                // Keep Arma's landing target alive throughout physical boarding.
                // V1 deleted the pad as soon as state changed from inbound to
                // boarding, even though survivors were still walking/getting in.
                if !(_state in ["inbound","boarding"]) exitWith {};

                if (_heli distance2D _pad <= 650) then {
                    private _wait = ITW_CLASH_CASEVAC_BoardingTimeout + 30;
                    private _ok = _heli landAt [_pad,"GetIn",_wait,true];
                    if (_ok && {!_successLogged}) then {
                        _successLogged = true;
                        ["lz-pad-locked",[
                            [_group] call ITW_CLASH_fnc_GroupId,
                            typeOf _heli,getPosATL _pad,
                            round (_heli distance2D _pad)
                        ]] call ITW_CLASH_CASEVAC_fnc_Log;
                    };
                };
                sleep 2;
            };

            private _group = if (isNull _heli) then {grpNull} else {
                _heli getVariable ["ITW_CLASH_CASEVAC_Group",grpNull]
            };
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_CASEVAC_LZPad",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_Rally",nil];
            };
            if (!isNull _heli) then {
                _heli setVariable ["ITW_CLASH_CASEVAC_LZPad",nil];
                _heli setVariable ["ITW_CLASH_CASEVAC_LZPadPinStarted",nil];
                _heli setVariable ["ITW_CLASH_CASEVAC_Group",nil];
            };
            if (!isNull _pad) then {deleteVehicle _pad};
        };
    };

    _routed
};

diag_log format [
    "CLASH BOOT | casevac-lz-pad-fix-ready | version=%1 infantryOffset=%2 pinStates=inbound+boarding",
    ITW_CLASH_CASEVAC_LZPadFixVersion,
    ITW_CLASH_CASEVAC_InfantryRallyOffset
];
