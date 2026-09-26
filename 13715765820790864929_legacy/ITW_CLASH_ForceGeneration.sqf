#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]) exitWith {true};

ITW_CLASH_ForceGenerationVersion = 2;
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
        case "GROUND_ATTACK_LIGHT": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerGroundAttackLightClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyGroundAttackLightClasses",[]]
            }
        };
        case "CAS_AIRCRAFT": {
            if (_friendly) then {
                missionNamespace getVariable ["ITW_CLASH_PlayerCASAircraftClasses",[]]
            } else {
                missionNamespace getVariable ["ITW_CLASH_EnemyCASAircraftClasses",[]]
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
    // Combat buys may only draw on ITW's attack/dual rows, so ITW's own caps
    // and spawn-adjustment params bind. Live run: 136/140 GROUND_ATTACK_LIGHT
    // and 69/115 CAS_AIRCRAFT buys billed the transport car row (1 ticket,
    // max 99) and transport heli row (2 tickets, max 8) instead.
    private _combatOnly = _capabilityKey in ["GROUND_ATTACK_LIGHT","CAS_AIRCRAFT"];
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
        && {!_combatOnly || {(_def#ITW_VEH_ROLE) in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]}}
    };

    [_defs,[],{
        private _def = _x;
        private _defClasses = (_def#ITW_VEH_CLASSES) apply {
            [_x] call ITW_CLASH_Generation_fnc_NormalizeClass
        };
        private _exactBias = if (_class in _defClasses) then {0} else {1000};
        private _role = _def#ITW_VEH_ROLE;
        // ARTILLERY, GROUND_ATTACK_LIGHT and CAS_AIRCRAFT are all combat
        // capabilities and want attack-role billing defs; everything else
        // (LOGISTICS_*, TRANSPORT) wants transport-role ones. This used to be
        // a plain ARTILLERY-vs-everything-else check, which would have scored
        // combat billing defs for the two new capabilities as if they needed
        // a transport role - a real bug, not just a missing case.
        private _roleBias = if (_capabilityKey in ["ARTILLERY","GROUND_ATTACK_LIGHT","CAS_AIRCRAFT"]) then {
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

    if (!isNil "ITW_CLASH_DualHAL_fnc_MarkVehicleCrew") then {
        [_group,_veh,"checkbook-" + toLowerANSI _capability] call
            ITW_CLASH_DualHAL_fnc_MarkVehicleCrew;
    };

    if (!isNil "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership") then {
        [_group,["NoAttack","NoRecon","NoDef"],true] call
            ITW_CLASH_CommanderParity_fnc_SetConstraintMembership;
    } else {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _arr pushBackUnique _group;
            _hq setVariable [_x,_arr];
        } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
    };

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
        // GROUND_ATTACK_LIGHT / CAS_AIRCRAFT are combat capabilities, unlike
        // every case above. The generic path just above this switch put this
        // group into NoAttack/NoRecon/NoDef - correct for a support truck,
        // wrong for a combat asset HAL asked for specifically to go fight
        // something. Clear that before projecting into the matching pool.
        case "GROUND_ATTACK_LIGHT": {
            if (!isNil "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership") then {
                [_group,["NoAttack","NoRecon","NoDef"],false] call
                    ITW_CLASH_CommanderParity_fnc_SetConstraintMembership;
            } else {
                {
                    private _arr = (+(_hq getVariable [_x,[]])) - [_group];
                    _hq setVariable [_x,_arr];
                } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
            };

            // Route by what was actually spawned. The classlist is now
            // Apc+Car only (see VehicleArrays.sqf) - no infantry, so no
            // NCrewInfG fallback; HAL already hunts infantry threats itself,
            // Checkbook doesn't need to manufacture infantry through a
            // vehicle provider. Wheeled Apc classes typically resolve as CAR,
            // tracked ones as TANK via ClassKind's isKindOf checks - CarsG is
            // the fallback for anything else only as a defensive default, not
            // an expected case; logged so an unexpected kind is visible.
            private _kind = [typeOf _veh] call ITW_CLASH_Generation_fnc_ClassKind;
            private _poolVar = switch (_kind) do {
                case "TANK": {"RydHQ_LArmorG"};
                case "CAR": {"RydHQ_CarsG"};
                default {
                    ["unexpected-ground-attack-light-kind",[_kind,typeOf _veh]] call
                        ITW_CLASH_Generation_fnc_Log;
                    "RydHQ_CarsG"
                };
            };
            private _pool = +(_hq getVariable [_poolVar,[]]);
            _pool pushBackUnique _group;
            _hq setVariable [_poolVar,_pool];
        };
        case "CAS_AIRCRAFT": {
            if (!isNil "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership") then {
                [_group,["NoAttack","NoRecon","NoDef"],false] call
                    ITW_CLASH_CommanderParity_fnc_SetConstraintMembership;
            } else {
                {
                    private _arr = (+(_hq getVariable [_x,[]])) - [_group];
                    _hq setVariable [_x,_arr];
                } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
            };

            // RCAS so both HAL's own RYD_Dispatcher merge and the addon's
            // fnc_watch.sqf pool see it; AirG so it counts in HAL's general
            // air bookkeeping too, same dual-registration shape LOGISTICS_AMMO/
            // AIR already uses above for AmmoDrop+AirG. RCAP too: HAL's own
            // "Air" threat dispatch (RYD_Dispatcher's "Air" case) draws on
            // RydHQ_RCAP specifically, not RCAS - without this a
            // CAS_AIRCRAFT purchase would never actually help HAL answer an
            // enemy-air deficit, only a ground-support one.
            private _rcas = +(_hq getVariable ["RydHQ_RCAS",[]]);
            _rcas pushBackUnique _group;
            _hq setVariable ["RydHQ_RCAS",_rcas];
            private _rcap = +(_hq getVariable ["RydHQ_RCAP",[]]);
            _rcap pushBackUnique _group;
            _hq setVariable ["RydHQ_RCAP",_rcap];
            private _air = +(_hq getVariable ["RydHQ_AirG",[]]);
            _air pushBackUnique _group;
            _hq setVariable ["RydHQ_AirG",_air];
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

    // Artillery (incl. rocket artillery) is rear echelon like every other
    // tank-killer: it spawns at the rear FOB and drives, never mid-corridor.
    private _profile = toUpperANSI (_requirements getOrDefault [
        "profile",
        if (_mode == "AIR") then {"REAR_AIR"} else {"REAR"}
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
} forEach ["ARTILLERY","LOGISTICS_AMMO","LOGISTICS_FUEL","LOGISTICS_REPAIR","GROUND_ATTACK_LIGHT","CAS_AIRCRAFT"];

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
                ["profile","REAR"],
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


/*
    ===================================================================
    Emerging Threats Budget generation
    ===================================================================

    The ETB decides whether a counter can be paid for. This section decides
    what can be built and builds it: the canonical provider definitions, the
    faction's own class choice, progression and airport checks, the spawn point,
    the physical spawn, the post-spawn check, and HAL registration.

    Two rules separate it from the Checkbook path above. Candidates come from
    Impasse's own attack and dual rows, so a faction never fields a foreign or
    hard-coded class and escalation still binds - no new class lists. And the
    asset is registered WITHOUT ITW_VehDef, because an ETB purchase is additive
    and must not count against Impasse's caps; ITW_CLASH_Generation_fnc_RegisterAsset
    above stamps it, which is exactly why this needs its own path.
*/

// Canonical provider definitions. An Impasse role is not a CLASH capability:
// what qualifies is read off the vehicle's own weapons, before the buy from
// config and again after the spawn from the real thing.
ITW_CLASH_ETBProviders = createHashMapFromArray [
    ["GROUND_ANTI_ARMOR",createHashMapFromArray [
        ["need","ANTI_ARMOR"],["domain","GROUND"],["spawn","REAR"]
    ]],
    ["ANTI_ARMOR_CAS",createHashMapFromArray [
        ["need","ANTI_ARMOR"],["domain","AIR"],["spawn","REAR_OR_AIRPORT"]
    ]],
    ["CAP_AIRCRAFT",createHashMapFromArray [
        ["need","COUNTER_AIR"],["domain","AIR"],["spawn","AIRPORT"]
    ]],
    ["SPAA",createHashMapFromArray [
        ["need","COUNTER_AIR"],["domain","GROUND"],["spawn","REAR"]
    ]]
];

ITW_CLASH_Generation_fnc_ETBProvidersFor = {
    params ["_need"];
    private _providers = [];
    {
        if ((_y get "need") isEqualTo _need) then {_providers pushBack _x};
    } forEach ITW_CLASH_ETBProviders;
    _providers
};

/*
    Does this capability's definition hold for this weapon profile? One place,
    used for a class's config before the buy and for the spawned vehicle after,
    so the two can never drift apart.
*/
ITW_CLASH_Generation_fnc_ETBQualifiesProfile = {
    params ["_capability","_profile","_isAir","_isPlane","_isStatic"];
    switch (_capability) do {
        // Ground combat vehicle with live anti-armor ammo. An unarmed vehicle
        // or one without anti-armor ammo does not qualify.
        case "GROUND_ANTI_ARMOR": {
            !_isAir && {!_isStatic} && {_profile get "antiArmor"}
        };
        // Attack helicopter or strike plane carrying anti-armor ordnance. A
        // door-gun transport helicopter does not qualify.
        case "ANTI_ARMOR_CAS": {
            _isAir && {_profile get "antiArmor"}
        };
        // Fixed-wing with air-to-air weapons. Helicopters and
        // ground-attack-only planes do not qualify.
        case "CAP_AIRCRAFT": {
            _isPlane && {_profile get "antiAirMissile"}
        };
        // Weapons that engage air and not armor. An IFV with an incidental AA
        // ability does not qualify: it is an armor answer HAL would send forward.
        case "SPAA": {
            !_isAir && {!_isStatic} && {_profile get "antiAir"} && {!(_profile get "antiArmor")}
        };
        default {false};
    }
};

ITW_CLASH_Generation_fnc_ETBQualifiesClass = {
    params ["_class","_capability"];
    if (_class isEqualTo "" || {!isClass (configFile >> "CfgVehicles" >> _class)}) exitWith {false};
    if (isNil "ITW_CLASH_AirPicture_fnc_ClassProfile") exitWith {false};
    [
        _capability,
        [_class] call ITW_CLASH_AirPicture_fnc_ClassProfile,
        _class isKindOf "Air",
        _class isKindOf "Plane",
        _class isKindOf "StaticWeapon"
    ] call ITW_CLASH_Generation_fnc_ETBQualifiesProfile
};

// The post-spawn check, on the real vehicle's real weapons and pylons.
ITW_CLASH_Generation_fnc_ETBQualifiesVehicle = {
    params ["_veh","_capability"];
    if (isNull _veh || {!alive _veh}) exitWith {false};
    if (isNil "ITW_CLASH_AirPicture_fnc_WeaponProfile") exitWith {false};
    [
        _capability,
        [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile,
        _veh isKindOf "Air",
        _veh isKindOf "Plane",
        _veh isKindOf "StaticWeapon"
    ] call ITW_CLASH_Generation_fnc_ETBQualifiesProfile
};

// Classes this capability has already proved itself wrong about: a class that
// spawned and did not fulfil its capability is skipped for the rest of the run.
ITW_CLASH_ETBRejectedClasses = createHashMap;

ITW_CLASH_Generation_fnc_ETBRejectClass = {
    params ["_capability","_class","_reason"];
    private _key = format ["%1|%2",_capability,_class];
    ITW_CLASH_ETBRejectedClasses set [_key,_reason];
    ["etb-class-rejected",[_capability,_class,_reason]] call ITW_CLASH_Generation_fnc_Log;
    true
};

/*
    Candidates for a capability, cheapest first, as [class, row index, price].

    Drawn from Impasse's own attack and dual rows for this side: the row carries
    the faction's classes, its escalation gate (ZONES_OWNED) and the ticket price
    the ETB normalizes. Impasse's own ticket balance and live count are
    deliberately NOT read - the ETB does not care whether Impasse can afford the
    row, only what the row says a thing costs and how many should exist.
*/
ITW_CLASH_Generation_fnc_ETBCandidates = {
    params ["_side","_capability"];
    if (isNil "ITW_VehArrays" || {isNil "ITW_CLASH_ETB_fnc_Price"}) exitWith {[]};
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _zonesOwned = [_friendly] call ITW_CLASH_Checkbook_fnc_GetZonesOwned;
    private _ownsAirport = if (isNil "ITW_ObjOwnsAirport") then {false} else {
        _friendly call ITW_ObjOwnsAirport
    };
    private _candidates = [];
    {
        private _row = _x;
        private _rowIndex = _forEachIndex;
        if ((_row#ITW_VEH_IS_FRIENDLY) isNotEqualTo _friendly) then {continue};
        if !((_row#ITW_VEH_ROLE) in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]) then {continue};
        // Faction progression stays in charge: nothing above its escalation tier.
        if ((_row#ITW_VEH_ZONES_OWNED) > _zonesOwned) then {continue};
        // No aircraft without an owned airport, exactly as Impasse rules it.
        if ((_row#ITW_VEH_TYPE) == ITW_TYPE_VEH_AIRPLANE && {!_ownsAirport}) then {continue};
        private _price = [_rowIndex] call ITW_CLASH_ETB_fnc_Price;
        if (_price <= 0) then {continue};
        {
            private _class = [_x] call ITW_CLASH_Generation_fnc_NormalizeClass;
            if (_class isEqualTo "") then {continue};
            if ((ITW_CLASH_ETBRejectedClasses getOrDefault [
                format ["%1|%2",_capability,_class],""
            ]) isNotEqualTo "") then {continue};
            if !([_class,_capability] call ITW_CLASH_Generation_fnc_ETBQualifiesClass) then {continue};
            _candidates pushBack [_class,_rowIndex,_price];
        } forEach (_row#ITW_VEH_CLASSES);
    } forEach ITW_VehArrays;

    // Cheapest first, so a price above the capacity is skipped for a cheaper
    // vehicle in the same capability instead of denying the whole need.
    [_candidates,[],{_x#2},"ASCEND"] call BIS_fnc_sortBy
};

/*
    Where an ETB asset appears. The echelon rule holds: a tank killer stages at
    the rear FOB and drives. Planes must come from an owned airport, which is
    what CLASH's air profile alone would have got wrong - it spawns at the rear
    base like everything else.
*/
ITW_CLASH_Generation_fnc_ETBSpawnPoint = {
    params ["_side","_capability","_class",["_reference",[]]];
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _needsAirport = _class isKindOf "Plane";
    if (_needsAirport) exitWith {
        if (isNil "ITW_ObjOwnedAirports") exitWith {["","AIRPORT_REQUIRED",[]]};
        private _airports = _friendly call ITW_ObjOwnedAirports;
        if (_airports isEqualTo []) exitWith {["","AIRPORT_REQUIRED",[]]};
        private _position = +(_airports#0);
        if (count _position < 3) then {_position pushBack 0};
        ["airport","",_position]
    };
    private _generation = [
        _side,_capability,"REAR",_reference
    ] call ITW_CLASH_Generation_fnc_Resolve;
    if ((_generation getOrDefault ["status",""]) isNotEqualTo "RESOLVED") exitWith {
        ["","NO_CANDIDATE",[]]
    };
    ["rear-base","",+(_generation getOrDefault ["origin",[]])]
};

/*
    Register an ETB asset with HAL. Same handoff as every other C.L.A.S.H.
    purchase - HAL owns employment from here - with two differences: no
    ITW_VehDef, and SPAA never enters HAL's attack, flank or recon pools, which
    is the one exception to "HAL owns employment" and what lets CLASH hold it in
    overwatch behind the front.
*/
ITW_CLASH_Generation_fnc_ETBRegisterAsset = {
    params ["_veh","_group","_hq","_capability"];
    if (isNull _veh || {isNull _group} || {isNull _hq}) exitWith {false};

    _veh setVariable ["ITW_CLASH_ETBAsset",true,true];
    _veh setVariable ["ITW_CLASH_ETBCapability",_capability,true];
    _group setVariable ["ITW_CLASH_ETBAsset",true];
    _group setVariable ["ITW_CLASH_ETBCapability",_capability];
    _group setVariable ["START" + str _group,getPosATL _veh];

    if !([_group,"etb-" + toLowerANSI _capability] call ITW_CLASH_DualHAL_fnc_RegisterGroup) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_MarkVehicleCrew") then {
        [_group,_veh,"etb-" + toLowerANSI _capability] call ITW_CLASH_DualHAL_fnc_MarkVehicleCrew;
    };

    private _combat = _capability isNotEqualTo "SPAA";
    if (!isNil "ITW_CLASH_CommanderParity_fnc_SetConstraintMembership") then {
        [_group,["NoAttack","NoRecon","NoDef"],!_combat] call
            ITW_CLASH_CommanderParity_fnc_SetConstraintMembership;
    } else {
        {
            private _arr = (+(_hq getVariable [_x,[]])) - [_group];
            if (!_combat) then {_arr pushBackUnique _group};
            _hq setVariable [_x,_arr];
        } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];
    };

    switch (_capability) do {
        case "GROUND_ANTI_ARMOR": {
            private _kind = [typeOf _veh] call ITW_CLASH_Generation_fnc_ClassKind;
            private _poolVar = switch (_kind) do {
                case "TANK": {"RydHQ_LArmorG"};
                case "CAR": {"RydHQ_CarsG"};
                default {
                    ["unexpected-etb-ground-kind",[_kind,typeOf _veh]] call
                        ITW_CLASH_Generation_fnc_Log;
                    "RydHQ_CarsG"
                };
            };
            private _pool = +(_hq getVariable [_poolVar,[]]);
            _pool pushBackUnique _group;
            _hq setVariable [_poolVar,_pool];
            // A tank killer belongs in HAL's own AT armor pool, which is what
            // its dispatcher draws on for an armor threat.
            private _at = +(_hq getVariable ["RydHQ_LArmorATG",[]]);
            _at pushBackUnique _group;
            _hq setVariable ["RydHQ_LArmorATG",_at];
        };
        case "ANTI_ARMOR_CAS": {
            {
                private _pool = +(_hq getVariable [_x,[]]);
                _pool pushBackUnique _group;
                _hq setVariable [_x,_pool];
            } forEach ["RydHQ_RCAS","RydHQ_AirG"];
        };
        case "CAP_AIRCRAFT": {
            // RCAP is what HAL's own "Air" dispatch draws on, RCAS so the
            // addon's responder sees it, AirG for HAL's air bookkeeping.
            {
                private _pool = +(_hq getVariable [_x,[]]);
                _pool pushBackUnique _group;
                _hq setVariable [_x,_pool];
            } forEach ["RydHQ_RCAP","RydHQ_RCAS","RydHQ_AirG"];
        };
        case "SPAA": {
            // Deliberately no pool at all. CLASH places it and HAL never sends
            // it anywhere; the overwatch layer owns it from here.
            _group setVariable ["ITW_CLASH_SPAAOverwatch",true];
            _veh setVariable ["ITW_CLASH_SPAAOverwatch",true,true];
        };
    };

    // Tracked for the service layers with no Impasse row: an ETB asset is not
    // Impasse's to bill, clean up or count.
    [_veh,[],"etb-" + toLowerANSI _capability] call ITW_CLASH_DualHAL_fnc_TrackAsset;
    true
};

/*
    One ETB purchase, as one transaction with exactly one economic owner.

      1. Resolve a candidate class and its Impasse row.
      2. Check progression, airport, the row limit and the reserve (the ETB).
      3. Reserve money and the row slot BEFORE anything that can pause.
      4. Re-check that the threat is still there.
      5. Spawn at the rear base, or the airport for a plane.
      6. Inspect the real class and pylons; if it does not fulfil the
         capability, delete it, return the reservation, and never try that class
         for this capability again.
      7. Register with HAL.
      8. On success the reservation becomes a living asset; on any failure the
         money and the slot go back.

    It never falls back to Impasse tickets when it is short.
*/
ITW_CLASH_Generation_fnc_ETBFulfil = {
    params ["_hq","_capability","_need",["_threatKey",""],["_threat",objNull],["_reference",[]]];
    private _deny = {
        params ["_reason",["_detail",[]]];
        createHashMapFromArray [
            ["status","DENIED"],["reason",_reason],["capability",_capability],
            ["detail",_detail],["asset",objNull]
        ]
    };
    if (isNull _hq) exitWith {["NO_CANDIDATE",["no-commander"]] call _deny};
    private _side = side _hq;

    private _candidates = [_side,_capability] call ITW_CLASH_Generation_fnc_ETBCandidates;
    if (_candidates isEqualTo []) exitWith {
        // No qualifying vehicle in the faction's own reachable rows. Honest
        // answer, not a silent retry: SPAA is what gives a side without an
        // airport a counter-air answer at all.
        private _anyRow = [_side,_capability] call ITW_CLASH_Generation_fnc_ETBAnyRow;
        [if (_anyRow) then {"PROGRESSION_LOCKED"} else {"NO_CANDIDATE"},[_capability]] call _deny
    };

    private _reserve = createHashMap;
    private _chosen = [];
    {
        _x params ["_class","_rowIndex","_price"];
        private _reply = [
            _side,_capability,_need,_rowIndex,_class,_threatKey
        ] call ITW_CLASH_ETB_fnc_Authorize;
        private _status = _reply get "status";
        if (_status isEqualTo "APPROVED" || {_status isEqualTo "DRY_RUN"}) exitWith {
            _reserve = _reply;
            _chosen = [_class,_rowIndex,_price];
        };
        // Only a price that cannot ever fit is worth trying a cheaper vehicle
        // for; every other reason is about the commander, not the class.
        if ((_reply get "reason") isNotEqualTo "COST_EXCEEDS_CAPACITY") exitWith {
            _reserve = _reply;
        };
    } forEach _candidates;

    if (_chosen isEqualTo []) exitWith {
        [_reserve getOrDefault ["reason","INSUFFICIENT_ETB"],[_capability]] call _deny
    };
    _chosen params ["_class","_rowIndex","_price"];
    if ((_reserve get "status") isEqualTo "DRY_RUN") exitWith {
        createHashMapFromArray [
            ["status","DRY_RUN"],["reason","dry-run"],["capability",_capability],
            ["detail",[_class,_price]],["asset",objNull]
        ]
    };
    private _reservationId = _reserve get "reservation";

    // The threat may have died while we were deciding. Cancel before spawning:
    // a reservation is never spent on something that is already gone.
    if (!isNull _threat && {!alive _threat}) exitWith {
        [_side,_reservationId,"threat-gone"] call ITW_CLASH_ETB_fnc_Cancel;
        ["THREAT_GONE",[_class]] call _deny
    };

    ([_side,_capability,_class,_reference] call ITW_CLASH_Generation_fnc_ETBSpawnPoint) params [
        "_spawnKind","_spawnReason","_origin"
    ];
    if (_spawnKind isEqualTo "") exitWith {
        [_side,_reservationId,toLowerANSI _spawnReason] call ITW_CLASH_ETB_fnc_Cancel;
        [_spawnReason,[_class]] call _deny
    };

    private _crewInfo = [_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes;
    _crewInfo params ["_crewTypes","_unitTypes"];
    if (_crewTypes isEqualTo [] || {_unitTypes isEqualTo []}) exitWith {
        [_side,_reservationId,"no-faction-crew"] call ITW_CLASH_ETB_fnc_Cancel;
        ["NO_CANDIDATE",["no-faction-crew"]] call _deny
    };

    private _veh = [[_class],_crewTypes,_unitTypes,_side,_origin,-1] call ITW_AtkSpawnVeh;
    if (isNull _veh) exitWith {
        [_side,_reservationId,"spawn-failed"] call ITW_CLASH_ETB_fnc_Cancel;
        ["SPAWN_FAILED",[_class,_spawnKind]] call _deny
    };
    private _crewGroup = group driver _veh;

    // What actually spawned, with its real pylons. A class the config promised
    // would answer this capability and does not is deleted and never tried for
    // it again.
    if !([_veh,_capability] call ITW_CLASH_Generation_fnc_ETBQualifiesVehicle) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        [_capability,_class,"post-spawn-check"] call ITW_CLASH_Generation_fnc_ETBRejectClass;
        [_side,_reservationId,"post-spawn-check"] call ITW_CLASH_ETB_fnc_Cancel;
        ["NO_CANDIDATE",[_class,"post-spawn-check"]] call _deny
    };

    if !([_veh,_crewGroup,_hq,_capability] call ITW_CLASH_Generation_fnc_ETBRegisterAsset) exitWith {
        deleteVehicleCrew _veh;
        deleteVehicle _veh;
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
        [_side,_reservationId,"hal-registration-failed"] call ITW_CLASH_ETB_fnc_Cancel;
        ["HAL_REGISTRATION_FAILED",[_class]] call _deny
    };

    [_veh,true] remoteExec ["allowDamage",_veh];
    {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;

    if !([_side,_reservationId,_veh,_crewGroup,_threatKey] call ITW_CLASH_ETB_fnc_Commit) exitWith {
        ["HAL_REGISTRATION_FAILED",[_class,"commit-failed"]] call _deny
    };

    ["etb-asset-provided",[
        _hq getVariable ["RydHQ_CodeSign","?"],_capability,_class,
        [_rowIndex] call ITW_CLASH_ETB_fnc_RowKey,round _price,_spawnKind,_threatKey
    ]] call ITW_CLASH_Generation_fnc_Log;

    createHashMapFromArray [
        ["status","APPROVED"],["reason","provided"],["capability",_capability],
        ["detail",[_class,_price,_spawnKind]],["asset",_veh],["group",_crewGroup]
    ]
};

// Is there a row for this capability at all, beyond the side's current
// escalation? It tells PROGRESSION_LOCKED apart from an honest NO_CANDIDATE.
ITW_CLASH_Generation_fnc_ETBAnyRow = {
    params ["_side","_capability"];
    if (isNil "ITW_VehArrays") exitWith {false};
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _index = ITW_VehArrays findIf {
        private _row = _x;
        (_row#ITW_VEH_IS_FRIENDLY) isEqualTo _friendly
        && {(_row#ITW_VEH_ROLE) in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]}
        && {
            ((_row#ITW_VEH_CLASSES) findIf {
                [[_x] call ITW_CLASH_Generation_fnc_NormalizeClass,_capability] call
                    ITW_CLASH_Generation_fnc_ETBQualifiesClass
            }) >= 0
        }
    };
    _index >= 0
};

// The cheapest counter this need could be answered with right now, for escrow:
// whether a bypassed demand is reachable at all depends on what it would cost.
ITW_CLASH_Generation_fnc_ETBCheapestPrice = {
    params ["_side","_need"];
    private _cheapest = -1;
    {
        private _candidates = [_side,_x] call ITW_CLASH_Generation_fnc_ETBCandidates;
        if (_candidates isNotEqualTo []) then {
            private _price = (_candidates#0)#2;
            if (_cheapest < 0 || {_price < _cheapest}) then {_cheapest = _price};
        };
    } forEach ([_need] call ITW_CLASH_Generation_fnc_ETBProvidersFor);
    _cheapest
};

ITW_CLASH_ForceGenerationReady = true;
diag_log format [
    "CLASH BOOT | force-generation-ready | version=%1 resolver=symmetric-itw-graph artillery=interstitial logistics=rear ticketing=itw-surrogate bothSides=true halTacticalAuthority=true etbProviders=GROUND_ANTI_ARMOR,ANTI_ARMOR_CAS,CAP_AIRCRAFT,SPAA etbVehDefStamped=false",
    ITW_CLASH_ForceGenerationVersion
];
true
