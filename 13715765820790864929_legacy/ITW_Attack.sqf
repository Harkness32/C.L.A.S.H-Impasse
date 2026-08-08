
#include "defines.hpp"
#include "\a3\ui_f\hpp\definecommongrids.inc"

ITW_AtkVehicleManagerBusy = false;
ITW_AtkInfantryManagerBusy = false;
ITW_ManagedVehs     = [];
ITW_AtkVectors   = [{},{}];
ITW_AtkManagersStarted = false;
ITW_VehArrays = [];
ITW_VehArraysUpdating = false;
ITW_AllyIndex = -1; // used when triggering a new zone to wake up the ITW_AtkManagers
ITW_AirVehsDef = [[[],[],[]],[[],[],[]]]; // vehDefs for air vehicles allowed in this zone as array of [[friendly attack,dual,transport],[enemy attack,dual,transport]]
ITW_AtkStaticNeedsCrew = [[],[]];
ITW_AtkPlayersJoinWave = [];
ITW_AtkTeammatesJoinWave = []; // array of  [player,array of teammates that didn't fit into vehicle]
#define WEAPONLESS_FACTIONS ["OPTRE_FC_COVENANT","HL_ZOMBIES","RYANZOMBIESFACTION","RYANZOMBIESFACTIONOPFOR","RYANZOMBIESFACTIONMODULE"] // units that are 'kindOf' these are not checked for weapons (UPPER CASE)
#define ATK_DEBUG(msg1,msg2,msg3) //diag_log format ["ITW: %1 %2 %3",msg1,msg2,msg3]
#define ATK_DEBUG2(msg1,msg2,msg3,msg4) //diag_log format ["ITW: %1 %2 %3 %4",msg1,msg2,msg3,msg4]
ITW_ATK_DEBUG = {ATK_DEBUG(_this#0,_this#1,_this#2)}; // if needed inside quotes, this allows for a workaround

ITW_Debug = {
    diag_log "===== ITW DEBUG =======";
    diag_log "---Objectives---";
    {diag_log [_forEachIndex,_x]} forEach ITW_Objectives;
    diag_log "---Bases---";
    {diag_log [_forEachIndex,_x]} forEach ITW_Bases;
    diag_log "---Zones---";
    {diag_log [_forEachIndex,_x]} forEach ITW_Zones;
    diag_log ("Zone Index: " + str ITW_ZoneIndex);
    diag_log "---Vehicle Spawn Info---";
    call ITW_AtkMgrDebug;
    diag_log "---Vehicle Assignments---";
    call ITW_AtkMgrDebugVehs;
    diag_log "---Vehicle List---";
    call ITW_DebugListVehs;
    diag_log "=======================";
};

ITW_AtkMgrDebug = {
    {
        _x params ["_type","_role","_zones","_ticketsReq","_tickets","_maxCnt","_count","_vehs","_isFriendly"];
        diag_log [
            if (_isFriendly) then {"Friend"}else{"Enemy "},
            ["Plane","Heli ","Tank ","APC  ","Car  ","Ship "] # (_type -10),
            ["Attack","Transp","Dual  ","DONE  "]     # (_role -20),
            "   Tickets",floor _tickets,_ticketsReq,
            "   Counts",_count,floor _maxCnt,
            "   VehTypes",count _vehs
        ];
    } forEach ITW_VehArrays;
};

ITW_AtkMgrDebugVehs = {
    diag_log ("Veh Types: " + (if (typeName ITW_PlayerFaction == "STRING") then {ITW_PlayerFaction} else {ITW_PlayerFaction joinString ","}) + " : " + (if (typeName ITW_EnemyFaction == "STRING") then {ITW_EnemyFaction} else {ITW_EnemyFaction joinString ","}));
    {
        _x params ["_type","_role","_zones","_ticketsReq","_tickets","_maxCnt","_count","_vehs","_isFriendly"];
        _vehNames = _vehs apply {if (typeName _x == "ARRAY") then {_x=_x#0};getText(configFile >> "cfgVehicles" >> _x >> "displayName")} joinString ",";
        //{"," + _type} forEach _vehNameArray;
        diag_log format["%1,%2,%3,%4",
            if (_isFriendly) then {"Friend"}else{"Enemy "},
            ["Plane","Heli ","Tank ","APC","Car","Ship "] # (_type -10),
            ["Attack","Transp","Dual","DONE"]     # (_role -20),
            _vehNames
        ];
    } forEach ITW_VehArrays;
    diag_log "---";
};

ITW_AtkRoadDebug = {
    // Show dots on spawning roads
    if (isNil "ITW_AtkRoadMap") exitWith {hint localize "STR_ITW_MISC_RoadsNotSetYet"};
    {
        _x params ["_baseFrom","_objTo"];
        {
            private _m = createMarkerLocal [format ["mroad_%1_%2_%3",_baseFrom,_objTo,_forEachIndex],_x];
            _m setMarkerPosLocal _x;
            _m setMarkerTypeLocal "hd_dot";
            _m setMarkerColorLocal "ColorBlack";
        } forEach _y;
    } forEach ITW_AtkRoadMap;
};

ITW_AtkManager = {
    // spawn on server for friendly and enemy ai separately
    params ["_isFriendly","_factions","_vehArray","_variablesArray","_fnAttackVectors",["_fnGroupsCallback",{}]];
    scriptName ("ITW_AtkManager" + (if (_isFriendly) then {"_friendly"} else {"_enemy"}));

    if (isNil "ITW_atkFriendlyAtkTime") then {ITW_atkFriendlyAtkTime =  time + ITW_ParamFriendlyInvasionDelay};

    //// code for testing to only allow a certain kind of vehicle
    //{
    //    if (_x#ITW_VEH_ROLE != ITW_VEH_ROLE_TRANSPORT || {_x#ITW_VEH_TYPE != ITW_TYPE_VEH_SHIP}) then {_vehArray deleteAt _forEachindex};
    //} forEachReversed _vehArray;

    private _whichSide = if (_isFriendly) then {ATTACK_FRIENDLY} else {ATTACK_ENEMY};

    // variable needed in some routines
    if (isNil "ITW_Atk_Flat_Place") then { 
        ITW_AtkFlatPlaceSem = false;
        ITW_Atk_Flat_Place = [[worldSize,worldSize,0], 0, worldSize*2, 20, 0, 0.5, 0, [], [[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
        if (count ITW_Atk_Flat_Place == 2) then {ITW_Atk_Flat_Place pushBack 0};
        ITW_TransportTypesAllowedHashmap = createHashMapFromArray [
            [ITW_TYPE_VEH_AIRPLANE, ITW_ParamTransportPlaneSpawnAdjustment > 0],
            [ITW_TYPE_VEH_HELI,     ITW_ParamTransportHeliSpawnAdjustment  > 0],
            [ITW_TYPE_VEH_TANK,     ITW_ParamTransportTankSpawnAdjustment  > 0],
            [ITW_TYPE_VEH_APC,      ITW_ParamTransportApcSpawnAdjustment   > 0],
            [ITW_TYPE_VEH_CAR,      ITW_ParamTransportCarSpawnAdjustment   > 0],
            [ITW_TYPE_VEH_SHIP,     ITW_ParamTransportShipSpawnAdjustment  > 0]
        ];

    };
    
    // _variablesArray params ["_reloadRocketsGrenadesTime","_onFootTeleportChance"];
    ITW_VehArrays = ITW_VehArrays + _vehArray;
     
    // spawn the managers only once
    if (!ITW_AtkManagersStarted) then {
        ITW_AtkManagersStarted = true;
        0 spawn ITW_AtkInfantryManager;
        0 spawn ITW_AtkVehicleManager;
        0 spawn ITW_AtkStuckHandler;
    };
    ITW_AtkVectors set [_whichSide,_fnAttackVectors];
    
    private _side      = if (_isFriendly) then {west} else {ITW_EnemySide};
    private _fallback  = if (_isFriendly) then {FACTION_UNIT_FALLBACK_SUBF_BLU} else {FACTION_UNIT_FALLBACK_SUBF_OPF};
    private _unitTypes =   ([_factions,["Crewman","Diver"],true,call _fallback] call FactionUnits) apply {toLowerANSI _x};
    private _crewTypes =   ([_factions,["Crewman"],false,call FACTION_UNIT_FALLBACK_ROLE_REQ] call FactionUnits) apply {toLowerANSI _x};
    private _missleTypes = ([_factions,["MissileSpecialist"],false,call FACTION_UNIT_FALLBACK_ROLE_REQ] call FactionUnits) apply {toLowerANSI _x};
    if (_crewTypes isEqualTo []) then {_crewTypes = _unitTypes};

    private _squadNames = [];// array of squadNames (order is identical to ITW_AllySquadTypes
    private _squadTypes = [];    // array of [unitClass,unitClass,...]
    {   // "West"
        {   // "BLU_F"
            {   // "Infantry"
                {   // "BUS_InfSquad" => "Rifle Squad"
                    private _squadCfg = _x;
                    private _unitCfgs = (configProperties [_squadCfg,"isClass _x && !(toLowerANSI (getText (_x >> 'vehicle')) in _unitTypes)",true]);
                    if (_unitCfgs isEqualTo []) then {
                        // only our infantry
                        _squad = [];
                        {
                            _squad pushBack toLowerANSI getText (_x >> "vehicle");
                        } forEach (configProperties [_squadCfg,"isClass _x",true]);
                        if (count _squad > 1) then {
                            if (_isFriendly) then {_squadNames pushBack format ["%1 (%2)",getText (_squadCfg >> "name"),count _squad]};
                            _squadTypes pushBack _squad;
                        };
                    };
                } forEach (configProperties [_x,"isClass _x",true]);
            } forEach (configProperties [_x,"isClass _x",true]);
        } forEach (configProperties [_x,"isClass _x",true]);
    } forEach (configProperties [(configFile >> "CfgGroups"),"isClass _x",true]);
    
    if (_isFriendly) then {
        ITW_AllySquadTypeNames = _squadNames;
        ITW_AllySquadTypes = _squadTypes;
        publicVariable "ITW_AllySquadTypeNames";
        publicVariable "ITW_AllySquadTypes";
    };
    
    // at least 50% of the units in this faction must be in squads or we don't use the defined squads, as a safety measure for strange factions
    private _flatSquads = flatten _squadTypes;
    _flatSquads = _flatSquads arrayIntersect _flatSquads; // get rid of duplicates
    if (count _flatSquads < (count _unitTypes / 2)) then {
        _squadTypes = [];
        diag_log format ["ITW: Too few %1 units in squads (%2/%3), using random squad makeup",["enemy","ally"] select _isFriendly,count _flatSquads,count _unitTypes];
    };
    _flatSquads = nil; // free up space
    private _zoneCount = count ITW_Zones - 1; // -1 since no-one owns the contested zone
    
    private _groups = [];
    private _spawnGroup = grpNull;
    private _homeObj = ITW_Objectives#(if (_isFriendly) then {ITW_Zones#0#0} else {ITW_Zones#-1#0});
    private _homeBase = ITW_Bases#(_homeObj#ITW_OBJ_INDEX);
    private _homeSpawnPt = _homeBase#ITW_BASE_A_SPAWN;
    private _homeVehSpawnPt = _homeObj#ITW_OBJ_V_SPAWN;
    private _spawnRateSlow = ITW_ParamEnemyAiCnt * AI_SPAWN_RATE;
    private _spawnRateFast = _spawnRateSlow * 2;
    private _defendPrevVehMax = _vehArray apply {_x#ITW_VEH_MAX};
    
    private _fnEnsureSpawn = {
        params ["_spawnPt","_obj"];
        if (_spawnPt isEqualTo []) then {
            private _begin = _obj#ITW_OBJ_POS;
            private _center = [worldSize/2,worldSize/2,0];
            private _dir = _begin getDir _center;
            private _dist = 100;
            private _pt = +_center;
            while {true} do {
                _dist = _dist + 20;
                _pt = _begin getPos [_dist,_dir];
                if (_pt distance2D _center < 200) exitWith {_pt = _center};
                if (_pt isFlatEmpty [5,-1,1.0,1,0,false,objNull] isEqualTo []) exitWith {};
            };
            
            // copy elements so that array is updated
            _spawnPt set [0,_pt#0];
            _spawnPt set [1,_pt#1];
            _spawnPt set [2,0];
            [_pt,20,[FLAG_TYPE]] remoteExec ["ITW_RemoveTerrainObjects",0,true];
        };
    };

    [_homeSpawnPt,_homeObj] call _fnEnsureSpawn;
    [_homeVehSpawnPt,_homeObj] call _fnEnsureSpawn;
    
    private _spawnTrigger = AI_SPAWN_TRIGGER - 2;
    private _prevVehSideAdj = -1;
    private ["_ticketsBase","_ticketsBasePlaneAttack","_ticketsBaseHeliAttack","_ticketsBaseTankAttack","_ticketsBaseApcAttack","_ticketsBaseCarAttack","_ticketsBaseShipAttack"];
    private ["_ticketsBasePlaneTransport","_ticketsBaseHeliTransport","_ticketsBaseTankTransport","_ticketsBaseApcTransport","_ticketsBaseCarTransport","_ticketsBaseShipTransport"];
    {
        private _role = _x#ITW_VEH_ROLE;
        private _type = _x#ITW_VEH_TYPE;
        private _oldMax = _x#ITW_VEH_MAX;
        private _typeAdj = switch (_type) do {
                case ITW_TYPE_VEH_AIRPLANE: {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportPlaneSpawnAdjustment} else {ITW_ParamAttackPlaneSpawnAdjustment}};
                case ITW_TYPE_VEH_HELI:     {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportHeliSpawnAdjustment } else {ITW_ParamAttackHeliSpawnAdjustment }};
                case ITW_TYPE_VEH_TANK:     {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportTankSpawnAdjustment } else {ITW_ParamAttackTankSpawnAdjustment }};
                case ITW_TYPE_VEH_APC:      {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportApcSpawnAdjustment  } else {ITW_ParamAttackApcSpawnAdjustment  }};
                case ITW_TYPE_VEH_CAR:      {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportCarSpawnAdjustment  } else {ITW_ParamAttackCarSpawnAdjustment  }};
                case ITW_TYPE_VEH_SHIP:     {if (_role == ITW_VEH_ROLE_TRANSPORT) then {ITW_ParamTransportShipSpawnAdjustment } else {ITW_ParamAttackShipSpawnAdjustment }};
                default {1};
            };
        private _adjustment = ITW_ParamVehicleSpawnAdjustment * _typeAdj;
        private _newMax =  1 max round (_oldMax * ITW_ParamVehicleSpawnAdjustment);
        if (_isFriendly) then {
            _adjustment = _adjustment * ITW_ParamVehicleSideAdjustment;
            _newMax =  1 max round (_oldMax * ITW_ParamVehicleSideAdjustment);
        };
        if (_role in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL]) then { 
            if (_adjustment <= 0) then { _newMax = 0} else {_newMax = 1 max round (_newMax * _adjustment)};
        } else { 
            if (_adjustment < 0) then {_newMax = 0};
        };
        _x set [ITW_VEH_MAX,_newMax];
    } forEach _vehArray;
    
    if (ITW_AllyIndex < 0) then {ITW_AllyIndex = ITW_ZoneIndex};
    
    private _zoneIndex = -1; // owned airport change triggers the loop to reset, but we need to know if its a new zone or just the airports
    private _inDefendPhase = false;
    private _defendPushTime = 0;  
    private _defendModeBoost = 1;
    private _defendStartBoost = ITW_ParamDefendVehBoost;
    
    while {!ITW_GameOver} do {
        while {ITW_ObjZonesUpdating} do {sleep 0.5};
        while {LV_PAUSE} do {sleep 5};
        
        private _newZone = _zoneIndex != ITW_ZoneIndex;
        _zoneIndex = ITW_ZoneIndex;
        if (_zoneIndex >= count ITW_Zones) exitWith {};
        
        // give the enemy ai a head start to populate objectives
        if (_isFriendly && _newZone) then {
            if (time < 300) then {
                // game just started
                ITW_atkFriendlyAtkTime = time + ITW_ParamFriendlyInvasionDelay; 
                publicVariable "ITW_atkFriendlyAtkTime";
                sleep ITW_ParamFriendlyInvasionDelay;
            } else {
                // advanced to new zone
                sleep 30;
            };
        }; 
        
        private _zonesOwned = if (_isFriendly || {ITW_ParamVehicleEscalation == 1}) then {_zoneIndex - 1} else {_zoneCount - _zoneIndex};        

        private _zoneLimtedCount = 0;
        private _transport = [];
        private _attackVeh = [];
        private _dualVeh = [];
        private _transportAir = [];
        private _attackVehAir = [];
        private _dualVehAir = [];
        private _airPlanes = [];
        private _ownsAirport = _isFriendly call ITW_ObjOwnsAirport;
        private _objsAttackableBySea = false;
        private _objectiveIds = ITW_Zones#_zoneIndex;
        
        // determine if any obj are able to be attacked by sea
        {
            if !(ITW_SeaPoints#(ITW_Objectives#_x#ITW_OBJ_INDEX) isEqualTo []) exitWith {_objsAttackableBySea = true};
        } forEach _objectiveIds;
        
        {
            private _vehDef = _x;
            if (_vehDef#ITW_VEH_ZONES_OWNED <= _zonesOwned) then {
                private _vehType = _vehDef#ITW_VEH_TYPE;
                if (_vehType==ITW_TYPE_VEH_AIRPLANE && {!_ownsAirport}) then {
                    continue; // cannot use plane without airport
                };
                if (ITW_VEH_IS_SEA(_vehDef#ITW_VEH_TYPE) && {!_objsAttackableBySea}) then {
                    continue; // cannot use ship if ships can't reach objectives
                };
                private _isAttack    = _vehDef#ITW_VEH_ROLE == ITW_VEH_ROLE_ATTACK;
                private _isTransport = _vehDef#ITW_VEH_ROLE == ITW_VEH_ROLE_TRANSPORT;
                private _isDual      = _vehDef#ITW_VEH_ROLE == ITW_VEH_ROLE_DUAL;
                if (_isTransport || {_isDual && (ITW_TransportTypesAllowedHashmap getOrDefault [_vehType,false])}) then {
                    if (_isDual) then {_dualVeh pushBack _vehDef} else {_transport pushBack _vehDef};
                    if (ITW_VEH_IS_AIR(_vehDef#ITW_VEH_TYPE)) then {if (_isDual) then {_dualVehAir pushback _vehDef} else {_transportAir pushback _vehDef}};
                };
                if (_isAttack || _isDual) then {
                    if (_isAttack) then {
                        _attackVeh pushBack _vehDef;
                    } else {
                        // dual fallbacks don't always have attack capabilities
                        if !((_vehDef#ITW_VEH_CLASSES#0) in va_TransportClasses) then {
                            _dualVeh pushBack _vehDef;
                        };
                    };
                    if (ITW_VEH_IS_AIR(_vehDef#ITW_VEH_TYPE)) then {if (_isDual) then {_dualVehAir pushback _vehDef} else {_attackVehAir pushback _vehDef}};
                };
            } else {
                if (ITW_ParamVehicleEscalation == 2) then {_zoneLimtedCount = _zoneLimtedCount + 1};
            };
            false
        } forEach _vehArray; 
        ITW_AirVehsDef set [_whichSide,[_attackVehAir,_dualVehAir,_transportAir]];

        private _ownedObjCnt = {_isFriendly == _x call ITW_ObjContestedOwnerIsFriendly} count (ITW_Zones#_zoneIndex);
        private _populateObjectives = _newZone && _ownedObjCnt > 0; // we have captured objectives to populate
        private _populateSquadCnt = 3; // populate zones owned at the start with this many squads if available
        
        if (!_isFriendly && {_zoneIndex == (count ITW_Zones - 1)}) then {
            // for last zone, enemy spawn out to sea
            _homeObj = ITW_Objectives#-1;
            _homeBase = ITW_Bases#-1;
            _homeSpawnPt = _homeBase#ITW_BASE_A_SPAWN;
            _homeVehSpawnPt = _homeObj#ITW_OBJ_V_SPAWN;
            [_homeSpawnPt,_homeObj] call _fnEnsureSpawn;
            [_homeVehSpawnPt,_homeObj] call _fnEnsureSpawn;
        };
        YIELD_CPU;
        
        if (_newZone) then {
            _inDefendPhase = false;
            _defendPushTime = 0;  // used at start of defend wave (if time < _defendPushTime then we're ramping up spawn rate)
            _defendModeBoost = 1;

            // zone start vehicle boost
            if (ITW_ParamVehBoostZone > 0) then {
                {
                    private _vehDef = _x;
                    private _reqTickets = _vehDef#ITW_VEH_REQD_TICKETS;
                    private _curTickets = _vehDef#ITW_VEH_CURR_TICKETS;
                    _vehDef set [ITW_VEH_CURR_TICKETS,_curTickets + (_reqTickets * ([0,0.5,1.0,1.5] select ITW_ParamVehBoostZone))];
                } forEach _vehArray; 
            };
        };

        while {_zoneIndex == ITW_ZoneIndex && {_ownsAirport == (_isFriendly call ITW_ObjOwnsAirport)} && {!ITW_GameOver}} do {
            
            //// Statics ////
            if !((ITW_AtkStaticNeedsCrew#_whichSide) isEqualTo []) then {
                private _statics = ITW_AtkStaticNeedsCrew#_whichSide;
                ITW_AtkStaticNeedsCrew set [_whichSide,[]];
                private _units = [];
                {
                    private _veh = _x;
                    private _group = createGroup [_side,false];         
                    for "_i" from 1 to (_veh emptyPositions "") do {               
                        private _unit = [_group,_unitTypes,_homeSpawnPt,true] call ITW_AtkUnitToGroup; 
                        _unit moveInAny _veh;
                        _units pushBack _unit;
                    };
                    _group deleteGroupWhenEmpty true;
                    [_group,[],false] call ITW_AtkAddInfantryGroup;
                    if (_side == ITW_PlayerSide) then {{_x hcSetGroup [_group]} forEach ITW_HcCmdr};
                    YIELD_CPU;
                } forEach _statics;
                if !(_units isEqualTo []) then { { _x addCuratorEditableObjects [_units, true]; } forEach allCurators };
            };
            
            private _maxAiCount = _isFriendly call ITW_AtkAiCount;
            if (_zoneLimtedCount > 0) then {
                _maxAiCount = _maxAiCount * (1.05 + (0.05*(floor (_zoneLimtedCount/3)))); // 20% extra units when weakest, 15% in middle, and 10% extra when just 1 level is limited
            };
            private _activeAiCnt = {alive _x} count (units _side);
            private _spawnRate = if (time < 300 || (time < _defendPushTime)) then {_spawnRateFast} else {_spawnRateSlow};
            private _maxAiRightNow = _maxAiCount min (_activeAiCnt + _spawnRate);
            // ensure we can populate the owned objectives with one squad each right at the start
            if (_populateObjectives && {_maxAiRightNow > 0}) then {_maxAiRightNow = _maxAiCount max (_activeAiCnt + (_populateSquadCnt * _ownedObjCnt*AI_SQUAD_SIZE))};
            
            private _newSquads = []; // this array shrinks as units get assigned
            private _newUnits = [];  // this array is the full list even after assignment
            if (_activeAiCnt + _spawnTrigger < _maxAiRightNow || {random 10 < 1 || {!(ITW_AtkPlayersJoinWave isEqualTo [])}}) then {
                if (!(ITW_AtkPlayersJoinWave isEqualTo [])) then {_maxAiRightNow = _maxAiRightNow max (_activeAiCnt + 4)};
                
                //// Infantry AI Spawner ////
                private _squad = [];
                while {_activeAiCnt < _maxAiRightNow} do {
                   _spawnPos = [_homeSpawnPt,0,25,1,0,0,0,[],[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
                    if (count _spawnPos < 3) then {_spawnPos pushBack 0} else {_spawnPos = _homeSpawnPt};
    
                    private _newSquad = false;
                    if (_squad isEqualTo []) then {
                        _newSquad = true;
                        if (_squadTypes isNotEqualTo []) then {
                            _squad = +(selectRandom _squadTypes);
                        } else {
                            for "_i" from 1 to AI_SQUAD_SIZE do {_squad pushBack selectRandom _unitTypes};
                        };
                    
                        // extra missile specialists?
                        if (ITW_ParamExtraLaunchers > 0 && {!(_missleTypes isEqualTo [])}) then {
                            private _mtypes = _missleTypes arrayIntersect _squad;
                            if (_mtypes isNotEqualTo []) then {
                                private _chance = if (ITW_ParamExtraLaunchers == 2) then {100/*lots percentage*/} else {50/*few percentage*/};
                                if (random 100 < _chance) then {
                                    _squad insert [1,_missleTypes];
                                };
                            };
                        };
                    };
   
                    if (isNull _spawnGroup) then {
                        _spawnGroup = createGroup [_side,false];
                        _spawnGroup setVariable ["noHeadless",true];
                        _spawnGroup setVariable ["itwInitGrp",true,true]; // block this group from being transported
                    };
                    
                    private _unit = [_spawnGroup,[_squad deleteAt 0],_spawnPos,false] call ITW_AtkUnitToGroup;                
                    if !(isNull _unit) then {
                        if (_newSquad) then {
                            _newSquads pushBack [_unit];
                        } else {
                            _newSquads#-1 pushBack _unit;
                        };
                        _activeAiCnt = _activeAiCnt + 1;
                    };
                    YIELD_CPU;
                };
                _newUnits = flatten _newSquads;
                if !(_newSquads isEqualTo []) then {{_x addCuratorEditableObjects [_newUnits, true]} forEach allCurators};

                //// Delivery Troops ////
                private _deliverySquads = if (_isFriendly) then {ITW_ParamFriendlySquadDelivery} else {0};
                if (_deliverySquads > 0) then {
                    //  hold back some squads for delivery to the AOs by players
                    private _currentDeliverySquads = 0;
                    {_currentDeliverySquads = _currentDeliverySquads + 1} forEach (groups _side select {_x getVariable ["itwDelivery",false]});
                    if (_currentDeliverySquads < _deliverySquads && {!(_newSquads isEqualTo [])}) then {
                        private _units = _newSquads deleteAt 0;
                        {ALLOW_DAMAGE(_x,true)} forEach _units; // do this before they leave the spawngroup since it's protected from headlessClient control
                        private _grp = createGroup [_side,false]; 
                        _units joinSilent _grp;
                        _grp deleteGroupWhenEmpty true;
                        [_grp] call ITW_AtkAddInfantryGroup;
                        [_grp] call _fnGroupsCallback;
                        [_grp] call ITW_AllyDelivery;
                    };
                    YIELD_CPU;
                };
                
                //// Populate Zones ////
                if (_populateObjectives) then {
                    for "_i" from 1 to _populateSquadCnt do {
                        {
                            private _objIdx = _x;
                            private _obj = ITW_Objectives#_objIdx;
                            if (_objIdx call ITW_ObjContestedOwnerIsFriendly == _isFriendly) then {
                                // assign to groups
                                private _units = _newSquads deleteAt 0;
                                {ALLOW_DAMAGE(_x,true)} forEach _units; // do this before they leave the spawngroup since it's protected from headlessCLient control
                                private _group = createGroup [_side,false];
                                _units joinSilent _group;
                                _group deleteGroupWhenEmpty true;
                                // send units on their way
                                [_group,_obj] call ITW_AtkAddInfantryGroup;
                                [_group] call _fnGroupsCallback;
                                VAR_SET_OBJ_IDX(_group,_objIdx);
                                ITW_DELETE_WAYPOINTS(_group);
                            };
                            YIELD_CPU;
                        } forEach _objectiveIds;
                    };
                };
            };

            //// Spawn Vehicles ////
            private _vehInfos = [_attackVeh,_transport,_dualVeh,_homeVehSpawnPt,_newSquads,_crewTypes,_unitTypes,_side,_populateObjectives] call ITW_AtkVehicleSpawner;
            if !(_vehInfos isEqualTo []) then {
                _vehInfos apply {
                    [_x#VEHINFO_CREW_GRP] call _fnGroupsCallback;
                    {
                        [_x] call _fnGroupsCallback;
                        if (_x call ITW_AtkAutoCombatDisabled) then {
                            {_x disableAI "AUTOCOMBAT"} forEach (units _x);
                        };
                    } forEach (_x#VEHINFO_CARGO_GRPS);
                };
                ATK_DEBUG("Veh Spawned: isFriendly, count",_isFriendly,count _vehInfos);                 
                YIELD_CPU;
            }; 
            _populateObjectives = false;
            
            //// On Foot Units ////
            while {!(_newSquads isEqualTo [])} do {
                // assign to groups
                private _units = _newSquads deleteAt 0;
                private _group = createGroup [_side,false];    
                _units joinSilent _group;
                _group deleteGroupWhenEmpty true;
                // send units on their way
                [_group] call ITW_AtkAddInfantryGroup;
                [_group] call _fnGroupsCallback;
                if (_group call ITW_AtkAutoCombatDisabled) then {
                    {_x disableAI "AUTOCOMBAT"} forEach _units;
                };
            };
            YIELD_CPU;
            
            {ALLOW_DAMAGE(_x,true)} forEach _newUnits;
            
            //// Sleep ////
            private _delaySec = if (_isFriendly) then {
                ((ITW_ParamSpawnDelay/2) + random ITW_ParamSpawnDelay); // total sleep time desired
            } else {
                ((ITW_ParamSpawnDelayEnemy/2) + random ITW_ParamSpawnDelayEnemy); // total sleep time desired
            };
            if (time < _defendPushTime && {_delaySec > 120}) then {_delaySec = 120}; // during defend push, spawn more often
            if (_isFriendly) then {ITW_atkFriendlyAtkTime = time + _delaySec; publicVariable "ITW_atkFriendlyAtkTime"}; // used at officer to know how long until next firendly wave
            
            private _sleepStep = 10; // seconds between checks
            private _startTime = time;
            for "_i" from 1 to _delaySec step _sleepStep do {
                sleep _sleepStep;
                if (_zoneIndex != ITW_AllyIndex) exitWith {}; // wake up and process new guys if zone changed
                if (ITW_defendRunning && {!_inDefendPhase}) exitWith {};
            };
            _delaySec = time - _startTime; // actual delay we slept
            while {LV_PAUSE} do {sleep 5};
            
            //// Scaling Difficulty Mode ////
            private _enemyScale = 1;
            private "_numOwnedEnemy";
            // enemy tickets per cycle can be reduced when they own fewer objectives
            while {ITW_ObjZonesUpdating} do {sleep 0.5};
            private _numOwnedEnemy    = {ITW_Objectives#_x#ITW_OBJ_OWNER == ITW_OWNER_ENEMY   } count _objectiveIds;
            private _numOwnedFriendly = {ITW_Objectives#_x#ITW_OBJ_OWNER == ITW_OWNER_FRIENDLY} count _objectiveIds;
            if (_numOwnedFriendly>_numOwnedEnemy && {_numOwnedEnemy > 0}) then {
                _enemyScale = 1 - (0.20/_numOwnedEnemy);
            };
            
            //// Defend Phase ////
            if (ITW_defendRunning && {!_inDefendPhase}) then {
                // defend phase has begun
                _inDefendPhase = true;
                if (!_isFriendly) then {
                    _defendPushTime = time + (ITW_ParamDefendPhaseDuration/2); //if time < _defendPushTime then we're ramping up spawn rate and doubling the delay between spawns
                    
                    // ramp up max number of vehicles allowed
                    private _addedMaxVeh = [0,1,1,1,2,2,2,2,3,3,3] select ITW_ParamDefendPhaseIntensity;
                    {
                        private _prevMax = _x#ITW_VEH_MAX;
                        _x set [ITW_VEH_MAX,_prevMax max (_prevMax + _addedMaxVeh)]; 
                        _prevMax
                    } forEach _vehArray;
                    
                    // ramp up tickets //
                    // boost is percent multiplied to ticket increment that is added every cycle until push time is up
                    _defendModeBoost =  1 + 0.25 * ITW_ParamDefendPhaseIntensity;
                    
                    // delaySec gives a one time boost
                    diag_log format ["Defend phase: Delay boost (sec): %1 ==> %2  Ticket boost (%): %3",round (_delaySec),round (_delaySec + (ITW_ParamDefendPhaseIntensity * 16) + ITW_ParamDefendPhaseDelay),_defendModeBoost];
                    _delaySec = _delaySec + (ITW_ParamDefendPhaseIntensity * 16) + ITW_ParamDefendPhaseDelay; // (ITW_ParamDefendPhaseIntensity * X min * 60 sec/min)
                  
                };  
                // zone start vehicle boost
                if (ITW_ParamDefendVehBoost > 0) then {
                    {
                        private _vehDef = _x;
                        private _reqTickets = _vehDef#ITW_VEH_REQD_TICKETS;
                        private _curTickets = _vehDef#ITW_VEH_CURR_TICKETS;
                        _vehDef set [ITW_VEH_CURR_TICKETS,_curTickets + (_reqTickets * ([0,0.4,0.8,1.2] select ITW_ParamDefendVehBoost))];
                    } forEach _vehArray; 
                };
            } else {
                if (!ITW_defendRunning && _inDefendPhase) then {
                    // defend phase has eneded
                    _inDefendPhase = false;
                    if (!_isFriendly) then {
                        {
                            _x set [ITW_VEH_MAX,_defendPrevVehMax#_forEachIndex];
                        } forEach _vehArray;
                        _defendPushTime = 0;
                        _defendModeBoost =  1;
                    };
                };
            };
            
            
            //// Tickets ////
            if (ITW_ParamVehicleSpawnAdjustment != _prevVehSideAdj) then {
                _prevVehSideAdj = ITW_ParamVehicleSpawnAdjustment;
                // tickets & max number are adjusted based on the vehicle spawn rate adjust param as well, tickets also based on the number of ai param
                _ticketsBase = (ITW_ParamVehicleSpawnAdjustment) * ((ITW_ParamEnemyAiCnt+70)/100) * (TICKETS_PER_MIN/60);
                if (_isFriendly) then {_ticketsBase = _ticketsBase * ITW_ParamVehicleSideAdjustment};
                diag_log ("ITW: Ticket base per min : " + str (round (_ticketsBase*6000)/100) + " " + (if (_isFriendly) then {"friendly"} else {"enemy"}));
                _ticketsBasePlaneAttack = (ITW_ParamAttackPlaneSpawnAdjustment) * _ticketsBase;
                _ticketsBaseHeliAttack  = (ITW_ParamAttackHeliSpawnAdjustment) * _ticketsBase;
                _ticketsBaseTankAttack  = (ITW_ParamAttackTankSpawnAdjustment) * _ticketsBase;
                _ticketsBaseApcAttack   = (ITW_ParamAttackApcSpawnAdjustment) * _ticketsBase;
                _ticketsBaseCarAttack   = (ITW_ParamAttackCarSpawnAdjustment) * _ticketsBase;
                _ticketsBaseShipAttack  = (ITW_ParamAttackShipSpawnAdjustment) * _ticketsBase;
                
                _ticketsBasePlaneTransport = (ITW_ParamTransportPlaneSpawnAdjustment) * _ticketsBase;
                _ticketsBaseHeliTransport  = (ITW_ParamTransportHeliSpawnAdjustment) * _ticketsBase;
                _ticketsBaseTankTransport  = (ITW_ParamTransportTankSpawnAdjustment) * _ticketsBase;
                _ticketsBaseApcTransport   = (ITW_ParamTransportApcSpawnAdjustment) * _ticketsBase;
                _ticketsBaseCarTransport   = (ITW_ParamTransportCarSpawnAdjustment) * _ticketsBase;
                _ticketsBaseShipTransport  = (ITW_ParamTransportShipSpawnAdjustment) * _ticketsBase;
            };
            
            private _sideOpsAdvantage = if (_isFriendly) then {1 + ((["VEH"] call ITW_SideOpsAdvantage)/20)} else {1}; // intensity 1:5% increase, 5:25% increase 10:50% increase in ticket rate per sideOp
            
            // add tickets for this loop
            ITW_TICKET_SEM_CHECK;
            {
                private _vehDef = _x;
                // only increment if under the max vehicles are currently in action
                if (_vehDef#ITW_VEH_ZONES_OWNED <= _zonesOwned && {_vehDef#ITW_VEH_COUNT < (_vehDef#ITW_VEH_MAX)}) then {
                    private _scale = if (_vehDef#ITW_VEH_IS_FRIENDLY) then {1} else {_enemyScale};
                    private _role = _x#ITW_VEH_ROLE;
                    private _type = _x#ITW_VEH_TYPE;
                    private _tickets = _ticketsBase;
                    if (_type == ITW_TYPE_VEH_AIRPLANE && !_ownsAirport) then {continue};
                    if (_role ==ITW_VEH_ROLE_TRANSPORT) then {
                        _tickets = switch (_type) do {
                            case ITW_TYPE_VEH_AIRPLANE: {_ticketsBasePlaneTransport};
                            case ITW_TYPE_VEH_HELI:     {_ticketsBaseHeliTransport};
                            case ITW_TYPE_VEH_TANK:     {_ticketsBaseTankTransport};
                            case ITW_TYPE_VEH_APC:      {_ticketsBaseApcTransport};
                            case ITW_TYPE_VEH_CAR:      {_ticketsBaseCarTransport};
                            case ITW_TYPE_VEH_SHIP:     {_ticketsBaseShipTransport};
                            default {_ticketsBase};
                        };
                    } else {
                        _tickets = switch (_type) do {
                            case ITW_TYPE_VEH_AIRPLANE: {_ticketsBasePlaneAttack};
                            case ITW_TYPE_VEH_HELI:     {_ticketsBaseHeliAttack};
                            case ITW_TYPE_VEH_TANK:     {_ticketsBaseTankAttack};
                            case ITW_TYPE_VEH_APC:      {_ticketsBaseApcAttack};
                            case ITW_TYPE_VEH_CAR:      {_ticketsBaseCarAttack};
                            case ITW_TYPE_VEH_SHIP:     {_ticketsBaseShipAttack};
                            default {_ticketsBase};
                        };
                    };
                    // give enemy a boost if zone advanced so they have vehicles to spawn into the new objectives
                    private _boost = if (!_isFriendly && {_zoneIndex != ITW_ZoneIndex && {ITW_VEH_IS_LAND(_type)}}) then {0.3 * (_vehDef#ITW_VEH_REQD_TICKETS)} else {0};
                    private _increment = (_scale * _tickets * _delaySec * _sideOpsAdvantage) + _boost;
                    //if (!_isFriendly) then {diag_log ["ATKVEH Increment",_type,_role," ",_increment,_defendModeBoost * _increment," ",round (_vehDef#ITW_VEH_CURR_TICKETS),round ((_vehDef#ITW_VEH_CURR_TICKETS) + _increment)]};
                    if (time < _defendPushTime) then {_increment = _increment * _defendModeBoost}; // during defend push, enemy earns tickets faster
                    _vehDef set [ITW_VEH_CURR_TICKETS,(_vehDef#ITW_VEH_CURR_TICKETS) + _increment]};
            } forEach _vehArray;
            //if (!_isFriendly) then {{diag_log ["ATKVEH",_inDefendPhase," ",_x#ITW_VEH_TYPE,_x#ITW_VEH_ROLE," ",_x#ITW_VEH_REQD_TICKETS,round(_x#ITW_VEH_CURR_TICKETS)," ",floor(_x#ITW_VEH_MAX),_x#ITW_VEH_COUNT]} forEach _vehArray};
            YIELD_CPU;
        };
    };
};

ITW_AtkAiCount = {    
    private _isFriendly = _this;
    if (!_isFriendly) exitWith {
        if (ITW_defendRunning) then {
            ITW_ParamEnemyAiCnt * (0.0222 * ITW_ParamDefendPhaseIntensity + 1.0778); // scale 1 to 10 to 1.1 to 1.3
        } else {
            ITW_ParamEnemyAiCnt
        };
    };
    
    
    private _fnUupdateCnts = { 
        private _numPlayers = count call BIS_fnc_listPlayers;
        private _maxUnits = (ITW_ParamEnemyAiCnt * (1+ITW_ParamFriendlyAiCntAdjustment/10) - (_numPlayers * 2));
        
        private _sideOpsAdvantage = ["AI"] call ITW_SideOpsAdvantage;
        if (_sideOpsAdvantage > 0) then {
            private _extraUnits = 1 max (_maxUnits * _sideOpsAdvantage / 100); // Intensity:  1:1% more troops  5:5%   10: 10% per sideOp (min 1)
            _maxUnits = _maxUnits + _extraUnits;
        };
        
        ITW_MaxFriendlyUnits = round _maxUnits;
        ITW_PrevFriendlyAiCntAdjustment = ITW_ParamFriendlyAiCntAdjustment;
    };
    if (isNil "ITW_PrevPlayerCnt") then {ITW_PrevPlayerCnt = -1};
    if (ITW_PrevPlayerCnt != count call BIS_fnc_listPlayers) then {call _fnUupdateCnts};
    if (ITW_PrevFriendlyAiCntAdjustment != ITW_ParamFriendlyAiCntAdjustment) then {call _fnUupdateCnts};
    ITW_MaxFriendlyUnits
};

ITW_AtkAutoCombatDisabled = {
    // returns true if the unit/group's auto-combat should be disabled and waypoints should be "AWARE"
    params ["_unitOrGroup"];
    private _side = side _unitOrGroup;
    
    // if defend phase is active and intensity is greater than 3, have enemy use combat disable mode
    if (ITW_defendRunning && {_side != ITW_PlayerSide && {ITW_ParamDefendPhaseIntensity > 3}}) exitWith {true};
    
    private _disabled = 
        switch (ITW_ParamAutoCombatDisable) do {
            case 0: {false};
            case 1: {true};
            case 2: {_side == ITW_PlayerSide};
            case 3: {_side != ITW_PlayerSide};
        };
    _disabled
};

ITW_AtkUnitCreateSem = false;
ITW_AtkUnitToGroup = {
    params ["_grp","_unitTypes","_aiSpawnPt",["_allowDamage",true]];
    if (!isServer) exitWith {diag_log "Error Pos: ITW_AtkUnitToGroup called on client not server";objNull};
    if (isNull _grp) exitWith {diag_log "Error Pos: ITW_AtkUnitToGroup called with a null group at start";objNull};
    private _fnStartTime = time;
    private _skill = if (GRP_IS_FRIENDLY(_grp)) then {ITW_ParamFriendlySquadSkill} else {ITW_ParamDifficulty};
    private _hasWeapon = false;
    private _unit = objNull;
    private _cnt = 5;
    private _isZombies = side _grp != ITW_PlayerSide && {"WBK_AI_ZHAMBIES" in ITW_EnemyFaction};
    while {!_hasWeapon} do {    
        private _unitType = toLowerANSI selectRandom _unitTypes;
        if (_isZombies) then {
            private _specialZombieCnt = 10;
            while {_specialZombieCnt > 0} do {
                _specialZombieCnt = _specialZombieCnt - 1;
                if (_unitType in ["wbk_goliaph_3","wbk_specialzombie_smasher_3","wbk_specialzombie_smasher_hellbeast_3","wbk_specialzombie_smasher_acid_3"] && {random 100 > 10}) then {_unitType = selectRandom _unitTypes;continue};
                if (_unitType in ["zombie_special_opfor_boomer","wbk_specialzombie_corrupted_3","zombie_special_opfor_leaper_1","zombie_special_opfor_leaper_2","zombie_special_opfor_screamer"] && {random 100 > 25}) then {_unitType = selectRandom _unitTypes;continue};
                _specialZombieCnt = 0;
            };
        };
        private _atkUnit = nil; 
        private _timeout = time + 15;       
        SEM_LOCK(ITW_AtkUnitCreateSem);
        if (isNull _grp) exitWith {diag_log ("Error Pos: ITW_AtkUnitToGroup called with a null group at "+str(time - _fnStartTime)+" sec");_unit = objNull;SEM_UNLOCK(ITW_AtkUnitCreateSem)};
        private _startTime = time;
        ItwAtkUnitCreated = nil;      
        _unitType createUnit [_aiSpawnPt, _grp, "ItwAtkUnitCreated = this"];
        waitUntil {sleep 0.05;!isNil "ItwAtkUnitCreated" || time > _timeout};
        _unit = if (!isNil "ItwAtkUnitCreated") then {ItwAtkUnitCreated} else {objNull};
        SEM_UNLOCK(ITW_AtkUnitCreateSem);
        if (isNull _unit) then {
            diag_log format ["Error Pos: ITW_AtkUnitToGroup: unit not created (%1 grpSize:%2 grp:%3 totalGroups:%4,%5)",_unitType,count units _grp,_grp,count groups west,count groups east + (count groups independent)] ;
            continue;
        } else {
            if (time - _startTime > 2) then {diag_log format ["Warning/Error Pos: Unit created too slowly: %1 sec",time - _startTime]};
        };
        _cnt = _cnt - 1;
        if (toUpperANSI (faction _unit) in WEAPONLESS_FACTIONS) exitWith {_hasWeapon = true};
        // don't allow weaponized backpacks
        if (backpack _unit isKindOf "Weapon_Bag_Base") then {
            removeBackpack _unit;
        };
        // if unit has no weapon, then change his loadout
        if (primaryWeapon _unit isEqualTo "") then {
            if (_cnt > 0 && {!(_unit isKindOf "WBK_C_ExportClass")}) then {
                deleteVehicle _unit;
                _unit = nil;  
            } else {
                if (handgunWeapon _unit isEqualTo "") then {
                    _unit addMagazines ["10Rnd_9x21_Mag",10];
                    _unit addWeapon "hgun_Pistol_01_F";
                };
                _hasWeapon = true;
            };
        } else {
            _hasWeapon = true;
        };
    };
    if (isNull _unit) exitWith {_unit};
    
    // ensure unit has first aid and some ammo
    private _FAK = "FirstAidKit";
    {
        private _type = getNumber (configFile >> "cfgWeapons" >> _x >> "iteminfo" >> "type");
        if (_type == 401) exitWith {_FAK = _x};
    } forEach items _unit;
    private _count = 6;
    while {_count > 0 && _unit canAdd _FAK} do {
        _count = _count - 1;
        _unit addItem _FAK;
    };
    private _ammo = primaryWeaponMagazine _unit;
    if !(_ammo isEqualTo []) then {
        _ammo = _ammo#0;
        _count = 6;
        while {_count > 0 && _unit canAdd _ammo} do {
            _count = _count - 1;
            _unit addItem _ammo;
        };
    };
    // PiR: add medical items
    if (isClass (configFile >> "CfgPatches" >> "pir")) then {
        (uniformContainer _unit) addItemCargoGlobal ["PiR_bint",2];
        if (_unit getUnitTrait "Medic") then {(uniformContainer _unit) addItemCargoGlobal ["PiR_apteka",1]};
    };
    // ACE: add medical items
    #if __has_include("\z\ace\addons\main\script_component.hpp")
        (uniformContainer _unit) addItemCargoGlobal ["ACE_fieldDressing",1];
        (uniformContainer _unit) addItemCargoGlobal ["ACE_plasmaIV",1];
    #endif  
    
    ALLOW_DAMAGE(_unit,_allowDamage);
    _unit setSkill _skill;
    _unit setSkill ["courage",1]; 
    _unit setVariable ["ITW_loadout",getUnitLoadout _unit];
    [_unit,true,true] call ITW_FncInfiniteAmmo;
    _unit
};

ITW_AtkVehicleSpawner = {
    params ["_vehsAttack","_vehsTransport","_vehsDual","_spawnPt","_newSquads","_crewTypes","_unitTypes","_side","_populateObjectives"];
    // _vehInfos array is returned: array of vehicles added [[_type,_veh,_crewGroup,_cargoGroups]],...] or [] if no vehs added
    // _vehsAttack are attack and dual purpose, _vehsTransport are transport and dual
    private _debug = false;
    private _vehInfos = []; 
    private _newObjects = [];
    
    private _ticketCheckFn = {
        params ["_vehArray","_shipsAllowed","_adjForPreference"];
        private _resultArray = _vehArray select {(_x select ITW_VEH_REQD_TICKETS) <= (_x select ITW_VEH_CURR_TICKETS) && {_x select ITW_VEH_ROLE == ITW_VEH_ROLE_TRANSPORT || {_x select ITW_VEH_COUNT < (_x select ITW_VEH_MAX)}}};
        if (!_shipsAllowed) then {_resultArray select {(_x select ITW_VEH_TYPE) != ITW_TYPE_VEH_SHIP}};
        if (_adjForPreference && {ITW_ParamVehicleAirLandBalance != 0}) then {
            // bias how many air vs land vehicles
            private _extraVehicles = [];
            if (ITW_ParamVehicleAirLandBalance < 0) then { // air
                _extraVehicles = _resultArray select {(_x select ITW_VEH_TYPE) <= ITW_TYPE_VEH_AIR_MAX};
            } else { // land
                _extraVehicles = _resultArray select {(_x select ITW_VEH_TYPE) > ITW_TYPE_VEH_AIR_MAX};
            };
            _extraVehicles = _extraVehicles + _extraVehicles + _extraVehicles; // 4x more likely than before
            if (abs ITW_ParamVehicleAirLandBalance > 1) then {_extraVehicles = _extraVehicles + _extraVehicles}; // 9x more likely
            _resultArray = _resultArray + _extraVehicles;
        };
        _resultArray
    };
    
    private _fillCargoFn = {
        private _cargoGroups = [];
        private _vehSpace = _veh emptyPositions "";
        private _playersJoinWaveNeedsPV = false;
        while {_vehSpace > 0} do {
            // allow players to join in on the infantry attack
            if (_side == ITW_PlayerSide && {ITW_AtkPlayersJoinWave isNotEqualTo []}) then {
                private _player = ITW_AtkPlayersJoinWave#0;
                private _teammates = [];
                if (leader _player == _player) then {
                    _teammates = units group _player select {_x != _player && {vehicle _x == _x && {_x distance _player < 200}}};
                };
                _player moveInAny _veh;
                [false,true] remoteExec ["ITW_AtkJoinWaveUI",_player];
                ITW_AtkPlayersJoinWave deleteAt 0;
                _playersJoinWaveNeedsPV = true;
                _vehSpace = _vehSpace - 1;
                private _overflow = [];
                {
                    private _unit = _x;
                    private _success = _unit moveInAny _veh;
                    if (_success) then {
                        _vehSpace = _vehSpace - 1;
                    } else {
                        _overflow pushBack _unit;
                    };
                } forEach _teammates;
                if (_overflow isNotEqualTo []) then {ITW_AtkTeammatesJoinWave pushBack [_player,_overflow]};
                _cargoGroups pushback grpNull;
                continue;
            };
            
            private _squad = [];
            if (_newSquads isNotEqualTo []) then {
                private _bestSquadIdx = -1; // index of largest squad that fits in this vehicle
                private _maxSquadIdx = -1;  // index of the largest squad
                private _maxCount = 0;
                private _bestCount = 0;
                {
                    private _currentCount = count _x;
                    if (_currentCount <= _vehSpace && {_currentCount > _bestCount}) then {
                        _bestSquadIdx = _forEachIndex;
                        _bestCount = _currentCount;
                    };
                    if (_currentCount > _maxCount) then {
                        _maxSquadIdx = _forEachIndex;
                        _maxCount = _currentCount;
                    };
                } forEach _newSquads;
                if (_bestSquadIdx >= 0) then {_squad = _newSquads deleteAt _bestSquadIdx};
                if (_squad isEqualTo []) then {
                    // no squad fit, we need to split up a squad
                    private _splitSquad = _newSquads#_maxSquadIdx;
                    _squad = _splitSquad select [0,_vehSpace];
                    _splitSquad deleteRange [0,_vehSpace];
                };
            };
            if (_squad isEqualTo []) exitWith {};
            
            private _cargoGroup = createGroup [_side,false];
            _squad joinSilent _cargoGroup;
            _cargoGroups pushback _cargoGroup;
            _squad apply {_x moveInAny _veh};
            _vehSpace = _vehSpace - count _squad;
        };
        if (_playersJoinWaveNeedsPV) then {publicVariable "ITW_AtkPlayersJoinWave"};
        if (_cargoGroups isNotEqualTo []) then {
            // don't allow units to take damage from friendly vehicles for a while after unloading
            private _hcIDs = allPlayers select {_x isKindOf "HeadlessClient_F"} apply {owner _x};
            _hcIDs pushBack 2;
            [_veh] remoteExec ["ITW_AtkUnloadProtect",_hcIDs]; // run on server and all headless clients since we don't know which will own vehicle when they unload
        };
        _cargoGroups
    };
            
    private _contestedObjIndexes = ITW_Zones#ITW_ZoneIndex;
    private _shipsAllowed = {count (ITW_SeaPoints#_x) >= 0} count _contestedObjIndexes > 0;

    // in Defend Phase, we may need to block ships
    if (ITW_defendPhaseObjIdx > 0) then {_shipsAllowed = count (ITW_SeaPoints#ITW_defendPhaseObjIdx) >= 0};
    
    // attack vehicles
    if !(_vehsAttack isEqualTo []) then {
        ITW_TICKET_SEM_CHECK;
        _usingDual = false;
        private _vehAttackTrimmed = [];
        if (_vehAttackTrimmed isEqualTo []) then {
            _vehAttackTrimmed = [_vehsAttack,_shipsAllowed,false] call _ticketCheckFn;
            if (_vehAttackTrimmed isEqualTo []) then {
                _vehAttackTrimmed = [_vehsDual,_shipsAllowed,false] call _ticketCheckFn;
                _usingDual = true;
            };
        };
        if (_populateObjectives) then {
            private _isFriendly = _side == ITW_PlayerSide;
            private _count = floor (2.5 * ITW_ParamVehicleSpawnAdjustment + 0.3) * ({_x call ITW_ObjContestedOwnerIsFriendly == _isFriendly} count _contestedObjIndexes);
            _count = _count + ITW_ParamVehBoostZone;
            private _groundVehs = _vehsAttack select {_x#ITW_VEH_ROLE in [ITW_VEH_ROLE_ATTACK,ITW_VEH_ROLE_DUAL] 
                                                     && {_x#ITW_VEH_TYPE in [ITW_TYPE_VEH_TANK,ITW_TYPE_VEH_APC,ITW_TYPE_VEH_CAR]}};
            if (_groundVehs isNotEqualTo []) then {
                if (_debug) then {diag_log format ["AT:Populating obj veh count %1",_count]}; 
                while {count _vehAttackTrimmed < _count} do {
                    _vehAttackTrimmed pushBack (selectRandom _groundVehs);
                };
            };
        };
        if (_debug) then {
            diag_log format ["AT:ATTACKS %1 #@2",_side,count _vehAttackTrimmed];
            {diag_log format ["AT: %1",_x]} forEach _vehAttackTrimmed;diag_log "AT:----";
        };  
        private _loopCnt = 20;
        while {!(_vehAttackTrimmed isEqualTo []) && {_loopCnt > 0}} do {
            _loopCnt = _loopCnt - 1;
            private _vehDef = if (_populateObjectives) then {
                // do this two different ways to optimize for performance since this way changes the array but is less commonly called
                private _randomIndex = floor random count _vehAttackTrimmed;
                _vehAttackTrimmed deleteAt _randomIndex
            } else {
                selectRandom _vehAttackTrimmed
            };
            _veh = [_vehDef,_crewTypes,_unitTypes,_side,_spawnPt] call ITW_AtkSpawnVeh;
            if (_debug) then {diag_log format ["AT:Aspawned %1 %2",_side,gettext (configfile >> "cfgvehicles" >> typeof _veh >> "displayname")]}; 
            if (!isNull _veh) then {
                private _crew = crew _veh;
                private _crewGroup = if (_crew isEqualTo []) then {createGroup [_side,false]} else {group (crew _veh # 0)};
                private _cargoGroups = [];
                // if is dual role, add cargo
                if (_vehDef#ITW_VEH_ROLE == ITW_VEH_ROLE_DUAL && {ITW_TransportTypesAllowedHashmap getOrDefault [_vehDef#ITW_VEH_TYPE,false] && {_newSquads isNotEqualTo []}}) then {
                    _cargoGroups = [_veh,_side,_newSquads] call _fillCargoFn;
                }; 
                
                private _vehInfo = [_vehDef#ITW_VEH_TYPE,_vehDef#ITW_VEH_ROLE,_veh,_crewGroup,_cargoGroups,getPosATL _veh];
                [_vehInfo,_populateObjectives] call ITW_AtkAddVehicle; // place vehicle and send on it's way
                _vehInfos pushBack _vehInfo;
                _newObjects pushBack _veh;
                _newObjects = _newObjects + units _crewGroup;
                
                // if we're populating objectives, then the vehicles are free :-)
                if (_populateObjectives) then {
                    _veh setVariable ["ITW_VehDef",_vehDef];
                } else {
                    // keep track of how many of this type is in the battle
                    ITW_TICKET_SEM_CHECK;
                    ITW_VEH_COUNT_INCR(_vehDef); 
                    _veh setVariable ["ITW_VehDef",_vehDef];
                    
                    // pay ticket price and update the vehicles available
                    ITW_TICKET_SEM_CHECK;
                    ITW_TICKET_REDUCE(_vehDef);
                    _vehAttackTrimmed = [_vehAttackTrimmed,_shipsAllowed,false] call _ticketCheckFn;
                    if (!_usingDual && {_vehAttackTrimmed isEqualTo []}) then {
                        _vehAttackTrimmed = [_vehsDual,_shipsAllowed,true] call _ticketCheckFn;
                        _usingDual = true;
                    };
                };
                
                sleep 2; // give vehicles chance to get placed 
                while {LV_PAUSE} do {sleep 5};
                _vehInfo set [VEHINFO_FROM_POS,getPosATL _veh]; // do this after vehicle has had a chance to get placed
                
                _crewGroup deleteGroupWhenEmpty true;
                {_x deleteGroupWhenEmpty true} forEach _cargoGroups;
            };
        };
    };
    
    // transports 
    if !(_vehsTransport isEqualTo []) then {
        ITW_TICKET_SEM_CHECK;
        private _usingDual = true;
        private _vehTranspTrimmed = [_vehsDual,_shipsAllowed,true] call _ticketCheckFn;
        if (_vehTranspTrimmed isEqualTo []) then {
            _vehTranspTrimmed = [_vehsTransport,_shipsAllowed,true] call _ticketCheckFn;
            _usingDual = false;
        };
        if (_debug) then {diag_log format["AT:TRANSPORT %1",_side];{diag_log format ["AT: %1",_x]} forEach _vehTranspTrimmed;diag_log "AT:----"};
        private _loopCnt = 50;
        while {!(_vehTranspTrimmed isEqualTo []) && {_newSquads isNotEqualTo [] && {_loopCnt > 0}}} do {
            _loopCnt = _loopCnt - 1;
            private _vehDef = selectRandom _vehTranspTrimmed;       
            _veh = [_vehDef,_crewTypes,_unitTypes,_side,_spawnPt] call ITW_AtkSpawnVeh;
            if (_debug) then {diag_log format["AT:Tspawned %1 %2",_side,gettext (configfile >> "cfgvehicles" >> typeof _veh >> "displayname")]};            
            if (!isNulL _veh) then { 
                // put units into cargo
                private _cargoGroups = [_veh,_side,_newSquads] call _fillCargoFn;
                private _crewGroup = group driver _veh;
                
                private _vehInfo = [_vehDef#ITW_VEH_TYPE,_vehDef#ITW_VEH_ROLE,_veh,_crewGroup,_cargoGroups,getPosATL _veh,_vehDef#ITW_VEH_IS_DUAL_AS_TRANSPORT];
                [_vehInfo,false] call ITW_AtkAddVehicle; // place vehicle and send on it's way
                _vehInfos pushBack _vehInfo;
                _newObjects pushBack _veh;
                _newObjects = _newObjects + units _crewGroup;
                
                // keep track of how many of this type is in the battle
                ITW_TICKET_SEM_CHECK;
                ITW_VEH_COUNT_INCR(_vehDef); 
                _veh setVariable ["ITW_VehDef",_vehDef];
                    
                // pay ticket price and update the vehicles available
                ITW_TICKET_SEM_CHECK;
                ITW_TICKET_REDUCE(_vehDef);
                _vehTranspTrimmed = [_vehTranspTrimmed,_shipsAllowed,false] call _ticketCheckFn;
                if (_usingDual && {_vehTranspTrimmed isEqualTo []}) then {
                    _vehTranspTrimmed = [_vehsTransport,_shipsAllowed,true] call _ticketCheckFn;
                    _usingDual = false;
                };
                sleep 1; // give vehicles chance to get placed 
                while {LV_PAUSE} do {sleep 5};  
                _vehInfo set [VEHINFO_FROM_POS,getPosATL _veh]; // do this after vehicle has had a chance to get placed              
                _crewGroup deleteGroupWhenEmpty true;
                {_x deleteGroupWhenEmpty true} forEach _cargoGroups;
            };
        };
    };
      
    if !(_vehInfos isEqualTo []) then {[_vehInfos apply {_x#VEHINFO_VEH}] remoteExec ["ITW_AtkVehicleSpawnerMP",0,true]};
    
    if !(_newObjects isEqualTo []) then { { _x addCuratorEditableObjects [_newObjects, true]; } forEach allCurators };
    
    _vehInfos
};

ITW_AtkUnloadProtect = {
    params ["_veh"];
    // don't allow units to take damage from friendly vehicles for a while after unloading
    // run where ever veh may be local (server and all headless clients)
    _veh addEventHandler ["GetOut", {   
        params ["_veh", "_role", "_unit"];
        if (!isNull _unit) then {
            _this remoteExec ["ITW_AtkUnloadProtUnit",_unit];
        };
    }];
};

ITW_AtkUnloadProtUnit = {
    params ["_veh", "_role", "_unit"];
    // don't allow units to take damage from friendly vehicles for a while after unloading
    // run where unit is local
    _unit setVariable ["ITW_unloadDmgTimeout",time + 240];
    _unit addEventHandler ["HandleDamage", {
        params ["_unit", "_selection", "_damage", "_source"];
        if (_unit getVariable ["ITW_unloadImmuneTime",0] > time) exitWith {0}; // immune for second after being hit by friendly vehicle as he bounces off the ground
        if (_unit getVariable ["ITW_unloadDmgTimeout",0] < time) exitWith {
            _unit removeEventHandler [_thisEvent,_thisEventHandler];
            _unit setVariable ["ITW_unloadDmgTimeout",nil];
            _unit setVariable ["ITW_unloadImmuneTime",nil];
            nil
        };
        if (isNull _source || {_source == _unit}) exitWith {nil};
        private _driver = driver _source;
        if (isNull _driver) exitWith {nil};
        if !(_source isKindOf "LandVehicle" || _source isKindOf "Air" || _source isKindOf "Ship") exitWith {nil};
        private _driverSide = side _driver;
        if (side _unit getFriend _driverSide >= 0.6 || {_driverSide isEqualTo civilian}) exitWith {
            _unit setVariable ["ITW_unloadImmuneTime",time + 1];
            0
        };
        nil
    }];
};
    
ITW_AtkVehicleSpawnerMP = {
    params ["_vehs"];
    {
        _x params ["_veh","_allowDmgReduction"];
        
        if (alive _veh) then {
            if (hasInterface) then {
                _veh addAction ["<t color='#00ff00'>" + localize "STR_ITW_MISC_UnlockVehicle" + "</t>",{
                        params ["_veh", "_caller", "_actionId", "_arguments"];
                        [_veh,true] remoteExec ["enableSimulationGlobal",2];
                        ALLOW_DAMAGE(_veh,_true);
                    },nil,10,false,true,"","! simulationEnabled _target && {_this == vehicle _this}",4,false];
            };
            
            _veh call ITW_VehDmgReduction;
        };
    } forEach _vehs;
};

ITW_AtkSwitchToAirVeh = {
    params ["_vehInfo","_deleteIfFail","_baseFromIdx"];
    private _success = false;
    private _type = _vehInfo#VEHINFO_TYPE;
    private _role = _vehInfo#VEHINFO_ROLE;
    private _sideIndex = ATTACK_SIDE(_vehInfo#VEHINFO_CREW_GRP);
    private _airVehs = [];
    private _attack = 0;
    private _dual = 1;
    private _transport = 2; 
    private _typeWasCar = false;
            
    // adjust role based on how dangerous the vehicle was
    if (_type == ITW_TYPE_VEH_CAR) then {
        _role = ITW_VEH_ROLE_TRANSPORT;
        _typeWasCar = true;
    };
    
    if (_role == ITW_VEH_ROLE_ATTACK) then {    
        _airVehs = ITW_AirVehsDef#_sideIndex#_attack;
        if (_airVehs isEqualTo []) then {_airVehs = ITW_AirVehsDef#_sideIndex#_dual};
        if (_airVehs isEqualTo []) then {_airVehs = ITW_AirVehsDef#_sideIndex#_transport};
    };
    if (_role == ITW_VEH_ROLE_DUAL) then {
        _airVehs = ITW_AirVehsDef#_sideIndex#_dual;
        if (_airVehs isEqualTo []) then {_airVehs = ITW_AirVehsDef#_sideIndex#_transport};
    };
    if (_role == ITW_VEH_ROLE_TRANSPORT) then {
        _airVehs = ITW_AirVehsDef#_sideIndex#_transport;
        if (_airVehs isEqualTo []) then {_airVehs = ITW_AirVehsDef#_sideIndex#_dual};
    };
    
    if !(_airVehs isEqualTo []) then {
        private _oldVeh = _vehInfo#VEHINFO_VEH;
        private _crewGrp = _vehInfo#VEHINFO_CREW_GRP;
        private _cargoGrps = _vehInfo#VEHINFO_CARGO_GRPS;
        
        private _playersOnBoard = crew _oldVeh select {isPlayer _x};
        
        if (_cargoGrps isEqualTo [] && {_playersOnBoard isEqualTo [] && {_role == ITW_VEH_ROLE_TRANSPORT}}) exitWith {
            // if we are switching to a transport, but there are not groups to transport, then don't spawn new aircraft
            if (_deleteIfFail) then {
                private _groups = crew _oldVeh apply {group _x};
                _groups = _groups arrayIntersect _groups;
                deleteVehicleCrew _oldVeh;
                deleteVehicle _oldVeh;
                _vehInfo set [VEHINFO_VEH,objNull];
                _groups apply {if !(units _x isEqualTo []) then {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup}};
            };
            false
        };
        
        {{unassignVehicle _x;moveOut _x} forEach (units _x)} forEach ([_crewGrp] + _cargoGrps);
        {unassignVehicle _x;moveOut _x} forEach _playersOnBoard;
        sleep 0.2;
        
        private _vehDef = selectRandom _airVehs;
        private _vehTypeTxtr = selectRandom (_vehDef#ITW_VEH_CLASSES);
        if (isNil "_vehTypeTxtr") exitWith {false};
        private _vehType = if (typeName _vehTypeTxtr == "ARRAY") then {_vehTypeTxtr#0} else {_vehTypeTxtr};
        
        private _airSpawn = getPosASL _oldVeh;   
        if (typeName _baseFromIdx == "SCALAR" && {_baseFromIdx >= 0}) then {
            private _basePos = ITW_Bases#_baseFromIdx#ITW_BASE_POS;
            _airSpawn = _oldVeh getPos [800,_oldVeh getDir _basePos]; // with "FLY" option, it will spawn in at 50m elevation
        };
        
        private _vehCfg = configFile >> "CfgVehicles" >> _vehType;
        if (isNil "_vehCfg") exitWith {false};
        private _crewCount = {
            round getNumber (_x >> "dontCreateAI") < 1 &&
            ((_x == _vehCfg && { round getNumber (_x >> "hasDriver") > 0 }) ||
            (_x != _vehCfg && { round getNumber (_x >> "hasGunner") > 0 }))
        } count ([_vehType, configNull] call BIS_fnc_getTurrets);
        private _newCrewCnt = 0;
        private _pilot = if (_crewCount == 0) then {objNull} else {leader _crewGrp};
               
        _veh = [_vehTypeTxtr,_airSpawn,"FLY",_pilot] call ITW_VehCreateVehicle;
        
        private _newCargoCnt = 0;
        private _overflowUnits = [];
        
        // transfer crew
        {
            private _unit = _x;
            if (vehicle _unit == _veh) then {_newCrewCnt = _newCrewCnt + 1;continue};
            if (_newCrewCnt < _crewCount) then {
                _newCrewCnt = _newCrewCnt + 1;
                //moveOut _unit;
                _unit moveInAny _veh;
            } else {
                _overflowUnits pushBack _unit;
            };
        } forEach units _crewGrp;
        
        if (_newCrewCnt < _crewCount) then {
            private _leader = leader _crewGrp;
            private _type = typeOf _leader;
            private _pos = getPosATL _oldVeh;
            while {_newCrewCnt < _crewCount} do {
                _newCrewCnt = _newCrewCnt + 1; 
                private _unit = [_crewGrp,[_type],_pos,true] call ITW_AtkUnitToGroup;
                //moveOut _unit;
                _unit moveInAny _veh;
            };
        };
        
        private _cargoCount = (_veh emptyPositions "") - _crewCount;
        // transfer players
        {
            private _player = _x;
            if (_newCargoCnt < _cargoCount) then {
                _newCargoCnt = _newCargoCnt + 1;
                _player moveInAny _veh;
            } else {
                // player can't continue in this vehicle, place them back in the queue
                ([getPosATL _oldVeh] call ITW_ObjGetPlayerSpawnPtDir) params ["_spawnPos","_spawnDir"];
                [true] remoteExec ["ITW_AtkJoinWaveUI",_player];
                _pos = _spawnPos getPos [2 + random 2,random 360];
                _player setPosATL _pos;
                [_player,true] call ITW_AtkJoinWave;
            };
        } forEach _playersOnBoard;
        
        // transfer cargo
        {
            private _grp = _x;
            {
                private _unit = _x;
                if (_newCargoCnt < _cargoCount) then {
                    _newCargoCnt = _newCargoCnt + 1;
                    //moveOut _unit;
                    _unit moveInAny _veh;
                } else {
                    if (isPlayer _unit) then {
                        [_unit] call _PlayerHandlerFn;
                    } else {
                        _overflowUnits pushBack _unit;
                    };
                };
            } forEach units _grp;
            false
        } forEach _cargoGrps;

        {deleteVehicle _x} forEach _overflowUnits;
        {if (count units _x == 0) then {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup}} forEach _cargoGrps;
        
        {_x setRank "SERGEANT";_x setSkill ["courage",1]} forEach units _crewGrp;
        private _driver = driver _veh;
        _driver setRank "LIEUTENANT";
        [_driver,"CARELESS"] call ITW_FncSetUnitBehavior;
        { _x addCuratorEditableObjects [[_veh], false]; } forEach allCurators;
               
        // update the vehicle info
        _vehInfo set [VEHINFO_TYPE,_vehDef#ITW_VEH_TYPE];
        _vehInfo set [VEHINFO_VEH,_veh];
        if (_typeWasCar) then {_vehInfo set [VEHINFO_ROLE,ITW_VEH_ROLE_TRANSPORT]};
        deleteVehicle _oldVeh;
        _success = true;
        YIELD_CPU;
    };
    _success
};

ITW_AtkAirDropVeh = {
    params ["_vehInfo","_objPos","_objSize"];
    private _success = false;
    private _type = _vehInfo#VEHINFO_TYPE;
    private _role = _vehInfo#VEHINFO_ROLE;
    private _veh = _vehInfo#VEHINFO_VEH;
    private _fromPos =  _vehInfo#VEHINFO_FROM_POS;
    
    private _isAllLandFn = {
        // check if there is water in a line from _pos along _dir
        params ["_pos","_dir","_objSize","_dist"];
        private _okay = true;
        for "_r" from _objSize to _dist step 5 do {
            if (getTerrainHeight (_pos getPos [_r,_dir]) < -0.4) exitWith {_okay = false}; 
        };
        _okay
    };
    
    private _pos = [];
    if (_veh isKindOf "Ship") then {
        // find a point to air drop sea vehicle
        private _cnt = 100;
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            private _dir = random 360;
            private _dist = ITW_ZoneKeepOut + random 1000;
            _pos = _objPos getPos [_dist,_dir];
            if (getTerrainHeightASL _pos < -1) then {
                private _closestEnemyObj = [_pos,ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
                private _nearestBase = ITW_Bases#(_closestEnemyObj#ITW_OBJ_INDEX);
                if (_pos distanceSqr (_nearestBase#ITW_BASE_POS) < ITW_ZoneKeepOutSqr) then {_pos = []};
            } else {
                _pos = [];
            };
            YIELD_CPU; // don't monopolize the cpu
        };
    } else {
        // find a point to air drop land vehicle
        private _cnt = 60;
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            private _dir = (_objPos getDir _fromPos) + (if (_cnt < 20) then {90 + random 180} else {-90 + random 180});
            private _dist = ITW_ZoneKeepOut + random 500;
            if ([_objPos,_dir,_objSize,_dist] call _isAllLandFn) then {
                _pos = _objPos getPos [_dist,_dir];
                private _closestEnemyObj = [_pos,ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
                private _nearestBase = ITW_Bases#(_closestEnemyObj#ITW_OBJ_INDEX);
                if (_pos distanceSqr (_nearestBase#ITW_BASE_POS) < ITW_ZoneKeepOutSqr) then {_pos = []};
            } else {
                _pos = [];
            };
            YIELD_CPU; // don't monopolize the cpu
        };
    };
    
    if !(_pos isEqualTo []) then {
        _success = true;
        _vehInfo set [VEHINFO_FROM_POS,_pos];
        _pos set [2,150];
        [_veh,_pos] remoteExec ["ITW_FncVehicleHalo",_veh];
    };
    _success
};

ITW_AtkSpawnVeh = {
    // returns vehicle object or objNull if spawning failed, damage is not allowed on vehicle
    params ["_vehArrayItem","_crewTypes","_unitTypes","_side","_spawnPt",["_vehArrayIndex",ITW_VEH_CLASSES]];
    if (isNil "_vehArrayItem") exitWith {objNull};
    private _veh = objNull;
    private _vehTypeTxtr = if (_vehArrayIndex >= 0) then {selectRandom (_vehArrayItem#_vehArrayIndex)} else {selectRandom _vehArrayItem};
    if (!isNil "_vehTypeTxtr") then {
        private _vehType = if (typeName _vehTypeTxtr == "ARRAY") then {_vehTypeTxtr#0} else {_vehTypeTxtr};
        private _vehCfg = configFile >> "CfgVehicles" >> _vehType;
        if (isNil "_vehCfg") exitWith {};
        // try using the defined vehicle crew type
        private _vehCrew = toLowerANSI getText (_vehCfg >> "crew");
        private _vehCrewTypes = if (_vehCrew in _crewTypes || {_vehCrew in _unitTypes}) then {[_vehCrew]} else {
            // special case for TIOW
            if (isClass (configfile >> "CfgPatches" >> "TIOWSpaceMarines")) then {
                private _isMarineVehicle = _veh isKindOf "TIOW_SM_Rhino_UM";
                private _ut = if (_isMarineVehicle) then {_unitTypes select {_x isKindOf "TIOWSpaceMarine_Base"}} else {_unitTypes select {!(_x isKindOf "TIOWSpaceMarine_Base")}};
                if (_ut isEqualTo []) then {_ut = _unitTypes};
                _ut
            } else {
                if (_vehType isKindOf "Air") then {_crewTypes} else {_unitTypes};
            };
        };
        private _crewCount = [_vehType, false] call BIS_fnc_crewCount;
        private _units = [];
        private _crewGrp = createGroup [_side,false];   
        if (_vehType isKindOf "Air") then {  
            private _pilot = if (_crewCount > 0) then {[_crewGrp,_vehCrewTypes,_spawnPt,true] call ITW_AtkUnitToGroup} else {objNull};
            _crewCount = _crewCount - 1;
            // with "FLY" option, it will spawn in at 50m elevation
            _veh = [_vehTypeTxtr,_spawnPt,"FLY",_pilot] call ITW_VehCreateVehicle;
        } else {
            private _landSpawn = +_spawnPt;
            _landSpawn set [2,_landSpawn#2 + 4];     
            _veh = [_vehTypeTxtr,_landSpawn] call ITW_VehCreateVehicle;
        };
        ALLOW_DAMAGE(_veh,false);
        
        for "_i" from 1 to _crewCount do {
            private _unit = [_crewGrp,_vehCrewTypes,_spawnPt,true] call ITW_AtkUnitToGroup;
            _units pushBack _unit;
            // _unit moveInAny _veh    didn't always work with RHS tanks, with this code I've seen it take 20 tries to get the unit into the vehicle
            private _success = false;
            private _cnt = 50;
            while {!_success && {_cnt > 0}} do {
                _success = _unit moveInAny _veh;
                _cnt = _cnt - 1;
                if (!_success) then {YIELD_CPU};
            };
        };
        {_x setRank "SERGEANT";_x setSkill ["courage",1]} forEach _units;
        private _driver = driver _veh;
        _driver setRank "LIEUTENANT";
        [_driver,"CARELESS"] call ITW_FncSetUnitBehavior;
                
        _crewGrp allowFleeing 0;
        _crewGrp deleteGroupWhenEmpty true;
        ITW_AtkNewVehSpawned = true;
        YIELD_CPU;
    };
    _veh
};

ITW_AtkVehRemoveMagazines = {
    // run where vehicle is local
    params ["_veh"];
    private _mags = magazinesAllTurrets [_veh,true] select {_n=toLowerANSI (_x#0);!("smoke" in _n) && !("flare" in _n)};
    {_veh removeMagazinesTurret [_x#0,_x#1]} forEach _mags;
};
    
ITW_AtkAddVehicle = {
    params ["_vehInfo","_populateObjectives"];
    private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
    private _cargoGroups = _vehInfo#VEHINFO_CARGO_GRPS;
    [_vehInfo,true,_populateObjectives] call ITW_AtkEngageVehicle;
    private _veh = _vehInfo#VEHINFO_VEH;
    if (!alive _veh) exitWith {}; // vehicle was removed
    
    if (_vehInfo#VEHINFO_ROLE == ITW_VEH_ROLE_TRANSPORT) then {
        // this file has many adjustments to try to ensure vehicles are available, but sometimes
        // a vehicle with weapons is assigned as a transport only.  In that case make sure it has no 
        // ammo available
        [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
    };
    
    SEM_LOCK(ITW_AtkVehicleManagerBusy);
    isNil {ITW_ManagedVehs pushBack _vehInfo};
    SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
};

ITW_AtkSafeGroupAllowDamage = {
    params ["_groups","_allowed"];
    if (typeName _groups == "GROUP") then {_groups = [_groups]};
    _groups = _groups arrayIntersect _groups;
    {
        private _grp = _x;
        if (!local _grp) then {
            [[_grp,_allowed],"ITW_AtkSafeGroupAllowDamage",_grp] call ITW_FncRemoteLocalGroup;
        } else {
            {ALLOW_DAMAGE(_x,_allowed)} forEach units _grp;
        };
    } forEach _groups
};

ITW_AtkSafeMove = {
    params ["_group","_pos"];
    private _units = units _group;
    _pos = +_pos; // don't modify the passed in array
    _pos set [2,0];
    private _isWater = surfaceIsWater _pos;
    {
        ALLOW_DAMAGE(_x,false);
        if (_isWater) then {_x setPosASL _pos} else {_x setPosATL _pos};
    } forEach _units; 
    sleep 1;
    {
        // sometimes the units is moved right away, but then it's back at it's original position
        while {_pos distance _x > 1000} do {
            if (_isWater) then {_x setPosASL _pos} else {_x setPosATL _pos};
            YIELD_CPU;   
        };
        ALLOW_DAMAGE(_x,true);
    } forEach _units;
};

ITW_AtkSafeSetVectorUp = {
    // set vector up accounting for locality
    params ["_veh","_pos"];
    if (!local _veh) then {
        _this remoteExec ["ITW_AtkSafeSetVectorUp",_veh];
        sleep 1;
    } else {
        ALLOW_DAMAGE(_veh,false);
        if (!surfaceIsWater _pos) then {
            _veh setVectorUp surfaceNormal _pos;
        } else {
            _veh setVectorUp [0,0,1];
        };
        _pos set [2,_pos#2 + 0.25];
        _veh setPosATL _pos;
        sleep 2;
        ALLOW_DAMAGE(_veh,true);
    };
};

ITW_AtkAddCrewToStatic = {
    params ["_veh","_isFriendly"];  
    ITW_AtkStaticNeedsCrew#(if (_isFriendly) then {ATTACK_FRIENDLY} else {ATTACK_ENEMY}) pushBack _veh;
};

ITW_AtkAddInfantryGroup = {
    params ["_group",["_objToPopulate",[]],["_teleportToAttackPos",true]];
    [_group,_teleportToAttackPos,_objToPopulate] call ITW_AtkEngageInfantry;
};

ITW_AtkEngageInfantry = {
    scriptName "ITW_AtkEngageInfantry";
    params ["_group","_teleportToAttackPos",["_objToPopulate",[]]];
    // choose objective to attack/defend and assign waypoints
    private _populateObj = !(_objToPopulate isEqualTo []);
    private _isFriendly = GRP_IS_FRIENDLY(_group);
    private _idx = ATTACK_SIDE(_group);
    private _fnAttackVectors = ITW_AtkVectors#_idx;
    private _vector = [AV_INFANTRY,_group,[],false,!_teleportToAttackPos && !_populateObj] call _fnAttackVectors;
    _vector params ["_objTo","_baseFromIdx"]; 
    private _toPos = _objTo#ITW_OBJ_POS;
    if (_populateObj) then {
        if (((_objToPopulate#ITW_OBJ_INDEX) call ITW_ObjContestedOwnerIsFriendly) != _isFriendly) then {
            _populateObj = false; // can only populate objectives that are captured by your side
        } else {
            _toPos = _objToPopulate#ITW_OBJ_POS;
        };
    };
    
    if (_teleportToAttackPos || _populateObj) then {
        private _pos = [];
        if (_populateObj) then {
            _pos = _toPos getPos [random 50,random 360]
        } else {
            private _rallyPt = [_objTo#ITW_OBJ_INDEX] call ITW_RallyPoint_ObjectivePoint;
            if (_rallyPt isNotEqualTo []) then {
                _pos = _rallyPt;
            } else {
                _pos = if (_baseFromIdx >= 0) then {ITW_Bases#_baseFromIdx#ITW_BASE_A_SPAWN} else {_isFriendly call ITW_ObjGetOutToSeaPos};
                private _dir = _pos getDir _toPos;
                _pos = _pos getPos [50 + random 50,_dir - 20 + random 40];
            };
        };
        if (surfaceIsWater _pos) then {
            private _toDir = _pos getDir _toPos;
            while {surfaceIsWater _pos} do {
                _pos = _pos getPos [300,_toDir];
                if (_pos distance2D _toPos < 800) exitWith {
                    // units are being dumped in the sea far from objective, just delete them
                    {deleteVehicle _x} forEach units _group;
                    deleteGroup _group;
                };
            };
        };
        if !(isNull _group) then {
            [[_group,_pos],"ITW_AtkSafeMove",_group] call ITW_FncRemoteLocalGroup;
            sleep 0.5;
        };
    };

    if (!_populateObj && {!(vehicle leader _group in ITW_Statics)}) then {
        private _objSize = _objTo#ITW_OBJ_SIZE;
        private _toPos = _toPos getPos [_objSize,_toPos getDir (getPosATL leader _group)];
        ITW_DELETE_WAYPOINTS(_group);
        _group addWaypoint [_toPos,100];
        ATK_DEBUG(_group,"ITW_AtkEngageInfantry waypoints updated",_toPos); 
    };
};

ITW_AtkGetRealType = {
    params ["_vehInfo"];
    private _veh = _vehInfo#VEHINFO_VEH;
    if (isNull _veh) exitWith {_vehInfo#VEHINFO_TYPE};
    
    private _type = switch (true) do {
        case (_veh isKindOf "Car")  : {ITW_TYPE_VEH_CAR};
        case (_veh isKindOf "Tank") : {ITW_TYPE_VEH_TANK};
        case (_veh isKindOf "Plane"): {ITW_TYPE_VEH_AIRPLANE};
        case (_veh isKindOf "Air")  : {ITW_TYPE_VEH_HELI};
        case (_veh isKindOf "Ship") : {ITW_TYPE_VEH_SHIP};
        default                       {ITW_TYPE_VEH_CAR};
    };
    _type
};

ITW_AtkEngageVehicle = {
    params ["_vehInfo",["_teleportToAttackPos",false],["_populateObjectives",false]];
    scopeName "ITW_AtkEngageVehicle";
    private _crewGroup = _vehInfo#VEHINFO_CREW_GRP;
    private _cargoGroups = _vehInfo#VEHINFO_CARGO_GRPS;
    private _type = [_vehInfo] call ITW_AtkGetRealType; // can't trust vehinfo since it is just the ticketing info
    private _role = _vehInfo#VEHINFO_ROLE;
    private _veh = _vehInfo#VEHINFO_VEH;
    // choose objectives to attack/defend and assign waypoints
    private _atkSide = ATTACK_SIDE(_crewGroup);
    private _fnAttackVectors = ITW_AtkVectors#_atkSide;
    private _vectorType = AV_VEHICLE;
    if (_role == ITW_VEH_ROLE_ATTACK) then {
        _vectorType = AV_VEHICLE_ATTACK;
        _veh setVariable ["itwattackveh",true]; // used by attack vectors to know which vehicle are attack vehicles
    };
    private _vector = [_vectorType,_crewGroup,_cargoGroups,_populateObjectives] call _fnAttackVectors;
    _vector params ["_objTo","_baseFromIdx"];
    private _objPos = _objTo#ITW_OBJ_POS;
    private _objSize = _objTo#ITW_OBJ_SIZE;
    private _objIndex = _objTo#ITW_OBJ_INDEX;
    private _vehIsSea = ITW_VEH_IS_SEA(_type);
    private _seaPts = if (_vehIsSea) then {ITW_SeaPoints#_objIndex} else {[]};
    private _atkPossible = _objTo#ITW_OBJ_ATK_AVAIL#(if (_vehIsSea) then {ATTACK_SIDE_SEA(_crewGroup)} else {_atkSide});
    private _baseIndexValid = true;
    private _isFriendly = GRP_IS_FRIENDLY(_crewGroup);
    if (!_atkPossible && {_vehIsSea}) then { _atkPossible = call ITW_WarshipsAvailable; _baseIndexValid = false};
    
    [_objIndex,_isFriendly] call ITW_WarshipAttackVector params ["_warshipAirIndex","_warshipSeaIndex"];
    if (!_atkPossible && _vehIsSea) then {_atkPossible = (_warshipSeaIndex >= 0)};
    
    // this is run only on first assignment, skipped when waypoint updated on vehicle in the field
    if (_teleportToAttackPos) then {
        if (_cargoGroups isNotEqualTo [] && {side _crewGroup == ITW_PlayerSide}) then {
            private _rallyPt = [_objTo#ITW_OBJ_INDEX] call ITW_RallyPoint_ObjectivePoint;
            if (_rallyPt isNotEqualTo []) then {
                private _playersOnBoard = crew _veh select {isPlayer _x};
                {{unassignVehicle _x;moveOut _x} forEach (units _x)} forEach _cargoGroups;
                {unassignVehicle _x;moveOut _x} forEach  _playersOnBoard;
                sleep 0.2;
                {{_x setPosATL _rallyPt} forEach (units _x)} forEach _cargoGroups;
                {_x setPosATL _rallyPt} forEach  _playersOnBoard;
                _cargoGroups = [];
                if (_role == ITW_VEH_ROLE_TRANSPORT) then { // use exitWith even though we're doing breakOut since I search for exitWith to find if we've extied early
                    // was a transport only, but we sent the cargo to rally point so delete the vehicle
                    private _groups = crew _veh apply {group _x};
                    _groups = _groups arrayIntersect _groups;
                    deleteVehicleCrew _veh;
                    deleteVehicle _veh;
                    _veh = objNull;
                    _vehInfo set [VEHINFO_VEH,objNull];
                    _groups apply {if !(units _x isEqualTo []) then {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup}};
                    breakOut "ITW_AtkEngageVehicle"; // EXIT THE FUNCTION DIRECTLY (exitWith
                };
            };
        };
        if (!_atkPossible && {!ITW_VEH_IS_AIR(_type) && {!(_veh isKindOf "Air")}}) then {
            // if no land/sea route, air drop or switch to air vehicle
            switch (true) do {
                case (_vehIsSea): {
                    if (_seaPts isEqualTo []) then {
                        // to obj is not accessible from sea           
                        [_vehInfo,false,_baseFromIdx] call ITW_AtkSwitchToAirVeh;
                    } else {
                        private _success = if (ITW_ParamAirDropVehicles == 1) then {[_vehInfo,_objPos,_objSize] call ITW_AtkAirDropVeh} else {false};
                        if (!_success) then {
                            [_vehInfo,true,_baseFromIdx] call ITW_AtkSwitchToAirVeh;
                        };
                    };
                };
                case ITW_VEH_IS_LAND(_type): {
                    if (!_populateObjectives) then {
                        // randomly choose 'air drop' or 'switchToAir', then try the other if not successful
                        if (random 1 < 0.5) then {           
                            private _success = [_vehInfo,false,_baseFromIdx] call ITW_AtkSwitchToAirVeh;
                            if (!_success) then {           
                                if (ITW_ParamAirDropVehicles == 1) then {[_vehInfo,_objPos,_objSize] call ITW_AtkAirDropVeh} else {false};
                            };
                        } else {    
                            private _success = if (ITW_ParamAirDropVehicles == 1) then {[_vehInfo,_objPos,_objSize] call ITW_AtkAirDropVeh} else {false};
                            if (!_success) then {
                                [_vehInfo,true,_baseFromIdx] call ITW_AtkSwitchToAirVeh;
                            };
                        };
                    };
                };
            };
            _baseIndexValid = true;
            _type = [_vehInfo] call ITW_AtkGetRealType;
        };
        if (!alive (_vehInfo#VEHINFO_VEH)) exitWith {}; // vehicle was removed
      
        // deal with dualAsTransport vehicles
        if (_vehInfo#VEHINFO_IS_DUAL_AS_TRANSPORT) then {
            _veh setVehicleAmmo 0;
        };
        
        private _baseIdxOrPt = _baseFromIdx;
        private _veh = _vehInfo#VEHINFO_VEH;
        private _pos = if (_baseIndexValid) then {ITW_Bases#_baseFromIdx#ITW_BASE_POS} else {_isFriendly call ITW_ObjGetOutToSeaPos};
        if (_vehIsSea && {_warshipSeaIndex >= 0} || (ITW_VEH_IS_AIR(_type) && {_warshipAirIndex >= 0})) then {
            // warship available
            private _shipPoint = [if (_vehIsSea) then {_warshipSeaIndex} else {_warshipAirIndex}] call ITW_WarshipGetPos;
            private _shipDist = _shipPoint distance _objPos;         
            private _objDist = _pos distance _objPos;
            private _deltaDist = _shipDist - _objDist;
            switch (true) do {
                case (_deltaDist < -400):        {_pos = _shipPoint; _baseIdxOrPt = _shipPoint};  // use ship
                case (_deltaDist > 400):         {};                                              // use obj
                default {if (random 10 < 5) then {_pos = _shipPoint; _baseIdxOrPt = _shipPoint}}; // select randomly between them
            };    
        };
        
        private _dir = _pos getDir _objPos;
        ALLOW_DAMAGE(_veh,false);
        private _spawnType = _type;
        if (_veh isKindOf "Air" && {_type > ITW_TYPE_VEH_AIR_MAX}) then {
            // land/sea vehicle replaced by air (due to no land vehicles)
            if (_veh isKindOf "Ship") then {_spawnType = ITW_TYPE_VEH_SHIP} else {
                if (_veh isKindOf "Plane") then {_spawnType = ITW_TYPE_VEH_AIRPLANE} else {
                    _spawnType = ITW_TYPE_VEH_HELI;
                };
            };
        };
        if (_spawnType == ITW_TYPE_VEH_AIRPLANE) then {
            // airplanes spawn by airfield
            private _veh = _vehInfo#VEHINFO_VEH;
            _pos = [_isFriendly,_objPos] call ITW_ObjClosestOwnedAirport;
            if (_pos isEqualTo []) then {
                // this shouldn't happen
                _pos = ITW_Objectives#(if (_isFriendly) then {0} else {-1})#ITW_OBJ_POS;
            };
            _pos = _pos getPos [- 200,_dir];
        } else {
            if (_spawnType == ITW_TYPE_VEH_HELI) then {
                // helis spawn on far side of base from objective
                _pos = _pos getPos [1000,_objPos getDir _pos];
            } else {
                if (_spawnType == ITW_TYPE_VEH_SHIP) then {
                    // leave _pos as is, it isn't used anyway
                } else {
                    // Land Veh: ideal spawn point for spawning on the ground is on the side of the base towards the objective
                    _pos = _pos getPos [ITW_ZoneKeepOut/2,_pos getDir _objPos];
                };
            };
        };
        
        [_type,_pos,_dir,_baseIdxOrPt,_objTo#ITW_OBJ_INDEX,typeOf _veh] call ITW_AtkSpawnOffsetter params ["_offsetPos","_offsetDir"];

        // if we're spawning into objectives, give it a try
        if (_veh isKindOf "Land" && _populateObjectives) then {     
            if (_isFriendly != ([_objIndex] call ITW_ObjContestedOwnerIsFriendly)) exitWith {}; // can only place into objectives we own
            private _pos = _objTo#ITW_OBJ_POS;
            _dir = _dir + 180;
            [_type,_pos,_dir,_objTo#ITW_OBJ_INDEX,_baseIdxOrPt,typeOf _veh] call ITW_AtkSpawnOffsetter params ["_offsetPos2","_offsetDir2"]; 
            _offsetPos = _offsetPos2;
            _offsetDir = _offsetDir2 + 180; // switch direction back to face toObj
        };
        
        if !(_offsetPos isEqualTo []) then {
            ALLOW_DAMAGE(_veh,false);
            YIELD_CPU;
            if (local _veh) then {_veh setDir _offsetDir} else {[_veh,_offsetDir] remoteExec ["setDir",_veh]};
            ITW_SETPOS_AGL(_veh,_offsetPos);
            if (ITW_VEH_IS_LAND(_type)) then {
                // this next code can take a few seconds and we could be in the veh mgr semaphore, so spawn it (remotely if needed)
                [_veh,getPosATL _veh] remoteExec ["ITW_AtkSafeSetVectorUp",_veh]; 
                YIELD_CPU;
            } else {
                if (ITW_VEH_IS_AIR(_type)) then {
                    private _vel = 60;
                    if (local _veh) then {_veh setVelocityModelSpace [0,_vel,0]} else {[_veh,[0,_vel,0]] remoteExec ["setVelocityModelSpace",_veh]};
                };
            };
        };
        _veh setVariable ["ITW_VehStartSafe",[getPosATL _veh, time+60]];
        _veh setVariable ["ITW_VehFriendly",_isfriendly];
        
        // if transports are destroyed before unloading, then the vehicles need to unload further back
        if !(_cargoGroups isEqualTo []) then {
            private _eh = _veh addMPEventHandler ["MPKilled", {
                if (!isServer) exitWith {};
                params ["_veh"];
                [_veh getVariable ["ITW_VehFriendly",-1],false] call ITW_AtkTranspSuccess;
                _veh removeMPEventHandler ["MPKilled",_thisEventHandler];
            }];
            _veh setVariable ["itwKilledEH",_eh];
        };
    };
    
    // move near center of obj, manager will take over once it gets close
    private _pos_FN = { // get a position outside the zone
        private _wpDist = _veh distance _objPos;
        private _angle = atan ((ITW_ParamObjectiveSize+200)/_wpDist);
        private _wpDir = _veh getDir _objPos;
        _veh getPos [_wpDist,_wpDir - _angle + random(2*_angle)]
    };
    
    private _getWpPos_FN = { // get a waypoint position based on vehicle type
        // uses local variable from caller
        if (ITW_VEH_IS_SEA(_type) && {count _seaPts > 0}) exitWith {selectRandom _seaPts};
        if (ITW_VEH_IS_AIR(_type)) exitWith {call _pos_FN};
        private _pos = [];
        private _attempts = 20;
        while {_pos isEqualTo []} do {
            _attempts = _attempts - 1;
            _pos = call _pos_FN;
            if (surfaceIsWater _pos && {_attempts > 0}) then {_pos = []};
        };
        _pos
    };
    
    ITW_DELETE_WAYPOINTS(_crewGroup);
    private _wp = _crewGroup addWaypoint [call _getWpPos_FN ,100]; 
    _wp setWaypointCompletionRadius 200;
    _wp setWaypointSpeed "NORMAL";
    private _moveType = "MOVE";
    if (_cargoGroups isEqualTo []) then {
        _moveType = if (ITW_ParamAggressivePlanes == 1 && {_veh isKindOf "PLANE"}) then {"MOVE"} else {"SAD"}; // planes don't do SAD very well
        _wp setWaypointType _moveType;
        _wp setWaypointBehaviour "COMBAT";
        _wp setWaypointCombatMode "RED";
    } else {
        _wp setWaypointType _moveType;
        _wp setWaypointBehaviour "AWARE";
        _wp setWaypointCombatMode "YELLOW";
        driver _veh doFollow leader _crewGroup;
    };
    if (_veh isKindOf "Plane") then {
        _veh flyInHeight 400;
    };
    ATK_DEBUG2(_crewGroup,"ITW_AtkEngageVehicle waypoints updated",waypointPosition _wp,_moveType); 
    YIELD_CPU;
    ALLOW_DAMAGE(_veh,true);
};

ITW_AtkSpawnOffsetter = {
    params ["_type","_pos","_dir","_fromBaseIdxOrPt","_toObjIdx",["_landVehClass","B_Quadbike_01_F"]];
    // returns [pos,dir]
    // pos: a position offset from pos to keep spawned vehicles from colliding
    // dir: direction facing towards the _toPos (land vehicles will be facing road direction)
    // _fromBaseIdxOrPt is a base index, or a warship center point (air/sea only)
    private _offset = 0;
    private _newPos = [];
    private _newDir = _dir;
    
    if (ITW_VEH_IS_AIR(_type)) then {
        // airplanes need to remain in the air
        // start with a radial offset at two different distances (works find for aircraft)
        
        if (isNil "ITW_SpawnPlaneOffset") then {ITW_SpawnPlaneOffset=0};
        private _offset = ITW_SpawnPlaneOffset;
        ITW_SpawnPlaneOffset = (_offset+1) mod 16;
        
        private _dist = if (_offset < 8) then {300} else {200};
        private _angle = switch (_offset) do {
                             case  0;
                             case  8: {0};
                             case  4;
                             case 13: {45};
                             case  1;
                             case  9: {90};
                             case  5;
                             case 14: {135};
                             case  2;
                             case 10: {180};
                             case  6;
                             case 15: {225};
                             case  3;
                             case 11: {270};
                             case  7;
                             case 12: {315};
                         };
        _newPos = _pos getPos [_dist,_angle];
        _newPos set [2,if (_type == ITW_TYPE_VEH_AIRPLANE) then {100} else {40}];
        
    } else {
        if (ITW_VEH_IS_SEA(_type)) then {
            // sea vehicles
            if (isNil "ITW_SpawnShipOffset") then {ITW_SpawnShipOffset=0};
            private _offset = ITW_SpawnShipOffset;
            ITW_SpawnShipOffset = (_offset+1);
            
            if (typeName _fromBaseIdxOrPt == "SCALAR") then {          
                private _seaPts = ITW_SeaPoints#_fromBaseIdxOrPt;
                if !(_seaPts isEqualTo []) then {
                    _offset = _offset mod (count _seaPts);
                    _newPos = _seaPts#_offset;
                    _newPos set [2,0];
                };
            } else {
                // warship, just place it around the ship somewhere
                _offset = _offset mod 36;
                _newPos = _fromBaseIdxOrPt getPos [150,_offset * 10];
                _newPos set [2,0];
            };
        } else {
            // land vehicles might end up in buildings and such
            // 1st try to place on roads
            
            // we cache the roads around a base biased towards the first objective we see from this base
            if (isNil "ITW_AtkRoadMap"  ) then {ITW_AtkRoadMap = createHashMap};
            private _roads = ITW_AtkRoadMap getOrDefault [[_fromBaseIdxOrPt,_toObjIdx],nil];
            if (isNil "_roads" && {_fromBaseIdxOrPt>= 0}) then {
                private _basePos = ITW_Bases#_fromBaseIdxOrPt#ITW_BASE_POS;
                private _roadBestPos = _basePos getPos [200,_basePos getDir _pos];
                 _roads = _pos nearRoads ((ITW_ZoneKeepOut/2)) select {_x distance _basePos > 100};
                if (count _roads < 25) then {
                    _roads = (_basePos getPos [ITW_ZoneKeepOut*.75,_basePos getDir _pos]) nearRoads ((ITW_ZoneKeepOut/2)+200) select {_x distance _basePos > 100};
                };
                if (count _roads < 25) then {
                    _roads = (_basePos getPos [ITW_ZoneKeepOut,_basePos getDir _pos]) nearRoads ((ITW_ZoneKeepOut)+200) select {_x distance _basePos > 100};
                };
                private _i = 1;
                while {_i < count _roads} do {
                    private _r = _roads#(_i-1);
                    for "_j" from (count _roads -1) to _i step -1  do {
                        private _r2 = _roads#_j;
                        if (_r distance _r2 < 70) then {_roads deleteAt _j};
                    };
                    _i = _i + 1;
                };                    
                _roads = [_roads,[_roadBestPos],{_x distance2D _input0},"ASCEND"] call BIS_fnc_sortBy;
                if (count _roads < 10) then {_roads = []} else {
                    if (count _roads > 20) then {_roads resize 20};
                };
                ITW_AtkRoadMap set [[_fromBaseIdxOrPt,_toObjIdx],_roads]; 
            };
            
            if (isNil "_roads" || {_roads isEqualTo []}) then {
                // no roads available
                private _emptyPos = [0];
                private _dist = 100;
                while {_emptyPos isEqualTo [0] && {_dist < 5000}} do {
                    //_emptyPos = _pos findEmptyPosition [0,_dist,_landVehClass]; - this caused huge frame delays as _dist could get very large
                    private _vehSize = sizeOf _landVehClass;
                    if (_vehSize == 0) then {_vehSize = 10};
                    _emptyPos = [_pos,0,_dist,_vehSize,0,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos;
                    _dist = _dist + 500;
                    YIELD_CPU;
                };
                if !(_emptyPos isEqualTo [0]) then {
                    _newPos = _emptyPos;
                };
            } else {
                // roads available 
                // keep different offsets for each base (it's cleared at NextZone)
                if (isNil "ITW_SpawnOffsets") then {ITW_SpawnOffsets = createHashMap};
                private _offset = ITW_SpawnOffsets getOrDefault [[_fromBaseIdxOrPt,_toObjIdx],count _roads - 1];
                private _road = _roads#_offset;
                private _rInfo = getRoadInfo _road;
                _newPos = _rInfo#6;
                _newDir = (_rInfo#6) getDir (_rInfo#7);
                if (_newPos isEqualTo [0,0,0]) then {
                    // some road segments are messed up : invisibleroadway_square_f.p3d
                    _newPos = getPosATL _road;
                    _newDir = getDir _road;
                };
                private _diff = abs (_newDir - _dir);
                if (_diff > 180) then {_newDir = _newDir - 180;_diff = abs (_newDir - _dir)};
                if (_diff > 90) then {_newDir = _newDir + 180};
                // to add even more space, count by 2 and toggle starting count
                // use -2 so we move from furthest to nearest, so the 1st spawned veh doesn't drive into the next spawn point
                _offset = _offset - 2;
                if (_offset < 0) then {
                    private _rdCnt = count _roads;
                    _offset = _rdCnt - (if (abs(_offset mod 2) == ((_rdCnt - 1) mod 2)) then {2} else {1}); 
                };
                ITW_SpawnOffsets set [[_fromBaseIdxOrPt,_toObjIdx],_offset];
            };
            // land vehicles need to spawn slightly above the ground and drop down 
            if !(_newPos isEqualTo []) then {
                _newPos set [2,0.5];
            };
        };
    };
    
    [_newPos,_newDir]
};

ITW_AtkStuckHandler = {
    scriptName "ITW_AtkStuckHandler";
    // Stuck Handler
    // If it's 1st time it's checked then delay = JustSpawnedTimeout otherwise noMoveTimeout
    // after timeout, check if it's moved, if not move it a little and check again
    #define AFTER_MOVE_TIME    100 // after unit moved, check again in this many seconds
    #define INIT_PREV_POS      [-10,-10]
    #define NEWLY_SPAWNED_TIME 100  // is considered newly spawned for first 100sec after spawning 
    private _started = false;
    private _objSizeSqr = ITW_ParamObjectiveSize * ITW_ParamObjectiveSize;
    private _playerDistUnitSqr = 400 * 400;
    private _playerDistVehSqr =  800 * 800;
    private _vehCanFloatHash = createHashMap;
    while {!ITW_GameOver} do {
        private _vehiclesProcessed = [];
        private _allUnits = +allUnits;
        private _sleepTime = AFTER_MOVE_TIME;
        ITW_AtkNewVehSpawned = false;        
        {
            private _unit = _x;
            private _grp = group _unit;
            if (_unit isKindOf "LOGIC") then {continue};
            private _unitGrp = group _unit;
            private _unitCurWpIdx = currentWaypoint _unitGrp;      
            if ( isPlayer _unit || {side _unit == civilian || {!ALIVE(_unit) || {captive _unit || {_unitCurWpIdx >= count waypoints _unitGrp}}}}) then {continue};
            
            private _veh = vehicle _unit; 
            if (_veh in _vehiclesProcessed || _veh in ITW_Statics || {fuel _veh == 0}) then {continue};
            
            // unit stuck in water check (not veh)
            private _canFloat = _vehCanFloatHash getOrDefault [typeOf _veh,nil];
            if (isNil "_canFloat") then {
                _canFloat = 1 == getNumber (configFile >> "cfgVehicles" >> typeOf _x >> "canFloat");
            };
            if !(_canFloat) then {
                if (_veh == _unit && {surfaceIsWater getPosATL _unit}) then {
                    private _waterTimeout = _unit getVariable ["itw_inWater",0];
                    if (_waterTimeout == 0) then {
                        _waterTimeout = time + 480; // 8 minutes
                        _unit setVariable ["itw_inWater",_waterTimeout];
                    };
                    if (time > _waterTimeout) then {
                        deleteVehicle _unit;
                        if (count units _unitGrp == 0) then {[[_unitGrp],"deleteGroup",_unitGrp] call ITW_FncRemoteLocalGroup};
                        continue;
                    };
                } else {
                    _unit setVariable ["itw_inWater",nil];
                };
            };
            
            // group is still at old captured objective
            if (_unit == leader _unit && {group _unit getVariable ["ITW_OkayToReset",false]}) then {
                private _veh = vehicle _unit;
                private _isVeh = _veh != _unit;
                if (_isVeh && {!(driver _veh in (units _grp))}) exitWith {}; // don't deal with cargo units
                private _dist = if (_isVeh) then {2000} else {1000};
                private _okayToDelete = true;   
                // if near players, don't allow deleting yet
                {if (_x distance _unit < _dist) exitWith {_okayToDelete = false}} forEach (allPlayers - HeadlessClients);
                // if near new objective, don't delete
                if (_okayToDelete) then {
                    private _objIdx = VAR_GET_OBJ_IDX(_grp);
                    private _obj = if (_objIdx >= 0) then {ITW_Objectives#_objIdx} else {
                        [getPosATL _unit,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED,true] call ITW_ObjGetNearest;
                    };
                    if !(_obj isEqualTo []) then {
                        private _objPt = _obj#ITW_OBJ_POS;
                        private _objSize = _obj#ITW_OBJ_SIZE;
                        if (_unit distance2D _objPt <= (_dist + _objSize)) then {_okayToDelete = false};
                        if (_okayToDelete) then {
                            if (_isVeh) then {
                                // delete vehicle and all crew/cargo in it
                                private _otherGrps = [];
                                {_otherGrps pushBackUnique group _x} forEach crew _veh;
                                _otherGrps = _otherGrps - [_grp];
                                deleteVehicleCrew _veh;
                                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
                                {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup} forEach _otherGrps;
                                deleteVehicle _veh;
                            } else {
                                // delete the 'on foot' group
                                {deleteVehicle _x} forEach (units _grp);
                                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
                            };
                            continue;
                        } else {
                            _grp setVariable ["ITW_OkayToReset",nil]
                        };
                    };
                };
            };
            
            // group stuck in position check
            _vehiclesProcessed pushBack _veh;
            private _pos = getPosATL _veh;
            private _group = group driver _veh;
            private _wpIdx = currentWaypoint _group;
            if (/*_wpIdx == 0 || */_wpIdx >= count waypoints _group) then {continue};
            private _wpPos = waypointPosition [_group,_wpIdx];
            if (_wpPos isEqualTo [0,0,0] || {_wpPos distance _pos < 50}) then {continue};            
            
            (_veh getVariable ["StuckPos",[0,0,INIT_PREV_POS,0,time]]) params ["_timeout","_maxTime","_prevPos","_stuckCnt","_spawnedTime"];
            if (time >= (_timeout - 1)) then {
                private ["_stuckLimit","_delay"];
                if (_spawnedTime + NEWLY_SPAWNED_TIME > time) then {
                    // new units & vehicles : 20 sec (after 4x as much [80sec] it will be deleted)
                    _stuckLimit = 4;
                    _delay = 20;
                } else {if (_veh == _unit) then {
                    // units : 50 sec (after 6x as much [5min] it will be deleted)
                    _stuckLimit = 6;
                    _delay = 50;
                } else {if (_veh distance _wpPos > (ITW_ParamObjectiveSize + 1000)) then {
                    // veh far from waypoint : 20 sec (after 9x as much [3min] it will be deleted)
                    _stuckLimit = 9;
                    _delay = 20;
                } else {
                    // old vehicles : 1.1 minutes (after 4x as much [5min] it will be deleted)
                    _stuckLimit = 4;
                    _delay = 75;
                }}};
                _timeout = time + _delay;
                _maxTime = _timeout;
                private _minMoveDist = if (_veh isKindOf "Ship") then {10} else {5};
                if (_pos distance _prevPos < _minMoveDist) then {
                    private _nearestPlayer = [_pos,playableUnits] call ITW_FncClosest;
                    private _nearestContestedObj = [getPosATL _unit,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED,true] call ITW_ObjGetNearest;
                    private _inContestedObj = _unit distanceSqr (_nearestContestedObj#ITW_OBJ_POS) < _objSizeSqr;
                    private _pDistSqr = if (_veh == _unit) then {_playerDistUnitSqr} else {_playerDistVehSqr};
                    if (_inContestedObj || {_nearestPlayer distanceSqr _pos < _pDistSqr}) then {
                        // if in contested zone, just bump the unit/leader up in the air a bit
                        if ({isPlayer _x} count crew _veh == 0) then {
                            private _upPos = getPosATL vehicle leader _grp;
                            _upPos set [2,_upPos#2 + 0.25];
                            _veh setPosATL _upPos;
                        };
                        _stuckCnt = 0;                     
                    } else {
                        if ( _stuckCnt > _stuckLimit) then {
                            // no one around and over stuck limit
                            if (_veh isEqualTo _unit) then {    
                                deleteVehicle _unit;
                                if (count units _unitGrp == 0) then {[[_unitGrp],"deleteGroup",_unitGrp] call ITW_FncRemoteLocalGroup};
                            } else {
                                deleteVehicleCrew _veh;
                                deleteVehicle _veh;  
                            };
                        } else {
                            private _newWpGrp = grpNull;
                            if (_veh isEqualTo _unit && {leader _unit == _unit}) then {_newWpGrp = group _unit};
                            if !(_veh isEqualTo _unit) then {_newWpGrp = group driver _veh};
                            if (!isNull _newWpGrp) then {{deleteWaypoint _x} forEachReversed waypoints _newWpGrp};
                            // under stuck limit (or players too nearby)
                            private _isShip = _veh isKindOf "Ship";
                            if (isTouchingGround _veh && !_isShip) then {
                                // land vehicles
                                //if (_veh == _unit && {_stuckCnt < (_stuckLimit/2)}) exitWith {}; // units standing still get longer to get moving
                                private _dist = if (_veh isEqualTo _unit) then {2} else {10};
                                private _handled = false;
                                if !(_veh isEqualTo _unit) then {
                                    // Vehicle
                                    private _advPos = _pos getPos [50,getDir _veh] ;
                                    private _roads = _advPos nearRoads 200;
                                    private _road = [_advPos,_roads] call ITW_FncClosest;
                                    if (!isNull _road) then {
                                        private _roadInfo = getRoadInfo _road;
                                        private _roadPosASL = _roadInfo#6;
                                        _roadPosASL set [2,_roadPosASL#2 + 0.2];
                                        private _dirR = _roadPosASL getDir (_roadInfo#7);
                                        private _dirV = getDir _veh;
                                        private _abs = abs (_dirR - _dirV);
                                        private _angle = _abs min (360 - _abs);
                                        if (_angle > 90) then {
                                            _dirR = _dirR + 180;
                                        };
                                        _veh setDir _dirR;
                                        _veh setPosASL _roadPosASL;
                                        _handled = true;
                                        _pos = getPosATL _veh;
                                   };
                                };
                                if (!_handled) then {
                                    //private _newPos = _pos findEmptyPosition [_dist,200,typeOf _veh]; -- findEmptyPosition causes frame drop
                                    private _newPos = [_pos,_dist,200,sizeOf typeOf _veh,0,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos;
                                    if !(_newPos isEqualTo [0]) then {
                                        _newPos set [2,4];
                                        [_veh,_newPos] call ITW_AtkSafeSetVectorUp;
                                        _pos = getPosATL _veh;
                                    };
                                };
                            } else {  
                                if (_isShip) then {
                                    // ships
                                    //private _newPos = _pos findEmptyPosition [10,200,typeOf _veh]; -- findEmptyPosition causes frame drop
                                    private _newPos = [_pos,10,200,sizeOf typeOf _veh,2,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos;
                                    if !(_newPos isEqualTo [0]) then {
                                        _newPos set [2,0.5];
                                        [_veh,ASLToATL _newPos] call ITW_AtkSafeSetVectorUp;
                                        _pos = getPosASL _veh;
                                    };
                                } else {
                                    if (_veh isKindOf "Helicopter" && {!isTouchingGround _veh}) then {
                                        // airborne helicopters
                                        private _dmgAllowed = isDamageAllowed _veh;
                                        private _curPos = getPosATL _veh;
                                        SEM_LOCK(ITW_AtkFlatPlaceSem);
                                        ALLOW_DAMAGE(_veh,false);
                                        _veh setPosATL ITW_Atk_Flat_Place;
                                        sleep 0.2;
                                        _veh setPosATL _curPos;
                                        if (_dmgAllowed) then {ALLOW_DAMAGE(_veh,true)};
                                        SEM_UNLOCK(ITW_AtkFlatPlaceSem);
                                    } else {
                                        // aircraft (& helis on the ground)
                                        private _newPos = _pos getPos [10,random 360];
                                        _newPos set [2,_pos#2];
                                        _veh setPosATL _newPos;
                                        _pos = getPosATL _veh;
                                    };
                                };
                            };
                        };               
                    };
                    _veh setVariable ["StuckPos",[_timeout,_maxTime,_pos,_stuckCnt + 1,_spawnedTime]];  
                } else {
                    if (_prevPos isEqualTo INIT_PREV_POS) then {
                        // if initial check, then we really haven't moved yet so leave _delay as is
                        _timeout = time + _delay;
                        _maxTime = _timeout;
                    } else {
                        _started = true; // some vehicles have moved so we can wait a while 
                        _timeout = time + AFTER_MOVE_TIME;
                        _maxTime = time + (AFTER_MOVE_TIME*2); // allow a variation in the time to trigger this routine less often
                    };
                    _veh setVariable ["StuckPos",[_timeout,_maxTime,_pos,0,_spawnedTime]];
                };             
            };
            private _timeLeft = _maxTime - time;
            if (_timeLeft < _sleepTime) then {_sleepTime = _timeLeft};
            YIELD_CPU;
            
        } forEach _allUnits; 
                
        private _sleepUntil = time + (if (_started) then {20 max _sleepTime min AFTER_MOVE_TIME} else {20}); 
        while {time < _sleepUntil && {!ITW_AtkNewVehSpawned}} do {sleep 10};
        while {LV_PAUSE} do {sleep 5};
    };
};

ITW_AtkGetInfantryGroups = {
    private _managedGroups = allGroups select {
        private _grp = _x;
        private _leader = leader _grp;
        side _x in [east,west,independent] && {
        count units _grp > 0               && {
        _leader isEqualTo vehicle _leader  && {
        !(_grp call ITW_IsGarrisoned)      && {
        !(_leader getVariable ["LV_PAUSE",false]) && {
        !(_grp getVariable ["itwDelivery",false]) && {
        !(!isNil "IGIT_HCC_HC_Groups_Array" && {_grp in IGIT_HCC_HC_Groups_Array}) && { // // hack for HCC (High Command Converter)
        {isPlayer _x} count units _grp == 0 }}}}}}}
    };    
    _managedGroups
};

ITW_AtkInfantryManager = {
    scriptName "ITW_AtkInfantryManager";
    waitUntil {sleep 1; count call ITW_AtkGetInfantryGroups > 2};
    private _playerSide = ITW_PlayerSide;
    private _enemySide = ITW_EnemySide;
    private _garrisonSafeSize = ITW_ParamObjectiveSize + 300;
    private _minSquadSize = AI_SQUAD_SIZE * 0.75;
    private _tooFarAwayDistSqr = (ITW_ParamObjectiveSize + 2000)^2;
    while {!ITW_GameOver} do {
        while {ITW_ObjZonesUpdating} do {sleep 0.5};
        SEM_LOCK(ITW_AtkInfantryManagerBusy);
        
        // check if any objectives need a garrison
        private _friendlyGarrisonObjs = createHashMap; // array of [objId,#unitsToGarrison]
        private _enemyGarrisonObjs = createHashMap;  
        private _garrisonCreatedMap = createHashMap; // map of [objId,time after which garrison is allowed]
        if (ITW_ParamGarrison > 0) then {
            {
                private _obj = _x;
                private _objPos = _obj#ITW_OBJ_POS;
                private _objIdx = _obj#ITW_OBJ_INDEX;
                private _objIsFriendly = [_objIdx] call ITW_ObjContestedOwnerIsFriendly;
                private _badSide = if (_objIsFriendly) then {_enemySide} else {_playerSide};
                private _safeToGarrison = true;
                {
                    private _grp = _x;
                    if (side _grp == _badSide && {{ALIVE(_x) && {_x distance _objPos < _garrisonSafeSize}} count units _grp > 0}) exitWith {_safeToGarrison = false};
                } forEach call ITW_AtkGetInfantryGroups;
                if (_safeToGarrison) then {
                    private _unitCnt = if (_objIsFriendly && {!isNil "ITW_MaxFriendlyUnits"}) then {ITW_MaxFriendlyUnits} else {ITW_ParamEnemyAiCnt};
                    private _objPerZone = count (ITW_Zones#ITW_ZoneIndex);
                    private _garrisonMaxCnt = 
                        switch (ITW_ParamGarrison) do {
                            case 1: {
                                6 max (_unitCnt/_objPerZone/3) min 18; // 6 to 18 units
                            };
                            case 2: {
                                12 max (_unitCnt/_objPerZone*2/3) min 50; // 12 to 50 units
                            };
                            default {};
                        };
                    private _garrisonCurrSize = [_objPos,if (_objIsFriendly) then {_playerSide} else {_enemySide}] call ITW_GarrisonSize;
                    if (_garrisonCurrSize < _garrisonMaxCnt) then {
                        if (_objIsFriendly) then {
                            _friendlyGarrisonObjs set [_objIdx,_garrisonMaxCnt - _garrisonCurrSize];
                        } else {
                            _enemyGarrisonObjs set [_objIdx,_garrisonMaxCnt - _garrisonCurrSize];
                        };
                    };
                };
            } forEach ([]call ITW_ObjGetContestedObjs);
        };
        
        private _smallGroups = [];
        private _managedGroups = call ITW_AtkGetInfantryGroups;
        {
            private _grp = _x;
            private _grpSize = {alive _x} count units _grp; 
            
            // ignore groups that are entering vehicles via the Ally or Enemy manager
            if (_grp getVariable ["ITW_getInState",-1] != -1) then {continue};
            
            private _leader = leader _grp;
            if (!ALIVE(_leader)) then {
                _alive = units _grp select {ALIVE(_x)};
                if !(_alive isEqualTo []) then {_leader = _alive#0};
            };
            
            // ignore groups in vehicles (they are being managed by the vehicle manager)
            if (vehicle _leader != _leader) then {continue};
            
            // groups that bailed out of their vehicle need to un-assign it and move on
            if !(isNull assignedVehicle _leader) then {{ [_x] remoteExec ["unassignVehicle",_x] } forEach units _grp};
            
            // keep track of small groups so we can join them up
            if (_grpSize < 2 && {vehicle _leader == _leader}) then {
                // ignore groups whose leader is being controlled by DCO Soldier FSM
                private _skipSmallGroupCheck = false;
                if !(isNil "SFSM_fnc_getAction") then {
                    private _action = [_leader] call SFSM_fnc_getAction;
                    if(!isNil "_action" && {_action isNotEqualTo "none"}) then {_skipSmallGroupCheck = true};
                };
                if (!_skipSmallGroupCheck) then {
                    if !(_grp getVariable ["smallGrp",false]) then {
                        _grp setVariable ["smallGrp",true];
                    } else {
                        _smallGroups pushBack _grp;
                    };
                };
            } else {
                _grp setVariable ["smallGrp",nil];
            };
            
            private _objIdx = VAR_GET_OBJ_IDX(_grp);
            if (_objIdx < 0) then {
                [_grp,false] spawn ITW_AtkEngageInfantry;
                continue;
            };
            
            private _obj = ITW_Objectives#_objIdx;
            private _objPt = _obj#ITW_OBJ_POS;
            private _objSize = _obj#ITW_OBJ_SIZE;
            private _dist = _leader distance2D _objPt;
            
            // setup garrisons as needed
            if (ITW_ParamGarrison > 0 && {_dist < _objSize}) then {
                private _isFriendly = side _grp == _playerSide;
                private _garrisonHashMap = if (_isFriendly) then {_friendlyGarrisonObjs} else {_enemyGarrisonObjs};
                private _cnt = _garrisonHashMap getOrDefault [_objIdx,0];
                if (_cnt > 1) then { // not > 0 just to keep from adding a lot when only a few more are allowed
                    if (_garrisonCreatedMap getOrDefault [_objIdx,0] < time) then {
                        // _garrisonCreatedMap ensures we don't re-garrison while the garrison thread is still populating the objective
                        _garrisonHashMap set [_objIdx,_cnt - count units _grp];
                        ITW_DELETE_WAYPOINTS(_grp);
                        [_objPt,_objSize,[_grp],_objIdx] spawn ITW_Garrison;
                        _garrisonCreatedMap set [_objIdx,time + 60];
                        continue;
                    };
                };
            };
            
            // UPDATE WAYPOINTS 
            private _wpIdx = currentWaypoint _grp;
            if (vehicle _leader == _leader &&                                 // not in transit
                  {!VAR_GET_WAIT_TRANSP(_grp) &&                              // not awaiting transport
                  {/*_wpIdx == 0 ||*/ _wpIdx >= count waypoints _grp}}) then {    // not executing any waypoints
                ITW_DELETE_WAYPOINTS(_grp);
                private _wpPos = _leader getPos [0 max (_dist - _objSize),_leader getDir _objPt];
                if (surfaceIsWater _wpPos) then {
                    _wpPos = [_objPt,_objSize] call ITW_AtkWpPoint;
                };              
                private _wp = _grp addWaypoint [_wpPos,0];
                _wp setWaypointBehaviour "AWARE";
                _wp setWaypointSpeed "FULL";
                _wp setWaypointCombatMode "YELLOW";
                _wp setWaypointType "MOVE";
                _wp setWaypointCompletionRadius ITW_ParamTransportUnloadDist;
                _wp setWaypointStatements ["true",format ['
                    if (isNil "thisList") exitWith {};
                    private _grp = group this;
                    if (isNull _grp) exitWith {};
                    {deleteWaypoint _x} forEachReversed waypoints _grp;
                    private _wpPos = [%1,%2] call ITW_AtkWpPoint;
                    private _wp1 = _grp addWaypoint [_wpPos, 0];
                    _wp1 setWaypointBehaviour (if (_grp call ITW_AtkAutoCombatDisabled) then {"AWARE"} else {"COMBAT"});
                    _wp1 setWaypointSpeed "NORMAL";
                    _wp1 setWaypointCombatMode "RED";
                    _wp1 setWaypointType "MOVE"; // was "SAD"
                    _wp1 setWaypointFormation selectRandom ["WEDGE","VEE","STAG COLUMN","DIAMOND"];
                    _wp1 setWaypointCompletionRadius 20;
                    _wp1 setWaypointStatements ["true","
                        if (isNil ""thisList"") exitWith {};
                        private _grp = group this;
                        private _wpPos = [%1,%2] call ITW_AtkWpPoint;
                        [_grp,currentWaypoint _grp] setWaypointPosition [_wpPos,0];
                        [_grp,""ITW_AtkInfantryManager waypoints updated 2"",_wpPos] call ITW_ATK_DEBUG;
                    "];
                    
                    private _wp2 = _grp addWaypoint [%1,0];
                    _wp2 setWaypointType "CYCLE";
                    _wp2 setWaypointCompletionRadius %2;
                ',_objPt,_objSize]];                
                ATK_DEBUG(_grp,"ITW_AtkInfantryManager waypoints updated 0",_wpPos); 
            };
            
            // Limit fleeing
            private _fleeTime = _grp getVariable ["ITW_fleeTimeout",0];
            if (fleeing _leader) then {               
                if (_fleeTime == 0) then {
                    _grp setVariable ["ITW_fleeTimeout",time + FLEE_TIMEOUT];   
                } else {
                    if (time > _fleeTime) then {
                        if (_fleeTime >= 0) then {_grp setVariable ["ITW_fleeTimeout",-(time + FLEE_TIMEOUT)]};
                        ATK_DEBUG("VEHBOARD-FleeMove",_grp,"");                      
                        _grp allowFleeing 0;
                        {_x moveTo getPosATL _x} forEach units _grp;                   
                    };
                };
            } else {
                if (_fleeTime != 0 && {time > -(_fleeTime)}) then {
                    _grp setVariable ["ITW_fleeTimeout",0];
                    _grp allowFleeing (1-UNIT_COURAGE);
                };
            };
            
            // if infantry is way too far from their objective, move them closer
            if (leader _grp distanceSqr _objPt > _tooFarAwayDistSqr) then {
                private _farTime = _grp getVariable ["ITW_FarTime",-1];
                if (_farTime == -1) then {
                    _farTime = time;
                    _grp setVariable ["ITW_FarTime",_farTime];
                };
                if (time - _farTime > 30) then {
                    _grp setVariable ["ITW_FarTime",nil];
                    [_grp,_objPt] spawn ITW_AtkInfantryMoveUp;
                };
            };
        } forEach _managedGroups;
        
        // Merge small groups into other groups
        if (count _smallGroups >= _minSquadSize) then {
            private _grpsF = _smallGroups select {GRP_IS_FRIENDLY(_x)};
            private _grpsE = _smallGroups select {!GRP_IS_FRIENDLY(_x)};
            while {count _grpsF >= _minSquadSize} do {
                private _newSqaud = _grpsF select [0,_minSquadSize];
                _grpsF = _grpsF - _newSqaud;
                _newSqaud joinSilent (_newSqaud#0);
            };
            while {count _grpsE >= _minSquadSize} do {
                private _newSqaud = _grpsE select [0,_minSquadSize];
                _grpsE = _grpsE - _newSqaud;
                _newSqaud joinSilent (_newSqaud#0);
            };
            _smallGroups = _grpsF + _grpsE
        };
        {
            private _grp = _x;
            private _side = side _grp;
            private _unitCnt = {ALIVE(_x)} count units _grp;
            private _otherSquads = (_managedGroups select {side _x == _side}) - [_grp];
            private _nearestSquad = [_otherSquads, getPosATL leader _grp] call BIS_fnc_nearestPosition;
            if (typeName _nearestSquad == "GROUP" && {getPosATL leader _nearestSquad distance leader _grp < 800}) then {
                units _grp joinSilent _nearestSquad;
                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
            };
        } forEach _smallGroups;
        
        SEM_UNLOCK(ITW_AtkInfantryManagerBusy);
        
        //// slowly damage any unit in the other teams zones so they eventually die if stuck there
        //{
        //    private _unit = _x;
        //    if (isPlayer _unit || {side _unit == civilian || {_unit isKindOf "LOGIC"}}) then {continue}; // players don't take damage
        //    if (!isDamageAllowed _unit) then {[_unit,true] remoteExec ["allowDamage",_unit]}; // Hack for: every once in a while I'm seeing units not allowing damage only on server
        //    if (!(vehicle _unit isEqualTo _unit) && {abs (speed vehicle _unit) > 1}) then {continue}; // moving vehicles get a break
        //    private _pos = getPosATL _unit;
        //    private _isFriendly = GRP_IS_FRIENDLY(_x);
        //    private _nearestContestedObj = [_pos,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest;
        //    if (_nearestContestedObj#ITW_OBJ_POS distanceSqr _pos > ITW_ZoneKeepOutSqr) then {
        //        private _nearestObj = [_pos,if (_isFriendly) then {ITW_OWNER_ENEMY} else {ITW_OWNER_FRIENDLY}] call ITW_ObjGetNearest;
        //        private _nearestBase = ITW_Bases#(_nearestObj#ITW_OBJ_INDEX);
        //        if (_nearestBase#ITW_BASE_POS distanceSqr _pos < ITW_ZoneKeepOutSqr) then {_unit setDamage (damage _unit + 0.1)}; // die in 5 minutes
        //    }; 
        //} count allUnits;
        sleep 30;
        while {LV_PAUSE} do {sleep 5};
    };
};
    
ITW_AtkWpPoint = {
    params ["_center","_size",["_vehType",ITW_TYPE_VEH_INFANTRY],["_innerClearSize",0]];
    //_vehType ITW_TYPE_VEH_INFANTRY for infantry
    private "_blacklist";
    switch (true) do {
        case ITW_VEH_IS_SEA(_vehType): {_blacklist = ["ground"]};
        case ITW_VEH_IS_AIR(_vehType): {_blacklist = []};
        default                        {_blacklist = ["water"]}; // land veh or infantry
    };
    if (_innerClearSize > 0) then {_blacklist pushBack [_center,_innerClearSize]};
    private _wpPos = [[[_center,_size]],_blacklist] call BIS_fnc_randomPos;
    if (_wpPos isEqualTo [0,0]) then {
        _wpPos = _center;
        if (ITW_VEH_IS_SEA(_vehType)) then {
            private _obj = [_center,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED,true] call ITW_ObjGetNearest;
            if !(_obj isEqualTo []) then {
                private _index = _obj#ITW_OBJ_INDEX;
                private _seaPts = if (count ITW_SeaPoints > _index) then {ITW_SeaPoints#_index} else {[]};
                if !(_seaPts isEqualTo []) then {
                    _wpPos = selectRandom _seaPts;
                };
            };
        };
    };
    _wpPos;
};

ITW_AtkInfantryMoveUp = {
    params ["_group","_toPos"];
    // move group to position near objective
    private _isAllLandFn = {
        // check if there is water in a line from _pos along _dir
        params ["_pos","_dir","_objSize","_dist"];
        private _okay = true;
        for "_r" from _objSize to _dist step 5 do {
            if (getTerrainHeight (_pos getPos [_r,_dir]) < -0.4) exitWith {_okay = false}; 
        };
        _okay
    };
    private _playerSpaceSqr = if (side _group == ITW_PlayerSide) then {4e4 /*200m*/} else {2.5e5 /*400m*/};
    
    // if players near the group, just leave them where they are
    private _nearestPlayer = [allPlayers, getPosATL leader _group] call BIS_fnc_nearestPosition;
    if (_nearestPlayer distanceSqr leader _group > 2.5e5 /*500m*/) then {        
        private _enemySpaceSqr = 9e4 /*300m*/;
        private _cnt = 50;
        private _pos = [];
        private _enemySide = if (side _group == ITW_PlayerSide) then {ITW_EnemySide} else {ITW_PlayerSide};
        private _enemies = allUnits select {side _x == _enemySide};
        private _fromPos = getPosATL leader _group;
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            // _dir is on the side near the units bases, unless we're having trouble finding a spawn point, then use anywhere around objective
            private _dir = (_toPos getDir _fromPos) + (
                switch (true) do {
                    case (_cnt > 40): {-10 + random 20};
                    case (_cnt > 30): {-30 + random 60};
                    case (_cnt > 20): {-60 + random 120};
                    case (_cnt > 10): {-90 + random 180};
                    default           {random 360};
                }
            );
            private _dist = ITW_ParamObjectiveSize + 500 + random 1000;
            if ([_toPos,_dir,ITW_ParamObjectiveSize,_dist] call _isAllLandFn) then {
                _pos = _toPos getPos [_dist,_dir];
                private _closestEnemyObj = [_pos,ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
                private _nearestBase = ITW_Bases#(_closestEnemyObj#ITW_OBJ_INDEX);
                if (_pos distanceSqr (_nearestBase#ITW_BASE_POS) < ITW_ZoneKeepOutSqr) then {_pos = []};
                if !(_pos isEqualTo []) then {
                    private _nearestEnemy = [_enemies, _pos] call BIS_fnc_nearestPosition;
                    if (_nearestEnemy distanceSqr _pos < _enemySpaceSqr) then {_pos = []};
                };
                if !(_pos isEqualTo []) then {
                    private _nearestPlayer = [allPlayers, _pos] call BIS_fnc_nearestPosition;
                    if (_nearestPlayer distanceSqr _pos < _playerSpaceSqr) then {_pos = []};
                };
            } else {
                _pos = [];
            };
            sleep 0.01; // don't monopolize the cpu
        };
        
        // if failed to find, try again with looser restrictions.  We really need a pos here.
        _cnt = 50;
        _enemySpaceSqr = _enemySpaceSqr/2;
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            // _dir is on the side near the units bases, unless we're having trouble finding a spawn point, then use anywher around objective
            private _dir = random 360;
            private _dist = ITW_ParamObjectiveSize + 500 + random 1000;
            _pos = _toPos getPos [_dist,_dir];
            if (!surfaceIsWater _pos) then {
                private _nearestEnemy = [_enemies, _pos] call BIS_fnc_nearestPosition;
                if (_nearestEnemy distanceSqr _pos < _enemySpaceSqr) then {_pos = []};
                if !(_pos isEqualTo []) then {
                    private _nearestPlayer = [allPlayers, _pos] call BIS_fnc_nearestPosition;
                    if (_nearestPlayer distanceSqr _pos < _playerSpaceSqr) then {_pos = []};
                };
            } else {
                _pos = [];
            };
            sleep 0.01; // don't monopolize the cpu
        };
        
        if !(_pos isEqualTo []) then {
            [[_group,_pos],"ITW_AtkSafeMove",_group] call ITW_FncRemoteLocalGroup;
            sleep 0.1;
            {deleteWaypoint _x} forEachReversed waypoints _group;
            private _wpPos = _toPos getPos [ITW_ParamObjectiveSize - 100,_toPos getDir _pos];
            _group addWaypoint [_wpPos,0];
            ATK_DEBUG(_group,"ITW_AtkInfantryMoveUp waypoints updated",_wpPos); 
        };
    };
};

ITW_AtkTranspSuccess = {
    params ["_isFriendly",["_success",0]];
    ATK_DEBUG("ITW_AtkTranspSuccess",_isFriendly,_success);
    if (!isServer) exitWith {};
    if (typeName _isFriendly != "BOOL") exitWith {};
    // returns the succcess rate as a percentage between 0 and 100 (or -1 if not enough data yet)
    // _success: BOOL = set that a transport was successful or not
    //           SCALAR = return -1 (decrease range), +1 increase range, or 0 leave range as is
    //           STRING = reset the arrays
    #define TS_ARRAY_SIZE     5 // number of previous success/failure checks monitored
    #define TW_INCREASE_FAILS 2 // min number of failures which triggers range increase
    #define TW_DECREASE_FAILS 0 // max number of failures which triggers range decrease
    
    if (isNil "ITW_atkTranspSuccessSEM") then {ITW_atkTranspSuccessSEM = false};
    SEM_LOCK(ITW_atkTranspSuccessSEM);
    private _which = if (_isFriendly) then {ATTACK_FRIENDLY} else {ATTACK_ENEMY};
    
    if (isNil "ITW_atkTranspSuccessRate") then {
        ITW_atkTranspSuccessRate = [[],[]];
    };
    
    if (typeName _success isEqualTo "STRING") then {
        ITW_atkTranspSuccessRate set [_which,[]];
    };
    
    private _data = ITW_atkTranspSuccessRate#_which;
    if (typeName _success == "BOOL") then {
        if (count _data >= TS_ARRAY_SIZE) then {_data deleteAt 0};
        _data pushBack _success;
    };
    
    private _return = 0;
    if (typeName _success == "SCALAR") then {
        private _cntFailures = {!_x} count _data;
        if (_cntFailures >= TW_INCREASE_FAILS) then {
            _return = +1;
            ITW_atkTranspSuccessRate set [_which,[]];
        } else {
            if (count _data == TS_ARRAY_SIZE && {_cntFailures <= TW_DECREASE_FAILS}) then {
                _return = -1;
                ITW_atkTranspSuccessRate set [_which,[]];
            };
        };
    };
    SEM_UNLOCK(ITW_atkTranspSuccessSEM);
    
    ATK_DEBUG("ITW_AtkTranspSuccess return",_return,ITW_atkTranspSuccessRate);
    _return
};

ITW_AtkVehicleManager = {
    scriptName "ITW_AtkVehicleManager";
    private _zoneIndex = ITW_ZoneIndex; 
    private _sleepCnt = 0;
    private _sadCheckTime = 0;
    private _sadTrigger = false;
    private _unloadDistAdjustment = [0,0]; // [friendly,enemy] a number >= 0, gets larger as transports are destroyed
    private _unloadDistance = ITW_ParamObjectiveSize + ITW_ParamTransportUnloadDist;
    private _unloadDistanceAir = _unloadDistance + 600;
    private _unloadDistanceSea = _unloadDistance + 300;
    private _heliSlowDist0 = _unloadDistanceAir + 300;
    private _heliSlowDist1 = _unloadDistanceAir + 500;
    private _heliSlowDist2 = _unloadDistanceAir + 1000;
    private _heliSlowDist3 = _unloadDistanceAir + 1500;
    private _heliSlowDist4 = _unloadDistanceAir + 2000;
    private _heliSlowDist5 = _unloadDistanceAir + 2500;
    private _heliSlowDist6 = _unloadDistanceAir + 3000;
    private _cleanupDist = if (ITW_ParamCleanupDelay < 120) then {200} else {1500};
    private _travelHdlrDist = ITW_ParamObjectiveSize + 300;
    private _returningVehicles = [];
    #define UNLOAD_DIST_ADJ_TIMEOUT 30
    #define UNLOAD_OFFSET 100
    private _unloadDistChecked = [time + UNLOAD_DIST_ADJ_TIMEOUT,time + UNLOAD_DIST_ADJ_TIMEOUT];
    while {!ITW_GameOver} do {
        while {LV_PAUSE} do {sleep 5};
        while {ITW_ObjZonesUpdating} do {sleep 0.5};
        if (_zoneIndex != ITW_ZoneIndex) then {
            _zoneIndex = ITW_ZoneIndex;
            _unloadDistAdjustment = [0,0];
        };
        SEM_LOCK(ITW_AtkVehicleManagerBusy);
        private _removeVehs = [];
        private _aircraft = [];
        private _managedVehs = ITW_ManagedVehs;
        {
            private _vehInfo = _x;
            _vehInfo params ["_type","_role","_veh","_grp","_cargoGroups","_fromPos"];
            private _vehStartSafe = _veh getVariable ["ITW_VehStartSafe",[]];
            if !(_vehStartSafe isEqualTo []) then {
                _vehStartSafe params ["_startPos","_startTime"];
                if (_veh distance _startPos > 50 || time > _startTime) then {
                    _veh setVariable ["ITW_VehStartSafe",nil];
                    ALLOW_DAMAGE(_veh,true);
                    private _crewGrps = crew _veh apply {group _x};
                    _crewGrps = (_crewGrps arrayIntersect _crewGrps) - [grpNull];
                    if !(_crewGrps isEqualTo []) then {
                        [_crewGrps,true] call ITW_AtkSafeGroupAllowDamage;
                    };
                };
            };
            
            private _aliveCrew = units _grp select {ALIVE(_x)};
            private _isFriendly = side _grp == ITW_PlayerSide;
            
            // remove empty & broken vehicles from the manager
            if (_aliveCrew isEqualTo [] || {!canMove _veh || {fuel _veh == 0}}) then {
                if (isTouchingGround _veh || {(getPos _veh)#2 < 5}) then { // getPos to handle on water or land
                    _removeVehs pushBack _vehInfo; 
                    {_x leaveVehicle _veh; [_x] remoteExec ["unassignVehicle",_x]} forEach crew _veh;
                    _veh setVariable ["ITW_CleanupVeh",true];
                    _veh setVariable ["ITW_VehDef",nil];
                };
                continue;
            };
            
            private _objIdx = VAR_GET_OBJ_IDX(_grp);
            if (_objIdx < 0) then {
                [_vehInfo,false,false] call ITW_AtkEngageVehicle;
                continue;
            };
            
            // reassign leader if needed
            private _leader = leader _grp;
            if (!ALIVE(_leader)) then {
                if !(_aliveCrew isEqualTo []) then {_leader = _aliveCrew#0};
            };
            
            // if driver is dead, move other crew into driver seat
            if (! ALIVE(driver _veh) && {!(_aliveCrew isEqualTo [])}) then {
                private _newDriver = _aliveCrew#-1;
                moveOut _newDriver;
                _newDriver moveInDriver _veh;
            };
            
            private _obj = ITW_Objectives#_objIdx;
            private _objPt = _obj#ITW_OBJ_POS;
            private _objSize = _obj#ITW_OBJ_SIZE;
            
            // unload cargo
            if !(_cargoGroups isEqualTo []) then {
                private _unloadCargoTime = _veh getVariable ["UnloadingCargoTime",1e5];
                if (_unloadCargoTime < 1e4) then {
                    private _cargoStillIn = false;
                    {{if (_cargoStillIn || {alive _x && {vehicle _x == _veh}}) exitWith {_cargoStillIn = true}} forEach (units _x)} forEach _cargoGroups;
                    if (!_cargoStillIn && {{isPlayer _x && {!(driver _veh == _x)}} count crew _veh > 0}) then {_cargoStillIn = true};
                    if !(_cargoStillIn) then {
                        ATK_DEBUG("VEH UNLOADED",_veh,_type);  
                        _veh removeMPEventHandler ["MPKilled",_veh getVariable ["itwKilledEH",-1]];
                        [_isFriendly,true] call ITW_AtkTranspSuccess;
                        _vehInfo set [VEHINFO_CARGO_GRPS,[]];
                        _veh setVariable ["UnloadingCargoTime",nil];
                        if (_veh isKindOf "Helicopter") then {
                            _veh limitSpeed 500;
                            _veh flyInHeight 30;
                        };
                        // unloaded units can get stuck after unload, so speed up their 'stuck' settings
                        _cargoGroups spawn {
                            scriptName "ITW_AtkVeh:unloadUnstuck";
                            sleep 10;
                            {
                                private _grp = _x;
                                {
                                    _x setVariable ["StuckPos",nil];
                                    _x doMove getPosATL _x;
                                    _x doFollow leader _x;
                                } forEach units _grp;
                            } forEach _this;
                        };
                    } else {
                        if (time > _unloadCargoTime && {isTouchingGround _veh}) then {
                            // units haven't unloaded after too long, eject them
                            {_x leaveVehicle _veh} forEach _cargoGroups;
                        };
                    };
                    continue
                } else {
                    private _distToAo = _veh distance _objPt;
                    private _unloadDist = switch (true) do {
                        case (_veh isKindOf "Air"): {_unloadDistanceAir};
                        case (_veh isKindOf "Ship"): {_unloadDistanceSea};
                        default {_unloadDistance + 250 - random 50}; // random so long line of vehs stop at different distances, add a couple 100m since only check every 8 seconds
                    };
                    
                    if !(ITW_defendRunning) then {
                        // Transport unload distance adjustment (not during defend phase)
                        private _which = if (_isFriendly) then [{ATTACK_FRIENDLY},{ATTACK_ENEMY}];
                        if (_unloadDistChecked#_which < time) then {
                            // check if transport unload distance needs adjustment
                            _unloadDistChecked set [_which,time + UNLOAD_DIST_ADJ_TIMEOUT];
                            switch ([_isFriendly] call ITW_AtkTranspSuccess) do {
                                case -1: { // decrease range
                                    _unloadDistAdjustment set [_which,(_unloadDistAdjustment#_which - UNLOAD_OFFSET) max 0];
                                    diag_log format ["ITW Attack transport unload distance decreased. Friendly:%1 Offset:%2",_isFriendly,_unloadDistAdjustment];
                                };
                                case 0: {}; // leave range as it
                                case 1: { // increase range
                                    _unloadDistAdjustment set [_which,(_unloadDistAdjustment#_which + UNLOAD_OFFSET) min 500];
                                    diag_log format ["ITW Attack transport unload distance increased. Friendly:%1 Offset:%2",_isFriendly,_unloadDistAdjustment];
                                };
                            };
                        };
                        _unloadDist = _unloadDist + (_unloadDistAdjustment#_which);
                    };
                    
                    if (currentWaypoint _grp >= count waypoints _grp) then {_unloadDist = 100000};// not executing any waypoints, so trigger unload
                    if (_distToAo < _unloadDist) then {
                        ATK_DEBUG("VEH UNLOAD",_veh,_type);                    
                        switch (_type) do {
                            case ITW_TYPE_VEH_AIRPLANE: { [_veh,_grp,_cargoGroups,_objPt] spawn ITW_AtkUnloadAirplane};
                            case ITW_TYPE_VEH_HELI    : { [_veh,_grp,_cargoGroups,_objPt] spawn ITW_AtkUnloadHeli    };
                            case ITW_TYPE_VEH_SHIP    : { [_veh,_grp,_cargoGroups,_objPt,_objSize] spawn ITW_AtkUnloadShip};
                            default                     { [_veh,_grp,_cargoGroups,_objPt] spawn ITW_AtkUnloadLand    };
                        };
                        _veh setVariable ["UnloadingCargoTime",time + 120];
                        continue
                    } else {
                        if (_veh isKindOf "Helicopter") then {
                            // helicopters need to slow down as they get close
                            private ["_speed","_height"];
                            switch (true) do {
                                case (_distToAo < _heliSlowDist0): {_speed =  80;_height = 10};  // < 300
                                case (_distToAo < _heliSlowDist1): {_speed =  90;_height = 11};  // < 500
                                case (_distToAo < _heliSlowDist2): {_speed = 110;_height = 16};  // < 1000
                                case (_distToAo < _heliSlowDist3): {_speed = 150;_height = 23};  // < 1500
                                case (_distToAo < _heliSlowDist4): {_speed = 190;_height = 30};  // < 2000
                                case (_distToAo < _heliSlowDist5): {_speed = 230;_height = 37};  // < 2500
                                case (_distToAo < _heliSlowDist6): {_speed = 270;_height = 44};  // < 3000
                                default                            {_speed = 500;_height = 50};  // >= 3000
                            };                          
                            _veh limitSpeed _speed;
                            _veh flyInHeight _height;
                        };
                        // if cargo got out on their own...
                        private _grpsNoLongerInVeh = _cargoGroups select {{alive _x && {vehicle _x == _veh}} count units _x == 0};
                        _grpsNoLongerInVeh = _grpsNoLongerInVeh - [grpNull]; // grpNull indicates players joined the wave in this vehicle
                        if !(_grpsNoLongerInVeh isEqualTo []) then {
                            _cargoGroups = _cargoGroups - _grpsNoLongerInVeh;
                            _vehInfo set [VEHINFO_CARGO_GRPS,_cargoGroups];
                        };
                    };
                };
            
                // transports need to keep moving even if enemy are around, so forget further out enemy
                private _driver = driver _veh;
                _driver targets [true] select {_veh distance _x > 500} apply {_driver forgetTarget _x};
            };
            
            // transports and attack vehicles w/o ammo need to vacate the area after unloading
            private _driverGrp = group driver _veh;
            private _transportDone = (_role == ITW_VEH_ROLE_TRANSPORT) && {_cargoGroups isEqualTo []};
            private _attackDone = (_role != ITW_VEH_ROLE_TRANSPORT) && 
                                        {_cargoGroups isEqualTo [] && 
                                        {{_x#1 > 0} count magazinesAmmo [_veh, false] == 0}};
            private _dualTransDone = (_role == ITW_VEH_ROLE_DUAL) && {_cargoGroups isEqualTo [] && {waypointType [_driverGrp, currentWaypoint _driverGrp] isEqualTo "TR UNLOAD"}};
            if (_dualTransDone) then {{deleteWaypoint _x} forEachReversed waypoints _driverGrp};
            if (_transportDone && {_veh isKindOf "Land"}) then {
                private _transWaitTimeout = _veh getVariable ["ITW_transportWaitTO",-1];
                if (_transWaitTimeout < 0) then {
                    _transWaitTimeout = time + 20;
                    _veh setVariable ["ITW_transportWaitTO",_transWaitTimeout];
                };           
                if (time >= _transWaitTimeout) then {
                    _veh setVariable ["ITW_transportWaitTO",nil];
                } else {
                    _transportDone = false;
                };
            };
            if (_transportDone || _attackDone) then {
                private _extraGroupsInCargo = [];
                crew _veh select {alive _x && {group _x != _grp}} apply {_extraGroupsInCargo pushBackUnique group _x};
                if !(_extraGroupsInCargo isEqualTo []) then {
                    {ITW_DELETE_WAYPOINTS(_x)} forEach _extraGroupsInCargo;
                    _cargoGroups = _extraGroupsInCargo;
                    _role = ITW_VEH_ROLE_TRANSPORT;
                    _vehInfo set [VEHINFO_CARGO_GRPS,_cargoGroups];
                    _vehInfo set [VEHINFO_ROLE,_role];
                } else {
                    ATK_DEBUG("VEH Atk/Trans Done",_grp,"");
                    _vehInfo set [VEHINFO_ROLE,ITW_VEH_ROLE_COMPLETE];
                    _role = ITW_VEH_ROLE_COMPLETE;
                    ITW_DELETE_WAYPOINTS(_grp);
                    _removeVehs pushBack _vehInfo;
                    if (_fromPos isEqualTo [0,0,0]) then {_fromPos = ([getPosATL _veh,if (GRP_IS_FRIENDLY(_grp)) then {ITW_OWNER_FRIENDLY} else {ITW_OWNER_ENEMY}] call ITW_ObjGetNearest)#ITW_OBJ_POS};
                    private _wp1 = _grp addWaypoint [_fromPos,0];
                    _wp1 setWaypointBehaviour "CARELESS";
                    _wp1 setWaypointSpeed "FULL";
                    _wp1 setWaypointCombatMode "YELLOW";
                    _wp1 setWaypointType "MOVE";
                    _wp1 setWaypointCompletionRadius 220;                 
                    if (_veh isKindOf "Air") then {
                        // aircraft can fly right to a good despawn position
                        _wp1 setWaypointStatements ["true", 
                                'if (isServer) then {                      
                                    private _veh = vehicle this;
                                    private _grp = group (crew _veh #0);
                                    deleteVehicleCrew _veh;
                                    deleteVehicle _veh;
                                    if (!isNil "_grp" && {count units _grp == 0}) then {[[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup};
                                }']; 
                    } else {
                        if (ITW_ParamDespawnTransports == 1) then {
                            deleteVehicleCrew _veh;
                            deleteVehicle _veh;
                        };
                        // land vehicles need to drive back to their spawn point
                        // and then drive a bit further if possible
                        _wp1 setWaypointStatements ["true", 
                            'if (isServer) then {
                                this spawn {
                                    scriptName "ITW_AtkVehicleManager - transport return";
                                    private _veh = vehicle _this;
                                    sleep 30;
                                    private _grp = group (crew _veh #0);
                                    deleteVehicleCrew _veh;
                                    deleteVehicle _veh;
                                    if (!isNil "_grp" && {count units _grp == 0}) then {[[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup};
                                };
                            }']; 
                        private _wp2 = _grp addWaypoint [_fromPos getPos [1000,getPosATL _veh getDir _fromPos],0];
                        _wp2 setWaypointType "MOVE";
                        _wp2 setWaypointCompletionRadius 210;
                    };
                    _returningVehicles pushBack [_veh,time + 180];
                    ATK_DEBUG(_grp,"ITW_AtkVehicleManager waypoints updated withdraw",_fromPos); 
                    continue;
                };
            };
            
            // I've seen vehicles with SAD waypoints search for a while then just sit still, so give them a push
            if (_sadTrigger) then {
                private _wpIdx = currentWaypoint _grp;
                if (waypointType [_grp,_wpIdx] == "SAD") then {
                    private _prevPos = _veh getVariable ["itwSadStuck",[0,0,0]];
                    private _currentPos = getPosASL _veh;
                    if (_prevPos distance _currentPos < 20) then {
                        ITW_DELETE_WAYPOINTS(_grp);
                        YIELD_CPU;
                    };
                    _veh setVariable ["itwSadStuck",_currentPos];
                };
            };
            
            // UPDATE WAYPOINTS  
            private _wpIdx = currentWaypoint _grp;
            if (/*_wpIdx == 0 || {*/_wpIdx >= count waypoints _grp/*}*/) then {    // not executing any waypoints
                if (!(_cargoGroups isEqualTo []) || {(_veh getVariable ["ITW_transportWaitTO",0]) != 0 || {_veh getVariable ["UnloadingCargoTime",1e5] < 1e4}}) exitWith {}; // unloading vehs need to stay until unloaded
                ITW_DELETE_WAYPOINTS(_grp);
                private _dist = _leader distance2D _objPt;
                private "_wpPos";
                if (ITW_VEH_IS_SEA(_type)) then {
                    _wpPos = selectRandom (ITW_SeaPoints#_objIdx);
                    if (isNil "_wpPos") then {_wpPos = [_objPt,_objSize,_type] call ITW_AtkWpPoint};
                } else {
                    _wpPos = _leader getPos [0 max (_dist - _objSize),_leader getDir _objPt];
                };
                private _moveType = if (ITW_ParamAggressivePlanes == 1 && {_veh isKindOf "PLANE"}) then {"MOVE"} else {"SAD"}; // planes don't do SAD very well
                private _wp = _grp addWaypoint [_wpPos,0];
                _wp setWaypointBehaviour (if (_veh isKindOf "Air") then {"COMBAT"} else {"AWARE"});
                _wp setWaypointSpeed "FULL";
                _wp setWaypointCombatMode (if (_veh isKindOf "Air") then {"RED"} else {"YELLOW"});
                _wp setWaypointType "MOVE";
                _wp setWaypointCompletionRadius 500;
                _wp setWaypointStatements ["true",format ['
                    if (isNil "thisList") exitWith {};
                    private _grp = group this;
                    if (isNull _grp) exitWith {};
                    {deleteWaypoint _x} forEachReversed waypoints _grp;
                    private _wpPos = [%1,%2,%3] call ITW_AtkWpPoint;
                    private _wp1 = _grp addWaypoint [_wpPos, 0];
                    _wp1 setWaypointBehaviour "COMBAT";
                    _wp1 setWaypointSpeed "NORMAL";
                    _wp1 setWaypointCombatMode "RED";
                    _wp1 setWaypointType "%4";
                    _wp1 setWaypointCompletionRadius 30;
                    _wp1 setWaypointStatements ["true","
                        if (isNil ""thisList"") exitWith {};
                        private _grp = group this;
                        private _wpPos = [%1,%2,%3] call ITW_AtkWpPoint;
                        [_grp,currentWaypoint _grp] setWaypointPosition [_wpPos,0];
                        [_grp,""ITW_AtkVehicleManager waypoints updated 2"",_wpPos] call ITW_ATK_DEBUG;
                        "];
                    ATK_DEBUG(_grp,"ITW_AtkVehicleManager waypoints updated 1",_wpPos); 
                    
                    private _wp2 = _grp addWaypoint [%1,0];
                    _wp2 setWaypointType "CYCLE";
                    _wp2 setWaypointCompletionRadius %2;
                ',_objPt,_objSize,_type,_moveType]];             
                ATK_DEBUG(_grp,"ITW_AtkVehicleManager waypoints updated 0",_wpPos); 
                _wpIdx = currentWaypoint _grp;
                _grp setCombatMode "RED";
            };
            
            // Travel handler - slow down/speed up vehicles if vehicles in their way
            if (_veh distance _objPt > _travelHdlrDist) then {
                _wpPos = waypointPosition [_grp,_wpIdx];
                if !(_wpPos isEqualTo [0,0,0] || {_wpPos distance _veh < 300}) then {
                    private _frontPos = _veh getPos [102,getDir _veh];
                    // if veh within 100m in front, then slow down
                    if ({(_x#VEHINFO_VEH) distance _frontPos < 100} count _managedVehs > 0) then {
                        _grp setSpeedMode "LIMITED";
                    } else {
                        _grp setSpeedMode "FULL";
                    };
                };
            };   
            
            if (_veh isKindOf "Air") then {_aircraft pushBack _veh};
        } forEach _managedVehs;

        _sadTrigger = false;
        if (time > _sadCheckTime) then {
            _sadCheckTime = time + 60;
            _sadTrigger = true;
        };
        
        // remove dead groups
        if !(_removeVehs isEqualTo []) then {ITW_ManagedVehs = ITW_ManagedVehs - _removeVehs};
        
        // remove returning vehicles that haven't made it back
        {
            _x params ["_veh","_timeout"];
            if (isNull _veh) then {
                _returningVehicles deleteAt _forEachIndex
            } else {
                if (time > _timeout) then {
                    private _grp = group (crew _veh #0);
                    deleteVehicleCrew _veh;
                    deleteVehicle _veh;
                    if (!isNil "_grp" && {count units _grp == 0}) then {[[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup};
                };
            };
        } forEachReversed _returningVehicles;
        
        SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
        
        // SLEEP
        private _sleepTime = 8;
        if (_aircraft isEqualTo []) then {sleep _sleepTime} else {
            // while sleeping, check if any aircraft crew need to eject
            for "_i" from 1 to _sleepTime step 1 do {
                sleep 1;
                while {LV_PAUSE} do {sleep 5};
                private _aircraftUnloaded = [];
                {
                    private _veh = _x;
                    if ((isNull (currentPilot _veh) || {!canMove _veh || fuel _veh == 0}) && {getPosATL _veh #2 > 50}) then {
                        // use airplane unload even for helis if they are crashing
                        private _groups = crew _veh select {alive _x} apply {group _x};
                        [_veh,grpNull,_groups arrayIntersect _groups,getPosATL _veh] spawn ITW_AtkUnloadAirplane;
                        _aircraftUnloaded pushBack _veh;
                    };
                    false
                } forEach _aircraft;
                if !(_aircraftUnloaded isEqualTo []) then {_aircraft = _aircraft - _aircraftUnloaded};
            };
        };
        while {ITW_ObjZonesUpdating} do {sleep 0.5};
        
        // Update some things every 30 seconds: count and dead vehicles, SAD vehicles not moving
        _sleepCnt = _sleepCnt + _sleepTime;
        if (_sleepCnt >= 30) then {
            _sleepCnt = 0;
            ITW_VehArraysUpdating = true;
            ITW_VehArrays apply {_x set [ITW_VEH_COUNT,0]};
            if (ITW_ParamCleanupDelay > 0) then {
                {
                    private _veh = _x;
                    if (_veh in ITW_Statics) then {continue};
                    if (_veh getVariable ["persistent",false]) then {continue};
                    if (_veh isKindOf "AllVehicles") then {
                        _cleanUp = _veh getVariable ["ITW_CleanupVeh",false];
                        if (_cleanUp && {{isPlayer _x} count crew _veh > 0}) then {_veh setVariable ["ITW_CleanupVeh",false]};
                        
                        // alive but empty vehicles are 'disableSimulation'ed in ITW_Vehicles
                        if (!alive _veh || {!canMove _veh || {fuel _veh == 0 || {_cleanUp}}}) then {
                            if (_veh getVariable ["ITW_CleanupTime",0] == 0) then {
                                _veh setVariable ["ITW_CleanupTime",time + 200];
                            } else {
                                if (_veh getVariable ["ITW_CleanupTime",1e10] < time) then {
                                    private _remove = true;
                                    {
                                        private _dist = _veh distance _x;
                                        if (_dist < _cleanupDist) exitWith {_remove = false};
                                    } forEach (allPlayers - HeadlessClients);
                                    if (_remove) then {
                                        deleteVehicle _veh;
                                    };
                                };
                            };
                        } else {
                            _veh setVariable ["ITW_CleanupTime",nil];
                            private _vehDef = _veh getVariable ["ITW_VehDef",[]];
                            if !(_vehDef isEqualTo []) then {
                                ITW_VEH_COUNT_INCR(_vehDef);
                            };
                        };
                    };
                } forEach vehicles;   
            };
            ITW_VehArraysUpdating = false;
        };
        
    };
};

ITW_AtkGetOverflowTeammateJoinWave = {
    params ["_crew"];
    private _overflow = [];
    private _players = _crew select {isPlayer _x};
    if (_players isNotEqualTo []) then {
        {
            private _player = _x;
            private _dataIdx = ITW_AtkTeammatesJoinWave findIf {_x#0 == _player};
            if (_dataIdx >= 0) then {
                private _data = ITW_AtkTeammatesJoinWave deleteAt _dataIdx;
                private _teammates = _data#1;
                if (_teammates isNotEqualTo []) then {_overflow append _teammates};
            };
        } forEach _players;
    };
    _overflow
};

ITW_AtkUnloadPlayerTeammates = {
    // give a list of players, waits until those players exit a vehicle, and then unloads any teammates in the same vehicle
    // this is needed since TR ULOAD will not unload player's teammates as Arma expects the player to unload them
    // call this code, don't spawn it.  It will spawn a task to do the unload if needed
    params ["_players",["_timeout",1e4]];
    if (_players isEqualTo []) exitWith {};
    private _teammates = [];
    {
        private _player = _x;
        private _veh = vehicle _player;
        if (_veh == _player) then {continue};
        private _units = units _player select {!isPlayer _x && {vehicle _x == _veh}};
        if (_units isNotEqualTo []) then {
            _teammates pushBack [_player,_units];
        };
    } forEach _players;
    if (_teammates isEqualTo []) exitWith {};
    [_teammates,_timeout] spawn {
        params ["_teammates","_timeout"];
        scriptName "ITW_AtkUnloadPlayerTeammates";
        _timeout = time + _timeout;
        while {_teammates isNotEqualTo []} do {
            sleep 3;
            {
                _x params ["_player","_units"];
                if (vehicle _player ==  _player || {time > _timeout}) then {
                    {
                        // encourage player's teammates to exit vehicle since they really seem to want the player to tell them
                        _x action ["GetOut", objectParent _x];
                        _x leaveVehicle (objectParent _x);
                        sleep 0.5;
                    } forEach _units;
                    _teammates deleteAt _forEachIndex;
                };
            } forEachReversed _teammates;
        };
    };
};

ITW_AtkUnloadAirplane = {
    // unload via parachute
    params ["_veh","_crewGroup","_cargoGroups","_objPt"];
    scriptName "ITW_AtkUnloadAirplane";
    
    // keep flying over target
    if !(_crewGroup isEqualTo grpNull) then {
        ITW_DELETE_WAYPOINTS(_crewGroup);
        private _vPos = getPosATL _veh;
        private _wPos = _vPos getPos [1500,[getDir _veh,_veh getDir _objPt] call ITW_FncDirMidpoint];
        _wPos set [2,_vPos#2];
        private _wp = _crewGroup addWaypoint [_wPos,100];
        _wp setWaypointBehaviour "CARELESS";
        ATK_DEBUG(_crewGroup,"ITW_AtkUnloadAirplane waypoints updated",_wPos); 
    };
    if !(_objPt isEqualTo []) then {
        private _timeout = time + 60;
        waitUntil {sleep 0.5;!surfaceIsWater getPosATL _veh || {time > _timeout}};
        private _unloadDist = ITW_ParamObjectiveSize + ITW_ParamTransportUnloadDist + 100;
        waitUntil {sleep 0.25;_veh distance2D _objPt < _unloadDist || {time > _timeout}};
    };
    
    private _unloadUnits = crew _veh select {isPlayer _x && {driver _veh != _x}}; // we don't need to add teammates since they automatically eject when player ejects
    private _overflow = [crew _veh] call ITW_AtkGetOverflowTeammateJoinWave;
    {_unloadUnits append units _x} forEach _cargoGroups;
    
    private _toggle = true;
    private _speed = speed _veh; 
    {
        private _unit = _x;
        if (!alive _unit || {vehicle _unit != _veh}) then {continue};
        private _dirTo = getDir _veh;
        private _vPos = getPosASL _veh;
        private _pos = if (_toggle) then {_veh modeltoWorld [7, -30, -20]} else {_veh modeltoWorld [-7, -30, -20]};
        if (_pos#2 < 0) then {_pos set [2,0]};
        _toggle = !_toggle;
        [_unit,_pos,_speed] call ITW_AtkParachute;
    } forEach _unloadUnits;
    
    // head away from objective right away
    if (!(_crewGroup isEqualTo grpNull) && {!(_objPt isEqualTo [])}) then {
        private _wPos = _veh getPos [1000,_objPt getDir _veh]; 
        _wPos set [2,(getPosATL _veh)#2];
        ITW_DELETE_WAYPOINTS(_crewGroup);
        private _wp = _crewGroup addWaypoint [_wPos,100];
    };
    
    if (_overflow isNotEqualTo []) then {
        private _playerIdx = _unloadUnits findIf {isPlayer _x};
        private _player = if (_playerIdx >= 0) then {
            _unloadUnits#_playerIdx
        } else {
            if (_unloadUnits isNotEqualTo []) then {_unloadUnits#0} else {objNull};
        };
        private "_pos";
        if (!isNull _player) then {
            private _timeout = time + 20;
            waitUntil {isTouchingGround _player || {time > _timeout}};
            _pos = getPosATL _player;
        } else {
            _pos = getPos _veh;
        };
        _pos set [2,0];
        private _overflowPos = [_pos, 5, 150, 3, 1, 0.5, 0, [],[_pos,_pos]] call BIS_fnc_findSafePos;
        if (count _overflowPos == 2) then {_overflowPos pushBack 0};
        {
            _x setPosATL _overflowPos;
        } forEach _overflow;
    };
};

ITW_AtkParachute = {
    // delays based on speed, even if unit is not local  (0.5 at 75kph, 0.25 at 150kph)
    params ["_unit","_pos",["_speed",80]];
    if (_speed < 1) then {_speed = 1};
    private _sleep = 0.1 max (40/_speed) min 0.5; // max of 1/2 sec delay
    
    if (!alive(_unit)) exitWith {};
    if (!local _unit) exitWith {
        _this remoteExec ["ITW_AtkParachute",_unit];
        sleep _sleep;
    };  

    // here on runs where unit is local
    private _para = "Steerable_Parachute_F" createVehicle _pos;
    ALLOW_DAMAGE(_unit,false);
    _para setPos _pos;
    unassignVehicle _unit;
    moveOut _unit;
    private _timeout = time + 1;
    waitUntil {vehicle _unit == _unit || {time > _timeout}};
    _unit moveindriver _para;
    _para lock false;
    sleep _sleep;
    ALLOW_DAMAGE(_unit,true);
};

ITW_AtkUnloadHeli = {
    // unload by landing
    params ["_veh","_crewGroup","_cargoGroups","_objPt"]; 
    if (_veh isKindOf "Plane" || {random 100 < ITW_ParamHelisUnload}) exitWith {_this call ITW_AtkUnloadAirplane};
    scriptName "ITW_AtkUnloadHeli";
    ITW_DELETE_WAYPOINTS(_crewGroup);
    private _wPos = _objPt getPos [ITW_ParamObjectiveSize + ITW_ParamTransportUnloadDist + 100,_objPt getDir _veh];
    private _wp = _crewGroup addWaypoint [_wPos,100];
    _wp setWaypointType "TR UNLOAD";
    _wp setWaypointCompletionRadius 10;
    _wp setWaypointBehaviour "CARELESS"; 
    ATK_DEBUG(_crewGroup,"ITW_AtkUnloadHeli waypoints updated",_wPos); 
    private _prevPos = getPosATL _veh;
    private _waitLimit = 0; // max loops we wait for
    
    // eject players and teammates as well as infantry cargo
    private _unloadUnits = crew _veh select {isPlayer leader _x && {driver _veh != _x}};
    [_unloadUnits select {isPlayer _x},60] call ITW_AtkUnloadPlayerTeammates;
    private _overflow = [crew _veh] call ITW_AtkGetOverflowTeammateJoinWave;
    _unloadUnits append _overflow;
    {_unloadUnits append units _x} forEach _cargoGroups;
    
    waitUntil {
        sleep 3; 
        private _pos = getPosATL _veh;
        private _height = _pos#2;
        if !(_prevPos isEqualTo []) then {
            if (_height < 1 || {isTouchingGround _veh}) exitWith {_prevPos = []};
            if (_pos distance _prevPos < 1) then {
                // TR UNLOAD failed (no place to land?)
                // after failing, the helicopter is in a broken state and will no longer move (until its touching the ground)
                // so unload troops, then teleport it to the ground and back
                for "_i" from 0 to 2 do {_veh setVelocityModelSpace [0,20,0]; sleep 1};
                private _toggle = true;
                private _speed = speed _veh;
                {
                    _veh setVelocityModelSpace [0,20,0];
                    private _unit = _x;
                    if (!alive _unit || {vehicle _unit != _veh&& {!(_unit in _overflow)}}) then {continue};
                    private _dirTo = getDir _veh;
                    private _vPos = getPosASL _veh;
                    private _pos = if (_toggle) then {_veh modeltoWorld [7, -30, -20]} else {_veh modeltoWorld [-7, -30, -20]};
                    if (_pos#2 < 0) then {_pos set [2,0]};
                    _toggle = !_toggle;
                    [_unit,_pos,_speed] call ITW_AtkParachute;
                } forEach _unloadUnits;
                
                for "_i" from 0 to 2 do {_veh setVelocityModelSpace [0,20,0]; sleep 1};
                
                // try to unstick heli
                private _dmgAllowed = isDamageAllowed _veh;
                private _curPos = getPosATL _veh;
                SEM_LOCK(ITW_AtkFlatPlaceSem);
                ALLOW_DAMAGE(_veh,false);
                _veh setPosATL ITW_Atk_Flat_Place;
                sleep 0.2;
                _veh setPosATL _curPos;
                if (_dmgAllowed) then {ALLOW_DAMAGE(_veh,true)};
                SEM_UNLOCK(ITW_AtkFlatPlaceSem);
                for "_i" from 0 to 2 do {_veh setVelocityModelSpace [0,20 - (_i*10),0]; sleep 1};
                
                // remove waypoints so system should send it on it's way
                ITW_DELETE_WAYPOINTS(_crewGroup);
                breakTo "ITW_AtkUnloadHeli";
            } else {
                _prevPos = _pos;
            };
        };
        !alive _veh || {_height < 10 || {isTouchingGround _veh}}
    };
   {_x leaveVehicle _veh; {[_x] remoteExec ["unassignVehicle",_x]} forEach units _x} forEach _cargoGroups; 
};

ITW_AtkUnloadShip = {
    params ["_veh","_crewGroup","_cargoGroups","_objPt","_objSize"];
    ITW_DELETE_WAYPOINTS(_crewGroup);
    if (_veh isKindOf "Air") exitWith {_this call ITW_AtkUnloadHeli}; // sometime helis take role of ground vehs 
    scriptName "ITW_AtkUnloadShip";
    private _vehPos = getPos _veh;
    // find a position on the shore near the ship that is the correct distance from the objective
    private _dist = 0;
    private _pos = [0,0];
    private _halfPt = [((_vehPos#0) + (_objPt#0))/2,((_vehPos#1) + (_objPt#1))/2,0];
    while {_pos isEqualTo [0,0]} do {
        _pos = [_halfPt, _dist, _dist + 200, 0, 0, 0.5, 1, [], [[0,0],[0,0]]] call BIS_fnc_findSafePos;
        _dist = _dist + 190;
    };
    if (_pos isEqualTo [0,0]) then {
        private _dir = _vehPos getDir _objPt;
        private _found = false;
        _pos = _vehPos;
        while {!_found} do {
            private _newPos = _pos getPos [10,_dir];
            if !(surfaceIsWater _newPos) then {
                _found = true;
            } else {
                _pos = _newPos;
            };
        };
    };
    if (count _pos == 2) then {_pos pushBack 0};
    private _wp = _crewGroup addWaypoint [_pos,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointCompletionRadius 10;
    _wp setWaypointBehaviour "CARELESS";
    ATK_DEBUG(_crewGroup,"ITW_AtkUnloadShip waypoints updated MOVE",_pos); 
    
    private _timeout = time + 90;
    waitUntil {sleep 1;time > _timeout || {_veh distance _pos < 100}};
    
    _wp setWaypointType "TR UNLOAD";
    _wp setWaypointCompletionRadius 10;
    _wp setWaypointBehaviour "CARELESS";
    private _wpIndex = _wp#1;
    ATK_DEBUG(_crewGroup,"ITW_AtkUnloadShip waypoints updated TR UNLOAD",_pos); 
    
    private _unloadUnits = crew _veh select {isPlayer leader _x && {driver _veh != _x}};
    [_unloadUnits select {isPlayer _x},60] call ITW_AtkUnloadPlayerTeammates;
    private _overflow = [crew _veh] call ITW_AtkGetOverflowTeammateJoinWave;
    {_unloadUnits append units _x} forEach _cargoGroups;
    
    private _timeout = time + 40;
    waitUntil {sleep 1;time > _timeout || {currentWaypoint _crewGroup > _wpIndex}};// || {_veh distance2D _pos < 20 && {speed _veh < 1}}}};
    while {LV_PAUSE} do {sleep 5};
    waitUntil {speed _veh < 2};
    
    // unload units
    {_x leaveVehicle _veh; {[_x] remoteExec ["unassignVehicle",_x]} forEach units _x} forEach _cargoGroups;
    
    while {!(_unloadUnits isEqualTo [])} do {
        sleep 10;
        {
            if (!CONSCIOUS(_x) || vehicle _x == _x) then {_unloadUnits deleteAt _forEachIndex; continue};
            moveOut _x;
            unassignVehicle _x;
            sleep 0.5;
        } forEachReversed _unloadUnits;
    };
    {_x setPosATL _pos} forEach _overflow;
    
    // rotate ship to get away from shore
    private _shipPos = getPosASL _veh;
    for "_i" from 2 to 80 step 5 do {
        for "_dir" from 0 to 359 step 10 do {
            private _pos = _shipPos getPos [_i,_dir];
            if !(surfaceIsWater _pos) exitWith {
                _i = 100;
                _dir = _dir + 180;
                private _up = vectorUp _veh;
                private _dirVec = [sin _dir, cos _dir, 0];
                private _rightVec = _dirVec vectorCrossProduct _up;
                private _dirVector = _up vectorCrossProduct  _rightVec;
                [_veh,[_dirVector,_up]] remoteExec ["setVectorDirAndUp",_veh];
                [_veh, _shipPos getPos [10,_dir]] remoteExec ["setPosASL", _veh];
            };
        };
    };
};

ITW_AtkUnloadLand = {
    params ["_veh","_crewGroup","_cargoGroups","_objPt"];
    ITW_DELETE_WAYPOINTS(_crewGroup);
    if (_veh isKindOf "Air") exitWith {_this call ITW_AtkUnloadHeli}; // sometime helis take role of ground vehs 
    scriptName "ITW_AtkUnloadLand";
    
    private _wPos = _veh getPos [150,getDir _veh + (if (random 1 < 0.5) then {20} else {-20})];
    // ensure point isn't in water
    private _cnt = 50;
    while {surfaceIsWater _wPos && _cnt > 0} do {_cnt = _cnt - 1; _wPos = _veh getPos [150,getDir _veh + (if (random 1 < 0.5) then {20} else {-20})]};
    
    private _wp = _crewGroup addWaypoint [_wPos,0];
    _wp setWaypointType "TR UNLOAD";
    _wp setWaypointCompletionRadius 20;
    _wp setWaypointBehaviour "CARELESS";
    private _wpIndex = _wp#1;
    ATK_DEBUG(_crewGroup,"ITW_AtkUnloadLand waypoints updated",_wPos); 
    
    private _unloadUnits = crew _veh select {isPlayer leader _x && {driver _veh != _x}};
    private _overflow = [crew _veh,true] call ITW_AtkGetOverflowTeammateJoinWave;
    [_unloadUnits select {isPlayer _x},50] call ITW_AtkUnloadPlayerTeammates;
    
    private _timeout = time + 30;
    waitUntil {sleep 1;time > _timeout || {currentWaypoint _crewGroup > _wpIndex || {_veh distance2D _wPos < 30 && {speed _veh < 2}}}};
    while {LV_PAUSE} do {sleep 5};
    deleteWaypoint _wp;
    waitUntil {speed _veh < 1};
    
    // eject players and teammates as well as infantry cargo
    {
        unassignVehicle _x;
        [_x] orderGetIn false;
        moveOut _x;
        sleep 0.5; 
    } forEach _unloadUnits;
    
    private _defaultPos = _veh getPos [5,random 360];
    private _overflowPos = [_veh, 5, 150, 3, 1, 0.5, 0, [],[_defaultPos,_defaultPos]] call BIS_fnc_findSafePos;
    if (count _overflowPos == 2) then {_overflowPos pushBack 0};
    {
        _x setPosATL _overflowPos;
    } forEach _overflow;
    
    private _units = [];
    {
        private _grp = _x;
        if (isNull _grp) then {continue};
        _units append units _grp; 
        _grp leaveVehicle _veh; 
        [_grp] remoteExec ["ITW_AtkUnassignVeh",leader _grp];
    } forEach _cargoGroups;
    _units allowGetIn false;
};

ITW_AtkMoveOutVeh = {
    // call where group leader is local
    params ["_group"];
    {unassignVehicle _x; moveOut _x; sleep 1} forEach units _group;
};

ITW_AtkDefendStart = {
    params ["_isZoneDefend"]; // is it zone or flag triggered defend?
    // reassign all vehicles and delete units far from objs & players

    private _defendObjIdx = ITW_defendPhaseObjIdx;
    private _defendObjPos = ITW_Objectives#_defendObjIdx#ITW_OBJ_POS;
    private _currentObjsPos = ITW_Zones#ITW_ZoneIndex apply {ITW_Objectives#_x#ITW_OBJ_POS};
    
    SEM_LOCK(ITW_AtkVehicleManagerBusy);
    {
        private _vehInfo = _x;
        _vehInfo params ["_type","_role","_veh","_grp","_cargoGroups","_fromPos"];
        if (VAR_GET_OBJ_IDX(_grp) != _defendObjIdx) then {
            [_vehInfo,false,false] call ITW_AtkEngageVehicle;// reassign to defend objective
        };
    } forEach ITW_ManagedVehs;
    SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
    
    YIELD_CPU;
    
    SEM_LOCK(ITW_AtkInfantryManagerBusy);
    {
        // Defend Phase - remove infantry far from objectives and players
        _x params ["_grp"];
        private _leader = leader _grp;
        if (vehicle _leader != _leader || {_grp getVariable ["itwInitGrp",false]}) then {continue}; // ignore cargo groups
        
        // Delete units (friendly and enemy) far from objectives and players so we have more infantry to add to defend phase
        private _objDist = 600 + ITW_ParamObjectiveSize + (if (VAR_GET_OBJ_IDX(_grp) == _defendObjIdx) then {600} else {0}); // units assigned to this obj can be further away
        private _nearPlayerIdx = playableUnits findIf {_x distance _leader < 800};  // and > 800m from any player
        if (_nearPlayerIdx == -1) then {         
            private _nearObj = false;
            if (_isZoneDefend) then {
                _nearObj = _defendObjPos distance _leader < _objDist; // and > (objSize+600) from any objective zone if flag triggered defend
            } else {
                _nearObj = -1 != (_currentObjsPos findIf {_x distance _leader < _objDist}); // and > (objSize+600) from any objective zone if flag triggered defend
            };
            if (!_nearObj) then {
                {deleteVehicle _x} forEach units _grp;
                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
            };
        };
    } forEach (call ITW_AtkGetInfantryGroups);
    SEM_UNLOCK(ITW_AtkInfantryManagerBusy);
};

ITW_AtkDefendDone = {
    // try to free up enemy vehicles when defend mode is complete
    params ["_isZoneDefend","_defendObjIdx"]; // if _isZoneDefend we will clean up more aggressively
    
    private _currObjsPos = (ITW_Zones#ITW_ZoneIndex) apply {ITW_Objectives#_x#ITW_OBJ_POS};
    private _defendPos = ITW_Objectives#_defendObjIdx#ITW_OBJ_POS;
    private _players = allPlayers - HeadlessClients;
    
    SEM_LOCK(ITW_AtkVehicleManagerBusy);
    {
        private _vehInfo = _x;
        _vehInfo params ["_type","_role","_veh","_grp","_cargoGroups","_fromPos"];
        if (side _veh != ITW_EnemySide) then {continue};
        if (ITW_ParamDefendPhaseEnd == 0) then {
            // clean up and/or reassign
            private _okayToDelete = !ITW_VEH_IS_AIR(_vehInfo#VEHINFO_TYPE);
            if (_isZoneDefend) then {
                // if new zone, delete vehs far from player
                if (_okayToDelete) then {{if (_x distance _veh < 1000) exitWith {_okayToDelete = false}} forEach _players};
            } else {
                // if not new zone, reassign veh to new objectives or delete veh if too far from player and objectives
                if (_okayToDelete) then {{if (_x distance _veh < 1500) exitWith {_okayToDelete = false}} forEach _players};
                if (_okayToDelete) then {{if (_x distance _veh < 1000) exitWith {_okayToDelete = false}} forEach _currObjsPos};
            };
            if (_okayToDelete) then {
                deleteVehicleCrew _veh;
                [[_vehInfo#VEHINFO_CREW_GRP],"deleteGroup",_vehInfo#VEHINFO_CREW_GRP] call ITW_FncRemoteLocalGroup;
                {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup} forEach (_vehInfo#VEHINFO_CARGO_GRPS);
                deleteVehicle _veh;
            } else {
                if (_isZoneDefend) then {
                    private _retreatObj = [getPosATL _veh,ITW_OWNER_ENEMY,ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
                    private _retreatPos = _retreatObj#ITW_OBJ_V_SPAWN;
                    if (_retreatPos isEqualTo []) then {_retreatObj#ITW_OBJ_POS};
                    ITW_DELETE_WAYPOINTS(_grp);
                    _grp addWaypoint [_retreatPos,100];
                } else {
                    [_vehInfo,false,false] call ITW_AtkEngageVehicle; // reset obj veh is assigned to
                };
            };
        } else {
            // retreat
            if (_isZoneDefend) then {
                private _retreatObj = [getPosATL _veh,ITW_OWNER_ENEMY,ITW_OWNER_ENEMY] call ITW_ObjGetNearest;
                private _retreatPos = _retreatObj#ITW_OBJ_V_SPAWN;
                if (_retreatPos isEqualTo []) then {_retreatObj#ITW_OBJ_POS};
                ITW_DELETE_WAYPOINTS(_grp);
                _grp addWaypoint [_retreatPos,100];
            } else {
                [_vehInfo,false,false] call ITW_AtkEngageVehicle; // reset obj veh is assigned to
            };
        };
    } forEach ITW_ManagedVehs;
    SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
    
    YIELD_CPU;
    
    SEM_LOCK(ITW_AtkInfantryManagerBusy);
    {
        private _grp = _x;
        if (side _grp != ITW_EnemySide) then {continue};
        private _leader = leader _grp;
        if (vehicle _leader == _leader) then {
            private _okayToDelete = true;
            if (_isZoneDefend) then {
                {if (_x distance _leader < 600) exitWith {_okayToDelete = false}} forEach _players;
                if (_okayToDelete) then {_okayToDelete = _defendPos distance _leader > (ITW_ParamObjectiveSize + 200)}; // leave units in defend objective
            } else {
                {if (_x distance _leader < 1000) exitWith {_okayToDelete = false}} forEach _players;
                if (_okayToDelete) then {{if (_x distance _leader < 1000) exitWith {_okayToDelete = false}} forEach _currObjsPos};
            };
            if (_okayToDelete) then {
                {deleteVehicle _x} forEach (units _grp);
                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
            } else {
                if (_isZoneDefend) then {
                    // groups outside of objectives will flee if zone capture mode
                    if (-1 == _currObjsPos findIf {_x distance _leader < ITW_ParamObjectiveSize + 200}) then {
                        private _retreatPos = ([getPosATL _leader,ITW_OWNER_ENEMY,ITW_OWNER_ENEMY] call ITW_ObjGetNearest)#ITW_OBJ_V_SPAWN;
                        ITW_DELETE_WAYPOINTS(_grp);
                        _grp addWaypoint [_retreatPos,100];
                    };
                } else {
                    // groups get reassigned
                    ITW_DELETE_WAYPOINTS(_grp);
                };
            };
        };
    } forEach (call ITW_AtkGetInfantryGroups);
    SEM_UNLOCK(ITW_AtkInfantryManagerBusy);
};

ITW_AtkNext = {
    // reset stuff for next zone
    0 call ITW_AllyNext;
    
    [] call ITW_GarrisonDone;
    
    [true,"RESET"] call ITW_AtkTranspSuccess;
    [false,"RESET"] call ITW_AtkTranspSuccess;
    
    SEM_LOCK(ITW_AtkVehicleManagerBusy);
    ITW_AtkRoadMap = nil;
    ITW_SpawnOffsets = nil;
    {
        private _vehInfo = _x;
        private _veh = _vehInfo#VEHINFO_VEH;
        private _okayToDelete = !ITW_VEH_IS_AIR(_vehInfo#VEHINFO_TYPE);
        if (_okayToDelete) then {{if (_x distance _veh < 2000) exitWith {_okayToDelete = false}} forEach (allPlayers - HeadlessClients)};
        if (_okayToDelete) then {
            // delete vehs that are > 2000m from any player
            deleteVehicleCrew _veh;
            [[_vehInfo#VEHINFO_CREW_GRP],"deleteGroup",_vehInfo#VEHINFO_CREW_GRP] call ITW_FncRemoteLocalGroup;
            {[[_x],"deleteGroup",_x] call ITW_FncRemoteLocalGroup} forEach (_vehInfo#VEHINFO_CARGO_GRPS);
            deleteVehicle _veh;
        } else {
            private _role = _vehInfo#VEHINFO_ROLE;
            if (_role != ITW_VEH_ROLE_COMPLETE) then {
                // reset veh crew waypoints so new ones will be assigned
                private _crewGroup = _x#VEHINFO_CREW_GRP;
                ITW_DELETE_WAYPOINTS(_crewGroup);
                VAR_SET_OBJ_IDX(_crewGroup,-1);
            };
            private _cargoGroups = _x#VEHINFO_CARGO_GRPS;
            _cargoGroups apply {
                VAR_SET_OBJ_IDX(_x,-1);
                _x setVariable ["ITW_OkayToReset",true];
            };
            _vehInfo#VEHINFO_CREW_GRP setVariable ["ITW_OkayToReset",true];
        };
    } forEach ITW_ManagedVehs;
    SEM_UNLOCK(ITW_AtkVehicleManagerBusy);
    
    SEM_LOCK(ITW_AtkInfantryManagerBusy);
    // delete groups that are > 1000m from any player
    {
        private _grp = _x;
        private _leader = leader _grp;
        if (vehicle _leader == _leader) then {
            VAR_SET_OBJ_IDX(_grp,-1);
            private _okayToDelete = true;
            {if (_x distance _leader < 1000) exitWith {_okayToDelete = false}} forEach (allPlayers - HeadlessClients);
            if (_okayToDelete) then {
                {deleteVehicle _x} forEach (units _grp);
                [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
            } else {
                _grp setVariable ["ITW_OkayToReset",true];
            };
        };
    } forEach (call ITW_AtkGetInfantryGroups);
    SEM_UNLOCK(ITW_AtkInfantryManagerBusy);
    
    ITW_AllyIndex = ITW_ZoneIndex;
};

////////////////////////////////
/// Join Wave 
/// - let the player join the infantry wave
/// - give options to swapping to driver/gunner/commander that will allow switching back so that the original driver is still correctly controlled by the Attack Mgr
////////////////////////////////
 
ITW_AtkJoinWave = {
    // call on server
    params ["_player","_enable"];
    if (_enable) then {
        ITW_AtkPlayersJoinWave pushBackUnique _player;
    } else {
        ITW_AtkPlayersJoinWave = ITW_AtkPlayersJoinWave - [_player];
    };
    publicVariable "ITW_AtkPlayersJoinWave"; // notify clients so the menu at officer shows add/remove correctly
};

ITW_AtkJoinWaveSwap = {
    // call on server - handles player requests to swap seats with crew
    params ["_player","_role"];
    private _veh = vehicle _player;
    _veh getVariable ["itwjwscrew",[0,0,0]] params ["_driver","_gunner","_commander"];
    if (typeName _driver isEqualTo "SCALAR") then {
        _driver = driver _veh;
        _gunner = gunner _veh;
        _commander = commander _veh;
        // some vehicles have multiple turrets and don't return the gunner/commander
        if (isNull _gunner) then {
            private _crew = fullCrew _veh;
            private _index = _crew findIf {_x#1 == "turret" && {_x#2 == 0}};
            if (_index >= 0) then {_gunner = _crew#_index#0};
            if (isNull _commander) then {
                _index = _crew findIf {_x#1 == "turret" && {_x#2 == 1}};
                if (_index >= 0) then {_commander = _crew#_index#0};
            };
        };
        _veh setVariable ["itwjwscrew",[_driver,_gunner,_commander]];
    };
    
    if (_role == "DRV" && {isPlayer driver _veh})    exitWith {cutText [localize "STR_ITW_BASE_JoinWaveError","PLAIN",1]};
    if (_role == "GNR" && {isPlayer gunner _veh})    exitWith {cutText [localize "STR_ITW_BASE_JoinWaveError","PLAIN",1]};
    if (_role == "CMR" && {isPlayer commander _veh}) exitWith {cutText [localize "STR_ITW_BASE_JoinWaveError","PLAIN",1]};
    
    if (_role == "EXIT") exitWith { // player exited the vehicle
        if (alive _veh && {isNull driver    _veh && {alive    _driver}}) then {_driver    setPosATL [0,0,0];_driver moveInDriver    _veh};
        if (alive _veh && {isNull gunner    _veh && {alive    _gunner}}) then {_gunner    setPosATL [0,0,0];_driver moveInGunner    _veh};
        if (alive _veh && {isNull commander _veh && {alive _commander}}) then {_commander setPosATL [0,0,0];_driver moveInCommander _veh};
    };
    if (_veh == _player) exitWith {diag_log "Error Pos: ITW_AtkJoinWaveSwap - player not in vehicle"};
    
    private _savePlayerSeatFn = {
        private _player = _this;
        private _info = fullCrew _veh select {_x#0 == _player};
        if (_info isEqualTo []) exitWith {diag_log "Error Pos: ITW_AtkJoinWaveSwap _savePlayerSeatFn: player not in crew"};
        private _seatInfo = [_info#0#1,_info#0#2,_info#0#3];
        _player setVariable ["itwjwsseat",_seatInfo];
        _seatInfo
    };
    
    private _allowDamageFn = {
        params ["_allowed","_units"];
        {
            if (!isNull _x) then {
                ALLOW_DAMAGE(_x,_allowed);
            };
        } forEach _units;
        sleep 0.1;
    };
    
    [false,[_player,_driver,_gunner,_commander]] call _allowDamageFn;
    private _seatInfo = _player getVariable ["itwjwsseat",["",-1,[]]];

    // if player in driver/gunner/cmdr, then move them back to cargo
    switch (true) do {
        case (_player == driver _veh): {
            waitUntil {moveOut _driver;vehicle _driver == _driver};
            waitUntil {moveOut _player;vehicle _player == _player};
            sleep 0.1;
            [_player,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_driver,"DRV",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            sleep 0.5;
        };
        case (_player == gunner _veh): {
            waitUntil {moveOut _gunner;vehicle _gunner == _gunner};
            waitUntil {moveOut _player;vehicle _player == _player};
            sleep 0.1;
            [_player,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_gunner,"GNR",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            sleep 0.5;
        };
        case (_player == commander _veh): {
            waitUntil {moveOut _commander;vehicle _commander == _commander};
            waitUntil {moveOut _player   ;vehicle _player == _player};
            sleep 0.1;
            [_player,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_commander,"CMR",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            sleep 0.5;
        };
    };
    // move player to desired seat (if 'ANY' then leave them in cargo)
    switch (_role) do {
        case "DRV": {
            _seatInfo = _player call _savePlayerSeatFn;
            _veh setVariable ["itwjwspos",waypointPosition [_driver,currentWaypoint group _driver],owner _player];
            waitUntil {moveOut _driver;vehicle _driver == _driver};
            waitUntil {moveOut _player;vehicle _player == _player};
            sleep 0.1;
            [_player,"DRV",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_driver,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
        };
        case "GNR": {
            _seatInfo = _player call _savePlayerSeatFn;
            waitUntil {moveOut _gunner;vehicle _gunner == _gunner};
            waitUntil {moveOut _player;vehicle _player == _player};
            sleep 0.1;
            [_player,"GNR",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_gunner,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
        };
        case "CMR": {
            _seatInfo = _player call _savePlayerSeatFn;
            waitUntil {moveOut _commander;vehicle _commander == _commander};
            waitUntil {moveOut _player   ;vehicle _player == _player};
            sleep 0.1;
            [_player,"CMR",_veh] call ITW_AtkJoinwWaveMoveToSeat;
            [_commander,_seatInfo,_veh] call ITW_AtkJoinwWaveMoveToSeat;
        };
    };
    
    [true,[_player,_driver,_gunner,_commander]] call _allowDamageFn;
    [_player, ["itwIgnoreGetOut",nil]] remoteExec ["setVariable",_player];
};
  
ITW_AtkJoinwWaveMoveToSeat = {
    params ["_unit","_seatInfo","_veh"];
    if (!local _unit) exitWith {_this remoteExec ["ITW_AtkJoinwWaveMoveToSeat",_unit]};
    if (typeName _seatInfo isEqualTo "ARRAY") then {
        _seatInfo params ["_seatRole","_cargoIndex","_turretPath"];
        switch (_seatRole) do {
            case "driver":    {_unit moveInDriver _veh              ;sleep 0.01;_unit moveInDriver _veh              };
            case "commander": {_unit moveInCommander _veh           ;sleep 0.01;_unit moveInCommander _veh           };
            case "gunner":    {_unit moveInGunner _veh              ;sleep 0.01;_unit moveInGunner _veh              };
            case "turret":    {_unit moveInTurret [_veh,_turretPath];sleep 0.01;_unit moveInTurret [_veh,_turretPath]};
            case "cargo":     {_unit moveInCargo [_veh,_cargoIndex] ;sleep 0.01;_unit moveInCargo [_veh,_cargoIndex] };
        };
    } else {
        switch (_seatInfo) do {
            case "DRV": {
                _unit moveInDriver _veh;
            };
            case "GNR": {
                _unit moveInGunner _veh;
            };
            case "CMR": {
                _unit moveInCommander _veh;
            };
        };
    };
};

ITW_AtkJoinWaveSwapLocal = {
    // call on client
    params ["_seatInfo"];
    player setVariable ["itwIgnoreGetOut",true]; // keep the GetOut event handler from thinking you want a parachute
    [player,_seatInfo] remoteExec ["ITW_AtkJoinWaveSwap",2]; // server handles the swapping
};

ITW_AtkJoinWaveSwapAddActions = {
    // spawn on client
    private _timeout = time + 10;
    while {vehicle player == player && time < _timeout} do {sleep 1};

    private _veh = vehicle player;
    if (_veh == player) exitWith {diag_log "Error Pos: ITW_AtkJoinWaveSwapAddActions - player not in vehicle"};
    
    private _actions = [];
    _actions pushBack (_veh addAction ["<t color='#22ff22'>" + localize "STR_ITW_BASE_JoinWaveCargo" + "</t>",{["ANY"] call ITW_AtkJoinWaveSwapLocal},nil,30,false,true,"","_this in [driver _target,gunner _target,commander _target] && {!unitIsUAV _target}",-1]);
    _actions pushBack (_veh addAction ["<t color='#55ff55'>" + localize "STR_ITW_BASE_JoinWaveDriver" + "</t>",{["DRV"] call ITW_AtkJoinWaveSwapLocal},nil,30,false,true,"","!(driver _target == _this) && {!unitIsUAV _target}",-1]);
    if (!isNull gunner _veh) then {
        _actions pushBack (_veh addAction ["<t color='#55ff55'>" + localize "STR_ITW_BASE_JoinWaveGunner" + "</t>",{["GNR"] call ITW_AtkJoinWaveSwapLocal},nil,30,false,true,"","!(gunner _target == _this) && {!unitIsUAV _target}",-1]);
    };
    if (!isNull commander _veh) then {
        _actions pushBack (_veh addAction ["<t color='#55ff55'>" + localize "STR_ITW_BASE_JoinWaveCommander" + "</t>",{["CMR"] call ITW_AtkJoinWaveSwapLocal},nil,30,false,true,"","!(commander _target == _this) && {!unitIsUAV _target}",-1]);
    };
    
    private _done = false;
    private _taskId = "itwJW" + str(clientOwner);
    while {!_done} do {
        sleep 1;
        
        private _driverTaskExists = [_taskId] call BIS_fnc_taskExists;
        if (player == driver _veh && {!_driverTaskExists}) then {
            private _description = localize "str_a3_boot_m01_bis_prepare_desc"; // "Move to the indicated position."
            [player, _taskId, [_description,_description,""], _veh getVariable ["itwjwspos",[0,0,0]], "ASSIGNED", -1, true, "move", true] call BIS_fnc_taskCreate;
        };
        if (player != driver _veh && {_driverTaskExists}) then {
            [_taskId] call BIS_fnc_deleteTask;
        };
        
        // play a little game since the player can be moved out of a moment when swapping seats
        _done = vehicle player != _veh;
        if (_done) then {sleep 0.5};
        _done = vehicle player != _veh || {!alive _veh};
    };
    
    player setVariable ["itwIgnoreGetOut",nil];
    [player,"EXIT"] remoteExec ["ITW_AtkJoinWaveSwap",2];
    {
        player removeAction _x;
    } forEach _actions;
    [_taskId] call BIS_fnc_deleteTask;
};

ITW_AtkJoinWaveUI = {
    // spawn on player's client
    params ["_enable",["_didJoin",false]];
    if (_enable) then {
        if (!canSuspend) exitWith {_this spawn ITW_AtkJoinWaveUI};
        player setVariable ["itwatkjw",true];
        private _joinFmtSec = localize "STR_ITW_BASE_JoinWaveSecFMT";
        private _joinFmtMin = localize "STR_ITW_BASE_JoinWaveMinFMT";
        while {player getVariable ["itwatkjw",false]} do {
            private _joinFmt = _joinFmtSec;
            private _joinDelay = ITW_atkFriendlyAtkTime - time;
            if (_joinDelay < 0) then {_joinDelay = 0};
            if (_joinDelay > 120) then {
                _joinFmt = _joinFmtMin;
                _joinDelay = _joinDelay/60;
            };
            hintSilent format [_joinFmt,round _joinDelay];     
            sleep 1;
            while {LV_PAUSE} do {sleep 5};
        };
        hintSilent "";
    } else {
        player setVariable ["itwatkjw",nil];
        hintSilent "";
        if (_didJoin) then {
            0 call ITW_AtkJoinWaveSwapAddActions;
        };
    };
};

ITW_AtkDeliveryCntChange = {
    private _deliveryGroups = groups ITW_PlayerSide select {_x getVariable ["itwDelivery",false]};
    if (count _deliveryGroups > ITW_ParamFriendlySquadDelivery) then {
        for "_i" from (ITW_ParamFriendlySquadDelivery + 1) to (count _deliveryGroups) do {
            private _grp = _deliveryGroups deleteAt 0;
            {deleteVehicle _x} forEach units _grp;
            [[_grp],"deleteGroup",_grp] call ITW_FncRemoteLocalGroup;
        };
    };
};

["ITW_AtkDeliveryCntChange"] call SKL_fnc_CompileFinal;
["ITW_ATK_DEBUG"] call SKL_fnc_CompileFinal;
["ITW_AtkMgrDebug"] call SKL_fnc_CompileFinal;
["ITW_AtkManager"] call SKL_fnc_CompileFinal;
["ITW_AtkAiCount"] call SKL_fnc_CompileFinal;
["ITW_AtkUnitToGroup"] call SKL_fnc_CompileFinal;
["ITW_AtkSpawnVeh"] call SKL_fnc_CompileFinal;
["ITW_AtkAddInfantryGroup"] call SKL_fnc_CompileFinal;
["ITW_AtkAddVehicle"] call SKL_fnc_CompileFinal;
["ITW_AtkEngageInfantry"] call SKL_fnc_CompileFinal;
["ITW_AtkEngageVehicle"] call SKL_fnc_CompileFinal;
["ITW_AtkSpawnOffsetter"] call SKL_fnc_CompileFinal;
["ITW_AtkInfantryManager"] call SKL_fnc_CompileFinal;
["ITW_AtkWpPoint"] call SKL_fnc_CompileFinal;
["ITW_AtkInfantryMoveUp"] call SKL_fnc_CompileFinal;
["ITW_AtkVehicleManager"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadAirplane"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadHeli"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadShip"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadLand"] call SKL_fnc_CompileFinal;
["ITW_AtkNext"] call SKL_fnc_CompileFinal;
["ITW_AtkVehicleSpawner"] call SKL_fnc_CompileFinal;
["ITW_AtkVehicleSpawnerMP"] call SKL_fnc_CompileFinal;
["ITW_AtkSwitchToAirVeh"] call SKL_fnc_CompileFinal;
["ITW_AtkStuckHandler"] call SKL_fnc_CompileFinal;
["ITW_AtkAddCrewToStatic"] call SKL_fnc_CompileFinal;
["ITW_AtkGetInfantryGroups"] call SKL_fnc_CompileFinal;
["ITW_AtkAirDropVeh"] call SKL_fnc_CompileFinal;
["ITW_AtkSafeGroupAllowDamage"] call SKL_fnc_CompileFinal;
["ITW_AtkSafeMove"] call SKL_fnc_CompileFinal;
["ITW_AtkSafeSetVectorUp"] call SKL_fnc_CompileFinal;
["ITW_AtkParachute"] call SKL_fnc_CompileFinal;
["ITW_AtkGetRealType"] call SKL_fnc_CompileFinal;
["ITW_AtkRoadDebug"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinWave"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinWaveUI"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinwWaveMoveToSeat"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinWaveSwap"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinWaveSwapLocal"] call SKL_fnc_CompileFinal;
["ITW_AtkJoinWaveSwapAddActions"] call SKL_fnc_CompileFinal;
["ITW_AtkTranspSuccess"] call SKL_fnc_CompileFinal;
["ITW_AtkVehRemoveMagazines"] call SKL_fnc_CompileFinal;
["ITW_AtkMgrDebugVehs"] call SKL_fnc_CompileFinal;
["ITW_AtkMoveOutVeh"] call SKL_fnc_CompileFinal;
["ITW_Debug"] call SKL_fnc_CompileFinal;
["ITW_AtkAutoCombatDisabled"] call SKL_fnc_CompileFinal;
["ITW_AtkDefendStart"] call SKL_fnc_CompileFinal;
["ITW_AtkDefendDone"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadProtect"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadProtUnit"] call SKL_fnc_CompileFinal;
["ITW_AtkGetOverflowTeammateJoinWave"] call SKL_fnc_CompileFinal;
["ITW_AtkUnloadPlayerTeammates"] call SKL_fnc_CompileFinal;