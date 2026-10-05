#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_FrontRoutingStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_FrontRoutingReady",false]
};

ITW_CLASH_FrontRoutingStarted = true;
ITW_CLASH_FrontRoutingReady = false;
ITW_CLASH_FrontRoutingVersion = 1;

/*
    Front Routing Phase 0

    This is the commander-facing operational FOB selector for both sides.

    Scope:
      - Impasse remains authoritative for the campaign/base graph.
      - C.L.A.S.H. derives one primary and zero-or-more alternate FOB lanes for
        each active objective from the live side-specific attack-source graph.
      - HAL's commander receives the selected operational source as strategic
        context only. Phase 0 is SHADOW ONLY: it does not spawn, move, teleport,
        waypoint, or retask a formation.
      - Selection is sticky. A current lane remains selected until it becomes
        INTERDICTED or disappears from the live graph. This prevents route
        oscillation when route-health evidence is added later.
      - Route health is an explicit API surface now, but Phase 0 does not infer
        threat pressure itself. Later hosted evidence will feed HAL-known threat
        and observed delivery/loss outcomes into this surface.

    Initial objective population is intentionally untouched. Native Impasse
    owns the opening battlefield seed. Front routing applies to later force flow.
*/

ITW_CLASH_FrontRoutingShadowMode = true;
ITW_CLASH_FrontRoutingPoll = missionNamespace getVariable [
    "ITW_CLASH_FrontRoutingPoll",10
];
ITW_CLASH_FrontRoutingAlternateDistanceFactor = missionNamespace getVariable [
    "ITW_CLASH_FrontRoutingAlternateDistanceFactor",2
];
ITW_CLASH_FrontRoutingAlternateExtraDistance = missionNamespace getVariable [
    "ITW_CLASH_FrontRoutingAlternateExtraDistance",2500
];

ITW_CLASH_FrontRoutingRoutes = createHashMap;
ITW_CLASH_FrontRoutingSelections = createHashMap;
ITW_CLASH_FrontRoutingSignatures = createHashMap;

ITW_CLASH_FrontRouting_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["front-routing-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH FRONT ROUTING | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_FrontRouting_fnc_SideToken = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_FrontRouting_fnc_FrontId = {
    params ["_side","_objectiveIndex"];
    format [
        "%1|OBJ%2",
        [_side] call ITW_CLASH_FrontRouting_fnc_SideToken,
        _objectiveIndex
    ]
};

ITW_CLASH_FrontRouting_fnc_RouteId = {
    params ["_side","_baseIndex","_objectiveIndex"];
    format [
        "%1|B%2|OBJ%3",
        [_side] call ITW_CLASH_FrontRouting_fnc_SideToken,
        _baseIndex,
        _objectiveIndex
    ]
};

ITW_CLASH_FrontRouting_fnc_LandSlotForSide = {
    params ["_side"];
    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"}) exitWith {-1};
    if (_side == ITW_PlayerSide) exitWith {ITW_ATTACK_LAND_F};
    if (_side == ITW_EnemySide) exitWith {ITW_ATTACK_LAND_E};
    -1
};

ITW_CLASH_FrontRouting_fnc_ActiveObjectives = {
    if (!isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds") exitWith {
        call ITW_CLASH_Generation_fnc_ActiveObjectiveIds
    };
    if (isNil "ITW_Zones" || {isNil "ITW_ZoneIndex"} || {
        ITW_ZoneIndex < 0 || {ITW_ZoneIndex >= count ITW_Zones}
    }) exitWith {[]};
    +(ITW_Zones#ITW_ZoneIndex)
};

ITW_CLASH_FrontRouting_fnc_ForwardBase = {
    params ["_side","_objectiveIndex"];
    if (isNil "ITW_Objectives" || {
        _objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}
    }) exitWith {-1};

    private _slot = [_side] call ITW_CLASH_FrontRouting_fnc_LandSlotForSide;
    if (_slot < 0) exitWith {-1};

    private _attacks = (ITW_Objectives#_objectiveIndex)#ITW_OBJ_ATTACKS;
    if (_slot >= count _attacks) exitWith {-1};
    private _baseIndex = _attacks#_slot;
    if (isNil "ITW_Bases" || {_baseIndex < 0} || {_baseIndex >= count ITW_Bases}) exitWith {-1};
    _baseIndex
};

ITW_CLASH_FrontRouting_fnc_BasePosition = {
    params ["_baseIndex"];
    if (!isNil "ITW_CLASH_Generation_fnc_BaseSpawn") exitWith {
        [_baseIndex,false] call ITW_CLASH_Generation_fnc_BaseSpawn
    };
    if (isNil "ITW_Bases" || {_baseIndex < 0} || {_baseIndex >= count ITW_Bases}) exitWith {[]};
    private _position = +(ITW_Bases#_baseIndex#ITW_BASE_A_SPAWN);
    if (_position isEqualTo []) then {_position = +(ITW_Bases#_baseIndex#ITW_BASE_POS)};
    if (_position isNotEqualTo [] && {count _position < 3}) then {_position pushBack 0};
    _position
};

ITW_CLASH_FrontRouting_fnc_StateSeverity = {
    params [["_state","HEALTHY"]];
    switch (toUpperANSI _state) do {
        case "CONTESTED": {1};
        case "DEGRADED": {2};
        case "INTERDICTED": {3};
        default {0};
    }
};

ITW_CLASH_FrontRouting_fnc_GetRouteState = {
    params ["_routeId"];
    private _entry = ITW_CLASH_FrontRoutingRoutes getOrDefault [_routeId,createHashMap];
    if (count _entry == 0) exitWith {"HEALTHY"};
    toUpperANSI (_entry getOrDefault ["state","HEALTHY"])
};

ITW_CLASH_FrontRouting_fnc_SetRouteState = {
    params ["_side","_baseIndex","_objectiveIndex",["_state","HEALTHY"],["_reason","manual"]];
    _state = toUpperANSI _state;
    if !(_state in ["HEALTHY","CONTESTED","DEGRADED","INTERDICTED"]) exitWith {false};

    private _routeId = [
        _side,_baseIndex,_objectiveIndex
    ] call ITW_CLASH_FrontRouting_fnc_RouteId;
    private _previous = [_routeId] call ITW_CLASH_FrontRouting_fnc_GetRouteState;
    private _entry = ITW_CLASH_FrontRoutingRoutes getOrDefault [_routeId,createHashMap];
    if (count _entry == 0) then {
        _entry = createHashMapFromArray [
            ["routeId",_routeId],
            ["side",_side],
            ["baseIndex",_baseIndex],
            ["objective",_objectiveIndex],
            ["createdAt",time]
        ];
    };
    _entry set ["state",_state];
    _entry set ["reason",_reason];
    _entry set ["changedAt",time];
    ITW_CLASH_FrontRoutingRoutes set [_routeId,_entry];

    if (_previous != _state) then {
        ["route-state",[
            _routeId,_previous,_state,_reason
        ]] call ITW_CLASH_FrontRouting_fnc_Log;
    };
    true
};

ITW_CLASH_FrontRouting_fnc_Candidates = {
    params ["_side","_objectiveIndex"];
    if (isNil "ITW_Objectives" || {
        _objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}
    }) exitWith {[]};

    private _primaryBase = [
        _side,_objectiveIndex
    ] call ITW_CLASH_FrontRouting_fnc_ForwardBase;
    if (_primaryBase < 0) exitWith {[]};

    private _objectivePos = +(ITW_Objectives#_objectiveIndex#ITW_OBJ_POS);
    private _primaryPos = [_primaryBase] call ITW_CLASH_FrontRouting_fnc_BasePosition;
    if (_primaryPos isEqualTo []) exitWith {[]};
    private _primaryDistance = _primaryPos distance2D _objectivePos;
    private _maxDistance = (
        _primaryDistance * ITW_CLASH_FrontRoutingAlternateDistanceFactor
    ) max (
        _primaryDistance + ITW_CLASH_FrontRoutingAlternateExtraDistance
    );

    // The requested objective's native attack-source FOB is always first.
    // Other side-specific FOBs serving this active zone are legitimate
    // alternate frontal bases if they are not geometrically absurd.
    private _baseIndices = [_primaryBase];
    {
        private _candidateBase = [
            _side,_x
        ] call ITW_CLASH_FrontRouting_fnc_ForwardBase;
        if (_candidateBase >= 0) then {
            _baseIndices pushBackUnique _candidateBase;
        };
    } forEach (call ITW_CLASH_FrontRouting_fnc_ActiveObjectives);

    private _candidates = [];
    {
        private _baseIndex = _x;
        private _position = [_baseIndex] call ITW_CLASH_FrontRouting_fnc_BasePosition;
        if (_position isEqualTo []) then {continue};
        private _distance = _position distance2D _objectivePos;
        if (_baseIndex != _primaryBase && {_distance > _maxDistance}) then {continue};

        private _routeId = [
            _side,_baseIndex,_objectiveIndex
        ] call ITW_CLASH_FrontRouting_fnc_RouteId;
        private _state = [_routeId] call ITW_CLASH_FrontRouting_fnc_GetRouteState;
        _candidates pushBack createHashMapFromArray [
            ["routeId",_routeId],
            ["baseIndex",_baseIndex],
            ["position",+_position],
            ["distance",_distance],
            ["state",_state],
            ["severity",[_state] call ITW_CLASH_FrontRouting_fnc_StateSeverity],
            ["primary",_baseIndex == _primaryBase]
        ];
    } forEach _baseIndices;
    _candidates
};

ITW_CLASH_FrontRouting_fnc_SelectCandidate = {
    params ["_frontId","_candidates"];
    if (_candidates isEqualTo []) exitWith {createHashMap};

    private _previous = ITW_CLASH_FrontRoutingSelections getOrDefault [
        _frontId,createHashMap
    ];
    private _selectedBefore = _previous getOrDefault ["selectedBase",-1];

    // Sticky selection: keep the commander's present lane unless it has become
    // physically invalid or explicitly INTERDICTED.
    if (_selectedBefore >= 0) then {
        private _existingIndex = _candidates findIf {
            (_x getOrDefault ["baseIndex",-1]) == _selectedBefore
        };
        if (_existingIndex >= 0) then {
            private _existing = _candidates#_existingIndex;
            if ((_existing getOrDefault ["state","HEALTHY"]) != "INTERDICTED") exitWith {
                _existing
            };
        };
    };

    // No viable sticky lane. Prefer the lowest route-health severity, then
    // shortest operational distance. The native primary wins equal-distance
    // ties because it is inserted first.
    private _best = _candidates#0;
    private _bestSeverity = _best getOrDefault ["severity",0];
    private _bestDistance = _best getOrDefault ["distance",1e12];
    {
        private _severity = _x getOrDefault ["severity",0];
        private _distance = _x getOrDefault ["distance",1e12];
        if (_severity < _bestSeverity || {
            _severity == _bestSeverity && {_distance < _bestDistance}
        }) then {
            _best = _x;
            _bestSeverity = _severity;
            _bestDistance = _distance;
        };
    } forEach _candidates;
    _best
};

ITW_CLASH_FrontRouting_fnc_PublishCommanderSelection = {
    params ["_side","_objectiveIndex","_selection"];
    if (count _selection == 0 || {
        isNil "ITW_CLASH_CommanderParity_fnc_GetCommanderForSide"
    }) exitWith {false};

    private _hq = [
        _side
    ] call ITW_CLASH_CommanderParity_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {false};

    private _published = _hq getVariable [
        "ITW_CLASH_FrontRoutingSelections",createHashMap
    ];
    _published set [str _objectiveIndex,_selection];
    _hq setVariable ["ITW_CLASH_FrontRoutingSelections",_published];
    true
};

ITW_CLASH_FrontRouting_fnc_Resolve = {
    params ["_side","_objectiveIndex",["_purpose","REINFORCEMENT"]];
    private _failed = createHashMapFromArray [
        ["status","UNRESOLVED"],
        ["side",_side],
        ["objective",_objectiveIndex],
        ["purpose",toUpperANSI _purpose],
        ["reason","no-valid-fob-lane"]
    ];

    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"} || {
        !(_side in [ITW_PlayerSide,ITW_EnemySide])
    }) exitWith {_failed};

    private _candidates = [
        _side,_objectiveIndex
    ] call ITW_CLASH_FrontRouting_fnc_Candidates;
    if (_candidates isEqualTo []) exitWith {_failed};

    private _primaryIndex = _candidates findIf {
        _x getOrDefault ["primary",false]
    };
    if (_primaryIndex < 0) exitWith {_failed};
    private _primary = _candidates#_primaryIndex;
    private _frontId = [
        _side,_objectiveIndex
    ] call ITW_CLASH_FrontRouting_fnc_FrontId;
    private _chosen = [
        _frontId,_candidates
    ] call ITW_CLASH_FrontRouting_fnc_SelectCandidate;
    if (count _chosen == 0) exitWith {_failed};

    private _previous = ITW_CLASH_FrontRoutingSelections getOrDefault [
        _frontId,createHashMap
    ];
    private _previousBase = _previous getOrDefault ["selectedBase",-1];
    private _selectedBase = _chosen getOrDefault ["baseIndex",-1];
    private _reason = if (_selectedBase == (_primary get "baseIndex")) then {
        if ((_chosen getOrDefault ["state","HEALTHY"]) == "INTERDICTED") then {
            "all-candidates-interdicted-primary-fallback"
        } else {
            "primary-available"
        }
    } else {
        if (_previousBase == _selectedBase) then {
            "sticky-alternate"
        } else {
            "primary-interdicted-alternate-selected"
        }
    };

    private _selection = createHashMapFromArray [
        ["status","RESOLVED"],
        ["frontId",_frontId],
        ["side",_side],
        ["objective",_objectiveIndex],
        ["purpose",toUpperANSI _purpose],
        ["primaryBase",_primary get "baseIndex"],
        ["selectedBase",_selectedBase],
        ["selectedRoute",_chosen get "routeId"],
        ["selectedPosition",+(_chosen get "position")],
        ["selectedState",_chosen getOrDefault ["state","HEALTHY"]],
        ["candidateCount",count _candidates],
        ["candidates",_candidates],
        ["reason",_reason],
        ["shadow",ITW_CLASH_FrontRoutingShadowMode],
        ["selectedAt",if (_previousBase == _selectedBase) then {
            _previous getOrDefault ["selectedAt",time]
        } else {
            time
        }]
    ];

    ITW_CLASH_FrontRoutingSelections set [_frontId,_selection];
    [_side,_objectiveIndex,_selection] call
        ITW_CLASH_FrontRouting_fnc_PublishCommanderSelection;
    _selection
};

ITW_CLASH_FrontRoutingReady = true;
diag_log format [
    "CLASH BOOT | front-routing-ready | version=%1 shadow=true symmetricSides=true stickySelection=true activeFrontAlternates=true routeHealthAPI=true noSpawnAuthority=true",
    ITW_CLASH_FrontRoutingVersion
];

[] spawn {
    scriptName "ITW_CLASH_FrontRoutingShadowManager";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_HALReady",false] && {
            !isNil "ITW_PlayerSide" && {
                !isNil "ITW_EnemySide"
            }
        }
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        private _objectives = call ITW_CLASH_FrontRouting_fnc_ActiveObjectives;
        {
            private _side = _x;
            {
                private _objectiveIndex = _x;
                private _resolved = [
                    _side,_objectiveIndex,"REINFORCEMENT"
                ] call ITW_CLASH_FrontRouting_fnc_Resolve;
                if ((_resolved getOrDefault ["status",""]) != "RESOLVED") then {
                    continue
                };

                private _frontId = _resolved get "frontId";
                private _candidateSummary = (
                    _resolved getOrDefault ["candidates",[]]
                ) apply {
                    [
                        _x get "baseIndex",
                        round (_x get "distance"),
                        _x getOrDefault ["state","HEALTHY"],
                        _x getOrDefault ["primary",false]
                    ]
                };
                private _signature = str [
                    _resolved get "primaryBase",
                    _resolved get "selectedBase",
                    _resolved get "selectedState",
                    _candidateSummary
                ];
                if (
                    ITW_CLASH_FrontRoutingSignatures getOrDefault [_frontId,""]
                    != _signature
                ) then {
                    ITW_CLASH_FrontRoutingSignatures set [_frontId,_signature];
                    ["shadow-selection",[
                        _frontId,
                        _resolved get "primaryBase",
                        _resolved get "selectedBase",
                        _resolved get "reason",
                        _candidateSummary
                    ]] call ITW_CLASH_FrontRouting_fnc_Log;
                };
            } forEach _objectives;
        } forEach [ITW_PlayerSide,ITW_EnemySide];

        sleep ITW_CLASH_FrontRoutingPoll;
    };
};

true
