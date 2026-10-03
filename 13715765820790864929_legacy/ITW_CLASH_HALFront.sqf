#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_HALFrontStarted",false]) exitWith {true};
if (isNil "ITW_CLASH_Generation_fnc_Resolve" || {isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds"}) exitWith {
    diag_log "CLASH BOOT | WARNING | hal-front-generation-graph-missing | HAL answers threats anywhere on the map";
    false
};

ITW_CLASH_HALFrontStarted = true;
ITW_CLASH_HALFrontVersion = 2;
ITW_CLASH_HALFrontReady = false;

/*
    HAL front for both commanders.

    Each cycle HAL's dispatcher answers every known enemy on the map, so a far
    contact pulls squads off the objectives, and two commanders feed each other
    (the 2026-09-26 Agios Dionysios loop). HAL has a native front for this. With
    RydHQ_Front set on a commander, HAL itself:
      - ignores threats outside it (HAC_fnc.sqf:1485),
      - recalls squads whose target leaves it (HAC_fnc.sqf:2119),
      - fires artillery at the closest enemies inside it (HAC_fnc.sqf:4046).
    RydHQ_FrontA stays off, so HAL still knows every enemy, and the SF raid
    routine never reads the front: only special forces go deep.

    A side's front is the contested objectives, plus a margin, and by default
    nothing else.

    It used to span everything the side had in play - objectives, each one's
    forward FOB, the rear FOB behind it, and the side's own artillery - which
    made the box reach from the rear base to the front line and stop meaning
    much. Worse, it defeated the thing it was meant to leave alone: HAL's SF
    raid routine never reads the front (HAL/GoSFAttack.sqf contains no reference
    to it), so enemy special forces go deep whatever the front says, and they are
    artillery raiders above all. With our own artillery park inside our own
    front, our dispatcher answered a deep raid on it with the main force, and the
    raid stopped being a raid.

    Keeping it to the objectives means the dispatcher stays on the fight it is
    supposed to be having, our artillery shells what is at the objectives rather
    than distant contacts (HAC_fnc.sqf:4046 sorts known enemies by front
    membership), and a deep raid is a deep raid.

    The trade, worth knowing: HAL will not answer a threat to a FOB or an
    artillery position that falls outside the objectives plus the margin. Base
    and rear defence belongs to Impasse's garrisons and to C.L.A.S.H.'s anchor
    doctrine, not to the dispatcher. Each part can be switched back on
    independently, and widening ITW_CLASH_HALFrontMargin is the gentler dial if
    forward FOBs sit just outside.
*/

ITW_CLASH_HALFrontMargin = missionNamespace getVariable ["ITW_CLASH_HALFrontMargin",1500];
ITW_CLASH_HALFrontIncludeForward = missionNamespace getVariable ["ITW_CLASH_HALFrontIncludeForward",false];
ITW_CLASH_HALFrontIncludeRear = missionNamespace getVariable ["ITW_CLASH_HALFrontIncludeRear",false];
ITW_CLASH_HALFrontIncludeArtillery = missionNamespace getVariable ["ITW_CLASH_HALFrontIncludeArtillery",false];
ITW_CLASH_HALFrontPoll = missionNamespace getVariable ["ITW_CLASH_HALFrontPoll",30];
ITW_CLASH_HALFrontMarkers = missionNamespace getVariable ["ITW_CLASH_HALFrontMarkers",false];

ITW_CLASH_HALFront_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["hal-front-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH HAL FRONT | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_HALFront_fnc_Centroid = {
    params ["_points"];
    if (_points isEqualTo []) exitWith {[]};
    private _sumX = 0;
    private _sumY = 0;
    {
        _sumX = _sumX + (_x#0);
        _sumY = _sumY + (_x#1);
    } forEach _points;
    [_sumX / count _points,_sumY / count _points,0]
};

// [objectives, forward FOBs, rear FOBs, artillery] positions for this commander.
ITW_CLASH_HALFront_fnc_Points = {
    params ["_hq"];
    private _side = side _hq;
    private _objectives = [];
    private _forward = [];
    private _rear = [];
    {
        if (_x < 0 || {_x >= count ITW_Objectives}) then {continue};
        private _objectivePos = +(ITW_Objectives#_x#ITW_OBJ_POS);
        _objectives pushBack _objectivePos;
        if (ITW_CLASH_HALFrontIncludeForward || {ITW_CLASH_HALFrontIncludeRear}) then {
            private _graph = [_side,"FRONT","FORWARD",_objectivePos] call ITW_CLASH_Generation_fnc_Resolve;
            if ((_graph getOrDefault ["status",""]) == "RESOLVED") then {
                if (ITW_CLASH_HALFrontIncludeForward) then {
                    _forward pushBack (_graph getOrDefault ["forwardPosition",[]]);
                };
                if (ITW_CLASH_HALFrontIncludeRear) then {
                    _rear pushBack (_graph getOrDefault ["rearPosition",[]]);
                };
            };
        };
    } forEach (call ITW_CLASH_Generation_fnc_ActiveObjectiveIds);

    // Our own artillery is deliberately NOT a front anchor by default: enemy SF
    // ignore the front and come for it anyway, and pulling it inside means the
    // main force answers a deep raid that should have bitten.
    private _artillery = [];
    if (ITW_CLASH_HALFrontIncludeArtillery) then {
        {
            if (!isNull _x && {({alive _x} count units _x) > 0}) then {
                _artillery pushBack getPosATL (vehicle leader _x);
            };
        } forEach (_hq getVariable ["RydHQ_ArtG",[]]);
    };

    [_objectives,_forward select {_x isNotEqualTo []},_rear select {_x isNotEqualTo []},_artillery]
};

// [center, half width, half length, direction] of the rectangle along the axis
// from the rear anchor to the objectives that contains every point, plus margin.
ITW_CLASH_HALFront_fnc_Box = {
    params ["_objectives","_forward","_rear","_artillery"];
    private _to = [_objectives] call ITW_CLASH_HALFront_fnc_Centroid;
    private _from = [if (_rear isNotEqualTo []) then {_rear} else {_forward}] call ITW_CLASH_HALFront_fnc_Centroid;
    private _dir = if (_from isEqualTo [] || {(_from distance2D _to) < 1}) then {0} else {_from getDir _to};
    private _sin = sin _dir;
    private _cos = cos _dir;

    private _minU = 0;
    private _maxU = 0;
    private _minV = 0;
    private _maxV = 0;
    {
        private _dx = (_x#0) - (_to#0);
        private _dy = (_x#1) - (_to#1);
        private _u = _dx * _sin + _dy * _cos;
        private _v = _dx * _cos - _dy * _sin;
        _minU = _minU min _u;
        _maxU = _maxU max _u;
        _minV = _minV min _v;
        _maxV = _maxV max _v;
    } forEach (_objectives + _forward + _rear + _artillery);

    private _midU = (_minU + _maxU) / 2;
    private _midV = (_minV + _maxV) / 2;
    [
        [
            (_to#0) + _midU * _sin + _midV * _cos,
            (_to#1) + _midU * _cos - _midV * _sin,
            0
        ],
        (_maxV - _minV) / 2 + ITW_CLASH_HALFrontMargin,
        (_maxU - _minU) / 2 + ITW_CLASH_HALFrontMargin,
        _dir
    ]
};

ITW_CLASH_HALFront_fnc_Update = {
    params ["_hq"];
    if (isNull _hq) exitWith {false};
    private _points = [_hq] call ITW_CLASH_HALFront_fnc_Points;
    if ((_points#0) isEqualTo []) exitWith {false};

    (_points call ITW_CLASH_HALFront_fnc_Box) params ["_center","_halfWidth","_halfLength","_dir"];
    private _signature = [
        round ((_center#0) / 50),round ((_center#1) / 50),
        round (_halfWidth / 50),round (_halfLength / 50),round (_dir / 5)
    ];
    if (_signature isEqualTo (_hq getVariable ["ITW_CLASH_HALFrontSignature",[]])) exitWith {false};
    _hq setVariable ["ITW_CLASH_HALFrontSignature",_signature];

    private _front = _hq getVariable ["ITW_CLASH_HALFrontLocation",locationNull];
    if (isNull _front) then {
        _front = createLocation ["Invisible",_center,_halfWidth,_halfLength];
        _hq setVariable ["ITW_CLASH_HALFrontLocation",_front];
    } else {
        _front setPosition _center;
        _front setSize [_halfWidth,_halfLength];
    };
    _front setDirection _dir;
    _front setRectangular true;

    // Self-check with the engine's own `in`, the test HAL uses: if any point
    // the front was built from falls outside it, drop the front rather than
    // leash HAL away from its own objectives or assets.
    private _outside = ((_points#0) + (_points#1) + (_points#2) + (_points#3)) select {!(_x in _front)};
    if (_outside isNotEqualTo []) exitWith {
        _hq setVariable ["RydHQ_Front",locationNull];
        _hq setVariable ["ITW_CLASH_HALFrontSignature",[]];
        ["selfcheck-failed",[
            _hq getVariable ["RydHQ_CodeSign","?"],
            _center apply {round _x},round _halfWidth,round _halfLength,round _dir,
            _outside apply {[round (_x#0),round (_x#1)]}
        ]] call ITW_CLASH_HALFront_fnc_Log;
        false
    };
    _hq setVariable ["RydHQ_Front",_front];

    if (ITW_CLASH_HALFrontMarkers) then {
        private _marker = "ITW_CLASH_HALFront_" + (_hq getVariable ["RydHQ_CodeSign","X"]);
        if !(_marker in allMapMarkers) then {
            createMarker [_marker,_center];
            _marker setMarkerShape "RECTANGLE";
            _marker setMarkerBrush "Border";
            _marker setMarkerColor (switch (side _hq) do {
                case west: {"ColorBLUFOR"};
                case east: {"ColorOPFOR"};
                default {"ColorIndependent"};
            });
        };
        _marker setMarkerPos _center;
        _marker setMarkerSize [_halfWidth,_halfLength];
        _marker setMarkerDir _dir;
    };

    ["updated",[
        _hq getVariable ["RydHQ_CodeSign","?"],
        side _hq,
        _center apply {round _x},
        round _halfWidth,
        round _halfLength,
        round _dir,
        _points apply {count _x}
    ]] call ITW_CLASH_HALFront_fnc_Log;
    true
};

[] spawn {
    scriptName "ITW_CLASH_HALFront";
    // HAL's Front.sqf converts a trigger front to a location once at start
    // and would call triggerArea on ours, so wait for a commander's first
    // cycle, which comes after it.
    waitUntil {
        sleep 5;
        missionNamespace getVariable ["ITW_GameOver",false] || {
            ["ITW_CLASH_HALHQ","ITW_CLASH_BLUFORHQ"] findIf {
                private _hq = missionNamespace getVariable [_x,grpNull];
                !isNull _hq && {(_hq getVariable ["RydHQ_Cyclecount",0]) >= 1}
            } >= 0
        }
    };

    while {!(missionNamespace getVariable ["ITW_GameOver",false])} do {
        {
            private _hq = missionNamespace getVariable [_x,grpNull];
            if (!isNull _hq && {(_hq getVariable ["RydHQ_Cyclecount",0]) >= 1}) then {
                [_hq] call ITW_CLASH_HALFront_fnc_Update;
            };
        } forEach ["ITW_CLASH_HALHQ","ITW_CLASH_BLUFORHQ"];
        sleep ITW_CLASH_HALFrontPoll;
    };
};

ITW_CLASH_HALFrontReady = true;
diag_log format [
    "CLASH BOOT | hal-front-ready | version=%1 anchors=objectives margin=%2 includeForward=%3 includeRear=%4 includeArtillery=%5 poll=%6 markers=%7 dispatcherLeash=true sfIgnoresFront=true artilleryRaidable=true enemyKnowledgeKept=true",
    ITW_CLASH_HALFrontVersion,
    ITW_CLASH_HALFrontMargin,
    ITW_CLASH_HALFrontIncludeForward,
    ITW_CLASH_HALFrontIncludeRear,
    ITW_CLASH_HALFrontIncludeArtillery,
    ITW_CLASH_HALFrontPoll,
    ITW_CLASH_HALFrontMarkers
];
true
