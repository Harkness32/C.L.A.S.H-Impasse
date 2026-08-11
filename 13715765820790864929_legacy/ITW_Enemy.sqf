
#include "defines.hpp"

#define ENEMY_DEBUG(msg1,msg2,msg3) //if (true) then {diag_log format ["ITW: Enemy: %1 %2 %3",msg1,msg2,msg3]} 

ITW_EnemyGroups = [];
ITW_EnemyAssignmentWeights = [];
ITW_EnemyAttackVectorsBusy = false;

ITW_EnemyInit = {
    waitUntil {! isNil "VEHICLE_ARRAYS_COMPLETE"};
    private _isFriendly = false;
    private _factions = ITW_EnemyFaction;    
    private _variablesArray = [300,25]; // [_reloadRocketsGrenadesTime,_onFootTeleportChance]
    
    // zonesOwned goes from 0 to # of zones minus 1.  So players start at 0, enemies end at 0 (unless ITW_ParamVehicleEscalation=1 then player and enemy are the same).
    private _zoneCnt = count ITW_Zones - 1;
    private _1st = 1 min _zoneCnt;
    private _2nd = 2 min _zoneCnt;
    private _3rd = 3 min _zoneCnt;
    private _4th = 4 min _zoneCnt;
    
    if (ITW_ParamVehicleEscalation == 0) then {
        _1st = 0; 
        _2nd = 0; 
        _3rd = 0; 
        _4th = 0; 
    };
    
    // We require the vehicle arrays to be filled.  This is to balance the vehicle spawning.
    // For instance, if a faction only has 1 vehicle, the tickets will keep it from being spawned very often, and almost no vehicles will spawn
    private _ensure = {
        params ["_array","_fallbacks"];
        {
            if !(_array isEqualTo []) exitWith {};
            _array = _x;
        } count _fallbacks;
        _array
    };
    private _pd = [va_ePlaneClassesDual     ,[va_eHeliClassesDual,va_ePlaneClassesTransport,va_eHeliClassesTransport]] call _ensure;
    private _pa = [va_ePlaneClassesAttack   ,[va_ePlaneClassesDual,va_eHeliClassesAttack,va_eHeliClassesDual]] call _ensure;
    private _pt = [va_ePlaneClassesTransport,[va_cPlaneClassesTransportFallback,va_eHeliClassesTransport,va_cHeliClassesTransportFallback]] call _ensure;
    
    private _hd = [va_eHeliClassesDual      ,[va_ePlaneClassesDual,va_eHeliClassesTransport,va_ePlaneClassesTransport]] call _ensure;
    private _ha = [va_eHeliClassesAttack    ,[va_eHeliClassesDual,va_ePlaneClassesAttack,va_ePlaneClassesDual]] call _ensure;
    private _ht = [va_eHeliClassesTransport ,[va_eHeliDualAsTransport,va_ePlaneClassesTransport,va_cHeliClassesTransportFallback,va_cPlaneClassesTransportFallback]] call _ensure;
      
    private _td = [va_eTankClassesDual      ,[va_eApcClassesDual,va_eTankClassesTransport]] call _ensure;
    private _ta = [va_eTankClassesAttack    ,[va_eTankClassesDual,va_eApcClassesAttack,va_eApcClassesDual]] call _ensure;
    private _tt = [va_eTankClassesTransport ,[va_eApcClassesTransport,va_eHeliClassesTransport,va_ePlaneClassesTransport]] call _ensure;
      
    private _ad = [va_eApcClassesDual       ,[va_eCarClassesDual,va_eApcClassesTransport,va_eTankClassesDual,va_eCarClassesTransport]] call _ensure;
    private _aa = [va_eApcClassesAttack     ,[va_eApcClassesDual,va_eTankClassesDual,va_eTankClassesAttack,va_eCarClassesDual,va_eCarClassesAttack]] call _ensure;
    private _at = [va_eApcClassesTransport  ,[va_eHeliClassesTransport,va_ePlaneClassesTransport,va_eCarClassesTransport,va_cCarClassesTransportFallback,va_cHeliClassesTransportFallback,va_cPlaneClassesTransportFallback]] call _ensure;
      
    private _cd = [va_eCarClassesDual       ,[va_eApcClassesDual,va_eCarClassesTransport]] call _ensure;
    private _ca = [va_eCarClassesAttack     ,[va_eCarClassesDual,va_eApcClassesAttack]] call _ensure;
    private _ct = [va_eCarClassesTransport  ,[va_eCarDualAsTransport,va_cCarClassesTransportFallback,va_eHeliClassesTransport,va_cHeliClassesTransportFallback,va_cPlaneClassesTransportFallback,va_ePlaneClassesTransport,va_eApcClassesTransport,va_eTankClassesTransport]] call _ensure;
      
    private _sd = va_eShipClassesDual;
    private _sa = va_eShipClassesAttack;
    private _st = [va_eShipClassesTransport ,[va_cShipClassesTransportFallback]] call _ensure;
    
    private _ctDAsT = false;
    private _htDAsT = false;
    if (_ct isEqualTo va_eCarDualAsTransport ) then {_ctDAsT = true};
    if (_ht isEqualTo va_eHeliDualAsTransport) then {_htDAsT = true};
    
    // the tickets will scale with ITW_ParamEnemyAiCnt                                           zones tickets  tickets                veh     is       dualAs
    private _vehArray = []; // array of              type                  role                  owned required current  allowed count classes friendly transp
    if !(_pa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_ATTACK   ,_3rd, 40,     random 43,   2,  0,    _pa,    false,   false]};
    if !(_pd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_DUAL     ,_3rd, 38,     random 40,   2,  0,    _pd,    false,   false]};
    if !(_pt isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_TRANSPORT,_1st, 12,     random 15,   3,  0,    _pt,    false,   false]};
    
    if !(_ha isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_ATTACK   ,_2nd, 42,     random 42,   2,  0,    _ha,    false,   false]};
    if !(_hd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_DUAL     ,_3rd, 39,     random 39,   2,  0,    _hd,    false,   false]};
    if !(_ht isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_TRANSPORT,   0,  2,     10       ,   8,  0,    _ht,    false,   _htDAsT]};
    
    if !(_ta isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_ATTACK   ,_2nd, 30,     random 30,   4,  0,    _ta,    false,   false]};
    if !(_td isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_DUAL     ,_2nd, 36,     random 41,   4,  0,    _td,    false,   false]};
    if !(_tt isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_TRANSPORT,_2nd, 10,     random 10,  10,  0,    _tt,    false,   false]};
    
    if !(_aa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_ATTACK   ,_1st, 16,     random 16,   5,  0,    _aa,    false,   false]};
    if !(_ad isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_DUAL     ,_1st, 20,     random 20,   5,  0,    _ad,    false,   false]};
    if !(_at isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_TRANSPORT,_1st,  9,     random  9,  13,  0,    _at,    false,   false]};
    
    if !(_ca isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_ATTACK   ,   0,  4,     10       ,   7,  0,    _ca,    false,   false]};
    if !(_cd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_DUAL     ,   0,  6,     12       ,   7,  0,    _cd,    false,   false]};
    if !(_ct isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_TRANSPORT,   0,  1,     10       ,  99,  0,    _ct,    false,   _ctDAsT]};
    
    if !(_sa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_ATTACK   ,   0, 12,     random 10,   7,   0,   _sa,    false,   false]};
    if !(_sd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_DUAL     ,   0, 15,     random 20,   7,   0,   _sd,    false,   false]};
    if !(_st isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_TRANSPORT,   0,  1,     10       ,  99,   0,   _st,    false,   false]};

    // if no infantry, increase starting chance of vehicles
    if (ITW_ParamEnemyAiCnt == 0) then {
        _vehArray apply {
            _x params ["_type","_role","_zo","_ticketsReq","_tickets"];
            if (_tickets < _ticketsReq) then {
                _x set [4,_tickets*1.2];
                if (_type == ITW_TYPE_VEH_CAR || _type == ITW_TYPE_VEH_APC && {_role == ITW_VEH_ROLE_ATTACK}) then {
                    if (_tickets < _ticketsReq) then {_x set [4,_ticketsReq*1.5]};
                };
            };
        };
    };
    
    [_isFriendly,_factions,_vehArray,_variablesArray,ITW_EnemyAttackVectors,ITW_EnemyGroupCallback] spawn ITW_AtkManager; 
    
    //ITW_EnemyVehArray = _vehArray; // use for debugging
};

ITW_EnemyDebugVehArray = {
    diag_log "-- Enemy Veh Array -- (type,role,zonesReq,reqTickets,currTickets,maxVeh,cntVeh)";
    {
        diag_log format ["%1,%2 %3 %5/%4 %7/%6",_x#0,_x#1,_x#2,_x#3,_x#4,_x#5,_x#6];
    } forEach ITW_EnemyVehArray;
    diag_log "----------------------";
};

ITW_EnemyGroupCallback = {
    params ["_group"];
    ITW_EnemyGroups pushBack _group;
    ["enemy-group-callback",_group] call ITW_CLASH_fnc_ObserveGroup;
};

ITW_EnemyAttackVectors = {
    // _type is AV_VEHICLE, AV_VEHICLE_ATTACK, or AV_INFANTRY
    // returns [_objectiveToAttack,_baseAttackingFrom]
    params ["_type",["_group",objNull],["_cargoGroups",[]],["_populateObjectivesVehs",false],["_infantryIsWalking",false]];

    private _atkType = ITW_ATTACK_LAND_E;
    if (_type != AV_INFANTRY) then {
        private _veh = vehicle (leader _group);
        if (_veh isKindOf "Air") then {_atkType = ITW_ATTACK_AIR_E};
        if (_veh isKindOf "Ship") then {_atkType = ITW_ATTACK_SEA_E};
        if (_populateObjectivesVehs) then {
            if ({!(_x call ITW_ObjContestedOwnerIsFriendly)} count (ITW_Zones#ITW_ZoneIndex) == 0) then {
                _populateObjectivesVehs = false;
            };
        };
    } else {
        _populateObjectivesVehs = false;
    };
    
    private "_objIndex";
    
    // only let one thread run this routine at a time
    SEM_LOCK(ITW_EnemyAttackVectorsBusy);
    
    private _forcedObjective = _group getVariable [
        "ITW_CLASH_TransitObjective",-1
    ];
    if (_forcedObjective < 0) then {
        private _forcedCargoIdx = _cargoGroups findIf {
            (_x getVariable ["ITW_CLASH_TransitObjective",-1]) >= 0
        };
        if (_forcedCargoIdx >= 0) then {
            _forcedObjective = (_cargoGroups#_forcedCargoIdx) getVariable [
                "ITW_CLASH_TransitObjective",-1
            ];
        };
    };

    if (ITW_defendPhaseObjIdx > 0) then {
        _objIndex = ITW_defendPhaseObjIdx;
    } else {
        private _objIndexes = ITW_Zones#ITW_ZoneIndex;
        if (_forcedObjective >= 0 && {
            _forcedObjective in _objIndexes
        }) then {
            _objIndex = _forcedObjective;
        } else {
        private _walkingObjs = _objIndexes;

        // if infantry are walking, then limit how far they are going to walk (no more than 2k unless no objectives that close)
        if (_infantryIsWalking) then {
            private _distArray = _objIndexes apply {[leader _group distance (ITW_Objectives#_x#ITW_OBJ_POS),_x]};
            _distArray sort true;
            private _maxDist = 2000 max (_distArray#0#0);
            _walkingObjs = _distArray select {_x#0 <= _maxDist} apply {_x#1};
        };
        
        // initializations
        if (count ITW_EnemyAssignmentWeights isNotEqualTo _objIndexes) then {
            private _cntZones = count _objIndexes;
            private _empty = [];
            _empty resize [_cntZones,1/_cntZones]; // default to equal units to all contested objectives
            ITW_EnemyAssignmentWeights = _empty;
        };
        
        
        // create array of under/over staffing for each objective
        private _assignments = ([_type == AV_VEHICLE_ATTACK] call ITW_EnemyGetAssignedGroups)#AG_COUNTS;
        private _asnGoals = ITW_EnemyAssignmentWeights;
        // get the total number of units assigned so far
        private _totalAssigned = 0;
        {_totalAssigned = _totalAssigned + _x} count _assignments;
        _totalAssigned = 1 max _totalAssigned; // make sure it's not zero

        private _deltas = []; // how far the obj is from being staffed (negative = overstaffed, value is % under/over staffed)
        {_deltas pushBack ((_asnGoals#_forEachIndex) - (_x/_totalAssigned))} forEach _assignments;

        // find most understaffed objective
        _objIndex = _objIndexes#0;
        private _deltaMax = -1;
        {
            private _objIdx = _x;
            if (_infantryIsWalking && {!(_objIdx in _walkingObjs)}) then {continue};
            private _delta = _deltas#_forEachIndex;
            if (isNil "_delta") then {_delta = -1};
            if (_atkType == ITW_ATTACK_SEA_E) then {
                // if ship, skip objs w/o water access
                private _seaPts = ITW_SeaPoints#_objIdx;
                if (_seaPts isEqualTo []) then {_delta = -100};
            };
            if (_populateObjectivesVehs && {(_objIdx call ITW_ObjContestedOwnerIsFriendly)}) then {
                // don't assign vehicles to ally objectives during 'populate objectives'
                _delta = -100;
            };
            if (_delta > _deltaMax) then {
                _objIndex = _objIdx;
                _deltaMax = _delta;
            };
        } forEach _objIndexes;
        };
    };
        
    VAR_SET_OBJ_IDX(_group,_objIndex);
    _cargoGroups apply {VAR_SET_OBJ_IDX(_x,_objIndex)};
    if ((_group getVariable ["ITW_CLASH_TransitObjective",-1]) >= 0) then {
        _group setVariable ["ITW_CLASH_TransitObjective",_objIndex];
    };
    {
        if ((_x getVariable ["ITW_CLASH_TransitObjective",-1]) >= 0) then {
            _x setVariable ["ITW_CLASH_TransitObjective",_objIndex];
        };
    } forEach _cargoGroups;
        
    private _objTo = ITW_Objectives#_objIndex;
    
    SEM_UNLOCK(ITW_EnemyAttackVectorsBusy);
    
    while {_objTo#ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS} do {sleep 1};
    private _baseFromIdx = _objTo#ITW_OBJ_ATTACKS#_atkType;
    
    // if no route, just use the air route
    if (_baseFromIdx == BASE_INDEX_NONE) then {_baseFromIdx = _objTo#ITW_OBJ_ATTACKS#ITW_ATTACK_AIR_E};
    [_objTo,_baseFromIdx]
};

ITW_EnemyGetAssignedGroups = {
    // returns array of groups assigned to each current objective and counts (in same order as ITW_Zones#ITW_ZoneIndex)
    // result#AG_GROUPS is groups, result#AG_COUNTS is counts
    // ex: vehGroups = _result#AG_GROUPS#_zoneObjIdx)
    // ex: infCount  = _result#AG_COUNTS#_zoneObjIdx)
    params [["_attackVehsOnly",false]];
    
    if (ITW_ZoneIndex >= count ITW_Zones) exitWith {sleep 30,[]};// game is over, just let it time out
    private _objectives = ITW_Zones#ITW_ZoneIndex;
    private _objCount = count _objectives;
    private _assignedGroups = [];
    _assignedGroups resize [_objCount,[]];
    {
        private _group = _x;
        if ({ALIVE(_x) && {_x isKindOf "CAManBase"}} count units _group < 1) then {continue};
        if (_attackVehsOnly) then {
            private _leader = leader _group;
            private _veh = vehicle _leader;
            if (_veh == _leader) then {continue};
            if !(_veh getVariable ["itwattackveh",false]) then {continue};
        };
        private _assignment = VAR_GET_OBJ_IDX(_group);
        if (_assignment >= 0) then {
            private _idx = _objectives find _assignment;
            if (_idx >= 0) then { 
                (_assignedGroups#_idx) pushBack _group;
            };
        };
        false
    } count groups ITW_EnemySide;
    
    private _counts = [];
    _counts resize [_objCount,0];
    {
        private _objGroups = _x;
        private _objIdx = _forEachIndex;
        private _cnt = 0;
        {
            private _grp = _x;
            if (!_attackVehsOnly) then {_cnt = _cnt  + (count units _grp)};
        } count _objGroups;
        if (_attackVehsOnly) then {_cnt = count _objGroups};
        _counts set [_objIdx,_cnt];
    } forEach _assignedGroups;
    [_assignedGroups,_counts]
};

ITW_EnemyCivManager = {
    
    if (ITW_ParamCivilians == 0) exitWith {};
    
    
    if (isNil "CivBehavior") then {
        CivBehavior = compileFinal preprocessFileLineNumbers "scripts\CivBehavior\CivBehavior.sqf"; 
        ITW_CivTypes = [ITW_CivFaction] call FactionUnits;
        ITW_CivFactionSide = [ITW_CivFaction] call FactionSide;
        ITW_PrevCivHandles = [];
    };
    

    private _objIds = ITW_Zones#ITW_ZoneIndex;
    private _objCnt = count _objids;
    private _handles = +ITW_PrevCivHandles;
    private _handleCnt = count _handles;
    private _loops = (_objCnt max _handleCnt) - 1;
    for "_i" from 0 to _loops do {
        if (_i < _handleCnt) then {
            // reposition existing civBevahior zone
            private _handle = _handles#_i;
            if (_i < _objCnt) then {
                private _center = ITW_Objectives#(_objIds#_i)#ITW_OBJ_POS;
                [[_handle,_center]] call CivBehavior; // update location
            } else {
                [_handle] call CivBehavior; // cancel 
                ITW_PrevCivHandles = ITW_PrevCivHandles - [_handle];
            };
        } else {
            // add new CivBehavior zone
            private _center = ITW_Objectives#(_objIds#_i)#ITW_OBJ_POS;
            private _size = 300;
            private _civCnt = round (MAX_CIV_UNITS * ITW_ParamCivilians/3 * _size / 300);
            
            ITW_PrevCivHandles pushBack ([_center,_size,_civCnt,ITW_CivTypes, {
                    [ITW_CivFactionSide,_this] call FactionSanitizeCivilians;
                    
                    // add killed handler to notify of civilian casualties
                    _this addEventHandler ["Killed", {
                        private _killer = _this#1;
                        private _side = side _killer;
                        if (_side in [east,west,independent]) then {
                            [_killer,format ["Civilian killed by %1",name _killer]] remoteExec ["globalChat",0];
                        };
                    }];
                    // add 'move' menu item to ask civilian to move away
                    [
                        _this,
                        [
                            localize "STR_ITW_MISC_MoveBang",  
                            {  
                                _dir = [(_this select 1), (_this select 0)] call BIS_fnc_dirTo;  
                                _movePos = (getPosATL (_this select 0)) getPos [200, _dir];    
                                while {(count (waypoints (group (_this select 0)))) > 0} do
                                {
                                    deleteWaypoint ((waypoints (group (_this select 0))) select 0);
                                };
                                _wp0 = (group (_this select 0)) addWaypoint [_movePos, 50];
                                _wp0 setWaypointSpeed "FULL";
                            },  
                            nil,  
                            4,  
                            false,  
                            true,  
                            "",  
                            "(_this distance _target < 4) && (vehicle _target == _target) && (alive _this) && (alive _target)"
                        ]
                    ] remoteExec ["addAction", 0, true];
                }
            ] call CivBehavior);
        };
    };
};

["ITW_EnemyInit"] call SKL_fnc_CompileFinal;
["ITW_EnemyGroupCallback"] call SKL_fnc_CompileFinal;
["ITW_EnemyAttackVectors"] call SKL_fnc_CompileFinal;
["ITW_EnemyDebugVehArray"] call SKL_fnc_CompileFinal;
["ITW_EnemyGetAssignedGroups"] call SKL_fnc_CompileFinal;
["ITW_EnemyCivManager"] call SKL_fnc_CompileFinal;
