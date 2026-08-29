#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_GTFOBookkeepingVersion = 3;

/*
    GTFO does not cancel HAL tactics. This patch removes only stale task-list
    metadata left by the job the squad was doing before HAL declared it
    exhausted. It also publishes the active objective's forward FOB as HAL's
    Withdrawal Rally Point so combat-ineffective formations physically leave
    the line through the same node where Impasse reconstitutes them.
*/

ITW_CLASH_GTFO_fnc_RetirePreviousTaskState = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    private _wasDefending = _group getVariable ["Defending",false];
    _group setVariable ["Defending",false];

    private _removedFrom = [];
    private _hq = if (
        isNil "ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup"
    ) then {
        grpNull
    } else {
        [_group] call ITW_CLASH_CommanderParity_fnc_GetCommanderForGroup
    };
    if (!isNull _hq) then {
        {
            private _listName = _x;
            private _before = +(_hq getVariable [_listName,[]]);
            if (_group in _before) then {
                _hq setVariable [_listName,_before - [_group]];
                _removedFrom pushBack _listName;
            };
        } forEach [
            "RydHQ_DefSpot",
            "RydHQ_Def",
            "RydHQ_DefRes",
            "RydHQ_RecDefSpot"
        ];
    };

    if (_wasDefending || {_removedFrom isNotEqualTo []}) then {
        ["task-state-retired",[
            [_group] call ITW_CLASH_fnc_GroupId,
            _wasDefending,
            _removedFrom
        ]] call ITW_CLASH_GTFO_fnc_Log;
    };
    true
};

// Replace only the strategic rally-point source. HAL_GoRest still owns the
// tactical route, smoke, local avoidance and actual withdrawal movement.
ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase = ITW_CLASH_GTFO_fnc_RefreshCorridor;
ITW_CLASH_GTFO_fnc_RefreshCorridor = {
    if (isNil "ITW_CLASH_fnc_GetActiveObjectives" || {
        isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn"
    }) exitWith {
        call ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase
    };

    private _side = missionNamespace getVariable ["ITW_EnemySide",sideUnknown];
    if (_side == sideUnknown) exitWith {
        call ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase
    };

    private _corridors = [];
    {
        private _objectiveIndex = _x#0;
        private _forward = [
            _objectiveIndex,_side
        ] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
        if (_forward isEqualTo [] || {(_forward#0) isEqualTo []}) then {continue};
        _corridors pushBack [
            _objectiveIndex,
            +(_forward#0),
            _forward#2,
            _forward#3
        ];
    } forEach (call ITW_CLASH_fnc_GetActiveObjectives);

    if (_corridors isEqualTo []) exitWith {
        call ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase
    };

    // HAL exposes one Withdrawal Rally Point per commander. Prefer the current
    // command objective's forward FOB; otherwise use the first active route.
    private _preferredObjective = missionNamespace getVariable [
        "ITW_CLASH_CommanderObjective",-1
    ];
    private _selectedIndex = _corridors findIf {(_x#0) == _preferredObjective};
    if (_selectedIndex < 0) then {_selectedIndex = 0};
    private _selected = _corridors#_selectedIndex;
    _selected params ["_objectiveIndex","_position","_source","_baseIndex"];

    ITW_CLASH_GTFO_Corridor = [+_position,_objectiveIndex,_source,_baseIndex];

    if (isNull ITW_CLASH_GTFO_RestDecoy) then {
        ITW_CLASH_GTFO_RestDecoy = createVehicle [
            "Land_HelipadEmpty_F",_position,[],0,"CAN_COLLIDE"
        ];
    };
    if (!isNull ITW_CLASH_GTFO_RestDecoy) then {
        ITW_CLASH_GTFO_RestDecoy setPosATL _position;
    };
    if (!isNull ITW_CLASH_HALHQ && {!isNull ITW_CLASH_GTFO_RestDecoy}) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_RestDecoy",ITW_CLASH_GTFO_RestDecoy];
        ITW_CLASH_HALHQ setVariable ["RydHQ_RDChance",100];
    };

    private _baseIndices = [];
    {_baseIndices pushBackUnique (_x#3)} forEach _corridors;
    private _signature = str [
        _objectiveIndex,_baseIndex,_source,
        _corridors apply {[_x#0,_x#2,_x#3]}
    ];
    if (_signature != ITW_CLASH_GTFO_CorridorSignature) then {
        ITW_CLASH_GTFO_CorridorSignature = _signature;
        ["forward-fob-corridor",[
            _objectiveIndex,_baseIndex,_source,_position,
            _corridors apply {[_x#0,_x#2,_x#3]}
        ]] call ITW_CLASH_GTFO_fnc_Log;
        if ((count _baseIndices) > 1) then {
            ["corridor-divergence",[
                _objectiveIndex,_baseIndex,_corridors
            ]] call ITW_CLASH_GTFO_fnc_Log;
        };
    };

    ITW_CLASH_GTFO_Corridor
};

if (!isNil "SKL_fnc_CompileFinal") then {
    ["ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase"] call SKL_fnc_CompileFinal;
};

ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase = ITW_CLASH_fnc_StartWithdrawal;
ITW_CLASH_fnc_StartWithdrawal = {
    private _group = _this param [0,grpNull];
    private _result = _this call ITW_CLASH_fnc_StartWithdrawal_GTFOStateBase;

    // Do this only after the GTFO transition succeeds. No waypoint, combat mode,
    // behaviour, attack state, Break flag or HAL GoRest state is touched here.
    if (_result && {!isNull _group} && {
        _group getVariable ["ITW_CLASH_GTFO",false]
    }) then {
        [_group] call ITW_CLASH_GTFO_fnc_RetirePreviousTaskState;
        if (!isNil "ITW_CLASH_GTFO_fnc_SetPersistentConstraints") then {
            [_group,true] call ITW_CLASH_GTFO_fnc_SetPersistentConstraints;
        };
        if (
            !isNil "ITW_EnemySide"
            && {side _group == ITW_EnemySide}
        ) then {
            call ITW_CLASH_GTFO_fnc_ApplyConstraints;
        };
    };
    _result
};

diag_log format [
    "CLASH BOOT | gtfo-bookkeeping-ready | version=%1 staleDefenseRetire=true commanderAware=true symmetricCommanderFallback=true forwardFOB=true tacticalWrites=false",
    ITW_CLASH_GTFOBookkeepingVersion
];

true