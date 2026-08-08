/*
How garrison works
- when no enemy nearby and flag captured and not already garrisoned
- find nearby (non-static) group(s) (1 to 3 full groups), num units = min 6 to ((#units = maxUnitsPerSide/numContestedObj)/2)  max 18
- randomly choose building(s) in zone to populate
- keep group together, put into building pos, use LV safer building pos
- at random interval have AI move to other building pos if extra pos, if not enough pos, have some contantly patrol inside
- don't let them lay down
*/

ItwGarrisonId = 1;
ITW_Garrisons = createHashMap; // maps garrison index to garrison data [center,size,maxGrps,side,[[units,building,bldPositions],...]]
#define GRSN_IDX_CENTER  0
#define GRSN_IDX_SIZE    1
#define GRSN_IDX_MAX_GRP 2
#define GRSN_IDX_SIDE    3
#define GRSN_IDX_GRPS    4 // this is an array of: ["_units",["_bldg",objNull],["_bldPositions",[]],["_usedPositions",[]]]
#define GRSN_EMPTY_INFO  [0,0,99,west,[]]

#include "defines.hpp"

#define DEBUG_LOG //diag_log

GRSN_INDEX = 0;
GRSN_RUNNING = false;
ITW_GrsnSem = false;

#if __has_include("\z\ace\addons\main\script_component.hpp")
#define ALIVE(unit) (lifeState unit in ["HEALTHY","INJURED"])
#else
#define ALIVE(unit) (alive unit)
#endif

ITW_Garrison = {
    // called on server
    scriptName "ITW_Garrison";
    params ["_center","_size","_groups","_objIdx"];
    // _center is used as garrison id, if garrison at center already exists new group will be added
    if (!isServer || {_groups isEqualTo []}) exitWith {};
    if (typeName _groups isEqualTo "GROUP") then {_groups = [_groups]};
    private _garIndex = if (typeName _center isEqualTo "ARRAY") then {mapGridPosition _center} else {_center};
    private _side = side (_groups#0);
    
    // don't garrison until add buildings are in place
    private _timeout = time + 60;
    waitUntil {_objIdx in ITW_genStructuresComplete || {time > _timeout}};
    if (ITW_ParamDamageBuildings > 0) then {sleep 5}; // give a little longer if an earthquake is about to destroy buildings
    
    SEM_LOCK(ITW_GrsnSem);
    private _garrisonInfo = (ITW_Garrisons getOrDefault [_garIndex,[_center,_size,99,_side,[]]]);
    
    // if another side is garrisoned here, free the up for the new side
    if !(_side isEqualTo _garrisonInfo#GRSN_IDX_SIDE) then {
        [_garIndex] call ITW_GrsnDone;
        _garrisonInfo = (ITW_Garrisons getOrDefault [_garIndex,[_center,_size,99,_side,[]]]);
    };
    
    {
        private _objIdx = VAR_GET_OBJ_IDX(_x);
        private _units = units _x;
        {
            private _unit = _x;
            if !(leader _unit == _unit) then {
                private _grp = createGroup [side _unit,false];
                [_unit] joinSilent _grp;
                _grp deleteGroupWhenEmpty true;
                VAR_SET_OBJ_IDX(_grp,_objIdx);
                if (side _unit == ITW_PlayerSide) then {{_x hcSetGroup [_grp]} forEach ITW_HcCmdr};
                _unit setVariable ["lambs_danger_disableAI", true];
            };
            private _grp = group _unit;
            _grp setVariable ["ITW_Garrison",true];
            // disable ai mods on garrisoned groups
            _grp setVariable ["lambs_danger_disableGroupAI", true];
            _grp setVariable ["Vcm_Disable",true];
        } forEach _units;
        (_garrisonInfo#GRSN_IDX_GRPS) pushBack [_units];
    } forEach _groups;
    ITW_Garrisons set [_garIndex,_garrisonInfo];
    SEM_UNLOCK(ITW_GrsnSem);
    
    isNil {if (!GRSN_RUNNING) then {GRSN_RUNNING = true;0 spawn ITW_GrsnManager}};
};

ITW_IsGarrisoned = {
    private _grp = _this;
    _grp getVariable ["ITW_Garrison",false]
};
 
ITW_GarrisonSize = {
    params ["_center",["_side","any"]];
    // if _side is a string then all sides are used
    private _useSide = if (typeName _side isEqualTo "STRING") then {false} else {true};
    private _garIndex = if (typeName _center isEqualTo "ARRAY") then {mapGridPosition _center} else {_center};
    private _numUnits = 0;
    SEM_LOCK(ITW_GrsnSem);
    private _garrisonInfo = ITW_Garrisons getOrDefault [_garIndex,GRSN_EMPTY_INFO];
    private _maxGrps = _garrisonInfo#2;
    {
        private _units = _x#0; 
        if (isNil "_units" || {{ALIVE(_x)} count _units == 0}) then {
            (_garrisonInfo#GRSN_IDX_GRPS) deleteAt _forEachIndex
        } else {
            if (!_useSide || {side (_units#0) == _side}) then {
                _numUnits = _numUnits + ({ALIVE(_x)} count _units);
            };
        };
    } forEachReversed (_garrisonInfo#GRSN_IDX_GRPS);
    if (count (_garrisonInfo#GRSN_IDX_GRPS) >= _maxGrps) then {_numUnits = 1000}; // say we're full
    SEM_UNLOCK(ITW_GrsnSem);
    _numUnits;
};

ITW_GarrisonDone = {
    params [["_center",[]]];
    // if _center = [] then all garrisons of the given side will be released
    // if _side is a string then all sides are used
    SEM_LOCK(ITW_GrsnSem);
    if (_center isEqualTo []) exitWith {
        private _garrisonKeys = keys ITW_Garrisons;
        {
            [_x] call ITW_GrsnDone;
        } forEach _garrisonKeys;
        SEM_UNLOCK(ITW_GrsnSem);
    };
    
    private _garIndex = if (typeName _center isEqualTo "ARRAY") then {mapGridPosition _center} else {_center};
    [_garIndex] call ITW_GrsnDone;
    SEM_UNLOCK(ITW_GrsnSem);
};

ITW_GrsnDone = {
    // private version of ITW_GarrisonDone without the lock
    params ["_grsnIdx"];
    DEBUG_LOG ["ITW_Garrison: done",_grsnIdx];
    private _garrisonInfo = ITW_Garrisons getOrDefault [_grsnIdx,GRSN_EMPTY_INFO];
    {
        private _units = _x#0; 
        if (!isNil "_units") then {
            {
                private _grp = group _x;
                _grp setVariable ["ITW_Garrison",false]; 
                _grp setVariable ["ITW_OkayToReset",true];
                _grp setVariable ["lambs_danger_disableGroupAI", false];
                _grp setVariable ["Vcm_Disable",false];
            } forEach _units;
            (_garrisonInfo#GRSN_IDX_GRPS) deleteAt _forEachIndex;
            _units apply {_x setVariable ["lambs_danger_disableAI", false]};
        };
    } forEachReversed (_garrisonInfo#GRSN_IDX_GRPS);
    if (_garrisonInfo#GRSN_IDX_GRPS isEqualTo []) then {ITW_Garrisons deleteAt _grsnIdx};
};

ITW_GrsnBuilding = {
    params ["_center","_radius"];
    
    private _houseObjects = (nearestObjects [_center, ["building"], _radius]);
    {
        // no-buildings have building positions equal to [0,0,0] or are in my list
        private _bldg = _x;
        private _className = typeOf _bldg;
        private _vehClass = toLowerANSI getText(configFile >> "cfgVehicles" >> _className >> "vehicleClass"); 
        private _isOkay = !(isObjectHidden _bldg || {(_bldg buildingPos 1) isEqualTo [0,0,0]});
        if (_isOkay) then {
            {if (_x in _vehClass) exitWith {_isOkay = false}} forEach ["_vr","industrial","infrastructure","airport","lamps"];
        };
        if (_isOkay) then {
            {if (_x in _className) exitWIth {_isOkay = false}} forEach [
                // THESE MUST BE LOWER CASE - shared with SplitSecond
                "amphitheater", "ancienthead", "antenna", "billboard", "_boat_", "breakwater", "_bridge", "_camonet", "castle", "canal_dutch", "_cave_", "_center", "concreteblock", "crater", 
                "_church_","csla_mil_house","csla_ind_quarry","csla_pristresek_csla","csla_a_office02","csla_hospital_","csla_bunker_lovz36",
                "_decal_", "_dirt", "fireescape", "fortress", "fuelbladder", "hangar", "_houseblock_", "_hull", "land_dome", "_shop_city_", "land_gh_mainbuilding", "_latrine", "_left", 
                "_maroula_", "_mash_", "_molonlabe_", "multistory", "_panelak_", "_part0", "_pier", "_pillar", "_prekazka_", "quayconcrete", 
                "radar", "_rail_track", "_revetment_", "_right", "_debris_",
                "sidewalk", "silagestorage", "snipertree", "_stairs_", "stadium", "stockpile", "strawstack", "tent_", "_trench_", "tower", "trafostanica", "_tunnel_", "turbine", 
                "voltage", "_wall_","_Pier_","_PierLadder_","_LampHarbour",
                "vn_slum_03","vn_hanoi_station","vn_molo_krych","vn_hootch_","vn_barracks_04_wall","vn_cathedral","_hopper","vn_hue_gate","_lighthouse_","_mobilecrane_",
                "pedestriancrossing","vn_pen_","warehouseshelter","gunpit","_foxhole_","vn_o_bunker","_reflector_","_storagebin_","_shelter_narrow_","vn_scf_01_shed","vn_scf_01_generalbuilding",
                "vn_mine_01_warehouse","_heap_","vn_factory_main","drydock","watercooler","smalltank","land_vn_gh_","vn_barracks_04_f","helipad","rampart","market_stalls","gantrycrane",
                "vn_barracks_02","vn_guardhouse_02","_washer_","_wreck_traw","crystallizer","_bigtank","_storagetank_","fishingboat","bunker_big_","hut_village_","cmp_shed_dam",
                "condenser","vn_shed_big","_shower_","marketshelter","concreteramp","vn_fuelstation_01_roof","mortarpit","vn_hlaska_","municipaloffice","warehouse","boilerbuilding","containercrane",
                "jbad_terrace","jbad_fp","shredder","vn_addon_02","aeropuerto","casa_caseta_peq","_coltan_","opx2_vcp1","_lamp","_heap","rubble","_well_",
                "misc_well_c_u","ind_shed_02","_minaret","_boom","_stream_","most_stred","_curve","_river_","outside_living","kamenny_most","_trash",
                "ind_sawmill","ind_shed_01","_embassy_","cementworks","_airport_","vn_u_shed_ind","molo_beton","_part1","_part2","_part3","_part4",
                "vn_guardhouse","factory","_crane","vn_i_addon_","cmp_shed","dyke","reservoir","metalshelter","diffuser","_wall","vn_shed_small","buildingwip",
                "barn_metal","_indpipe","_heli_","majak_v","ind_pec","barn_w_01","dom_i1i","land_fuelstation","ind_mlyn","_silo","helfenburk_zed","_mausoleum_",
                "sklady_01_ruins","generalstore_01_ruins","ruin_corner","helfenburk_cimburi","_m_ruins","sara_domek","telek","bunker_01_ruins","boathouse",
                "apartmentcomplex","land_hut03","malykomin","dum_istan","podesta","benzina","kasarna_rohova","quarry","land_housev3_03","protectionzone","_construct2",
                "_angle","kostel","_craine","vez_pec","kasarna_brana","cathedral","manure","containerline","land_u_barracks_v2_f","_d_vsilo_","dam_concp_",
                "land_afdum_mesto","land_addon_05_f","land_shed_w4","land_orlhot","land_misc_powerstation","land_dum_mesto","land_dum_olez_istan2_maly2",
                "land_dum_olez_istan2_open_dam","land_terrace_","land_orthodoxchurch_03_f","land_barn_04_f","_ruins","_houseb_tenement","land_house_2w03_f","_cowshed_",
                "land_helfenburk","land_ind_tank","warfarebairport",
                // spearhead 1944
                "land_calvary_", "land_chickencoop_", "land_cmp_tower_", "land_concretewell", "land_cross_", "land_feedrack_", 
                "land_feedshack_", "land_feedstorage_", "land_grave_", "land_gravefence_", "land_hutch_", "land_lamp", "land_spe_bocage_",
                "land_spe_french_gate_", "land_spe_french_wall_", "land_spe_ger_lamp", "land_spe_haystack", "land_spe_mound_", "land_spe_onion_", "land_spe_pond", 
                "land_spe_river_", "land_spe_us_lamp", "land_spe_wood_fence_", "land_spe_wood_gate_", "land_spe_wood_trench", "land_stonewell_", "land_telephoneline_",
                // cups
                "land_d_vsilo_pec","land_molo_krychle","land_vysilac_","land_dam_","land_helfenburk_","land_mbg_shoothouse_1","pond_acr",
                // reaction forces
                "land_flexibletank"
            ];
        };
        if (!_isOkay) then {
            _houseObjects deleteAt _forEachIndex;
        };
    } forEachReversed _houseObjects;
 
    if(isNil("_houseObjects")) exitWith {[]};
    if((count _houseObjects)==0) exitWith {[]};

    _houseObjects;
};

ITW_GrsnGetBuildingPositions = compileFinal preprocessFileLineNumbers "fn_BetterBuildingPositions.sqf";

ITW_GrsnManager = {
    private _betterMoveTo = compileFinal preprocessFileLineNumbers "fn_BetterMoveTo.sqf";
    private _loopDelay = 10; // sleep this many seconds before checking for new units
    private _motionTime = 60; // about every this many seconds, one unit of a each group will wander the building
    private _randomCheck = _motionTime/_loopDelay;
    private _playerRange = ITW_ParamObjectiveSize + 800;
    private _buildingHashMap = createHashMap;
    while {!ITW_GameOver} do {
        private _garrisonsLost = [];
        private _unitToSetposAuto = [];
        SEM_LOCK(ITW_GrsnSem);
        {
            private _grsnIdx = _x;          
            private _garrisonInfo = _y;
            _y params ["_center","_size","_maxGrps","_side","_unitsInfo"];
            if (_unitsInfo isEqualTo []) then {continue};
            private _playersInZone = {_x distance _center < _playerRange} count playableUnits > 0;
            
            // check if units have lost the zone
            if ((_center call ITW_ObjIsNearestFriendly) != (_side == west)) then {
                DEBUG_LOG ["ITW_Garrison: Garrison lost",_grsnIdx];            
                _garrisonsLost pushBack _grsnIdx;
                continue
            };
            
            private _bldgInUse = [];
            {           
                _x params ["_units",["_bldg",objNull],["_bldPositions",[]],["_usedPositions",[]]];
                if ({ALIVE(_x)} count _units == 0) then {
                    _unitsInfo deleteAt _forEachIndex;
                } else {
                    if (!isNull _bldg) then {_bldgInUse pushBack _bldg};
                };
            } forEachReversed _unitsInfo;
            
            private _overflowObjIdx = -1;
            {
                private _thisGrpInfo = _x;
                _x params ["_units",["_bldg",objNull],["_bldPositions",[]],["_usedPositions",[]]];
                private _overflowUnits = [];
                private _returnUnits = [];
                if (isNull _bldg) then {
                    // this takes some time, so we need to unlock the sem, make a copy of info so we know if it was changed
                    private _prevGrpInfo = +_thisGrpInfo; 
                    SEM_UNLOCK(ITW_GrsnSem);
                    if (count _bldgInUse >= _maxGrps) exitWith {
                        _returnUnits append _units;
                    };
                    // new group, assign to a building
                    _buildings = _buildingHashMap getOrDefault [_grsnIdx,nil];
                    if (isNil "_buildings") then {
                        _buildings = [_center,_size] call ITW_GrsnBuilding;
                        _buildingHashMap set [_grsnIdx,_buildings];
                        DEBUG_LOG ["ITW_Garrison: Garrison buildings",_grsnIdx,count _buildings];            
                    };
                    _bldg = selectRandom (_buildings - _bldgInUse);
                    if (isNil "_bldg" || {isNull _bldg}) exitWith {
                        _garrisonInfo set [2,count _bldgInUse];
                        _returnUnits append _units;
                    };
                    _bldgInUse pushBack _bldg;
                    _bldPositions = [_bldg] call ITW_GrsnGetBuildingPositions;
                    SEM_LOCK(ITW_GrsnSem);
                    if !(_prevGrpInfo isEqualTo _thisGrpInfo) exitWith {};
                    _thisGrpInfo set [1,_bldg];
                    _thisGrpInfo set [2,_bldPositions call BIS_fnc_arrayShuffle];
                    _usedPositions = [];
                    private _buildingPos = getPosATL _bldg;
                    private _playersNearby = {_buildingPos distance _x < 1000} count playableUnits > 0;
                    private _posIdx = 0;
                    private _maxInThisBuilding = 3 + random 5;
                    {
                        private _unit = _x;
                        if (!ALIVE(_unit)) then {continue};
                        if (count _bldPositions > _posIdx && {_posIdx < _maxInThisBuilding}) then {
                            private _pos = _bldPositions#_posIdx;
                            _posIdx = _posIdx + 1;
                            _usedPositions pushBack _pos;
                            _unit setVariable ["itwgmBPos",_pos];
                            if (true) then { //_playersNearby) then {
                                [_unit,_pos,_bldg] call _betterMoveTo;
                            } else {
                                _unit setPosATL _pos;
                                doStop _unit;
                            };
                        } else {
                            // more units than positions, set them up for a new building
                            _overflowUnits pushBack _unit;
                        };
                    } forEach _units;
                    _thisGrpInfo set [3,_usedPositions];
                    DEBUG_LOG ["ITW_Garrison: garrisoning",_grsnIdx,count _units,"in",typeOf _bldg,"overflow",count _overflowUnits];
                } else {
                    {
                        private _unit = _x;
                        private _pos = _unit getVariable ["itwgmBPos",[]];
                        if (_unit distance _pos > 5 && {!(_unit setVariable ["BMT_moving",false])}) then {
                            DEBUG_LOG ["ITW_Garrison: regroup",_grsnIdx,_unit,_unit distance _pos,_pos];                            
                            [_unit,_pos,_bldg] call _betterMoveTo;
                        };
                    } forEach _units;
                };
                
                // don't bother with some unit handling if players are not nearby
                if (_playersInZone) then {
                    {
                        // don't let units lay down in buildings as they shoot through the floor
                        private _unit = _x;
                        if (stance _unit == "PRONE" 
                                && {behaviour _unit in ["AWARE","COMBAT"] 
                                && {canStand _unit 
                                && {currentWeapon _unit != ""
                                }}}) then {
                            _unit setUnitPos "MIDDLE";
                            _unitToSetposAuto pushBack _unit;
                        };

                        // put up on floor if needed
                        private _pos = _unit getVariable ["itwgmBPos",[-10,-10,-10]];
                        if (_unit distance2D _pos < 2) then {
                            private _elevationDiff = (ATLtoASL _pos)#2 - (getPosASL _unit #2);
                            if (abs _elevationDiff > 0.25 && {{_x distance2D _pos < 12} count playableUnits == 0}) then {
                                _unit setPosATL _pos;
                            };
                        };
                    } forEach _units;
                    
                    // random chance units will move around in the building 
                    if (random _randomCheck <= 1) then {
                        private _availPos = _bldPositions - _usedPositions;
                        if (_availPos isEqualTo []) then {
                            // no spare positions, swap two units
                            private _unit1 = selectRandom _units;
                            if (isNil "_unit1") exitWith {};
                            private _unit2 = selectRandom (_units select {!(_x isEqualTo _unit1)});
                            if (isNil "_unit2") exitWith {};
                            private _pos1 = _unit1 getVariable ["itwgmBPos",[]];
                            private _pos2 = _unit2 getVariable ["itwgmBPos",[]];
                            if (_pos1 isEqualTo []) then {_unit2 doMove (getPosATL _unit2)} else {
                                _unit2 setVariable ["itwgmBPos",_pos1];
                                [_unit1,_pos1,_bldg] call _betterMoveTo
                            };
                            if (_pos2 isEqualTo []) then {_unit1 doMove (getPosATL _unit1)} else {
                                _unit1 setVariable ["itwgmBPos",_pos2];
                                [_unit2,_pos2,_bldg] call _betterMoveTo;
                            };
                            DEBUG_LOG ["ITW_Garrison: swap positions",_grsnIdx,_unit1,_unit2];
                        } else {
                            private _unit1 = selectRandom _units;
                            private _pos1 = _unit1 getVariable ["itwgmBPos",[]];
                            private _pos2 = selectRandom _availPos;
                            if (isNil "_pos2") then {_unit1 doMove (getPosATL _unit1)} else {
                                _unit1 setVariable ["itwgmBPos",_pos2];
                                [_unit1,_pos2,_bldg] call _betterMoveTo;
                                _usedPositions = _usedPositions - [_pos1];
                                _usedPositions pushBack _pos2;
                                _thisGrpInfo set [3,_usedPositions];
                                DEBUG_LOG ["ITW_Garrison: moving",_grsnIdx,_unit1];
                            };
                        };
                    };
                };
                
                private _deadUnits = _units select {!ALIVE(_x) || {vehicle _x != _x}};
                if !(_deadUnits isEqualTo []) then {
                    _units = _units - _deadUnits;
                    _thisGrpInfo set [0,_units];
                };
                
                // units to return to the infantry manager
                if !(_returnUnits isEqualTo []) then {
                    {group _x setVariable ["ITW_Garrison",false]} forEach _returnUnits;
                    _units = _units - _returnUnits;
                    if (_units isEqualTo []) then {
                        (_garrisonInfo#GRSN_IDX_GRPS) deleteAt _forEachIndex
                    } else {
                        _thisGrpInfo set [0,_units];
                    };
                };
                
                // units to put in other buildings
                if !(_overflowUnits isEqualTo []) then {           
                    _units = _units - _overflowUnits;
                    _thisGrpInfo set [0,_units]; // remove overflow units from current building assignment
                    _unitsInfo pushBack [_overflowUnits]; // create a new building assignment
                };
            } forEach _unitsInfo;
        } forEach ITW_Garrisons;
        
        {      
            [_x] call ITW_GrsnDone;
        } forEach _garrisonsLost;
        
        SEM_UNLOCK(ITW_GrsnSem);
        sleep _loopDelay;
        while {LV_PAUSE} do {sleep 5};
        {_x setUnitPos "AUTO"} forEach _unitToSetposAuto;
    };
};

ITW_GrsnGetGroups = {
    params ["_side"];
    private _result = [];
    {
        private _gInfo = _y;
        if (_gInfo#GRSN_IDX_SIDE == _side) then {
            {
                private _units = _x#0;
                _result append (_units apply {group _x});
            } forEach _gInfo#GRSN_IDX_GRPS;
        };
    } forEach ITW_Garrisons;
    _result
};

["ITW_Garrison"] call SKL_fnc_CompileFinal;
["ITW_IsGarrisoned"] call SKL_fnc_CompileFinal;
["ITW_GarrisonSize"] call SKL_fnc_CompileFinal;
["ITW_GarrisonDone"] call SKL_fnc_CompileFinal;
["ITW_GrsnDone"] call SKL_fnc_CompileFinal;
["ITW_GrsnBuilding"] call SKL_fnc_CompileFinal;
["ITW_GrsnManager"] call SKL_fnc_CompileFinal;
["ITW_GrsnGetGroups"] call SKL_fnc_CompileFinal;
