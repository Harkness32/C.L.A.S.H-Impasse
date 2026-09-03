#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_DualHALCheckbookStarted",false]) exitWith {true};

ITW_CLASH_DualHALCheckbookStarted = true;
ITW_CLASH_DualHALCheckbookVersion = 5;
ITW_CLASH_DualHALReady = false;
ITW_CLASH_CheckbookEnabled = true;
ITW_CLASH_CommanderRegistry = createHashMap;
ITW_CLASH_BLUFORLeader = objNull;
ITW_CLASH_BLUFORHQ = grpNull;
ITW_CLASH_BLUFORObjectiveMirrors = createHashMap;
ITW_CLASH_DualHALBLUFORGroups = [];
ITW_CLASH_DualHALOPFORExtraGroups = [];
ITW_CLASH_CheckbookAssets = [];
ITW_CLASH_CheckbookRequestSerial = 0;

ITW_CLASH_DualHAL_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["dual-hal-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH DUAL HAL | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_DualHAL_fnc_SideKey = {
    params ["_side"];
    toUpperANSI (str _side)
};

ITW_CLASH_fnc_GetCommanderForSide = {
    params ["_side"];
    if (!isNil "ITW_EnemySide" && {_side == ITW_EnemySide}) exitWith {
        missionNamespace getVariable ["ITW_CLASH_HALHQ",grpNull]
    };
    if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) exitWith {
        missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull]
    };
    private _entry = ITW_CLASH_CommanderRegistry getOrDefault [
        [_side] call ITW_CLASH_DualHAL_fnc_SideKey,[grpNull,objNull,""]
    ];
    _entry#0
};

ITW_CLASH_fnc_GetCommanderForGroup = {
    params ["_group"];
    if (isNull _group) exitWith {grpNull};
    [side _group] call ITW_CLASH_fnc_GetCommanderForSide
};

ITW_CLASH_DualHAL_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_fnc_GroupId
    };
    private _id = groupId _group;
    if (_id isEqualTo "") then {str _group} else {_id}
};

ITW_CLASH_DualHAL_fnc_IsPlayerGroup = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    ((units _group) findIf {isPlayer _x}) >= 0
};

ITW_CLASH_DualHAL_fnc_IsLifecycleReserved = {
    params ["_group",["_veh",objNull]];
    if (isNull _group) exitWith {true};

    if (_group getVariable ["ITW_CLASH_ExcludeHAL",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_CASEVAC",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_GroundMEDEVAC",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_ReconstitutionTransit",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_RecoveryOwned",false]) exitWith {true};
    if (_group getVariable ["itwDelivery",false]) exitWith {true};

    if (!isNull _veh) then {
        if (_veh getVariable ["ITW_CLASH_CASEVAC",false]) exitWith {true};
        if (_veh getVariable ["ITW_CLASH_GroundMEDEVAC",false]) exitWith {true};
        if (_veh getVariable ["ITW_CLASH_ReconstitutionTransport",false]) exitWith {true};
    };
    false
};

ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup = {
    params ["_group"];
    if !(missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]) exitWith {false};
    if (isNull _group || {isNil "ITW_PlayerSide"}) exitWith {false};
    if (side _group != ITW_PlayerSide) exitWith {false};
    if ([_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup) exitWith {false};
    if (time < (_group getVariable ["ITW_CLASH_ReeligibleAt",0])) exitWith {false};
    if ([_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved) exitWith {false};
    if (_group == ITW_CLASH_BLUFORHQ) exitWith {false};
    if (((units _group) findIf {!(_x isKindOf "Logic") && {!(_x isKindOf "VirtualMan_F")}}) < 0) exitWith {false};
    ({alive _x} count units _group) > 0
};

ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter = {
    params ["_group",["_vehInfo",[]]];
    if !(missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]) exitWith {false};
    if (isNull _group) exitWith {false};
    if ([_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup) exitWith {false};

    private _veh = if (
        _vehInfo isEqualType [] && {count _vehInfo > VEHINFO_VEH}
    ) then {_vehInfo#VEHINFO_VEH} else {vehicle leader _group};
    if ([_group,_veh] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved) exitWith {false};

    private _supported = false;
    if (!isNil "ITW_PlayerSide" && {side _group == ITW_PlayerSide}) then {_supported = true};
    if (!isNil "ITW_EnemySide" && {side _group == ITW_EnemySide}) then {_supported = true};
    _supported
};

ITW_CLASH_DualHAL_fnc_RegisterGroup = {
    params ["_group",["_reason","fielded"]];
    if (isNull _group || {[_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup}) exitWith {false};
    if (((units _group) findIf {!(_x isKindOf "Logic") && {!(_x isKindOf "VirtualMan_F")}}) < 0) exitWith {false};

    private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    if (isNull _hq || {_group == _hq}) exitWith {false};

    private _slot = if (!isNil "ITW_PlayerSide" && {side _group == ITW_PlayerSide}) then {"B"} else {"A"};
    _group setVariable ["ITW_CLASH_DualHALManaged",true];
    _group setVariable ["ITW_CLASH_CommanderSlot",_slot];
    _group setVariable ["ITW_CLASH_Authority","HAL_FIELD"];
    _group setVariable ["ITW_CLASH_AuthorityReason",_reason];

    // Preserve the native Impasse formation template before attrition so
    // side-symmetric reconstitution can rebuild the original squad.
    if ((_group getVariable ["ITW_CLASH_Archetype",[]]) isEqualTo []) then {
        private _archetype = (units _group) apply {toLowerANSI typeOf _x};
        if (_archetype isNotEqualTo []) then {
            _group setVariable ["ITW_CLASH_Archetype",+_archetype];
        };
    };
    if ((_group getVariable ["ITW_CLASH_Lineage",""]) isEqualTo "") then {
        _group setVariable [
            "ITW_CLASH_Lineage",
            [_group] call ITW_CLASH_DualHAL_fnc_GroupId
        ];
    };

    if (_slot == "B") then {
        ITW_CLASH_DualHALBLUFORGroups pushBackUnique _group;
    } else {
        ITW_CLASH_DualHALOPFORExtraGroups pushBackUnique _group;
    };

    private _included = +(_hq getVariable ["RydHQ_Included",[]]);
    _included pushBackUnique _group;
    _hq setVariable ["RydHQ_Included",_included];

    if !(_group getVariable ["ITW_CLASH_DualHALAdmissionLogged",false]) then {
        _group setVariable ["ITW_CLASH_DualHALAdmissionLogged",true];
        ["group-admitted",[
            [_group] call ITW_CLASH_DualHAL_fnc_GroupId,
            _slot,
            side _group,
            _reason,
            count units _group,
            typeOf (vehicle (leader _group))
        ]] call ITW_CLASH_DualHAL_fnc_Log;
    };
    true
};

ITW_CLASH_DualHAL_fnc_SyncIncluded = {
    if (!isNull ITW_CLASH_BLUFORHQ) then {
        ITW_CLASH_DualHALBLUFORGroups = ITW_CLASH_DualHALBLUFORGroups select {
            !isNull _x && {{alive _x} count units _x > 0}
        };
        // Keep the durable registry intact, but expose only groups whose
        // current lifecycle belongs to HAL. A boarded CASEVAC/MEDEVAC group
        // temporarily disappears from Included and automatically returns if
        // recovery aborts and the lifecycle markers clear.
        private _blu = ITW_CLASH_DualHALBLUFORGroups select {
            [_x] call ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup
        };
        ITW_CLASH_BLUFORHQ setVariable ["RydHQ_Included",_blu];
        RydHQB_Included = +_blu;
    };

    if (!isNil "ITW_CLASH_HALHQ" && {!isNull ITW_CLASH_HALHQ}) then {
        ITW_CLASH_DualHALOPFORExtraGroups = ITW_CLASH_DualHALOPFORExtraGroups select {
            !isNull _x && {{alive _x} count units _x > 0}
        };
        private _legacy = if (isNil "ITW_CLASH_ManagedGroups") then {[]} else {
            ITW_CLASH_ManagedGroups select {!isNull _x && {{alive _x} count units _x > 0}}
        };
        private _included = _legacy + ITW_CLASH_DualHALOPFORExtraGroups;
        _included = _included arrayIntersect _included;
        ITW_CLASH_HALHQ setVariable ["RydHQ_Included",_included];
        RydHQ_Included = +_included;
    };
    true
};

ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives = {
    if (isNil "ITW_CLASH_fnc_GetActiveObjectives" || {
        isNil "ITW_ObjContestedOwnerIsFriendly"
    }) exitWith {[]};

    private _active = call ITW_CLASH_fnc_GetActiveObjectives;
    private _activeKeys = [];
    private _mirrors = [];

    {
        _x params ["_objectiveIndex","_flag"];
        private _key = str _objectiveIndex;
        _activeKeys pushBack _key;

        private _mirror = ITW_CLASH_BLUFORObjectiveMirrors getOrDefault [_key,objNull];
        private _pos = [_objectiveIndex,_flag] call ITW_CLASH_fnc_GetObjectiveCenter;
        if (_pos isEqualTo []) then {continue};

        if (isNull _mirror) then {
            _mirror = createVehicle ["Land_HelipadEmpty_F",_pos,[],0,"CAN_COLLIDE"];
            _mirror hideObjectGlobal true;
            _mirror enableSimulationGlobal false;
            _mirror allowDamage false;
            _mirror setVariable ["ITW_CLASH_ObjectiveIndex",_objectiveIndex,true];
            ITW_CLASH_BLUFORObjectiveMirrors set [_key,_mirror];
        } else {
            _mirror setPosATL _pos;
        };

        private _friendlyOwned = [_objectiveIndex] call ITW_ObjContestedOwnerIsFriendly;
        _mirror setVariable ["SetTakenA",_friendlyOwned,true];
        _mirror setVariable ["ITW_CLASH_BLUFOROwned",_friendlyOwned,true];
        _mirrors pushBack _mirror;
    } forEach _active;

    {
        if !(_x in _activeKeys) then {
            private _old = ITW_CLASH_BLUFORObjectiveMirrors getOrDefault [_x,objNull];
            if (!isNull _old) then {deleteVehicle _old};
            ITW_CLASH_BLUFORObjectiveMirrors deleteAt _x;
        };
    } forEach +(keys ITW_CLASH_BLUFORObjectiveMirrors);

    RydHQB_SimpleObjs = +_mirrors;
    if (!isNull ITW_CLASH_BLUFORHQ) then {
        ITW_CLASH_BLUFORHQ setVariable ["RydHQ_SimpleObjs",+_mirrors];
    };
    _mirrors
};

ITW_CLASH_DualHAL_fnc_ConfigureBLUFORGlobals = {
    RydHQB_Wait = 1;
    RydHQB_SubAll = false;
    RydHQB_SubSynchro = false;
    RydHQB_Included = [];
    RydHQB_Excluded = [];
    RydHQB_NoDef = [];
    RydHQB_NoAttack = [];
    RydHQB_NoRecon = [];
    RydHQB_CargoFind = 1;
    RydHQB_NoAirCargo = false;
    RydHQB_NoLandCargo = false;
    RydHQB_SecTasks = false;
    RydHQB_ResetOnDemand = false;
    RydHQB_ResetTime = 30;
    RydHQB_Order = "ATTACK";
    RydHQB_Berserk = false;
    RydHQB_AttackAlways = false;
    RydHQB_IdleDef = true;
    RydHQB_DefendObjectives = 1;
    RydHQB_CRDefRes = missionNamespace getVariable ["ITW_CLASH_ReserveRatio",0.15];
    RydHQB_MAtt = true;
    RydHQB_Personality = "COMPETENT";
    RydHQB_Recklessness = 0.5;
    RydHQB_Consistency = 0.5;
    RydHQB_Activity = 0.5;
    RydHQB_Reflex = 0.5;
    RydHQB_Circumspection = 0.5;
    RydHQB_Fineness = 0.5;
    RydHQB_SimpleMode = true;
    RydHQB_SimpleObjs = [];
    RydHQB_MaxSimpleObjs = 4;
    RydHQB_GetHQInside = false;
    RydHQB_LRelocating = false;
    true
};

ITW_CLASH_DualHAL_fnc_PrepareCommanderB = {
    if (!isNull ITW_CLASH_BLUFORHQ) exitWith {true};
    if (isNil "ITW_PlayerSide") exitWith {false};

    call ITW_CLASH_DualHAL_fnc_ConfigureBLUFORGlobals;

    // Native HAL cargo is now a tactical service. A may request it as well;
    // C.L.A.S.H./Impasse only provides missing capacity.
    RydHQ_CargoFind = 1;
    RydHQ_NoAirCargo = false;
    RydHQ_NoLandCargo = false;

    private _pos = [100,100,0];
    if (!isNil "ITW_Bases" && {count ITW_Bases > 0}) then {
        _pos = +(ITW_Bases#0#ITW_BASE_POS);
    };
    if (_pos isEqualTo [] && {!isNil "ITW_Objectives" && {count ITW_Objectives > 0}}) then {
        _pos = +(ITW_Objectives#0#ITW_OBJ_POS);
    };

    private _class = if (ITW_PlayerSide == west) then {"B_officer_F"} else {
        if (ITW_PlayerSide == resistance) then {"I_officer_F"} else {"O_officer_F"}
    };
    private _hq = createGroup [ITW_PlayerSide,true];
    private _leader = _hq createUnit [_class,_pos,[],0,"NONE"];
    _hq setGroupIdGlobal ["CLASH BLUFOR HQ"];
    _leader setPosATL _pos;
    _leader allowDamage false;
    _leader hideObjectGlobal true;
    _leader enableSimulationGlobal false;
    _hq setVariable ["ITW_CLASH_ExcludeHAL",true];
    _hq setVariable ["ITW_CLASH_CommanderSlot","B"];

    ITW_CLASH_BLUFORLeader = _leader;
    ITW_CLASH_BLUFORHQ = _hq;
    leaderHQB = _leader;
    publicVariable "leaderHQB";

    call ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives;

    ITW_CLASH_CommanderRegistry set [
        [ITW_PlayerSide] call ITW_CLASH_DualHAL_fnc_SideKey,
        [_hq,_leader,"B"]
    ];
    if (!isNil "ITW_EnemySide" && {!isNil "ITW_CLASH_HALHQ"}) then {
        ITW_CLASH_CommanderRegistry set [
            [ITW_EnemySide] call ITW_CLASH_DualHAL_fnc_SideKey,
            [ITW_CLASH_HALHQ,missionNamespace getVariable ["ITW_CLASH_HALLeader",objNull],"A"]
        ];
    };

    ["commander-b-created",[side _hq,_pos,count RydHQB_SimpleObjs]] call
        ITW_CLASH_DualHAL_fnc_Log;
    true
};

ITW_CLASH_DualHAL_fnc_GetSupportSpawn = {
    params ["_side",["_mode","GROUND"],["_reference",[]]];
    if (isNil "ITW_Objectives" || {isNil "ITW_Bases"}) exitWith {[]};

    // V2 delegates geography to the symmetric ITW generation-node resolver.
    // Keep the legacy FOB-derived fallback below so transport remains fail-open
    // while the campaign graph is still being established.
    private _resolvedSpawn = [];
    if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
        private _resolved = [
            _side,
            "TRANSPORT",
            if (_mode == "AIR") then {"FORWARD_AIR"} else {"FORWARD"},
            _reference
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if (_resolved isEqualType createHashMap && {
            (_resolved getOrDefault ["status",""]) == "RESOLVED"
        }) then {
            _resolvedSpawn = [
                +(_resolved getOrDefault ["origin",[]]),
                _resolved getOrDefault ["forwardBase",-1],
                _resolved getOrDefault ["objective",-1],
                _resolved getOrDefault ["source","generation-node"]
            ];
        };
    };
    if (_resolvedSpawn isNotEqualTo []) exitWith {_resolvedSpawn};

    if (_reference isEqualTo []) then {
        _reference = if (!isNil "ITW_Bases" && {count ITW_Bases > 0}) then {
            ITW_Bases#0#ITW_BASE_POS
        } else {[0,0,0]};
    };

    private _slot = if (_mode == "AIR") then {
        if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) then {
            ITW_ATTACK_AIR_F
        } else {
            ITW_ATTACK_AIR_E
        }
    } else {
        if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) then {
            ITW_ATTACK_LAND_F
        } else {
            ITW_ATTACK_LAND_E
        }
    };

    private _candidates = [];
    if (!isNil "ITW_CLASH_fnc_GetActiveObjectives") then {
        {
            private _objectiveIndex = _x#0;
            if (_objectiveIndex < 0 || {_objectiveIndex >= count ITW_Objectives}) then {continue};
            private _attacks = ITW_Objectives#_objectiveIndex#ITW_OBJ_ATTACKS;
            if (_slot >= count _attacks) then {continue};
            private _baseIndex = _attacks#_slot;
            if (_baseIndex >= 0 && {_baseIndex < count ITW_Bases}) then {
                _candidates pushBackUnique [_baseIndex,_objectiveIndex];
            };
        } forEach (call ITW_CLASH_fnc_GetActiveObjectives);
    };

    if (_candidates isEqualTo []) then {
        private _wantedOwner = if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) then {
            ITW_OWNER_FRIENDLY
        } else {
            ITW_OWNER_ENEMY
        };
        {
            if ((_x#ITW_OBJ_OWNER) == _wantedOwner) then {
                private _baseIndex = _x#ITW_OBJ_INDEX;
                if (_baseIndex >= 0 && {_baseIndex < count ITW_Bases}) then {
                    _candidates pushBackUnique [_baseIndex,_forEachIndex];
                };
            };
        } forEach ITW_Objectives;
    };

    if (_candidates isEqualTo [] && {!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide} && {count ITW_Bases > 0}}) then {
        _candidates pushBack [0,0];
    };
    if (_candidates isEqualTo []) exitWith {[]};

    private _best = _candidates#0;
    private _bestDist = _reference distance2D (ITW_Bases#(_best#0)#ITW_BASE_POS);
    {
        private _dist = _reference distance2D (ITW_Bases#(_x#0)#ITW_BASE_POS);
        if (_dist < _bestDist) then {
            _best = _x;
            _bestDist = _dist;
        };
    } forEach _candidates;

    _best params ["_baseIndex","_objectiveIndex"];
    private _base = ITW_Bases#_baseIndex;
    private _spawn = +(_base#ITW_BASE_A_SPAWN);
    private _source = "attack-source-ai-spawn";
    if (_spawn isEqualTo []) then {
        _spawn = +(_base#ITW_BASE_POS);
        _source = "attack-source-base";
    };
    if (_mode == "AIR" && {_baseIndex < count ITW_Objectives}) then {
        private _vehicleSpawn = +(ITW_Objectives#_baseIndex#ITW_OBJ_V_SPAWN);
        if (_vehicleSpawn isNotEqualTo []) then {
            _spawn = _vehicleSpawn;
            _source = "attack-source-vehicle-staging";
        };
    };
    if (count _spawn < 3) then {_spawn pushBack 0};
    [_spawn,_baseIndex,_objectiveIndex,_source]
};

ITW_CLASH_DualHAL_fnc_StageFriendlyInfantry = {
    params ["_group",["_teleportToAttackPos",true],["_objToPopulate",[]]];
    if (isNull _group) exitWith {false};
    if (_group getVariable ["ITW_CLASH_DualHALManaged",false]) exitWith {true};

    private _reference = getPosATL leader _group;
    private _spawnInfo = [
        side _group,"GROUND",_reference
    ] call ITW_CLASH_DualHAL_fnc_GetSupportSpawn;
    if (_spawnInfo isEqualTo []) exitWith {false};

    _spawnInfo params ["_spawn","_baseIndex","_objectiveIndex","_source"];
    private _staging = _spawn getPos [15 + random 35,random 360];

    if (!isNil "ITW_AtkSafeMove") then {
        if (local _group) then {
            [_group,_staging] call ITW_AtkSafeMove;
        } else {
            [[_group,_staging],"ITW_AtkSafeMove",_group] call ITW_FncRemoteLocalGroup;
        };
    } else {
        {if (alive _x) then {_x setPosATL _staging}} forEach units _group;
    };

    {deleteWaypoint _x} forEachReversed waypoints _group;
    VAR_SET_OBJ_IDX(_group,_objectiveIndex);
    _group setVariable ["ITW_CLASH_DualHALObjectiveAffinity",_objectiveIndex];

    [_group,"impasse-spawn-support-corridor"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
    ["infantry-staged",[
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId,
        _baseIndex,_objectiveIndex,_source,_staging,
        _teleportToAttackPos,!(_objToPopulate isEqualTo [])
    ]] call ITW_CLASH_DualHAL_fnc_Log;
    true
};

ITW_CLASH_DualHAL_fnc_TrackAsset = {
    params ["_veh",["_vehDef",[]],["_source","impasse-field"]];
    if (isNull _veh) exitWith {false};
    if (_veh getVariable ["ITW_CLASH_CheckbookTracked",false]) exitWith {true};

    _veh setVariable ["ITW_CLASH_CheckbookTracked",true];
    _veh setVariable ["ITW_CLASH_CheckbookSource",_source];
    ITW_CLASH_CheckbookAssets pushBack [_veh,_vehDef,_source,false];
    true
};

ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn = {
    params ["_vehInfo"];
    if !(_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) exitWith {[]};

    private _veh = _vehInfo#VEHINFO_VEH;
    private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
    if (isNull _veh || {isNull _crewGroup}) exitWith {[]};

    private _vehType = _vehInfo#VEHINFO_TYPE;
    private _class = typeOf _veh;
    private _artilleryClasses = if (
        !isNil "ITW_PlayerSide" && {side _crewGroup == ITW_PlayerSide}
    ) then {
        missionNamespace getVariable ["ITW_CLASH_PlayerArtilleryClasses",[]]
    } else {
        missionNamespace getVariable ["ITW_CLASH_EnemyArtilleryClasses",[]]
    };
    private _isArtillery = _class in _artilleryClasses;

    private _profile = if (_isArtillery) then {
        "INTERSTITIAL"
    } else {
        if (_vehType in [ITW_TYPE_VEH_TANK,ITW_TYPE_VEH_APC]) then {
            "REAR"
        } else {
            "FORWARD"
        }
    };

    if (_profile == "FORWARD") exitWith {
        [
            side _crewGroup,
            if (_veh isKindOf "Air") then {"AIR"} else {"GROUND"},
            getPosATL _veh
        ] call ITW_CLASH_DualHAL_fnc_GetSupportSpawn
    };

    if (!isNil "ITW_CLASH_Generation_fnc_Resolve") then {
        private _resolved = [
            side _crewGroup,
            if (_isArtillery) then {"ARTILLERY"} else {"FIELD_ARMOR"},
            _profile,
            getPosATL _veh
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if (_resolved isEqualType createHashMap && {
            (_resolved getOrDefault ["status",""]) == "RESOLVED"
        }) exitWith {
            private _baseIndex = if (_profile == "REAR") then {
                _resolved getOrDefault ["rearBase",-1]
            } else {
                _resolved getOrDefault ["forwardBase",-1]
            };
            [
                +(_resolved getOrDefault ["origin",[]]),
                _baseIndex,
                _resolved getOrDefault ["objective",-1],
                format [
                    "field-%1-%2",
                    toLowerANSI _profile,
                    _resolved getOrDefault ["source","generation-node"]
                ]
            ]
        };
    };

    // Never deliberately fall artillery back into a protected FOB when the
    // interstitial geometry cannot be resolved. Preserve its native physical
    // origin and let HAL own tactical employment from there.
    if (_isArtillery) exitWith {
        [
            getPosATL _veh,
            -1,
            VAR_GET_OBJ_IDX(_crewGroup),
            "field-interstitial-unresolved-native-origin"
        ]
    };

    // Rear armor resolution should normally be available once ForceGeneration
    // is live. Fail open to native field position instead of moving heavy armor
    // forward in violation of the echelon contract.
    [
        getPosATL _veh,
        -1,
        VAR_GET_OBJ_IDX(_crewGroup),
        "field-rear-unresolved-native-origin"
    ]
};

ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];
    if !(_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) exitWith {false};

    private _veh = _vehInfo#VEHINFO_VEH;
    private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
    private _cargoGroups = +(_vehInfo#VEHINFO_CARGO_GRPS);
    if (isNull _veh || {isNull _crewGroup}) exitWith {false};

    if (_crewGroup getVariable ["ITW_CLASH_DualHALManaged",false]) exitWith {true};

    private _mode = if (_veh isKindOf "Air") then {"AIR"} else {"GROUND"};
    private _spawnInfo = [
        _vehInfo
    ] call ITW_CLASH_DualHAL_fnc_GetFieldVehicleSpawn;
    if (_spawnInfo isEqualTo []) exitWith {false};
    _spawnInfo params ["_spawn","_baseIndex","_objectiveIndex","_source"];

    private _staging = _spawn getPos [80 + random 100,random 360];
    if (_veh isKindOf "Air") then {
        private _safe = [_staging,0,250,25,0,0.25,0,[],[_staging,_staging]] call BIS_fnc_findSafePos;
        if (_safe isNotEqualTo []) then {_staging = _safe};
    };
    if (count _staging < 3) then {_staging pushBack 0};

    ALLOW_DAMAGE(_veh,false);
    if (local _veh) then {
        _veh setPosATL _staging;
    } else {
        [_veh,_staging] remoteExec ["setPosATL",_veh];
    };
    [_veh] spawn {
        params ["_veh"];
        sleep 2;
        if (!isNull _veh) then {ALLOW_DAMAGE(_veh,true)};
    };

    // Existing Impasse wave transports become HAL-owned capacity instead of
    // executing the pre-scripted assault insertion. Their cargo is staged at
    // the same rear interface and HAL may immediately request the vehicle again.
    private _cargoStaging = _spawn getPos [20 + random 30,random 360];
    {
        private _cargoGroup = _x;
        if (isNull _cargoGroup || {[_cargoGroup] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup}) then {continue};
        _cargoGroup leaveVehicle _veh;
        {
            unassignVehicle _x;
            [_x] orderGetIn false;
            moveOut _x;
        } forEach units _cargoGroup;
        if (!isNil "ITW_AtkSafeMove") then {
            if (local _cargoGroup) then {
                [_cargoGroup,_cargoStaging] call ITW_AtkSafeMove;
            } else {
                [[_cargoGroup,_cargoStaging],"ITW_AtkSafeMove",_cargoGroup] call ITW_FncRemoteLocalGroup;
            };
        };

        if (!isNil "ITW_PlayerSide" && {side _cargoGroup == ITW_PlayerSide}) then {
            [_cargoGroup,"legacy-impasse-cargo-staged"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
        } else {
            if (!isNil "ITW_EnemySide" && {side _cargoGroup == ITW_EnemySide} && {!isNil "ITW_EnemyGroupCallback"}) then {
                [_cargoGroup] call ITW_EnemyGroupCallback;
            };
        };
    } forEach _cargoGroups;
    _vehInfo set [VEHINFO_CARGO_GRPS,[]];

    VAR_SET_OBJ_IDX(_crewGroup,_objectiveIndex);
    [_crewGroup,"impasse-vehicle-handoff"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
    _veh setVariable ["ITW_CLASH_DualHALManaged",true];

    private _role = _vehInfo#VEHINFO_ROLE;
    if (_role in [ITW_VEH_ROLE_TRANSPORT,ITW_VEH_ROLE_DUAL]) then {
        private _hq = [_crewGroup] call ITW_CLASH_fnc_GetCommanderForGroup;
        if (!isNull _hq) then {
            private _cargo = +(_hq getVariable ["RydHQ_CargoG",[]]);
            _cargo pushBackUnique _crewGroup;
            _hq setVariable ["RydHQ_CargoG",_cargo];

            private _cargoOnly = +(_hq getVariable ["RydHQ_CargoOnly",[]]);
            _cargoOnly pushBackUnique _crewGroup;
            _hq setVariable ["RydHQ_CargoOnly",_cargoOnly];

            {
                private _arr = +(_hq getVariable [_x,[]]);
                _arr pushBackUnique _crewGroup;
                _hq setVariable [_x,_arr];
            } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];

            if (_veh isKindOf "Air") then {
                private _air = +(_hq getVariable ["RydHQ_AirG",[]]);
                _air pushBackUnique _crewGroup;
                _hq setVariable ["RydHQ_AirG",_air];
            };
        };
    };

    private _vehDef = _veh getVariable ["ITW_VehDef",[]];
    if (_vehDef isEqualTo []) then {
        [_veh] spawn {
            params ["_veh"];
            private _deadline = time + 10;
            waitUntil {
                sleep 0.25;
                isNull _veh || {
                    (_veh getVariable ["ITW_VehDef",[]]) isNotEqualTo [] || {time >= _deadline}
                }
            };
            if (!isNull _veh) then {
                private _def = _veh getVariable ["ITW_VehDef",[]];
                [_veh,_def,"impasse-field-handoff"] call ITW_CLASH_DualHAL_fnc_TrackAsset;
            };
        };
    } else {
        [_veh,_vehDef,"impasse-field-handoff"] call ITW_CLASH_DualHAL_fnc_TrackAsset;
    };

    ["vehicle-staged",[
        [_crewGroup] call ITW_CLASH_DualHAL_fnc_GroupId,
        typeOf _veh,_role,_baseIndex,_objectiveIndex,_source,count _cargoGroups
    ]] call ITW_CLASH_DualHAL_fnc_Log;
    true
};

ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles = {
    if (isNil "ITW_ManagedVehs" || {isNil "ITW_AtkVehicleManagerBusy"}) exitWith {0};
    private _migrated = 0;

    SEM_LOCK(ITW_AtkVehicleManagerBusy);
    for "_i" from ((count ITW_ManagedVehs) - 1) to 0 step -1 do {
        private _vehInfo = ITW_ManagedVehs#_i;
        if !(_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CARGO_GRPS}) then {continue};

        private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
        private _veh = _vehInfo#VEHINFO_VEH;
        private _cargo = _vehInfo#VEHINFO_CARGO_GRPS;
        if (isNull _veh || {isNull _crewGroup} || {_cargo isNotEqualTo []}) then {continue};
        if !([_crewGroup,_vehInfo] call ITW_CLASH_DualHAL_fnc_ShouldSuppressImpasseVehicleWriter) then {
            continue
        };

        ITW_ManagedVehs deleteAt _i;
        VAR_SET_OBJ_IDX(_crewGroup,-1);
        [_crewGroup,"managed-vehicle-migration"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
        _veh setVariable ["ITW_CLASH_DualHALManaged",true];

        private _vehDef = _veh getVariable ["ITW_VehDef",[]];
        [_veh,_vehDef,"managed-vehicle-migration"] call ITW_CLASH_DualHAL_fnc_TrackAsset;
        _migrated = _migrated + 1;

        ["vehicle-migrated",[
            [_crewGroup] call ITW_CLASH_DualHAL_fnc_GroupId,
            typeOf _veh,
            _vehInfo#VEHINFO_ROLE
        ]] call ITW_CLASH_DualHAL_fnc_Log;
    };
    SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
    _migrated
};

ITW_CLASH_Checkbook_fnc_GetZonesOwned = {
    params ["_friendly"];
    private _zoneIndex = missionNamespace getVariable ["ITW_ZoneIndex",0];
    private _zoneCount = if (isNil "ITW_Zones") then {1} else {count ITW_Zones};
    if (_friendly || {missionNamespace getVariable ["ITW_ParamVehicleEscalation",0] == 1}) then {
        (_zoneIndex - 1) max 0
    } else {
        (_zoneCount - _zoneIndex) max 0
    }
};

ITW_CLASH_Checkbook_fnc_SelectTransportDefs = {
    params ["_side","_mode","_seatCount"];
    if (isNil "ITW_VehArrays") exitWith {[]};

    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _zonesOwned = [_friendly] call ITW_CLASH_Checkbook_fnc_GetZonesOwned;
    private _defs = ITW_VehArrays select {
        private _def = _x;
        private _role = _def#ITW_VEH_ROLE;
        private _type = _def#ITW_VEH_TYPE;
        private _sideMatch = (_def#ITW_VEH_IS_FRIENDLY) == _friendly;
        private _modeMatch = if (_mode == "AIR") then {
            _type == ITW_TYPE_VEH_HELI
        } else {
            ITW_VEH_IS_LAND(_type)
        };
        _sideMatch
        && {_role in [ITW_VEH_ROLE_TRANSPORT,ITW_VEH_ROLE_DUAL]}
        && {_modeMatch}
        && {_def#ITW_VEH_ZONES_OWNED <= _zonesOwned}
        && {_def#ITW_VEH_CURR_TICKETS >= _def#ITW_VEH_REQD_TICKETS}
        && {_def#ITW_VEH_COUNT < _def#ITW_VEH_MAX}
    };

    [_defs,[],{
        private _roleBias = if ((_x#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT) then {0} else {10000};
        _roleBias + (_x#ITW_VEH_REQD_TICKETS)
    },"ASCEND"] call BIS_fnc_sortBy
};

ITW_CLASH_Checkbook_fnc_GetCrewTypes = {
    params ["_side"];
    private _friendly = !isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide};
    private _factions = if (_friendly) then {
        missionNamespace getVariable ["ITW_PlayerFaction",[]]
    } else {
        missionNamespace getVariable ["ITW_EnemyFaction",[]]
    };

    private _fallback = if (_friendly) then {
        call FACTION_UNIT_FALLBACK_SUBF_BLU
    } else {
        call FACTION_UNIT_FALLBACK_SUBF_OPF
    };
    private _rawUnitTypes = ([_factions,["Crewman","Diver"],true,_fallback] call FactionUnits) apply {
        toLowerANSI _x
    };
    private _rawCrewTypes = ([
        _factions,["Crewman"],false,call FACTION_UNIT_FALLBACK_ROLE_REQ
    ] call FactionUnits) apply {toLowerANSI _x};
    private _validManClass = {
        params ["_class"];
        _class isEqualType "" && {
            _class isNotEqualTo "" && {
                isClass (configFile >> "CfgVehicles" >> _class) && {
                    _class isKindOf "CAManBase"
                }
            }
        }
    };
    private _unitTypes = _rawUnitTypes select {[_x] call _validManClass};
    private _crewTypes = _rawCrewTypes select {[_x] call _validManClass};
    if (_crewTypes isEqualTo []) then {_crewTypes = +_unitTypes};
    if (
        count _unitTypes != count _rawUnitTypes
        || {count _crewTypes != count _rawCrewTypes}
    ) then {
        ["crew-pool-sanitized",[
            _side,count _unitTypes,count _rawUnitTypes,count _crewTypes,count _rawCrewTypes
        ]] call ITW_CLASH_DualHAL_fnc_Log;
    };
    [_crewTypes,_unitTypes]
};

ITW_CLASH_Checkbook_fnc_RegisterTransport = {
    params ["_veh","_crewGroup","_vehDef","_hq","_requestId","_source"];
    if (isNull _veh || {isNull _crewGroup} || {isNull _hq}) exitWith {false};

    _veh setVariable ["ITW_VehDef",_vehDef];
    _veh setVariable ["ITW_CLASH_CheckbookAsset",true,true];
    _veh setVariable ["ITW_CLASH_CheckbookRequest",_requestId,true];
    _crewGroup setVariable ["ITW_CLASH_CheckbookAsset",true];
    _crewGroup setVariable ["ITW_CLASH_CheckbookRequest",_requestId];
    _crewGroup setVariable ["START" + str _crewGroup,getPosATL _veh];
    private _injectCycle = _hq getVariable ["RydHQ_Cyclecount",-1];
    _crewGroup setVariable ["ITW_CLASH_CheckbookInjectedCycle",_injectCycle];
    _veh setVariable ["ITW_CLASH_CheckbookInjectedCycle",_injectCycle,true];

    [_crewGroup,"checkbook-transport"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;

    private _cargo = +(_hq getVariable ["RydHQ_CargoG",[]]);
    _cargo pushBackUnique _crewGroup;
    _hq setVariable ["RydHQ_CargoG",_cargo];

    private _cargoOnly = +(_hq getVariable ["RydHQ_CargoOnly",[]]);
    _cargoOnly pushBackUnique _crewGroup;
    _hq setVariable ["RydHQ_CargoOnly",_cargoOnly];

    {
        private _arr = +(_hq getVariable [_x,[]]);
        _arr pushBackUnique _crewGroup;
        _hq setVariable [_x,_arr];
    } forEach ["RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef"];

    if (_veh isKindOf "Air") then {
        private _air = +(_hq getVariable ["RydHQ_AirG",[]]);
        _air pushBackUnique _crewGroup;
        _hq setVariable ["RydHQ_AirG",_air];
    };

    if ((_vehDef#ITW_VEH_ROLE) == ITW_VEH_ROLE_TRANSPORT && {!isNil "ITW_AtkVehRemoveMagazines"}) then {
        [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
    };

    [_veh,_vehDef,_source] call ITW_CLASH_DualHAL_fnc_TrackAsset;

    // ITW_AtkSpawnVeh deliberately creates vehicles damage-protected and the
    // normal Impasse field pipeline releases that protection later. Checkbook
    // bypasses that pipeline, so the HAL handoff is the matching release point.
    ALLOW_DAMAGE(_veh,true);
    true
};

ITW_CLASH_Checkbook_fnc_RequestTransport = {
    params ["_requester","_hq","_destination","_mode",["_seatCount",1],["_externalRequestId",""]];
    if !(missionNamespace getVariable ["ITW_CLASH_CheckbookEnabled",true]) exitWith {objNull};
    if (isNull _requester || {isNull _hq} || {_destination isEqualTo []}) exitWith {objNull};
    if !(_mode in ["AIR","GROUND"]) exitWith {objNull};

    private _side = side _requester;
    private _defs = [_side,_mode,_seatCount] call ITW_CLASH_Checkbook_fnc_SelectTransportDefs;
    private _requestId = _externalRequestId;
    if (_requestId isEqualTo "") then {
        ITW_CLASH_CheckbookRequestSerial = ITW_CLASH_CheckbookRequestSerial + 1;
        _requestId = format [
            "CB-%1-%2-%3",round time,ITW_CLASH_CheckbookRequestSerial,_mode
        ];
    };

    if (_defs isEqualTo []) exitWith {
        ["checkbook-denied",[
            _requestId,[_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
            side _requester,_mode,_seatCount,"no-affordable-capability"
        ]] call ITW_CLASH_DualHAL_fnc_Log;
        objNull
    };

    private _spawnInfo = [
        _side,_mode,getPosATL leader _requester
    ] call ITW_CLASH_DualHAL_fnc_GetSupportSpawn;
    if (_spawnInfo isEqualTo []) exitWith {
        ["checkbook-denied",[
            _requestId,[_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
            side _requester,_mode,_seatCount,"no-support-spawn"
        ]] call ITW_CLASH_DualHAL_fnc_Log;
        objNull
    };
    _spawnInfo params ["_spawn","_baseIndex","_objectiveIndex","_spawnSource"];

    private _crewInfo = [_side] call ITW_CLASH_Checkbook_fnc_GetCrewTypes;
    _crewInfo params ["_crewTypes","_unitTypes"];
    if (_crewTypes isEqualTo [] || {_unitTypes isEqualTo []}) exitWith {
        ["checkbook-denied",[
            _requestId,[_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
            side _requester,_mode,_seatCount,"no-faction-crew"
        ]] call ITW_CLASH_DualHAL_fnc_Log;
        objNull
    };

    private _result = objNull;
    {
        if (!isNull _result) then {continue};
        private _vehDef = _x;
        private _veh = [_vehDef,_crewTypes,_unitTypes,_side,_spawn] call ITW_AtkSpawnVeh;
        if (isNull _veh) then {continue};

        private _crewGroup = group driver _veh;
        private _capacity = _veh emptyPositions "";
        private _kindOK = if (_mode == "AIR") then {
            _veh isKindOf "Helicopter"
        } else {
            _veh isKindOf "LandVehicle"
        };
        if (!_kindOK || {_capacity < _seatCount}) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        private _registered = [_veh,_crewGroup,_vehDef,_hq,_requestId,"checkbook"] call
            ITW_CLASH_Checkbook_fnc_RegisterTransport;
        if (!_registered) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {
                deleteGroup _crewGroup;
            };
            continue;
        };

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        ITW_TICKET_REDUCE(_vehDef);

        {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;
        _result = _veh;

        ["checkbook-approved",[
            _requestId,[_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
            side _requester,_mode,_seatCount,typeOf _veh,_capacity,
            _baseIndex,_objectiveIndex,_spawnSource,
            _vehDef#ITW_VEH_REQD_TICKETS,_vehDef#ITW_VEH_CURR_TICKETS
        ]] call ITW_CLASH_DualHAL_fnc_Log;
    } forEach _defs;

    if (isNull _result) then {
        ["checkbook-denied",[
            _requestId,[_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
            side _requester,_mode,_seatCount,"spawn-or-capacity-failed"
        ]] call ITW_CLASH_DualHAL_fnc_Log;
    };
    _result
};

ITW_CLASH_Checkbook_fnc_HasCargoCapacity = {
    params ["_hq","_requester","_mode","_seatCount"];
    if (isNull _hq) exitWith {false};
    private _cargo = +(_hq getVariable ["RydHQ_CargoG",[]]);
    (_cargo findIf {
        private _group = _x;
        private _valid = !isNull _group && {{alive _x} count units _group > 0};
        private _veh = if (_valid) then {assignedVehicle leader _group} else {objNull};
        private _modeOK = _valid && {!isNull _veh} && {
            if (_mode == "AIR") then {_veh isKindOf "Air"} else {!(_veh isKindOf "Air")}
        };
        _modeOK
        && {!(_group getVariable ["Busy" + str _group,false])}
        && {!(_group getVariable ["Unable",false])}
        && {alive _veh}
        && {canMove _veh}
        && {_veh emptyPositions "" >= _seatCount}
        && {(assignedCargo _veh) isEqualTo []}
    }) >= 0
};

ITW_CLASH_Checkbook_fnc_CargoMode = {
    params ["_requester","_hq","_destination",["_withdraw",false],["_requestAir",false],["_requestGround",false]];
    if (_withdraw) exitWith {""};
    if (_requestGround) exitWith {"GROUND"};

    // This is HAL state, not Impasse state. If HAL's own picture contains air
    // or AA threats, C.L.A.S.H. does not write an AIR check. The untouched
    // native SCargo routine remains the final tactical authority either way.
    private _airThreats = (_hq getVariable ["RydHQ_AAthreat",[]]) +
        (_hq getVariable ["RydHQ_Airthreat",[]]);
    private _airPermittedByHAL = _airThreats isEqualTo [];

    if (_requestAir) exitWith {
        if (_airPermittedByHAL) then {"AIR"} else {""}
    };

    private _from = getPosATL leader _requester;
    private _offRoad = ((count (_from nearRoads 100)) < 1) || {
        (count (_destination nearRoads 100)) < 1
    };
    if (!_offRoad) exitWith {"GROUND"};
    if (!_airPermittedByHAL) exitWith {""};
    "AIR"
};

ITW_CLASH_DualHAL_fnc_InstallCargoHook = {
    if (missionNamespace getVariable ["ITW_CLASH_CheckbookCargoHookReady",false]) exitWith {true};
    if (isNil "HAL_SCargo") exitWith {false};

    ITW_CLASH_Checkbook_fnc_NativeSCargo = HAL_SCargo;
    HAL_SCargo = {
        private _requester = _this param [0,grpNull];
        private _hq = _this param [1,grpNull];
        private _destination = _this param [2,[]];
        private _withdraw = _this param [3,false];
        private _requestAir = _this param [4,false];
        private _requestGround = _this param [5,false];

        if (
            !isNull _requester
            && {!isNull _hq}
            && {_destination isNotEqualTo []}
            && {!_withdraw}
            && {!([_requester] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup)}
            && {missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]}
        ) then {
            private _mode = [
                _requester,_hq,_destination,_withdraw,_requestAir,_requestGround
            ] call ITW_CLASH_Checkbook_fnc_CargoMode;

            if (_mode isNotEqualTo "") then {
                private _seatCount = {alive _x} count units _requester;
                private _has = [
                    _hq,_requester,_mode,_seatCount
                ] call ITW_CLASH_Checkbook_fnc_HasCargoCapacity;
                if (!_has) then {
                    ["cargo-request",[
                        [_requester] call ITW_CLASH_DualHAL_fnc_GroupId,
                        _hq getVariable ["RydHQ_CodeSign","?"],
                        _mode,_seatCount,_destination
                    ]] call ITW_CLASH_DualHAL_fnc_Log;
                    if (!isNil "ITW_CLASH_fnc_RequestCapability") then {
                        private _requirements = createHashMapFromArray [
                            ["hq",_hq],
                            ["destination",+_destination],
                            ["mode",_mode],
                            ["seats",_seatCount],
                            ["side",side _requester]
                        ];
                        ["TRANSPORT",_requester,_requirements,"NORMAL"] call
                            ITW_CLASH_fnc_RequestCapability;
                    } else {
                        [_requester,_hq,_destination,_mode,_seatCount] call
                            ITW_CLASH_Checkbook_fnc_RequestTransport;
                    };
                };
            };
        };

        _this call ITW_CLASH_Checkbook_fnc_NativeSCargo
    };

    ITW_CLASH_CheckbookCargoHookReady = true;
    diag_log "CLASH BOOT | checkbook-cargo-hook-ready | nativeSCargo=true checkbookProvidesCapacity=true withdraw=false";
    true
};

ITW_CLASH_DualHAL_fnc_Prepare = {
    if !(call ITW_CLASH_DualHAL_fnc_PrepareCommanderB) exitWith {false};
    call ITW_CLASH_DualHAL_fnc_InstallCargoHook;
    true
};

// Do not wrap NR6_fnc_HALcore here. Native HAL legitimately rebinds its core
// during VarInit, which made the old override both ineffective and misleading.
// The Checkbook API's deferred side binder owns Commander B preparation.
diag_log "CLASH BOOT | dual-hal-core-wrapper-skipped | sideBinderOwnsCommanderB=true";

[] spawn {
    scriptName "ITW_CLASH_DualHAL_Runtime";
    private _deadline = time + 240;
    waitUntil {
        sleep 0.25;
        (
            !isNull ITW_CLASH_BLUFORHQ
            && {!isNil "RydxHQ_AllHQ"}
            && {ITW_CLASH_BLUFORHQ in RydxHQ_AllHQ}
        ) || {time >= _deadline}
    };

    if (isNull ITW_CLASH_BLUFORHQ || {
        isNil "RydxHQ_AllHQ" || {!(ITW_CLASH_BLUFORHQ in RydxHQ_AllHQ)}
    }) exitWith {
        diag_log "CLASH BOOT | WARNING | dual-hal-runtime-timeout | BLUFOR HAL unavailable";
    };

    ITW_CLASH_DualHALReady = true;
    ITW_CLASH_CommanderRegistry set [
        [ITW_PlayerSide] call ITW_CLASH_DualHAL_fnc_SideKey,
        [ITW_CLASH_BLUFORHQ,ITW_CLASH_BLUFORLeader,"B"]
    ];
    if (!isNil "ITW_EnemySide" && {!isNil "ITW_CLASH_HALHQ"}) then {
        ITW_CLASH_CommanderRegistry set [
            [ITW_EnemySide] call ITW_CLASH_DualHAL_fnc_SideKey,
            [ITW_CLASH_HALHQ,missionNamespace getVariable ["ITW_CLASH_HALLeader",objNull],"A"]
        ];
    };

    call ITW_CLASH_DualHAL_fnc_InstallCargoHook;
    diag_log "CLASH BOOT | dual-hal-ready | BLUFOR=B OPFOR=A checkbook=true cargo=native";

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;

        call ITW_CLASH_DualHAL_fnc_RefreshBLUFORObjectives;

        // Adopt existing fielded BLUFOR infantry after the second commander is
        // live. Vehicle crews are admitted at the Impasse handoff or Checkbook.
        {
            private _group = _x;
            if !([_group] call ITW_CLASH_DualHAL_fnc_ShouldOwnFriendlyGroup) then {continue};
            private _leader = leader _group;
            if (isNull _leader) then {continue};
            if (vehicle _leader != _leader && {!(_group getVariable ["ITW_CLASH_CheckbookAsset",false])}) then {
                continue;
            };
            if !(_group getVariable ["ITW_CLASH_DualHALManaged",false]) then {
                {deleteWaypoint _x} forEachReversed waypoints _group;
                [_group,"runtime-existing-field"] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
            };
        } forEach +allGroups;

        call ITW_CLASH_DualHAL_fnc_MigrateManagedVehicles;
        call ITW_CLASH_DualHAL_fnc_SyncIncluded;
        if (!isNil "ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints") then {
            call ITW_CLASH_InfantryAuthority_fnc_ApplyRoleConstraints;
        };

        for "_i" from ((count ITW_CLASH_CheckbookAssets) - 1) to 0 step -1 do {
            private _entry = ITW_CLASH_CheckbookAssets#_i;
            _entry params ["_veh","_vehDef","_source","_released"];
            if (_released) then {
                ITW_CLASH_CheckbookAssets deleteAt _i;
                continue;
            };

            if (isNull _veh || {!alive _veh}) then {
                if (_vehDef isNotEqualTo [] && {count _vehDef > ITW_VEH_COUNT}) then {
                    ITW_TICKET_SEM_CHECK;
                    _vehDef set [
                        ITW_VEH_COUNT,
                        ((_vehDef#ITW_VEH_COUNT) - 1) max 0
                    ];
                };
                ["asset-released",[
                    if (isNull _veh) then {"<deleted>"} else {typeOf _veh},
                    _source,
                    if (_vehDef isEqualTo []) then {-1} else {_vehDef#ITW_VEH_COUNT}
                ]] call ITW_CLASH_DualHAL_fnc_Log;
                ITW_CLASH_CheckbookAssets deleteAt _i;
            };
        };
    };
};

diag_log format [
    "CLASH BOOT | dual-hal-checkbook-loaded | version=%1 compatibilityLayer=true impasse=checkbook hal=commander echelonFieldVehicles=true symmetricTransportSettle=true symmetricInfantryRoles=true",
    ITW_CLASH_DualHALCheckbookVersion
];

true
