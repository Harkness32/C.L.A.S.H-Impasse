
#include "defines.hpp"
#include "defines_gui.hpp"

#define ALLY_DEBUG(msg1,msg2,msg3) //if (true) then {diag_log format ["ITW: Ally: %1 %2 %3",msg1,msg2,msg3]} 

ITW_AllyGroups = [];
ITW_AllyAssignmentWeights = [];
ITW_AllyAttackVectorsBusy = false;
ITW_AllyPriority = []; // [obj1Pri, obj2Pri, ...]
ITW_AllyReassignTime = -1;

ITW_AllyInit = {
    waitUntil {! isNil "VEHICLE_ARRAYS_COMPLETE"};
    private _isFriendly = true;
    private _factions = ITW_PlayerFaction;    
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
    private _pd = [va_pPlaneClassesDual     ,[va_pHeliClassesDual,va_pPlaneClassesTransport,va_pHeliClassesTransport]] call _ensure;
    private _pa = [va_pPlaneClassesAttack   ,[va_pPlaneClassesDual,va_pHeliClassesAttack,va_pHeliClassesDual]] call _ensure;
    private _pt = [va_pPlaneClassesTransport,[va_cPlaneClassesTransportFallback,va_pHeliClassesTransport,va_cHeliClassesTransportFallback]] call _ensure;
    
    private _hd = [va_pHeliClassesDual      ,[va_pPlaneClassesDual,va_pHeliClassesTransport,va_pPlaneClassesTransport]] call _ensure;
    private _ha = [va_pHeliClassesAttack    ,[va_pHeliClassesDual,va_pPlaneClassesAttack,va_pPlaneClassesDual]] call _ensure;
    private _ht = [va_pHeliClassesTransport ,[va_pHeliDualAsTransport,va_cHeliClassesTransportFallback,va_pPlaneClassesTransport,va_cPlaneClassesTransportFallback]] call _ensure;
      
    private _td = [va_pTankClassesDual      ,[va_pApcClassesDual,va_pTankClassesTransport]] call _ensure;
    private _ta = [va_pTankClassesAttack    ,[va_pTankClassesDual,va_pApcClassesAttack,va_pApcClassesDual]] call _ensure;
    private _tt = [va_pTankClassesTransport ,[va_pApcClassesTransport,va_pHeliClassesTransport,va_pPlaneClassesTransport]] call _ensure;
      
    private _ad = [va_pApcClassesDual       ,[va_pCarClassesDual,va_pApcClassesTransport,va_pTankClassesDual,va_pCarClassesTransport]] call _ensure;
    private _aa = [va_pApcClassesAttack     ,[va_pApcClassesDual,va_pTankClassesDual,va_pTankClassesAttack,va_pCarClassesDual,va_pCarClassesAttack]] call _ensure;
    private _at = [va_pApcClassesTransport  ,[va_pHeliClassesTransport,va_pPlaneClassesTransport,va_pCarClassesTransport,va_cCarClassesTransportFallback,va_cHeliClassesTransportFallback,va_cPlaneClassesTransportFallback]] call _ensure;
      
    private _cd = [va_pCarClassesDual       ,[va_pApcClassesDual,va_pCarClassesTransport]] call _ensure;
    private _ca = [va_pCarClassesAttack     ,[va_pCarClassesDual,va_pApcClassesAttack]] call _ensure;
    private _ct = [va_pCarClassesTransport  ,[va_pCarDualAsTransport,va_cCarClassesTransportFallback,va_pHeliClassesTransport,va_cHeliClassesTransportFallback,va_cPlaneClassesTransportFallback,va_pPlaneClassesTransport,va_pApcClassesTransport,va_pTankClassesTransport]] call _ensure;
      
    private _sd = va_pShipClassesDual;
    private _sa = va_pShipClassesAttack;
    private _st = [va_pShipClassesTransport ,[va_cShipClassesTransportFallback]] call _ensure;
    
    private _ctDAsT = false;
    private _htDAsT = false;
    if (_ct isEqualTo va_pCarDualAsTransport ) then {_ctDAsT = true};
    if (_ht isEqualTo va_pHeliDualAsTransport) then {_htDAsT = true};

    // the tickets will scale with ITW_ParamEnemyAiCnt                                           zones tickets  tickets                veh     is       dualAs
    private _vehArray = []; // array of              type                  role                  owned required current  allowed count classes friendly transp
    if !(_pa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_ATTACK   ,_3rd, 40,     random 43,   2,   0,   _pa,    true,    false]};
    if !(_pd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_DUAL     ,_3rd, 38,     random 40,   2,   0,   _pd,    true,    false]};
    if !(_pt isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_AIRPLANE,ITW_VEH_ROLE_TRANSPORT,_1st, 12,     random 15,   3,   0,   _pt,    true,    false]};
    
    if !(_ha isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_ATTACK   ,_2nd, 42,     random 42,   2,   0,   _ha,    true,    false]};
    if !(_hd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_DUAL     ,_3rd, 39,     random 39,   2,   0,   _hd,    true,    false]};
    if !(_ht isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_HELI    ,ITW_VEH_ROLE_TRANSPORT,   0,  2,     10       ,   8,   0,   _ht,    true,    _htDAsT]};
    
    if !(_ta isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_ATTACK   ,_2nd, 30,     random 30,   4,   0,   _ta,    true,    false]};
    if !(_td isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_DUAL     ,_2nd, 36,     random 41,   4,   0,   _td,    true,    false]};
    if !(_tt isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_TANK    ,ITW_VEH_ROLE_TRANSPORT,_2nd, 10,     random 10,  10,   0,   _tt,    true,    false]};
    
    if !(_aa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_ATTACK   ,_1st, 16,     random 16,   5,   0,   _aa,    true,    false]};
    if !(_ad isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_DUAL     ,_1st, 20,     random 20,   5,   0,   _ad,    true,    false]};
    if !(_at isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_APC     ,ITW_VEH_ROLE_TRANSPORT,_1st,  9,     random  9,  13,   0,   _at,    true,    false]};
    
    if !(_ca isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_ATTACK   ,   0,  4,     10       ,   7,   0,   _ca,    true,    false]};
    if !(_cd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_DUAL     ,   0,  6,     12       ,   7,   0,   _cd,    true,    false]};
    if !(_ct isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_CAR     ,ITW_VEH_ROLE_TRANSPORT,   0,  1,     10       ,  99,   0,   _ct,    true,    _ctDAsT]};
    
    if !(_sa isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_ATTACK   ,   0, 12,     random 10,   7,   0,   _sa,    true,    false]};
    if !(_sd isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_DUAL     ,   0, 15,     random 20,   7,   0,   _sd,    true,    false]};
    if !(_st isEqualTo []) then {_vehArray pushBack [ITW_TYPE_VEH_SHIP    ,ITW_VEH_ROLE_TRANSPORT,   0,  1,     10       ,  99,   0,   _st,    true,    false]};
    
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
    
    [_isFriendly,_factions,_vehArray,_variablesArray,ITW_AllyAttackVectors,ITW_AllyGroupCallback] spawn ITW_AtkManager; 
    
    //ITW_AllyVehArray = _vehArray; // use for debugging
    
    0 spawn ITW_AllyLoadIntoVehManager;
    
    // manage HC role = [];
    0 spawn {
        scriptName "ITW_AllyHcManager";
        private _currentHCs = [];
        while {true} do {
            if !(_currentHCs isEqualTo ITW_HcCmdr) then {
                {
                    private _hc = _x;
                    if !(_hc in ITW_HcCmdr) then {
                        hcRemoveAllGroups _hc;
                    };
                } forEach _currentHCs;
                {
                    private _hc = _x;
                    if !(_hc in _currentHCs) then {
                        {
                            private _grp = _x;
                            if (side _grp == ITW_PlayerSide && {!(_grp getVariable ["itwInitGrp",false])}) then {
                                _hc hcSetGroup [_grp];
                            };
                        } forEach allGroups;
                    };
                } forEach ITW_HcCmdr;
                _currentHCs = +ITW_HcCmdr;
                ITW_Hc setVariable ["commanders", ITW_HcCmdr, true];
            };
            sleep 5;
        };
    };
};

ITW_AllyGroupCallback = {
    params ["_group"];
    if (side _group != ITW_PlayerSide) exitWith {if (!isNull _group) then {diag_log format ["Error Pos: ITW_AllyGroupCallback called with non-player group : %1",_group]}};
    
    ITW_AllyGroups pushBack _group; // add to groups able to revive players
    ["ally-group-callback",_group] call ITW_CLASH_fnc_ObserveGroup;
    if !(missionNamespace getVariable ["ITW_CLASH_DisableNativeHC",false]) then {
        {_x hcSetGroup [_group]} forEach ITW_HcCmdr;
    };
    
    // we want to make ITW_AllyGroups public, but it only needs to be updated slowly to keep from pushing lots
    // of changes over the network
    if (isNil "ITW_AGVarUpdateRunning") then {ITW_AGVarUpdateRunning = false};
    isNil {
        if (!ITW_AGVarUpdateRunning) then {
            ITW_AGVarUpdateRunning = true;
            0 spawn {
                scriptName "ITW_AGVarUpdate";
                sleep 5;
                ITW_AGVarUpdateRunning = false;
                publicVariable "ITW_AllyGroups";
            };
        };
    };
};

ITW_AllyAttackVectors = {
    // _type is AV_VEHICLE, AV_VEHICLE_ATTACK, or AV_INFANTRY
    // returns [_objectiveToAttack,_baseAttackingFrom]
    params ["_type",["_group",objNull],["_cargoGroups",[]],["_populateObjectivesVehs",false],["_infantryIsWalking",false]];    
    // _populateObjectivesVehs is only true for attack vehicles when we want them placed into objectives we own
    
    private _atkType = ITW_ATTACK_LAND_F;
    if (_type != AV_INFANTRY) then {
        private _veh = vehicle (leader _group);
        if (_veh isKindOf "Air") then {_atkType = ITW_ATTACK_AIR_F};
        if (_veh isKindOf "Ship") then {_atkType = ITW_ATTACK_SEA_F};
        if (_populateObjectivesVehs) then {
            if ({_x call ITW_ObjContestedOwnerIsFriendly} count (ITW_Zones#ITW_ZoneIndex) == 0) then {
                _populateObjectivesVehs = false;
            };
        };
    } else {
        _populateObjectivesVehs = false;
    };
    
    private "_objIndex";

    // only let one thread run this routine at a time
    SEM_LOCK(ITW_AllyAttackVectorsBusy);
    
    if (ITW_defendPhaseObjIdx > 0) then {
        _objIndex = ITW_defendPhaseObjIdx;
    } else {
        private _objIndexes = ITW_Zones#ITW_ZoneIndex;
        private _walkingObjs = _objIndexes;
        
        // if infantry are walking, then limit how far they are going to walk (no more than 2k unless no objectives that close)
        if (_infantryIsWalking) then {
            private _distArray = _objIndexes apply {[leader _group distance (ITW_Objectives#_x#ITW_OBJ_POS),_x]};
            _distArray sort true;
            private _maxDist = 2000 max (_distArray#0#0);
            _walkingObjs = _distArray select {_x#0 <= _maxDist} apply {_x#1};
        };
        
        // Initializations
        if (ITW_AllyAssignmentWeights isEqualTo []) then {
            private _cntZones = count _objIndexes;
            private _empty = [];
            _empty resize [_cntZones,1/_cntZones]; // default to equal units to all contested objectives
            ITW_AllyAssignmentWeights = _empty;
        };
        
        // create array of under/over staffing for each objective
        private _assignments = ([_type == AV_VEHICLE_ATTACK] call ITW_AllyGetAssignedGroups)#AG_COUNTS;
        private _asnGoals = ITW_AllyAssignmentWeights;

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
            private _delta = -1;
            if (_forEachIndex < count _deltas) then {
                _delta = _deltas#_forEachIndex;
                if (isNil "_delta") then {_delta = -1};
            } else {
                diag_log format ["Error pos: ITW_AllyAttackVectors bad forEach: #assignments %1, #objs %2, _forEachIndex %3, _deltas %4, %5",count _assignments, count _objIndexes,_forEachIndex,count _deltas,_deltas];
            };
            if (_atkType == ITW_ATTACK_SEA_F) then {
                // if ship, skip objs w/o water access
                private _seaPts = ITW_SeaPoints#_objIdx;
                if (_seaPts isEqualTo []) then {_delta = -100};
            };
            if (_populateObjectivesVehs && {!(_objIdx call ITW_ObjContestedOwnerIsFriendly)}) then {
                // don't assign vehicles to enemy objectives during 'populate objectives'
                _delta = -100;
            };
            if (_delta > _deltaMax) then {
                _objIndex = _objIdx;
                _deltaMax = _delta;
            };
        } forEach _objIndexes;
    };
        
    VAR_SET_OBJ_IDX(_group,_objIndex);
    _cargoGroups apply {VAR_SET_OBJ_IDX(_x,_objIndex)};
        
    private _objTo = ITW_Objectives#_objIndex;
    
    SEM_UNLOCK(ITW_AllyAttackVectorsBusy);
    
    while {_objTo#ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS} do {sleep 1};
    private _baseFromIdx = _objTo#ITW_OBJ_ATTACKS#_atkType;
    
    // if no route, just use the air route
    if (_baseFromIdx == BASE_INDEX_NONE) then {_baseFromIdx = _objTo#ITW_OBJ_ATTACKS#ITW_ATTACK_AIR_F};

    [_objTo,_baseFromIdx]
};
    
ITW_AllyReassign = {
    params ["_priorities"];
    // call on server - check if correct number of units assigned to each objective and update as needed
    while {ITW_ObjZonesUpdating} do {sleep 0.5};
    
    _priorities call ITW_AllyCalculateWeights;
    
    // we want to wait a bit before re-assigning in case user changes assignments again
    private _timeout = 15;
    if (ITW_AllyReassignTime > 0) exitWith {ITW_AllyReassignTime = time + _timeout};
    ITW_AllyReassignTime = time + _timeout;    
    waitUntil {sleep 2;time > ITW_AllyReassignTime};
    
    private _assignments = [] call ITW_AllyGetAssignedGroups;
    
    // create array of under/over staffing for each objective
    private _assignmentCounts = _assignments#AG_COUNTS;
    private _assignedGroups = _assignments#AG_GROUPS;
    private _asnGoals = ITW_AllyAssignmentWeights;
    
    // get the total number of units assigned so far
    private _totalAssigned = 0;
    {_totalAssigned = _totalAssigned + _x} count _assignmentCounts;
    _totalAssigned = 1 max _totalAssigned; // make sure it's not zero

    private _deltaUnits = []; // how far the obj is from being staffed (negative = overstaffed, value is #units under/over staffed)
    {_deltaUnits pushBack (_totalAssigned * ((_asnGoals#_forEachIndex) - (_x/_totalAssigned)))} forEach _assignmentCounts;

    // search through overstaffed objectives and remove groups to get the count down closer to desired staffing
    private _objectives = ITW_Zones#ITW_ZoneIndex;
    {
        private _overstaff = -_x;
        if (_overstaff > 0) then {
            private _index = _forEachIndex;
            private _objIdx = _objectives#_index;
            _groups = _assignedGroups#_index;
            private _found = true;
            while {_found} do {
                {
                    private _group = _x;
                    private _unitCnt = {alive _x} count units _group;
                    if (_unitCnt <= _overstaff) exitWith {
                        // reassign group
                        _found = true;
                        _groups deleteAt _forEachIndex;
                        VAR_SET_OBJ_IDX(_group,-1);
                    };
                } forEach _groups;
            } 
        };
    } forEach _deltaUnits;
};

ITW_AllyGetAssignedGroups = {
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
    } count groups ITW_PlayerSide;
    
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

ITW_AllyCalculateWeights = {
    // call on server - reset the assignment weights based on priorities
    private _priorities = _this;
    private _sum = 0;
    {_sum = _sum + _x} count _priorities;
    private _values = _priorities apply {_x/_sum};
    ITW_AllyAssignmentWeights = _values;
    ITW_AllyPriority = _priorities;
    publicVariable "ITW_AllyPriority";
};

ITW_AllyNext = {
    SEM_LOCK(ITW_AllyAttackVectorsBusy);
    private _objectives = ITW_Zones#ITW_ZoneIndex;
    private _priorities = [];
    _priorities resize [count _objectives,3];
    _priorities call ITW_AllyCalculateWeights;
    SEM_UNLOCK(ITW_AllyAttackVectorsBusy);
};

ITW_AllyOptions = {
    params ["_officer", "_player", "_actionId", "_arguments"];
    ITW_ALLY_MENU = [[localize "STR_ITW_ALLY_TeammateOptions", false],
        [localize "STR_ITW_ALLY_RecruitAi"  ,[2], "", -5, [["expression","0 spawn ITW_AllyRecruitLocal"       ]], "1", "IsLeader + IsAlone"],
        [localize "STR_ITW_ALLY_RecruitTeam",[3], "", -5, [["expression","true spawn ITW_AllyRecruitTeam"]], "1", "IsLeader + IsAlone"],
        [localize "STR_ITW_ALLY_DismissAi"  ,[4], "", -5, [["expression","0 spawn ITW_AllyDismiss"             ]], "1", "IsLeader"          ],
        [localize "STR_ITW_ALLY_LoadAi"     ,[5], "", -5, [["expression","0 spawn ITW_TeammateLoadLocal"       ]], "1", "IsLeader + IsAlone"],
        [localize "STR_ITW_ALLY_SaveAi"     ,[6], "", -5, [["expression","0 spawn ITW_TeammateSaveLocal"       ]], "1", "IsLeader"          ],
        [localize "STR_ITW_COMMON_Cancel"  ,[16], "", -3, [["expression", ""]], "1", "1"]];
    showCommandingMenu "#USER:ITW_ALLY_MENU";
};
    
ITW_AllyDismiss = {
    if ({!(isPlayer _x)} count units group player == 0) exitWith {hint localize "STR_ITW_ALLY_NoAiInGroup"};
    while {true} do {
        private _teammates = units group player select {!isPlayer _x};
        if (count _teammates == 0) exitWith {};
        private _unitIdx = -1;
        ITW_TA_Index = -1;
        ITW_ALLY_MENU = [[localize "STR_ITW_RADIO_SelectTeammate", false]];
        {
            ITW_ALLY_MENU pushBack [name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
        } forEach _teammates;
        ITW_ALLY_MENU pushBack [localize "STR_ITW_RADIO_AllTeammates",[30], "", -5, [["expression","ITW_TA_Index = 999"]], "1", "1"];
        ITW_ALLY_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
        showCommandingMenu "#USER:ITW_ALLY_MENU";
        waitUntil {commandingMenu == ""};
        _unitIdx = ITW_TA_Index;
        if (_unitIdx < 0) exitWith {};
        
        private _indexes = [];
        if (_unitIdx == 999) then {
            {_indexes pushBack _forEachIndex} forEach _teammates;
        } else {
            _indexes pushBack _unitIdx;
        };      
        {
            private _unit = _teammates#_x;
            if (vehicle _unit == _unit) then {
                deleteVehicle _unit;
            } else {
                vehicle _unit deleteVehicleCrew _unit;
            };
        } forEach _indexes;
    };
};
 
ITW_AllyLoadoutCopy = {
    if ({!(isPlayer _x)} count units group player == 0) exitWith {hint localize "STR_ITW_ALLY_NoAiInGroup"};
    private _teammates = units group player;
    if (count _teammates < 2) exitWith {};
    
    // FROM        
    private _unitIdx = -1;
    ITW_TA_Index = -1;
    ITW_ALLY_MENU = [[localize "STR_ITW_ALLY_CopyLoadoutFrom", false]];
    {
        ITW_ALLY_MENU pushBack [name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
    } forEach _teammates;
    ITW_ALLY_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
    showCommandingMenu "#USER:ITW_ALLY_MENU";
    waitUntil {commandingMenu == ""};
    _unitIdx = ITW_TA_Index;
    if (_unitIdx < 0) exitWith {};
    
    private _fromUnit = _teammates#_unitIdx;
    private _showMenu = true;
    
    while {_showMenu} do {
        // TO
        _teammates = units group player select {!isPlayer _x};
        _unitIdx = -1;
        ITW_TA_Index = -1;
        ITW_ALLY_MENU = [[localize "STR_ITW_ALLY_CopyLoadoutTo", false]];
        {
            if (_fromUnit != _x) then {
                ITW_ALLY_MENU pushBack [name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
            };
        } forEach _teammates;
        ITW_ALLY_MENU pushBack [localize "STR_ITW_RADIO_AllTeammates",[30], "", -5, [["expression","ITW_TA_Index = 999"]], "1", "1"];
        ITW_ALLY_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
        showCommandingMenu "#USER:ITW_ALLY_MENU";
        waitUntil {commandingMenu == ""};
        _unitIdx = ITW_TA_Index;
        if (_unitIdx < 0) exitWith {};
        
        private _indexes = [];
        if (_unitIdx == 999) then {
            {_indexes pushBack _forEachIndex} forEach _teammates;
            _showMenu = false;
        } else {
            _indexes pushBack _unitIdx;
        };
        
        private _loadout = getUnitLoadout _fromUnit;
        {
            private _unit = _teammates#_x;
            [_unit,_loadout] call ITW_FncSetUnitLoadout;
        } forEach _indexes;
    };
};

ITW_AllyRecruitLocal = {
    private _aiCnt = {!isPlayer _x && {alive _x}} count units group player;
    if (_aiCnt >= ITW_ParamFriendlySquadSize) then {
        hint localize "STR_ITW_ALLY_CanceledMaxSquadSize";
    } else {
        if (isNil "ITW_AllyRecruitMenu_1") then {
            private _header = [[localize "STR_ITW_BASE_SelectLoadout", false]];
            private _index = 0;
            private _maxItems = 11;
            private _cnt = _maxItems+10;
            private _maxLoops = _maxItems;
            private _menu = +_header;
            waitUntil {!isNil "ITW_AllyUnitTypes"};
            {
                private _unitType = _x;
                private _name = getText (configFile >> "CfgVehicles" >> _unitType >> "displayName");
                if (_cnt >= _maxLoops) then {
                    if (_index > 0) then {
                        if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], format ["#USER:ITW_AllyRecruitMenu_%1",_index-1], -5, [["expression",""]], "1", "1"]};
                        _menu pushBack [localize "STR_ITW_COMMON_More",[31], format ["#USER:ITW_AllyRecruitMenu_%1",_index+1], -5, [["expression",""]], "1", "1"];
                        _menu pushBack [localize "STR_ITW_COMMON_Quit",[16], "", -5, [["expression","showCommandingMenu ''"]], "1", "1"];
                        call compile format ["ITW_AllyRecruitMenu_%1 = _menu;",_index];
                        _maxLoops = _maxItems - 1; // we've now got 'BACK' as well
                    };
                    _menu = +_header;
                    _cnt = 1;
                    _index = _index + 1;
                    if (_index == 1) then {
                        _menu pushBack [localize "STR_ITW_BASE_RandomLoadout",[_cnt+1], "", -5, [["expression",format ["['',%1] spawn ITW_AllyRecruitMenuItem",_index]]], "1", "1"];
                        _cnt = _cnt + 1;
                    };
                } else {
                    _cnt = _cnt + 1;
                };          
                _menu pushBack [_name,[_cnt+1], "", -5, [["expression",format ["['%1',%2] spawn ITW_AllyRecruitMenuItem",_x,_index]]], "1", "1"];
            } forEach ITW_AllyUnitTypes;
            _menu pushBack [localize "STR_ITW_COMMON_Back",[17], format ["#USER:ITW_AllyRecruitMenu_%1",_index-1], -5, [["expression",""]], "1", "1"];
            _menu pushBack [localize "STR_ITW_COMMON_Quit",[16], "", -5, [["expression","showCommandingMenu ''"]], "1", "1"];
            call compile format ["ITW_AllyRecruitMenu_%1 = _menu;",_index];
        };
        showCommandingMenu "#USER:ITW_AllyRecruitMenu_1";
    };
};

ITW_AllyRecruitMenuItem = {
    // call on player's client who is using the menu
    params ["_unitType","_menuIndex"];
    private _aiCnt = ({!isPlayer _x && {alive _x}} count units group player) + 1; // so this before creation since creation takes some time
    private _unitArray = if (_unitType isEqualTo "") then {[]} else {[_unitType]};
    [player,_unitArray] remoteExec ['ITW_AllyRecruit',2];
    hint localize 'STR_ITW_ALLY_UnitAdded';
    if (_aiCnt < ITW_ParamFriendlySquadSize) then {
        showCommandingMenu format ["#USER:ITW_AllyRecruitMenu_%1",_menuIndex];
    };
};

ITW_AllyRecruit = {
    // call on server
    params ["_player",["_info",[]]];
    if (!isServer) exitWith {diag_log "Error pos ITW_AllyRecruit called from client"};
    private _grp = group _player;
    private _unitLoadout = [];
    waitUntil {!isNil "ITW_AllyUnitTypes"};
    private ["_unit"];
    if (_info isEqualTo []) then {
        _unit = [_grp, ITW_AllyUnitTypes, getPosATL _player, true] call ITW_AtkUnitToGroup;
    } else {
        switch (typeName _info) do {
            case "ARRAY": {
                _info params ["_type",["_name",""],["_loadout",[]],["_id",-1],["_face",""],["_speaker",""]];
                private _unitTypes = if (_type != "" && {_type in ITW_AllyUnitTypes}) then {[_type]} else {ITW_AllyUnitTypes};
                private _group = if (_id >= 0) then {createGroup side _grp} else {_grp};
                _unit = [_group, _unitTypes, getPosATL _player, true] call ITW_AtkUnitToGroup;
                if !(_name isEqualTo "") then {
                    private _first = "";
                    private _last = _name;
                    private _spaceIdx = _name find " ";
                    if (_spaceIdx > 0) then {
                        _first = _name select [0,_spaceIdx];
                        _last = _name select [_spaceIdx + 1];
                    };
                    [_unit,[_name,_first,_last]] remoteExec ["setName",0,_unit];
                };
                if (_id >= 0) then {
                    _unit joinAsSilent [_grp, _id];
                    deleteGroup _group;
                };
                if (!(_face isEqualTo "") || {!(_speaker isEqualTo "")}) then {
                    [_unit,_face,_speaker] remoteExec ["ITW_FncSetIdentityMP",0,_unit];
                };
                _unitLoadout = _loadout;
            };
            case "STRING": {
                private _unitTypes = ITW_AllyUnitTypes;
                // special case for TIOW
                if (isClass (configfile >> "CfgPatches" >> "TIOWSpaceMarines")) then {
                    private _vehType = _info;
                    private _vehCrew = getText (configFile >> "cfgVehicles" >> _vehType >> "crew");
                    _unitTypes = if (_vehCrew in ITW_AllyUnitTypes) then {[_vehCrew]} else {
                        private _isMarineVehicle = _vehType isKindOf "TIOW_SM_Rhino_UM";
                        private _ut = if (_isMarineVehicle) then {ITW_AllyUnitTypes select {_x isKindOf "TIOWSpaceMarine_Base"}} else {ITW_AllyUnitTypes select {!(_x isKindOf "TIOWSpaceMarine_Base")}};
                        if (_ut isEqualTo []) then {_ut = ITW_AllyUnitTypes};
                        _ut
                    };
                };
                _unit = [_grp, _unitTypes, getPosATL _player, true] call ITW_AtkUnitToGroup;
            };
        };
    };
    [_unit,_unitLoadout] remoteExec ["ITW_AllyRecruitUnitLocal",0,_unit];
    [_unit] remoteExec ["ITW_TeammateCreated",0,_unit];
};

ITW_AllyRecruitUnitLocal = {
    // call where unit is local
    params ["_unit","_loadout"];
    if !(_loadout isEqualTo []) then {sleep 0.1;[_unit,_loadout] call ITW_FncSetUnitLoadout};
};

ITW_AllyRecruitTeam = {
    // returns the array of unit types, if _addToPlayerGroup == true, then units are spawned and added to player's group
    params ["_addToPlayerGroup"];
    private _aiCnt = {!isPlayer _x && {alive _x}} count units group player;
    if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {hint localize "STR_ITW_ALLY_CanceledMaxSquadSize";[]};
    if (isNil "ITW_AllySquadTypesMenu_1") then {
        waitUntil {!isNil "ITW_AllySquadTypes"};
        private _header = [[localize "STR_ITW_ALLY_SelectSquadType", false]];
        private _index = 0;
        private _maxItems = 10;
        private _cnt = _maxItems+2;
        private _menu = +_header;
        {
            private _name = ITW_AllySquadTypeNames#_forEachIndex;
            private _unitsInSquad = _x;
            if (_cnt > _maxItems) then {
                if (_index > 0) then {
                    if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"]};
                    _menu pushBack [localize "STR_ITW_COMMON_More",[31], format ["#USER:ITW_AllySquadTypesMenu%1",_index+1], -5, [["expression",""]], "1", "1"];
                    call compile format ["ITW_AllySquadTypesMenu%1 = _menu;",_index];
                };
                _menu = +_header;
                _cnt = 0;
                _index = _index + 1;
            } else {
                _cnt = _cnt + 1;
            };          
            _menu pushBack [_name,[_cnt+2], "", -5, [["expression",format ["ITW_ArAnswer = %1;",_unitsInSquad]]], "1", "1"];
        } forEach ITW_AllySquadTypes;
        if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"]}
        else {                _menu pushBack [localize "STR_ITW_COMMON_Quit",[16], "", -4, [["expression",""]], "1", "1"]};
        call compile format ["ITW_AllySquadTypesMenu%1 = _menu;",_index];
    };
    
    ITW_ArAnswer = [];
    showCommandingMenu "#USER:ITW_AllySquadTypesMenu1";
    waitUntil {!(commandingMenu isEqualTo "")};
    waitUntil {commandingMenu isEqualTo ""};
    if !(ITW_ArAnswer isEqualTo []) then {
        if (_addToPlayerGroup) then {
            [player,ITW_ParamFriendlySquadSize - _aiCnt,ITW_ArAnswer] remoteExec ["ITW_AllyRecruitTeamServer",2];
        };
    };
    ITW_ArAnswer
};

ITW_AllyRecruitTeamServer = {
    // call on server
    params ["_player","_maxAiToAdd","_unitTypes"];
    if (!isServer) exitWith {diag_log "Error pos ITW_AllyRecruit called from client"};
    private _grp = group _player;
    {
        if (_forEachIndex >= _maxAiToAdd) exitWith {[localize "STR_ITW_ALLY_MaxSquadSize"] remoteExec ["hint",_player]};
        private _unit = [_grp, [_x], getPosATL _player, true] call ITW_AtkUnitToGroup;
        [_unit] remoteExec ["ITW_TeammateCreated",0,_unit];
    } forEach _unitTypes;
};

ITW_AllyRecall = {
    // call on server
    params ["_name"];
    {
        private _group = _x;            
        if (str _group isEqualTo _name) then {
            private _vehicles = [];
            {
                private _unit = _x;
                private _veh = vehicle _unit;
                if (_veh == _unit) then {
                    deleteVehicle _unit;
                } else {
                    _veh deleteVehicleCrew _unit;
                    _vehicles pushBackUnique _veh;
                };
            } forEach units _group;
            {
                private _veh = _x;
                if ({alive _x} count crew _veh == 0) then {deleteVehicle _veh};
            } forEach _vehicles;
        };
    } forEach ITW_AllyGroups;
};

ITW_HcCmdr = []; 
ITW_AllyHighCmdr = {
    // call on server    
    params ["_player","_enable"];
    if (_enable) then {
        ITW_HcCmdr pushBackUnique _player;
    } else {
        ITW_HcCmdr = ITW_HcCmdr - [_player];
    };
    publicVariable "ITW_HcCmdr";
}; 

ITW_AllyHcRespawn = {
    // call on server when a unit respawns
    params ["_unit","_corpse"];
    if (_corpse in ITW_HcCmdr) then {
        ITW_HcCmdr = ITW_HcCmdr - [_corpse];
        ITW_HcCmdr pushBackUnique _unit;
    };
    publicVariable "ITW_HcCmdr";
};

ITW_AllyLoadIntoVehManager = {
    // spawn on server
    scriptName "ITW_AllyLoadIntoVehManager";
    while {!ITW_GameOver} do {
        {
            private _veh = _x;
            private _pilot = currentPilot _veh;
            if (!isPlayer _pilot && {units group _pilot findIf {isPlayer _x} == -1}) then {continue};
            if (side _pilot != ITW_PlayerSide) then {continue};
            if (speed _veh > 5) then {continue};
            private _vPos = getPosATL _veh;
            private _isWater = surfaceIsWater _vPos;
            if (_isWater && {_vPos#2 > 4.5}) then {continue};
            if (!_isWater && {!(isTouchingGround _veh) && {_vPos#2 > 2}}) then {continue};
            if (!canMove _veh || {fuel _veh == 0}) then {continue};      
            if (isPlayer _pilot && {_veh getVariable ["ITW_BlockAllyEntry",false]}) then {continue};
            if !(_veh getVariable ["ITW_reservedGroups",[]] isEqualTo []) then {continue};
            if (_veh getVariable ["ITW_AllyEntryTimeout",0] > time) then {continue};
            if (_veh getVariable ["ITW_AllyCrewEject",false]) then {continue};
            if (_veh getVariable ["SKL_BFC_running",false]) then {continue};
            
            private _emptySeats = 
                    if (_veh getVariable ['ITW_BlockAllyCrew',true]) then {
                        {isNull (_x#5) && {_x#2 >= 0}} count fullCrew [_veh,"",true]; 
                    } else {
                        {isNull (_x#5) && {_x#2 >= 0 || {!(_x#3 isEqualTo [])}}} count fullCrew [_veh,"",true]; 
                    };
            if (_emptySeats == 0) then {continue};

            if (isPlayer _pilot && {speed _veh > 6 && {_veh getVariable ["ITW_ForceAllyEntry",false] && {ITW_ELEVATION(_vPos) > 6}}}) then {
                _veh setVariable ["ITW_ForceAllyEntry",false,true];
            };

            private _objType = if (isPlayer _pilot && {_veh getVariable ["ITW_ForceAllyEntry",false]}) then {ITW_OWNER_ENEMY} else {ITW_OWNER_CONTESTED};
            private _closestObj = [_vPos, ITW_OWNER_CONTESTED, _objType] call ITW_ObjGetNearest;
            if (_closestObj#ITW_OBJ_POS distance _veh < 1000) then {continue};

            private _onFootAllies = ITW_AllyGroups select {
                    private _grp = _x;
                    private _leader = leader _grp;
                    !(_grp getVariable ["ITW_Garrison",false]) && 
                    {!(_grp getVariable ["itwInitGrp",false]) &&  // skip the initial group of all units being spawned
                    {vehicle _leader == _leader && 
                    {_leader distance _veh < 250 && 
                    {isNull getAttackTarget _leader && 
                    {!fleeing _leader && 
                    {_grp getVariable ["ITW_getInState",-1] == -1}}}}}}
                } apply {[leader _x distance _veh,_x]};
            if (_onFootAllies isEqualTo []) then {continue};
            
            _onFootAllies sort true;
            private _groupsToLoad = [];
            {
                private _grp = _x#1;
                private _grpSize = count units _grp;
                if (_grpSize <= _emptySeats) then {
                    _emptySeats = _emptySeats - _grpSize;
                    _groupsToLoad pushBack _grp;
                    VAR_SET_OBJ_IDX(_grp,_closestObj#ITW_OBJ_INDEX);
                    if (!isNil "ITW_CLASH_PlayerTransport_fnc_Acquire") then {
                        [_grp,_veh,"player-ferry-boarding"] call
                            ITW_CLASH_PlayerTransport_fnc_Acquire;
                    };
                    _grp setVariable ["ITW_getInState",0];
                    ITW_DELETE_WAYPOINTS(_grp);
                };
            } count _onFootAllies;
            if !(_groupsToLoad isEqualTo []) then {
                _veh setVariable ["ITW_reservedGroups",_groupsToLoad];
                [_veh,_groupsToLoad] spawn ITW_AllyLoadGrpIntoVeh;
            };
        } forEach vehicles;
        sleep 8;
        while {LV_PAUSE} do {sleep 5};
    };
};

ITW_AllyLoadGrpIntoVeh = {
    params ["_veh","_groupsToLoad"];

    private _grpCntInVeh = _veh getVariable ["ITW_groupCntActive",0];
    _veh setVariable ["ITW_groupCntActive",_grpCntInVeh + count _groupsToLoad];
    private _groupsInState1 = false;
    private _doGetOut = false;
    private _wrongBaseWarning = false;
    private _reportProgress = isPlayer currentPilot _veh;
    private _wrongWarningShown = false;
    
    while {_veh getVariable ["ITW_groupCntActive",0] > 0} do {
        
        if (_groupsInState1) then {
            // do some calculations once instead of doing it for each group
            private _check =  _veh getVariable ["ITW_BlockAllyEntry",false] ||
                             {(!canMove _veh) ||
                             {(fuel _veh == 0) ||
                             {isNull currentPilot _veh}}};
            private _distF = 1e5;
            private _distE = 1e5;                
            if (!_check) then {
                private _contestedObjs = [] call ITW_ObjGetContestedObjs;
                private _friendlyObjs = _contestedObjs select {
                                            private _flag = _x#ITW_OBJ_FLAG;                                          
                                            flagAnimationPhase _flag == 1 && {flagTexture _flag == ITW_PlayerFlag}
                                        };
                private _enemyObjs = _contestedObjs - _friendlyObjs;
                {private _d = _x#ITW_OBJ_POS distance _veh;if (_d < _distF) then {_distF = _d}} forEach _friendlyObjs;
                {private _d = _x#ITW_OBJ_POS distance _veh;if (_d < _distE) then {_distE = _d}} forEach _enemyObjs;
            };
            _doGetOut = _check || {(_distE < TRANSPORT_DROP_MAX_DIST && {(isTouchingGround _veh || (ITW_ELEVATION_LT(_veh,2))) && {speed _veh < 5}}) || {_veh getVariable ["ITW_AllyCrewEject",false]}};
            _wrongBaseWarning = !(_doGetOut) && {_distF < TRANSPORT_DROP_MAX_DIST};  
            if (!_wrongBaseWarning) then {_wrongWarningShown = false};
        };
        
        {
            private _grp = _x;
            
            // Get in transport
            if (_grp getVariable ["ITW_getInState",-1] == 0) then {
                if (_reportProgress) then {
                    if !(_veh getVariable ["reported",false]) then {
                        _veh setVariable ["reported",true];
                        private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
                        ["bStart",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
                    };
                    [leader _grp,localize "STR_ITW_ALLY_WeAreBoarding"] remoteExec ["sideChat",currentPilot _veh];
                };
                ITW_DELETE_WAYPOINTS(_grp);        
                                
                private _units = units _grp select {ALIVE(_x)};
                private _leader = leader _grp;
                private _vPos = getPosATL _veh;
                {
                    if (_x distance _leader > 200) then {_x setPosATL (getPosATL _leader)};
                    _x setDamage 0;
                    _x doMove _vPos;
                } forEach _units;
                {
                    [_x,_veh] call ITW_AllyOrderGetIn;
                } forEach _units;
                [_units,true] remoteExec ["orderGetIn",_leader];
                _grp setVariable ["ITW_ExitVehicle",false];
                _veh setVariable ["ITW_AllyCrewEject",false];
                
                // SPAWN ----------------------------------------------------------------------------------------
                [_grp,_veh,_reportProgress] spawn { 
                    scriptName "ITW_LoadGroupIntoVeh_GetIn";
                    params ["_grp","_veh","_reportProgress"];                              
                    private _players = allPlayers select {vehicle _x isEqualto _veh};
                    private _units = units _grp select {ALIVE(_x)};
                    private _leader = leader _grp;
                    private _timeout = time + 40;
                    [_grp,_timeout-time] remoteExec ["ITW_AllySpeedUp",0];
                    waitUntil { sleep 1;
                        private _vPos = getPosATL _veh;
                        private _ready = 
                            ITW_ELEVATION(_vPos) > 5 || 
                            {{ALIVE(_x) && vehicle _x == _x} count _units == 0 ||
                            {_veh getVariable ["ITW_BlockAllyEntry",false] ||
                            {_veh emptyPositions "Cargo" == 0 ||
                            {isNull currentPilot _veh ||
                            {(!canMove _veh) ||
                            {(fuel _veh == 0) ||
                            {_grp getVariable ["ITW_ExitVehicle",false]}}}}}}};
                        if (!_ready) then {
                            // player may have taken someone's seat
                            {
                                private _unit = _x;
                                if (isNull assignedVehicle _unit) then {
                                    [_unit,_veh] call ITW_AllyOrderGetIn;
                                };
                            } forEach _units;
                            if (time > _timeout) then {
                                playSound3D ["a3\sounds_f\vehicles\soft\mrap_01\getin.wss", _veh,true,_vPos,0.5];
                                private _fullCrew = fullCrew [_veh,"",true];
                                {
                                    private _unit = _x;
                                    if (vehicle _unit ==_unit) then {
                                        private _seatInfo = _fullCrew select {_x#5 == _unit};
                                        private _seat = if (_seatInfo isEqualTo []) then {""} else {if (_seatInfo#0#2 < 0) then {_seatInfo#0#3} else {_seatInfo#0#2}};
                                        switch (typeName _seat) do {
                                            case "SCALAR": {_unit moveInCargo  [_veh,_seat,true]; sleep 0.2};
                                            case "ARRAY":  {_unit moveInTurret [_veh,_seat,true]; sleep 0.2};
                                        };
                                    };
                                } forEach _units;
                                sleep 0.2;
                                {
                                    if (vehicle _x ==_x) then {
                                        [_x,_veh,true] call ITW_AllyOrderGetIn;
                                    };
                                } forEach _units;
                            };
                        };           
                        _ready
                    };                   
                    
                    private _success = true;
                    private _pilot = currentPilot _veh;
                    if (! isNull _pilot && 
                       {vehicle _leader == _veh && 
                       {!(_veh getVariable ["ITW_BlockAllyEntry",false]) &&
                       {!(_grp getVariable ["ITW_ExitVehicle",false])}}}) then {
                       if (isPlayer _pilot) then {
                            [format [localize "STR_ITW_ALLY_DeliverUnitsFMT",TRANSPORT_DROP_MAX_DIST]] remoteExec ["hint",_pilot];
                        };
                        _veh setVariable ["ITW_pickupSuccess",true];
                        private _groups = _veh getVariable ["ITW_transportGroups",[]];
                        _groups = _groups + [_grp];
                        _veh setVariable ["ITW_transportGroups",_groups,true];
                    } else {
                        _success = false;
                        _grp leaveVehicle _veh;
                        _grp setVariable ["ITW_getInState",-1];
                        if (!isNil "ITW_CLASH_PlayerTransport_fnc_Release") then {
                            [_grp,"player-ferry-boarding-failed"] call
                                ITW_CLASH_PlayerTransport_fnc_Release;
                        };
                        _leader doMove getPosATL _leader;
                        private _unitsNotFollowing = [];
                        {
                            if (_x != _leader) then {_unitsNotFollowing pushBack _x};
                        } forEach _units;
                        if !(_unitsNotFollowing isEqualTo []) then {[_unitsNotFollowing,_leader] remoteExec ["doFollow",_leader]};
                    };                                     
                    private _groups = _veh getVariable ["ITW_reservedGroups",[]];
                    _groups = _groups - [_grp];
                    if (_groups isEqualTo []) then {
                        if (_reportProgress && {_veh getVariable ["ITW_pickupSuccess",false]}) then {
                            private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
                            ["bEnd",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
                            if (!isNull driver _veh) then {[leader _grp,localize "STR_ITW_ALLY_WeAreIn"] remoteExec ["sideChat",driver _veh]};
                            
                        };
                        _veh setVariable ["ITW_pickupSuccess",nil];
                        _veh setVariable ["ITW_reservedGroups",nil];
                        _veh setVariable ["reported",nil];
                    } else {
                        _veh setVariable ["ITW_reservedGroups",_groups];
                    };
                    if (_success) then {
                        waitUntil {sleep 1; speed _veh > 3};
                        // tell any units that couldn't get in to continue to the objective  
                        {
                            if (vehicle _x == _x) then {
                                [_x,_veh,true] call ITW_AllyOrderGetIn;
                            };
                        } forEach _units;
                    } else {
                        {
                            [_x] remoteExec ["unassignVehicle",_x];
                        } forEach _units;
                        _veh setVariable ["ITW_groupCntActive",(_veh getVariable ["ITW_groupCntActive",0]) - 1];
                        _grp setVariable ["ITW_getInState",2];
                        _veh setVariable ["reported",nil];
                    };
                };
                // END -----------------------------------------------------------------------------------------
                _grp setVariable ["ITW_getInState",1];
                _groupsInState1 = true;
            };
        
            // Get out of transport
            if (_grp getVariable ["ITW_getInState",-1] == 1) then {
                private _vehPos = getPosATL _veh;
                if (!_wrongWarningShown && {_wrongBaseWarning && {ITW_ELEVATION_LT(_veh,2) && {speed _veh < 5}}}) then {
                    _wrongWarningShown = true;
                    [localize "STR_ITW_ALLY_AlreadyCaptured"] remoteExec ["hint",currentPilot _veh];
                };
                if (_doGetOut) then {
                    _grp setVariable ["ITW_ExitVehicle",true];
                    if (ITW_ELEVATION(_vehPos) < 5) then {                        
                        {
                            [_x] remoteExec ["unassignVehicle",_x];
                        } forEach units _grp;
                        private _units = units _grp;
                        private _leader = leader _grp;
                        [_units,false] remoteExec ["orderGetIn",_leader];
                        [_units,_leader] remoteExec ["doFollow",_leader];
                    };
                    // SPAWN -----------------------------------------------------------------------------------------
                    _grp setVariable [
                        "ITW_CLASH_TransportPhysicalUnloadPending",true
                    ];
                    [_grp,_veh,_reportProgress] spawn {
                        scriptName "ITW_LoadGroupIntoVeh_GetOut";
                        params ["_grp","_veh","_reportProgress"];
                        if (_reportProgress) then {
                            if !(_veh getVariable ["reported",false]) then {
                                _veh setVariable ["reported",true];
                                private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
                                ["dStart",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
                            };
                        };
                        if (ITW_ELEVATION_GT(_veh,15)) then {
                            [_veh,_grp] call ITW_AllyParadropCargo;
                            [units _grp,leader _grp] remoteExec ["doFollow",leader _grp];       
                        } else {
                            {
                                moveOut _x;
                                sleep 2;
                            } forEach units _grp;
                        };
                        sleep 1;
                        if (_veh getVariable ["ITW_AllyCrewEject",false]) then {_veh setVariable ["ITW_AllyEntryTimeout",time + 30]};
                        private _groups = _veh getVariable ["ITW_transportGroups",[]];
                        _groups = _groups - [_grp];
                        _veh setVariable ["ITW_transportGroups",_groups,true];
                        if (_groups isEqualTo []) then {
                            {
                                private _assignedUnit = _x#5;
                                if (! isNull _assignedUnit && {vehicle _assignedUnit != _veh}) then {
                                    [_assignedUnit] remoteExec ["unassignVehicle",_assignedUnit];
                                };
                            } forEach fullCrew [_veh,"",true];
                            _veh setVariable ["ITW_AllyCrewEject",false];
                            if (_reportProgress && {canMove _veh && fuel _veh > 0}) then {
                                private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
                                ["dEnd",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
                                [leader _grp,localize "STR_ITW_ALLY_WereAllOut"] remoteExec ["sideChat",driver _veh];
                                
                            };
                            // clear the vehicle transport variables just in case there's a hole in the logic somewhere
                            _veh setVariable ["ITW_pickupSuccess",nil];
                            _veh setVariable ["ITW_reservedGroups",nil];
                            _veh setVariable ["ITW_transportGroups",nil,true];
                            _veh setVariable ["reported",nil];
                        };
                        // tell them to get out again, sometimes a couple get back in
                        units _grp apply { _x leaveVehicle (assignedVehicle _x) };
                        // move the units away from the vehicle
                        private _toPos = _veh getPos [200,_veh getDir (([getPosATL _veh] call ITW_ObjGetNearest)#ITW_OBJ_POS)];
                        {_x doMove _toPos} forEach units _grp;
                        _grp setVariable [
                            "ITW_CLASH_TransportPhysicalUnloadPending",nil
                        ];
                        if (!isNil "ITW_CLASH_PlayerTransport_fnc_Release") then {
                            [_grp,"player-ferry-delivered"] call
                                ITW_CLASH_PlayerTransport_fnc_Release;
                        };
                    };
                    // END -----------------------------------------------------------------------------------------
                    _grp setVariable ["ITW_getInState",2];
                    _veh setVariable ["ITW_groupCntActive",(_veh getVariable ["ITW_groupCntActive",0]) - 1];
                    
                    if (_grp getVariable ["itwDelivery",false]) then {
                        private _curPos = getPosATL leader _grp;
                        private _pos = _grp getVariable ["itwDeliveryPos",_curPos];
                        if (_pos distance _curPos < 500) then {
                            [_grp] call ITW_AllyDelivery;
                        } else {
                            _grp setVariable ["itwDelivery",nil];
                            _grp setVariable ["itwDeliveryPos",nil];
                            ITW_DELETE_WAYPOINTS(_grp);                                
                        };
                    };
                };
            };
        } count _groupsToLoad;
        sleep 4;
    };
    
    private _closestObj = [getPosATL _veh, ITW_OWNER_CONTESTED, ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
    {
        _x setVariable ["ITW_getInState",-1];
        if (!isNil "ITW_CLASH_PlayerTransport_fnc_Release") then {
            [_x,"player-ferry-cleanup"] call
                ITW_CLASH_PlayerTransport_fnc_Release;
        };
        VAR_SET_OBJ_IDX(_x,_closestObj#ITW_OBJ_INDEX);
    } count _groupsToLoad;
};

ITW_AllyParadropCargo = {
    params ["_veh","_grp"];
    if (isNil "ITW_AllyParaCargoSem") then {ITW_AllyParaCargoSem = false};
    SEM_LOCK_LONG(ITW_AllyParaCargoSem);
    [_veh,grpNull,[_grp],[]] call ITW_AtkUnloadAirplane;
    SEM_UNLOCK(ITW_AllyParaCargoSem);
};

ITW_AllySpeedUp = {
    // run on all clients
    params ["_group","_timeout"];
    private _units = units _group;
    {
        _x setAnimSpeedCoef 1.5;
        if (local _x) then {
            _x setSpeedMode "FULL"; 
            _x setBehaviour "AWARE"; 
        };
    } forEach _units;
    sleep _timeout;
    {
        _x setAnimSpeedCoef 1;
    } forEach _units;
};
    
ITW_AllyOrderGetIn = {
    params ["_unit","_veh",["_force",false]];  
    private _seats = fullCrew [_veh,"",true] select {_x#5 == _unit};
    if (_force && {!(_seats isEqualTo [])}) exitWith {
        private _seat = _seats#0;
        if (_seat#2 >= 0) then {
            _unit moveInCargo [_veh,_seat#2];
        } else {
            _unit moveInTurret [_veh,_seat#3];
        };
    };
    private _emptySeats = {isNull (_x#5) && {_x#2 >= 0}} count fullCrew [_veh,"",true];
    if (_emptySeats > 0) then {
        _unit assignAsCargo _veh; 
        if (_force) then {_unit moveInCargo _veh} else {[[_unit],true] remoteExec ["orderGetIn",_unit]};
    } else {
        if !(_veh getVariable ["ITW_BlockAllyCrew",true]) then {
            private _emptyTurrretSeats =  fullCrew [_veh,"",true] select {isNull (_x#5) && {!(_x#3 isEqualTo [])}};
            if !(_emptyTurrretSeats isEqualTo []) then {
                private _turret = (_emptyTurrretSeats select -1)#3;
                _unit assignAsTurret [_veh,_turret]; 
                if (_force) then {_unit moveInTurret [_veh,_turret]} else {[[_unit],true] remoteExec ["orderGetIn",_unit]};
            };           
        };
    };
};

ITW_AllyRadioMsg = {
    // call on clients
    params ["_msgType","_veh"]; // "bStart","bEnd","dEnd"
    if (!hasInterface) exitWith {};
    
    private _path = "\a3\dubbing_f_heli\";
    private "_msg";
    switch (_msgType) do {
        case "bStart": {
            _msg = selectRandom ["mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_IHQ_2.ogg",
                                 "mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_BHQ_0.ogg",
                                 "mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_BHQ_1.ogg",
                                 "mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_BHQ_2.ogg",
                                 "mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_IHQ_0.ogg",
                                 "mp_groundsupport\05_BoardingStarted\mp_groundsupport_05_boardingstarted_IHQ_1.ogg"];
        };
        case "bEnd": {
            _msg = selectRandom ["mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_IHQ_2.ogg",
                                 "mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_BHQ_0.ogg",
                                 "mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_BHQ_1.ogg",
                                 "mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_BHQ_2.ogg",
                                 "mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_IHQ_0.ogg",
                                 "mp_groundsupport\10_BoardingEnded\mp_groundsupport_10_boardingended_IHQ_1.ogg"];
        };
        case "dStart": {
            _msg = selectRandom ["showcase_slingloading\37_Landed\showcase_slingloading_37_landed_PIL_0.ogg"];
        };
        case "dEnd": {
            _msg = selectRandom ["mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_IHQ_2.ogg",
                                 "mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_BHQ_0.ogg",
                                 "mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_BHQ_1.ogg",
                                 "mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_BHQ_2.ogg",
                                 "mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_IHQ_0.ogg",
                                 "mp_groundsupport\15_Disembarked\mp_groundsupport_15_disembarked_IHQ_1.ogg"];
        };
    };
    if (! isNil "_msg") then {
        private _volume = 1;
        if (vehicle player != _veh) then {_volume = 0.5 - ((player distance _veh)/20)}; 
        playSoundUI [_path + _msg,_volume,1];
    };
};

ITW_AllyShowAssignmentsDisplay = {
    // spawn on client
    if (!hasInterface) exitWith {};
    scriptname "ITW_AllyShowAssignmentsDisplay";
    
    waitUntil {sleep 1;ITW_ZoneIndex > 0};
    
    createDialog 'RscItwAssignments';
    
    private _timeout = time + 5;
    private "_display";
    waitUntil {_display = findDisplay ITW_DISPLAY_ASSIGNMENTS_ID; !isNull _display || {time > _timeout}};
    if (isNull _display) exitWith {};
    
    _table = _display displayCtrl ITW_ASSIGNMENTS_TABLE_IDC;
    _header = ctAddHeader _table;
    _header#1 params ["_hdrBack","_hdrCol0","_hdrCol1","_hdrCol2","_hdrCol3","_hdrCol4","_hdrCol5","_hdrCloseBtn"];
    _hdrCol0 ctrlSetText localize "STR_ITW_ALLY_ObjectiveName";
    _hdrCol1 ctrlSetText "--";
    _hdrCol2 ctrlSetText " -";
    _hdrCol3 ctrlSetText "0";
    _hdrCol4 ctrlSetText " +";
    _hdrCol5 ctrlSetText "++";
    _hdrBack ctrlSetBackgroundColor [0,0,0,1];
    
    _hdrCloseBtn ctrlSetText "X";
    _hdrCloseBtn ctrlSetBackgroundColor [0,0,0,0.7];
    _hdrCloseBtn ctrlAddEventHandler ["ButtonClick",{closeDialog 1}];
    
    private _visibleMap = visibleMap;
    if (!_visibleMap) then {openMap true};
    
    private _objectives = ITW_Zones#ITW_ZoneIndex;
    private _azPriCnt = count _objectives;
    if (count ITW_AllyPriority != _azPriCnt) then {
        ITW_AllyPriority = [];
        ITW_AllyPriority resize [_azPriCnt,3];
    };
    ITW_AllyTempPriorities = +ITW_AllyPriority;
    ITW_AllyRowCBoxes = [];
    ITW_AllyCBoxesUpdating = true;
    
    {
        private _objIdx = _x;
        private _obj    = ITW_Objectives#_objIdx;
        private _objName     = _obj#ITW_OBJ_NAME;
        private _objCaptured = _objIdx call ITW_ObjContestedOwnerIsFriendly; 
        private _priority    = ITW_AllyTempPriorities param [_forEachIndex,3];
        
        _newRow = ctAddRow _table;
        _newRow#1 params ["_rowBack","_rowCol0","_rowCol1","_rowCol2","_rowCol3","_rowCol4","_rowCol5"];
        private _cboxes = [_rowCol1,_rowCol2,_rowCol3,_rowCol4,_rowCol5];
        ITW_AllyRowCBoxes pushBack _cboxes;
        _rowCol0 ctrlSetText _objName;
        {
            private _cbox = _x;
            _cbox cbSetChecked ((_priority-1) == _forEachIndex);
            _cbox ctrlAddEventHandler ["CheckedChanged", {
                    params ["_cb","_checked"];
                    if !(ITW_AllyCBoxesUpdating) then {;
                        ITW_AllyCBoxesUpdating = true;
                        if (_checked == 1) then {
                            {
                                private _cboxes = _x;
                                private _priority = _cboxes find _cb;
                                if (_priority >= 0) exitWith {
                                    private _row = _forEachIndex;
                                    _cboxes apply {_x cbSetChecked false}; // disable all cboxes in row
                                    ITW_AllyTempPriorities set [_row,_priority + 1];
                                };    
                            } forEach ITW_AllyRowCBoxes;
                        };
                        _cb cbSetChecked true;
                        ITW_AllyCBoxesUpdating = false;
                    };
            }];
        } forEach _cboxes;
        _rowBack ctrlSetBackgroundColor (if (_objCaptured) then {[0,0,0.5,1]} else {[0.5,0,0,1]});
    } forEach _objectives;
    ITW_AllyCBoxesUpdating = false;
      
    waitUntil {isNull _display};
    
    if (!_visibleMap) then {openMap false};
    
    if !(ITW_AllyTempPriorities isEqualTo ITW_AllyPriority) then {
        [ITW_AllyTempPriorities] remoteExec ["ITW_AllyReassign",2];
    };
};

ITW_AllyPlaceLandRouteMarker = {
    params ["_marker","_objIdx","_attakToObjIdx"];
    private _dir = random 360;
    if (_objIdx < 0) then {_objIdx = _attakToObjIdx;_dir = 0};
    private _objPos = ITW_Objectives#_objIdx#ITW_OBJ_POS;
    private _pos = _objPos getPos [200,_dir];
    _marker setMarkerPosLocal _pos;
};

ITW_AllyChooseLandRoutes = {
    ITW_LAND_ROUTE_RESET = false;
    ITW_LAND_MKR = "";
    ITW_LAND_MARKERS = []; // array of [marker,attackFromObjIdx,attackToObjIdx]
    if (ITW_ZoneIndex >= count ITW_Zones) exitWith {};
    private _objIds = ITW_Zones#ITW_ZoneIndex;
    private _objs = [];
    private _resetIndexes = [];
    private _zoneIndex = ITW_ZoneIndex;
    private _tooSoon = false;
    {
        private _objIdx = _x;
        private _obj = ITW_Objectives#_objIdx;
        private _letter = _obj#ITW_OBJ_NAME;
        private _attacks = _obj#ITW_OBJ_ATTACKS;
        if (_attacks isEqualTo []) exitWith {_tooSoon = true};
        private _attackFromIdx = if (_obj#ITW_OBJ_ATK_AVAIL#0) then {_obj#ITW_OBJ_ATTACKS#ITW_ATTACK_LAND_F} else {BASE_INDEX_NONE};
        _objs pushBack _obj;
        _resetIndexes pushBack _attackFromIdx;
        private _marker = createMarkerLocal ["landRoute"+str(_forEachIndex), [0,0]]; 
        _marker setMarkerTypeLocal "loc_BusStop";
        _marker setMarkerColorLocal "ColorBlue";
        _marker setMarkerTextLocal _letter;
        _marker setMarkerAlphaLocal 0.8;
        ITW_LAND_MARKERS pushBack [_marker,_attackFromIdx,_objIdx];
        [_marker,_attackFromIdx,_objIdx] call ITW_AllyPlaceLandRouteMarker;
    } forEach _objIds;
    if (_tooSoon) exitWith {hint localize "STR_ITW_ALLY_UnavailableTryAgain"}; // attack vectors are still being calculated
    ITW_LAND_MARKERS_RESET = +ITW_LAND_MARKERS;
    
    private _keyHandler = findDisplay 12 displayCtrl 51 ctrlAddEventHandler ["KeyDown", 
        {
            params ["_displayorcontrol", "_key", "_shift", "_ctrl", "_alt"];
            private ["_return"];
            _return = false;
            // key 0x13 is R
            if (_key == 0x13 and !_alt and !_shift) then {
                ITW_LAND_ROUTE_RESET = true;
                ITW_LAND_MKR = "";
                {_x call ITW_AllyPlaceLandRouteMarker} forEach ITW_LAND_MARKERS_RESET;
                _return = true;
            };
            _return
        }];
    
    private _handlerDown = findDisplay 12 displayCtrl 51 ctrlAddEventHandler ["MouseButtonDown", 
        {
            params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
            // 0 is left button
            if (!_alt and !_shift and !_ctrl and _button == 0) then {
                // Get marker near click location
                private _pos = (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                private _minDist = 1e6; // 1000 squared
                private _closest = "";
                {
                    private _dist = (getMarkerPos (_x#0)) distanceSqr _pos;
                    if (_dist < _minDist) then {
                        _minDist = _dist;
                        _closest = _x#0;
                    };
                } forEach ITW_LAND_MARKERS;
                ITW_LAND_MKR = _closest; 
            };
            false
        }];
    private _handlerUp = findDisplay 12 displayCtrl 51 ctrlAddEventHandler ["MouseButtonUp", 
        {
            params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
            // 0 is left button
            if (_button == 0 && {ITW_LAND_MKR != ""}) then {
                // Drop the marker
                private _mIdx = ITW_LAND_MARKERS findIf {_x#0 == ITW_LAND_MKR};
                if (_mIdx < 0) exitWith {};
                private _pos = (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                private _nearestObj = [_pos,ITW_OWNER_FRIENDLY] call ITW_ObjGetNearest;
                private _nearestObjPos = _nearestObj#ITW_OBJ_POS;
                if (_pos distanceSqr _nearestObjPos < 1e6) then {
                    private _objIdx = _nearestObj#ITW_OBJ_INDEX;
                    ITW_LAND_MARKERS#_mIdx set [1,_objIdx];
                } else {
                    ITW_LAND_MARKERS#_mIdx set [1,-1];
                };
                (ITW_LAND_MARKERS#_mIdx) call ITW_AllyPlaceLandRouteMarker;
                ITW_LAND_MKR = ""; 
            };
            false
        }];    
    private _handlerMoving = findDisplay 12 displayCtrl 51 ctrlAddEventHandler ["MouseMoving",
        {
            params ["_control", "_xPos", "_yPos", "_mouseOver"];
            if (ITW_LAND_MKR != "") then {
                ITW_LAND_MKR setMarkerPosLocal (_control ctrlMapScreenToWorld [_xPos,_yPos]);
            };
            false
        }];
        
    ITW_ShowFriendlyPaused = true;
    showMap true; 
    openMap true;
    waitUntil {visibleMap};
    mapAnimAdd [0, 1, [worldSize/2,worldSize/2]];
    mapAnimCommit;
    private _timeout = 0;
    while {visibleMap && {_zoneIndex == ITW_ZoneIndex}} do {
        if (time > _timeout) then {
            hintSilent localize "STR_ITW_ALLY_DragCarIcon";
            _timeout = time + 29;
        };
        sleep 1;
    };
    ITW_ShowFriendlyPaused = false;
    findDisplay 12 displayCtrl 51 ctrlRemoveEventHandler ["MouseButtonUp",_handlerUp];
    findDisplay 12 displayCtrl 51 ctrlRemoveEventHandler ["MouseButtonDown",_handlerDown];
    findDisplay 12 displayCtrl 51 ctrlRemoveEventHandler ["MouseMoving",_handlerMoving]; 
    findDisplay 12 displayCtrl 51 ctrlRemoveEventHandler ["KeyDown",_keyHandler]; 
    if (_zoneIndex == ITW_ZoneIndex) then {
        private _msg = "";
        private _updatedObjs = [];
        {      
            _x params ["_marker","_fromObjIdx","_toObjIdx"];
            private _origFromIdx = ITW_LAND_MARKERS_RESET#_forEachIndex#1;
            if (_fromObjIdx != _origFromIdx) then {
                // friendly land attack vector changed
                _updatedObjs pushBack [_toObjIdx,_fromObjIdx];
                _msg = _msg + (markerText _marker) + " " + localize "STR_ITW_ALLY_Updated" + "\n";
            };
            deleteMarker _marker;
        } forEach ITW_LAND_MARKERS;
        if !(_updatedObjs isEqualTo []) then { 
            _updatedObjs remoteExec ["ITW_ObjLandAtkAdjust",2];
            hint _msg;
        } else {hint localize "STR_ITW_ALLY_NoRoutesUpdated"};
    } else {
        hint localize "STR_ITW_ALLY_CanceldZoneCaptured";
    };
};

ITW_AllyDelivery = {
    params ["_grp"];
    if (!isNil "ITW_CLASH_PlayerTransport_fnc_ReserveDelivery") then {
        [_grp,"itw-delivery-route"] call
            ITW_CLASH_PlayerTransport_fnc_ReserveDelivery;
    } else {
        _grp setVariable ["itwDelivery",true];
    };
    ITW_DELETE_WAYPOINTS(_grp);
    private _pos = ([getPosATL leader _grp] call ITW_BaseNearest)#ITW_BASE_POS;
    _grp setVariable ["itwDelivery",true];
    _grp setVariable ["itwDeliveryPos",_pos];
    private _wp1 = _grp addWaypoint [[_pos,100,0,60] call ITW_AtkWpPoint,10];
    _wp1 setWaypointBehaviour "SAFE";
    _wp1 setWaypointSpeed "LIMITED";
    _wp1 setWaypointCombatMode "YELLOW";
    _wp1 setWaypointType "MOVE";
    _wp1 setWaypointFormation selectRandom ["COLUMN","STAG COLUMN","DIAMOND"];
    _wp1 setWaypointStatements ["true",format ["
        if (isNil ""thisList"") exitWith {};
        private _grp = group this;
        [_grp,currentWaypoint _grp] setWaypointPosition [[%1,100,0,60] call ITW_AtkWpPoint,10]",_pos]];
    private _wp2 = _grp addWaypoint [_pos,0];
    _wp2 setWaypointType "CYCLE";
    _wp2 setWaypointCompletionRadius 150;
};

ITW_AllyTeamSwitch = {
    [
        { // which units function
            units ITW_PlayerSide select {alive _x && {!((group _x) getVariable ["itwInitGrp",false])}}}, 
        {  // before switch function (called where player is local)
            params ["_player","_ai"];
            _player setVariable ["itwIgnoreGetOut",true];
        },
        {  // after switch function (called where player is local)
            params ["_player","_ai"];
            _player setVariable ["itwIgnoreGetOut",false];
            [group _player,group _ai] call ITW_TeammatesSwapTeam;
        }
    ] spawn SKL_TeamSwitch;
};

ITW_AllyReqReinforcements = {
    // call on client requesting reinforcements
    ITW_ALLY_MENU = [
        [localize "STR_ITW_ALLY_Reinforcements", false],
        [localize "STR_ITW_ALLY_SomeInfantry"  ,[2], "", -5, [["expression", "ITW_allyMenu = 1"]], "1", "1"],
        [localize "STR_ITW_ALLY_SomeVehicles"  ,[3], "", -5, [["expression", "ITW_allyMenu = 2"]], "1", "1"],
        [localize "STR_ITW_ALLY_SomeBoth"      ,[4], "", -5, [["expression", "ITW_allyMenu = 3"]], "1", "1"],
        [localize "STR_ITW_ALLY_AllInfantry"   ,[5], "", -5, [["expression", "ITW_allyMenu = 4"]], "1", "1"],
        [localize "STR_ITW_ALLY_AllVehicles"   ,[6], "", -5, [["expression", "ITW_allyMenu = 5"]], "1", "1"],
        [localize "STR_ITW_ALLY_AllBoth"       ,[7], "", -5, [["expression", "ITW_allyMenu = 6"]], "1", "1"],
        [localize "STR_ITW_COMMON_Cancel"      ,[16],"", -3, [["expression", ""]], "1", "1"]
    ];
    ITW_allyMenu = nil;
    showCommandingMenu "#USER:ITW_ALLY_MENU";
    waitUntil {commandingMenu == ""};
    if (!isNil "ITW_allyMenu") then {[ITW_allyMenu,player] remoteExec ["ITW_AllyReqReinfServer",2]};
    ITW_ALLY_MENU = nil;
    ITW_allyMenu = nil;
};

ITW_AllyReqReinfServer = {
    params ["_who","_player"]; // 1=infantry,  2=vehicles,  3=both
    private _pos = getPosATL _player;
    private _troopsSent = 0;
    private _vehSent = 0;
    private _transports = [];
    private _justSome = _who in [1,2,3];
    #define ALLY_INF_DIST 1000
    #define ALLY_VEH_DIST 1000
    if (_who in [1,3,4,6]) then {
        // Infantry
        private _distSqr = ALLY_INF_DIST * ALLY_INF_DIST;
        private _groups = ITW_AllyGroups select {
            private _grp = _x;
            private _keep = true;
            private _leader = leader _grp;
            private _veh = vehicle _leader;
            if (_leader != _veh) then {
                // don't use non-land vehicles, or vehicles where this group is the driver/gunner/etc
                if (!(_veh isKindOf "Land") || {driver _veh in units _grp}) then {_keep = false};
            };
            if (_keep && {_leader distanceSqr _pos > _distSqr}) then {_keep = false};
            _keep
        };
        if (_justSome && {count _groups > 1}) then {
            private _distArray = _groups apply {[leader _x distance _pos,_x]};
            _distArray sort true;
            private _cutoff = floor (((count _distArray)/2) - 0.4);
            _distArray resize _cutoff;
            _groups = _distArray apply {_x#1};
        };
{diag_log ["INF",_x,count units _x]} foreach _groups;        
        {_troopsSent = _troopsSent + count units _x} forEach _groups;
        {
            private _grp = _x;
            private _complRadius = 20;
            private _leader = leader _grp;
            private _veh = vehicle _leader;
            if (_veh != _leader) then {
                if (_veh in _transports) then {continue};
                _grp = group driver _veh;
                _transports pushBack _veh;
                _complRadius = 250;
            };
            ITW_DELETE_WAYPOINTS(_grp);
            private _wp = _grp addWaypoint [_pos getPos [random 50,random 360], 0];
            _wp setWaypointBehaviour "AWARE";
            _wp setWaypointSpeed "NORMAL";
            _wp setWaypointCombatMode "RED";
            _wp setWaypointType "MOVE"; 
            _wp setWaypointFormation selectRandom ["WEDGE","VEE","STAG COLUMN","DIAMOND"];
            _wp setWaypointCompletionRadius _complRadius;
        } forEach _groups;
    };
    if (_who in [2,3,5,6]) then {
        // vehicles
        private _groups = [];
        private _groupsWithTroops = [];
        private _distSqr = ALLY_VEH_DIST * ALLY_VEH_DIST;
        SEM_LOCK(ITW_AtkVehicleManagerBusy);
        {
            private _vehInfo = _x;
            private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
            if (side _crewGroup != ITW_PlayerSide) then {continue};
            if (!(ITW_VEH_IS_LAND(_vehInfo#VEHINFO_TYPE))) then {continue};
            if (_vehInfo#VEHINFO_ROLE in [ITW_VEH_ROLE_TRANSPORT,ITW_VEH_ROLE_COMPLETE]) then {continue};
            if (_vehInfo#VEHINFO_VEH in _transports) then {continue};
            if (leader _crewGroup distanceSqr _pos > _distSqr) then {continue}; 
            if (_vehInfo#VEHINFO_CARGO_GRPS isNotEqualTo []) then {_groupsWithTroops pushBack _crewGroup} else { _groups pushBack _crewGroup};
        } forEach ITW_ManagedVehs;
        SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
        if (_who in [2,5] && {_groupsWithTroops isNotEqualTo []}) then {
            // didn't ask for infantry, but found attack vehicle with infantry inside
            if (_who == 2) then {
                // asked for some vehicles, lets add the lists together, but we'll count the dual veh as far away later
                _groups = _groups + _groupsWithTroops;
            } else {
                // asked for all vehicles
                if (count _groups < 2) then {_groups = _groups + _groupsWithTroops};
            };
        };
        if (_justSome && {count _groups > 1}) then {
            private _distArray = _groups apply {[(if (_x in _groupsWithTroops) then {1000} else {0}) + (leader _x distance _pos),_x]};
            _distArray sort true;
            private _cutoff = floor ((count _distArray + 1)/2);
            _distArray resize _cutoff;
            _groups = _distArray apply {_x#1};
        };
        _vehSent = count _groups; 
        {
            private _grp = _x;
            ITW_DELETE_WAYPOINTS(_grp);
            private _wp = _grp addWaypoint [_pos getPos [random 200,random 360], 0];
            _wp setWaypointBehaviour "COMBAT";
            _wp setWaypointSpeed "NORMAL";
            _wp setWaypointCombatMode "RED";
            _wp setWaypointType "SAD"; 
            _wp setWaypointCompletionRadius 30;
        } forEach _groups;
    };
    
    // notify requester of who was sent
    if (_troopsSent + _vehSent == 0) then {
        [localize "STR_ITW_ALLY_ReinfNone"] remoteExec ["hint",_player];
    } else {
        [format [localize "STR_ITW_ALLY_ReinfResponse",_troopsSent,_vehSent]] remoteExec ["hint",_player];
    };
};

["ITW_AllyInit"] call SKL_fnc_CompileFinal;
["ITW_AllyGroupCallback"] call SKL_fnc_CompileFinal;
["ITW_AllyAttackVectors"] call SKL_fnc_CompileFinal;
["ITW_AllyReassign"] call SKL_fnc_CompileFinal;
["ITW_AllyGetAssignedGroups"] call SKL_fnc_CompileFinal;
["ITW_AllyCalculateWeights"] call SKL_fnc_CompileFinal;
["ITW_AllyNext"] call SKL_fnc_CompileFinal;
["ITW_AllyDismiss"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruit"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruitTeam"] call SKL_fnc_CompileFinal;
["ITW_AllyRecall"] call SKL_fnc_CompileFinal;
["ITW_AllyHighCmdr"] call SKL_fnc_CompileFinal;
["ITW_AllyHcRespawn"] call SKL_fnc_CompileFinal;
["ITW_AllyLoadIntoVehManager"] call SKL_fnc_CompileFinal;
["ITW_AllyLoadGrpIntoVeh"] call SKL_fnc_CompileFinal;
["ITW_AllySpeedUp"] call SKL_fnc_CompileFinal;
["ITW_AllyOrderGetIn"] call SKL_fnc_CompileFinal;
["ITW_AllyRadioMsg"] call SKL_fnc_CompileFinal;
["ITW_AllyShowAssignmentsDisplay"] call SKL_fnc_CompileFinal;
["ITW_AllyPlaceLandRouteMarker"] call SKL_fnc_CompileFinal;
["ITW_AllyChooseLandRoutes"] call SKL_fnc_CompileFinal;
["ITW_AllyDelivery"] call SKL_fnc_CompileFinal;
["ITW_AllyOptions"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruitTeamServer"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruitLocal"] call SKL_fnc_CompileFinal;
["ITW_AllyParadropCargo"] call SKL_fnc_CompileFinal;
["ITW_AllyLoadoutCopy"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruitMenuItem"] call SKL_fnc_CompileFinal;
["ITW_AllyRecruitUnitLocal"] call SKL_fnc_CompileFinal;
["ITW_AllyTeamSwitch"] call SKL_fnc_CompileFinal;
["ITW_AllyReqReinforcements"] call SKL_fnc_CompileFinal;
["ITW_AllyReqReinfServer"] call SKL_fnc_CompileFinal;