
//#define OBJ_DEBUG_ZONES true
#include "defines.hpp"
#include "defines_gui.hpp"
#include "\a3\ui_f\hpp\definedikcodes.inc"

ITW_Objectives = []; // array of ["_aoPos","_aoSize","_marker","_name","_flag","_taskId","_zoneIdx","_captured","_attackVectors","_baseIndex"]...];
ITW_Zones = []; // array of objective indexes [_zone0IndexArray,_zone1IndexArray,...],  #0 is players starting base
ITW_ZoneIndex = 0;   // the contested zone
ITW_SeaPoints = [];
ITW_FlagsActive = [objNull,objNull];
ITW_GameOver = false; 
ITW_KeepOutSize = 1000; // size of keep out zone around enemy bases
ITW_ObjZonesUpdating = false; // allow threads to pause while we update for the next zone
ITW_ObjContestedState = []; // array of arrays of [objIdx,is fully captured by players,target completion state]
ITW_ObjShowArty = false; // if true, artillery hits will show on host's map
ITW_ZoneKeepOut = 1000;
ITW_ZoneKeepOutSqr = 1e6;
ITW_genStructuresComplete = [];
ITW_defendPhaseFlagCount = -1;
ITW_defendPhaseObjIdx = -1;
ITW_defendRunning = false;
ITW_objStartedTime = 0;
ITW_defendPhaseZoneDone = -1;

#define END_ZONE_LETTER    " "

// zone state will be zone number if inactive red, zones count from zero (player's base zone)
#define OBJ_STATE_INACTIVE_BLUE -3
#define OBJ_STATE_ACTIVE_BLUE   -2
#define OBJ_STATE_ACTIVE_RED    -1
#define OBJ_STATE_INACTIVE_RED  0  // or higher

#if __has_include("\z\ace\addons\main\script_component.hpp")
#define CONSCIOUS(unit) (!(unit getVariable ["ACE_isUnconscious", false]))
#else
#define CONSCIOUS(unit) (lifeState unit in ["HEALTHY","INJURED"])
#endif

#define WAIT_FOR_BASE_MAP(BM_MSG,BM_OBJ) \
    private _doBaseMsg = false;          \
   if (BM_OBJ select ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS) then {_doBaseMsg = true; diag_log format ["%1 waiting for base map %2",BM_MSG,BM_OBJ select ITW_OBJ_INDEX]}; \
   while {BM_OBJ select ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS} do {sleep 1}; \
   if (_doBaseMsg) then {diag_log format ["%1 done waiting for base map",BM_MSG]};

ITW_ShowSeaPoints = {
    if (isNil "ITW_SPMRK") then {ITW_SPMRK = []};
    {deleteMarker _x} forEach ITW_SPMRK;
    {
      _spIdx = _forEachIndex;
      {
       _m = createMarker ["ms"+str _spIdx + "-" +str _forEachIndex,_x];
       ITW_SPMRK pushBack _m;
       _m setMarkerType "hd_dot";
      } foreach _x;
    } foreach ITW_SeaPoints;
};

ITW_ShowAllObjectives = {
    params [["_show",true]];
    { if ((_x find "obj#") == 0) then { deleteMarker _x }; } forEach allMapMarkers;
    if (typeName _show != "BOOL") then {_show = true};
    #define ZONE_BUFFER 800
    
    if (_show) then {
        private _cnt = count ITW_Objectives - 2;
        {
            private _mrkr = createMarkerLocal ["obj#"+str _forEachIndex,_x#ITW_OBJ_POS];
            _mrkr setMarkerShapeLocal "ELLIPSE";
            _mrkr setMarkerSizeLocal [_x#ITW_OBJ_SIZE,_x#ITW_OBJ_SIZE];
            _mrkr setMarkerColorLocal (if (_forEachIndex == 0) then {"ColorBlue"} else {if (_forEachIndex < _cnt) then {"ColorBlack"} else {"ColorRed"}});
            private _mrkrT = createMarkerLocal ["obj#T#"+str _forEachIndex,ITW_Bases#(_x#ITW_OBJ_INDEX)#ITW_BASE_POS];
            _mrkrT setMarkerTypeLocal "loc_Frame";
            _mrkrT setMarkerTextLocal ((_x#ITW_OBJ_NAME)+":"+str _forEachIndex);
            _mrkrT setMarkerSizeLocal [0.5,0.5];
            _mrkrT setMarkerColorLocal (if (_forEachIndex == 0) then {"ColorBlue"} else {if (_forEachIndex < _cnt) then {"ColorBlack"} else {"ColorRed"}});
        } forEach ITW_Objectives;
        
        {
            private _pointIndices = _x;
            private _count = count _pointIndices;
            private _zoneNum = _forEachIndex;
            
            private _mName = format ["obj#zone_%1", _zoneNum];
            private _tName = format ["obj#zone_%1_txt", _zoneNum];

            private _positions = _pointIndices apply { (ITW_Objectives#_x)#ITW_OBJ_POS };
            private ["_center", "_width", "_height", "_dir"];

            switch (true) do {
                case (_count == 1): {
                    _center = _positions#0;
                    _width = ZONE_BUFFER; _height = ZONE_BUFFER; _dir = 0;
                };
                case (_count == 2): {
                    private _sumX = 0; private _sumY = 0;
                    { _sumX = _sumX + (_x#0); _sumY = _sumY + (_x#1); } forEach _positions;
                    _center = [_sumX / _count, _sumY / _count, 0];
                    _dir = _positions#0 getDir (_positions#1);
                    _height = (_positions#0 distance (_positions#1))/2 + (ZONE_BUFFER);
                    _width = _height/4;
                };
                default {
                    // Find the center of the zone
                    private _sumX = 0; private _sumY = 0;
                    { _sumX = _sumX + (_x#0); _sumY = _sumY + (_x#1); } forEach _positions;
                    _center = [_sumX / _count, _sumY / _count, 0];

                    // Find the longest axis and direction
                    private _furthestDist = 0;
                    private _pStart = _positions#0; 
                    private _pEnd = _positions#0;
                    {
                        private _curr = _x;
                        {
                            private _d = _curr distance _x;
                            if (_d > _furthestDist) then { _furthestDist = _d; _pStart = _curr; _pEnd = _x; };
                        } forEach _positions;
                    } forEach _positions;

                    _dir = _pStart getDir _pEnd;

                    // 3. Calculate width/height in relative to rotation
                    private _minLocalX = 1e10; private _maxLocalX = -1e10;
                    private _minLocalY = 1e10; private _maxLocalY = -1e10;
                    
                    // Negative angle to align points to north
                    private _angleRad = -(_dir * pi / 180);
                    private _cosA = cos _angleRad;
                    private _sinA = sin _angleRad;

                    {
                        // calulate point relative to center
                        private _relX = (_x#0) - (_center#0);
                        private _relY = (_x#1) - (_center#1);

                        // Rotate point
                        private _rotX = (_relX * _cosA) - (_relY * _sinA);
                        private _rotY = (_relX * _sinA) + (_relY * _cosA);

                        _minLocalX = _minLocalX min _rotX; _maxLocalX = _maxLocalX max _rotX;
                        _minLocalY = _minLocalY min _rotY; _maxLocalY = _maxLocalY max _rotY;
                    } forEach _positions;

                    _width = ((_maxLocalX - _minLocalX) / 2) + ZONE_BUFFER;
                    _height = ((_maxLocalY - _minLocalY) / 2) + ZONE_BUFFER;
                };
            };
            
            if (_height < _width) then {private _tmp = _width; _width = _height ; _height = _tmp};
            
            createMarker [_mName, _center];
            _mName setMarkerShape "ELLIPSE";
            _mName setMarkerSize [_width, _height]; // Correctly mapped to local axes
            _mName setMarkerDir _dir;
            _mName setMarkerBrush "SolidBorder";
            _mName setMarkerColor "ColorOrange";
            _mName setMarkerAlpha 0.4;

            createMarker [_tName, _center];
            _tName setMarkerType "EmptyIcon";
            _tName setMarkerText (format ["Zone %1", _zoneNum]);
            _tName setMarkerColor "ColorOrange";

        } forEach ITW_Zones;
    };
};

ITW_ObjectivesSetup = {
    params ["_fromSave"];
    
    if (!_fromSave) then {
        0 call ITW_ObjGetObjectives;
        true call ITW_ObjGetZones;
    } else {
        ITW_ParamStartWithZonesCaptured = 0; // only used when creating a new game
        ["itw",[localize "STR_ITW_OBJ_SettingUpObjectives","BLACK OUT",0.001]] remoteExec ["cutText",0,false];  
    };
    
    // setup vehicle spawn points on roads
    {
        private _obj = _x;
        [_obj] call ITW_ObjSetVehicleSpawn;
    } forEach ITW_Objectives;   
    
    // ensure contested objectives are marked as such
    {
        ITW_Objectives#_x#ITW_OBJ_OWNER == ITW_OWNER_CONTESTED;
    } forEach (ITW_Zones#ITW_ZoneIndex);
    
    _fromSave call ITW_CreateBases;  

    if (!_fromSave) then {
        // handle the final enemy spawn point that is out to sea
        private _pos = false call ITW_ObjGetOutToSeaPos;
        _obj = INIT_OBJECTIVE;
        _obj set [ITW_OBJ_POS,_pos];
        _obj set [ITW_OBJ_V_SPAWN,_pos];
        _obj set [ITW_OBJ_INDEX,count ITW_Bases];
        _obj set [ITW_OBJ_NAME,"Enemy Attack Corridor"];
        _obj set [ITW_OBJ_ZONEID,count ITW_Zones - 1];
        _obj set [ITW_OBJ_HIDDEN,true];
        _obj set [ITW_OBJ_MARKER,"obj-enemyAttack"];
        if (ITW_ParamObjectiveVariation in [1,3]) then {
            _obj set [ITW_OBJ_SIZE,round (ITW_ParamObjectiveSize * (0.75 + random 0.5))];
        };
        ITW_Objectives pushBack _obj;
        
        private _base = EMPTY_BASE;
        _base set [ITW_BASE_POS,_pos];
        _base set [ITW_BASE_A_SPAWN,_pos];
        ITW_Bases pushBack _base;
    } else {
        [false,ITW_Objectives#-1#ITW_OBJ_POS] call ITW_ObjSetOutToSeaPos;
    }; 
  
    if (isNil "VEHICLE_ARRAYS_COMPLETE") then {["itw",[localize "STR_ITW_START_ParsingVehicles", "BLACK OUT", 0.001]] remoteExec ["cutText",0,false]}; 
    waitUntil {! isNil "VEHICLE_ARRAYS_COMPLETE"};
    ["itw",[localize "STR_ITW_OBJ_PopulatingObjectives", "BLACK OUT", 0.001]] remoteExec ["cutText",0,false];
    _fromSave call ITW_ObjNext;
    
    // add flag options
    private _flags = [];
    {
        private _flag = _x#ITW_OBJ_FLAG;
        private _pos = ITW_Bases#_forEachIndex#ITW_BASE_GARAGE_POS;
        _flags pushBack [_flag,_pos];
        [_x,ITW_ZoneIndex] call ITW_ObjSetMarker;
    } forEach ITW_Objectives;
    [_flags] remoteExec ["ITW_ObjFlagMP",0,true];
     
    // calculate sea points
    {
        private _objPt = _x#ITW_OBJ_POS;
        private _objSize = _x#ITW_OBJ_SIZE;
        private _seaPts = [];
        private _minDistToSea = 100;
        private _maxDistToSea = 500 + _objSize;
        private _minDepth = -0.5;
        for "_d" from 0 to 359 step 15 do {
            private _cnt = 0;
            for "_r" from _minDistToSea to _maxDistToSea step 10 do {
                private _pos = _objPt getPos [_r,_d];
                if (surfaceIsWater _pos && {getTerrainHeightASL _pos < _minDepth}) then {
                    private _fromPosASL = +_pos;
                    _fromPosASL set [2,0];
                    private _toPosASL = +_fromPosASL;
                    _toPosASL set [2,20];
                    private _surfaces = lineIntersectsSurfaces [_fromPosASL, _toPosASL, objNull, objNull, true, 1, "GEOM", "NONE", true];
                    if (_surfaces isEqualTo []) then {_cnt = _cnt + 1} else {_cnt = 0};
                } else {
                    _cnt = 0;
                };
                if (_cnt >= 10) exitWith {_seaPts pushBack _pos};
            };
        };
        if (count _seaPts < 5) then {_seaPts = []}; // at least 5 points required
        ITW_SeaPoints pushBack _seaPts;
    } forEach ITW_Objectives;
    
    private _seaIsViable = {count _x > 0} count ITW_SeaPoints > 1;
    if (!_seaIsViable) then {
        va_pShipClassesTransport = [];
        va_eShipClassesTransport = [];
        va_cShipClassesTransport = [];
        va_pShipClassesAttack = [];
        va_eShipClassesAttack = [];
        va_cShipClassesAttack = [];
        va_pShipClassesDual = [];
        va_eShipClassesDual = [];
        va_cShipClassesDual = [];
    }; 
    
    for "_i" from 1 to ITW_ParamStartWithZonesCaptured do {
        false call ITW_ObjNext;
    };
            
    0 call ITW_ObjCreateNearestBasesMap;
    0 spawn ITW_ObjFlagTask; 
    0 spawn ITW_ObjArtillery; 
    
    //{diag_log ["Zone",_forEachIndex,_x]} forEach ITW_Zones; 
    //{diag_log ["OBJ",_forEachIndex,_x]} forEach ITW_Objectives;
    //{diag_log ["Base",_forEachIndex,_x]} forEach ITW_Bases; 
    
    ITW_objStartedTime = time;
};
    
ITW_ObjGetObjectives = {        
    // constants
    private _objInCities = true;
    private _numBldgsSize = 100;
    private _blacklist = ["water"];
    private _worldSize = worldSize/2; 
    private _worldSizeMargin = _worldSize - 400;
    private _whiteList = [[[_worldSize,_worldSize],[_worldSizeMargin,_worldSizeMargin,0,true]]]; // defaults to whole map
    
    switch (toLowerANSI worldname) do {
        case "cam_lao_nam": {
            // cam lao nam tunnels don't really work
            _blacklist = ["water",
                [[350,     16979.3, 0],1000],
                [[253.172, 18696.2, 0],1000],
                [[556.726, 20229.9, 0],1000],
                [[2730.52, 20066.4, 0],1000],
                [[4252.47, 20084.8, 0],1000],
                [[5769.42, 20088.9, 0],1000]
            ];
        };
        case "zargabad": {
            _whiteList = [[[4250,4000],[750,700,0,true]]];
        };
        case "stozec": {
            _blacklist = ["water",
                [[11100, 5800, 0],500]
            ];
        };
    };
    
    // clear objectives if we're re-making them
    {
        _x params ["_center","_size","_marker"];
        deleteMarker _marker;
    } count ITW_Objectives;
    ITW_Objectives = [];
    
    if (ITW_ParamObjectiveCount == 0) then {
        // player chooses locations
        // just setup with player and enemy and one objective for the player to edit
        private _w2 = worldSize / 2;
        private _w4 = worldSize / 4;
        // player base
        private _obj = INIT_OBJECTIVE;
        _obj set [ITW_OBJ_POS,[_w4,_w2]];
        _obj set [ITW_OBJ_NAME,call ITW_ObjGetRandomName];
        _obj set [ITW_OBJ_SIZE,ITW_ParamObjectiveSize]; // random variation happens after players may have moved them around
        ITW_Objectives pushBack _obj;
        // one objective
        _obj = INIT_OBJECTIVE;
        _obj set [ITW_OBJ_POS,[_w2,_w2]];
        _obj set [ITW_OBJ_NAME,call ITW_ObjGetRandomName];
        _obj set [ITW_OBJ_SIZE,ITW_ParamObjectiveSize]; 
        // enemy base
        ITW_Objectives pushBack _obj;
        _obj = INIT_OBJECTIVE;
        _obj set [ITW_OBJ_POS,[_w2+_w4,_w2]];
        _obj set [ITW_OBJ_NAME,call ITW_ObjGetRandomName];
        _obj set [ITW_OBJ_SIZE,ITW_ParamObjectiveSize]; 
        ITW_Objectives pushBack _obj;
    };
    
    if (ITW_ParamObjectiveCount > 0) then {
        // algorithm chooses objective locations
        // Determine appropriate number of objectives based on world size
        private _objectiveSpacing = 1500/ITW_ParamObjectiveCount + ITW_ParamObjectiveSize;
        private _landSqKm = 0;
        private _seaSqKm = 0;
        for "_i" from 500 to worldSize step 1000 do {
            for "_j" from 500 to worldSize step 1000 do {
                private _pos = [_i,_j,0];
                if (surfaceIsWater _pos && {getTerrainHeightASL _pos < -5}) then {
                    _seaSqKm = _seaSqKm + 1;
                } else {
                    _landSqKm = _landSqKm + 1;
                };
            };
        };
        private _objSuggestedCnt = (_landSqKm / 5) min 50; // don't add more than 50 objectives
        private _objCnt = floor (_objSuggestedCnt * (ITW_ParamObjectiveCount/10)) max (ITW_ParamObjectivesPerZone + 2);    
        diag_log format ["ITW: Obj Count: suggested %1  (Land %2 sqkm) adjusted to %3 based on parameter setting",floor _objSuggestedCnt,_landSqKm, _objCnt];
        private _prevNumBldsFound = 50;
        // Find all the objectives
        for "_i" from 1 to _objCnt do {
            ["itw",[format [localize "STR_ITW_OBJ_SettingUpFMT",_i,_objCnt],"BLACK OUT",0.001]] remoteExec ["cutText",0,false];  
            private _aoPos = [];
            private _aoSize = 100;
            private _nearby = [];
            private _okay = false;
            
            // we will search for buildings _loopCnt times, and reduce the number of buildings required from the limit to 0 across those 500 tries
            private _loopCnt = 500;
            private _minNumberOfBuildings = (_prevNumBldsFound + 10) min ITW_ParamObjectiveInTowns;
            private _numBldsStep = _minNumberOfBuildings/_loopCnt;
            
            while {!_okay && {_loopCnt > 0}} do {
                _loopCnt = _loopCnt - 1;
                _aoPos = [_whitelist, _blacklist] call BIS_fnc_randomPos;
                if (count _aoPos == 2) exitWith {diag_log "ITW_ObjGetObjectives: quit looking because BIS_fnc_randomPos has given up"};
                if (_objInCities) then {              
                    _minNumberOfBuildings = _minNumberOfBuildings - _numBldsStep;
                    if (_loopCnt == 0) then {
                        // give up on cities
                        _objInCities = false;
                        _loopCnt = 200;
                    };
                    _bldg = nearestBuilding _aoPos;
                    if ((_bldg distance2D _aoPos) < 800) then {
                        _nearby = [_bldg, _numBldgsSize] call ITW_ObjNearestBuildings;
                        if (count _nearby >= _minNumberOfBuildings) then {
                            _okay = true;
                            _aoPos = [_nearby] call ITW_ObjCenter;
                        };
                    };
                } else {
                    _okay = true;
                };
                if (_okay) then {
                    // make sure we're not too close to another AO
                    {
                        private _otherAoCenter = _x#ITW_OBJ_POS;
                        if (_aoPos distance2D _otherAoCenter < _objectiveSpacing) exitWith {_okay = false};
                    } count ITW_Objectives;
                    
                    if (_okay) then {
                        _prevNumBldsFound = _minNumberOfBuildings;
                        // recenter
                        _aoSize = ITW_ParamObjectiveSize;
                        _nearby = [_aoPos, _aoSize/2] call ITW_ObjNearestBuildings;
                        if (count _nearby > 0) then {
                            private _centeredPos = [_nearby] call ITW_ObjCenter;
                            // make sure we're still not too close to another AO
                            {
                                private _otherAoCenter = _x#ITW_OBJ_POS;
                                if (_centeredPos distance2D _otherAoCenter < _objectiveSpacing) exitWith {_centeredPos = _aoPos};
                            } count ITW_Objectives;
                            _aoPos = _centeredPos;
                        };
                    };
                };
            }; 
            if (!_okay) exitWith {diag_log "ITW_ObjGetObjectives: quit looking because we've tried too many times"};// quit adding locations as there are none left
                        
            _blacklist pushBack [_aoPos,1500];
            
            private _obj = INIT_OBJECTIVE;
            _obj set [ITW_OBJ_POS,_aoPos];
            _obj set [ITW_OBJ_NAME,call ITW_ObjGetRandomName];
            _obj set [ITW_OBJ_SIZE,ITW_ParamObjectiveSize]; // random variation happens after players may have moved them around
            ITW_Objectives pushBack _obj;
        };
    };
};

ITW_ObjGetRandomName = {
    private _alternateNames = ["Apple","Brother","Continental","Dover","Eastern","Father","George","Harry","Ivy","Joker",
                               "King","London","Mother","Nobel","October","Peter","Quigley","Robert","Sugar","Thomas",
                               "Uncle","Victoria","Wednesday","Xmas","Yellow","Zebra","Amsterdam","Baltimore","Casablanca","Denmark",
                               "Edison","Florida","Golf","Havana","India","Juliett","Kilogramme","Liverpool","Madagascar","New York",
                               "Oslo","Paris","Queen","Roma","Santiago","Tripoli","Uppsala","Valencia","Washington","Xanthippe","Yokohama","Zurich"
                              ];
    private _altNameCount = count _alternateNames;
    if (isNil "ITW_OBJ_AltNameIdx") then {ITW_OBJ_AltNameIdx = floor random _altNameCount};
    _aoText = _alternateNames#(ITW_OBJ_AltNameIdx mod _altNameCount);
    ITW_OBJ_AltNameIdx = ITW_OBJ_AltNameIdx + 1;
    _aoText
};

ITW_ObjMoving = {
    params ["_viewEditZonesForce"];
    missionNamespace setVariable ["ITW_OBJ_MOVE_DONE",nil];
    // choose who will pick locations
    if (isDedicated) then {        
        // if using a dedicated server, use a the first player to choose 
        waitUntil {count (call BIS_fnc_listPlayers) > 0};
        private _playerClient = owner ((call BIS_fnc_listPlayers)#0);
        [false] remoteExec ["ITW_ObjMovingMP",-(_playerClient),true];
        [true,ITW_Objectives,_viewEditZonesForce] remoteExec ["ITW_ObjMovingMP",_playerClient];
    } else {
        // hosted server, so just let the host choose 
        [false] remoteExec ["ITW_ObjMovingMP",-2,true];
        sleep 1; // need a sleep since some cutText remoteExec calls may still be in the pipe
        [true,ITW_Objectives,_viewEditZonesForce] call ITW_ObjMovingMP;
    };
    waitUntil {sleep 0.5; missionNamespace getVariable ["ITW_OBJ_MOVE_DONE",false]};
    private _viewEditZones = missionNamespace getVariable ["ITW_OBJ_MOVE_EDITING",false];
    private _objMoved = false;
    if (_viewEditZones) then {
        _objMoved = missionNamespace getVariable ["ITW_OBJ_MOVE_CHANGED",false];
        if (_objMoved) then {
            ITW_Objectives = missionNamespace getVariable ["ITW_OBJ_MOVE_OBJS",ITW_Objectives];
            private _zones = missionNamespace getVariable ["ITW_OBJ_MOVE_ZONES",[]];
            if (_zones isNotEqualTo []) then {ITW_MAP_SavedZones = _zones};
        };
    };
    [_objMoved,_viewEditZones]
};

ITW_ObjMovingMP = {
    params ["_isChooser",["_objBackup",[]],["_viewEditZonesForce",false]];
    if (!hasInterface) exitWith {};
    
    private _objectives = +_objBackup;
    private _zones = [];
    private _debug = false;
    private _debugObj = {{diag_log [_x#ITW_OBJ_NAME,_x#ITW_OBJ_POS]} forEach _objectives};
    private _hadMap = true;
    if (player getSlotItemName 608 isEqualTo "") then {
        _hadMap = false;
        player linkItem "ItemMap";
    };
    if (_isChooser) then {
        // ask if the player wants to edit the mission
        private _viewEditZones = _viewEditZonesForce;
        if (!_viewEditZones) then {_viewEditZones = [localize "STR_ITW_OBJ_ViewEditMsg", localize "STR_ITW_OBJ_ViewEditHeader", localize "STR_ITW_COMMON_Yes", localize "STR_ITW_COMMON_No"] call BIS_fnc_guiMessage};
        if !(_viewEditZones) exitWith {
            missionNamespace setVariable ["ITW_OBJ_MOVE_EDITING",false,2];
            missionNamespace setVariable ["ITW_OBJ_MOVE_DONE",true,true];
        };
        missionNamespace setVariable ["ITW_OBJ_MOVE_EDITING",true,2];
        missionNamespace setVariable ["ITW_OBJ_MOVE_DONE",false,true];
    
        ITW_MAP_Reset = false; // ctrl-c to quit without saving changes
        ITW_MAP_Help = true; // H to show help
        ITW_MAP_ShowKeepOut = false; // S to toggle the yellow larger circles
        ITW_MAP_Ins = []; // insert key to add an objective
        ITW_MAP_Del = []; // delete key to remove an objective
        ITW_MAP_MouseDownPos = [];
        ITW_MAP_MouseUpPos = [];
        ITW_MAP_Enter = false;
        ITW_MAP_Circle = nil;
        ITW_MAP_Circle2 = nil;
        ITW_MAP_MarkerInUse = nil;
        ITW_MAP_MarkerUpdateTime = 0;
        ITW_MAP_Load = false;
        private _mapDisplay = findDisplay 12;
        private _keyDownEH = _mapDisplay displayAddEventHandler ["KeyDown", 
            {
                params ["_display", "_key"];
                _return = false;
                // DIK_NUMPADENTER keydown is closing the map
                if (_key == DIK_RETURN || _key == DIK_NUMPADENTER) then {
                    ITW_MAP_Enter = true;
                    _return = true;
                };
                _return
            }];
        private _keyUpEH = _mapDisplay displayAddEventHandler ["KeyUp", 
            {              
                params ["_display", "_key", "_shift", "_ctrl", "_alt"];
                if (ITW_MAP_Load) exitWith {false}; // let listSelector handle keys while it's open
                private _return = false;
                private _mapDisplay = findDisplay 12;
                if ((_key == DIK_INSERT || _key == DIK_I) and !_alt and !_shift) then {
                    ITW_MAP_Ins = _mapDisplay displayCtrl 51 ctrlMapScreenToWorld getMousePosition;
                    _return = true;
                };
                if ((_key == DIK_DELETE || _key == DIK_D) and !_alt and !_shift) then {
                    ITW_MAP_Del = _mapDisplay displayCtrl 51 ctrlMapScreenToWorld getMousePosition;
                    _return = true;
                };
                if (_key == DIK_H and !_alt and !_shift) then {
                    ITW_MAP_Help = true;
                    _return = true;
                };
                if (_key == DIK_T and !_alt and !_shift) then {
                    ITW_MAP_ShowKeepOut = !ITW_MAP_ShowKeepOut;
                    _return = true;
                };
                if (_key == DIK_C and _ctrl and !_alt and !_shift) then {
                    ITW_MAP_Reset = true;
                    _return = true;
                };
                if (_key == DIK_L and _ctrl and !_alt and !_shift) then {
                    ITW_MAP_Load = true;
                    _return = true;
                };
                if (_key == DIK_RETURN || _key == DIK_NUMPADENTER) then {
                    ITW_MAP_Enter = true;
                    _return = true;
                };
                _return
            }];
        private _mouseDownEH = _mapDisplay displayCtrl 51 ctrlAddEventHandler ["MouseButtonDown", 
            {
                params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
                // 0 is left button
                if (!_alt and !_shift and !_ctrl and _button == 0 and isNil "ITW_MAP_MarkerInUse") then {
                    ITW_MAP_MouseDownPos = _control ctrlMapScreenToWorld [_xPos, _yPos];
                };
                false
            }];
        private _mouseUpEH = _mapDisplay displayCtrl 51 ctrlAddEventHandler ["MouseButtonUp", 
            {
                params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
                // 0 is left button
                if (!_alt and !_shift and !_ctrl and _button == 0 and !isNil "ITW_MAP_MarkerInUse") then {
                    ITW_MAP_MouseUpPos = _control ctrlMapScreenToWorld [_xPos, _yPos];
                };
                false
            }];
        private _circleMovingEH = _mapDisplay displayCtrl 51 ctrlAddEventHandler ["MouseMoving",
            {
                params ["_control", "_xPos", "_yPos", "_mouseOver"];
                private _localUpdate = time < ITW_MAP_MarkerUpdateTime;
                if (!isNil "ITW_MAP_Circle") then {
                    if (_localUpdate) then {
                        ITW_MAP_Circle  setMarkerPosLocal (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                    } else {
                        ITW_MAP_MarkerUpdateTime = time + 0.5;
                        ITW_MAP_Circle  setMarkerPos (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                    };
                };
                if (!isNil "ITW_MAP_Circle2") then {
                    if (_localUpdate) then {
                        ITW_MAP_Circle2 setMarkerPosLocal (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                    } else {
                        ITW_MAP_MarkerUpdateTime = time + 0.5;
                        ITW_MAP_Circle2 setMarkerPos (_control ctrlMapScreenToWorld [_xPos,_yPos]);
                    };
                };
            }];
    
        private _moveMarkers = []; // array params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"]
        private _createMarker_Fn = {
            params ["_pos","_owner","_obj"];
            private _name = format ["objMove_%1",count _moveMarkers];
            private _color = switch (_owner) do {
                case ITW_OWNER_FRIENDLY: {"ColorBlue"};
                case ITW_OWNER_ENEMY:    {"ColorRed" };
                default                  {"ColorBlack"};
            };
            private _mrkr = createMarkerLocal [_name,_pos];
            _mrkr setMarkerSizeLocal [ITW_ParamObjectiveSize,ITW_ParamObjectiveSize];
            _mrkr setMarkerShapeLocal "ELLIPSE";
            _mrkr setMarkerBrushLocal "Solid";
            _mrkr setMarkerColorLocal _color;
            _mrkr setMarkerAlpha 0.7;
            private _mrkr2 = createMarkerLocal [_name + "-2",_pos];
            _mrkr2 setMarkerSizeLocal [ITW_ZoneKeepOut,ITW_ZoneKeepOut];
            _mrkr2 setMarkerShapeLocal "ELLIPSE";
            _mrkr2 setMarkerBrushLocal "Border";
            _mrkr2 setMarkerColorLocal "ColorYellow";
            _mrkr2 setMarkerAlpha 0.5;
            _moveMarkers pushBack [_pos,_owner,_mrkr,_mrkr2,_obj];
        };
        
        private _setupMarkers_Fn = {
            private _objectives = _this;
            {
                _x params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
                deleteMarker _mrkr;
                deleteMarker _keepOutMrkr;
            } forEach _moveMarkers;
            _moveMarkers = [];
            private _cnt = count _objectives - 1;
            {
                private _obj = _x;
                private _color = "ColorGrey";
                private _owner = ITW_OWNER_CONTESTED;
                if (_forEachIndex == 0   ) then {_owner = ITW_OWNER_FRIENDLY};
                if (_forEachIndex == _cnt) then {_owner = ITW_OWNER_ENEMY};
                private _pos = _obj#ITW_OBJ_POS;
                [_pos,_owner,_obj] call _createMarker_Fn;
            } forEach _objectives;
        };
        _objectives call _setupMarkers_Fn;
        
        showMap true; 
        openMap [true,false];
        waitUntil {visibleMap};
        mapAnimAdd [0, 1, [worldSize/2,worldSize/2]];
        mapAnimCommit;
        "itw" cutText ["","PLAIN"];
        private _keepOutShown = true;
        private _objSize = ITW_ParamObjectiveSize max 200;
        private _objectivesChanged = false;
        private _hintTime = 0;
        if (_debug) then {diag_log format ["ITW Objective Move: START visibleMap: %1",visibleMap]; call _debugObj};
        while {visibleMap} do {
            if (time > _hintTime) then {hintSilent localize "STR_ITW_OBJ_MoveHint"; _hintTime = time + 25};
            if (ITW_MAP_Help) then {
                ITW_MAP_Help = false;
                if (_debug) then {diag_log "ITW Objective Move: Help started"};
                hintSilent "";
                private _marker = createMarkerLocal ["baseSelectBlur", [worldSize/2,worldSize/2]];    
                _marker setMarkerShapeLocal "RECTANGLE";   
                _marker setMarkerBrushLocal "SolidFull";   
                _marker setMarkerColorLocal "ColorBlack";   
                _marker setMarkerSizeLocal [worldSize/2,worldSize/2];     
                _marker setMarkerAlphaLocal 0.7;
                ITW_MAP_Enter = false;
                ["itw","<t size='0.6' align='left'><br/>" + localize "STR_ITW_OBJ_MoveInstructions" + "</t>",0.1,0] spawn ITW_FncCutTextXY;
                waitUntil {visibleMap};
                waitUntil {!visibleMap || {ITW_MAP_MouseDownPos isNotEqualTo [] || {ITW_MAP_Help || {ITW_MAP_Enter}}}};
                if (_debug) then {diag_log format ["ITW Objective Move: Help Done         visibleMap: %1, mapClick: %2, H key: %3",visibleMap,ITW_MAP_MouseDownPos isNotEqualTo [],ITW_MAP_Help]}; 
                deleteMarkerLocal _marker;
                "itw" cutText ["","PLAIN"];
                // reset all inputs in case player pressed them while viewing instructions
                ITW_MAP_Enter = false;
                ITW_MAP_Help = false;
                ITW_MAP_MouseDownPos = [];
                ITW_MAP_MouseUpPos = [];
                ITW_MAP_Ins = [];
                ITW_MAP_Del = [];
                ITW_MPA_Reset = false;
                ITW_MAP_ShowKeepOut = _keepOutShown;
                ITW_MAP_Load = false;
                _hintTime = 0;
            };
            if (ITW_MAP_ShowKeepOut != _keepOutShown) then {
                if (_debug) then {diag_log format ["ITW Objective Move: Toggle keep out markers: %1",_keepOutShown]};
                {
                    _x params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
                    _keepOutMrkr setMarkerAlpha (if (ITW_MAP_ShowKeepOut) then {0.5} else {0});
                } forEach _moveMarkers;
                _keepOutShown = ITW_MAP_ShowKeepOut;
            };
            if (ITW_MAP_MouseDownPos isNotEqualTo []) then {
                private _markerInfo = [ITW_MAP_MouseDownPos,_moveMarkers,0] call ITW_FncClosest;
                _markerInfo params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
                if (_debug) then {diag_log format ["ITW Objective Move: Mouse down  pos: %1  markerDist: %2  obj: %3",ITW_MAP_MouseDownPos,ITW_MAP_MouseDownPos distance _mrkPos,_obj#ITW_OBJ_NAME]};
                if (ITW_MAP_MouseDownPos distance _mrkPos < _objSize) then {
                    ITW_MAP_MarkerInUse = _markerInfo;
                    ITW_MAP_Circle = _mrkr;
                    ITW_MAP_Circle2 = _keepOutMrkr;
                    if (_debug) then {call _debugObj};
                };
                ITW_MAP_MouseDownPos = [];
            };
            if (ITW_MAP_MouseUpPos isNotEqualTo []) then {
                if (_debug) then {diag_log format ["ITW Objective Move: Mouse up  pos: %1  markerInUse: %2",ITW_MAP_MouseUpPos, !isNil "ITW_MAP_MarkerInUse"]};
                if (!isNil "ITW_MAP_MarkerInUse") then {
                    ITW_MAP_MarkerInUse params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
                    private _pos = ITW_MAP_MouseUpPos;
                    ITW_MAP_Circle setMarkerPos  _pos;
                    ITW_MAP_Circle2 setMarkerPos _pos;
                    ITW_MAP_MarkerInUse     set [0,_pos];
                    _obj set [ITW_OBJ_POS,_pos];
                    _objectivesChanged = true;
                    if (_debug) then {call _debugObj};
                };
                ITW_MAP_MouseUpPos = [];
                ITW_MAP_MarkerInUse = nil;
                ITW_MAP_Circle = nil;
                ITW_MAP_Circle2 = nil;
            };
            if (ITW_MAP_Ins isNotEqualTo []) then {
                if (_debug) then {diag_log format ["ITW Objective Move: Insert  pos: %1  markerInUse: %2",ITW_MAP_Ins, !isNil "ITW_MAP_MarkerInUse"]};
                if (isNil "ITW_MAP_MarkerInUse") then {
                    private _pos = ITW_MAP_Ins;
                    if (_pos isNotEqualTo []) then {
                        private _obj = INIT_OBJECTIVE;
                        _obj set [ITW_OBJ_POS,_pos];
                        _obj set [ITW_OBJ_NAME, call ITW_ObjGetRandomName];
                        [_pos,ITW_OWNER_CONTESTED,_obj] call _createMarker_Fn;
                        _objectives insert [1,[_obj]];
                        _objectivesChanged = true;
                        if (_debug) then {call _debugObj};
                        if (_zones isNotEqualTo []) then {
                            {
                                if (_forEachIndex > 0) then {
                                    _zones set [_forEachIndex,_x apply {_x + 1}];
                                };
                            } forEach _zones;
                            _zones#1 pushBack 1;
                        };
                    };
                };
                ITW_MAP_Ins = [];
            };
            if (ITW_MAP_Del isNotEqualTo []) then {
                if (_debug) then {diag_log format ["ITW Objective Move: Delete  pos: %1  markerInUse: %2",ITW_MAP_Del, !isNil "ITW_MAP_MarkerInUse"]};
                if (isNil "ITW_MAP_MarkerInUse") then {
                    private _markerInfo = [ITW_MAP_Del,_moveMarkers,0] call ITW_FncClosest;
                    _markerInfo params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
                    if (ITW_MAP_Del distance _mrkPos < _objSize) then {
                        private _objIdx = _objectives find _obj;
                        if (_objIdx > 0 && {_objIdx < (count _objectives - 1)}) then {
                            _objectives deleteAt _objIdx;
                            deleteMarker _mrkr;
                            deleteMarker _keepOutMrkr;
                            _moveMarkers = _moveMarkers - _markerInfo;
                            if (_debug) then {call _debugObj};
                            
                            if (_zones isNotEqualTo []) then {
                                {
                                    private _zone = _x;
                                    private _idx = _zone findif {_objIdx == _x};
                                    if (_idx >= 0) exitWith {_zone deleteAt _idx};
                                } forEach _zones;
                                _zones = _zones - [[]];
                                {
                                    private _zone = _x;
                                    {
                                        if (_x > _objIdx) then {_zone set [_forEachIndex,_x - 1]};
                                    } forEach _zone;
                                } forEach _zones;
                            };
                        };
                    };
                };
                ITW_MAP_Del = [];
            };
            if (ITW_MAP_Load) then {
                if (_debug) then {diag_log "ITW Objective Move: Load"};
                if (isNil "SKL_ListSelector") then {SKL_ListSelector = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_ListSelector.sqf"};
                private _savedObjs = [] call ITW_LoadObjectives; // array of [_name,_objectives,_zones]
                if (_savedObjs isEqualTo []) then {
                    hint localize "STR_ITW_OBJ_NoSavedObjectives";
                } else {
                    while {true} do {
                        private _index = [_savedObjs apply {_x#0},localize "STR_ITW_OBJ_LoadTitle",localize "STR_ITW_OBJ_Load",localize "STR_SKL_COMMON_Cancel",localize "STR_ITW_OBJ_Delete",false,_mapDisplay] call SKL_ListSelector;
                        if (_index == -1) exitWith {};
                        if (_index >= 0) exitWith {
                            // load objectives
                            _objectives = _savedObjs#_index#1;
                            _zones = _savedObjs#_index#2;
                            _objectives call _setupMarkers_Fn;
                            _objectivesChanged = true;
                        };
                        // delete from list
                        _index = -(_index+2); // handle middle button translation
                        _savedObjs deleteAt _index;
                        _savedObjs call ITW_SaveObjectives;
                    };
                };
                ITW_MAP_Load = false;
            };
            if (ITW_MAP_Reset) then {
                if (_debug) then {diag_log "ITW Objective Move: Reset"};
                ITW_MAP_Reset = false;
                _zones = [];
                _objectives = +_objBackup;
                _objectivesChanged = false;
                _objectives call _setupMarkers_Fn;
                if (_debug) then {call _debugObj};
            };
        };
        if (_debug) then {diag_log format ["ITW Objective Move: DONE visibleMap %1",visibleMap]};
        hint "";
        "itw" cutText ["","BLACK OUT",0.001];
        _mapDisplay displayRemoveEventHandler ["KeyDown",_keyDownEH]; 
        _mapDisplay displayRemoveEventHandler ["KeyUp",_keyUpEH]; 
        _mapDisplay displayCtrl 51 ctrlRemoveEventHandler ["MouseButtonDown",_mouseDownEH];
        _mapDisplay displayCtrl 51 ctrlRemoveEventHandler ["MouseButtonUp"  ,_mouseUpEH];
        _mapDisplay displayCtrl 51 ctrlRemoveEventHandler ["MouseMoving"    ,_circleMovingEH]; 
        missionNamespace setVariable ["ITW_OBJ_MOVE_CHANGED",_objectivesChanged,2];
        missionNamespace setVariable ["ITW_OBJ_MOVE_OBJS",_objectives,2];
        missionNamespace setVariable ["ITW_OBJ_MOVE_ZONES",_zones,2];
        missionNamespace setVariable ["ITW_OBJ_MOVE_DONE",true,true];
        {
            _x params ["_mrkPos","_owner","_mrkr","_keepOutMrkr","_obj"];
            deleteMarker _mrkr;
            deleteMarker _keepOutMrkr;
        } forEach _moveMarkers;
        ITW_MAP_Reset = nil;
        ITW_MAP_Help = nil;
        ITW_MAP_ShowKeepOut = nil;
        ITW_MAP_Ins = nil;
        ITW_MAP_Del = nil;
        ITW_MAP_MouseDownPos = nil;
        ITW_MAP_MouseUpPos = nil;
        ITW_MAP_Enter = nil;
        ITW_MAP_Circle = nil;
        ITW_MAP_Circle2 = nil;
        ITW_MAP_MarkerInUse = nil;
        ITW_MAP_MarkerUpdateTime = nil;
        ITW_MAP_Load = nil;
    } else {
        waitUntil {typeName (missionNamespace getVariable ["ITW_OBJ_MOVE_DONE","-"]) == "BOOL"};
        if !(missionNamespace getVariable ["ITW_OBJ_MOVE_DONE",false]) then {
            showMap true; 
            openMap [true,true];
            waitUntil {visibleMap};
            "itw" cutText ["","PLAIN"];
            hint localize "STR_ITW_OBJ_OtherPlayerChoosing";
            waitUntil {sleep 0.5; missionNamespace getVariable ["ITW_OBJ_MOVE_DONE",false]};
            "itw" cutText ["","BLACK OUT",0.001];
            openMap [false,false];
        };
    };
    if (!_hadMap) then {player unlinkItem "ItemMap"};
};

ITW_ObjZoneSelection = {
    missionNamespace setVariable ["ITW_OBJ_ZONE_DONE",nil];
    // choose who will pick locations
    if (isDedicated) then {        
        // if using a dedicated server, use a the first player to choose 
        waitUntil {count (call BIS_fnc_listPlayers) > 0};
        private _playerClient = owner ((call BIS_fnc_listPlayers)#0);
        [false] remoteExec ["ITW_ObjZoneSelectionMP",-(_playerClient),true];
        [true,ITW_Zones,ITW_Objectives] remoteExec ["ITW_ObjZoneSelectionMP",_playerClient];
    } else {
        // hosted server, so just let the host choose 
        [false] remoteExec ["ITW_ObjZoneSelectionMP",-2,true];
        sleep 1; // need a sleep since some cutText remoteExec calls may still be in the pipe
        [true,ITW_Zones,ITW_Objectives] call ITW_ObjZoneSelectionMP;
    };
    waitUntil {sleep 0.5; missionNamespace getVariable ["ITW_OBJ_ZONE_DONE",false]};
    private _zonesMoved = missionNamespace getVariable ["ITW_OBJ_ZONE_CHANGED",false];
    if (_zonesMoved) then {
        ITW_Zones = missionNamespace getVariable ["ITW_OBJ_ZONE_ARRAY",ITW_Zones];
        {
            private _obj = _x;
            private _objIdx = _obj#7;
            private _zone = ITW_Zones findIf {_objIdx in _x};
            _obj set [ITW_OBJ_ZONEID,_zone];
        } forEach ITW_Objectives;
    };
    _zonesMoved
};

ITW_ObjZoneSelectionMP = {
    params ["_isChooser",["_zonesBackup",[]],["_objectives",[]]];
    if (!hasInterface) exitWith {};
    // This function returns a zone map.  It does not change any objectives.
    // so after calling this and getting the zones, the objectives need to be updated
    private _zones = +_zonesBackup;
    private _debug = false;
    private _debugZone = {{diag_log [_forEachIndex,_x apply {str _x + ":" + (_objectives#_x#ITW_OBJ_NAME)}]} forEach _zones};
    private _hadMap = true;
    private _finalObjIndex = count _objectives - 1;
    private _finalZone = count _zones - 1;
    if (player getSlotItemName 608 isEqualTo "") then {
        _hadMap = false;
        player linkItem "ItemMap";
    };
    if (_isChooser) then {
        ITW_MAP_Reset = false; // ctrl-c to reset
        ITW_MAP_Help = true; // H to show help
        ITW_MAP_MouseDownPos = [];
        ITW_MAP_MouseUpPos = [];
        ITW_MAP_Enter = false;
        ITW_MAP_LineType = 0; // 0: connecting  1: rearranging
        ITW_MAP_LineOrigin = [];
        ITW_MAP_LineInUse = nil;
        ITW_MAP_LineUpdateTime = 0;
        ITW_MAP_ObjLines = [];
        ITW_MAP_Save = false;
        
        private _mapDisplay = findDisplay 12;
        private _mapCtrl = findDisplay 12 displayCtrl 51;
        private _keyDownEH = _mapDisplay displayAddEventHandler ["KeyDown", 
            {
                params ["_display", "_key"];
                _return = false;
                // DIK_NUMPADENTER keydown is closing the map
                if (_key == DIK_RETURN || _key == DIK_NUMPADENTER) then {
                    ITW_MAP_Enter = true;
                    _return = true;
                };
                _return
            }];
        private _keyUpEH = _mapDisplay displayAddEventHandler ["KeyUp", 
            {              
                params ["_display", "_key", "_shift", "_ctrl", "_alt"];
                if (ITW_MAP_Save) exitWith {false}; // let listSelector handle keys while it's open
                private _return = false;
                if (_key == DIK_H && !_alt && !_shift) then {
                    ITW_MAP_Help = true;
                    _return = true;
                };
                if (_key == DIK_C && _ctrl && !_alt && !_shift) then {
                    ITW_MAP_Reset = true;
                    _return = true;
                };
                if (_key == DIK_S && _ctrl && !_alt && !_shift) then {
                    ITW_MAP_Save = true;
                    _return = true;
                };
                if (_key == DIK_RETURN || _key == DIK_NUMPADENTER) then {
                    ITW_MAP_Enter = true;
                    _return = true;
                };
                _return
            }];
        private _mouseDownEH = _mapCtrl ctrlAddEventHandler ["MouseButtonDown", 
            {
                params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
                // 0 is left button
                private _return = false;
                if (!_shift && !_ctrl && _button == 0 && {isNil "ITW_MAP_LineInUse"}) then {
                    ITW_MAP_MouseDownPos = _control ctrlMapScreenToWorld [_xPos, _yPos];
                };
                _return
            }];
        private _mouseUpEH = _mapCtrl ctrlAddEventHandler ["MouseButtonUp", 
            {
                params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
                // 0 is left button
                if (_button == 0 && !isNil "ITW_MAP_LineInUse") then {
                    ITW_MAP_MouseUpPos = _control ctrlMapScreenToWorld [_xPos, _yPos];
                };
                false
            }];
        private _drawEH = _mapCtrl ctrlAddEventHandler ["Draw", {
            params ["_control"];
            if (!isNil "ITW_MAP_LineInUse") then {
                // Update the mouse position dynamically on the map
                private _pos = _control ctrlMapScreenToWorld getMousePosition;
                _control drawLine [ITW_MAP_LineOrigin, _pos, [0, 1, 1-ITW_MAP_LineType, 1], 6];
            };
            {
                private _origin = _x#0;
                {
                    _control drawLine [_origin, _x, [0, 1, 1, 1], 5];
                } forEach (_x#1);
            } forEach ITW_MAP_ObjLines;
        }];
    
        private _objMarker = [];  // array params ["_mrkPos","_mrkr","_obj"] 
        private _zoneMarkers = []; // array params ["_mrkPos","_mrkr","zoneIdx"]
        private _createObjMarker_Fn = {
            params ["_pos","_owner","_obj","_debug"];
            private _name = format ["objMove_%1",count _zoneMarkers];
            private _color = switch (_owner) do {
                case ITW_OWNER_FRIENDLY: {"ColorBlue"};
                case ITW_OWNER_ENEMY:    {"ColorRed" };
                default                  {"ColorBlack"};
            };
            private _mrkr = createMarkerLocal [_name,_pos];
            _mrkr setMarkerSizeLocal [ITW_ParamObjectiveSize,ITW_ParamObjectiveSize];
            _mrkr setMarkerShapeLocal "ELLIPSE";
            _mrkr setMarkerBrushLocal "Solid";
            _mrkr setMarkerColorLocal _color;
            _mrkr setMarkerAlpha 0.7;
            if (_debug) then {
                private _mrkr2 = createMarkerLocal [_name+"_debug",_pos];
                _mrkr2 setMarkerTypeLocal "EmptyIcon";
                _mrkr2 setMarkerColorLocal _color;
                _mrkr2 setMarkerText (str (_obj#ITW_OBJ_INDEX) + ":" + (_obj#ITW_OBJ_NAME));
                _mrkr2 setMarkerAlpha 1;
            };
            if (_forEachIndex == 0) then {_pos = [-9999,-9999]};
            _zoneMarkers pushBack [_pos,_mrkr,_obj];
        };
        private _createZoneMarker_Fn = {
            params ["_name","_pos","_zoneId"];
            private _mrkr = createMarkerLocal [_name,_pos];
            _mrkr setMarkerSizeLocal [1,1];
            _mrkr setMarkerTypeLocal "mil_destroy";
            _mrkr setMarkerColorLocal "ColorGreen";
            _mrkr setMarkerTextLocal (localize "STR_ITW_OBJ_Zone" + str _zoneId);
            _mrkr setMarkerAlpha (if (_zoneId == 0) then {0} else {1});
        };
        private _updateZonesMarkers_Fn = {
            params ["_objectives","_zones"];
            ITW_MAP_ObjLines = [];
            private _objCount1 = count _objectives - 1;
            {
                if (_forEachIndex == 0) then {
                    continue
                };
                private _indexes = _x;
                private _zoneId = _forEachIndex;
                private _name = format ["zoneMove_%1",_zoneId];
                
                // calculate central point to place zone number
                private _objPositions = [];
                private _count = count _indexes;
                private _sumX = 0;
                private _sumY = 0;
                {
                    private _pt = _objectives#_x#ITW_OBJ_POS;
                    _sumX = _sumX + (_pt#0);
                    _sumY = _sumY + (_pt#1);
                    _objPositions pushBack _pt;
                } forEach _indexes;
                private _pos = [_sumX / _count,_sumY / _count];
                
                if (_count < 2) then {
                    _pos = _pos getPos [ITW_ParamObjectiveSize+ITW_ParamObjectiveSize,90];
                };
                if (getMarkerColor _name == "") then {
                    [_name,_pos,_zoneId] call _createZoneMarker_Fn;
                    _zoneMarkers pushBack [_pos,_name,_zoneId];
                } else {
                    _name setMarkerPos _pos;
                    (_zoneMarkers#(_objCount1 + _forEachIndex)) set [0,_pos];
                };
                if (count _objPositions > 1) then {ITW_MAP_ObjLines pushBack [_pos,_objPositions]};
            } forEach _zones;
            publicVariable "ITW_MAP_ObjLines";
            
            // delete any extra markers if the zone count was reduced
            private _markerArraySize = _objCount1 + count _zones;
            while {count _zoneMarkers > _markerArraySize} do {
                private _info = _zoneMarkers deleteAt (count _zoneMarkers - 1);
                _info params ["_pos","_mrkr","_zoneId"];
                deleteMarker _mrkr;
            };
            _finalZone = count _zones - 1;
        };
        private _getZone_Fn = {
            params ["_objIdx","_zones"];
            private _zoneIdx = -1;
            {
                if (_objIdx in _x) exitWith {_zoneIdx = _forEachIndex};
            } forEach _zones;
            if (_zoneIdx < 0) then {
                diag_log format ["Error Pos: ITW_ObjZoneSelectionMP _getZone_Fn: objIndex (%1) not in any zone",_objIdx];
                {diag_log [_forEachIndex,_x]} forEach _zones;
                _zoneIdx = 0;
            };
            _zoneIdx
        };
        private _error_Fn = {
            playSound "addItemFailed";

            // 2. Grab the map control display to find where the mouse is pointing
            private _mapCtrl = (findDisplay 12) displayCtrl 51;

            if (!isNull _mapCtrl) then {
                private _marker = createMarkerLocal ["zoneMoveError", _mapCtrl ctrlMapScreenToWorld getMousePosition];
                _marker setMarkerTypeLocal "hd_warning";
                _marker setMarkerColorLocal "ColorRed";
                _marker setMarkerSizeLocal [2, 2]; 
                uiSleep 0.5; 
                deleteMarkerLocal _marker; 
            };
        };
        
        {
            private _obj = _x;
            private _color = "ColorGrey";
            private _owner = ITW_OWNER_CONTESTED;
            if (_forEachIndex == 0             ) then {_owner = ITW_OWNER_FRIENDLY};
            if (_forEachIndex == _finalObjIndex) then {_owner = ITW_OWNER_ENEMY};
            private _pos = _obj#ITW_OBJ_POS;
            [_pos,_owner,_obj,_debug] call _createObjMarker_Fn;
        } forEach _objectives;
        
        [_objectives,_zones] call _updateZonesMarkers_Fn;
        if (_debug) then {diag_log "Objectives:";{diag_log [_forEachIndex,_x]} forEach _objectives};
 
        showMap true; 
        openMap [true,false];
        waitUntil {visibleMap};
        mapAnimAdd [0, 1, [worldSize/2,worldSize/2]];
        mapAnimCommit;
        "itw" cutText ["","PLAIN"];
        private _keepOutShown = true;
        private _objSize = ITW_ParamObjectiveSize max 200;
        private _zonesChanged = false;
        private _hintTime = 0;
        if (_debug) then {diag_log format ["ITW Zone Move: START visibleMap: %1",visibleMap]; call _debugZone};
        while {visibleMap} do {
            if (time > _hintTime) then {hintSilent localize "STR_ITW_OBJ_MoveHint"; _hintTime = time + 25};
            if (ITW_MAP_Help) then {
                ITW_MAP_Help = false;
                if (_debug) then {diag_log "ITW Zone Move: Help started"};
                hintSilent "";
                private _marker = createMarkerLocal ["baseSelectBlur", [worldSize/2,worldSize/2]];    
                _marker setMarkerShapeLocal "RECTANGLE";   
                _marker setMarkerBrushLocal "SolidFull";   
                _marker setMarkerColorLocal "ColorBlack";   
                _marker setMarkerSizeLocal [worldSize/2,worldSize/2];     
                _marker setMarkerAlphaLocal 0.7;
                ITW_MAP_Enter = false;
                ["itw","<t size='0.6' align='left'><br/>" + localize "STR_ITW_OBJ_ZoneInstructions" + "</t>",0.1,0] spawn ITW_FncCutTextXY;
                waitUntil {!visibleMap || {ITW_MAP_MouseDownPos isNotEqualTo [] || {ITW_MAP_Help || {ITW_MAP_Enter}}}};
                if (_debug) then {diag_log format ["ITW Zone Move: Help Done         visibleMap: %1, mapClick: %2, H key: %3",visibleMap,ITW_MAP_MouseDownPos isNotEqualTo [],ITW_MAP_Help]}; 
                deleteMarkerLocal _marker;
                "itw" cutText ["","PLAIN"];
                // reset all inputs in case player pressed them while viewing instructions
                ITW_MAP_Enter = false;
                ITW_MAP_Help = false;
                ITW_MAP_MouseDownPos = [];
                ITW_MAP_MouseUpPos = [];
                ITW_MAP_Ins = false;
                ITW_MPA_Reset = false;
                ITW_MAP_Save = false;
                _hintTime = 0;
                
            };
            if (ITW_MAP_MouseDownPos isNotEqualTo []) then {
                private _markerInfo = [ITW_MAP_MouseDownPos,_zoneMarkers,0] call ITW_FncClosest;
                _markerInfo params ["_mrkPos","_mrkr","_objOrIdx"];
                private _zoneDrag = typeName _objOrIdx == "SCALAR";
                if (_zoneDrag) then {
                    private _zoneIdx = _objOrIdx;
                    if (_debug) then {diag_log format ["ITW Zone Move: Mouse down  pos: %1  markerDist: %2  zone: %3",ITW_MAP_MouseDownPos,ITW_MAP_MouseDownPos distance _mrkPos,_zoneIdx]};
                    if (_zoneIdx != _finalZone) then {
                        ITW_MAP_LineInUse = _markerInfo;
                        ITW_MAP_LineOrigin = _mrkPos;
                        ITW_MAP_LineType = 1;
                        if (_debug) then {call _debugZone};
                    } else {call _error_Fn};
                } else {
                    private _obj = _objOrIdx;
                    if (_debug) then {diag_log format ["ITW Zone Move: Mouse down  pos: %1  markerDist: %2  obj: %3:%4",ITW_MAP_MouseDownPos,ITW_MAP_MouseDownPos distance _mrkPos,_obj#ITW_OBJ_INDEX,_obj#ITW_OBJ_NAME]};
                    if (ITW_MAP_MouseDownPos distance2D _mrkPos < _objSize) then {
                        if ((_obj#ITW_OBJ_INDEX) > 0) then {
                            ITW_MAP_LineInUse = _markerInfo;
                            ITW_MAP_LineOrigin = _mrkPos;
                            ITW_MAP_LineType = 0;
                            if (_debug) then {call _debugZone};
                        } else {call _error_Fn};
                    };
                };
                ITW_MAP_MouseDownPos = [];
            };
            if (ITW_MAP_MouseUpPos isNotEqualTo []) then {
                ITW_MAP_LineInUse params ["_mrkPos","_mrkr","_objOrIdx"];
                private _zoneDrag = typeName _objOrIdx == "SCALAR";
                if (!isNil "ITW_MAP_LineInUse") then {
                    if (_zoneDrag) then {
                        // rearrange zones
                        private _zoneIdx = _objOrIdx;
                        if (_debug) then {diag_log format ["ITW Zone Move: Mouse up  pos: %1  shift: %2  lineInUse: zone %3",ITW_MAP_MouseUpPos, _zoneDrag, _zoneIdx]};
                        private _zoneToSwap = _zoneIdx;
                        private _markerInfo = [ITW_MAP_MouseUpPos,_zoneMarkers,0] call ITW_FncClosest;
                        _markerInfo params ["_mrkPos","_mrkr","_objOrIdx"];
                        private _zoneIdx = if (typeName _objOrIdx == "SCALAR") then {_objOrIdx} else {[_objOrIdx#ITW_OBJ_INDEX,_zones] call _getZone_Fn};
                        if (_zoneIdx != _finalZone) then {
                            if (_debug) then {diag_log format ["ITW Zone Move: Mouse up zone %1 <==> zone %2",_zoneToSwap,_zoneIdx]};
                            private _temp = _zones#_zoneToSwap;
                            _zones set [_zoneToSwap,_zones#_zoneIdx];
                            _zones set [_zoneIdx,_temp];
                            playSound "click";
                        } else {call _error_Fn};
                    } else {
                        private _obj = _objOrIdx;
                        if (_debug) then {diag_log format ["ITW Zone Move: Mouse up  pos: %1  shift: %2  lineInUse: %3:%4",ITW_MAP_MouseUpPos, _zoneDrag, _obj#ITW_OBJ_INDEX, _obj#ITW_OBJ_NAME]};
                        private _objIdxToMove = _obj#ITW_OBJ_INDEX;
                        private _oldZone = [_objIdxToMove,_zones] call _getZone_Fn;
                        private _markerInfo = [ITW_MAP_MouseUpPos,_zoneMarkers,0] call ITW_FncClosest;
                        _markerInfo params ["_mrkPos","_mrkr","_objOrIdx"];
                        if (_mrkPos distance2D ITW_MAP_MouseUpPos < _objSize) then {
                            // move obj to new zone
                            private _newZone = if (typeName _objOrIdx == "ARRAY") then {
                                [_objOrIdx#ITW_OBJ_INDEX,_zones] call _getZone_Fn;
                            } else {
                                _objOrIdx
                            };
                            if (_debug) then {diag_log format ["ITW Zone Move: Mouse up obj %1:%2 zone %3 ==> zone %4",_obj#ITW_OBJ_INDEX, _obj#ITW_OBJ_NAME,_oldZone,_newZone]};
                            _zones set [_oldZone,(_zones#_oldZone) - [_objIdxToMove]];
                            (_zones#_newZone) pushBack _objIdxToMove;
                            if (count (_zones#_oldZone) == 0) then {_zones deleteAt _oldZone};  
                            if !(_finalObjIndex in (_zones#-1)) then { // keep final obj in final zone
                                _newZone = count _zones - 1;
                                _oldZone = [_finalObjIndex,_zones] call _getZone_Fn;
                                if (_debug) then {diag_log format ["ITW Zone Move: Mouse up: attempt to move final obj, zone %1 ==> zone %2",_oldZone,_newZone]};
                                if (_newZone != _oldZone) then {
                                    private _temp = _zones#_newZone;
                                    _zones set [_newZone,_zones#_oldZone];
                                    _zones set [_oldZone,_temp];
                                };
                            };
                            playSound "click";
                        } else {
                            // create new zone for objective
                            private _objIdx = _obj#ITW_OBJ_INDEX;
                            private _prevZone = [_objIdx,_zones] call _getZone_Fn;
                            if (count (_zones#_prevZone) > 1) then {
                                _zones set [_prevZone,_zones#_prevZone - [_objIdx]];
                                private _newZoneIdx = if (_prevZone == count _zones - 1) then {_prevZone} else {_prevZone+1};
                                if (_objIdx == _finalObjIndex) then {_newZoneIdx = count _zones}; // keep final obj in final zone
                                _zones insert [_newZoneIdx,[[_objIdx]]];
                                if (_debug) then {diag_log format ["ITW Zone Move: Mouse up  new zone %1 with obj %2:%3",_newZoneIdx, _objIdx, _obj#ITW_OBJ_NAME]};
                                if (_debug) then {call _debugZone};
                                playSound "click";
                            } else {call _error_Fn};
                        }
                    };
                    _zonesChanged = true;
                    [_objectives,_zones] call _updateZonesMarkers_Fn;
                    if (_debug) then {call _debugZone};
                } else {
                    if (_debug) then {diag_log format ["ITW Zone Move: Mouse up  pos: %1  shift: %2  lineInUse: nil",ITW_MAP_MouseUpPos, _zoneDrag]};
                };
                ITW_MAP_MouseUpPos = [];
                ITW_MAP_LineInUse = nil;
            };
            if (ITW_MAP_Save) then {
                if (_debug) then {diag_log "ITW Zone Move: Save"};
                if (isNil "SKL_ListSelector") then {SKL_ListSelector = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_ListSelector.sqf"};
                private _savedObjs  = [] call ITW_LoadObjectives; // array of [_name,_objectives,_zones]
                private _done = false;
                while {true} do {
                    private _result = [_savedObjs apply {_x#0},localize "STR_ITW_OBJ_SaveTitle",localize "STR_ITW_OBJ_Save",localize "STR_SKL_COMMON_Cancel",localize "STR_ITW_OBJ_Delete",true,_mapDisplay] call SKL_ListSelector;
                    if (_result isEqualTo "" || {_result isEqualTo -1}) exitWith {};
                    if (typeName _result == "STRING") exitWith {
                        // save objectives
                        private _replaceIdx = _savedObjs findIf {_x#0 == _result};
                        if (_replaceIdx >= 0) then {_savedObjs deleteAt _replaceIdx};
                        _savedObjs pushBack [_result,_objectives,_zones];
                        _savedObjs sort true;
                        _savedObjs call ITW_SaveObjectives;
                        _zonesChanged
                    };
                    // delete from list
                    _index = -(_result+2); // handle middle button translation
                    _savedObjs deleteAt _index;
                    _savedObjs call ITW_SaveObjectives;
                };
                ITW_MAP_Save = false;
            };
            if (ITW_MAP_Reset) then {
                if (_debug) then {diag_log "ITW Zone Move: Reset"};
                ITW_MAP_Reset = false;
                _zones = +_zonesBackup;
                _zonesChanged = false;
                [_objectives,_zones] call _updateZonesMarkers_Fn;
                if (_debug) then {call _debugZone};
                playSound "click";
            };
        };
        if (_debug) then {diag_log format ["ITW Zone Move: DONE visibleMap %1",visibleMap]};
        hint "";
        "itw" cutText ["","BLACK OUT",0.001];
        _mapDisplay displayRemoveEventHandler ["KeyDown",_keyDownEH]; 
        _mapDisplay displayRemoveEventHandler ["KeyUp",_keyUpEH]; 
        _mapCtrl ctrlRemoveEventHandler ["MouseButtonDown",_mouseDownEH];
        _mapCtrl ctrlRemoveEventHandler ["MouseButtonUp"  ,_mouseUpEH];
        _mapCtrl ctrlRemoveEventHandler ["Draw"           ,_drawEH];
        missionNamespace setVariable ["ITW_OBJ_ZONE_CHANGED",_zonesChanged,2];
        missionNamespace setVariable ["ITW_OBJ_ZONE_ARRAY",_zones,2];
        missionNamespace setVariable ["ITW_OBJ_ZONE_DONE",true,true];
        {
            _x params ["_mrkPos","_mrkr","_objOrIdx"];
            deleteMarker _mrkr;
            if (_debug && {typeName _objOrIdx == "ARRAY"}) then {deleteMarker (_mrkr + "_debug")};
        } forEach (_zoneMarkers);
        ITW_MAP_Reset = nil;
        ITW_MAP_Help = nil;
        ITW_MAP_MouseDownPos = nil;
        ITW_MAP_MouseUpPos = nil;
        ITW_MAP_Enter = nil;
        ITW_MAP_LineType = nil;
        ITW_MAP_LineOrigin = nil;
        ITW_MAP_LineInUse = nil;
        ITW_MAP_LineUpdateTime = nil;
        ITW_MAP_ObjLines = nil;
        ITW_MAP_Save = nil;
    } else {
        showMap true; 
        openMap [true,true];
        waitUntil {visibleMap};
        "itw" cutText ["","PLAIN"];
        hint localize "STR_ITW_OBJ_OtherPlayerChoosing";
        
        ITW_MAP_ObjLines = [];
        private _mapCtrl = findDisplay 12 displayCtrl 51;
        private _drawEH = _mapCtrl ctrlAddEventHandler ["Draw", {
            params ["_control"];
            {
                private _origin = _x#0;
                {
                    _control drawLine [_origin, _x, [0, 1, 1, 1], 5];
                } forEach (_x#1);
            } forEach ITW_MAP_ObjLines;
        }];
        
        waitUntil {sleep 0.5; missionNamespace getVariable ["ITW_OBJ_ZONE_DONE",false]};
        
        "itw" cutText ["","BLACK OUT",0.001];
        _mapCtrl ctrlRemoveEventHandler ["Draw",_drawEH];
        ITW_MAP_ObjLines = nil;
        openMap [false,false];
    };
    if (!_hadMap) then {player unlinkItem "ItemMap"};
};

ITW_ObjGetZones = {
    params ["_createNewZones"];
    private _viewEditZones = false;
    if (_createNewZones) then {
        // sanity check
        if (count ITW_Objectives < 3) exitWith {
            ITW_Zones = [];
            [localize "STR_ITW_OBJ_TooFewObjs"] remoteExec ["ITW_ObjFailure",0];
        };
        
        private _objSort_FN = {
            params ["_objectives","_keepFirstLast"];
            private _objSorter = []; // array of [dist,index] 
            private _pt0 = _objectives#0#ITW_OBJ_POS;
            {
                private _center = _x#ITW_OBJ_POS;
                private _dist = _center distance2D _pt0;
                _objSorter pushBack [_dist,_forEachIndex];
            } forEach _objectives;

            if (_keepFirstLast) then {
                // players chose locations    
                _objSorter#0 set [0,0];
                _objSorter#-1 set [0,1e10];
            };   
            _objSorter sort true;
            
            // now rearrange the objective array to be in the desired order
            private _objs = [];
            {
                private _idx = _x#1;
                private _obj = _objectives#_idx;
                _objs pushBack _obj;
            } forEach _objSorter;
            _objs
        };
        
        private _zoneDir = random 360;
        private _w2 = worldSize/2;
        if (ITW_ParamObjectiveCount == 0) then {
            // players chose locations
            _viewEditZones = true;
            _zoneDir = [_w2,_w2] getDir (ITW_Objectives#0#ITW_OBJ_POS);
            // player choosen already has the player base 1st
        };
        
        // we do this twice (possibly), once to get locations and a second time if the player chose to rearrange them
        for "_loop" from 1 to 2 do {
            // find first (player base) point nearest the _zoneDir direction by sorting distance from line
            private _ptToLineDist = {
                params ["_pt","_line"];
                _line params ["_a","_b","_c"];
                // find distance between _pt and line: d = |Ax0 + By0 + C| / sqrt(a² + b²)
                abs(_a*(_pt#0) + _b*(_pt#1) + _c)/sqrt((_a*_a) + (_b*_b))
            };
            
            // we want to sort the objectives from player's side of the map to the enemies side of the map
            private ["_A","_B","_C"];
            // y = mx+b
            // m = slope
            // b = y - mx
            // mx - y + b = 0
            // Ax+By+C=0
            // so A = m, B = -1, C = b
            // m = tan(angle)
            private _pt = [_w2,_w2] getPos [worldSize,_zoneDir];
           
            private _m = tan(-_zoneDir);
            private _A = _m;
            private _B = -1;
            private _C = (_pt#1) - (_m * (_pt#0));
            private _line = [_A,_B,_C];
       
            private _objSorter = []; // array of [dist,index]    
            {
                private _center = _x#ITW_OBJ_POS;
                private _dist = [_center,_line] call _ptToLineDist;
                _objSorter pushBack [_dist,_forEachIndex];
            } forEach ITW_Objectives;
            
            if (ITW_ParamObjectiveCount == 0 || {_loop > 1}) then {
                // players chose locations    
                _objSorter#0 set [0,0];
                _objSorter#-1 set [0,1e10];
            };  
            
            _objSorter sort true;
        
            // now rearrange the objective array to be in the desired order
            private _objs = [];
            {
                private _idx = _x#1;
                _objs pushBack (ITW_Objectives#_idx);
            } forEach _objSorter;
            ITW_Objectives = _objs;
            private _objCnt = count _objs;
            
            //if (ITW_ParamObjectiveCount == 0) exitWith {}; // players setup locations, they don't need to rearrange them
            
            ITW_Objectives = [ITW_Objectives,_loop > 1] call _objSort_FN;
            
            if (_loop == 1) then {
                (_viewEditZones call ITW_ObjMoving)  params ["_objectivesMoved","_editingZones"];
                _viewEditZones = _editingZones;
                if (!_objectivesMoved || {!isNil "ITW_MAP_SavedZones"}) then {_loop = 2}; // exit the loop
            };
        };
        
        ["itw",[localize "STR_ITW_OBJ_SettingUpObjectives","BLACK OUT",0.001]] remoteExec ["cutText",0,false];
        
        // do the random variation of size now that player is done setting it up        
        if (ITW_ParamObjectiveVariation in [1,3]) then {
            {
                _x set [ITW_OBJ_SIZE,round (ITW_ParamObjectiveSize * (0.75 + random 0.5))];
            } forEach ITW_Objectives;
        };
                
        // Define zones
        private _numBases = count ITW_Objectives - 2;
        
        private _zoneId = 0;
        private _objsAvailable = ITW_Objectives apply {_x}; // array that is a copy of all the objectives
        _objsAvailable deleteAt 0; // player's base is not available
        _objsAvailable deleteAt (count _objsAvailable - 1); // final base is fixed as enemy camp
        while {count _objsAvailable > 0} do {
            _zoneId = _zoneId + 1;
            private _obj0 = _objsAvailable#0;
            private _pos0 = _obj0#ITW_OBJ_POS;
            _obj0 set [ITW_OBJ_ZONEID,_zoneId]; // save the zone (will update in ITW_Objectives
            _objsAvailable deleteAt 0;          // remove this objective from the local array _objAvailable
            private _objPerZone = ITW_ParamObjectivesPerZone;
            if (ITW_ParamObjectiveVariation in [2,3]) then {
                if (ITW_ParamObjectivesPerZone == 1) then {
                    _objPerZone = floor (ITW_ParamObjectivesPerZone + random 2);
                } else {
                    _objPerZone = floor (ITW_ParamObjectivesPerZone - 1 + random 3);
                };
            };      
            for "_i" from 2 to _objPerZone do { 
                if (count _objsAvailable == 0) exitWith {};
                private _idx = [_pos0,_objsAvailable,ITW_OBJ_POS] call ITW_FncClosestIndex;
                _objsAvailable#_idx set [ITW_OBJ_ZONEID,_zoneId]; // save the zone (will update in ITW_Objectives
                _objsAvailable deleteAt _idx;                     // remove this objective from the local array _objAvailable
            };
        };
        ITW_Objectives#-1 set [ITW_OBJ_ZONEID,_zoneId];
    }; 
    
    // set the marker names
    {
        _x set [ITW_OBJ_MARKER,"obj" + str _forEachIndex];
        _x set [ITW_OBJ_INDEX,_forEachIndex];
    } forEach ITW_Objectives;
    
    // create ITW_Zones array
    if (isNil "ITW_MAP_SavedZones") then {
        ITW_Zones = [];
        private _zoneCnt = 0;
        {
            if (_x#ITW_OBJ_HIDDEN) then {continue}; 
            private _cnt = _x#ITW_OBJ_ZONEID;
            if (_cnt > _zoneCnt) then {_zoneCnt = _cnt};
        } count ITW_Objectives;
        ITW_Zones resize [_zoneCnt+1,[]];
        {
            if (_x#ITW_OBJ_HIDDEN) then {continue};
            private _objZone = _x#ITW_OBJ_ZONEID;
            ITW_Zones#_objZone pushBack _forEachIndex;
        } forEach ITW_Objectives;
        
        if (_createNewZones) then {
            // make the final zone have only 1 or 2 objectives
            if (count (ITW_Zones#-1) > 2 || {count ITW_Zones < 3}) then {
                private _lastZone = ITW_Zones#-1;
                private _lastIndex = count _lastZone - 1;
                private _lastObjIdx = _lastZone#_lastIndex;
                _lastZone deleteAt _lastIndex;
                ITW_Zones pushBack [_lastObjIdx];
                ITW_Objectives#_lastObjIdx set [ITW_OBJ_ZONEID,count ITW_Zones - 1];
            };
            if (_viewEditZones) then {call ITW_ObjZoneSelection};
        };
    } else {
        ITW_Zones = ITW_MAP_SavedZones;
        ITW_MAP_SavedZones = nil;
        {
            private _zoneIdx = _forEachIndex;
            {
                ITW_Objectives#_x set [ITW_OBJ_ZONEID,_forEachIndex];
            } forEach _x;
        } forEach ITW_Zones;
        call ITW_ObjZoneSelection;
    };
    publicVariable "ITW_Zones";
    
    {      
        // Objective Markers
        if (_x#ITW_OBJ_HIDDEN) then {continue};
        private _objective = _x;
        private _aoPos = _objective#ITW_OBJ_POS;
        private _owner = _objective#ITW_OBJ_OWNER;
        private _captured = switch (_owner) do {
            case ITW_OWNER_CONTESTED: {_forEachIndex call ITW_ObjContestedOwnerIsFriendly};
            case ITW_OWNER_FRIENDLY:  {true};
            default                   {false};
        };
        if (_forEachIndex == 0) then {_captured = true};
        private _flag = [_aoPos,_captured] call ITW_ObjFlag;
        _objective set [ITW_OBJ_FLAG,_flag];
        private _taskId = format ["tCap%1",_forEachIndex];
        _objective set [ITW_OBJ_TASKID,_taskId];
    } forEach ITW_Objectives;
};

ITW_ObjContestedOwnerIsFriendly = {
    // flag is owned by friendlies (blue), but may be going up/down either red or blue
    // this call is safe on server or client
    params ["_objIdx"];
    private _idx = ITW_ObjContestedState findIf {_x#ITW_CONT_OBJ_IDX == _objIdx};
    if (_idx < 0) exitWith {false};
    ITW_ObjContestedState#_idx#ITW_CONT_PLAYER_OWNED
};

ITW_ObjFailure = {
    // call on all clients
    "itw" cuttext ["<t size='2'>" + _msg + "</t>","PLAIN",-1,true,true];
};

ITW_ObjGenStructures = {
    params ["_aoCenter","_aoSize","_minBuildings","_keepClearZones","_objIdx"];
    
    // collections that only need to happen once, first thread to get here starts it
    if (isNil "ITW_ADDED_BUILDING_BLACKLIST") then {
        ITW_ADDED_BUILDING_BLACKLIST = ["water"];
        // this collects thousands of buildings, so convert it to a weighted array to keep from keeping an 11k array around
        // on altis it found 11,354 buildings, but only took 20msec to convert it to a weighted array of 93 building types
        private _mapSize2 = worldSize/2;
        _buildingTypes = [];
        private _allBuildings = ([[_mapSize2,_mapSize2,0], worldSize] call ITW_ObjNearestBuildings) apply {typeOf _x} select {sizeOf _x < 40};
        private _bldTypes = _allBuildings arrayIntersect _allBuildings;
        private _hashmap = createHashMap;
        {_hashmap set [_x,0]} count _bldTypes;
        {
            private _bldg = _x;
            private _cnt = _hashmap get _bldg;
            _hashmap set [_bldg,_cnt + 1];
        } count _allBuildings;
        {
            _buildingTypes pushBack _x;
            _buildingTypes pushBack _y;
            false
        } forEach _hashmap;
        
        // don't put buildings near airports
        ITW_AIRPORT_BLACKLIST = ["water"]; 
        if (count (allAirports#0) > 0) then {
            private _taxiOff = (getArray (configfile >> "CfgWorlds" >> worldname >> "ilsTaxiOff")) call ITW_AirfieldFixIlsTaxi;
            private _ils = getArray (configfile >> "CfgWorlds" >> worldname >> "ilsPosition");
            if (count _taxiOff > 3 && count _ils > 1) then {
                private _taxi = [_taxiOff#2,_taxiOff#3,0];
                private _center = [(_taxi#0 + _ils#0)/2,(_taxi#1 + _ils#1)/2,0];
                private _dist = 200 + (_taxi distance2D _ils)/2; 
                private _ilsDir = getArray (configfile >> "CfgWorlds" >> worldname >> "ilsDirection");
                private _angle = (_ilsDir#0) atan2 (_ilsDir#2);
                if (_dist < 2000) then {ITW_AIRPORT_BLACKLIST pushBack [_center,200,_dist,_angle,true]};
            };
            private _sec = (configfile >> "CfgWorlds" >> worldname >> "SecondaryAirports");
            for "_i" from 0 to (count _sec - 1) do {
                private _cfg = _sec select _i;
                _taxiIn = (getArray (_cfg >> "ilsTaxiIn")) call ITW_AirfieldFixIlsTaxi;
                _ils = getArray (_cfg >> "ilsPosition");
                if (count _taxiIn > 1 && count _ils > 1) then { 
                    private _taxi = [_taxiIn#0,_taxiIn#1,0];
                    private _center = [(_taxi#0 + _ils#0)/2,(_taxi#1 + _ils#1)/2,0];
                    private _dist = 150 + (_taxi distance2D _ils)/2; 
                    private _ilsDir = getArray (_cfg >> "ilsDirection");
                    private _angle = (_ilsDir#0) atan2 (_ilsDir#2);
                    if (_dist < 2000) then {ITW_AIRPORT_BLACKLIST pushBack [_center,200,_dist,_angle,true]};
                };
            };
        };
        ITW_BUILDING_TYPES = _buildingTypes;
    };
    while {isNil "ITW_BUILDING_TYPES"} do {sleep 0.5}; // wait for other thread to finish defining buildings
    
    private _nearest = [_aoCenter, _aoSize] call ITW_ObjNearestBuildings;
    private _numBuildings = count _nearest; 
    if (_numBuildings < _minBuildings) then {  
        private _origNumBldgs = _numBuildings;
        private _placeDir = if (_numBuildings > 0) then {getDir (selectRandom _nearest)} else {random 360};
        private _loopCnt = 50;
        private _buildingSizeMax = 1e5;
        private _blacklist = ITW_AIRPORT_BLACKLIST + _keepClearZones;
        while {_numBuildings < _minBuildings && {_loopCnt > 0}} do {
            _loopCnt = _loopCnt - 1;
            private _type = switch (ITW_ParamExtraBuildings) do {
                case 2: {selectRandomWeighted (if (random 1 < 0.5) then {ITW_BUILDING_TYPES} else {
                            _fort = 0 call ITW_FortificationsGetWeightedStructures; 
                            if (_fort isEqualTo []) then {ITW_BUILDING_TYPES} else {_fort}
                        })};
                case 3: {selectRandomWeighted (call ITW_FortificationsGetWeightedStructures)};
                default {selectRandomWeighted ITW_BUILDING_TYPES};
            };  
            if (isNil "_type") exitWith {diag_log "ITW: ITW_ObjGenStructures: no structures to mimic found"};          
            private _pos = [];
            private _bSize = sizeOf _type;
            if (_bSize < _buildingSizeMax) then { // no point in searching for a larger building if we couldn't find spot for a smaller one
                private _posLoopCnt = 10;  
                while {count _pos == 0 && {_posLoopCnt > 0}} do {
                    // if count pos = 0, we try again, if it's 2 we found a pos, if it's 3 we're stopping the search
                    _posLoopCnt = _posLoopCnt - 1;
                    _pos = [_aoCenter, 0, _aoSize, _bSize, 0, 0.2, 0, _blacklist,[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
                    if (count _pos == 2 && {isOnRoad _pos}) exitWith {_blacklist pushBack [_pos,10]; _pos = []};
                    if (count _pos == 3 && {_posLoopCnt > 7}) then {_pos = []};
                };
                if (count _pos == 3) then {_buildingSizeMax = _bSize + 0.1};
            };
            if (count _pos == 2) then {
                _numBuildings = _numBuildings + 1;
                _pos pushBack 0;
                private _bldg = _type createVehicle _pos;
                _bldg setDir _placeDir + (floor random 4 * 90);
                _bldg setPosATL _pos;  
                _blacklist pushBack [_pos, sizeOf _type + 10];
                
                // add map marker
                private _bbox = 0 boundingBox _bldg;               
                private _mrkr = createMarkerLocal [format ["bldg_%1",count ITW_ADDED_BUILDING_BLACKLIST],_pos];
                _mrkr setMarkerShapeLocal "RECTANGLE";
                _mrkr setMarkerSizeLocal [(_bbox#1#0 - (_bbox#0#0))/2,(_bbox#1#1 - (_bbox#0#1))/2];
                _mrkr setMarkerColorLocal "ColorBlack";
                _mrkr setMarkerDirLocal getDir _bldg;
                _mrkr setMarkerAlpha 0.5;
                
                ITW_ADDED_BUILDING_BLACKLIST pushBack [_pos, sizeOf _type + 10];
            };            
        };      
        diag_log format ["ITW: Added %1 to the %2 existing buildings in %3",_numBuildings - _origNumBldgs,_origNumBldgs,ITW_Objectives#_objIdx#ITW_OBJ_NAME];
    };
    ITW_genStructuresComplete pushBack _objIdx;
};

ITW_ObjGetNearest = {
    params ["_pos",["_owner",ITW_OWNER_CONTESTED],["_capturedBy",ITW_OWNER_CONTESTED],["_allowEmpty",false]]; 
    // _owner: ITW_OWNER_UNDEFINDED:all objectives or ITW_OWNER_ENEMY or ITW_OWNER_FRIENDLY or ITW_OWNER_CONTESTED
    // _capturedBy: if _owner is contested, who has captured it ITW_OWNER_FRIENDLY, ITW_OWNER_ENEMY, or ITW_OWNER_CONTESTED for any owner
    // if _allowEmpty is true, then if the desired objective does not exist then [] is returned, otherwise a suitable replacement is returned
    if (ITW_Objectives isEqualTo []) exitWith {EMPTY_OBJECTIVE};
    if (ITW_ZoneIndex < 0) exitWith {ITW_Objectives#0};
    if (ITW_ZoneIndex >= count ITW_Zones) exitWith {ITW_Objectives#-1};
    private _objectives = switch (_owner) do {
        case ITW_OWNER_ENEMY;
        case ITW_OWNER_FRIENDLY: {ITW_Objectives select {_x#ITW_OBJ_OWNER == _owner}};
        case ITW_OWNER_CONTESTED: {
            switch (_capturedBy) do {
                case ITW_OWNER_CONTESTED: {ITW_Objectives select {_x#ITW_OBJ_OWNER == ITW_OWNER_CONTESTED}};
                default {ITW_Objectives select {_x#ITW_OBJ_OWNER == ITW_OWNER_CONTESTED && {_x#ITW_OBJ_INDEX call ITW_ObjContestedOwnerIsFriendly == (_capturedBy == ITW_OWNER_FRIENDLY)}}};
            };
        };
        default {ITW_Objectives};
    };
    if (_objectives isEqualTo []) exitWith {
        if (_allowEmpty) then {
            []
        } else {
            diag_log format ["ITW_ObjGetNearest, no objective (_this = %1, ITW_ZoneIndex = %2)",_this,ITW_ZoneIndex];
            if (_owner isEqualTo ITW_OWNER_FRIENDLY) then {ITW_Objectives#0} else {ITW_Objectives#-1};
        };
    };
    private _nearestObj = [_pos,_objectives,ITW_OBJ_POS] call ITW_FncClosest;
    //private _garagePos = [ITW_Garages, _nearestObj#ITW_OBJ_POS] call BIS_fnc_nearestPosition;
    _nearestObj
};

ITW_ObjIsNearestFriendly = {
    private _pos = _this;
    if (typeName _pos == "OBJECT" || {typeName _pos == "GROUP"}) then {_pos = getPosATL _pos};
    private _nearestObj = [_pos,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest;
    _nearestObj#ITW_OBJ_INDEX call ITW_ObjContestedOwnerIsFriendly
};

ITW_ObjGetBase = {
    params ["_posNearObj",["_isFriendly",true]];
    private _nearestObj = [_posNearObj,if (_isFriendly) then {ITW_OWNER_FRIENDLY} else {ITW_OWNER_ENEMY}] call ITW_ObjGetNearest;
    ITW_Bases#(_nearestObj#ITW_OBJ_INDEX)
};

ITW_ObjGetPlayerSpawnPtDir = {
    params [["_posNearObj",[]],["_isByLand",true]];
    // if _posNearObj == [] then it will choose a random attack objective
    if (_posNearObj isEqualTo []) then {
        private _objs = [true,true] call ITW_ObjGetContestedObjs;
        _posNearObj = if (_objs isEqualTo []) then {ITW_Objectives#0#ITW_OBJ_POS} else {(selectRandom _objs)#ITW_OBJ_POS};
    }; 
    private _base = [_posNearObj,true] call ITW_ObjGetBase;
    if (isNil "_base") then {_base = ITW_Bases#0};
    if (ITW_ParamSmallBases == 2 && {!(_base#0 isEqualTo (ITW_Bases#0#0))}) then {_base = ITW_Bases#0}; // if no base option, spawn at base 0
    private _spawnDir = (_base#ITW_BASE_DIR)-90;
    private _spawnPt = _base#ITW_BASE_P_SPAWN;
    [_base] call ITW_BaseEnsure;
    [_spawnPt,_spawnDir]
};

ITW_ObjGetContestedObjs = {
    // gets contested points, falls back to returning defend points if no attack points available and vise versa
    // if no arguments supplied then all contested points are returned
    params [["_isFriendly",nil],["_isAttack",true]];
    private _objectives = ITW_Objectives select {_x#ITW_OBJ_OWNER == ITW_OWNER_CONTESTED};
    if (isNil "_isFriendly") exitWith {_objectives};
    
    private _friendlyAttackPts = _objectives select {!(_x#ITW_OBJ_INDEX call ITW_ObjContestedOwnerIsFriendly)};
    private _friendlyDefendPts = _objectives - _friendlyAttackPts;
    if (_friendlyAttackPts isEqualTo []) then {_friendlyAttackPts = _friendlyDefendPts}
    else {if (_friendlyDefendPts isEqualTo []) then {_friendlyDefendPts = _friendlyAttackPts}};
    private _objs = if (_isFriendly) then {if (_isAttack) then {_friendlyAttackPts} else {_friendlyDefendPts}}
                                     else {if (_isAttack) then {_friendlyDefendPts} else {_friendlyAttackPts}};
    _objs
};

ITW_ObjSetMarker = {
    params ["_objective","_zoneIndex"];
    private _hidden = _objective#ITW_OBJ_HIDDEN;
    if (_hidden) exitWith {};
    
    private _aoPos = _objective#ITW_OBJ_POS;
    private _aoSize = _objective#ITW_OBJ_SIZE;
    private _marker = _objective#ITW_OBJ_MARKER;
    private _name = _objective#ITW_OBJ_NAME;
    private _zoneId = _objective#ITW_OBJ_ZONEID;
    private _objId = _objective#ITW_OBJ_INDEX;
    private _captured = _objId call ITW_ObjContestedOwnerIsFriendly;
    private _garagePadMrk = GARAGE_MARKER_NAME(_objective#ITW_OBJ_FLAG); // garage pad marker only shows in player owned contested objectives
    
    #define COLOR_ACTIVE_BLUE   "ColorBlue"
    #define COLOR_ACTIVE_RED    "ColorEast"
    #define COLOR_INACTIVE_BLUE "ColorWest"
    #define COLOR_INACTIVE_RED  "ColorRed"

//#def SHOW_COLORED_ZONES 1
#ifdef SHOW_COLORED_ZONES
    #define COLOR_ARRAY ["ColorRed"] // ["ColorRed","ColorCIV","ColorYellow","Color3_FD_F","ColorBlack"]
    private _clrArrayCnt = count COLOR_ARRAY;
#endif
    
    private "_color";
    private _brush = "Solid";
    private _alpha = 0.5;
    switch (true) do {
        case (_zoneId < _zoneIndex || _zoneId == 0): {
                                            _color = COLOR_INACTIVE_BLUE;
                                            _brush = "DiagGrid";
                                            _aoSize = ITW_ZoneKeepOut;
                                            _aoPos = ITW_Bases#(_objective#ITW_OBJ_INDEX)#ITW_BASE_POS;
                                            _garagePadMrk setMarkerAlpha 0;
                                            _alpha = if (ITW_ParamShowEnemyZonesOnMap == 1) then {0.5} else {0};
                                        };
        case (_zoneId > _zoneIndex): {
                                            _color = COLOR_INACTIVE_RED;
                                            _brush = "DiagGrid";
                                            _aoSize = ITW_ZoneKeepOut;
                                            _name = "";
                                            _alpha = if (ITW_ParamShowEnemyZonesOnMap == 1) then {1} else {0};
                                            //_aoPos = ITW_Bases#(_objective#ITW_OBJ_INDEX)#ITW_BASE_POS;
                                            _garagePadMrk setMarkerAlpha 0;
                                            #ifdef SHOW_COLORED_ZONES
                                                private _idx = _zoneId - 2;
                                                if (_idx < 0) then {_idx = 0};
                                                if (_idx >= _clrArrayCnt) then {_idx = _idx mod _clrArrayCnt};
                                                _color = COLOR_ARRAY#_idx; 
                                            #endif
                                        };
        case (_captured):               {_color = COLOR_ACTIVE_BLUE;_garagePadMrk setMarkerAlpha 1};
        default                         {_color = COLOR_ACTIVE_RED ;_garagePadMrk setMarkerAlpha 1};
    };
    
    private ["_mrkr","_mrkrT"];
    if (getMarkerColor _marker isEqualTo "") then {
        _mrkr = createMarkerLocal [_marker,_aoPos];
        _mrkrT = createMarkerLocal [_marker+"t",_aoPos];
    } else {
        _mrkr = _marker;
        _mrkrT = _marker+"t";
        _mrkr setMarkerPosLocal _aoPos;
        _mrkrT setMarkerPosLocal _aoPos;
    };
    _mrkr setMarkerBrushLocal _brush;
    _mrkr setMarkerColorLocal _color;
    _mrkr setMarkerShapeLocal "ELLIPSE";
    _mrkr setMarkerSizeLocal [_aoSize,_aoSize];
    _mrkr setMarkerAlpha _alpha;
    
    _mrkrT setMarkerTextLocal _name;
    _mrkrT setMarkerTypeLocal "EmptyIcon";
    _mrkrT setMarkerColorLocal _color;
    _mrkrT setMarkerAlpha 1;
};
        
ITW_ObjNearestBuildings = {
    // Get nearest buildings (not power lines and garbage heaps)
    params ["_pos","_radius"];
    
    private _nonBuildingTypes = [
        "Land_SCF_01_heap_bagasse_F","Land_vn_dyke_10","Land_vn_bridge_monkey_01","Land_vn_bridge_monkey_02",
        "Land_vn_bridge_monkey_03","Land_vn_bridge_monkey_04","Land_vn_bridge_monkey_05","Land_vn_fence_bamboo_01_03",
        "Land_vn_fence_bamboo_01_05","Land_vn_fence_bamboo_01_10","Land_vn_fence_bamboo_01_gate","Land_vn_fence_bamboo_02",
        "Land_vn_fence_bamboo_02_gate","Land_vn_crater_04_pond_black","Land_vn_crater_04_pond_blue",
        "Land_vn_crater_04_pond_brown","Land_vn_crater_04_pond_green","Land_vn_crater_04_pond_orange", 
        "Land_vn_crater_04_pond_yellow","Land_vn_crater_decal_01","Land_vn_crater_decal_02","Land_vn_crater_01_01",
        "Land_vn_crater_01_02","Land_vn_crater_02_01","Land_vn_crater_02_02","Land_vn_crater_03_01","Land_vn_crater_03_02",
        "Land_vn_crater_04_01","Land_vn_crater_04_02","Land_House_2W03_F","Land_vn_b_tower_01","Land_vn_guardtower_01_f",
        "Land_vn_hut_tower_01","Land_vn_o_prop_cong_cage_01","Land_vn_o_prop_cong_cage_03","Land_vn_o_bunker_02",
        "Land_vn_o_shelter_01","Land_vn_o_shelter_02","Land_vn_o_shelter_03","Land_vn_o_shelter_04","Land_vn_o_shelter_05",
        "Land_vn_o_shelter_06","Land_vn_o_platform_01","Land_vn_o_platform_02","Land_vn_o_platform_03","Land_vn_o_platform_04",
        "Land_vn_o_platform_05","Land_vn_o_platform_06","Land_vn_o_wallfoliage_01","Land_vn_trench_01_grass_f",
        "Land_vn_trenchframe_01_f","Land_vn_trench_01_forest_f","Land_vn_o_trench_firing_01","Land_vn_pierwooden_02_16m_f",
        "Land_vn_pierwooden_01_10m_norails_f", "Land_vn_pierwooden_01_16m_f", "Land_vn_pierwooden_01_dock_f", 
        "Land_vn_pierwooden_01_hut_f", "Land_vn_pierwooden_01_ladder_f", "Land_vn_pierwooden_01_platform_f", 
        "Land_vn_pierwooden_02_16m_f", "Land_vn_pierwooden_02_30deg_f", "Land_vn_pierwooden_02_barrel_f", 
        "Land_vn_pierwooden_02_hut_f", "Land_vn_pierwooden_02_ladder_f", "Land_vn_pierwooden_03_f", "land_gm_euro_railramp_01",
        "land_gm_euro_railramp_02","land_gm_euro_railramp_03","land_gm_standard_gauge_1_18m","land_gm_standard_gauge_2_18m",
        "land_gm_standard_gauge_5_18m","land_gm_standard_gauge_10_18m","land_gm_standard_gauge_25m","land_gm_standard_gauge_3m",
        "land_gm_standard_gauge_36m_bridge","Land_nav_pier_m_F","Land_Pier_addon","Land_Pier_Box_F","Land_Pier_F","Land_Pier_small_F",
        "Land_Pier_wall_F","Land_PierLadder_F","Land_Pillar_Pier_F","Land_Sea_Wall_F","Land_Canal_Dutch_01_15m_F","Land_Canal_Dutch_01_bridge_F",
        "Land_Canal_Dutch_01_corner_F","Land_Canal_Dutch_01_plate_F","Land_Canal_Dutch_01_stairs_F","Land_Breakwater_01_F",
        "Land_Breakwater_02_F","Land_QuayConcrete_01_5m_ladder_F","Land_QuayConcrete_01_20m_F","Land_QuayConcrete_01_20m_wall_F",
        "Land_QuayConcrete_01_innerCorner_F","Land_QuayConcrete_01_outterCorner_F","Land_QuayConcrete_01_pier_F",
        "Land_PierConcrete_01_4m_ladders_F","Land_PierConcrete_01_16m_F","Land_PierConcrete_01_30deg_F","Land_PierConcrete_01_end_F",
        "Land_PierConcrete_01_steps_F","Land_PierWooden_01_10m_noRails_F","Land_PierWooden_01_16m_F","Land_PierWooden_01_dock_F",
        "Land_PierWooden_01_hut_F","Land_PierWooden_01_ladder_F","Land_PierWooden_01_platform_F","Land_PierWooden_02_16m_F",
        "Land_PierWooden_02_30deg_F","Land_PierWooden_02_barrel_F","Land_PierWooden_02_hut_F","Land_PierWooden_02_ladder_F",
        "Land_PierWooden_03_F","Land_vn_nav_pier_m_2","Land_vn_breakwater_01_f","Land_vn_breakwater_02_f","Land_vn_quayconcrete_01_5m_ladder_f",
        "Land_vn_quayconcrete_01_20m_f","Land_vn_quayconcrete_01_20m_wall_f","Land_vn_quayconcrete_01_innercorner_f",
        "Land_vn_quayconcrete_01_outtercorner_f","Land_vn_quayconcrete_01_pier_f","Land_vn_pierconcrete_01_4m_ladders_f",
        "Land_vn_pierconcrete_01_16m_f","Land_vn_pierconcrete_01_30deg_f","Land_vn_pierconcrete_01_end_f","Land_vn_pierconcrete_01_steps_f",
        // SPE_NORWAY
        "Land_Calvary_03_F", "Land_ChickenCoop_01_F", "Land_cmp_Tower_F", "Land_ConcreteWell_02_F", "Land_Cross_01_small_F",
        "Land_FeedRack_01_F", "Land_FeedShack_01_F", "Land_FeedStorage_01_F", "Land_Grave_08_F", "Land_Grave_09_F", 
        "Land_Grave_10_F", "Land_Grave_11_F", "Land_Grave_dirt_F", "Land_Grave_forest_F", "Land_Grave_rocks_F", 
        "Land_GraveFence_01_F", "Land_GraveFence_02_F", "Land_GraveFence_03_F", "Land_GraveFence_04_F", "Land_Hutch_01_F", 
        "Land_LampIndustrial_02_F", "Land_SPE_bocage_long_mound", "Land_SPE_bocage_long_mound_lc", 
        "Land_SPE_bocage_short_mound_lc", "Land_SPE_bocage_tree_01_mound_lc", "Land_SPE_bocage_tree_02_mound_lc", 
        "Land_SPE_bocage_tree_03_mound_lc", "Land_SPE_French_Gate_01_Blue", "Land_SPE_French_Gate_01_Green", 
        "Land_SPE_French_Gate_01_White", "Land_SPE_French_Wall_01_Gate", "Land_SPE_French_Wall_01_Short_d", 
        "Land_SPE_French_Wall_01_Tall_d", "Land_SPE_French_Wall_02_Gate", "Land_SPE_French_Wall_02_Short_d", 
        "Land_SPE_French_Wall_02_Tall_d", "Land_SPE_French_Wall_03_Gate", "Land_SPE_French_Wall_03_Short_d", 
        "Land_SPE_French_Wall_03_Tall_d", "Land_SPE_French_Wall_Dark_01_Gate", "Land_SPE_French_Wall_Dark_01_Small_d", 
        "Land_SPE_French_Wall_Dark_01_Tall_d", "Land_SPE_French_Wall_Dark_02_Gate", "Land_SPE_French_Wall_Dark_02_Small_d",
        "Land_SPE_French_Wall_Dark_02_Tall_d", "Land_SPE_French_Wall_Dark_03_Gate", "Land_SPE_French_Wall_Dark_03_Small_d",
        "Land_SPE_French_Wall_Dark_03_Tall_d", "Land_SPE_French_Wall_Light_01_Gate", 
        "Land_SPE_French_Wall_Light_01_Small_d", "Land_SPE_French_Wall_Light_01_Tall_d", 
        "Land_SPE_French_Wall_Light_02_Gate", "Land_SPE_French_Wall_Light_02_Small_d", 
        "Land_SPE_French_Wall_Light_02_Tall_d", "Land_SPE_French_Wall_Light_03_Gate", 
        "Land_SPE_French_Wall_Light_03_Small_d", "Land_SPE_French_Wall_Light_03_Tall_d", "Land_SPE_Ger_Lamp", 
        "Land_SPE_Haystack", "Land_SPE_Haystack_low", "Land_SPE_Mound_End_01", "Land_SPE_Mound_End_01_LC", 
        "Land_SPE_Mound_End_02", "Land_SPE_Mound_End_02_LC", "Land_SPE_Mound_Long", "Land_SPE_Mound_Long_LC", 
        "Land_SPE_Mound_Low_01", "Land_SPE_Mound_Low_01_LC", "Land_SPE_Mound_Low_02", "Land_SPE_Mound_Low_02_LC", 
        "Land_SPE_Mound_Short_LC", "Land_SPE_Onion_Lamp", "Land_spe_pond1", "land_spe_pond2", 
        "land_spe_river_large_10m_left_10d_01", "land_spe_river_large_10m_left_20d_01", 
        "land_spe_river_large_10m_left_30d_01", "land_spe_river_large_10m_left_5d_01", 
        "land_spe_river_large_10m_right_10d_01", "land_spe_river_large_10m_right_20d_01", 
        "land_spe_river_large_10m_right_30d_01", "land_spe_river_large_10m_right_5d_01", 
        "land_spe_river_large_10m_straight_01", "land_spe_river_large_20m_left_10d_01", 
        "land_spe_river_large_20m_left_5d_01", "land_spe_river_large_20m_right_10d_01", 
        "land_spe_river_large_20m_right_10d_Junction_2m_01", "land_spe_river_large_20m_right_10d_Junction_2m_02", 
        "land_spe_river_large_20m_right_5d_01", "land_spe_river_large_20m_straight_01", 
        "land_spe_river_large_20m_straight_01_crossing_01", "land_spe_river_large_40m_straight_01", 
        "land_spe_river_medium_10m_left_10d_01", "land_spe_river_medium_10m_left_30d_01", 
        "land_spe_river_medium_10m_left_5d_01", "land_spe_river_medium_10m_right_10d_01", 
        "land_spe_river_medium_10m_right_30d_01", "land_spe_river_medium_10m_right_5d_01", 
        "land_spe_river_medium_10m_straight_01", "land_spe_river_medium_20m_left_10d_01", 
        "land_spe_river_medium_20m_left_5d_01", "land_spe_river_medium_20m_right_10d_01", 
        "land_spe_river_medium_20m_right_5d_01", "land_spe_river_medium_20m_straight_01", 
        "land_spe_river_medium_40m_straight_01", "land_spe_river_medium_junction_01", "land_spe_river_medium_junction_02", 
        "land_spe_river_medium_junction_03", "land_spe_river_medium_junction_04", "land_spe_river_medium_junction_05", 
        "land_spe_river_medium_junction_06", "land_spe_river_medium_junction_07", "land_spe_river_medium_junction_08", 
        "land_spe_river_small_10m_left_10d_01", "land_spe_river_small_10m_left_30d_01", 
        "land_spe_river_small_10m_left_5d_01", "land_spe_river_small_10m_right_10d_01", 
        "land_spe_river_small_10m_right_30d_01", "land_spe_river_small_10m_right_5d_01", 
        "land_spe_river_small_10m_straight_01", "land_spe_river_small_20m_left_10d_01", 
        "land_spe_river_small_20m_left_5d_01", "land_spe_river_small_20m_right_10d_01", 
        "land_spe_river_small_20m_right_5d_01", "land_spe_river_small_20m_straight_01", 
        "land_spe_river_small_40m_straight_01", "land_spe_river_small_junction_01", "land_spe_river_small_junction_02", 
        "land_spe_river_water_large_10m_left_10d_01", "land_spe_river_water_large_10m_left_20d_01", 
        "land_spe_river_water_large_10m_left_30d_01", "land_spe_river_water_large_10m_left_5d_01", 
        "land_spe_river_water_large_10m_right_10d_01", "land_spe_river_water_large_10m_right_20d_01", 
        "land_spe_river_water_large_10m_right_30d_01", "land_spe_river_water_large_10m_right_5d_01", 
        "land_spe_river_water_large_10m_straight_01", "land_spe_river_water_large_20m_left_10d_01", 
        "land_spe_river_water_large_20m_left_5d_01", "land_spe_river_water_large_20m_right_10d_01", 
        "land_spe_river_water_large_20m_right_10d_Junction_2m_01", 
        "land_spe_river_water_large_20m_right_10d_Junction_2m_02", "land_spe_river_water_large_20m_right_5d_01", 
        "land_spe_river_water_large_20m_straight_01", "land_spe_river_water_large_20m_straight_01_crossing_01", 
        "land_spe_river_water_large_40m_straight_01", "land_spe_river_water_medium_10m_left_10d_01", 
        "land_spe_river_water_medium_10m_left_30d_01", "land_spe_river_water_medium_10m_left_5d_01", 
        "land_spe_river_water_medium_10m_right_10d_01", "land_spe_river_water_medium_10m_right_30d_01", 
        "land_spe_river_water_medium_10m_right_5d_01", "land_spe_river_water_medium_10m_straight_01", 
        "land_spe_river_water_medium_20m_left_10d_01", "land_spe_river_water_medium_20m_left_5d_01", 
        "land_spe_river_water_medium_20m_right_10d_01", "land_spe_river_water_medium_20m_right_5d_01", 
        "land_spe_river_water_medium_20m_straight_01", "land_spe_river_water_medium_40m_straight_01", 
        "land_spe_river_water_medium_junction_01", "land_spe_river_water_medium_junction_02", 
        "land_spe_river_water_medium_junction_03", "land_spe_river_water_medium_junction_04", 
        "land_spe_river_water_medium_junction_05", "land_spe_river_water_medium_junction_06", 
        "land_spe_river_water_medium_junction_07", "land_spe_river_water_medium_junction_08", 
        "land_spe_river_water_small_10m_left_10d_01", "land_spe_river_water_small_10m_left_30d_01", 
        "land_spe_river_water_small_10m_left_5d_01", "land_spe_river_water_small_10m_right_10d_01", 
        "land_spe_river_water_small_10m_right_30d_01", "land_spe_river_water_small_10m_right_5d_01", 
        "land_spe_river_water_small_10m_straight_01", "land_spe_river_water_small_20m_left_10d_01", 
        "land_spe_river_water_small_20m_left_5d_01", "land_spe_river_water_small_20m_right_10d_01", 
        "land_spe_river_water_small_20m_right_5d_01", "land_spe_river_water_small_20m_straight_01", 
        "land_spe_river_water_small_40m_straight_01", "land_spe_river_water_small_junction_01", 
        "land_spe_river_water_small_junction_02", "Land_SPE_StreetLamp", "Land_SPE_StreetLamp_Off", 
        "Land_SPE_StreetLamp_pole", "Land_SPE_StreetLamp_pole_off", "Land_SPE_StreetLamp_wall", "Land_SPE_US_Lamp", 
        "Land_SPE_Wood_Fence_02_Gate", "Land_SPE_Wood_Gate_4m_01", "Land_SPE_Wood_Gate_4m_02", "Land_SPE_Wood_Gate_5m_01", 
        "Land_SPE_Wood_Gate_5m_02", "Land_SPE_Wood_TrenchLogWall_01_4m_v1", "Land_StoneWell_01_F", 
        "Land_TelephoneLine_01_wire_50m_main_F",
        "Land_vn_tunnel_01_building_01_01","Land_vn_tunnel_01_building_01_02","Land_vn_tunnel_01_building_01_03","Land_vn_tunnel_01_building_01_04",
        "Land_vn_tunnel_01_building_02_01","Land_vn_tunnel_01_building_02_02","Land_vn_tunnel_01_building_02_03","Land_vn_tunnel_01_building_02_04",
        "Land_vn_tunnel_01_building_03_01","Land_vn_tunnel_01_building_03_02","Land_vn_tunnel_01_building_03_03","Land_vn_tunnel_01_building_03_04",
        "Land_vn_tunnel_01_building_04_01","Land_vn_tunnel_01_building_04_02","Land_vn_tunnel_01_building_04_03","Land_vn_tunnel_01_building_04_04",
        "Land_vn_tunnel_01_building_01_05","Land_vn_tunnel_01_building_02_05","Land_vn_tunnel_01_building_03_05","Land_vn_tunnel_01_building_04_05",
        "Land_Crane_F","Land_MobileCrane_01_F","Land_MobileCrane_01_hook_F","Land_CraneRail_01_F","Land_GantryCrane_01_F","Land_A_Crane_02a",
        "Land_A_Crane_02b","Land_A_CraneCon"
    ];                                                                             
                                                                                   
    private _objectsArray = nearestObjects [_pos, ["house"], _radius];  
    
    {
        // no-buildings have building positions equal to [0,0,0] or are in my list
        if ((_x buildingPos 0) isEqualTo [0,0,0] || {typeOf _x in _nonBuildingTypes}) then {
            _objectsArray deleteAt _forEachIndex;
        };
    } forEachReversed _objectsArray;                     
            
    _objectsArray
};

ITW_ObjCenter = {
    params ["_buildings"];
    private ["_xmin","_xmax","_ymin","_ymax","_p","_px","_py"];
    
    // Find center of the nearby buildings
    _xmin = worldSize;
    _xmax = 0;
    _ymin = worldSize;
    _ymax = 0;
    {
        _p = getPosATL _x;
        _px = _p select 0;
        _py = _p select 1;
        if (_px > _xmax) then { _xmax = _px; };
        if (_px < _xmin) then { _xmin = _px; };
        if (_py > _ymax) then { _ymax = _py; };
        if (_py < _ymin) then { _ymin = _py; };
    } count _buildings;
    _center = [(_xmax + _xmin)/2, (_ymax + _ymin)/2, 0];
    
    // now find the center of the current town
    _dist = 50;
    _radius = 150;
    _done = false;
    while {not _done} do {
        _centerN  = _center getPos [_dist, 0];
        _centerNE = _center getPos [_dist, 45];
        _centerE  = _center getPos [_dist, 90];
        _centerSE = _center getPos [_dist, 135];
        _centerS  = _center getPos [_dist, 180];
        _centerSW = _center getPos [_dist, 125];
        _centerW  = _center getPos [_dist, 270];
        _centerNW = _center getPos [_dist, 315];
    
        _count   = count ([_center,   _radius] call ITW_ObjNearestBuildings);
        _countN  = count ([_centerN , _radius] call ITW_ObjNearestBuildings);
        _countNE = count ([_centerNE, _radius] call ITW_ObjNearestBuildings);
        _countE  = count ([_centerE , _radius] call ITW_ObjNearestBuildings);
        _countSE = count ([_centerSE, _radius] call ITW_ObjNearestBuildings);
        _countS  = count ([_centerS , _radius] call ITW_ObjNearestBuildings);
        _countSW = count ([_centerSW, _radius] call ITW_ObjNearestBuildings);
        _countW  = count ([_centerW , _radius] call ITW_ObjNearestBuildings);
        _countNW = count ([_centerNW, _radius] call ITW_ObjNearestBuildings);
        
        //diag_log format ["GP: center ao %1 : N%2 E%3 S%4 W%5",_count,_countN,_countE,_countS,_countW];
        _done = true;
        if (_count < _countN ) then { _count = _countN ; _center = _centerN ; _done = false; };
        if (_count < _countNE) then { _count = _countNE; _center = _centerNE; _done = false; };
        if (_count < _countE ) then { _count = _countE ; _center = _centerE ; _done = false; };
        if (_count < _countSE) then { _count = _countSE; _center = _centerSE; _done = false; };
        if (_count < _countS ) then { _count = _countS ; _center = _centerS ; _done = false; };
        if (_count < _countSW) then { _count = _countSW; _center = _centerSW; _done = false; };
        if (_count < _countW ) then { _count = _countW ; _center = _centerW ; _done = false; };
        if (_count < _countNW) then { _count = _countNW; _center = _centerNW; _done = false; };
        
        if (!_done and (_count > 40) and ((random 10) > 6)) then { _done = true; }; // random chance to just leave it offcenter
    };
    _center
};

ITW_ObjNext = {
    params [["_isSaveLoad",false]]; // _isSaveLoad is true when starting up a saved game
    
    if !(isServer) exitWith {[_isSaveLoad] remoteExec ["ITW_ObjNext",2]};
    
    private _prevZoneIndex = ITW_ZoneIndex;
    private _newZoneIndex = if (!_isSaveLoad) then {ITW_ZoneIndex + 1} else {ITW_ZoneIndex};  
    
    diag_log format ["ITW: ZoneNext %1 >> %2",_prevZoneIndex,_newZoneIndex];
    
    if (!_isSaveLoad && _newZoneIndex > 1) then {
        // complete previous tasks
        private _oldObjIds = ITW_Zones#_prevZoneIndex;
        if (isNil "_oldObjIds") exitWith {};
        {
            private _idx = _x;
            private _obj = ITW_Objectives#_idx;
            private _taskId = _obj#ITW_OBJ_TASKID;
            private _subTaskId = _taskId + "-1";
            private _name = _obj#ITW_OBJ_NAME;
            {
                if (_x isEqualTo _subTaskId) then {[_subTaskId,"SUCCEEDED",false] call BIS_fnc_taskSetState} else {
                    if !(_x call BIS_fnc_taskCompleted) then {[_x,"CANCELED",false] call BIS_fnc_taskSetState};
                };
            } forEach (_taskId call BIS_fnc_taskChildren);
            [_taskId, "SUCCEEDED", _forEachIndex == 0 && _newZoneIndex - 1 > ITW_ParamStartWithZonesCaptured] call BIS_fnc_taskSetState;
            [_obj,_newZoneIndex] call ITW_ObjSetMarker;
            private _board = nearestObject [ITW_Bases#(_obj#ITW_OBJ_INDEX)#ITW_BASE_GARAGE_POS,ITW_BASE_PLACARD];
            private _gInfo = _board getVariable ["itwrepair",[]];
            if !(_gInfo isEqualTo []) then {
                _gInfo call ITW_vehRepairPointRemove;
                (_gInfo#0) remoteExec ["ITW_BaseAddVehFTPointMP",0,true];
            };
            deleteVehicle _board; // 'fast travel from garage pad to flag' board needs deleting on captured zones
            false
        } forEach _oldObjIds;
        if (ITW_ParamMines > 0) then {[_oldObjIds,true] spawn ITW_ObjMinefields};
    };
    
    call ITW_SideOpsNext;
    
    // handle win state
    if (_newZoneIndex >= count ITW_Zones) exitWith {
        ITW_GameOver = true;
        sleep 7;
        call ITW_EraseGame;
        call SKL_BoundaryLinesErase;
        if (ITW_ParamEndMission == 1) then {
            ["END1", true,  true, true, true] remoteExec ["BIS_fnc_endMission",0, true];
        } else {
            [localize "STR_ITW_OBJ_MissionComplete",-1,-1,8,1,0,888] remoteExec ["BIS_fnc_dynamicText",0];
        };
        sleep 1e10;
    };
    
    ITW_ZoneIndex = _newZoneIndex;
    publicVariable "ITW_ZoneIndex";
    
    // calculate new KeepOutZone
    _newZoneIndex spawn {
        // spawn this in case attack vectors are still be calculated
        private _zoneIndex = _this;
        private _minDist = 1e6;
        {
            private _objId = _x;
            private _obj = ITW_Objectives#_objId;
            private _objPos = _obj#ITW_OBJ_POS;
            private _vectors = [-1];
            while {_vectors = (_obj#ITW_OBJ_ATTACKS) arrayIntersect (_obj#ITW_OBJ_ATTACKS);_vectors isEqualTo [-1]} do {sleep 1};
            {
                private _baseId = _x;
                private _dist = _objPos distance (ITW_Bases#_baseId#ITW_BASE_POS);
                if (_dist < _minDist) then {_minDist = _dist};
            } forEach _vectors;
        } forEach ITW_Zones#_zoneIndex;
        private _objSize = ITW_ParamObjectiveSize * (if (ITW_ParamObjectiveVariation in [1,3]) then {1.25} else {1});
        private _minSize = 400 max (_minDist - _objSize)/2 min 1000;
        if (_minSize != ITW_ZoneKeepOut) then {
            ITW_ZoneKeepOut = _minSize;
            ITW_ZoneKeepOutSqr = _minSize*_minSize;
            publicVariable "ITW_ZoneKeepOut";
            publicVariable "ITW_ZoneKeepOutSqr";
        };
    };

    private _contestedObjectives = if (_newZoneIndex < count ITW_Zones) then {ITW_Zones#_newZoneIndex} else {[]};
    
    if (!_isSaveLoad) then {
        // mark contested objectives
        {
            private _obj = ITW_Objectives#_x;
            _obj set [ITW_OBJ_OWNER,ITW_OWNER_CONTESTED];
            false
        } count _contestedObjectives;
        
        // setup captured bases
        {
            private _obj = ITW_Objectives#_x;
            _obj set [ITW_OBJ_OWNER,ITW_OWNER_FRIENDLY];
            private _baseIndex = _obj#ITW_OBJ_INDEX;
            _baseIndex spawn ITW_BaseNext;
            YIELD_CPU;
            false
        } count (ITW_Zones#_prevZoneIndex);
        
        ["before-atk-next",[_prevZoneIndex,_newZoneIndex]] call ITW_CLASH_fnc_ObserveLifecycle;
        0 call ITW_AtkNext;
        
        ITW_ObjContestedState = _contestedObjectives apply {[_x,false,-1]};
    } else {
        // on loading a game, setup all owned bases
        {
            if (_forEachIndex >= _newZoneIndex) exitWith {};
            private _objIds = _x;
            {
                private _obj = ITW_Objectives#_x;
                private _baseIndex = _obj#ITW_OBJ_INDEX;
                _baseIndex call ITW_BaseNext;
                _obj set [ITW_OBJ_OWNER,ITW_OWNER_FRIENDLY];
            } forEach _objIds;
            false
        } forEach ITW_Zones;
        
            // saw once where ITW_ObjContestedState still held previous zone data, handle that case here
        if (ITW_ObjContestedState isNotEqualTo [] && {!(ITW_ObjContestedState#0#0 in (ITW_Zones#ITW_ZoneIndex))}) then {ITW_ObjContestedState = []};
        
        if (ITW_ObjContestedState isEqualTo []) then {ITW_ObjContestedState = _contestedObjectives apply {[_x,false,-1]}};
    };
    publicVariable "ITW_Bases";
    publicVariable "ITW_Objectives";
    publicVariable "ITW_ObjContestedState";
    ["objective-state-published",[_prevZoneIndex,_newZoneIndex,+_contestedObjectives]] call ITW_CLASH_fnc_ObserveLifecycle;
    
    0 call ITW_EnemyCivManager;
    
    if (ITW_ParamShowEnemyZonesOnMap == 2) then {
        [{
            params ["_pos"];
            private _obj = [_pos,ITW_OWNER_UNDEFINDED] call ITW_ObjGetNearest;
            switch (_obj#ITW_OBJ_OWNER) do {
                case ITW_OWNER_ENEMY:    {east};
                case ITW_OWNER_FRIENDLY: {west};
                default                  {sideUnknown};
            };
        },800,50,"DiagGrid",1] spawn SKL_BoundaryLines;
    };  
    private _flags = [];
    ITW_genStructuresComplete = [];
    {
        // add extra buildings if needed
        private _objIdx = _x;
        private _obj = ITW_Objectives#_objIdx;
        private _aoPos = +(_obj#ITW_OBJ_POS);
        private _objSize = _obj#ITW_OBJ_SIZE;
        private _basePos = ITW_Bases#(_obj#ITW_OBJ_INDEX)#ITW_BASE_POS;
        private _vehSpawn = _obj#ITW_OBJ_V_SPAWN;
        private _keepClearZones = [[_basePos,120]];
        if (!isNil "_vehSpawn" && {!(_vehSpawn isEqualTo [])}) then {_keepClearZones pushBack [_vehSpawn,50]};
        if (ITW_ParamExtraBuildings > 0) then {
            private _minNumberOfBuildings = round (_objSize/12);
            [_aoPos,_objSize,_minNumberOfBuildings,_keepClearZones,_objIdx] spawn ITW_ObjGenStructures;
        } else {
            ITW_genStructuresComplete pushBack _objIdx;
        };
                
        // create new tasks
        private _idx = _objIdx;
        private _taskId = _obj#ITW_OBJ_TASKID;
        private _name   = _obj#ITW_OBJ_NAME;
        private _flag   = _obj#ITW_OBJ_FLAG;
        private _assign = "CREATED";
        private _showHint = if (_isSaveLoad || {_forEachIndex > 0 || {_newZoneIndex - 1 < ITW_ParamStartWithZonesCaptured}}) then {false} else {true};
        _aoPos set [2,1];
        private _title = if (ITW_ParamTargets > 0) then {_name} else {localize "STR_ITW_OBJ_Attack" +" "+_name};
        [true, _taskId, ["",_title,""], _aoPos, _assign, 20, _showHint, "attack", ITW_ParamObjectivesVisible3D == 1] call BIS_fnc_taskCreate;
        _flags pushBack _flag;
        [_obj,ITW_ZoneIndex] call ITW_ObjSetMarker;
        YIELD_CPU;
    } forEach _contestedObjectives;
    [_contestedObjectives] call ITW_ObjGenStatics;
    
    if (ITW_ParamDamageBuildings > 0) then {
        [_contestedObjectives] spawn {
            params ["_contestedObjectives"];
            private _objCount = count _contestedObjectives;
            waitUntil {sleep 1;count ITW_genStructuresComplete == _objCount};
            {
                private _pos = ITW_Objectives#_x#ITW_OBJ_POS;
                private _size = ITW_Objectives#_x#ITW_OBJ_SIZE + 800;
                private _playerDist = playableUnits apply {_x distance _pos} select {_x <= _size};
                if (_playerDist isNotEqualTo []) then {
                    _size = selectMax _playerDist - 300;
                };
                [_pos,_size,random 10000] call BIS_fnc_destroyCity;
            } forEach _contestedObjectives;
        };
    };
    
    // add minefields if needed
    if (ITW_ParamMines > 0) then {[_contestedObjectives] spawn ITW_ObjMinefields};
        
    // handle flags and markers
    ITW_FlagsActive = _flags;
    publicVariable "ITW_FlagsActive";
    
    // setup targets
    if (ITW_ParamTargets > 0) then {
        [_contestedObjectives] call ITW_Targets;
        
        // if we added subtasks, then we need to add the subtask to capture the zone as well
        if (!isNil "ITW_targetsActive") then {
            {
                private _obj = ITW_Objectives#_x;
                private _parentTaskId = _obj#ITW_OBJ_TASKID;
                private _name   = _obj#ITW_OBJ_NAME;
                private _aoPos = +(_obj#ITW_OBJ_POS);
                _aoPos set [2,1];
                private _childTaskId = _parentTaskId + "-1";
                [true, [_childTaskId,_parentTaskId], ["",localize "STR_ITW_OBJ_Attack" +" "+_name,""], _aoPos, "CREATED", 10, false, "attack", ITW_ParamObjectivesVisible3D == 1] call BIS_fnc_taskCreate;
                if (ITW_ParamObjectivesVisible3D == 1) then {
                    // hide the parent task
                    [_parentTaskId, false] call BIS_fnc_taskSetAlwaysVisible;
                };
            } forEach ITW_targetsActive;
        } else {
            {
                private _obj = ITW_Objectives#_x;
                private _taskId = _obj#ITW_OBJ_TASKID;
                private _name   = _obj#ITW_OBJ_NAME;
                [_taskId, ["",localize "STR_ITW_OBJ_Attack" +" "+_name,""]] call BIS_fnc_taskSetDescription;
            } forEach _contestedObjectives;
        };
    };
    
    if (!_isSaveLoad) then {["zone"] call ITW_SaveGame};
    ITW_OwnedAirports = nil;
    [true] call ITW_ObjOwnedAirports; // update the markers
    ["zone"] call ITW_Bombardment;
};

ITW_ObjFlag = {
    params ["_aoPos","_captured"];
    private _flag = objNull;
    private _flagPos = _aoPos;
    private _flagTexture = if (_captured) then {ITW_PlayerFlag} else {ITW_EnemyFlag};
    
    //private _pos = _aoPos findEmptyPosition [0,ITW_ParamObjectiveSize,"Flag_Blue_F"];-- findEmptyPosition causes frame drop
    private _pos = [_aoPos,0,20,2,0,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo [0]) then {_pos = [_aoPos,0,ITW_ParamObjectiveSize,2,0,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos};
    if (_pos isEqualTo [0]) then {_pos = _aoPos};
    _flag = createVehicle [FLAG_TYPE, _pos, [], 0, "Can_collide"];
    _flag setVariable ["ITW_FlagPos",_aoPos];
    _flag setFlagTexture _flagTexture;
    _flag allowDamage false;
    _flagPos = getPosATL _flag;
        
    _flag
};

ITW_ObjFlagMP = {
    // call on all clients
    waitUntil {!isNil "ITW_ParamVirtualGarage"};
    params ["_flags"];
    {
        _x params ["_flag","_pos"];
        _lightPos = getPosATL _flag;
        _lightPos set [2,2];
        private _light = "#lightpoint" createVehicleLocal _lightPos;
        _light setLightIntensity 500;
        _light setLightAmbient [0,0,0]; 
        _light setLightColor [0.3,0.3,0.3];
        if (ITW_ParamVirtualGarage > 0) then {
            _flag addAction [localize "STR_ITW_OBJ_FtToGaragePad",{
                    params ["_flag", "_player", "_actionId", "_arguments"];
                    private _pos = [ITW_Garages, _flag] call BIS_fnc_nearestPosition;
                    private _bringUnits = call ITW_RadioBringAiMenu;
                    if (_bringUnits isEqualTo 0) exitWith {};
                    _player setDir -90;
                    _pos = _pos getPos [10,90];
                    _pos set [2,0.2];
                    _player setPosASL _pos;
                    _bringUnits apply {_x setPosATL (_pos getPos [0.5 + random 1,random 360])};
                },nil,10,true,true,"",'vehicle _this == _this && {flagTexture _target == ITW_PlayerFlag && {flagAnimationPhase _target > 0.9}}',6];
        };
        _flag addAction [localize "STR_ITW_BASE_FastTravel",{
                params ["_flag", "_player", "_actionId", "_arguments"];
                [] spawn ITW_RadioFastTravel;
            },nil,10,false,true,"",'vehicle _this == _this && {flagTexture _target == ITW_PlayerFlag && {flagAnimationPhase _target > 0.9}}',8];
        //_flag addAction ["Arsenal",{
        //        params ["_flag", "_player", "_actionId", "_arguments"];
        //        ["Open",true,missionNamespace] call BIS_fnc_arsenal;
        //    },nil,10,false,true,"",'flagTexture _target == ITW_PlayerFlag && {flagAnimationPhase _target > 0.9}',6];
        
    } forEach _flags;
    [_flags apply {_x#0},true,6] call CustomArsenal_AddVAs;
};

ITW_ObjFlagCapture = {
    params [["_objIdx",-1]];
    if (_objIdx in (ITW_Zones#ITW_ZoneIndex)) then {
        ITW_objFlagDebug = _objIdx;
    } else {
        private _info = [];
        {_info pushBack [_x,ITW_Objectives#_x#ITW_OBJ_NAME]} forEach (ITW_Zones#ITW_ZoneIndex);
        diag_log "==== ITW_ObjFlagCapture ====";
        {diag_log _x} forEach _info;
        _info
    };
};

ITW_ObjFlagTask = {
    // runs on server
    scriptname "ITW_FlagTask";
    #define FLAG_SLEEP           0.5
    #define FLAG_MAX_UNIT_EFFECT 15 // maximum number of units one team has over the other that still increase capture speed
    #define FLAG_MOVE_PER_SEC    0.0004 
    
    private _captureSpeed = FLAG_MOVE_PER_SEC * ITW_ParamObjectiveCaptureSpeed/3;
    private _prevZoneIndex = 0;
    
    // defend phase setup
    private _dpZoneTrigger = false; // if true, defend phase will trigger just before zone capture
    private _dpIsFlag = ITW_ParamDefendPhaseType >= 10 && {ITW_ParamDefendPhaseType < 20};
    private _dpDoneTimeout = 1; // needs to initialize to something > 0
    private _dpObjIdx = -1; // variable to hold capture obj id after defend phase has ended
    private _defendMustSucceed = ITW_ParamDefendPhaseType >= 30;
    
    private ["_currObjIdxs","_targetUnitsAdvantage"];
    
    waitUntil {sleep 1;ITW_ZoneIndex > 0};
    
    while {ITW_ZoneIndex < count ITW_Zones} do {
        if (ITW_defendPhaseObjIdx > 0 && {_dpObjIdx < 0}) then {_dpObjIdx = ITW_defendPhaseObjIdx};
        if (ITW_ZoneIndex != _prevZoneIndex) then {
            _dpObjIdx = -1;
            _currObjIdxs = ITW_Zones#ITW_ZoneIndex;
            _targetUnitsAdvantage = 5 min round (ITW_ParamEnemyAiCnt / (count _currObjIdxs) / 4); // how many units advantage a side gets due to Targets
            
            // Defend Mode: Zone trigger
            if (ITW_ParamDefendPhaseType >= 20) then {
                if (_defendMustSucceed || {ITW_defendPhaseZoneDone != ITW_ZoneIndex}) then {
                    _chance = ITW_ParamDefendPhaseType mod 10;
                    if (_chance == 0) then {_chance = 10};
                    if (random 10 < _chance) then {_dpZoneTrigger = true};
                };
            };
        };
        
        // Defend Mode Flag trigger
        if (_dpIsFlag && {ITW_defendPhaseFlagCount <= 0}) then {
            _chance = ITW_ParamDefendPhaseType mod 10;
            if (_chance == 0) then {_chance = 10};
            ITW_defendPhaseFlagCount = ceil ((ln random 1) / ln (1 - _chance/30)); // after this many flag captures, the defend phase is triggered 
            // sometimes you'll get a really large number here.  Lets truncate it.
            ITW_defendPhaseFlagCount = ITW_defendPhaseFlagCount min (15 - _chance)
        };
        
        private _contestedStateChanged = false;
        private _allCaptured = true;
        {
            private _objIdx = _x;
            
            if (isNil "ITW_objFlagDebug") then { // only freeze when we're not still handling the debug flag
                if (ITW_defendPhaseObjIdx == _objIdx && {!ITW_defendRunning})        then {continue}; // freeze defend flag during wait before defend phase
                if (ITW_defendPhaseObjIdx > 0 && {ITW_defendPhaseObjIdx != _objIdx}) then {continue}; // freeze all other flags during defend phase and during wait before it
            };
            
            private _obj = ITW_Objectives#_objIdx;
            private _objSize = _obj#ITW_OBJ_SIZE;
            
            private _flag = _obj#ITW_OBJ_FLAG;         
            if (ITW_ZoneIndex != _prevZoneIndex) then {
                private _isPlayer = _objIdx call ITW_ObjContestedOwnerIsFriendly;
                _flag setFlagTexture (if (_isPlayer) then {ITW_PlayerFlag} else {ITW_EnemyFlag});          
                _flag setVariable ["ITW_FlagIsPlayer",_isPlayer,true];
                _flag setVariable ["ITW_FlagPhase",1,true]; 
                _flag setVariable ["ITW_FlagUnlockTime",nil,true];
                _flag setVariable ["ITW_FlagLockOwner",_isPlayer];
            };
            
            private _flagUnlockTime = _flag getVariable ["ITW_FlagUnlockTime",0];
            
            if (_flagUnlockTime > serverTime) then {continue};
            if (_flagUnlockTime > 0) then {_flag setVariable ["ITW_FlagUnlockTime",nil,true]};
            
            private _ratio = 1;
            private _prevPhase = _flag getVariable ["ITW_FlagPhase",1];
            private _flagIsPlayer = _flag getVariable "ITW_FlagIsPlayer"; 
            private _isAttack = _flag getVariable ["ITW_FlagIsAttack",!(_objIdx call ITW_ObjContestedOwnerIsFriendly)];            
            
            private _phaseAdj = 0;
            
            if (_prevPhase < 1 || {!_flagIsPlayer}) then {_allCaptured = false};
            
            private _pos = _flag getVariable "ITW_FlagPos";
            private _friendlyCnt = {CONSCIOUS(_x) && {_x distance _pos < _objSize}} count units ITW_PlayerSide;
            private _enemyCnt = {CONSCIOUS(_x) && {_x distance _pos < _objSize}} count units ITW_EnemySide;
            private _targetAdvantage = [_objIdx] call ITW_TargetAdvantage;
            if (_targetAdvantage != 0 && {time > 60}) then { // at start of mission don't give advantage until units are all in place
                if (_targetAdvantage > 0 && {_friendlyCnt > 0}) then { // friendlies only get advantage if at least one is present
                    _friendlyCnt = _friendlyCnt + _targetUnitsAdvantage;
                } else {
                    _enemyCnt = _enemyCnt + _targetUnitsAdvantage;
                };
            };
            private _sideOpsAdvantage = (["CAP"] call ITW_SideOpsAdvantage)/3; // give +1/3 person per sideOp done per intensity (default 1.6 per sideop)
            if (_sideOpsAdvantage > 0 && {time > 60}) then { // at start of mission don't give advantage until units are all in place
                if (_friendlyCnt > 0) then { // friendlies only get advantage if at least one is present
                    _friendlyCnt = _friendlyCnt + _sideOpsAdvantage;
                };
            };
            
            if (!isNil "ITW_objFlagDebug") then {
                ///////////////
                //// DEBUG ////      ITW_objFlagDebug = "all", obj Name case sensitive, or obj Index
                ///////////////
                _debugSafe = false;
                private _isAllBlue = false;
                private _isAllRed = false;
                private _isAll = [toLowerANSI ITW_objFlagDebug,"all"] call ITW_FncStartsWith;
                if (_isAll) then {
                    _isAllBlue = [toLowerANSI ITW_objFlagDebug,"blue"] call ITW_FncEndsWith;
                    _isAllRed = [toLowerANSI ITW_objFlagDebug,"red"] call ITW_FncEndsWith;
                };
                private _trigger = _isAll;
                if (!_trigger) then {
                    if (typeName ITW_objFlagDebug == "SCALAR") then { 
                        // obj index
                        if (_objIdx == ITW_objFlagDebug) then {_trigger = true};
                    } else {
                        // case sensitive obj name
                        if (ITW_objFlagDebug isEqualTo (_obj#ITW_OBJ_NAME)) then {_trigger = true};
                    };
                };
                if (_trigger) then {
                    if (!_isAll || {_forEachIndex == ((count _currObjIdxs) - 1)}) then {ITW_objFlagDebug = nil};
                    _flagIsPlayer = !_flagIsPlayer;
                    if (_isAllBlue) then {_flagIsPlayer = true};
                    if (_isAllRed) then {_flagIsPlayer = false};
                    _flag setVariable ["ITW_FlagIsPlayer",_flagIsPlayer,true];
                    _flag setFlagTexture (if (_flagIsPlayer) then {ITW_PlayerFlag} else {ITW_EnemyFlag});
                    _prevPhase = 0.999;
                    if (_flagIsPlayer) then {_friendlyCnt = 1000;_enemyCnt = 0;} else {_friendlyCnt = 0;_enemyCnt = 1000};
                };
            };
            
            if (_friendlyCnt + _enemyCnt == 0) then {
                // allow flag to drop/recover when no one around
                if ( _isAttack && {!_flagIsPlayer && {_prevPhase >= 1}})  then {continue};
                if (!_isAttack && { _flagIsPlayer && {_prevPhase >= 1}})  then {continue};
                if (_isAttack) then {_ratio = -1} else {_ratio = 1};
            } else {
                if (_friendlyCnt == _enemyCnt) then {continue};
                
                // check for flag not going to change cases
                if ( _isAttack && {!_flagIsPlayer && {_prevPhase >= 1 && {_friendlyCnt < _enemyCnt}}}) then {continue};
                if (!_isAttack && { _flagIsPlayer && {_prevPhase >= 1 && {_friendlyCnt > _enemyCnt}}}) then {continue}; 

                _ratio = FLAG_MAX_UNIT_EFFECT min (_friendlyCnt - _enemyCnt); // how many more units in zone (negative is more enemy)
                if (_ratio > FLAG_MAX_UNIT_EFFECT ) then {_ratio = FLAG_MAX_UNIT_EFFECT };
                if (_ratio < -FLAG_MAX_UNIT_EFFECT) then {_ratio = -FLAG_MAX_UNIT_EFFECT};
                _ratio = if (_ratio < 0) then {(_ratio/2)-0.5} else {(_ratio/2)+0.5}; // scale as 1, 1.5, 2
                if (_enemyCnt == 0 || {_friendlyCnt == 0}) then {_ratio = _ratio + 0.5}; // capture even faster if no opposition
            };
            _phaseAdj = _ratio * _captureSpeed;
            if (!_flagIsPlayer) then {_phaseAdj = -_phaseAdj};
            
            _phase = _prevPhase + _phaseAdj;            
            if (_phase < 0) then {
                _phase = 0;
                _flagIsPlayer = !_flagIsPlayer;              
                _flag setVariable ["ITW_FlagIsPlayer",_flagIsPlayer,true];
                _flag setFlagTexture (if (_flagIsPlayer) then {ITW_PlayerFlag} else {ITW_EnemyFlag});
            } else {
                if (_phase >= 1) then {
                    _phase = 1;
                    if (_prevPhase != 1) then {
                        private _updateMarker = false;
                        if (ITW_ParamObjLockTime > 0 && {_flag getVariable ["ITW_FlagLockOwner",false] != _flagIsPlayer}) then {
                            _flag setVariable ["ITW_FlagUnlockTime",serverTime + ITW_ParamObjLockTime,true];
                            _flag setVariable ["ITW_FlagLockOwner",_flagIsPlayer];
                        };
                        if ( _isAttack && { _flagIsPlayer}) then {_flag setVariable ["ITW_FlagIsAttack",false];_updateMarker=true} else {
                        if (!_isAttack && {!_flagIsPlayer}) then {_flag setVariable ["ITW_FlagIsAttack",true] ;_updateMarker=true}};
                        ITW_ObjContestedState#_forEachIndex set [ITW_CONT_PLAYER_OWNED,_flagIsPlayer];
                        _contestedStateChanged = true;
                        if (_updateMarker) then {[_obj,ITW_ZoneIndex] call ITW_ObjSetMarker};
                        if (_dpIsFlag && {_flagIsPlayer && {ITW_defendPhaseFlagCount > 0}}) then {
                            // handle Defend Mode flag trigger
                            ITW_defendPhaseFlagCount = ITW_defendPhaseFlagCount - 1;
                            if (ITW_defendPhaseFlagCount == 0) then {0 call ITW_ObjDefendPhase};
                        };
                        if (!_flagIsPlayer && _defendMustSucceed) then {_dpZoneTrigger = true};
                    };
                };
            };
            if (_phase != _prevPhase) then {
                _flag setVariable ["ITW_FlagPhase",_phase,true];
            };
            YIELD_CPU;
        } forEach _currObjIdxs;
        _prevZoneIndex = ITW_ZoneIndex;
        
        if (_contestedStateChanged) then {
            publicVariable "ITW_ObjContestedState";
            ["contested-state-published",[ITW_ZoneIndex,+ITW_ObjContestedState]] call ITW_CLASH_fnc_ObserveLifecycle;
        };
        if (_allCaptured && _dpZoneTrigger && !ITW_defendRunning) then {
            0 call ITW_ObjDefendPhase;
            _dpZoneTrigger = false; 
        };
        
        private _zoneCaptured = _allCaptured && {ITW_defendPhaseObjIdx <= 0 && {time > _dpDoneTimeout}};
        
        // _dpDoneTimeout is used so we don't trigger the zone capture until a few seconds after the defend phase has ended so the notifications don't show on top of each other
        if (_dpDoneTimeout > 0 && ITW_defendRunning)  then {_dpDoneTimeout = -1;       [ITW_ParamDefendPhaseType >= 20] spawn ITW_AtkDefendStart};
        if (_dpDoneTimeout < 0 && !ITW_defendRunning) then {_dpDoneTimeout = time + 8; [_zoneCaptured && (ITW_ParamDefendPhaseType >= 20),_dpObjIdx] spawn ITW_AtkDefendDone};
        
        if (_zoneCaptured) then {
            ITW_ObjZonesUpdating = true;
            ["zone-transition-begin",[ITW_ZoneIndex]] call ITW_CLASH_fnc_ObserveLifecycle;
            false call ITW_ObjNext;
            ITW_ObjZonesUpdating = false;
            ["zone-transition-end",[ITW_ZoneIndex]] call ITW_CLASH_fnc_ObserveLifecycle;
        };
        
        sleep FLAG_SLEEP;
        while {LV_PAUSE} do {sleep 5};
        
    };
};

ITW_ObjFlagHud = {
    // spawn on all clients
    if (!hasInterface) exitWith {};
    scriptname "ITW_ObjFlagHud";
    
    private _layerId = "RscItwFlagStatus" call BIS_fnc_rscLayer;
    _layerId cutRsc ["RscItwFlagStatus", "PLAIN", -1, false];
    
    private "_display";
    waitUntil {_display = uiNamespace getVariable ['RscItwFlagStatus',displayNull]; !isNull _display};
    
    private _blueCtrls = [ITW_0_BLUE_CTRL,ITW_1_BLUE_CTRL,ITW_2_BLUE_CTRL,ITW_3_BLUE_CTRL,ITW_4_BLUE_CTRL,ITW_5_BLUE_CTRL,ITW_6_BLUE_CTRL,ITW_7_BLUE_CTRL] apply {_display displayCtrl _x};
    private _redCtrls  = [ITW_0_RED_CTRL,ITW_1_RED_CTRL,ITW_2_RED_CTRL,ITW_3_RED_CTRL,ITW_4_RED_CTRL,ITW_5_RED_CTRL,ITW_6_RED_CTRL,ITW_7_RED_CTRL]         apply {_display displayCtrl _x};
    private _textCtrls = [ITW_0_TEXT_CTRL,ITW_1_TEXT_CTRL,ITW_2_TEXT_CTRL,ITW_3_TEXT_CTRL,ITW_4_TEXT_CTRL,ITW_5_TEXT_CTRL,ITW_6_TEXT_CTRL,ITW_7_TEXT_CTRL] apply {_display displayCtrl _x};
    private _lockCtrls = [ITW_0_LOCK_CTRL,ITW_1_LOCK_CTRL,ITW_2_LOCK_CTRL,ITW_3_LOCK_CTRL,ITW_4_LOCK_CTRL,ITW_5_LOCK_CTRL,ITW_6_LOCK_CTRL,ITW_7_LOCK_CTRL] apply {_display displayCtrl _x};
    private _flagCtrls = [ITW_RED_FACTION_FLAG,ITW_BLUE_FACTION_FLAG] apply {_display displayCtrl _x};
    private _hBlueCtrls = [ITW_0H_BLUE_CTRL,ITW_1H_BLUE_CTRL,ITW_2H_BLUE_CTRL,ITW_3H_BLUE_CTRL,ITW_4H_BLUE_CTRL,ITW_5H_BLUE_CTRL,ITW_6H_BLUE_CTRL,ITW_7H_BLUE_CTRL] apply {_display displayCtrl _x};
    private _hRedCtrls = [ITW_0H_RED_CTRL,ITW_1H_RED_CTRL,ITW_2H_RED_CTRL,ITW_3H_RED_CTRL,ITW_4H_RED_CTRL,ITW_5H_RED_CTRL,ITW_6H_RED_CTRL,ITW_7H_RED_CTRL] apply {_display displayCtrl _x};
    private _hBgBlueCtrls= [ITW_0H_BG_BLUE_CTRL,ITW_1H_BG_BLUE_CTRL,ITW_2H_BG_BLUE_CTRL,ITW_3H_BG_BLUE_CTRL,ITW_4H_BG_BLUE_CTRL,ITW_5H_BG_BLUE_CTRL,ITW_6H_BG_BLUE_CTRL,ITW_7H_BG_BLUE_CTRL] apply {_display displayCtrl _x};
    private _hBgRedCtrls = [ITW_0H_BG_RED_CTRL,ITW_1H_BG_RED_CTRL,ITW_2H_BG_RED_CTRL,ITW_3H_BG_RED_CTRL,ITW_4H_BG_RED_CTRL,ITW_5H_BG_RED_CTRL,ITW_6H_BG_RED_CTRL,ITW_7H_BG_RED_CTRL] apply {_display displayCtrl _x};
    private _onSide = true;
    
    switch (ITW_ParamObjectivesFlagGui) do {
        case 1: {
            // gui on 
            {_x ctrlShow false} count _hBlueCtrls;
            {_x ctrlShow false} count _hRedCtrls;
            {_x ctrlShow false} count _hBgBlueCtrls;
            {_x ctrlShow false} count _hBgRedCtrls;
            {_x ctrlShow false} count _flagCtrls;
        };
        case 2: {
            // gui on left
            {_x ctrlShow false} count _hBlueCtrls;
            {_x ctrlShow false} count _hRedCtrls;
            {_x ctrlShow false} count _hBgBlueCtrls;
            {_x ctrlShow false} count _hBgRedCtrls;
            {_x ctrlShow false} count _flagCtrls;
            
            private _GUI_GRID_WAbs = ((safezoneW / safezoneH) min 1.2);
            private _GUI_GRID_HAbs = (_GUI_GRID_WAbs / 1.2);
            private _GUI_GRID_W =    (_GUI_GRID_WAbs / 40);
            private _GUI_GRID_H =    (_GUI_GRID_HAbs / 25);
            private _FLAG_WIDTH =    (_GUI_GRID_W * 0.25);
            private _FLAG_HEIGHT =   (_GUI_GRID_H * 3);
            private _FLAG_SPACE =    (_GUI_GRID_W * 0.15);
            private _FLAG_VSPACE =   (_GUI_GRID_H * 0.45);
            
            private _FLAG_X0 =       (safezoneX + _FLAG_SPACE);
            private _FLAG_X1 =       (_FLAG_X0 + _FLAG_WIDTH + _FLAG_SPACE);
            private _FLAG_X2 =       (_FLAG_X0 + 2*(_FLAG_WIDTH + _FLAG_SPACE));
            private _FLAG_X3 =       (_FLAG_X0 + 3*(_FLAG_WIDTH + _FLAG_SPACE));
            private _FLAG_Y0 =       (safezoneY + (safezoneH*0.25));
            private _FLAG_Y1 =       (_FLAG_Y0 - _FLAG_HEIGHT - _FLAG_VSPACE);
            private _TEXT_W  =       (_GUI_GRID_W);
            private _TEXT_H  =       (_GUI_GRID_H);
            private _TEXT_X0 =       (_FLAG_X0 - _FLAG_WIDTH);
            private _TEXT_X1 =       (_FLAG_X1 - _FLAG_WIDTH);
            private _TEXT_X2 =       (_FLAG_X2 - _FLAG_WIDTH); 
            private _TEXT_X3 =       (_FLAG_X3 - _FLAG_WIDTH);
            private _TEXT_Y0 =       (_FLAG_Y0 + _FLAG_HEIGHT - _TEXT_H/3);
            private _TEXT_Y1 =       (_FLAG_Y1 + _FLAG_HEIGHT - _TEXT_H/3);

            private _ctrl = _blueCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_X2 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_X3 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_X2 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_X3 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _redCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_X2 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_X3 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_X2 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_X3 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _textCtrls#0;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_TEXT_Y0,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#1;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_TEXT_Y0,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#2;
            _ctrl ctrlSetPosition [_TEXT_X2 ,_TEXT_Y0,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#3;
            _ctrl ctrlSetPosition [_TEXT_X3 ,_TEXT_Y0,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#4;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_TEXT_Y1,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#5;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_TEXT_Y1,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#6;
            _ctrl ctrlSetPosition [_TEXT_X2 ,_TEXT_Y1,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#7;
            _ctrl ctrlSetPosition [_TEXT_X3 ,_TEXT_Y1,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            
            _ctrl = _lockCtrls#0;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y0,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#1;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y0,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#2;
            _ctrl ctrlSetPosition [_TEXT_X2 ,_FLAG_Y0,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#3;
            _ctrl ctrlSetPosition [_TEXT_X3 ,_FLAG_Y0,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#4;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y1,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#5;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y1,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#6;
            _ctrl ctrlSetPosition [_TEXT_X2 ,_FLAG_Y1,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _lockCtrls#7;
            _ctrl ctrlSetPosition [_TEXT_X3 ,_FLAG_Y1,_TEXT_W,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
        };
        case 3: {
            // gui on top
            {_x ctrlShow false} count _blueCtrls;
            {_x ctrlShow false} count _redCtrls;
            
            _blueCtrls = _hBlueCtrls;
            _redCtrls  = _hRedCtrls;
            _onSide = false;
            
            private _maxObjPerZone = selectMax (ITW_Zones apply {count _x});
            
            private _GUI_GRID_WAbs = ((safezoneW / safezoneH) min 1.2);
            private _GUI_GRID_HAbs = (_GUI_GRID_WAbs / 1.2);
            private _GUI_GRID_W =    (_GUI_GRID_WAbs / 40);
            private _GUI_GRID_H =    (_GUI_GRID_HAbs / 25);
            private _FLAG_HEIGHT =   (_GUI_GRID_W * (switch (_maxObjPerZone) do {case 1:{1.3}; case 2:{0.6}; default {0.5}}));
            private _FLAG_WIDTH =    (_GUI_GRID_H * 3);
            private _FLAG_SPACE =    (_GUI_GRID_W * 0.15);
            private _FLAG_HSPACE =   (_GUI_GRID_H * 0.45);
            private _GUI_X_CENTER =  (safezoneX + (safeZoneW/2));
            private _FACTION_FLAG_W =(_GUI_GRID_W * 2);
            private _FACTION_FLAG_H =(_GUI_GRID_H * 1.3);
            private _LOCKED_Y_OFFSET=(_GUI_GRID_H * 0.05);
            private _FACTION_FLAG_PX=(_GUI_X_CENTER - _FACTION_FLAG_W - _FLAG_SPACE);
            private _FLAG_P_X0 =     (_FACTION_FLAG_PX - _FLAG_WIDTH - _FLAG_SPACE);
            private _FLAG_P_X1 =     (_FLAG_P_X0 - _FLAG_WIDTH - _FLAG_HSPACE);
            private _FACTION_FLAG_Y =(safezoneY);
            
            private _FACTION_FLAG_EX=(_GUI_X_CENTER + _FLAG_SPACE);
            private _FLAG_E_X0 =     (_FACTION_FLAG_EX +_FACTION_FLAG_W + _FLAG_SPACE);
            private _FLAG_E_X1 =     (_FLAG_E_X0 + _FLAG_WIDTH + _FLAG_HSPACE);
            
            private _FLAG_Y0 =       (safezoneY + _FLAG_SPACE);
            private _FLAG_Y1 =       (_FLAG_Y0 + _FLAG_HEIGHT + _FLAG_SPACE);
            private _FLAG_Y2 =       (_FLAG_Y0 + 2*(_FLAG_HEIGHT + _FLAG_SPACE));
            private _FLAG_Y3 =       (_FLAG_Y0 + 3*(_FLAG_HEIGHT + _FLAG_SPACE));
            private _TEXT_W  =       (_GUI_GRID_W * 0.5);
            private _TEXT_H  =       (_GUI_GRID_H * 0.7);
            private _TEXT_X0 =       (_FLAG_P_X0 - (_GUI_GRID_W * 0.6));
            private _TEXT_X1 =       (_FLAG_P_X1 - (_GUI_GRID_W * 0.6));
            private _TEXT_Y0 =       (_FLAG_Y0);
            private _TEXT_Y1 =       (_FLAG_Y1);
            private _TEXT_Y2 =       (_FLAG_Y2); 
            private _TEXT_Y3 =       (_FLAG_Y3);
            private _TEXT_Y_OFFSET=(_GUI_GRID_H * 0.1);

            private _ctrl = _blueCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _blueCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _hBgBlueCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgBlueCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _redCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _redCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _hBgRedCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#1;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#2;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#3;
            _ctrl ctrlSetPosition [_FLAG_E_X0 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#4;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y0,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#5;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y1,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#6;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y2,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl = _hBgRedCtrls#7;
            _ctrl ctrlSetPosition [_FLAG_E_X1 ,_FLAG_Y3,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            
            _ctrl = _textCtrls#0;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y0-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#1;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y1-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#2;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y2-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#3;
            _ctrl ctrlSetPosition [_TEXT_X0 ,_FLAG_Y3-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#4;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y0-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#5;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y1-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#6;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y2-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            _ctrl = _textCtrls#7;
            _ctrl ctrlSetPosition [_TEXT_X1 ,_FLAG_Y3-_TEXT_Y_OFFSET,_TEXT_W,_TEXT_H];
            _ctrl ctrlCommit 0;
            
            _ctrl = _lockCtrls#0;
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y0-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;    
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#1;  
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y1-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#2;  
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y2-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#3;  
            _ctrl ctrlSetPosition [_FLAG_P_X0 ,_FLAG_Y3-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#4;  
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y0-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#5;  
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y1-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#6;  
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y2-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
            _ctrl = _lockCtrls#7;  
            _ctrl ctrlSetPosition [_FLAG_P_X1 ,_FLAG_Y3-_LOCKED_Y_OFFSET,_FLAG_WIDTH,_FLAG_HEIGHT];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText "L O C K E D";
        
            _ctrl = _display displayCtrl ITW_BLUE_FACTION_FLAG;
            _ctrl ctrlSetPosition [_FACTION_FLAG_PX ,_FACTION_FLAG_Y,_FACTION_FLAG_W,_FACTION_FLAG_H];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText ITW_PlayerFlag; 
            _ctrl = _display displayCtrl ITW_RED_FACTION_FLAG;
            _ctrl ctrlSetPosition [_FACTION_FLAG_EX ,_FACTION_FLAG_Y,_FACTION_FLAG_W,_FACTION_FLAG_H];
            _ctrl ctrlCommit 0;
            _ctrl ctrlSetText ITW_EnemyFlag; 
        };
    };
    
    // turn everything off until it's ready to run
    {_x ctrlShow false} count _blueCtrls;
    {_x ctrlShow false} count _redCtrls;
    {_x ctrlShow false} count _hBlueCtrls;
    {_x ctrlShow false} count _hRedCtrls;
    {_x ctrlShow false} count _hBgBlueCtrls;
    {_x ctrlShow false} count _hBgRedCtrls;
    {_x ctrlShow false} count _textCtrls;
    {_x ctrlShow false} count _lockCtrls;
    {_x ctrlShow false} count _flagCtrls;
    
    waitUntil {sleep 1;ITW_ZoneIndex > 0};
        
    private _show = ITW_ParamObjectivesFlagGui > 0;
    
    private _flags = [];
    private _garagePads = []; // in same order as flags
    private _prevIndex = -1;
    while {!ITW_GameOver} do {
        sleep FLAG_SLEEP;
        if (ITW_ZoneIndex != _prevIndex) then {
            private _zones = ITW_Zones#ITW_ZoneIndex;
            _flags = _zones apply {[ITW_Objectives#_x#ITW_OBJ_FLAG,_x,false]}; // flag object, obj index, isFaded
            if (isNil "_flags" || {_flags isEqualTo []}) then {continue};
            private _names = _zones apply {ITW_Objectives#_x#ITW_OBJ_NAME};
            if (isNil "_names" || {_names isEqualTo []}) then {continue};
            // hide the controls then show the used ones
            {_x ctrlShow false;_x ctrlSetFade 0;_x ctrlCommit 0} count _blueCtrls;
            {_x ctrlShow false;_x ctrlSetFade 0;_x ctrlCommit 0} count _redCtrls;
            {_x ctrlShow false;_x ctrlCommit 0} count _hBgBlueCtrls;
            {_x ctrlShow false;_x ctrlCommit 0} count _hBgRedCtrls;
            {_x ctrlShow false} count _textCtrls;
            {_x ctrlShow false} count _lockCtrls;
            {
                private _name = _x;
                if (_forEachIndex > 7) exitWith {};
                private _blueCtrl = _blueCtrls#_forEachIndex;
                private _textCtrl = _textCtrls#_forEachIndex;
                _textCtrl ctrlSetText (_name select [0,1]);
                _textCtrl ctrlShow _show;              
            } forEach _names;
            _garagePads = _flags apply {GARAGE_MARKER_NAME(_x#0)};
            _prevIndex = ITW_ZoneIndex;
        };
        {
            _x params ["_flag","_objIdx","_ctrlFaded"];
            if (_forEachIndex > 7) exitWith {};
            
            private _lockCtrl = _lockCtrls#_forEachIndex;
            if (_flag getVariable ["ITW_FlagUnlockTime",0] > 0) then {
                // flag is locked
                _lockCtrl ctrlShow true;
                continue;
            };
            _lockCtrl ctrlShow _ctrlFaded;
            
            private _blueCtrl = _blueCtrls#_forEachIndex;
            private _redCtrl = _redCtrls#_forEachIndex;
            private _textCtrl = _textCtrls#_forEachIndex;
            private _flagIsPlayer = _flag getVariable "ITW_FlagIsPlayer";
            if (! isNil "_flagIsPlayer") then {
                private _phase = _flag getVariable ["ITW_FlagPhase",1];
                _flag setFlagAnimationPhase _phase;
                if (_onSide) then {
                    if (ITW_defendPhaseObjIdx > 0 && {!ITW_defendRunning || {ITW_defendPhaseObjIdx != _objIdx}}) then {
                        _blueCtrl progressSetPosition _phase;
                        _blueCtrl ctrlShow _show;
                        _redCtrl progressSetPosition _phase;
                        _redCtrl ctrlShow _show;
                        if (!_ctrlFaded) then {
                            _blueCtrl ctrlSetFade (if (_flagIsPlayer) then {0.7} else {0.9});
                            _redCtrl  ctrlSetFade  (if (_flagIsPlayer) then {0.9} else {0.7});
                            _blueCtrl ctrlCommit 0;
                            _redCtrl  ctrlCommit 0;
                            _x set [2,true];
                        };
                    } else {
                        if (_ctrlFaded) then {
                            _blueCtrl ctrlSetFade 0;
                            _redCtrl  ctrlSetFade 0;
                            _blueCtrl ctrlCommit 0;
                            _redCtrl  ctrlCommit 0;
                            _x set [2,false];
                        };
                        if (_flagIsPlayer) then {
                            _blueCtrl progressSetPosition _phase;
                            _redCtrl ctrlShow false;
                            _blueCtrl ctrlShow _show;
                            if (_phase == 1) then {_textCtrl ctrlSetTextColor [0,0,1,1]};
                        } else {
                            _redCtrl progressSetPosition _phase;
                            _redCtrl ctrlShow _show;
                            _blueCtrl ctrlShow false;
                            if (_phase == 1) then {_textCtrl ctrlSetTextColor [1,0,0,1]};
                        };
                    };
                } else {
                    // gui to top of screen
                    _redCtrl ctrlShow _show;
                    _blueCtrl ctrlShow _show;
                    {_x ctrlShow true} count _flagCtrls;
                    (_hBgBlueCtrls#_forEachIndex) ctrlShow _show;
                    (_hBgRedCtrls#_forEachIndex) ctrlShow _show;
                    if (ITW_defendPhaseObjIdx > 0 && {!ITW_defendRunning || {ITW_defendPhaseObjIdx != _objIdx}}) then {
                        if (!_ctrlFaded) then {
                            _redCtrl  ctrlSetFade 0.7;
                            _redCtrl  ctrlCommit 0;
                            _x set [2,true];
                        };
                    } else {
                        if (_ctrlFaded) then {
                            _redCtrl  ctrlSetFade 0;
                            _redCtrl  ctrlCommit 0;
                            _x set [2,false];
                        };
                        if (_flagIsPlayer) then {
                            _blueCtrl progressSetPosition (1-_phase);
                            _redCtrl progressSetPosition 0;
                            if (_phase == 1) then {_textCtrl ctrlSetTextColor [0,0,1,1]};
                        } else {
                            _redCtrl progressSetPosition _phase;
                            _blueCtrl progressSetPosition 1;
                            if (_phase == 1) then {_textCtrl ctrlSetTextColor [1,0,0,1]};
                        };
                    };
                };
                _garagePads#_forEachIndex setMarkerColorLocal (if (_flagIsPlayer && {_phase == 1}) then {"ColorBlue"} else {"ColorGrey"});
            };
        } forEach _flags;
    };
};

ITW_ObjRedOut = {
    // spawn on clients
    scriptName "ITW_ObjRedOut";
    if (!hasInterface) exitWith {};
    private _delay = ITW_ParamRedOut;
    if (_delay > 1000) exitWith {}; // param set to never show red
    private _handle = -1;
    private _timeout = -1;
    private _hinting = false;
    while {!ITW_GameOver} do {
        sleep 2;
        // Exit Area Warning & Damage
        private _pos = getPosATL player;
        private _nearestObj = [_pos,ITW_OWNER_UNDEFINDED,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest;
        if (_nearestObj#ITW_OBJ_OWNER == ITW_OWNER_ENEMY && {_nearestObj#ITW_OBJ_POS distanceSqr _pos < ITW_ZoneKeepOutSqr}) then {
            _hinting = true;
            if (_timeout < 0) then {
                _timeout = time + _delay;
                hint localize "STR_ITW_OBJ_TooNearEnemyBase";
            } else {
                hintSilent localize "STR_ITW_OBJ_TooNearEnemyBase";
            };
            if (time >= _timeout && {_handle < 0}) then {
                _handle = ppEffectCreate ["colorCorrections", 1501];
                _handle ppEffectEnable true;
                _handle ppEffectAdjust [
                    1,   // brightness,
                    1,   // contrast,
                    0,   // offset,
                    [1,0,0,0.30], // [blendR, blendG, blendB, blendA],
                    [1,1,1,0.63], // [colorizeR, colorizeG, colorizeB, colorizeA],
                    [0.2,0.2,1,0] // [weightR, weightG, weightB, 0],
                ];
                _handle ppEffectCommit 1;
            };
        } else {
            _timeout = -1;
            if (_handle >= 0) then {
                ppEffectDestroy _handle;
                _handle = -1;
            };
            if (_hinting) then {hintSilent "";_hinting = false};
        };
        if (LV_PAUSE) then {waitUntil {sleep 1;!LV_PAUSE}};
    };
    if (_handle >= 0) then {
        ppEffectDestroy _handle;
    };
};

ITW_ObjCreateNearestBasesMap = {
    // call on server 
    waitUntil {sleep 1;(count ITW_Bases == count ITW_Objectives)};
    private _ready = [false];
    _ready spawn {
        scriptName "ITW_ObjCreateNearestBasesMap";
        private _ready = _this;
        private _agent = objNull;
        private _car = objNull;
        private _agent2 = objNull;
        private _boat = objNull;
        private _hashMap = createHashMap; // hashKey is [objId,objId] with the 1st one being the lower number
        private _slowSleep = 0.75;
        private _DEBUG = false;
        if (_DEBUG) then {diag_log ["ITW_ObjCreateNearestBasesMap","STARTED"]};
            
        private _fnCreateAgent = {
            // create agent for calculating path on land
            // _agent, _agent2, _car, _boat are local to the caller
            private _basePt = ITW_Bases#0#ITW_BASE_A_SPAWN;
            //private _spawnPt = _basePt findEmptyPosition [0,200,"C_Quadbike_01_F"];-- findEmptyPosition causes frame drop
            private _spawnPt = [_basePt,0,200,6.5,0,1.2,0,[],[[0],[0]]] call BIS_fnc_findSafePos;
            if (_spawnPt isEqualTo []) then {_spawnPt = _basePt};
            _car = "B_MRAP_01_F" createVehicle _spawnPt;
            _car allowDamage false;
            _agent = createAgent ["C_man_1", _spawnPt, [], 0, "NONE"];
            _agent allowDamage false;
            hideObjectGlobal _car;
            hideObjectGlobal _agent;
            while {vehicle _agent == _agent} do {
                _agent moveInDriver _car;
                sleep 0.5;
            };
            _agent setBehaviour "CARELESS";            
            _agent addEventHandler ["PathCalculated", {
                params ["_agent", "_path"];
                if (!isNil "ITW_PathDist") exitWith {};
                private _prevPos = [0,0,0];
                private _dist = 0;
                {
                    if (_forEachIndex > 0) then {
                        _dist = _dist + (_x distance2D _prevPos);
                    };
                    _prevPos = _x;
                } forEach _path;
                if (_dist == 0) then {_dist = 1e10};
                ITW_PathDist = _dist;
            }];
            
            waitUntil {! isNil "VEHICLE_ARRAYS_COMPLETE"};
            private _seaIsViable = !(va_pShipClassesTransport isEqualTo [] && va_eShipClassesTransport isEqualTo [] && va_cShipClassesTransport isEqualTo []);
            if (_seaIsViable) then {
                _boat = "B_Boat_Transport_01_F" createVehicle [0,0,0];
                _boat allowDamage false;
                _agent2 = createAgent ["C_man_1", _spawnPt, [], 0, "NONE"];
                _agent2 allowDamage false;
                hideObjectGlobal _boat;
                hideObjectGlobal _agent2;
                while {vehicle _agent2 == _agent2} do {
                    _agent2 moveInDriver _boat;
                    sleep 0.5;
                };
                _agent2 setBehaviour "CARELESS";
                _agent2 addEventHandler ["PathCalculated", {
                    params ["_agent", "_path"];
                    if (!isNil "ITW_PathDist") exitWith {};
                    private _prevPos = [0,0,0];
                    private _dist = 0;
                    {
                        if (_forEachIndex > 0) then {
                            _dist = _dist + (_x distance2D _prevPos);
                        };
                        _prevPos = _x;
                    } forEach _path;
                    if (_dist == 0) then {_dist = 1e10};
                    ITW_PathDist = _dist;
                }];
            };
        };
        
        private _fnAddNearestObjBases = {
            params ["_zoneId","_objIds","_agent","_car","_agent2","_boat","_hashMap","_fast"];
            if (_DEBUG) then {diag_log ["NearestBasesMap: Adding Bases","zone",_zoneId,"objectives",_objIds,"fast",_fast]}; 
            
            private _fnLandSeaDist = {
                params ["_objId1","_objId2","_agent","_car","_agent2","_boat","_hashMap"];
                
                
                if (_objId1 > _objId2) then {
                    private _temp = _objId1;
                    _objId1 = _objId2;
                    _objId2 = _temp;
                };
                private _hashKey = [_objId1,_objId2];
                private _landSeaDist = _hashMap get _hashKey;
                if (isNil "_landSeaDist") then {
                    private _pt1 = ITW_Objectives#_objId1#ITW_OBJ_POS;
                    private _pt2 = ITW_Objectives#_objId2#ITW_OBJ_POS;                    
                    private _objId = if (_agent distance2D _pt1 > (_agent distance2D _pt2)) then {_objId1} else {_objId2};
                    private _obj = ITW_Objectives#_objId;
                    
                    // Land distance
                    private _pt = _obj#ITW_OBJ_V_SPAWN;
                    if (_pt isEqualTo []) then {
                        private _base = ITW_Bases#(_obj#ITW_OBJ_INDEX);
                        _pt = _base#ITW_BASE_A_SPAWN;
                    };
                    private _landDist = 1e10;
                    ITW_PathDist = nil; // distance, point path-ed to
                    _agent setDestination [_pt, "LEADER PLANNED", true];
                    private _timeout = time + 2.5;
                    waitUntil {time > _timeout || {!isNil "ITW_PathDist"}}; 
                    doStop _agent;
                    _car engineOn false;
                    if !(isNil "ITW_PathDist") then {
                        _landDist = ITW_PathDist;
                    };    
                    
                    private _seaDist = 1e10;
                    if (!isNull _boat) then {
                        // Sea distance
                        private _seaPts1 = ITW_SeaPoints#_objId1;
                        private _seaPts2 = ITW_SeaPoints#_objId2;
                        if !(_seaPts1 isEqualTo [] || {_seaPts2 isEqualTo []}) then {
                            _pt = if (_agent2 distance2D (_seaPts1#0) > (_agent2 distance2D (_seaPts2#0))) then {_seaPts1#0} else {_seaPts2#0};
                            ITW_PathDist = nil; // distance, point path-ed to
                            _agent2 setDestination [_pt, "LEADER PLANNED", true];
                            private _timeout = time + 2.5;
                            waitUntil {time > _timeout || {!isNil "ITW_PathDist"}}; 
                            doStop _agent2;
                            _boat engineOn false;
                            if !(isNil "ITW_PathDist") then {
                                _seaDist = ITW_PathDist;
                            }; 
                        };
                    };
                    _landSeaDist = [_landDist,_seaDist];
                    _hashMap set [_hashKey,_landSeaDist];
                };
                _landSeaDist
            };
            
            private _baseFirst = 0;
            private _baseLast = (count ITW_Bases)-1;
            private _friendlyObjIds = [];
            private _enemyObjIds = [];
            private _nearestData = [];
            {
                switch (true) do {
                    case (_x#ITW_OBJ_ZONEID > _zoneId): {_enemyObjIds    pushBack _forEachIndex};
                    case (_x#ITW_OBJ_ZONEID < _zoneId): {_friendlyObjIds pushBack _forEachIndex};
                };
            } forEach ITW_Objectives;
            
            private _closestCount = 5; // how many closest bases will be do land routing for
            private _loopCnt = 1;
            
            {
                private _objectiveId = _x;
                private _objective = ITW_Objectives#_objectiveId;
                private _objectivePt = _objective#ITW_OBJ_POS;
                private _distAirF = 1e10;
                private _distAirE = 1e10;
                private _distLandF = 1e10;
                private _distLandE = 1e10;
                private _distSeaF = 1e10;
                private _distSeaE = 1e10;
                private _nearestAirF  = _baseFirst;
                private _nearestLandF = [];
                private _nearestSeaF = [];
                private _nearestAirE  = _baseLast;
                private _nearestLandE = [];
                private _nearestSeaE = [];
                private _spawnPt = _objective#ITW_OBJ_V_SPAWN;
                if (_spawnPt isEqualTo []) then {
                    private _base = ITW_Bases#(_objective#ITW_OBJ_INDEX);
                    _spawnPt = _base#ITW_BASE_A_SPAWN;
                };
                _spawnPt set [2,0.5];
                _car setPosATL _spawnPt;
                _car setVectorUp surfaceNormal getPosASL _car;
                while {vehicle _agent == _agent} do {
                    _agent moveInDriver _car;
                    sleep 0.2;
                };
                
                if (!isNull _boat) then {
                    private _seaPts = ITW_SeaPoints#_objectiveId;
                    if !(_seaPts isEqualTo []) then {
                        _boat setPosATL _seaPts#0;
                        while {vehicle _agent2 == _agent2} do {
                            _agent2 moveInDriver _boat;
                            sleep 0.2;
                        };
                    };
                };
                sleep 0.1;
                
                // _distList is array of [distance,objId] so it can be sorted by distance
                private _distList = _friendlyObjIds apply {
                    private _objId = _x;
                    private _pt1 = ITW_Objectives#_objectiveId#ITW_OBJ_POS;
                    private _pt2 = ITW_Objectives#_objId#ITW_OBJ_POS;
                    private _airDist = _pt1 distance2D _pt2;
                    [_airDist,_objId]
                };
                _distList sort true;
                _distAirF = _distList#0#0;
                _nearestAirF = _distList#0#1;
                private _closestFriendlyObjIds = _distList select [0,_closestCount];
              
                _distList = _enemyObjIds apply {
                    private _objId = _x;
                    private _pt1 = ITW_Objectives#_objectiveId#ITW_OBJ_POS;
                    private _pt2 = ITW_Objectives#_objId#ITW_OBJ_POS;
                    private _airDist = _pt1 distance2D _pt2;
                    [_airDist,_objId]
                };
                _distList sort true;
                _distAirE = _distList#0#0;
                _nearestAirE = _distList#0#1;
                if (isNil "_nearestAirE") then {_nearestAirE = _baseLast}; // last zone has enemy coming from OutToSea (the last base)
                private _closestEnemyObjIds = _distList select [0,_closestCount];
                private _maxLoopCnt = count _objIds * (count _closestFriendlyObjIds + count _closestEnemyObjIds);
                {
                    if (_fast && {isNil "ITW_GameReady"}) then {["itw",[format ["%1 (%2/%3)",localize "STR_ITW_OBJ_CalcAtkVectors",_loopCnt,_maxLoopCnt],"BLACK OUT",0.001]] remoteExec ["cutText",0,false];_loopCnt = _loopCnt + 1};
                    private _objId = _x#1;
                    [_objectiveId,_objId,_agent,_car,_agent2,_boat,_hashMap] call _fnLandSeaDist params ["_dLand","_dSea"];
                    if (_dLand < _distLandF) then {
                        _distLandF = _dLand;
                        _nearestLandF = _objId;
                    };
                    if (_dSea < _distSeaF) then {
                        _distSeaF = _dSea;
                        _nearestSeaF = _objId;
                    };
                    if (!_fast) then {sleep _slowSleep};
                } count _closestFriendlyObjIds;
                if (_DEBUG) then {diag_log ["NearestBasesMap: FLandX",_distLandF,"FAir",_distAirF,_nearestLandF,_nearestAirF,_objectivePt]};  
                {
                    if (_fast && {isNil "ITW_GameReady"}) then {["itw",[format ["%1 (%2/%3)",localize "STR_ITW_OBJ_CalcAtkVectors",_loopCnt,_maxLoopCnt],"BLACK OUT",0.001]] remoteExec ["cutText",0,false];_loopCnt = _loopCnt + 1};
                    private _objId = _x#1;
                    [_objectiveId,_objId,_agent,_car,_agent2,_boat,_hashMap] call _fnLandSeaDist params ["_dLand","_dSea"];
                    if (_DEBUG) then {diag_log ["NearestBasesMap: EX",_dLand,_dSea,_objectiveId,_objId]};
                    if (_dLand < _distLandE) then {
                        _distLandE = _dLand;
                        _nearestLandE = _objId;
                    };
                    if (_dSea < _distSeaE) then {
                        _distSeaE = _dSea;
                        _nearestSeaE = _objId;
                    };
                    if (!_fast) then {sleep _slowSleep};
                } count _closestEnemyObjIds;
                if (_DEBUG) then {diag_log ["NearestBasesMap: ELandX",_distLandE,"EAir",_distAirE,"ESea",_distSeaE,_nearestLandE,_nearestAirE,_objectivePt]};

                // if no land paths found, just leave from closest base
                private _landAttackPossible = [true,true,true,true];
                if (_nearestLandF isEqualTo []) then {_nearestLandF = _nearestAirF; _landAttackPossible set [ATTACK_FRIENDLY,false]}; 
                if (_nearestLandE isEqualTo []) then {_nearestLandE = _nearestAirE; _landAttackPossible set [ATTACK_ENEMY,false]};
                if (_distLandF > 7000) then {_landAttackPossible set [ATTACK_FRIENDLY,false]};
                if (_distLandE > 7000) then {_landAttackPossible set [ATTACK_ENEMY,false]};
                if (_nearestSeaF isEqualTo []) then {_nearestSeaF = _nearestAirF; _landAttackPossible set [ATTACK_SEA_FRIENDLY,false]}; 
                if (_nearestSeaE isEqualTo []) then {_nearestSeaE = _nearestAirE; _landAttackPossible set [ATTACK_SEA_ENEMY,false]};
                
                _nearestData pushBack [_objective,[ITW_Objectives#_nearestLandF#ITW_OBJ_INDEX,
                                                   ITW_Objectives#_nearestAirF #ITW_OBJ_INDEX,
                                                   ITW_Objectives#_nearestLandE#ITW_OBJ_INDEX,
                                                   ITW_Objectives#_nearestAirE #ITW_OBJ_INDEX,
                                                   _nearestSeaF,
                                                   _nearestSeaE
                                                  ],_landAttackPossible];
                if (_DEBUG) then {diag_log ["NearestBasesMap: ObjUpdate",_objectiveId,_nearestData#-1#1]};              
                if (!_fast) then {sleep _slowSleep};
            } count _objIds;
            
            // on the final objective, place 
            // update the objectives all at once in case the player saves during the calculation and only some of the data is done
            {
                _x params ["_obj","_data","_landAttackPossible"];
                _obj set [ITW_OBJ_ATTACKS,_data];
                _obj set [ITW_OBJ_ATK_AVAIL,_landAttackPossible];
            } count _nearestData;
        };
        
        {
            private _zoneNum = _forEachIndex;
            private _fast = _zoneNum <= ITW_ZoneIndex; // run as fast as possible to calculate the current zone, others can be slower
            if (_DEBUG) then {diag_log ["NearestBasesMap","_zoneNum",_zoneNum,"begun",ITW_ZoneIndex,"fast",_fast]};
            if (_zoneNum < ITW_ZoneIndex) then {continue};
            private _objIds = _x;
            private _obj = ITW_Objectives#(_objIds#0); // just check the first objective to see if it's already been done
            if (_obj#ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS) then {
                if (isNull _agent) then { call _fnCreateAgent};
                if (!_fast) then {sleep _slowSleep};
                [_forEachIndex,_objIds,_agent,_car,_agent2,_boat,_hashMap,_fast] call _fnAddNearestObjBases;
                publicVariable "ITW_Objectives";
                diag_log format ["ITW: NearestBasesMap: zone %1 completed (obj: %2)",_forEachIndex,_objIds];
                if (_zoneNum != 0) then {["attackVector"] call ITW_SaveGame}; 
            }; 
            _ready set [0,true]; // trigger that we are ready to work with the current zone
        } forEach ITW_Zones;
        
        if (_DEBUG) then {diag_log ["NearestBasesMap","COMPLETED"]};
        _car deleteVehicleCrew _agent;
        deleteVehicle _car;
        deleteVehicle _agent; // in case agent got out of car
        if (!isNull _boat) then {
            _boat deleteVehicleCrew _agent2;
            deleteVehicle _boat;
            deleteVehicle _agent2; // in case agent got out of boat
        };
    };
    
    waitUntil {sleep 1;_ready#0};
};

ITW_ObjGetOutToSeaPos = {
    private _isFriendly = _this;
    if (isNil "ITW_OutToSeaPos") then {
        private _lastObjIdx = ITW_Zones#-1#-1;
        private _firstObjPos = ITW_Objectives#0#ITW_OBJ_POS;
        private _lastObjPos = ITW_Objectives#_lastObjIdx#ITW_OBJ_POS;
        ITW_OutToSeaPos = [_firstObjPos getPos [3000,_lastObjPos getDir _firstObjPos],_lastObjPos getPos [3000,_firstObjPos getDir _lastObjPos]];
    };
    ITW_OutToSeaPos#(if (_isFriendly) then {0} else {1})
};

ITW_ObjSetOutToSeaPos = {
    params ["_isFriendly","_pos"];
    
    if (isNil "ITW_OutToSeaPos") then {false call ITW_ObjGetOutToSeaPos};
    ITW_OutToSeaPos set [if (_isFriendly) then {0} else {1},_pos];
};

ITW_ObjGetAttackVectorFromPos = {
    // given an objective, get which base it should be attacked from
    params ["_obj","_isFriendly","_isLand"];
    private _which = if (_isFriendly) then {if (_isLand) then {ITW_ATTACK_LAND_F} else {ITW_ATTACK_AIR_F}}
                                      else {if (_isLand) then {ITW_ATTACK_LAND_E} else {ITW_ATTACK_AIR_E}};
    WAIT_FOR_BASE_MAP("ITW_ObjGetAttackVectorBase",_obj);
    private _fromObjIdx = _obj#ITW_OBJ_ATTACKS#_which;
    private "_pos";
    if (_fromObjIdx >= 0) then {
        _pos = ITW_Bases#_fromObjIdx#ITW_BASE_POS
    } else {
        _pos = false call ITW_ObjGetOutToSeaPos;
    };
    _pos
};

ITW_ObjLandAtkAdjust = {
    // params is array of [toObjIdx,fromObjIdx]  fromObjIdx == -1 if no land route
    {
        _x params ["_toObjIdx","_fromObjIdx"];
        private _obj = ITW_Objectives#_toObjIdx;
        _obj#ITW_OBJ_ATTACKS  set [ITW_ATTACK_LAND_F,if (_fromObjIdx >= 0) then {_fromObjIdx} else {_obj#ITW_OBJ_ATTACKS#ITW_ATTACK_AIR_F}];
        _obj#ITW_OBJ_ATK_AVAIL set [0,_fromObjIdx >= 0];
    } forEach _this;
    publicVariable "ITW_Objectives";
};
            
ITW_ObjShowAttackVectors = {
    if (!canSuspend) exitWith {0 spawn ITW_ObjShowAttackVectors};
    scriptName "ITW_ObjShowAttackVectors";
    // spawn from the debug console
    BM_PT1 = [0,0,0];
    BM_PT2 = [0,0,0];
    BM_PT3 = [0,0,0];
    BM_PT4 = [0,0,0];
    BM_OBJPT = [0,0,0];
    BM_SHOW = FALSE;
    private _mBase = createMarkerLocal ["ITW_MkrBaseShow",[0,0,0]];
    private _mVeh  = createMarkerLocal ["ITW_MkrVehShow",[0,0,0]];
    _mBase setMarkerShapeLocal "ICON";
    _mBase setMarkerTypeLocal "loc_frame";
    _mVeh setMarkerShapeLocal "ICON";
    _mVeh setMarkerTypeLocal "loc_car";
    (finddisplay 49) closeDisplay 1;
    openMap true;
    private _mapCtrl = (findDisplay 12 displayCtrl 51);
    private _ehID = _mapCtrl ctrlAddEventHandler ["Draw", {
        if (BM_SHOW) then {
            private _map = _this#0;
            _map drawLine [BM_PT1,BM_OBJPT,[0,0,1,1]];
            _map drawLine [BM_PT2,BM_OBJPT,[0,1,1,1]];
            _map drawLine [BM_PT3,BM_OBJPT,[1,0,0,1]];
            _map drawLine [BM_PT4,BM_OBJPT,[1,1,0,1]];
        };
    }];
    
    private _objIndexes = [];
    {_objIndexes = _objIndexes + _x} count ITW_Zones;
    private _index = 1;
    private _maxIndex = count ITW_Objectives - 1;
    while {true} do {
        if (_index < 1) then {_index = 1};
        if (_index > _maxIndex) then {_index = _maxIndex};
        private _objIndex = _objIndexes#_index;
        private _obj = ITW_Objectives#_objIndex;
        BM_OBJPT = _obj#0;
        diag_log ["SHOWING OBJECTIVE",_objIndex,_obj#8];
        BM_SHOW = false;
        BM_PT1 = ([_obj,true,true]   call ITW_ObjGetAttackVectorBasePos);
        BM_PT2 = ([_obj,true,false]  call ITW_ObjGetAttackVectorBasePos);
        BM_PT3 = ([_obj,false,true]  call ITW_ObjGetAttackVectorBasePos);
        BM_PT4 = ([_obj,false,false] call ITW_ObjGetAttackVectorBasePos);         
        BM_SHOW = true;
        hint "Press move forward key for next objective, move backward for previous. Close map to quit. Red & Blue are land"; // this is debug, don't need to localize
        // now show base and vehicle spawn locations
        _mBase setMarkerPosLocal (ITW_Bases#(_obj#ITW_OBJ_INDEX)#ITW_BASE_POS);
        private _vehPt = _obj#ITW_OBJ_V_SPAWN;
        if (isNil "_vehPt" || {_vehPt isEqualTo []}) then {
            _mVeh setMarkerAlphaLocal 0;
        } else {
            _mVeh setMarkerAlphaLocal 1;
            _mVeh setMarkerPosLocal _vehPt;
        };
        waitUntil {inputAction "MoveForward" > 0 || inputAction "MoveBack" > 0 || !visibleMap};
        if (inputAction "MoveForward" > 0) then {_index = _index + 1}
        else {if (inputAction "MoveBack" > 0) then {_index = _index - 1}};
        if (!visibleMap) exitWith{};
        waitUntil {inputAction "MoveForward" == 0 && inputAction "MoveBack" == 0};       
    };
    _mapCtrl ctrlRemoveEventHandler ["Draw",_ehID];
    deleteMarkerLocal _mVeh;
    deleteMarkerLocal _mBase;
    hint "";
};

ITW_ObjSetVehicleSpawn = {
    // vehicle spawn point (on a road), or [] if no reads nearby, or nil if not setup yet
    params ["_obj"];  
    private _center = _obj#ITW_OBJ_POS;
    private _aiVehSpawnPt = _obj#ITW_OBJ_V_SPAWN;
    if (isNil "_aiVehSpawnPt") then {
        private _roads = [];
        private _dist = 400;
        while {_roads isEqualTo [] && {_dist <= 800}} do {
            _roads = (_center nearRoads _dist) select {private _info = getRoadInfo _x; !(_info#2 || _info#8)}; // not pedestrian or bridge
            _dist = _dist + 200;
        };
        if (!(_roads isEqualTo [])) then {
            _aiVehSpawnPt = getPosATL (selectRandom _roads);
            _aiVehSpawnPt set [2,_aiVehSpawnPt#2 + 0.5];
        } else {
            _aiVehSpawnPt = [];
        };
        _obj set [ITW_OBJ_V_SPAWN,_aiVehSpawnPt];
    };
   
    if !(_aiVehSpawnPt isEqualTo []) then {[_aiVehSpawnPt,30,[FLAG_TYPE]] remoteExec ["ITW_RemoveTerrainObjects",0,true]};
};

ITW_ObjOwnedAirports = {
    // returns array of positions or [] if no airports owned
    params ["_isFriendly"];
    
    if (isNil "ITW_ZoneAirportMap") then {
        ITW_ZoneAirportMap = createHashMap;
        private _airportPts = [];
        private _cfg = (configFile >> "CfgWorlds" >> worldName);
        private _ilsPos = getArray (_cfg >> "ilsTaxiOff");
        if !(_ilsPos isEqualTo []) then {_airportPts pushBack [_ilsPos#0,_ilsPos#1]};
        {
            _ilsPos = getArray (_x >> "ilsTaxiOff");
            if !(_ilsPos isEqualTo []) then {_airportPts pushBack [_ilsPos#0,_ilsPos#1]};
        } forEach ("true" configClasses (_cfg >> "SecondaryAirports"));
        
        {
            private _airport = _x;
            private _dist = 1e10;
            private _closestZoneId = 0;
            {
                private _obj = _x;
                private _d = _airport distance2D (_obj#ITW_OBJ_POS);
                if (_d < _dist) then {
                    _dist = _d;
                    _closestZoneId = _obj#ITW_OBJ_ZONEID;
                };
            } count ITW_Objectives;
            ITW_ZoneAirportMap set [_closestZoneId,_airport];
        } forEach _airportPts;
    };
    
    waitUntil {isNil "ITW_OwnedAirportsProcessing"};
    if (isNil "ITW_OwnedAirports") then {
        ITW_OwnedAirportsProcessing = true;
        private _airportsF = [];
        private _airportsE = [];
        private _startF = 0;
        private _startE = ITW_ZoneIndex+1;
        private _endF = ITW_ZoneIndex-1;
        private _endE = count ITW_Zones-1;
        {
            private _zone = _x,
            private _airport = _y;
            private _mrkr = "itwAPmrkr"+str _airport;
            if (getMarkerColor _mrkr isEqualTo "") then {createMarkerLocal [_mrkr, _airport]};
            _mrkr setMarkerSizeLocal [0.01,0.01];
            _mrkr setMarkerTypeLocal "EmptyIcon";
            if (_zone >= _startF && {_zone <= _endF}) then {
                _airportsF pushBack _airport;
                _mrkr setMarkerColorLocal COLOR_INACTIVE_BLUE;
                _mrkr setMarkerTextLocal localize "STR_ITW_OBJ_AllyAirfield";
                _mrkr setMarkerAlpha 1;
            } else {
                if (_zone >= _startE && {_zone <= _endE}) then {
                    _airportsE pushBack _airport;
                    _mrkr setMarkerColorLocal COLOR_ACTIVE_RED;
                    _mrkr setMarkerTextLocal localize "STR_ITW_OBJ_EnemyAirfield";
                    _mrkr setMarkerAlpha 1;
                } else {
                    _mrkr setMarkerAlpha 0;
                };
            };
        } forEach ITW_ZoneAirportMap;
        ITW_OwnedAirports = [_airportsF,_airportsE];
        ITW_OwnedAirportsProcessing = nil;
        
        if (ITW_ParamAirplaneWithoutAirport == 1) then {
            ITW_OwnedAirports#0 pushBack (ITW_Objectives#0#ITW_OBJ_POS);
            ITW_OwnedAirports#1 pushBack (ITW_Objectives#(count ITW_Objectives - 1)#ITW_OBJ_POS);
        };
    };
    
    ITW_OwnedAirports#(if(_isFriendly)then{0}else{1})
};

ITW_ObjClosestOwnedAirport = {
    // returns position of nearest airport or [] if no airports owned
    params ["_isFriendly","_pos"];
    private _airportPos = [];
    private _airportPositions = (_isFriendly call ITW_ObjOwnedAirports) + (_isFriendly call ITW_WarshipCarrierPositions);
    [_pos,_airportPositions] call ITW_FncClosest
};

ITW_ObjOwnsAirport = {
    // returns true if this side (friendly or not) owns at least one airport
    params ["_isFriendly"];
    !((_isFriendly call ITW_ObjOwnedAirports) isEqualTo []) || {!((_isFriendly call ITW_WarshipCarrierPositions) isEqualTo [])}
};

ITW_ObjMinefields = {
    params ["_objs",["_clear",false]];
    scriptName "ITW_ObjMinefields";
    {
        private _obj = ITW_Objectives#_x;
        private _objPos = _obj#ITW_OBJ_POS;
        if (_clear) then {
            private _mines = nearestMines [_objPos, [], ITW_ParamObjectiveSize+720, false, true];
            {deleteVehicle _x} count _mines;
        } else {
            if (random 1 < (0.4 * ITW_ParamMines)) then {
                private _mineTypes = ["ATMine","APERSMine","APERSBoundingMine","SLAMDirectionalMine"];
                private _fromBasePos = [_obj,true,true] call ITW_ObjGetAttackVectorFromPos;
                private _count = ceil random 3;
                for "_i" from 1 to _count do {
                    private _dir = (_objPos getDir _fromBasePos) - 80 + random 160;
                    private _size = 150 + random 100;
                    private _range = ITW_ParamObjectiveSize + (_size/2) + random (400);
                    private _pos = _objPos getPos [_range,_dir];
                    private _numMines = _size*_size*0.001; // scale to around 20 per 200m circle
                    for "_m" from 1 to _numMines do {   
                        _mine = createMine [selectRandom _mineTypes, _pos, [], _size];
                        _mine setDir (_dir - 45 + random 90);
                    };
                };
            };
        };
    } forEach _objs;
};

ITW_ObjShowMines = {
    private _mineMarkers = [];
    {
        private _m = createMarkerLocal ["itwmine"+str _forEachIndex,getPosATL _x];
        _m setMarkerType "hd_dot";
        _mineMarkers pushBack _m;
    } forEach allMines;
    sleep 10;
    { deleteMarker _x} count _mineMarkers;
};

ITW_ObjArtillery = {
    // spawn on server
    scriptName "ITW_ObjArtillery";
    if (ITW_ParamArtillery == 0) exitWith {};

    private _artilleryParamSec = ITW_ParamArtillery * 60;
    private _showArtyInfo = [];
    
    private _etaTime           = 30; // how long mortar shell is in the air
    private _noTargetCheckTime = 60; // if no targets found, how long until we check again
    
    private _dropSpacingAddPercent = 0.2; // shots will be min spacing + up to 20%
    
    private _volleyMaxCount    = ITW_ParamObjectivesPerZone;
    private _volleySpacingMin  = 0; // time between each round in a volley: _etaTime + MIN + random ADD
    private _volleySpacingAdd  = 30;

    private _rechargeSpacingMin = _artilleryParamSec/2 - _etaTime; // time between artillery volleys: MIN + random ADD
    private _rechargeSpacingAdd = _volleySpacingMin + _artilleryParamSec; 
    
    private _accuracy = 200; // how close to the target a round will land
    private _friendlyDist = _accuracy + 80; // distance from target friendlies must not be
    #define A_VAR_DROP_TIME   0  // _artillery array indexes
    #define A_VAR_DROP_CNTR   1 
    #define A_VAR_DROP_MAX    2 
    #define A_VAR_DROP_SPACE  3 
    #define A_VAR_VOLLEY_CNTR 4
    #define A_VAR_VOLLEY_MAX  5
    #define A_VAR_TARGET_POS  6
    #define A_VAR_AMMO_CURR   7
    #define A_VAR_AMMO_TYPES  8
    private _artillery = [[0,0,0,0,0,0,[],"Sh_82mm_AMOS",va_pArtyAmmo],
                          [0,0,0,0,0,0,[],"Sh_82mm_AMOS",va_eArtyAmmo]]; 
 
    //diag_log "--- Ally Artillery --- ";{diag_log _x} forEach (_artillery#0#A_VAR_AMMO_TYPES);
    //diag_log "--- Enemy Artillery ---";{diag_log _x} forEach (_artillery#1#A_VAR_AMMO_TYPES);
    
    while {!ITW_GameOver} do {
        while {LV_PAUSE} do {sleep 5};
        private _sleep = 1e10;
        {
            if (ITW_ZoneIndex >= count ITW_Zones) exitWith {};
            private _arty = _x;
            private _dropTime  = _arty#A_VAR_DROP_TIME;
            if (time >= _dropTime) then {
                private _dropCnt = _arty#A_VAR_DROP_CNTR;
                private _dropMax = _arty#A_VAR_DROP_MAX;
                private _dropSpacingMin = _arty#A_VAR_DROP_SPACE;
                private _volleyCnt = _arty#A_VAR_VOLLEY_CNTR;
                private _volleyMax = _arty#A_VAR_VOLLEY_MAX;
                private _targetPos = _arty#A_VAR_TARGET_POS;
                
                if (_targetPos isEqualTo []) then {
                    // time to pick a target
                    // choose the target for the next shell to hit
                    private _isFriendly = _forEachIndex == 0;
                    private _targetObjIdx = selectRandom (ITW_Zones#ITW_ZoneIndex);
                    if (isNil "_targetObjIdx") exitWith {}; // skip this drop as we must be setting up or shutting down
                    private _objPos = ITW_Objectives#_targetObjIdx#ITW_OBJ_POS;
                    private _hitUnits = []; 
                    private _avoidUnits = [];
                    private _hitSide = if (_isFriendly) then {ITW_EnemySide} else {west}; 
                    private _avoidSide = if (_isFriendly) then {west} else {ITW_EnemySide};
                    {
                        switch (side _x) do {
                            case _hitSide: {if (_avoidSide knowsAbout _x > 0.105) then {_hitUnits pushBack _x}};
                            case _avoidSide: {_avoidUnits pushBack _x};
                        };
                    } forEach (_objPos nearEntities ["Land",ITW_ParamObjectiveSize+750]);
                    
                    private _target = objNull;
                    {
                        private _unit = _x;
                        private _okay = true;
                        {if (_unit distance _x < _friendlyDist) exitWith {_okay = false}} count _avoidUnits;
                        if (_okay) exitWith {_target = _unit};
                    } count (_hitUnits call BIS_fnc_arrayShuffle);
                    
                    if (isNull _target) then {
                        _dropTime = time + _noTargetCheckTime;
                    } else {
                        _dropTime = time + _etaTime;
                        _arty set [A_VAR_DROP_TIME  ,_dropTime];
                        _arty set [A_VAR_TARGET_POS,if (isNull _target) then {[]} else {getPosATL _target}]; 
                        
                        // choose ammo type for this volley
                        (selectRandom (_arty#A_VAR_AMMO_TYPES)) params ["_shell","_count","_delay"];
                        _arty set [A_VAR_AMMO_CURR,_shell];  
                        _arty set [A_VAR_DROP_MAX,ceil random _count];
                        _arty set [A_VAR_DROP_SPACE,_delay];
                    };
                } else {
                    // time to drop an artillery shell
                    private _posToFireAt = _targetPos getPos [random (_accuracy - 30) + 30, random 360];
                    _posToFireAt set [2,600];
                    
                    private _shell = (_arty#A_VAR_AMMO_CURR) createVehicle _posToFireAt;
                    _shell setPosATL _posToFireAt;
                    _shell setVelocity [0,0,-50];
                    
                    // setup for next volley
                    _dropCnt = _dropCnt + 1;
                    if (_dropCnt < _dropMax) then {
                        _dropTime = time + _dropSpacingMin * (1 + random _dropSpacingAddPercent);
                        _arty set [A_VAR_DROP_TIME,_dropTime];
                        _arty set [A_VAR_DROP_CNTR,_dropCnt]; 
                    } else {
                        // drops complete
                        _volleyCnt = _volleyCnt + 1;
                        if (_volleyCnt < _volleyMax) then {
                            // volleys NOT complete
                            _dropTime = time + _volleySpacingMin + random _volleySpacingAdd;
                            _arty set [A_VAR_DROP_TIME  ,_dropTime];
                            _arty set [A_VAR_DROP_CNTR  ,0];
                            _arty set [A_VAR_VOLLEY_CNTR,_volleyCnt];
                            _arty set [A_VAR_TARGET_POS ,[]];                     
                        } else {
                            // volleys COMPLETE
                            _dropTime = time + _rechargeSpacingMin + random _rechargeSpacingAdd;
                            _arty set [A_VAR_DROP_TIME  ,_dropTime];
                            _arty set [A_VAR_DROP_CNTR  ,0]; 
                            _arty set [A_VAR_VOLLEY_CNTR,0]; 
                            _arty set [A_VAR_VOLLEY_MAX ,ceil random _volleyMaxCount];
                            _arty set [A_VAR_TARGET_POS ,[]];                    
                        };
                    };
                    
                    if (ITW_ObjShowArty) then {
                        if (_showArtyInfo isEqualTo []) then {
                            _showArtyInfo = [[0,[]],[0,[]]];
                            for "_i" from 0 to 9 do {
                                private _mrkr = createMarkerLocal ["itwsarty"+str _i,[0,0,0]];
                                _mrkr setMarkerTypeLocal "hd_dot";
                                _mrkr setMarkerColorLocal "ColorBlue";
                                (_showArtyInfo#0#1) pushBack _mrkr;
                                _mrkr = createMarkerLocal ["itwsarty2"+str _i,[0,0,0]];
                                _mrkr setMarkerTypeLocal "hd_dot";
                                _mrkr setMarkerColorLocal "ColorRed";
                                (_showArtyInfo#1#1) pushBack _mrkr;
                            };
                        };
                        private _showInfo = _showArtyInfo#_forEachIndex;
                        private _index = _showInfo#0;
                        private _mrkr = _showInfo#1#_index;
                        _mrkr setMarkerPosLocal _posToFireAt;
                        _mrkr setMarkerTextLocal ([time,"MM:SS"] call BIS_fnc_secondsToString);
                        _index = _index + 1;
                        if (_index > 9) then {_index = 0};
                        _showInfo set [0,_index];
                        diag_log ["Arty Hit","side",_forEachIndex,_arty];
                    };
                };
            };
            private _nextDropIn = _dropTime - time;
            if (_nextDropIn < _sleep) then {_sleep = _nextDropIn};
        } forEach _artillery;
        sleep _sleep;      
    };
};
    
ITW_Statics = [];
ITW_ObjGenStatics = {
    params ["_objIds"];
    if (ITW_ParamStatics == 0) exitWith {ITW_Statics = []};
    if !(ITW_Statics isEqualTo []) then {
        private _statics = +ITW_Statics; // copy so we can change the original
        _statics spawn {
            scriptName "ITW_GenStatics";
            private _statics = _this;
            while {!(_statics isEqualTo [])} do {
                {
                    private _static = _x;
                    private _deletable = true;
                    if (_deletable) then {
                        {
                            if (_x distance _static < 1000) exitWith {_deletable = false};
                        } forEach playableUnits;
                    };
                    if (_deletable) then {
                        {deleteVehicle _x} count crew _static;
                        deleteVehicle _static;
                    };
                } forEach _statics;
                sleep 10;
                _statics = _statics - [objNull];
            };           
        };
    };
    ITW_Statics = [];
    
    if (isNil "ITW_AoStaticTypes") then {
        ITW_AoStaticTypes = [va_pStaticClasses,va_eStaticClasses];
        if (ITW_ParamStatics > 0) then {ITW_AoStaticTypes = [va_pStaticClasses + va_eMortarClasses,va_eStaticClasses + va_eMortarClasses]};
        if (ITW_AoStaticTypes#0 isEqualTo []) then {diag_log "ITW: ITW_AoGenStatics: no statics available to player faction"};
        if (ITW_AoStaticTypes#1 isEqualTo []) then {diag_log "ITW: ITW_AoGenStatics: no statics available to enemy faction"};
    };
    if (ITW_AoStaticTypes isEqualTo [[],[]]) exitWith {};
    
    if (isNil "SKL_SmartStaticDefense") then {
        SKL_SmartStaticDefense = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_SmartStaticDefence.sqf";
    };
    if (isNil "ITW_ADDED_BUILDING_BLACKLIST") then {ITW_ADDED_BUILDING_BLACKLIST = ["water"]};
    
    #define MAX_STATICS 9 // max statics in a 300m zone, levels will be 1/3, 2/3, or this amount depending on ITW_ParamStatics
    private _aoSize = ITW_ParamObjectiveSize;
    private _maxStatics = (floor (MAX_STATICS * (abs ITW_ParamStatics)/3 * ((_aoSize / 300)^1.5))) min 50 max 2;
    private _statics = [];
    private _blacklist = +ITW_ADDED_BUILDING_BLACKLIST;
    {
        private _aoCenter = ITW_Objectives#_x#ITW_OBJ_POS;
        private _isFriendly = _x call ITW_ObjContestedOwnerIsFriendly;
        private _staticTypes = ITW_AoStaticTypes#(if (_isFriendly) then {0} else {1});
        if (_staticTypes isEqualTo []) then {continue};
        private _placeSize = _aoSize - 50;
        private _loopCnt = 10;
        private _numStatics = 0;
        private _maxThisObj = floor (_maxStatics - 1 + random 2);      
        while {_numStatics < _maxThisObj && {_loopCnt > 0}} do {
            _loopCnt = _loopCnt - 1;
            private _vehTypeTxtr = selectRandom _staticTypes;
            private _type = if (typeName _vehTypeTxtr == "ARRAY") then {_vehTypeTxtr#0} else {_vehTypeTxtr};
            private _pos = [];
            private _isMortar = _vehTypeTxtr in va_eMortarClasses;
            private _maxLoops = 30;
            while {count _pos != 2 && {_maxLoops > 0}} do {
                _maxLoops = _maxLoops - 1;
                _pos = [_aoCenter, 0, _placeSize, _type call ITW_FncSizeOf, 0, 0.2, 0, _blacklist,[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
                private _road = roadAt _pos;
                if (!isNull _road) then {
                    // move the static off the road
                    getRoadInfo _road  params ["_mapType", "_width", "_isPedestrian", "_texture", "_textureEnd", "_material", "_begPos", "_endPos", "_isBridge"];
                    if (_isBridge) exitWith {_pos = []};
                    private _crossDir = (_begPos getDir _endPos) + (if (random 1 < 0.5) then {90} else {-90});
                    _pos = _pos getPos [_width,_crossDir];
                    if (_pos isFlatEmpty [3, -1, 0.8, 2, 0, false, objNull] isEqualTo []) then {_pos = []};
                };
                if (_isMortar && {count _pos == 2 && {!(_pos call ITW_ObjClearSkyCode)}}) then  {_pos = []};
            };
            if (count _pos == 2) then {
                _numStatics = _numStatics + 1;
                _pos pushBack 0.2;
                _blacklist pushBack [_pos,15];
                private _static = [_vehTypeTxtr,_pos] call ITW_VehCreateVehicle;
                _static allowDamage false;
                _static setDir (_aoCenter getDir _pos);
                _static setPosATL _pos; 
                _static setVectorUp surfaceNormal getPosASL _static;
                [_static,_isFriendly] call ITW_AtkAddCrewToStatic;
                [_static] call SKL_SmartStaticDefense;
                _statics pushBack _static;
                ITW_Statics pushBack _static;
                sleep 0.2;              
            };             
        };
        diag_log format ["ITW: Added %1 statics to %2",_numStatics,ITW_Objectives#_x#ITW_OBJ_NAME];
    } forEach _objIds;
    if !(_statics isEqualTo []) then { { _x addCuratorEditableObjects [_statics, true]; } forEach allCurators };
    sleep 2;
    {_x allowDamage true} forEach ITW_Statics;
};

ITW_ObjClearSkyCode = {
    private _pos = +_this;
    _pos set [2,1];
    private _beg = ATLToASL _pos;
    _pos set [2,20];
    private _end = ATLToASL _pos;
    // _ix will be an array of [intersectPosASL, surfaceNormal, intersectObj, parentObject] or empty array
    private _ix = lineIntersectsSurfaces [_beg,_end,objNull,objNull,true,1,"VIEW","NONE"];
    _ix isEqualTo []
};

//ITW_ParamDefendPhaseType       0: none, 1x: flag capture (x/30)% of the time (x=0=>10), 2x: zone capture (x/10)% of the time (x=0=>10) 
//ITW_ParamDefendPhaseIntensity  1 (mild) to 10 (extreme), This mode will ramp up number of ai on the map and that will scale with intensity
//ITW_ParamDefendPhaseDelay      delay before wave spawns in seconds, tickets accumulate during this time
//ITW_ParamDefendPhaseDuration   seconds - how long does the push to this obj last and before zone can be captured

ITW_ObjDefendPhase = {
    // call on server when a defend phase should be triggered
    
    // Pick which objective to attack
    private _objIndexes = playableUnits
        apply {[getPosATL _x,ITW_OWNER_CONTESTED,ITW_OWNER_FRIENDLY,true] call ITW_ObjGetNearest} 
        select {_x isNotEqualTo []}
        apply {_x#ITW_OBJ_INDEX};
    private _indexHash = createHashMap; // [Idx,count]
    {
        private _prevValue = _indexHash getOrDefault [_x,0];
        _indexHash set [_x,_prevValue + 1];
    } forEach _objIndexes;
    private _maxIdx = -1;
    private _maxCnt = -1;
    {
        if (_y > _maxCnt) then {_maxIdx = _x};
    } forEach _indexHash;
    if (_maxIdx < 0) exitWith {diag_log "Error Pos: ITW_ObjDefendPhase called when no friendly owned contested objectives exist"};
    
    // figure out when to trigger
    private _minStartDelay = 0 max (ITW_objStartedTime + ITW_ParamFriendlyInvasionDelay + 30 - time);
    private _when = round ((_minStartDelay + ITW_ParamDefendPhaseDelay)/60);

    // Notify the players
    diag_log format ["ITW: Defend Phase starting in %1 sec, type: %2, intense: %3, duration: %4",(round (ITW_ParamDefendPhaseDelay/6))/10,ITW_ParamDefendPhaseType,ITW_ParamDefendPhaseIntensity,(round (ITW_ParamDefendPhaseDuration/6))/10];
    if (_when == 0) then {_when = "now"} else {_when = "in " + str _when + " minutes"};
    [
        format [localize "STR_ITW_OBJ_DefendStartMsg",ITW_Objectives#_maxIdx#ITW_OBJ_NAME, mapGridPosition (ITW_Objectives#_maxIdx#ITW_OBJ_POS), _when],
        0,     // X : 0 is center
        0.2,   // Y : 0.2 is above center
        10,    // Duration
        1,     // Fade-in time
        0,     // Delta Y 
        6831   // layer ID
    ] remoteExec ["BIS_fnc_dynamicText", 0];
    
    // update tasks so player can figure which one it is if they missed the text
    private _subTaskStates = [];
    {
        private _objIdx = _x;
        private _obj = ITW_Objectives#_objIdx;
        private _taskId = _obj#ITW_OBJ_TASKID;
        private _subTasks = _taskId call BIS_fnc_taskChildren;
        if (typeName _subTasks == "ARRAY") then {
            {
                _subTaskStates pushBack [_x,_x call BIS_fnc_taskState];
                [_x,"CANCELED",false] call BIS_fnc_taskSetState;
            } forEach (_taskId call BIS_fnc_taskChildren);
        };
        if (_objIdx == _maxIdx) then {
            private _name = _obj#ITW_OBJ_NAME;
            [_taskId,nil,["",localize "STR_ITW_OBJ_Defend" +" "+_name,""],nil,"ASSIGNED",nil,false,nil,"defend"] call BIS_fnc_setTask;
        } else {
            [_taskId,"CANCELED",false] call BIS_fnc_taskSetState;
        };
    } forEach (ITW_Zones#ITW_ZoneIndex);

    // don't progress if mission just started, wait for some allies to be spawned in
    sleep _minStartDelay;
    
    // Trigger the wave prep
    ITW_defendPhaseObjIdx = _maxIdx;
    publicVariable "ITW_defendPhaseObjIdx";
    
    // setup for the ending of the phase
    _subTaskStates spawn {
        scriptName "ITW_ObjDefendPhase";
        private _subTaskStates = _this;
        
        // delay the request amount (or more if needed for friendly to spawn in at start of a saved game)
        sleep ITW_ParamDefendPhaseDelay;

        ["defend"] call ITW_Bombardment;
    
        diag_log "ITW: Defend Phase starting";
        // trigger the wave start
        ITW_defendRunning = true;
        publicVariable "ITW_defendRunning";
        private _timeout = time + ITW_ParamDefendPhaseDuration;
        [format [localize "STR_ITW_OBJ_MinutesRemaining",round ((_timeout - time)/60)]] remoteExec ["hint",0];
        while {time < _timeout} do {
            sleep 60;
            if (LV_PAUSE) then {private _t = time; waitUntil {sleep 5;!LV_PAUSE};_timeout = _timeout + (time - _t)};
            if (ITW_ParamDefendNofication < 100) then {
                private _minute = round ((_timeout - time)/60);
                if (_minute >  0 && {_minute == 2 || {_minute mod ITW_ParamDefendNofication == 0}}) then {
                    [format [localize "STR_ITW_OBJ_MinutesRemaining",_minute]] remoteExec ["hint",0];
                };
            };
        };
        diag_log "ITW: Defend Phase ending";
        {
            private _obj = ITW_Objectives#_x;
            private _name = _obj#ITW_OBJ_NAME;
            private _taskId = _obj#ITW_OBJ_TASKID;
            [_taskId,nil,["",localize "STR_ITW_OBJ_Attack" +" "+_name,""],nil,"CREATED",nil,false,nil,"attack"] call BIS_fnc_setTask;
        } forEach (ITW_Zones#ITW_ZoneIndex);
        {
            [_x#0,_x#1,false] call BIS_fnc_taskSetState;
        } forEach _subTaskStates;
        ITW_defendPhaseZoneDone = ITW_ZoneIndex;
        ITW_defendPhaseObjIdx = -1; // end the phase
        publicVariable "ITW_defendPhaseObjIdx";
        ITW_defendRunning = false;
        publicVariable "ITW_defendRunning";
        [
            localize "STR_ITW_OBJ_DefendEndMsg",
            0,     // X : 0 is center
            0.2,   // Y : 0.2 is above center
            10,    // Duration
            1,     // Fade-in time
            0,     // Delta Y 
            6831   // layer ID
        ] remoteExec ["BIS_fnc_dynamicText", 0];
    };
};

ITW_ObjLoad = {
    params ["_objectives","_zoneIndex","_captured"];
    _captured apply { // backwards compatibility fixes
        if (count _x <= ITW_CONT_TARGET_COMPLETE) then {_x pushBack 0};
        if (typeName (_x#ITW_CONT_TARGET_COMPLETE) != "SCALAR") then {_x set [ITW_CONT_TARGET_COMPLETE,0]};
    };
    ITW_ObjContestedState = _captured;
    ITW_Objectives = _objectives;
    ITW_ZoneIndex = _zoneIndex;
    // clean up objectives if they got corrupted
    {
        private _obj = _x;
        if (_obj#ITW_OBJ_ZONEID > _zoneIndex) then {_obj set [ITW_OBJ_OWNER,ITW_OWNER_ENEMY]};
        if (_obj#ITW_OBJ_ZONEID < _zoneIndex) then {_obj set [ITW_OBJ_OWNER,ITW_OWNER_FRIENDLY]};
    } forEach ITW_Objectives;
    false call ITW_ObjGetZones;
    publicVariable "ITW_Objectives";
    publicVariable "ITW_ZoneIndex"; 
    true call ITW_ObjectivesSetup;
};


["ITW_ObjCenter"] call SKL_fnc_CompileFinal;
["ITW_ObjClosestOwnedAirport"] call SKL_fnc_CompileFinal;
["ITW_ObjCreateNearestBasesMap"] call SKL_fnc_CompileFinal;
["ITW_ObjectivesSetup"] call SKL_fnc_CompileFinal;
["ITW_ObjFailure"] call SKL_fnc_CompileFinal;
["ITW_ObjFlag"] call SKL_fnc_CompileFinal;
["ITW_ObjFlagHud"] call SKL_fnc_CompileFinal;
["ITW_ObjFlagTask"] call SKL_fnc_CompileFinal;
["ITW_ObjGenStructures"] call SKL_fnc_CompileFinal;
["ITW_ObjGetBase"] call SKL_fnc_CompileFinal;
["ITW_ObjGetContestedObjs"] call SKL_fnc_CompileFinal;
["ITW_ObjGetNearest"] call SKL_fnc_CompileFinal;
["ITW_ObjGetNearestBase"] call SKL_fnc_CompileFinal;
["ITW_ObjGetObjectives"] call SKL_fnc_CompileFinal;
["ITW_ObjGetPlayerSpawnPtDir"] call SKL_fnc_CompileFinal;
["ITW_ObjGetZones"] call SKL_fnc_CompileFinal;
["ITW_ObjLoad"] call SKL_fnc_CompileFinal;
["ITW_ObjNearestBuildings"] call SKL_fnc_CompileFinal;
["ITW_ObjNext"] call SKL_fnc_CompileFinal;
["ITW_ObjOwnedAirports"] call SKL_fnc_CompileFinal;
["ITW_ObjOwnsAirport"] call SKL_fnc_CompileFinal;
["ITW_ObjSetMarker"] call SKL_fnc_CompileFinal;
["ITW_ObjSetVehicleSpawn"] call SKL_fnc_CompileFinal;
["ITW_ObjShowAttackVectors"] call SKL_fnc_CompileFinal;
["ITW_ObjIsNearestFriendly"] call SKL_fnc_CompileFinal;
["ITW_ObjFlagMP"] call SKL_fnc_CompileFinal;
["ITW_ObjContestedOwnerIsFriendly"] call SKL_fnc_CompileFinal;
["ITW_ObjRedOut"] call SKL_fnc_CompileFinal;
["ITW_ObjGetOutToSeaPos"] call SKL_fnc_CompileFinal;
["ITW_ObjGetAttackVectorFromPos"] call SKL_fnc_CompileFinal;
["ITW_ObjMinefields"] call SKL_fnc_CompileFinal;
["ITW_ObjShowMines"] call SKL_fnc_CompileFinal;
["ITW_ObjArtillery"] call SKL_fnc_CompileFinal;
["ITW_ObjLandAtkAdjust"] call SKL_fnc_CompileFinal;
["ITW_ObjGenStatics"] call SKL_fnc_CompileFinal;
["ITW_ObjClearSkyCode"] call SKL_fnc_CompileFinal;
["ITW_ShowSeaPoints"] call SKL_fnc_CompileFinal;
["ITW_ObjSetOutToSeaPos"] call SKL_fnc_CompileFinal;
["ITW_ObjFlagCapture"] call SKL_fnc_CompileFinal;
["ITW_ShowAllObjectives"] call SKL_fnc_CompileFinal;
["ITW_ObjGetRandomName"] call SKL_fnc_CompileFinal;
["ITW_ObjMoving"] call SKL_fnc_CompileFinal;
["ITW_ObjMovingMP"] call SKL_fnc_CompileFinal;
["ITW_ObjDefendPhase"] call SKL_fnc_CompileFinal;
["ITW_ObjZoneSelection"] call SKL_fnc_CompileFinal;
["ITW_ObjZoneSelectionMP"] call SKL_fnc_CompileFinal;