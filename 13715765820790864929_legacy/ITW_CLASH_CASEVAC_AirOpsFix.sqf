#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_CASEVAC_AirOpsFixStarted",false]) exitWith {};
ITW_CLASH_CASEVAC_AirOpsFixStarted = true;
ITW_CLASH_CASEVAC_AirOpsFixVersion = 1;

// CASEVAC itself is loaded asynchronously. Wait for the function surface before
// correcting two pre-live issues found during the top-down audit:
// 1) SpawnHeli used the same local-result + breakOut pattern that caused the
//    reconstitution dispatcher nil-return bug.
// 2) the extraction coroutine had landing-distance checks but no explicit
//    inbound waypoint telling the helicopter to fly to the LZ.
waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_CASEVAC_fnc_SpawnHeli" && {
        !isNil "ITW_CLASH_CASEVAC_fnc_RunExtraction" && {
            !isNil "ITW_CLASH_CASEVAC_fnc_Log"
        }
    }
};

ITW_CLASH_CASEVAC_fnc_SpawnHeli = {
    params ["_seatCount","_spawnInfo"];
    if (_spawnInfo isEqualTo []) exitWith {[]};
    if (isNil "ITW_AtkReconstitutionTransportContext") exitWith {[]};
    if (ITW_AtkReconstitutionTransportContext isEqualTo []) exitWith {[]};

    ITW_AtkReconstitutionTransportContext params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (!isNil "ITW_EnemySide" && {_side != ITW_EnemySide}) exitWith {[]};

    private _candidates = (_transport + _dualVeh) select {
        (_x#ITW_VEH_TYPE) == ITW_TYPE_VEH_HELI && {
            (_x#ITW_VEH_REQD_TICKETS) <= (_x#ITW_VEH_CURR_TICKETS) && {
                (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT || {
                    (_x#ITW_VEH_COUNT) < (_x#ITW_VEH_MAX)
                }
            }
        }
    };
    if (_candidates isEqualTo []) exitWith {[]};

    private _pureTransport = _candidates select {
        (_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT
    };
    private _ordered = _pureTransport + (_candidates - _pureTransport);
    _spawnInfo params ["_spawnPos","_baseIndex","_spawnSource"];

    private _result = [];
    for "_candidateIndex" from 0 to ((count _ordered) - 1) do {
        if (_result isNotEqualTo []) then {continue};

        private _vehDef = _ordered#_candidateIndex;
        private _heli = [
            _vehDef,_crewTypes,_unitTypes,_side,_spawnPos
        ] call ITW_AtkSpawnVeh;
        if (isNull _heli) then {continue};

        private _crewGroup = group driver _heli;
        if !(_heli isKindOf "Helicopter") then {
            deleteVehicleCrew _heli;
            deleteVehicle _heli;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        if ((_heli emptyPositions "cargo") < _seatCount) then {
            deleteVehicleCrew _heli;
            deleteVehicle _heli;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _heli setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        _heli setVariable ["ITW_CLASH_CASEVAC",true,true];
        _crewGroup setVariable ["ITW_CLASH_CASEVAC",true];
        _crewGroup setVariable ["noHeadless",true];
        _crewGroup allowFleeing 0;
        _crewGroup enableAttack false;
        _crewGroup setBehaviourStrong "CARELESS";
        _crewGroup setCombatMode "BLUE";
        _crewGroup setSpeedMode "FULL";
        _heli flyInHeight 50;
        _heli limitSpeed 250;

        if (!isNil "ITW_AtkVehRemoveMagazines") then {
            [_heli] remoteExec ["ITW_AtkVehRemoveMagazines",_heli];
        };
        ALLOW_DAMAGE(_heli,true);
        {ALLOW_DAMAGE(_x,true)} forEach crew _heli;
        {_x addCuratorEditableObjects [[_heli] + units _crewGroup,true]} forEach allCurators;

        _result = [_heli,_crewGroup,_vehDef,_baseIndex,_spawnSource,+_spawnPos];
    };

    if (_result isNotEqualTo []) then {
        ["spawn-selected",[
            typeOf (_result#0),
            _baseIndex,
            _spawnSource,
            _seatCount
        ]] call ITW_CLASH_CASEVAC_fnc_Log;
    };
    _result
};

ITW_CLASH_CASEVAC_fnc_OrderHeliLZ = {
    params ["_heli","_crewGroup","_lz"];
    if (isNull _heli || {!alive _heli} || {isNull _crewGroup} || {_lz isEqualTo []}) exitWith {false};

    {deleteWaypoint _x} forEachReversed waypoints _crewGroup;
    _crewGroup enableAttack false;
    _crewGroup setBehaviourStrong "CARELESS";
    _crewGroup setCombatMode "BLUE";
    _crewGroup setSpeedMode "FULL";
    _heli land "NONE";
    _heli flyInHeight 50;
    _heli limitSpeed 250;

    private _wp = _crewGroup addWaypoint [_lz,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointBehaviour "CARELESS";
    _wp setWaypointCombatMode "BLUE";
    _wp setWaypointCompletionRadius 80;

    ["inbound-route",[
        typeOf _heli,
        _lz,
        round (_heli distance2D _lz)
    ]] call ITW_CLASH_CASEVAC_fnc_Log;
    true
};

ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base = ITW_CLASH_CASEVAC_fnc_RunExtraction;
ITW_CLASH_CASEVAC_fnc_RunExtraction = {
    params [
        "_id","_group","_heli","_crewGroup","_lz","_returnPos",
        "_originalObjective","_egressObjective","_archetype","_lineage","_startedAt"
    ];

    private _routed = [
        _heli,_crewGroup,_lz
    ] call ITW_CLASH_CASEVAC_fnc_OrderHeliLZ;
    if (!_routed) exitWith {
        [
            _id,_group,"inbound-route-failed",_heli,_crewGroup,_returnPos
        ] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
    };

    _this call ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base
};

diag_log format [
    "CLASH BOOT | casevac-air-ops-fix-ready | version=%1 explicitLZ=true",
    ITW_CLASH_CASEVAC_AirOpsFixVersion
];
