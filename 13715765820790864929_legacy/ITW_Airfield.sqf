
ITW_airfieldBase = objNull;
ITW_airfieldRepair = [];    // [_pos,_radius]
ITW_airfieldPos = []; // _pos
ITW_airfieldDir = 0;
ITW_storedVehicles = [];

#define AIRFIELD_BOX_TYPE "Land_PaperBox_01_small_stacked_F"

ITW_AirfieldSpawnCrate = {
    params ["_pos"];
    _pos set [2,15];
    private _crate = AIRFIELD_BOX_TYPE createVehicle _pos;
    _crate allowDamage false;
    _crate setPosATL _pos;
    _crate setVariable ["Deployed",false,true];
    [_crate] remoteExec ["ITW_AirfieldBoxMP",0,_crate];
    ITW_airfieldBase = _crate;
    publicVariable "ITW_airfieldBase";
};
        
ITW_AirfieldDelete = {
    if !(isServer) exitWith {0 remoteExec ["ITW_AirfieldDelete",2]};
    deleteVehicle ITW_airfieldBase;
    ITW_airfieldBase = objNull;
    publicVariable 'ITW_airfieldBase';
    if !(ITW_airfieldRepair isEqualTo []) then {  
        ITW_airfieldRepair call ITW_vehRepairPointRemove;
        ITW_airfieldRepair = [];
    };    
    if !(ITW_airfieldPos isEqualTo []) then {   
        ITW_Garages = ITW_Garages - [ITW_airfieldPos]; publicVariable "ITW_Garages";
        ITW_airfieldPos = []; publicVariable "ITW_airfieldPos";
    };
    [] remoteExec ["ITW_AirfieldCircleMP",0,"AirCircle"];
};

ITW_AirfieldBoxMP = {
    params ["_crate"];
    if (!hasInterface) exitWith {};
    
    0 spawn ITW_AirfieldMarkerUpdater;
    
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_MoveToAirfield"+"</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            private _extraText = if (isNil "ITW_AirportPtsShowing") then {"<br/>"+localize "STR_ITW_AF_ValidLocShown"+"</t>"} else {"</t>"};
            cutText ["<t size='3'>" + localize "STR_ITW_AF_Instructions" + _extraText, "PLAIN", -1, true, true];
            if (isNil "ITW_AirportPtsShowing") then {
                ITW_AirportPtsShowing = true;
                if (isNil "ITW_AirportPts") then {[_crate] call ITW_AirfieldBoxInRange};
                private _airportDots = [];
                private _cfg = (configFile >> "CfgWorlds" >> worldName);
                {
                    _x params ["_idx","_pts"];
                    {
                        private _pos = _x;
                        _mrkr = createMarkerLocal [format ["apdot_%1_%2",_idx,_forEachIndex], _pos];
                        _mrkr setMarkerSizeLocal [100,100];
                        _mrkr setMarkerBrushLocal "Solid";
                        _mrkr setMarkerShapeLocal "ELLIPSE";
                        _mrkr setMarkerTypeLocal "hd_dot";
                        _mrkr setMarkerColorLocal "ColorOrange";
                        _mrkr setMarkerAlphaLocal 0.75;
                        _airportDots pushBack _mrkr;
                    } forEach _pts;
                } forEach ITW_AirportPts;
                _airportDots spawn {
                    private _timeout = time + 30;
                    while {!isNil "ITW_AirportPtsShowing" && {time < _timeout}} do {sleep 1};
                    {deleteMarkerLocal _x} forEach _this; 
                    ITW_AirportPtsShowing = nil;
                };
            };
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true])",4]; 
        
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Deploy" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            if !(isNull attachedTo _crate) then {
                private _carrier = attachedTo _crate;
                _carrier setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                sleep 0.5;
                player setAnimSpeedCoef 1;
                _crate setVelocity [0,0,-0.1]; 
            };   
            ITW_AirportPtsShowing = nil;
            [_crate,true] remoteExec ["ITW_AirfieldDeploy",2];
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true]) && {[_target] call ITW_AirfieldBoxInRange >= 0}",4]; 
        
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Carry" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            _crate attachTo [player, [0, 2, 1]];
            player setAnimSpeedCoef 0.7;
            player playAction "PlayerStand";
            player action ["SwitchWeapon",player,player,-1];
            player addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_Drop" + "</t>", { 
                params ["_player", "_caller", "_actionId", "_arguments"];
                private _crate = ITW_AF_CRATE; 
                player setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                sleep 0.5;
                player setAnimSpeedCoef 1;
                _crate setVelocity [0,0,-0.1]; 
                _player removeAction _actionId;
            },nil,10,false,true,"","player == attachedTo ITW_AF_CRATE",4];
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true]) && {(isPlayer _this) && {isNull attachedTo _target}}",4];  
    ITW_AF_CRATE = _crate;
    
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_LoadInVehicle" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            player addAction ["<t color='#ff0000'>" + localize "STR_ITW_AF_SelectVehicle" + "</t>", {
                params ["_target", "_caller", "_actionId", "_crate"];
                player removeAction _actionId;
                private _veh = cursorTarget;
                if (_veh isKindOf "Helicopter") then {
                    hint localize "STR_ITW_AF_UseSlingLoad";
                } else {
                    if ((_veh isKindOf "Land" || _veh isKindOf "Sea") && {alive _veh && {speed _veh < 1 && {boundingBox _veh #2 > 5.5}}}) then {
                        if (!simulationEnabled _veh) then {
                            [_veh,true] remoteExec ["enableSimulationGlobal",2];
                            [_veh,true] remoteExec ["allowDamage",_veh];
                        };
                        private _dimensions = getArray (configOf _veh >> "VehicleTransport" >> "Carrier" >> "cargoBayDimensions");
                        private "_loadPos";
                        if (_dimensions isEqualTo []) then {
                            _loadPos = [0,-1.8,0.3];
                        } else {
                            {
                                if (typeName _x isEqualTo "STRING") then {_dimensions set [_forEachIndex,_veh selectionPosition _x]};
                            } forEach _dimensions;
                            _loadPos = [(_dimensions#0#0 + (_dimensions#1#0))/2,(_dimensions#0#1 + (_dimensions#1#1))/2,(_dimensions#0#2) + 0.8];
                        };
                        _crate attachTo [_veh,_loadPos];
                        [_veh,_crate] remoteExec ["ITW_AirfieldBoxLoadMP",0];
                    } else {
                        hint localize "STR_ITW_AF_NoVehSelected";
                    };
                };
            },_crate,100,true,true,"","_this == _target",4]; 
        },nil,10,false,true,"","!(ITW_airfieldBase getVariable ['Deployed',false]) && {isNull attachedTo _target}",4]; 
             
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_BASE_OpenGarage" + "</t>", {
        params ["_crate", "_player", "_actionId", "_arguments"];
            [] call ITW_GaragePreload;
            private _pos = ITW_airfieldPos;
            if (isnil "BIS_fnc_garage_center") then {BIS_fnc_garage_center = objNull};
            if (BIS_fnc_garage_center distance _pos < 10 && {!(crew BIS_fnc_garage_center isEqualTo [])}) exitWith {
                    playSoundUI ["A3\UI_F\data\Sound\CfgNotifications\addItemFailed.wss"];
                    hint localize "STR_ITW_BASE_CrewStillInVeh";
            };
            if (BIS_fnc_garage_center distance _pos >= 10 || {!(crew BIS_fnc_garage_center isEqualTo [])}) then {
                BIS_fnc_garage_center = objNull;
            };
            private _opened = true;
            private _nearbyVehs = nearestObjects [_pos,["Air","LandVehicle","Ship","RoadCone_F"],12];
            {
                if (!alive _x || {typeOf _x isEqualTo "RoadCone_F"}) then {
                    deleteVehicle _x;
                    _nearbyVehs deleteAt _forEachIndex;
                };
            } forEachReversed _nearbyVehs;
            private _nearestVeh = if (count _nearbyVehs > 0) then {_nearbyVehs#0} else {objNull};
            if (_nearestVeh distance _pos > 10 || {_nearestVeh == BIS_fnc_garage_center}) then {
                // okay to spawn new vehicle 
                if (_nearestVeh != BIS_fnc_garage_center) then {
                    BIS_fnc_garage_center = createVehicleLocal ["RoadCone_F", _pos, [], 0, "CAN_COLLIDE"]; 
                };
                BIS_fnc_garage_center setDir ITW_airfieldDir;                  
                ["Open", false] call ITW_Garage;
            } else {
                if (!(_nearestVeh isKindOf "CAManBase") && 
                    {{alive _x} count crew _nearestVeh == 0}) then {
                    // use nearby vehicle as garage vehicle start point
                    deleteVehicle _nearestVeh;
                    BIS_fnc_garage_center = createVehicleLocal ["RoadCone_F", _pos, [], 0, "CAN_COLLIDE"]; 
                    BIS_fnc_garage_center setDir ITW_airfieldDir;   
                    ["Open", false] call ITW_Garage;
                } else {
                    // Garage is blocked
                    playSoundUI ["A3\UI_F\data\Sound\CfgNotifications\addItemFailed.wss"];
                    hint localize "STR_ITW_BASE_GarageBlocked";
                    _opened = false;
                };
            };
            if (_opened && {isNil "ITW_GarageFound"}) then {
                ITW_GarageFound = true;
                sleep 1;
                hint format [localize "STR_ITW_BASE_GarageIsToTheFMT",
                    localize (["STR_ITW_BASE_North","STR_ITW_BASE_NE","STR_ITW_BASE_East","STR_ITW_BASE_SE","STR_ITW_BASE_South",
                               "STR_ITW_BASE_SW","STR_ITW_BASE_West","STR_ITW_BASE_NW","STR_ITW_BASE_North"] select
                    round ((player getDir _pos) / 45))]; 
            };
        },nil,10,true,true,"","ITW_ParamVirtualGarage > 0 && {ITW_airfieldBase getVariable ['Deployed',false]}",4];
        
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_BASE_FastTravel" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            [] spawn ITW_RadioFastTravel;
        },nil,10,false,true,"","ITW_airfieldBase getVariable ['Deployed',false]",8];  
        
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_RetractDeployment" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            if (leader player == player) then {
                ITW_YesNoMenu3 = [
                    [localize "STR_ITW_AF_RetractDeployment", true],
                    [localize "STR_ITW_COMMON_No",  [], "", -5, [["expression", "hint localize 'STR_ITW_COMMON_OperationCancel'"]], "1", "1"],
                    [localize "STR_ITW_COMMON_Yes", [], "", -5, [["expression", 
                        '[objNull,false] remoteExec ["ITW_AirfieldDeploy",2]'
                    ]], "1", "1"]
                ];
                showCommandingMenu "#USER:ITW_YesNoMenu3";
            } else {
                hint localize "STR_ITW_AF_RequiresLeader";
            };
        },nil,10,false,true,"","_target getVariable ['Deployed',true]",4];  
};

ITW_AirfieldBoxLoadMP = {
    // call on all clients
    params ["_veh","_crate"];
    if (!hasInterface) exitWith {};
    private _timeout = time + 5;
    waitUntil {simulationEnabled _veh || {time > _timeout}}; 
    sleep 1;
    ITW_AifieldBoxUnloadActionId = _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_UnloadAfCrate" + "</t>", {
        params ["_veh", "_caller", "_actionId", "_crate"];
        [_veh,false] remoteExec ["allowDamage",_veh];
        playSoundUI ["A3\Sounds_F_Orange\vehicles\soft\Van_02\Van_02_Door_Slide_02.wss", 0.5, 1];
        sleep 1;
        detach _crate;
        _crate setDir getDir _veh;
        private _pos = _veh getPos [((boundingBox _veh)#2)/2 + 3,(getDir _veh) + 180];
        _pos set [2,3];
        _crate setPos _pos;
        [_veh] remoteExec ["ITW_AirfieldBoxUnloadMP",0];
        sleep 3;
        [_veh,true] remoteExec ["allowDamage",_veh];
    },_crate,100,false,true,"","!(isNull attachedTo ITW_airfieldBase)",8]; 
};

ITW_AirfieldBoxUnloadMP = {
    params ["_veh"];
    if !(isNil "ITW_AifieldBoxUnloadActionId") then {
        _veh removeAction ITW_AifieldBoxUnloadActionId;
        ITW_AifieldBoxUnloadActionId = nil;
    };
};

ITW_AirfieldMarkerUpdater = {
    scriptName "ITW_AirfieldMarkerUpdater";
    // spawn on all clients
    #define AIRFIELD_MARKER "ITW_Airfield_mkr"
    #define AIRFIELD_CIRCLE_MARKER "ITW_AirfieldCir_mkr"
    if (!hasInterface) exitWith {};
    sleep 1; // make sure all the things we're looking at have been updated over network
    if (getMarkerColor AIRFIELD_MARKER isEqualTo "") then {
        private _mrkr = createMarkerLocal [AIRFIELD_MARKER, getPosATL ITW_airfieldBase];
        _mrkr setMarkerColorLocal "Color4_FD_F";
        _mrkr setMarkerSizeLocal [1,1];
        _mrkr setMarkerTypeLocal "loc_plane";
        _mrkr setMarkerTextLocal localize "STR_ITW_AF_PlayerAirbase";
        _mrkr = createMarkerLocal [AIRFIELD_CIRCLE_MARKER, getPosATL ITW_airfieldBase];
        _mrkr setMarkerColorLocal "ColorBlue";
        _mrkr setMarkerSizeLocal [25,25];
        _mrkr setMarkerBrushLocal "Border";
        _mrkr setMarkerShapeLocal "ELLIPSE";
        _mrkr setMarkerAlphaLocal 0;
    };
    AIRFIELD_MARKER setMarkerColorLocal "Color4_FD_F";
    while {!isNull ITW_airfieldBase && {!(ITW_airfieldBase getVariable ["Deployed",false])}} do {
        AIRFIELD_MARKER setMarkerPosLocal getPosATL ITW_airfieldBase;
        sleep 2;
    };
    if (ITW_airfieldBase getVariable ["Deployed",false]) then {
        AIRFIELD_MARKER setMarkerPosLocal getPosATL ITW_airfieldBase;
        AIRFIELD_MARKER setMarkerColorLocal "ColorBLUFOR";
        if !(ITW_airfieldPos isEqualTo []) then {
            AIRFIELD_CIRCLE_MARKER setMarkerPosLocal ITW_airfieldPos;
            AIRFIELD_CIRCLE_MARKER setMarkerDirLocal ITW_airfieldDir;
            AIRFIELD_CIRCLE_MARKER setMarkerAlphaLocal 1;
        };
    } else {
        deleteMarkerLocal AIRFIELD_MARKER;
        deleteMarkerLocal AIRFIELD_CIRCLE_MARKER;
    };
};

ITW_AirfieldFixIlsTaxi = {
    private _array = _this;
    {
        private _input = _x;
        if (typeName _input isEqualTo "SCALAR") then {continue};
        if !(typeName _input isEqualTo "STRING") then {diag_log format ["Error Pos: ITW_AirfieldFixIlsTaxi invalid value: %1",_input]; _array set [_forEachIndex,0]};
        _array set [_forEachIndex,call compile _input];
    } forEach _array;
    _array
};

ITW_AirfieldBoxInRange = {
    params ["_crate"];
    #define AIRPORT_TO_CRATE_MAX_DIST 100
    if (isNil "ITW_AirportPts") then {
        
        private _collectDataFN = {
            params ["_cfg","_idx"];
            private _pts = [];
            _pts pushBack (getArray (_cfg >> "ilsPosition"));
            private _taxi = ((getArray (_cfg >> "ilsTaxiOff")) + (getArray (_cfg >> "ilsTaxiIn"))) call ITW_AirfieldFixIlsTaxi;
            private _cnt = count _taxi - 1;
            for "_i" from 0 to _cnt step 2 do {
                _pts pushBack [_taxi#_i,_taxi#(_i+1)];
            };
            [_idx,_pts]
        };
        
        ITW_AirportPts = [];
        private _cfg = (configFile >> "CfgWorlds" >> worldName);
        ITW_AirportPts pushBack ([_cfg,0] call _collectDataFN);
        {
            private _cfgSecondary = _x;
            private _idx = _forEachIndex + 1;
            ITW_AirportPts pushBack ([_cfgSecondary,_idx] call _collectDataFN);
        } forEach ("true" configClasses (_cfg >> "SecondaryAirports"));
    };
    
    private _airport = -1;
    private _cratePos = getPosATL _crate;
    {
        _x params ["_idx","_pts"];
        {
            private _pos = _x;
            if (_cratePos distance _pos <= AIRPORT_TO_CRATE_MAX_DIST) exitWith {_airport = _idx};
        } forEach _pts;
        if (_airport >= 0) exitWith {};
    } forEach ITW_AirportPts;
    _airport
};

ITW_AirfieldDeploy = {
    // call on server
    params ["_crate","_deploy"];
    if (_deploy) then {
        private _toArrayFN = {  
            // convert array to points to array of positions ([a,b,c,d...] ==> [[a,b],[c,d]...]
            private _array = [];
            private _points = _this call ITW_AirfieldFixIlsTaxi;
            private _cnt = count _points - 1;
            for "_i" from 0 to _cnt step 2 do {
                _array pushBack [_points#_i,_points#(_i+1)];
            };
            _array
        };
        private _ptsToDataFn = {
            params ["_pts","_endPt",["_backwards",false]];
            private _array = [];
            private _cnt = count _pts - 2;
            private ["_start","_end","_step"];
            if (_backwards) then {
                _start = 1; _end = count _pts - 1; _step = -1;
            } else {
                _start = 0; _end = count _pts - 2; _step = 1;
            };
            
            for "_i" from _start to _end do {
                private _pt = _pts#_i;
                _array pushBack [_pt,_pt getDir (_pts#(_i+_step))];
            };
            if (_backwards) then {
                _array pushBack [_pts#0,_pts#0 getDir _endPt];
            } else {
                _array pushBack [_pts#(_end+1),_pts#(_end+1) getDir _endPt];
            };
            _array
        };
        
        _crate setVariable ['Deployed',true,true];
        
        // gather all the points we could use
        private _airfieldId = [_crate] call ITW_AirfieldBoxInRange;
        private _cfg = (configFile >> "CfgWorlds" >> worldName);
        if (_airfieldId > 0) then {
            _cfg = ("true" configClasses (_cfg >> "SecondaryAirports"))#(_airfieldId-1);
        };
        private _ils = getArray (_cfg >> "ilsPosition");
        private _taxiOut= (getArray (_cfg >> "ilsTaxiOff")) call _toArrayFN;
        private _taxiIn = (getArray (_cfg >> "ilsTaxiIn" )) call _toArrayFN;
        private _data = [];
        _data pushBack [_ils,_ils getDir (_taxiOut#0)];
        _data = _data + ([_taxiOut,_ils,true] call _ptsToDataFn);
        _data = _data + ([_taxiIn,_ils] call _ptsToDataFn);
        
        // find the closest point
        private _distMin = 1e5;
        private _closestPt = [0,0];
        private _closestDir = 0;
        {
            _x params ["_pt","_dir"];
            private _dist = _crate distance _pt;
            if (_dist < _distMin) then {
                _distMin = _dist;
                _closestPt = _pt;
                _closestDir = _dir;
            };
        } forEach _data;
        _closestPt pushBack 0;
        
        ITW_airfieldRepair = [_closestPt,50];
        ITW_airfieldPos = _closestPt;  publicVariable "ITW_airfieldPos";
        ITW_airfieldDir = _closestDir;  publicVariable "ITW_airfieldDir";
        ITW_airfieldRepair call ITW_vehRepairPoint;
        ITW_Garages pushback ITW_airfieldPos;
        [_closestPt,_closestDir] remoteExec ["ITW_AirfieldCircleMP",0,"AirCircle"];
    } else {
        _crate = ITW_airfieldBase;
        if !(ITW_airfieldRepair isEqualTo []) then {  
            ITW_airfieldRepair call ITW_vehRepairPointRemove;
            ITW_airfieldRepair = [];
        };
        if !(ITW_airfieldPos isEqualTo []) then {   
            ITW_Garages = ITW_Garages - [ITW_airfieldPos];
            ITW_airfieldPos = [];  publicVariable "ITW_airfieldPos";
        };
        [] remoteExec ["ITW_AirfieldCircleMP",0,"AirCircle"];
        [] remoteExec ["ITW_AirfieldMarkerUpdater",0,"AirMrkr"];
        _crate setVariable ['Deployed',false,true];
    };
};

ITW_AirfieldCircleMP = {
    // call on all clients
    params ["_pos","_dir"]; // pos [] to delete
    if (!hasInterface) exitWith {};
    if (isNil "ITW_AirfieldCircle") then {ITW_AirfieldCircle = objNull};
    if (!isNull ITW_AirfieldCircle) then {deleteVehicle ITW_AirfieldCircle};
    if (isNil "_pos") then {
        ITW_AirfieldCircle = objNull;
        deleteMarkerLocal AIRFIELD_MARKER;
        deleteMarkerLocal AIRFIELD_CIRCLE_MARKER;
    } else {
        ITW_AirfieldCircle = createSimpleObject ["a3\Modules_F_Curator\Multiplayer\surfaceSectorUnknown100m.p3d", _pos, true]; 
        ITW_AirfieldCircle setObjectScale 0.5;
    };
};

ITW_AirfieldLoad = {
    params ["_airbaseData"];
    if (count _airbaseData == 2) then {
        _airbaseData params ["_cratePos","_isDeployed"];
        if !(_cratePos isEqualTo []) then {
            [_cratePos] call ITW_AirfieldSpawnCrate;
            [ITW_airfieldBase,_isDeployed] call ITW_AirfieldDeploy;
        };
    };
};

ITW_AirfieldSave = {
    private _airbaseData = 
        if (isNull ITW_airfieldBase) then {[]}
        else {[getPosATL ITW_airfieldBase,ITW_airfieldBase getVariable ['Deployed',false]]};
    _airbaseData
};

["ITW_AirfieldFixIlsTaxi"] call SKL_fnc_CompileFinal;
["ITW_AirfieldSpawnCrate"] call SKL_fnc_CompileFinal;
["ITW_AirfieldDelete"] call SKL_fnc_CompileFinal;
["ITW_AirfieldBoxMP"] call SKL_fnc_CompileFinal;
["ITW_AirfieldBoxLoadMP"] call SKL_fnc_CompileFinal;
["ITW_AirfieldBoxUnloadMP"] call SKL_fnc_CompileFinal;
["ITW_AirfieldMarkerUpdater"] call SKL_fnc_CompileFinal;
["ITW_AirfieldBoxInRange"] call SKL_fnc_CompileFinal;
["ITW_AirfieldDeploy"] call SKL_fnc_CompileFinal;
["ITW_AirfieldCircleMP"] call SKL_fnc_CompileFinal;
["ITW_AirfieldLoad"] call SKL_fnc_CompileFinal;
["ITW_AirfieldSave"] call SKL_fnc_CompileFinal;