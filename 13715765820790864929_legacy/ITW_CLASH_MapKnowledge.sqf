#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_MapKnowledgeStarted",false]) exitWith {true};

ITW_CLASH_MapKnowledgeStarted = true;
ITW_CLASH_MapKnowledgeVersion = 1;

/*
    The players' map, drawn by Impasse from what their HAL commander knows.

    Hark, 2026-10-17: "can we untick HAL's [Info Markers] and leave Impasse's
    by default on, but can we wire HAL's knows about to Impasse's".

    Two things drew enemies on the players' map:
      - Impasse (ITW_Radio.sqf, ITW_RadioShowFriendlies, on by default with
        ShowEnemyOnMap): an enemy group when the players' side knowsAbout its
        leader's vehicle at 1 or more.
      - HAL's Info Markers for the players' commander, turned on earlier the
        same day (ITW_CLASH_PlayerInfoMarkers): every group in its
        RydHQ_KnEnemiesG, as a second, global set of markers.
    HAL's are now off by default (ITW_CLASH_DualHALCheckbook.sqf) and
    Impasse's read HAL's list: an enemy group is drawn when the players'
    commander knows of it. This file publishes that list to every machine
    (ITW_CLASH_MapKnownEnemyGroups); without it Impasse falls back to its own
    knowsAbout test.

    HAL rebuilds the list every cycle (HAC_fnc2.sqf, RYD_StatusQuo): it is
    emptied at the start and filled again further down, so a read in between
    sees nothing. An empty read after a full one is only published once it
    has stayed empty for EmptyHold seconds, so the markers do not blink out
    once a cycle.

    Positions are the group's live position, as HAL's markers were: HAL keeps
    a group while anyone's knowsAbout on one of its men is 0.05 or more, and
    that decays slowly, so a group seen once is shown where it is for a while
    after (the knowledge layer's own header has the detail).
*/

ITW_CLASH_MapKnowledgeEnabled = missionNamespace getVariable ["ITW_CLASH_MapKnowledgeEnabled",true];
ITW_CLASH_MapKnowledgePoll = missionNamespace getVariable ["ITW_CLASH_MapKnowledgePoll",5];
ITW_CLASH_MapKnowledgeEmptyHold = missionNamespace getVariable ["ITW_CLASH_MapKnowledgeEmptyHold",15];
ITW_CLASH_MapKnowledgeLogEvery = missionNamespace getVariable ["ITW_CLASH_MapKnowledgeLogEvery",60];

ITW_CLASH_MapKnowledge_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["map-knowledge-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH MAP KNOWLEDGE | %1 | %2",_event,_payload];
    };
};

// The enemy groups this side's HAL commander knows of, alive, as HAL has them.
ITW_CLASH_MapKnowledge_fnc_Known = {
    params ["_side"];
    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
        [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    if (isNull _hq) exitWith {[]};
    (_hq getVariable ["RydHQ_KnEnemiesG",[]]) select {
        _x isEqualType grpNull
        && {!isNull _x}
        && {(side _x) isNotEqualTo _side}
        && {((units _x) findIf {alive _x}) >= 0}
    }
};

// Same groups, whatever the order HAL put them in.
ITW_CLASH_MapKnowledge_fnc_Same = {
    params ["_a","_b"];
    ((_a - _b) isEqualTo []) && {(_b - _a) isEqualTo []}
};

missionNamespace setVariable ["ITW_CLASH_MapKnownEnemyGroups",[],true];

if (ITW_CLASH_MapKnowledgeEnabled) then {
    [] spawn {
        scriptName "ITW_CLASH_MapKnowledge";
        waitUntil {
            sleep 1;
            !isNil "ITW_PlayerSide" || {missionNamespace getVariable ["ITW_GameOver",false]}
        };
        private _published = [];
        private _emptySince = -1;
        private _loggedAt = -1e10;
        while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
            private _known = [ITW_PlayerSide] call ITW_CLASH_MapKnowledge_fnc_Known;
            private _held = false;
            if (_known isEqualTo [] && {_published isNotEqualTo []}) then {
                if (_emptySince < 0) then {_emptySince = time};
                if ((time - _emptySince) < ITW_CLASH_MapKnowledgeEmptyHold) then {
                    _held = true;
                    _known = _published select {!isNull _x && {((units _x) findIf {alive _x}) >= 0}};
                };
            } else {
                _emptySince = -1;
            };
            if !([_known,_published] call ITW_CLASH_MapKnowledge_fnc_Same) then {
                _published = +_known;
                missionNamespace setVariable ["ITW_CLASH_MapKnownEnemyGroups",_published,true];
            };
            if ((time - _loggedAt) >= ITW_CLASH_MapKnowledgeLogEvery) then {
                _loggedAt = time;
                ["published",[toUpperANSI str ITW_PlayerSide,count _published,_held]] call ITW_CLASH_MapKnowledge_fnc_Log;
            };
            sleep ITW_CLASH_MapKnowledgePoll;
        };
    };
};

diag_log format [
    "CLASH BOOT | map-knowledge-ready | version=%1 enabled=%2 source=RydHQ_KnEnemiesG side=players drawnBy=impasse halInfoMarkers=%3 poll=%4s emptyHold=%5s livePositions=true",
    ITW_CLASH_MapKnowledgeVersion,
    ITW_CLASH_MapKnowledgeEnabled,
    missionNamespace getVariable ["ITW_CLASH_PlayerInfoMarkers",false],
    ITW_CLASH_MapKnowledgePoll,
    ITW_CLASH_MapKnowledgeEmptyHold
];
true
