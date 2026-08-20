#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_GTFOBookkeepingVersion = 1;

/*
    GTFO does not cancel HAL tactics. This patch removes only stale task-list
    metadata left by the job the squad was doing before HAL declared it
    exhausted. In particular, a rearward GoRest waypoint must never be mistaken
    by C.L.A.S.H.'s objective-allocation auditor for a drifting defensive order.
*/

ITW_CLASH_GTFO_fnc_RetirePreviousTaskState = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    private _wasDefending = _group getVariable ["Defending",false];
    _group setVariable ["Defending",false];

    private _removedFrom = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        {
            private _listName = _x;
            private _before = +(ITW_CLASH_HALHQ getVariable [_listName,[]]);
            if (_group in _before) then {
                ITW_CLASH_HALHQ setVariable [_listName,_before - [_group]];
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
        call ITW_CLASH_GTFO_fnc_ApplyConstraints;
    };
    _result
};

diag_log format [
    "CLASH BOOT | gtfo-bookkeeping-ready | version=%1 staleDefenseRetire=true tacticalWrites=false",
    ITW_CLASH_GTFOBookkeepingVersion
];

true
