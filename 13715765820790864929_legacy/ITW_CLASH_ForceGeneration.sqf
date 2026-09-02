#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]) exitWith {true};

ITW_CLASH_ForceGenerationVersion = 1;
ITW_CLASH_ArtilleryMinimumPerSide = missionNamespace getVariable [
    "ITW_CLASH_ArtilleryMinimumPerSide",1
];
ITW_CLASH_CheckbookAIArtilleryEnabled = missionNamespace getVariable [
    "ITW_CLASH_CheckbookAIArtilleryEnabled",true
];
ITW_CLASH_GenerationSanctuaryRadius = missionNamespace getVariable [
    "ITW_CLASH_GenerationSanctuaryRadius",300
];

ITW_CLASH_Generation_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["generation-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH GENERATION | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_Generation_fnc_NormalizeClass = {
    params ["_entry"];
    if (_entry isEqualType []) then {
        if (_entry isEqualTo []) then {""} else {_entry#0}
    } else {
        _entry
    }
};

ITW_CLASH_Generation_fnc_GetPool = {
    params ["_side","_capability",["_mode","GROUND"]];
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _pool = switch (toUpperANSI _capability) do {
        case "ARTILLERY": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyArtilleryClasses",[]]
            }
        };
        case "PLAYER_ARTILLERY": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyArtilleryClasses",[]]
            }
        };
        case "LOGISTICS_AMMO": {
            if (toUpperANSI _mode == "AIR") then {
                if (_friendly) then {
                    missionNamespace getVariable ["ITW_CLASH_PlayerAmmoHeloClasses",[]]
                } else {
                    missionNamespace getVariable ["ITW_CLASH_EnemyAmmoHeloClasses",[]]
                }
            } else {
                if (_friendly) then {
                    missionNamespace getVariable ["ITW_CLASH_PlayerAmmoClasses",[]]
                } else {
                    missionNamespace getVariable ["ITW_CLASH_EnemyAmmoClasses",[]]
                }
            }
        };
        case "LOGISTICS_FUEL": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerFuelClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyFuelClasses",[]]
            }
        };
        case "LOGISTICS_REPAIR": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerRepairClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyRepairClasses",[]]
            }
        };
        default {[]};
    };

    private _classes = _pool apply {[_x] call ITW_CLASH_Generation_fnc_NormalizeClass};
    _classes select {
        _x isEqualType "" && {_x isNotEqualTo ""} && {
            isClass (configFile >> "CfgVehicles" >> _x)
        }
    }
};

ITW_CLASH_Generation_fnc_ActiveObjectiveIds = {
    private _ids = [];
    if (!isNil "ITW_CLASH_fnc_GetActiveObjectives") then {
        {
            if (_x isEqualType [] && {count _x > 0}) then {
                _ids pushBackUnique (_x#0);
            };
        } forEach (call ITW_CLASH_fnc_GetActiveObjectives);
    };
    if (_ids isEqualTo [] && {!isNil "ITW_Zones"} && {!isNil "ITW_ZoneIndex"} && {
        ITW_ZoneIndex >= 0 && {ITW_ZoneIndex < count ITW_Zones}
    }) then {
        _ids = +(ITW_Zones#ITW_ZoneIndex);
    };
    _ids
};

ITW_CLASH_Generation_fnc_BaseSpawn = {
    params ["_baseIndex",["_air",false]];
    if (isNil "ITW_Bases" || {_baseIndex < 0} || {_baseIndex >= count ITW_Bases}) exitWith {[]};
    private _base = ITW_Bases#_baseIndex;
    private _spawn = +(_base#ITW_BASE_A_SPAWN);
    if (_air && {_baseIndex < count ITW_Objectives}) then {
        private _airSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_airSpawn isNotEqualTo []) then {_spawn = _airSpawn};
    };
    if (_spawn isEqualTo []) then {_spawn = +(_base#ITW_BASE_POS)};
    if (count _spawn < 3) then {_spawn pushBack 0};
    _spawn
};

ITW_CLASH_Generation_fnc_Interstitial = {
    params ["_rearPos","_forwardPos"];
    if (_rearPos isEqualTo [] || {_forwardPos isEqualTo []}) exitWith {[]};

    private _distance = _rearPos distance2D _forwardPos;
    private _direction = _rearPos getDir _forwardPos;
    private _mid = _rearPos getPos [_distance * 0.5,_direction];
    private _minimum = ITW_CLASH_GenerationSanctuaryRadius min (_distance * 0.2);
    private _roads = [_mid nearRoads 1000,[],{
        _x distance2D _mid
    },"ASCEND"] call BIS_fnc_sortBy;
    private _roadIndex = _roads findIf {
        private _roadPos = getPosATL _x;
        (_roadPos distance2D _rearPos) >= _minimum && {
            (_roadPos distance2D _forwardPos) >= _minimum
        }
    };
    private _point = if (_roadIndex >= 0) then {
        getPosATL (_roads#_roadIndex)
    } else {
        [_mid,25,750,12,0,0.35,0,[],[_mid,_mid]] call BIS_fnc_findSafePos
    };
    if (_point isEqualTo []) then {_point = _mid};
    if (count _point < 3) then {_point pushBack 0};
    _point set [2,0];
    _point
};

/*
    Resolve the same ITW base graph for either side:
      active objective -> side attack-source FOB -> upstream rear FOB.

    Profiles only select an operational echelon. INTERSTITIAL is derived from
    the two real nodes and a nearby road; it is not a theater-proximity corridor.
*/
ITW_CLASH_Generation_fnc_Resolve = {
    params ["_side","_capability",["_profile","FORWARD"],["_reference",[]]];
    private _failed = createHashMapFromArray [
        ["status","UNRESOLVED"],
        ["side",_side],
        ["capability",toUpperANSI _capability],
        ["profile",toUpperANSI _profile],
        ["reason","campaign-graph-unavailable"]
    ];
    if (isNil "ITW_Objectives" || {isNil "ITW_Bases"} || {
        ITW_Objectives isEqualTo [] || {ITW_Bases isEqualTo []}
    }) exitWith {_failed};
    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"} || {
        !(_side in [ITW_PlayerSide,ITW_EnemySide])
    }) exitWith {_failed};

    private _profileKey = toUpperANSI _profile;
    private _air = _profileKey in ["FORWARD_AIR","REAR_AIR"];
    private _friendly = _side == ITW_PlayerSide;
    private _slot = if (_air) then {
        if (_friendly) then {ITW_ATTACK_AIR_F} else {ITW_ATTACK_AIR_E}
    } else {
        if (_friendly) then {ITW_ATTACK_LAND_F} else {ITW_ATTACK_LAND_E}
    };
    private _objectiveIds = call ITW_CLASH_Generation_fnc_ActiveObjectiveIds;
    if (_objectiveIds isEqualTo []) exitWith {
        _failed set ["reason","no-active-objectives"];
        _failed
    };

    private _fallbackRear = if (_friendly) then {0} else {(count ITW_Bases) - 1};
    private _candidates = [];
    {
        private _objectiveId = _x;
        if (_objectiveId < 0 || {_objectiveId >= count ITW_Objectives}) then {continue};
        private _attacks = ITW_Objectives#_objectiveId#ITW_OBJ_ATTACKS;
        if (_slot < 0 || {_slot >= count _attacks}) then {continue};
        private _forwardBase = _attacks#_slot;
        if (_forwardBase < 0 || {_forwardBase >= count ITW_Bases}) then {continue};

        private _rearBase = _fallbackRear;
        if (_forwardBase < count ITW_Objectives) then {
            private _upstream = ITW_Objectives#_forwardBase#ITW_OBJ_ATTACKS;
            if (_slot >= 0 && {_slot < count _upstream}) then {
                private _candidateRear = _upstream#_slot;
                if (_candidateRear >= 0 && {_candidateRear < count ITW_Bases} && {
                    _candidateRear != _forwardBase
                }) then {
                    _rearBase = _candidateRear;
                };
            };
        };
        if (_rearBase == _forwardBase) then {_rearBase = _fallbackRear};
        _candidates pushBack [_objectiveId,_forwardBase,_rearBase];
    } forEach _objectiveIds;
    if (_candidates isEqualTo []) exitWith {
        _failed set ["reason","no-side-generation-nodes"];
        _failed
    };

    if (_reference isEqualTo []) then {
        _reference = ITW_Objectives#(_candidates#0#0)#ITW_OBJ_POS;
    };
    private _best = _candidates#0;
    private _bestDistance = _reference distance2D (ITW_Bases#(_best#1)#ITW_BASE_POS);
    {
        private _distance = _reference distance2D (ITW_Bases#(_x#1)#ITW_BASE_POS);
        if (_distance < _bestDistance) then {
            _best = _x;
            _bestDistance = _distance;
        };
    } forEach _candidates;
    _best params ["_objectiveId","_forwardBase","_rearBase"];

    private _forwardPos = [_forwardBase,_air] call ITW_CLASH_Generation_fnc_BaseSpawn;
    private _rearPos = [_rearBase,_air] call ITW_CLASH_Generation_fnc_BaseSpawn;
    if (_forwardPos isEqualTo [] || {_rearPos isEqualTo []}) exitWith {
        _failed set ["reason","empty-generation-node-position"];
        _failed
    };
    if (_profileKey == "INTERSTITIAL" && {
        _rearBase == _forwardBase || {_rearPos distance2D _forwardPos < 600}
    }) exitWith {
        _failed set ["reason","distinct-rear-forward-nodes-unavailable"];
        _failed
    };

    private _origin = switch (_profileKey) do {
        case "REAR";
        case "REAR_AIR": {+_rearPos};
        case "INTERSTITIAL": {[_rearPos,_forwardPos] call ITW_CLASH_Generation_fnc_Interstitial};
        default {+_forwardPos};
    };
    if (_origin isEqualTo []) exitWith {
        _failed set ["reason","deployment-position-unavailable"];
        _failed
    };

    createHashMapFromArray [
        ["status","RESOLVED"],
        ["side",_side],
        ["capability",toUpperANSI _capability],
        ["profile",_profileKey],
        ["objective",_objectiveId],
        ["forwardBase",_forwardBase],
        ["rearBase",_rearBase],
        ["forwardPosition",+_forwardPos],
        ["rearPosition",+_rearPos],
        ["origin",+_origin],
        ["direction",_rearPos getDir _forwardPos],
        ["source","itw-base-graph"]
    ]
};

ITW_CLASH_Generation_fnc_ClassKind = {
    params ["_class"];
    switch (true) do {
        case (_class isKindOf "Helicopter"): {"HELICOPTER"};
        case (_class isKindOf "Plane"): {"PLANE"};
        case (_class isKindOf "Tank"): {"TANK"};
        case (_class isKindOf "Car"): {"CAR"};
        case (_class isKindOf "Ship"): {"SHIP"};
        default {"OTHER"};
    }
};

ITW_CLASH_Generation_fnc_SelectBillingDefs = {
    params ["_side","_class","_capability"];
    if (isNil "ITW_VehArrays") exitWith {[]};
    private _friendly = _side == ITW_PlayerSide;
    private _zonesOwned = [_friendly] call ITW_CLASH_Checkbook_fnc_GetZonesOwned;
    private _kind = [_class] call ITW_CLASH_Generation_fnc_ClassKind;
    private _capabilityKey = toUpperANSI _capability;
    private _defs = ITW_VehArrays select {
        private _def = _x;
        private _defClasses = (_def#ITW_VEH_CLASSES) apply {
            [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
        };
        private _physicalMatch = _defClasses findIf {
            ([_x] call ITW_CLASH_Generation_fnc_ClassKind) == _kind
        };
        (_def#ITW_VEH_IS_FRIENDLY) == _friendly
        && {_physicalMatch >= 0}
        && {_def#ITW_VEH_ZONES_OWNED <= _zonesOwned}
        && {_def#ITW_VEH_CURR_TICKETS >= _def#ITW_VEH_REQD_TICKETS}
        && {_def#ITW_VEH_COUNT < _def#ITW_VEH_MAX}
    };

    [_defs,[],{
        private _def = _x;
        private _defClasses = (_def#ITW_VEH_CLASSES) apply {
            [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
        };
        private _exactBias = if (_class in _defClasses) then {0} else {1000};
        private _role = _def#ITW_VEH_ROLE;
        private _roleBias = if (_capabilityKey == "ARTILLERY") then {
            if (_role in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]) then {0} else {500}
        } else {
            if (_role in [ITW_VEH_ROLE_TRANSPORT,ITW_VEH_ROLE_DUAL]) then {0} else {500}
        };
        _exactBias + _roleBias + (_def#ITW_VEH_REQD_TICKETS)
    },"ASCEND"] call BIS_fnc_sortBy
};

ITW_CLASH_Generation_fnc_SelectClassAndBill = {
    params ["_side","_capability","_mode"];
    private _pool = [_side,_capability,_mode] call ITW_CLASH_Generation_fnc_GetPool;
    if (_pool isEqualTo []) exitWith {[]};

    private _ordered = +_pool;
    _ordered = [_ordered,[],{random 1},"ASCEND"] call BIS_fnc_sortBy;
    private _selection = [];
    {
        private _defs = [_side,_x,_capability] call ITW_CLASH_Generation_fnc_SelectBillingDefs;
        if (_defs isNotEqualTo []) exitWith {_selection = [_x,_defs#0]};
    } forEach _ordered;
    _selection
};

ITW_CLASH_Generation_fnc_RegisterAsset = {
    params ["_veh","_group","_hq","_capability","_mode","_requestId","_vehDef"];
    if (isNull _veh || {isNull _group} || {isNull _hq}) exitWith {false};

    _veh setVariable ["ITW_VehDef",_vehDef];
    _veh setVariable ["ITW_CLASH_CheckbookAsset",true,true];
    _veh setVariable ["ITW_CLASH_CheckbookRequest",_requestId,true];
    _veh setVariable ["ITW_CLASH_GenerationCapability",_capability,true];
    _group setVariable ["ITW_CLASH_CheckbookAsset",true];
    _group setVariable ["ITW_CLASH_CheckbookRequest",_requestId];
    _group setVariable ["ITW_CLASH_GenerationCapability",_capability];
    _group setVariable ["START" + str _group,getPosATL _veh];

    if !([_group,"checkbook-" + toLowerANSI _capability] call ITW_CLASH_DualHAL_fnc_RegisterGroup) exitWith {false};

    private _noAttack = +(_hq getVariable ["RydHQ_NoAttack",[]]);
    _noAttack pushBackUnique _group;
    _hq setVariable ["RydHQ_NoAttack",_noAttack];
    private _noRecon = +(_hq getVariable ["RydHQ_NoRecon",[]]);
    _noRecon pushBackUnique _group;
    _hq setVariable ["RydHQ_NoRecon",_noRecon];
    private _noDef = +(_hq getVariable ["RydHQ_NoDef",[]]);
    _noDef pushBackUnique _group;
    _hq setVariable ["RydHQ_NoDef",_noDef];

    switch (_capability) do {
        case "ARTILLERY": {
            private _art = +(_hq getVariable ["RydHQ_ArtG",[]]);
            _art pushBackUnique _group;
            _hq setVariable ["RydHQ_ArtG",_art];
        };
        case "LOGISTICS_AMMO";
        case "LOGISTICS_FUEL";
        case "LOGISTICS_REPAIR": {
            private _support = +(_hq getVariable ["RydHQ_Support",[]]);
            {_support pushBackUnique _x} forEach units _group;
            _hq setVariable ["RydHQ_Support",_support];
            if (_capability == "LOGISTICS_AMMO" && {_mode == "AIR"}) then {
                private _drops = +(_hq getVariable ["RydHQ_AmmoDrop",[]]);
                _drops pushBackUnique _group;
                _hq setVariable ["RydHQ_AmmoDrop",_drops];
                private _air = +(_hq getVariable ["RydHQ_AirG",[]]);
                _air pushBackUnique _group;
                _hq setVariable ["RydHQ_AirG",_air];
            };
        };
    };

    [_veh,_vehDef,"checkbook-" + toLowerANSI _capability] call
        ITW_CLASH_DualHAL_fnc_TrackAsset;
    true
};

ITW_CLASH_Generation_fnc_Provider = {
    private _request = _this;
    private _capability = _request get "capability";
    private _side = _request get "side";
    private _requester = _request get "requester";
    private _requirements = _request get "requirements";
    private _mode = toUpperANSI (_requirements getOrDefault ["mode","GROUND"]);
    private _hq = _requirements getOrDefault ["hq",grpNull];
    if (isNull _hq) then {_hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide};
    if (isNull _hq) exitWith {
        [_request,"DEFERRED",[],"commander-unavailable","generation-v1"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _profile = toUpperANSI (_requirements getOrDefault [
        "profile",
        if (_capability == "ARTILLERY") then {"INTERSTITIAL"} else {
            if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}
        }
    ]);
    private _reference = +(_requirements getOrDefault [
        "reference",getPosATL leader _requester
    ]);
    private _generation = [
        _side,_capability,_profile,_reference
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {
        [_request,"DEFERRED",[],_generation getOrDefault ["reason","node-unresolved"],"generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _selection = [_side,_capability,_mode] call
        ITW_CLASH_Generation_fnc_SelectClassAndBill;
    if (_selection isEqualTo []) exitWith {
        [_request,"DENIED",[],"no-affordable-faction-capability","generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    _selection params ["_class","_vehDef"];

    private _crewInfo = [_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes;
    _crewInfo params ["_crewTypes","_unitTypes"];
    if (_crewTypes isEqualTo [] || {_unitTypes isEqualTo []}) exitWith {
        [_request,"DENIED",[],"no-faction-crew","generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _origin = +(_generation get "origin");
    private _veh = [[_class],_crewTypes,_unitTypes,_side,_origin,-1] call ITW_AtkSpawnVeh;
    if (isNull _veh) exitWith {
        [_request,"FAILED",[],"spawn-failed","generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    _veh setDir (_generation getOrDefault ["direction",direction _veh]);
    private _crewGroup = group driver _veh;

    ITW_TICKET_SEM_CHECK;
    if (
        _vehDef#ITW_VEH_CURR_TICKETS < _vehDef#ITW_VEH_REQD_TICKETS || {
            _vehDef#ITW_VEH_COUNT >= _vehDef#ITW_VEH_MAX
        }
    ) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        [_request,"DEFERRED",[],"budget-changed-during-spawn","generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _registered = [
        _veh,_crewGroup,_hq,_capability,_mode,_request get "id",_vehDef
    ] call ITW_CLASH_Generation_fnc_RegisterAsset;
    if (!_registered) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        [_request,"FAILED",[],"hal-registration-failed","generation-v1",createHashMap,_generation] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _ticketsBefore = _vehDef#ITW_VEH_CURR_TICKETS;
    ITW_VEH_COUNT_INCR(_vehDef);
    ITW_TICKET_REDUCE(_vehDef);
    [_veh,true] remoteExec ["allowDamage",_veh];
    {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;

    private _billing = createHashMapFromArray [
        ["class",_class],
        ["ticketCost",_vehDef#ITW_VEH_REQD_TICKETS],
        ["ticketsBefore",_ticketsBefore],
        ["ticketsAfter",_vehDef#ITW_VEH_CURR_TICKETS],
        ["count",_vehDef#ITW_VEH_COUNT],
        ["max",_vehDef#ITW_VEH_MAX],
        ["surrogate",!(_class in (_vehDef#ITW_VEH_CLASSES))]
    ];
    private _metadata = createHashMapFromArray [
        ["mode",_mode],
        ["halCommander",_hq getVariable ["RydHQ_CodeSign","?"]]
    ];

    ["asset-provided",[
        _request get "id",_capability,_side,_class,
        _generation get "rearBase",_generation get "forwardBase",
        _profile,_vehDef#ITW_VEH_REQD_TICKETS
    ]] call ITW_CLASH_Generation_fnc_Log;

    [_request,"APPROVED",[_veh],"provided","generation-v1",_billing,_generation,_metadata] call
        ITW_CLASH_Checkbook_fnc_Response
};

{
    [_x,ITW_CLASH_Generation_fnc_Provider] call ITW_CLASH_Checkbook_fnc_RegisterProvider;
} forEach ["ARTILLERY","LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR"];

ITW_CLASH_Generation_fnc_UsableGroups = {
    params ["_groups"];
    _groups select {
        !isNull _x && {{alive _x} count units _x > 0} && {
            private _veh = vehicle leader _x;
            !isNull _veh && {alive _veh} && {canMove _veh}
        }
    }
};

// HAL owns all subsequent movement and fire employment. This loop only fills a
// budgeted capacity deficit in HAL's own RydHQ_ArtG state.
[] spawn {
    scriptName "ITW_CLASH_AIArtilleryFulfillment";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_DualHALReady",false] && {
            missionNamespace getVariable ["ITW_CLASH_CapabilityPoolsReady",false]
        }
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 15;
        if (!ITW_CLASH_CheckbookAIArtilleryEnabled) then {continue};
        {
            _x params ["_side","_hq"];
            if (isNull _hq) then {continue};
            private _art = [
                +(_hq getVariable ["RydHQ_ArtG",[]])
            ] call ITW_CLASH_Generation_fnc_UsableGroups;
            _hq setVariable ["RydHQ_ArtG",_art];
            if (count _art >= ITW_CLASH_ArtilleryMinimumPerSide) then {continue};

            private _retryAt = _hq getVariable ["ITW_CLASH_ArtilleryCheckbookRetryAt",0];
            if (time < _retryAt) then {continue};
            _hq setVariable ["ITW_CLASH_ArtilleryCheckbookRetryAt",time + 90];

            private _requirements = createHashMapFromArray [
                ["hq",_hq],
                ["side",_side],
                ["profile","INTERSTITIAL"],
                ["mode","GROUND"],
                ["reference",getPosATL leader _hq]
            ];
            private _reply = [
                "ARTILLERY",_hq,_requirements,"HIGH"
            ] call ITW_CLASH_fnc_RequestCapability;
            if ((_reply getOrDefault ["status",""]) == "APPROVED") then {
                _hq setVariable ["ITW_CLASH_ArtilleryCheckbookRetryAt",time + 300];
            };
        } forEach [
            [ITW_PlayerSide,[ITW_PlayerSide] call ITW_CLASH_fnc_GetCommanderForSide],
            [ITW_EnemySide,[ITW_EnemySide] call ITW_CLASH_fnc_GetCommanderForSide]
        ];
    };
};

ITW_CLASH_ForceGenerationReady = true;
diag_log format [
    "CLASH BOOT | force-generation-ready | version=%1 resolver=symmetric-itw-graph artillery=interstitial logistics=rear ticketing=itw-surrogate bothSides=true halTacticalAuthority=true",
    ITW_CLASH_ForceGenerationVersion
];
true
