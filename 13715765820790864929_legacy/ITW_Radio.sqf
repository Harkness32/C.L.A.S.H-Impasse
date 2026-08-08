#include "defines.hpp"
#include "defines_gui.hpp"

ITW_RadioInit = {
    // called on all clients
    if (isServer) then {
        // supports availability
        missionNamespace setVariable ["casBomb",count va_pPlaneClassesAttack + count va_pPlaneClassesDual > 0,true];
        missionNamespace setVariable ["casHeli",count va_pHeliClassesAttack + count va_pHeliClassesDual > 0,true];
        SKL_CASPlane = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_CASPlane.sqf";
        SKL_CASHeli = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_CASHeli.sqf";
    };
    
    if (hasInterface) then {
        [] call ITW_RadioShowFriendlies;
        [] spawn {
            scriptName "ITW_RadioMenus";
            // Add radio menu items
            private _items = [
                "lifeSignScan",
                "showFriendlies",
                "supports",
                "transports",
                "commander",
                "sideops"
            ];
            private _ftId = -1;
            private _asmtId = -1;
            private _landId = -1;
            private _ids = [];
            _ids resize [count _items,-1];
            while {true} do {
                while {LV_PAUSE} do {sleep 5};
                if (CONSCIOUS(player)) then {
                    if (_ids#0 == -1) then {
                        {
                            _ids set [_forEachIndex,[player, _x, nil, nil, ""] call BIS_fnc_addCommMenuItem];
                        } forEach _items;
                    };
                } else {
                    // all radio items disappear if you are unconscious
                    if (_ids#0 != -1) then {
                        {[player, _x ] call BIS_fnc_removeCommMenuItem; _ids set [_forEachIndex,-1]} forEach _ids;
                    };
                };
                sleep 5;
            };
        };
    };
        
    SKL_HE_NEW_HELI_FN = ITW_RadioHeliTransport;
    SKL_TE_NEW_TRUCK_FN = ITW_RadioTruckTransport;
    SKL_TS_NEW_TRUCK_FN = ITW_RadioTruckService;
    
    // Get faction correct stuff        
    private _unitTypes = [ITW_PlayerFaction,["Crewman"],false,call FACTION_UNIT_FALLBACK_ROLE_REQ] call FactionUnits;
    if (_unitTypes isEqualTo []) then {_unitTypes = [ITW_PlayerFaction,["Rifleman"]] call FactionUnits};
    ITW_RADIO_PILOTS = _unitTypes;
    
    private _helis = va_pHeliClasses call ITW_RadioHeliCheck;
    //if (_helis isEqualTo []) then {_helis = va_cHeliClasses call ITW_RadioHeliCheck};
    if (_helis isEqualTo []) then {_helis = va_eHeliClasses call ITW_RadioHeliCheck};
    if (_helis isEqualTo []) then {_helis = ["B_Heli_Light_01_F"]};
    ITW_RADIO_HELIS = _helis;
    
    if (isNil "SKL_LocationSelection") then {SKL_LocationSelection = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_LocationSelection.sqf"};
};
  
ITW_RadioHeliCheck = {
    private _helis = [];
    {
        private _vehCfgName = if (typeName _x == "ARRAY") then {_x#0} else {_x};
        private _totalSeats = [_vehCfgName, true] call BIS_fnc_crewCount; // Number of total seats: crew + cargo/passengers
        private _crewSeats = [_vehCfgName, false] call BIS_fnc_crewCount; // Number of crew seats only
        private _cargoSeats = _totalSeats - _crewSeats; // Number of total cargo/passenger seats      
        if (_cargoSeats >= 4) then {
            _helis pushBack _x;
        };
    } forEach _this;
    _helis
};

ITW_RadioBringAiMenu = {
    // returns array of the teammate ai selected; or 0 if canceled.  Only considers ai not in a player vehicle
    private _bringUnits = [];
    private _aiUnits = units group player select {!isPlayer _x && {crew vehicle _x findIf {isPlayer _x} == -1}}; // ai in our group not in any player's vehicle
    if !(_aiUnits isEqualTo []) then {
        ITW_RFTAnswer = 0;
        ITW_RFTMenu1 = [
            [localize "STR_ITW_RADIO_BringAI", true],
            [localize "STR_ITW_COMMON_No"            , [2], "", -5, [["expression", "ITW_RFTAnswer = 0"]], "1", "1"],                
            [localize "STR_ITW_RADIO_BringAiAll"     , [3], "", -5, [["expression","ITW_RFTAnswer = 1"]], "1", "IsLeader"],
            [localize "STR_ITW_RADIO_BringAiNearby"  , [4], "", -5, [["expression","ITW_RFTAnswer = 2"]], "1", "1"],
            [localize "STR_ITW_RADIO_BringAiOnFoot"  , [5], "", -5, [["expression","ITW_RFTAnswer = 3"]], "1", "IsLeader"],
            [localize "STR_ITW_RADIO_BringAiSelected", [6], "", -5, [["expression","ITW_RFTAnswer = 4"]], "1", "IsLeader"]
        ];
        showCommandingMenu "#USER:ITW_RFTMenu1";
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};   
        if (ITW_RFTAnswer > 0) then {
            switch (ITW_RFTAnswer) do {
                case 1: { // all of them
                    // don't bring ai in vehicles with other players in them
                    private _playerVehs = [];
                    {
                        private _veh = vehicle _x;
                        if (_veh != _x) then {_playerVehs pushBackUnique _veh};
                    } forEach (allPlayers - [player]);
                    _bringUnits = _aiUnits select {!(vehicle _x in _playerVehs)}; 
                };
                case 2: { // those nearby
                    _bringUnits = _aiUnits select {_x distance player < 200}; 
                };
                case 3: { // those not in vehicles
                    _bringUnits = _aiUnits select {vehicle _x isEqualTo _x}; 
                };
                case 4: { // those not in vehicles
                    private _teammates = units group player select {!isPlayer _x};
                    if (count _teammates == 0) exitWith {};
                    while {true} do {
                        ITW_TA_Index = -1;
                        ITW_RADIO_MENU = [[localize "STR_ITW_RADIO_SelectTeammates", false]];
                        ITW_RADIO_MENU pushBack [localize "STR_ITW_RADIO_Go",[34], "", -5, [["expression","ITW_TA_Index = -3"]], "1", "1"];
                        {
                            private _selected = if (_x in _bringUnits) then {"* "} else {"  "};
                            ITW_RADIO_MENU pushBack [_selected + name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
                        } forEach _teammates;
                        ITW_RADIO_MENU pushBack [localize "STR_ITW_RADIO_AllTeammates",[30], "", -5, [["expression","ITW_TA_Index = -2"]], "1", "1"];
                        ITW_RADIO_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
                        showCommandingMenu "#USER:ITW_RADIO_MENU";
                        waitUntil {commandingMenu == ""};
                        if (ITW_TA_Index == -1) exitWith {_bringUnits = 0};
                        if (ITW_TA_Index == -2) exitWith {_bringUnits = _teammates};
                        if (ITW_TA_Index == -3) exitWith {}; // GO
                        private _unit = _teammates#ITW_TA_Index;
                        ITW_RADIO_MENU = nil;
                        if (_unit in _bringUnits) then {_bringUnits = _bringUnits - [_unit]} else {_bringUnits pushBack _unit};
                    };
                };
            };
            
            {
                _x setDamage 0;
                _x call ITW_FncAceHeal;
                [_x, false] remoteExec ["setUnconscious",_x];
                [_x, false] remoteExec ["setCaptive",_x];
            } forEach _bringUnits;
        };
    };
    _bringUnits
};

ITW_RadioFastTravel = {
    if (vehicle player getVariable ["tgtActionId",-1] != -1) exitWith {"itw" cutText [localize "STR_ITW_RADIO_NoFtDelivery","PLAIN"]};
    private _bringUnits = call ITW_RadioBringAiMenu;
    if (_bringUnits isEqualTo 0) exitWith {};
    private _pos = [];
    private _travelPos = [];
    private _travelDir = 0;
    private ["_flag"]; // if _flag not nil, then obj is nearest & < 800m
    private _isHALO = false;
    private _isRallyPointAvailable = vehicle player == player && {ITW_RallyPointBase getVariable ['Deployed',false] && {ITW_ParamFastTravel > 0}};
    private _msg = switch (ITW_ParamFastTravel) do {
        case 0: {localize "STR_ITW_RADIO_FtSelect0"};
        case 1: {localize "STR_ITW_RADIO_FtSelect1"};
        default {localize "STR_ITW_RADIO_FtSelect2"};
    };
    if (ITW_AirfieldBase getVariable ['Deployed',false]) then {
        _msg = _msg + localize "STR_ITW_RADIO_OrAirfield";
    };
    if (_isRallyPointAvailable) then {
        _msg = _msg + localize "STR_ITW_RADIO_OrRallyPoint";
    };
    private _msgHeader = localize "STR_ITW_RADIO_Ft";
    
    while {_travelPos isEqualTo []} do {
        private _objNoFtSize = 200;
        private _baseFtSize = 800;
        _pos = [_msgHeader + _msg,false,true,_objNoFtSize,_baseFtSize] call ITW_RadioChooseOnMap;
        if (_pos isEqualTo []) exitWith {_travelPos = [];};
        
        private _isEnemyControlled = false;
        private _base = [_pos,ITW_OWNER_FRIENDLY,true,vehicle player == player] call ITW_BaseNearest;
        private _baseDist = (_base call ITW_BaseGetCenterPt) distance _pos;
        if (_baseDist < _baseFtSize) then {
            [_base] call ITW_BaseEnsure;
            _travelPos = _base call ITW_BaseGetPlayerFastTravelPt;
            _travelDir = (_base call ITW_BaseGetDir) - 90;
        };

        // check rally point, click distance is less for rally point than a base
        if (_travelPos isEqualTo [] && {_isRallyPointAvailable && {_pos distance ITW_RallyPointBase < (_baseFtSize/2)}}) then { 
            _travelPos = getPosATL ITW_RallyPointBase getPos [5,0];
            _travelDir = 0;
        };
        
        // check if we clicked near a friendly flag, if we found a base choose the closer of flag or base
        if (ITW_ParamFastTravel > 0) then {
            private _obj = [_pos,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest;
            private _objPos = _obj#ITW_OBJ_POS;
            private _objSize = _obj#ITW_OBJ_SIZE;
            private _objDist = _objPos distance _pos;
            if (_objPos distance _pos <= (_objSize + 200) && {_objDist < _baseDist}) then {
                private _flag = _obj#ITW_OBJ_FLAG;
                private _captured = flagTexture _flag == ITW_PlayerFlag && {flagAnimationPhase _flag > 0.95};
                if (_captured) then {
                    _travelPos = _objPos getPos [3,180];
                } else {
                    if (ITW_ParamFastTravel >= 2 && {_objPos distance _pos < (_objSize + _objNoFtSize)}) then {
                        // oops, clicked too close to an enemy held objective
                        _isEnemyControlled = ITW_ParamFastTravel < 5;
                    };
                };
            };
            if (ITW_ParamFastTravel >= 2 && {_travelPos isEqualTo [] && {!_isEnemyControlled}}) then {
                _travelPos = _pos;
                _travelDir = _pos getDir _objPos;
                _isHALO = true;
            };
        };
        
        if (_travelPos isEqualTo []) then {
            if (_isEnemyControlled) then {
                _msgHeader = localize "STR_ITW_RADIO_FtOnEnemy";
            } else {
                _msgHeader = localize "STR_ITW_RADIO_FtInvalid";
            };
        };
    };
    hintSilent "";
    
    if (_travelPos isNotEqualTo []) then {
        if (!_isHalo) then {
            // travel to BASE or FRIENDLY FLAG
            private _blacklist = ["water"];
            private _units = [player] + _bringUnits;
            _units = _units apply {vehicle _x}; // switch to vehicles
            _units = _units arrayIntersect _units; // remove duplicates
            {           
                private _object = _x;
                if (_object isKindOf "CAManBase") then {
                    _object setDir _travelDir;
                    private _pos = _travelPos;
                    if (_forEachIndex > 0) then {
                        _pos = _travelPos getPos [0.5 + random 1,random 360];
                        _pos set [2,_travelPos#2]; // need to work with warships
                    };
                    _object setPosATL _pos;
                } else {
                    private _ftPos = [0,0,0];
                    private _range = 200;
                    private _size = (sizeOf typeOf _object) + 1;
                    while {count _ftPos == 3} do {
                        _ftPos = [_travelPos,100,_range,_size,0,0,0,_blacklist,[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos; 
                        _range = _range + 50;
                    };
                    _blacklist pushBack [_ftPos,_size];
                    _ftPos pushBack 0;
                    _object allowDamage false;
                    _object setDir (_ftPos getDir _travelPos);
                    private _elevation = getTerrainHeightASL _ftPos; 
                    if (_object isKindOf "Ship" && {_elevation < 1}) then {
                        _ftPos set [2,-_elevation];
                    };
                    _object setPosATL _ftPos;
                    _object spawn {sleep 8;_this allowDamage true};
                };
            } forEach _units;
        } else {
            // Halo Drop (2), Heli/Plane (3), or Instant (4)
            private _bringAI = [];
            private _bringVeh = [];
            {
                private _ai = _x;  
                if (vehicle _ai == _ai) then {
                    _bringAI pushBack _ai;
                } else {
                    _bringVeh pushBackUnique vehicle _ai;
                };
            } forEach _bringUnits;
            // use para drop to un-captured territory
            private _veh = vehicle player;
            private _dropPos = +_travelPos;
            _dropPos set [2,if (_veh == player) then {1000} else {400}];
            if (ITW_ParamFastTravel in [3,6] && {_veh == player}) then {
                //// Heli / Plane ////
                // ITW_fastTravelAircraft holds [_ftPos,_veh] for transport plane/heli
                if (isNil "ITW_fastTravelAircraft") then {ITW_fastTravelAircraft = []; publicVariable "ITW_fastTravelAircraft"};
                ITW_fastTravelAircraft = ITW_fastTravelAircraft select {!isNull (_x#1)};
                private _planeInfo = ITW_fastTravelAircraft select {_dropPos distance2D (_x#0) < 1000};
                private _veh = objNull;
                if (_planeInfo isEqualTo []) then {
                    // create a transport aircraft
                    private _firstNonEmpty = {
                        private _array = [];
                        {
                            _array = _x;
                            if (_array isNotEqualTo []) exitWith {};
                        } forEach _this;
                        _array
                    };
                    private _vehTypes = [va_pPlaneClassesTransport,va_pHeliClassesTransport,va_pHeliDualAsTransport,va_cPlaneClassesTransportFallback,va_cHeliClassesTransportFallback,va_pPlaneClassesDual,va_pHeliClassesDual] call _firstNonEmpty;
                    
                    if (_vehTypes isNotEqualTo []) then {
                        #define ITW_HELI_HGT 800
                        _vehType = selectRandom _vehTypes; 
                        private _texture = false;
                        private _anim = false;     
                        if (typeName _vehType == "ARRAY") then {
                            _texture = _vehType#1;
                            if (count _vehType > 2) then {_anim = _vehType#2};
                            _vehType = _vehType#0;
                        };
                        _spawnPos = getPosATL player getPos [400,_dropPos getDir player];
                        _spawnPos set [2,ITW_HELI_HGT];
                        private _dir = _spawnPos getDir _dropPos;
                        _veh = createVehicle [_vehType, _spawnPos, [], 0, "FLY"];
                        _veh setDir _dir;
                        _veh setPos _spawnPos; // not ATL since it needs to work over water
                        createVehicleCrew _veh;	
                        private _group = createGroup [ITW_PlayerSide,false];
                        (crew _veh) joinSilent _group;	
                        _group deleteGroupWhenEmpty true;
                        sleep 0.05;
                        [_veh,_texture,_anim] call BIS_fnc_initVehicle;
                        waitUntil {!isNull (currentPilot _veh)};
                        _veh setVariable ["BIS_noCoreConversations", true];
                        // move pilot to his own group so we can disable autocombat
                        private _driver = driver _veh;
                        private _driverGroup = createGroup [ITW_PlayerSide, false];
                        [_driver] joinSilent _driverGroup;
                        _driver disableAI "TARGET";
                        _driver disableAI "AUTOTARGET";
                        _driver disableAI "AUTOCOMBAT";
                        _driver disableAI "SUPPRESSION";
                        _driver disableAI "MINEDETECTION";
                        _driver disableAI "TEAMSWITCH";
                        _driver setCombatMode "BLUE";
                        _driver setBehaviour "CARELESS";
                        _veh flyInHeightASL [ITW_HELI_HGT, ITW_HELI_HGT, ITW_HELI_HGT];
                        // allow gunners to engage if they can
                        _group setBehaviour "AWARE";
                        _group setCombatMode "YELLOW";
                        private _pos = _dropPos getPos [300,_dir];
                        _pos set [2,ITW_HELI_HGT];
                        ITW_DELETE_WAYPOINTS(_driverGroup);
                        private _wp = _driverGroup addWaypoint [_pos, 0];
                        _wp setWaypointBehaviour "CARELESS";
                        _wp setWaypointSpeed "FULL";
                        _wp setWaypointCombatMode "BLUE";
                        _wp setWaypointType "MOVE"; 
                        _wp setWaypointCompletionRadius 300;
                        
                        private _configMaxSpeed = getNumber (configFile >> "CfgVehicles" >> typeOf _veh >> "maxSpeed");
                        _veh forceSpeed (_configMaxSpeed / 3.6); 
                        
                        [_veh,_driverGroup,_group] spawn {
                            params ["_veh","_driverGroup","_group"];
                            scriptName "ITW_FastTravelAircraft";
                            private _startPos = getPosATL _veh;
                            private _timeout = time + 10;
                            waitUntil {sleep 1; !alive _veh || {time > _timeout || {crew _veh findIf {isPlayer _x} >= 0}}}; // wait for players to board
                            waitUntil {sleep 1; !alive _veh || {crew _veh findIf {isPlayer _x}== -1}}; // wait for players to eject
                            _veh forceSpeed -1;
                            driver _veh enableAI "MINEDETECTION";
                            ITW_DELETE_WAYPOINTS(_driverGroup);
                            private _wp = _driverGroup addWaypoint [_startPos, 0];
                            _wp setWaypointBehaviour "CARELESS";
                            _wp setWaypointSpeed "FULL";
                            _wp setWaypointCombatMode "BLUE";
                            _wp setWaypointType "MOVE"; 
                            _wp setWaypointCompletionRadius 150;
                            _timeout = time + 60;
                            waitUntil {sleep 1; time > _timeout || {!alive _veh || {_veh distance2D _startPos < 200}}};
                            deleteVehicleCrew _veh;
                            deleteGroup _driverGroup;
                            deleteGroup _group;
                            deleteVehicle _veh;
                        };
                    } else {
                        hint localize "STR_ITW_RADIO_FtNoAircraft";
                    };
                } else {
                    _dropPos = _planeInfo#0#0;
                    _veh = _planeInfo#0#1;
                };
                
                if !(isNull _veh) then {
                    private _bringAiInfantry = _bringAI select {_x == vehicle _x};
                    private _emptySeats = (_veh emptyPositions "") - 1 - count _bringAiInfantry;
                    // Uncomment once arma main branch is at 2.22 and I have tested this
                    //if (productVersion#3 >= 222) then {
                    //    player moveInAny [_veh,["GUNNER","TURRET","COMMANDER","CARGO"]];
                    //    {_x moveInAny [_veh,["CARGO","COMMANDER","TURRET","GUNNER"]]} forEach _bringAiInfantry;
                    //} else {
                        player moveInAny _veh;
                        {_x moveInAny _veh} forEach _bringAiInfantry;;
                    //};
                    _planeInfo = [_dropPos,_veh];
                    if (_emptySeats > 0) then {
                        if !(_planeInfo in ITW_fastTravelAircraft) then {
                            ITW_fastTravelAircraft pushBackUnique _planeInfo;
                            publicVariable "ITW_fastTravelAircraft";
                        };
                    } else {
                        if (_planeInfo in ITW_fastTravelAircraft) then {
                            ITW_fastTravelAircraft = ITW_fastTravelAircraft - [_planeInfo];
                            publicVariable "ITW_fastTravelAircraft";
                        };
                    };
                    // private _maxSpeed = getNumber (configFile >> "CfgVehicles" >> typeOf _veh >> "maxSpeed");
                    // private _ejectDist = (_maxSpeed max 200);
                    waitUntil {sleep 0.5; vehicle player != _veh || {!alive _veh || {!alive player || {_veh distance2D _dropPos < ((speed _veh) max 200) || {ITW_ELEVATION_LT(player,10)}}}}};
                    if (vehicle player != _veh || {!alive player || {ITW_ELEVATION_LT(player,10)}}) then {_dropPos = []}; // cancel FT
                    if (_dropPos isNotEqualTo []) then {
                        // change drop position to where the aircraft is
                        _dropPos = getPosATL _veh;
                        _dropPos set [2,_dropPos#2 - 5];
                        sleep 0.5;
                        player setVariable ["itwIgnoreGetOut",true];
                        moveOut player;
                        player setDir _travelDir;
                        sleep 0.5;
                        player setVariable ["itwIgnoreGetOut",false];
                        if (_bringAiInfantry isNotEqualTo []) then {
                            private _pos = ITW_Bases#0#ITW_BASE_A_SPAWN;
                            {_x setPosATL _pos} forEach _bringAiInfantry;
                        };
                    };
                    // remove planeinfo if no other players in aircraft
                    if (_planeInfo in ITW_fastTravelAircraft && {crew _veh findIf {isPlayer _x} == -1}) then {
                        ITW_fastTravelAircraft = ITW_fastTravelAircraft - [_planeInfo];
                        ITW_fastTravelAircraft = ITW_fastTravelAircraft select {!isNull (_x#1)};
                        publicVariable "ITW_fastTravelAircraft";
                    };
                };
            };
            
            if (_dropPos isNotEqualTo []) then {
                [player,_dropPos,_travelDir,_bringAI,_bringVeh] call ITW_RadioFastTravelHalo;
            };
        };
    };
};

ITW_RadioFastTravelHalo = {
    params ["_player","_dropPos","_travelDir","_bringAI","_bringVeh"];
    private _veh = vehicle _player;
    if (ITW_ParamFastTravel in [4,7]) then {
        //// Instant ////
        _dropPos set [2,0];
        _veh setDir _travelDir;
        _veh setPosATL _dropPos;
    } else {
        //// Halo Drop ////
        _veh setDir _travelDir;
        _veh setPosATL _dropPos;
        YIELD_CPU;
        private _timeout = time + 3;
        waitUntil{(getPosATL _veh)#2 > 100 || {time > _timeout}}; // sometimes on server, veh isn't actually moved before the waitUntil's below are triggered
        sleep 0.2; // give a little more time to get into the air (somehow, the previous
        if (_veh == _player) then {
            waitUntil {((getPosATL _veh)#2) < 60 || {((getPosASL _veh)#2) < 60}}; 
            [_veh] spawn BIS_fnc_halo; 
        } else {
            waitUntil {((getPosATL _veh)#2) < 100 || {((getPosASL _veh)#2) < 100}};
            [_veh] spawn ITW_FncVehicleHalo;
        };
    };
#ifdef AI_PARACHUTE_WORKING
    private _pos = getPosATL _veh;
    private _dir = getDir _veh - 180;
    {
        _pos = _pos getPos [20,_dir];
        _pos set [2,60];
        _x setPosATL _pos;
        [_x] call ITW_FncAiHalo;
    } forEach _bringAI; 
    {
        _pos = _pos getPos [40,_dir];
        _pos set [2,150];
        _x setPosATL _pos;
        [_x] spawn ITW_FncVehicleHalo;
    } forEach _bringVeh;
#else
    // after parachuting ai would often never move again
    // enableai "move" and "path" were set to true, if placed in a vehicle, the air would drive, but would not walk again
    // fix is to never parachute teammates
    waitUntil {isTouchingGround _veh || {(getPosATL _veh)#2 < 2}};
    private _pos = getPosATL _veh;
    private _dir = getDir _veh - 180;
    {
        _pos = _pos getPos [20,_dir];
        _x allowDamage false;
        _x setPosATL _pos;
    } forEach _bringAI; 
    {
        _pos = _pos getPos [40,_dir];
        _x allowDamage false;
        _x setPosATL _pos;
    } forEach _bringVeh;

    sleep 1;
    _bringAI apply {_x allowDamage true};
    _bringVeh apply {_x allowDamage true};
#endif
};

ITW_RadioVehicleDrop = {
    params ["_pos"];
    scriptName "ITW_RadioVehicleDrop";
    params ["_pos"];
    private ["_vehs","_alt"];
    if (getTerrainHeightASL _pos <= -1) then {
        _alt = 30;
        _vehs = va_pShipClasses;
        //if (_vehs isEqualTo []) then { _vehs = va_cShipClasses};
        if (_vehs isEqualTo []) then { _vehs = va_eShipClasses};
        if (_vehs isEqualTo []) then { _vehs = ["C_Rubberboat"]};
    } else {
        _alt = 100;
        _vehs = va_pCarClassesTransport;
        if (_vehs isEqualTo []) then { _vehs = va_pCarClasses};
        if (_vehs isEqualTo []) then { _vehs = va_eCarClassesTransport};
        //if (_vehs isEqualTo []) then { _vehs = va_cCarClasses};
        if (_vehs isEqualTo []) then { _vehs = va_pQuadBikeClasses};
        //if (_vehs isEqualTo []) then { _vehs = va_cQuadBikeClasses};
        if (_vehs isEqualTo []) then { _vehs = va_eQuadBikeClasses};
        if (_vehs isEqualTo []) then { _vehs = va_pApcClasses};
        if (_vehs isEqualTo []) then { _vehs = ["B_G_Offroad_01_F"]};
    };
    private _vehTypeTxtr = selectRandom _vehs;
    private _vehType = if (typeName _vehTypeTxtr == "ARRAY") then {_vehTypeTxtr#0} else {_vehTypeTxtr};
    
    private _vehDesc = getText (configFile >> "cfgVehicles" >> _vehType >> "displayName");
    if (isNil "_vehDesc" || {_vehDesc == ""}) then {_vehDesc = localize "STR_ITW_RADIO_Vehicle"};
    ["HQ",format [localize "STR_ITW_RADIO_DispatchedFmt",_vehDesc]] call ITW_RadioSendMessage;
    ["SentRequestAcknowledgedTransport"] call ITW_RadioPlayMessage;
    sleep 20;
    // add a jet sound
    private _hp = "Land_HelipadEmpty_F" createVehicle _pos;
    sleep 0.5;
    _soundFlyover = ["BattlefieldJet1","BattlefieldJet2"] call bis_fnc_selectrandom;
    [_hp,_soundFlyover,"say3d"] remoteExec ["bis_fnc_sayMessage",0];
    sleep 3;
    _pos set [2,300];
    private _veh = [_vehTypeTxtr,_pos] call ITW_VehCreateVehicle;
    _veh allowDamage false;
    private _dir = random 360;
    _veh setDir _dir;
    _veh setPosATL _pos;

    // add parachute at correct altitude 
    waitUntil {((getPosATL _veh) select 2) < 100}; 
    
    private _objectPos = getPosATL _veh;
    private _para = createvehicle ["B_Parachute_02_F",_objectPos,[],0,"none"];
    _veh attachto [_para,[0,0,1]];
    _para setDir _dir;
    _para setPosATL _objectPos;
    _para setvelocity [0,0,-1];
    
    private _timeout = time + 30;
    waitUntil {sleep 1;isNull _para || isTouchingGround _veh || time > _timeout};
    deleteVehicle _para;
    deleteVehicle _hp;
    sleep 10;
    _pos = getPosATL _veh;
    _pos set [2,0.05];
    if (surfaceIsWater _pos) then {
        _veh setPosASLW _pos;
        _veh setVectorUp [0,0,1];
    } else {
        _veh setPosATL _pos;
        _veh setVectorUp surfaceNormal _pos;
    };
    sleep 5;
    _veh allowDamage true;
    
    // setup vehicle for other systems
    _veh addItemCargoGlobal ["ToolKit",1];
    [_veh] remoteExec ["ITW_VehSpawnMP",0,true];

    // set default value to allowing allies in crew seats
    private _blockAllyInCrewSeats = true;
    private _vehType = typeOf _veh;
    if (_vehType isKindOf "Car") then {
        // cars (not aps) allow allies in turrets		
        _edSubcat = ((configFile >> "CfgVehicles" >> _vehType >> "editorSubcategory") call BIS_fnc_getCfgData);
        if (!isNil "_edSubcat") then {
            if !(["apc", _edSubcat, false] call BIS_fnc_inString) then {
                _blockAllyInCrewSeats = false;
            };
        };
    };
    if (_blockAllyInCrewSeats == false) then {_veh setVariable ["ITW_BlockAllyCrew",false,true]};
};
    
ITW_RadioSupplyDrop = {
    params ["_pos"];
    scriptName "ITW_RadioSupplyDrop";
    params ["_pos"];
    private _vehType = "B_supplyCrate_F";
    ["HQ",localize "STR_ITW_RADIO_SuppliesOnRoute"] call ITW_RadioSendMessage;
    ["SentRequestAcknowledgedSGSupplyDrop"] call ITW_RadioPlayMessage;
    _pos set [2,300];
    sleep 20;
    // add a jet sound
    private _hp = "Land_HelipadEmpty_F" createVehicle _pos;
    sleep 0.5;
    _soundFlyover = ["BattlefieldJet1","BattlefieldJet2"] call bis_fnc_selectrandom;
    [_hp,_soundFlyover,"say3d"] remoteExec ["bis_fnc_sayMessage",0];
    sleep 3;
    private _ammoBox = _vehType createVehicle _pos;
    _ammoBox setPosATL _pos;
    _ammoBox allowDamage false;
    // add parachute at correct altitude 
    waitUntil {((getPosATL _ammoBox) select 2) < 80}; 
    
    _pos = getPosATL _ammoBox;
    private _para = createvehicle ["B_Parachute_02_F",_pos,[],0,"none"];
    _ammoBox attachto [_para,[0,0,1]];
    _para setPosATL _pos;
    _para setdir direction _ammoBox;
    _para setvelocity [0,0,-1];
    private _smoke = "SmokeshellRed" createVehicle getPosATL _ammoBox;
    _smoke attachTo [_ammoBox,[0,0,0]];
    private _chem = "Chemlight_yellow_Infinite" createVehicle getPosATL _ammoBox;
    _chem attachTo [_ammoBox,[0,0,0]];
    
    clearItemCargoGlobal _ammoBox;
    clearWeaponCargoGlobal _ammoBox;
    clearBackpackCargoGlobal _ammoBox;
    clearMagazineCargoGlobal _ammoBox;
    _ammoBox remoteExec ["CustomArsenal_AddVAs",0,true];
    
    private _timeout = time + 30;
    waitUntil {sleep 1;isNull _para || isTouchingGround _ammoBox || time > _timeout};
    deleteVehicle _para;
    deleteVehicle _smoke;
    _smoke = "SmokeshellRed" createVehicle getPosATL _ammoBox;
    _smoke attachTo [_ammoBox,[0,0,0]];
    deleteVehicle _hp;
    [_ammoBox] remoteExec ["ITW_RadioSupplyDropMoveMP",0,_ammoBox];
    sleep 10;
    _ammoBox allowDamage true;
};

ITW_RadioSupplyDropMoveMP = {
    params ["_crate"];
    if (!hasInterface) exitWith {};
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_RADIO_CarryCrate"+"</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            _crate attachTo [_caller, [0, 2, 1]];
            _caller setAnimSpeedCoef 0.5;
            _caller playAction "PlayerStand";
            _caller action ["SwitchWeapon",_caller,_caller,-1];
            
            player addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Drop"+"</t>", {
                params ["_player", "_caller", "_actionId", "_crate"];
                _player setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                _player setAnimSpeedCoef 1;
                _player removeAction _actionId;
            },_crate,10,false,true,"",""];
        },nil,1.5,false,true,"","(isPlayer _this) && {isNull attachedTo _target}",4];

    date call BIS_fnc_sunriseSunsetTime params ["_sunrise","_sunset"];
    date params ["_y","_m","_d","_hour","_min"];
    _hour = _hour + (_min/60);
    if (_hour < _sunrise || {_hour > _sunset}) then {
        _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_RADIO_CreateRemoveLight"+"</t>", {
                params ["_crate", "_caller", "_actionId", "_arguments"];
                _crate removeAction _actionId;
                {
                    if (_x isKindOf 'Chemlight_base') exitWith {deleteVehicle _x};
                } forEach attachedObjects _crate;
            },nil,1.5,false,true,"","(isPlayer _this) && {{_x isKindOf 'Chemlight_base'} count attachedObjects _target > 0}",4];    
    };
};

ITW_RadioFlareDrop = {
    params ["_pos"];
    private _text = format ["<t  size='1.25'>"+localize "STR_ITW_RADIO_FlareInbound"+"</t>",mapGridPosition _pos];  
    ["HQ",_text] call ITW_RadioSendMessage;
    ["SentRequestAcknowledgedSGArty"] call ITW_RadioPlayMessage;
        
    private _timeOut = time + 30; // delay before flares start
    waitUntil {sleep 1; time > _timeOut };
    
    private _aliveTime = 40; // how long flare are alive for            
    private _flareCnt = selectRandom [6,7,8];
    private _totalFlareTime = 1200; // flares run for 20 minutes
    
    private _flareSequence = []; // array of [_pos,_nextDropTime,_maxTime]
    private _flares = [[0,objNull]];        // array of [deathTime,flareObject]
    
    private _positionOrigin = _pos;
    private _startDropTime = time;
    private _flareMaxTime = 0;
    for "_i" from 1 to _flareCnt do {
        _pos = _positionOrigin getPos [_i * 35, random 360];
        _flareMaxTime = _startDropTime + _totalFlareTime; // 20 minutes
        _flareSequence pushBack [_pos,_startDropTime, _flareMaxTime];
        _startDropTime = _startDropTime + 5 + random 10;
    };         
    while {!(_flares isEqualTo [])} do {
        // create flares
        {
            private _maxTime = _x#2;
            if (time > _maxTime) then {continue}; // done this column of flares
            private _nextDropTime = _x#1;
            if (time < _nextDropTime) then {continue}; // not time for next drop
            private _pos = _x#0;
            private _fpos = _pos getPos [random 80,random 360];
            _fpos set [2,240];
            private _flare = createVehicle ["F_40mm_White_Infinite", _fpos, [], 0, "none"]; 
            _flare setVelocity [wind select 0, wind select 1, 30];
            [_flare,_aliveTime] remoteExec ["ITW_RadioFlareMP",0];
            _flares pushBack [time + _aliveTime,_flare];
            _x set [1,time + 25 + random 15]; // set the next drop time for this column
        } count _flareSequence;
        
        // delete flares
        {
            private _deleteTime = _x#0;
            if (time < _deleteTime) then {continue}; // not time yet
            private _flare = _x#1;
            deleteVehicle _flare;
            _flares deleteAt _forEachIndex;
        } forEachReversed _flares;
        
        sleep 2;
    };
};

ITW_RadioFlareMP = {
    // run on all clients
    if (!hasInterface) exitWith {};
    params ["_flare","_delay"];
    private _light = "#lightpoint" createVehicle (getPosASL _flare);
    _light attachTo [_flare, [0, 0, 0]];
    _light setLightColor [0.5, 0.5, 0.5];
    _light setLightAmbient [1, 1, 1];
    _light setLightIntensity 100000;
    _light setLightUseFlare true;
    _light setLightFlareSize 3;
    _light setLightFlareMaxDistance 600;
    _light setLightDayLight true;
    _light setLightAttenuation [4, 0, 0, 0.3, 200, 500];
    sleep (_delay-2);
    waitUntil {
        sleep 0.1;
        !alive _flare;
    };
    deletevehicle _light;
};

ITW_RadioChooseOnMap = {
    params [["_hint","",[""]],["_public",false],["_mapOnly",false],["_objIncrSize",-1],["_baseSize",-1]];
    private _pos = [0,0,0];
    if (!_mapOnly && !visibleMap) then {
        private _beg = eyePos player;
        private _end = _beg vectorAdd (player weaponDirection currentWeapon player vectorMultiply 3000);
        _pos = terrainIntersectAtASL [_beg,_end];
    };
    if !(_pos isEqualTo [0,0,0]) then {
        _pos set [2,0];
    } else {
        ITW_RadioPos = nil;
        
        // get user selected position   
        onMapSingleClick {
            if (!_alt && !_shift) then {
                ITW_RadioPos = _pos;
                openMap false; 
            };
        };         
        
        private _markers = [];
        private _drawMarker_FN = {
            params ["_pos","_size","_isFriendly"];
            private _mrkr = createMarkerLocal ["ft#"+str(count _markers),_pos];
            _mrkr setMarkerShapeLocal "ELLIPSE";
            _mrkr setMarkerSizeLocal [_size,_size];
            _mrkr setMarkerColorLocal (if (_isFriendly) then {"ColorWest"} else {"ColorEast"});
            _mrkr setMarkerBrushLocal (if (_isFriendly) then {"BDiagonal"} else {"FDiagonal"});
            _mrkr setMarkerAlphaLocal 0.7;
            _markers pushBack _mrkr;
        };
        
        if (_objIncrSize > 0) then {
            {
                private _obj = ITW_Objectives#_x;
                private _flag = _obj#ITW_OBJ_FLAG;
                private _flagAllTheWayUp = flagAnimationPhase _flag > 0.95;
                private _captured = flagTexture _flag == ITW_PlayerFlag;
                private _msize = (_obj#ITW_OBJ_SIZE) + _objIncrSize;
                [_obj#ITW_OBJ_POS,_msize,_flagAllTheWayUp && _captured] call _drawMarker_FN;
            } forEach (ITW_Zones#ITW_ZoneIndex);
        };
        if (_baseSize > 0) then {
            {
                private _obj = _x;
                if (_x#ITW_OBJ_OWNER == ITW_OWNER_FRIENDLY) then {
                    private _basePos = ITW_Bases#(_obj#ITW_OBJ_INDEX)#ITW_BASE_POS;
                    [_basePos,_baseSize,true] call _drawMarker_FN;
                };
            } forEach ITW_Objectives;
            if (ITW_AirfieldBase getVariable ["Deployed",false]) then {
                [getPosATL ITW_AirfieldBase,_baseSize,true] call _drawMarker_FN;
            };
            if (player == vehicle player) then {
                if (ITW_RallyPointBase getVariable ["Deployed",false]) then {
                    [getPosATL ITW_RallyPointBase,_baseSize/2,true] call _drawMarker_FN;
                };
                {
                    [_x#ITW_BASE_P_SPAWN,_baseSize,true] call _drawMarker_FN;
                } forEach (0 call ITW_WarshipGetBases);
            };
            {
                [_x#ITW_BASE_P_SPAWN,_baseSize,true] call _drawMarker_FN;
            } forEach (0 call ITW_FortificationGetBases);
        };
        
        showMap true; 
        openMap true;
        waitUntil {visibleMap};
        _hintTime = -100;
        while {visibleMap} do {
            if (time - _hintTime > 25) then {
                _hintTime = time;
                hintSilent _hint; 
            };
            YIELD_CPU;
        };
        onMapSingleClick "";
        hintSilent "";
        {deleteMarkerLocal _x} forEach _markers;
        if (isNil "ITW_RadioPos") then {ITW_RadioPos = []};
        if (_public) then {publicVariable "ITW_RadioPos"};
        _pos = ITW_RadioPos;
    };
    _pos
};

ITW_RadioLeaderRequest = {
    // called on requesting client
    if (isNil "ITW_REQ_LEADER_TIME") then {ITW_REQ_LEADER_TIME = 0};
    if (ITW_REQ_LEADER_TIME > time) exitWith {
        "itw" cutText ["<t size='3'>"+localize "STR_ITW_RADIO_LeaderCooldown"+"</t>","PLAIN",-1,true,true];
    };
    ITW_REQ_LEADER_TIME = time + 60; // only able to request every 60 seconds
    private _leader = leader player;
    if (player == _leader) exitWith {};
    if (isPlayer _leader) then {
        [player] remoteExec ["ITW_RadioLeaderAuthorize",_leader];
    } else {
        [[group player, player],"selectLeader",group player] call ITW_FncRemoteLocalGroup;
    };
};

ITW_RadioLeaderAuthorize = {
    // called on current leader client
    params ["_newLeader"];
    ITW_NewLeader = _newLeader;
    CreateDialog "ITWAuthorizationDisplay";
    ctrlSetText [ITW_DIALOG_TEXT1_ID, format ['$STR_ITW_RADIO_RelinquishLeadershipFmt',name _newLeader] ];
};

ITW_RadioLeaderRelinquish = {
    // called on current leader client
    private _units = units group player - [player];
    if (_units isEqualTo []) exitWith {
        "itw" cutText ["<t size='3'>"+localize "STR_ITW_RADIO_RelinquishNoUnits"+"</t>","PLAIN",-1,true,true];
    };
    ITW_NewLeaderUnits = _units;
    CreateDialog "ITWRelinquishDisplay";
    {      
        private _index = lbAdd [ITW_DIALOG_LISTBOX_ID, name _x];
        lbSetData [ITW_DIALOG_LISTBOX_ID, _index, str _forEachIndex];
    } forEach _units;
};

ITW_RadioLeaderProcess = {
    // called on current leader's client
    params ["_code"];
    private _newLeader = objNull;
    switch (_code) do {
        case 'ok': {_newLeader = ITW_NewLeader};
        case 'relinquish': {               
            if !(isNil "ITW_NewLeaderUnits") then {
                private _display = findDisplay ITW_DISPLAY_LIST_ID;
                private _indexes = lbSelection (_display displayCtrl ITW_DIALOG_LISTBOX_ID);
                if !(_indexes isEqualTo []) then {
                    private _index = _indexes#0;  
                    if (_index >= 0 && {_index < count ITW_NewLeaderUnits}) then {
                        _newLeader = ITW_NewLeaderUnits # _index;
                    };
                };
            };
            ITW_NewLeaderUnits = nil;
        };
        case 'cancel': {
            ["itw",["<t size='3'>"+localize "STR_ITW_RADIO_LeadershipDenied"+"</t>","PLAIN",-1,true,true]] remoteExec ["cutText",ITW_NewLeader];
        };
    };
    ITW_NewLeader = objNull;
    if !(isNull _newLeader) then {
        [[group _newLeader, _newLeader],"selectLeader",group _newLeader] call ITW_FncRemoteLocalGroup;
    };
};

ITW_RadioSquadMenu = {
    params ["_msg","_function"];
	ITW_Squad_Menu = [[_msg, false]];
    private _groups = call BIS_fnc_listPlayers apply {group _x};
    _groups = _groups arrayIntersect _groups; // remove duplicates
 //   _groups = _groups - [group player];
    if (_groups isEqualTo []) exitWith {hint localize "STR_ITW_RADIO_NoPlayerGroups"};
    {
        private _grp = _x;
        if (_grp != group player) then {
            ITW_Squad_Menu pushBack [name leader _grp, [_forEachIndex + 2], "", -5, [["expression",format ["[ITW_Squad_Menu_Groups#%1] spawn %2",_forEachIndex,str _function]]],"1","1"];
        };
    } forEach _groups;
    ITW_Squad_Menu_Groups = _groups;
    showCommandingMenu "#USER:ITW_Squad_Menu";
};

ITW_RadioSquadJoin = {
    [localize "STR_ITW_RADIO_JoinSquad", {
        params ["_group"];
        [player] joinSilent _group;
    }] call ITW_RadioSquadMenu;
};

ITW_RadioSquadMerge = {
    [localize "STR_ITW_RADIO_MergeToSquad", {
        params ["_group"];
        private _oldGroup = group player;
        units _oldGroup joinSilent _group;
        [[_oldGroup],"deleteGroup",_oldGroup] call ITW_FncRemoteLocalGroup; 
    }] call ITW_RadioSquadMenu;
};

ITW_ShowFriendlyLevel = 0;  // used to determine if currently showing friendlies or not (0=no,1=groups,2=all)
ITW_ShowFriendlyPaused = false;
ITW_SF_SubMenu = [
	[localize "STR_ITW_RADIO_ShowSquadsOnMap", false],
    [localize "STR_ITW_COMMON_No"          , [2], "", -5, [["expression", "[0] spawn ITW_RadioShowFriendlies;"]], "1", "1"],
	[localize "STR_ITW_RADIO_ShowGroups"   , [3], "", -5, [["expression", "[1]  spawn ITW_RadioShowFriendlies;"]], "1", "1"],
	[localize "STR_ITW_RADIO_ShowSquadsAll", [4], "", -5, [["expression", "[2]  spawn ITW_RadioShowFriendlies;"]], "1", "1"]
];

UNIT_MARKER_SIZE = [1,1];

ITW_RadioShowFriendlies = {
    //  show/hide of friendly group icons
    params [["_showIcons",profileNamespace getVariable ["ITWShowAllyIcons",1]]];
    if (typeName _showIcons == "BOOL") then {_showIcons = 1};
    if (ITW_ShowFriendlyLevel == _showIcons) exitWith {};
    ITW_ShowFriendlyLevel = _showIcons;
    if (_showIcons > 0 && {isNil "ITW_ShowFriendliesRunning"}) then {
        ITW_ShowFriendliesRunning = true;
        0 spawn {
            scriptName "ITW_RadioShowFriendlies";
            // local variables are faster so set some up
            private _sides = [ITW_PlayerSide,ITW_EnemySide];
            private _playerSide = ITW_PlayerSide; 
            private _infantryIcons = ["b_inf","o_inf"];
            private _infantryMrkSize = [0.8,0.8];
            private _unitMrkSize = [0.6,0.6];
            private _vehMrkSize = [1,1];
            
            private _allMarkers = [];
            while {ITW_ShowFriendlyLevel > 0} do {
                private _activeMarkers = []; 
                private _timeout = time + 1;
                private _yieldCount = 0;
                {
                    private _group = _x;
                    
                    // every 20 groups processed, yeild the cpu
                    _yieldCount = _yieldCount + 1;
                    if (_yieldCount > 20) then {YIELD_CPU;_yieldCount = 0};
                    
                    if !(side _group in _sides) then {continue};
                    if (_group getVariable ["itwInitGrp",false]) then {continue};
                    private _leader = leader _group;
                    if (isNull _leader) then {continue};
                    private _isFriendly = side _group == _playerSide;
                    if (!alive _leader) then {
                        private _units = units group _leader;
                        _index = _units findIf {alive _x};
                        if (_index >= 0) then {
                            _leader = _units#_index;
                        } else {continue};
                    };
                    private _veh = vehicle _leader;
                    if (_veh isKindOf "ParachuteBase") then {continue};
                    if (!_isFriendly && {ITW_ParamShowEnemyOnMap == 0 || {_playerSide knowsAbout _veh < 1}}) then {continue};
                    if (_group getVariable ["itw_hideOnMap",false]) then {continue};
                    private _inVeh = _leader != _veh;
                    if (_inVeh && {group driver _veh != _group && {! isNull (driver _veh)}}) then {continue}; // don't show transport groups
                    
                    if (ITW_ShowFriendlyLevel == 2) then {
                        // show all unit icons
                        {
                            if (!alive _x || {_x != vehicle _x}) then {continue};
                            private _pos = getPosATL _x;
                            _mrkr = "ITW_RSF_" + netId _group + ":" + str _forEachIndex;
                            if (getMarkerColor _mrkr isEqualTo "") then {
                                _mrkr = createMarkerLocal [_mrkr, _pos];
                                if (_isFriendly) then {
                                    _mrkr setMarkerTypeLocal "b_unknown";
                                    _mrkr setMarkerColorLocal "ColorBLUFOR";
                                } else {
                                    _mrkr setMarkerTypeLocal "o_unknown";
                                    _mrkr setMarkerColorLocal "ColorOPFOR";
                                };
                                _mrkr setMarkerSizeLocal _unitMrkSize;
                                _allMarkers pushBack _mrkr;
                            } else {
                                _mrkr setMarkerPosLocal _pos;
                            };
                            _activeMarkers pushBack _mrkr;
                        } forEach units _group;
                        if (!_inVeh) then {continue}; // don't show the leader icon since we're showing all units
                    };
                    
                    private _mrkr = "ITW_RSF_" + netId _group;
                    if (getMarkerColor _mrkr isEqualTo "") then {
                        _mrkr = createMarkerLocal [_mrkr, getPosATL _leader];
                        if (_isFriendly) then {
                             _mrkr setMarkerTypeLocal "b_inf";
                             _mrkr setMarkerColorLocal "ColorBLUFOR";
                        } else {
                             _mrkr setMarkerTypeLocal "o_inf";
                             _mrkr setMarkerColorLocal "ColorOPFOR";
                        };
                        _mrkr setMarkerSizeLocal _infantryMrkSize;
                        _allMarkers pushBack _mrkr;
                    } else {
                        _mrkr setMarkerPosLocal getPosATL _leader;
                    };
                    
                    private _isInfantryIcon = getMarkerType _mrkr in _infantryIcons;
                    if (_inVeh && {_group getVariable ["itwvehtype",objNull] != _veh}) then {_isInfantryIcon = _inVeh}; // veh changed, trigger new icon
                    if (_inVeh == _isInfantryIcon) then {
                        if (_inVeh) then {
                            private _icon = if (_veh isKindOf "Car") then {
                                private _armor = getNumber (configFile >> "cfgVehicles" >> typeOf _veh >> "armor");
                                if (_armor < 250) then {"motor_inf"} else {"mech_inf"};
                            } else {
                                if (_veh isKindOf "Tank")          then {"armor"} else {
                                if (_veh isKindOf "Plane")         then {"plane"} else {
                                if (_veh isKindOf "ParachuteBase") then {"inf"} else {
                                if (_veh isKindOf "StaticWeapon")  then {"Ordnance"} else {
                                if (_veh isKindOf "Ship")          then {"naval"} else {
                                if (_veh isKindOf "Air")           then {"air"} else {"inf"}}}}}};
                            };
                            _icon = (if (_isFriendly) then {"b_"} else {"o_"}) + _icon;
                            _mrkr setMarkerTypeLocal _icon;
                            _mrkr setMarkerSizeLocal _vehMrkSize;
                            _group setVariable ["itwvehtype",_veh];
                        } else {
                            _mrkr setMarkerTypeLocal (if (_isFriendly) then {"b_inf"} else {"o_inf"});
                            _mrkr setMarkerSizeLocal _infantryMrkSize;
                        };
                    };
                    _activeMarkers pushBack _mrkr;
                    
                    // debug option to show combat mode in map
                    //if (combatBehaviour group driver _veh == "COMBAT") then {_mrkr setMarkerColorLocal (if (_isFriendly) then {"ColorBlue"} else {"ColorRed"})} else {_mrkr setMarkerColorLocal (if (_isFriendly) then {"ColorBLUFOR"} else {"ColorOPFOR"})};
                    
                } forEach allGroups;
                
                // delete markers on dead units
                {
                    deleteMarkerLocal _x;
                } forEach (_allMarkers - _activeMarkers);
                _allMarkers = _activeMarkers;
 
                if (ITW_ShowFriendlyPaused || {hcShownBar}) then {
                    _allMarkers apply {_x setMarkerAlphaLocal 0};
                    while {ITW_ShowFriendlyLevel > 0 && {ITW_ShowFriendlyPaused || {hcShownBar}}} do {sleep 1};
                    _allMarkers apply {_x setMarkerAlphaLocal 1};
                } else {
                    sleep (time - _timeout);
                };
            };
            _allMarkers apply {deleteMarkerLocal _x};
            ITW_ShowFriendliesRunning = nil;
        };
    };
    profileNamespace setVariable ["ITWShowAllyIcons",_showIcons];
};

ITW_RadioLifeSignScan = {
    if (assignedItems player select {_x isKindOf ["ItemMap",configFile >> "cfgWeapons"]} isEqualTo []) then {
        player linkItem "ItemMap";
    };  
    if (isNil "ITW_THREMAL_SCAN") then {ITW_THREMAL_SCAN = 0};
    if (time < ITW_THREMAL_SCAN) exitWIth {hint format [localize "STR_ITW_RADIO_ScanRechargingFMT",round (ITW_THREMAL_SCAN - time)]};
    
    private _timeout  = 90; // time between scans
    private _duration = 30; // how long life signs show as they fade out
    private _range2 = (ITW_ParamObjectiveSize + 50)^2;
    
    private _pos = ([getPosATL player] call ITW_ObjGetNearest)#ITW_OBJ_POS;
    if (_pos distance player > 1000) exitWith {hint localize "STR_ITW_RADIO_NeedToBeCloser"};
    
    ITW_THREMAL_SCAN = time + _timeout; 
    
    private _markers = []; 
    private _size = 4; 
    private _alpha = 1; 
    
    {
        if (_x isKindOf "LOGIC") then {continue};
        private _unitPos = getPosATL _x;
        private _unitPosASL = getPosASL _x;
        if (_unitPos#2 < 15 || {_unitPosASL#2 < 4 && {_unitPos distanceSQR _pos < _range2}}) then {
            private _mrk = createMarkerLocal [format ["ITWLS_%1",_forEachIndex],getPosATL _x]; 
            _mrk setMarkerShapeLocal "ELLIPSE"; 
            _mrk setMarkerBrushLocal "SolidFull"; 
            _mrk setMarkerSizeLocal [_size,_size]; 
            _mrk setMarkerAlphaLocal _alpha; 
            _mrk setMarkerColorLocal "ColorOrange"; 
            _markers pushBack [_mrk,_x]; 
        };
    } forEach allUnits; 
    
    openMap true;
    mapAnimAdd [0,0.015,_pos]; 
    mapAnimCommit;  
    
    if !(_markers isEqualTo []) then { 
        private _timeout = time + _duration; 
        private _tick = 0.3; 
        private _deltaAlpha = _alpha / _duration * _tick; 
        while {time < _timeout} do { 
            sleep _tick; 
            _alpha = _alpha - _deltaAlpha; 
            { 
                _x params ["_mrk","_unit"]; 
                _mrk setMarkerPosLocal getPosATL _unit;  
                _mrk setMarkerAlphaLocal _alpha;           
            } forEach _markers; 
        }; 
        { 
            deleteMarkerLocal (_x#0); 
        } forEach _markers; 
    }; 
};

ITW_RadioCommanderMenu = [
    [localize "STR_ITW_RADIO_CommanderMenu", false],
    [localize "STR_ITW_RADIO_AdjustPriority"   , [2], "", -5, [["expression", "0 spawn ITW_AllyShowAssignmentsDisplay"]], "1", "1"],
    [localize "STR_ITW_RADIO_AdjustRoutes"     , [3], "", -5, [["expression", "0 spawn ITW_AllyChooseLandRoutes"]], "1", "1"],
    [localize "STR_ITW_RADIO_ReqReinforcements", [4], "", -5, [["expression", "0 spawn ITW_AllyReqReinforcements"]], "1", "1"],
    [localize "STR_ITW_COMMON_Cancel"          ,[16], "", -3, [["expression", ""]], "1", "1"]
];

ITW_RadioCommsMenu = {
    params ["_supportType"];
    private _subType = "";
    private _locationType = "";
    private _pos = [];
    ITW_RadioCall = nil;
    ITW_RADIO_MENU = switch (_supportType) do {
        case "SUPPORT": { 
            private _casAvailB = "1";
            private _casAvailH = "1";
            private _uavAvail = "1";
            private _mortarAvail = "1";
            private _casExB = "";
            private _casExH = "";
            private _mrtEx = "";
            private _uavEx = "";
            private _casVisible = "0";
            private _mrtVisible = "0";
            private _uavVisible = "0";
            
            if (ITW_ParamPlayerCAS > 0) then {
                _casVisible = "1";
                private _casTime = missionNamespace getVariable ["ITW_CasTime",0];
                if (serverTime < _casTime) then {
                    _casAvailB = "0";
                    _casAvailH = "0";
                    _casExB = " " + format [localize "STR_ITW_RADIO_AvailInMinFMT",round ((_casTime - serverTime)/60)];
                    _casExH = _casExB;
                };
                if !(true call ITW_ObjOwnsAirport)                  then {_casAvailB = "0";_casExB = " "+localize "STR_ITW_RADIO_NoCapturedAirports"};
                if !(missionNamespace getVariable ["casBomb",true]) then {_casAvailB = "0";_casExB = " "+localize "STR_ITW_RADIO_NoAtkPlanes"};
                if !(missionNamespace getVariable ["casHeli",true]) then {_casAvailH = "0";_casExH = " "+localize "STR_ITW_RADIO_NoAtkHelis"};
            };
            
            if (ITW_ParamPlayerArtillery > 0) then {
                _mrtVisible = "1";
                private _mrtTime = missionNamespace getVariable ["ITW_MortarTime",0];
                if (serverTime < _mrtTime) then {
                    _mortarAvail = "0";
                    _mtrTime = round (_mrtTime - serverTime);
                    _mrtEx = " " + (if (_mtrTime < 45) then {format [localize "STR_ITW_RADIO_AvailInSecFMT",_mtrTime]} else {format [localize "STR_ITW_RADIO_AvailInMinFMT",str round (_mtrTime/60)]});
                };
            };
            
            if (ITW_ParamPlayerUavSupport > 0) then {
                if (va_pUavClassesUnarmed isEqualTo [] && {va_pUavClassesAttack isEqualTo [] && {va_pUavClassesAttackSmall isEqualTo []}}) exitWith {};
                _uavVisible = "1";
                if (ITW_ParamPlayerUavTerminal == 1) then {
                    if ((player getslotitemname 612) isKindOf ["UavTerminal_base", configFile >> "CfgWeapons"]) then {
                        // player can only use B_UAVTerminal since player side is west
                        player linkItem "B_UAVTerminal";
                    } else {
                        _uavEx = localize "STR_ITW_RADIO_UavNoTerminal";
                        _uavAvail = "0";
                    };
                };
                if (_uavEx isEqualTo "") then {
                    private _uavTime = 0;
                    if (va_pUavClassesUnarmed isEqualTo []) then {
                        _uavTime = missionNamespace getVariable [if (va_pUavClassesAttackSmall isEqualTo []) then {"ITW_UavTime"} else {"ITW_UavSmallTime"},0];
                    };
                    if (serverTime < _uavTime) then {
                        _uavAvail = "0";
                        _uavTime = round (_uavTime - serverTime);
                        _uavEx = " " + (if (_uavTime < 45) then {format [localize "STR_ITW_RADIO_AvailInSecFMT",_uavTime]} else {format [localize "STR_ITW_RADIO_AvailInMinFMT",str round (_uavTime/60)]});
                    };
                };
            };
            
            [
                [localize "STR_ITW_RADIO_Supports", false],
                [localize "STR_ITW_RADIO_SupplyDrop"       , [2], "", -5, [["expression", "ITW_RadioCall = 'SUPPLY'"]], "1", "1"],
                [localize "STR_ITW_RADIO_Flares"           , [3], "", -5, [["expression", "ITW_RadioCall = 'FLARE' "]], "1", "1"],
                [localize "STR_ITW_RADIO_Smokes"           , [4], "", -5, [["expression", "ITW_RadioCall = 'SMOKE' "]], "1", "1"],
                [localize "STR_ITW_RADIO_Artillery"+_mrtEx , [5], "", -5, [["expression", "ITW_RadioCall = 'MORTAR'"]], _mrtVisible, _mortarAvail],
                [localize "STR_ITW_RADIO_CasBomber"+_casExB, [6], "", -5, [["expression", "ITW_RadioCall = 'CAS-B' "]], _casVisible, _casAvailB],
                [localize "STR_ITW_RADIO_CasHeli"+_casExH  , [7], "", -5, [["expression", "ITW_RadioCall = 'CAS-H' "]], _casVisible, _casAvailH],
                [localize "STR_ITW_RADIO_UavSupport"+_uavEx, [8], "", -5, [["expression", "ITW_RadioCall = 'UAV' "]], _uavVisible, _uavAvail],
                [localize "STR_SKL_TS_SupportVeh"          , [9], "#USER:SKL_TS_SubMenu", -5, [["expression", ""]], "1", "1"],
                [""                                ,  [], "", -1, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_COMMON_Back"            ,[48], "#User:BIS_fnc_addCommMenuItem_menu", -2, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_COMMON_Cancel"          ,[16], "", -3, [["expression", ""]], "1", "1"]
            ];
        };
        case "TRANSPORT": {
            [
                [localize "STR_ITW_RADIO_Transports", false],
                [localize "STR_ITW_RADIO_HeliExtract", [2], "#USER:SKL_HE_SubMenu", -5, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_RADIO_TranspTruck", [3], "#USER:SKL_TE_SubMenu", -5, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_RADIO_AirDropVeh" , [4], "", -5, [["expression", "ITW_RadioCall = 'AIR-DROP'"]], "1", "1"],
                [""                          ,  [], "", -1, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_COMMON_Back"      ,[48], "#User:BIS_fnc_addCommMenuItem_menu", -2, [["expression", ""]], "1", "1"],
                [localize "STR_ITW_COMMON_Cancel"    ,[16], "", -3, [["expression", ""]], "1", "1"]
            ];
        };
        default {[]};
    };
    if !(ITW_RADIO_MENU isEqualTo []) then {
        showCommandingMenu "#USER:ITW_RADIO_MENU";
        waitUntil {commandingMenu == ""};
        if (!isNil "ITW_RadioCall") then {_subType = ITW_RadioCall};
        ITW_RadioCall = nil;
        ITW_RADIO_MENU = nil;
    };
    
    // now handle items requiring a position
    if !(_subType isEqualTo "") then {
        if (_subType in ["UAV"]) then {
            _pos = getPosATL player;
        } else {
            _pos = [] call SKL_LocationSelection;
        };
        
        if !(_pos isEqualTo []) then {
            switch (_subType) do {
                case 'SUPPLY':   {[_pos] spawn ITW_RadioSupplyDrop};
                case 'FLARE' :   {[_pos] spawn ITW_RadioFlareDrop};
                case 'SMOKE' :   {[_pos] spawn ITW_RadioSmokeDrop};
                case 'CAS-B' :   {[_pos] spawn ITW_RadioCasPlane};
                case 'CAS-H' :   {[_pos] spawn ITW_RadioCasHeli};
                case 'UAV'   :   {[_pos] spawn ITW_RadioUAV};
                case 'MORTAR':   {[_pos] spawn ITW_RadioMortar};
                case "AIR-DROP": {[_pos] spawn ITW_RadioVehicleDrop};
            };
        };
    };
};

ITW_RadioTeammateMenu = {
    if (isNil "ITW_RADIO_TEAMMATE_DELIVERY_MENU") then {
        ITW_RADIO_TEAMMATE_DELIVERY_MENU = [
            [localize "STR_ITW_RADIO_DeliverTeammates", false],
            [localize "STR_ITW_COMMON_None"         ,[11], "", -5, [["expression", "ITW_RadioTmCountLocal = 0"]], "1", "1"],
            ["1 "+localize "STR_ITW_RADIO_Teammate" , [2], "", -5, [["expression", "ITW_RadioTmCountLocal = 1"]], "1", "1"],
            ["2 "+localize "STR_ITW_RADIO_Teammates", [3], "", -5, [["expression", "ITW_RadioTmCountLocal = 2"]], "1", "1"],
            ["3 "+localize "STR_ITW_RADIO_Teammates", [4], "", -5, [["expression", "ITW_RadioTmCountLocal = 3"]], "1", "1"],
            ["4 "+localize "STR_ITW_RADIO_Teammates", [5], "", -5, [["expression", "ITW_RadioTmCountLocal = 4"]], "1", "1"],
            ["5 "+localize "STR_ITW_RADIO_Teammates", [6], "", -5, [["expression", "ITW_RadioTmCountLocal = 5"]], "1", "1"],
            ["6 "+localize "STR_ITW_RADIO_Teammates", [7], "", -5, [["expression", "ITW_RadioTmCountLocal = 6"]], "1", "1"],
            [localize "STR_ITW_ALLY_RecruitTeam"    , [8], "", -5, [["expression", "ITW_RadioTmCountLocal =-1"]], "1", "1"],
            [localize "STR_ITW_COMMON_Cancel"       ,[16], "", -3, [["expression", ""]], "1", "1"]
        ];
    };
    ITW_RadioTmCountLocal = nil;
    showCommandingMenu "#USER:ITW_RADIO_TEAMMATE_DELIVERY_MENU";
    waitUntil {commandingMenu == ""};
    if (isNil "ITW_RadioTmCountLocal") then {ITW_RadioTmCountLocal = 0};
    if (ITW_RadioTmCountLocal == -1) then {ITW_RadioTmCountLocal = false call ITW_AllyRecruitTeam};
    ITW_RadioTmCount = ITW_RadioTmCountLocal;
    publicVariableServer "ITW_RadioTmCount";
}; 

ITW_RadioTeammateParadropMenu = {
    ITW_RADIO_MENU = [
        [localize "STR_ITW_RADIO_ParachuteTeammates", false],
        [localize "STR_ITW_RADIO_TeamUnloadLand", [2], "", -5, [["expression", "ITW_RadioTmPara = false"]], "1", "1"],
        [localize "STR_ITW_RADIO_TeamUnloadPara", [3], "", -5, [["expression", "ITW_RadioTmPara = true" ]], "1", "1"]
    ];
    ITW_RadioTmPara = nil;
    showCommandingMenu "#USER:ITW_RADIO_MENU";
    waitUntil {commandingMenu == ""};
    if (isNil "ITW_RadioTmPara") then {ITW_RadioTmPara = false};
    publicVariableServer "ITW_RadioTmPara";
    ITW_RADIO_MENU = nil;
};

ITW_RadioHaloDropMenu = {
    ITW_RADIO_MENU = [
        [localize "STR_ITW_RADIO_HaloDrop", false],
        [localize "STR_ITW_RADIO_HaloNo",  [2], "", -5, [["expression", "ITW_RadioHalo = false"]], "1", "1"],
        [localize "STR_ITW_RADIO_HaloYes", [3], "", -5, [["expression", "ITW_RadioHalo = true" ]], "1", "1"]
    ];
    ITW_RadioHalo = false;
    showCommandingMenu "#USER:ITW_RADIO_MENU";
    waitUntil {commandingMenu == ""};
    private _halo = ITW_RadioHalo;
    ITW_RADIO_MENU = nil;
    ITW_RadioHalo = nil;
    _halo
};

ITW_RadioHeliTransport = {
    // called on server
    params ["_lzPos","_caller"];
    
    private _cargoUnits = [];
    private _paradrop = false;
    if (leader _caller == _caller) then {
        ITW_RadioTmCount = nil;
        [] remoteExec ["ITW_RadioTeammateMenu",_caller];
        waitUntil {sleep 0.001;!isNil "ITW_RadioTmCount"};
        private _unitTypes = [];
        if (typeName ITW_RadioTmCount == "SCALAR") then {
            for "_i" from 1 to ITW_RadioTmCount do {_unitTypes pushBack selectRandom ITW_AllyUnitTypes};
        } else {
            _unitTypes = ITW_RadioTmCount;
        };
        ITW_RadioTmCount = nil;
        private _cargoGrp = grpNull;
        if (_unitTypes isNotEqualTo []) then {
            private _fromObj = [_lzPos,ITW_OWNER_FRIENDLY] call ITW_ObjGetNearest;
            private _spawnPt = _fromObj#ITW_OBJ_V_SPAWN;
            {
                private _unitType = _x;
                private _aiCnt = {!isPlayer _x && {alive _x}} count units group _caller;
                if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {
                    hint localize "STR_ITW_RADIO_MaxSquadSizeReached";
                };    
                if (isNull _cargoGrp) then {_cargoGrp = createGroup [playerSide,false]};
                private _unit = [_cargoGrp,[_unitType],_spawnPt,true] call ITW_AtkUnitToGroup;
                _cargoUnits pushBack _unit;
            } forEach _unitTypes;
            if (!isNull _cargoGrp) then {
                _cargoGrp deleteGroupWhenEmpty true;
                ITW_RadioTmPara = nil;
                [] remoteExec ["ITW_RadioTeammateParadropMenu",_caller]; // ask if they should be parachuted in
                waitUntil {sleep 0.001;!isNil "ITW_RadioTmPara"};
                _paradrop = ITW_RadioTmPara;
                ITW_RadioTmPara = nil;
            };
        };
    };
    
    private _pilot = selectRandom ITW_RADIO_PILOTS;    
    private _base = [_lzPos,ITW_OWNER_FRIENDLY] call ITW_BaseNearest;
    private _basePos = _base call ITW_BaseGetCenterPt;
    
    [_lzPos, _caller, ITW_RADIO_HELIS, _pilot, side _caller, _basePos, {group driver _this setVariable ["itw_hideOnMap",true]},_cargoUnits,_paradrop] spawn SKL_HeliExtract;
};

ITW_RadioTruckTransport = {
    // truck transport setup function - run on server
    params ["_lzPos","_player",["_vehClass",""],["_allowTeammates",true]];
    private _truckType = if (_vehClass isEqualTo "") then {selectRandom va_pCarClassesTransport} else {_vehClass};
    if (isNil "_truckType") then {selectRandom va_cCarClassesTransport};
    if (isNil "_truckType") then {_truckType = "C_Van_02_transport_F"};
    private _fromObj = [_lzPos,ITW_OWNER_FRIENDLY] call ITW_ObjGetNearest;
    private _spawnPt = _fromObj#ITW_OBJ_V_SPAWN;
    // we can't spawn here since this is where the attack manager spawns vehicles so move a little away
    private _roads = _spawnPt nearRoads (200) select {_x distance _spawnPt > 20};
    if (_roads isEqualTo []) then {
        _spawnPt = [_spawnPt,20,500,12,0,0,0,[],[_spawnPt,_spawnPt]] call BIS_fnc_findSafePos;
    } else {
        _spawnPt = getPosATL selectRandom _roads;
    };
    private _crewGrp = createGroup [civilian,false];
    private _driver = [_crewGrp,ITW_AllyUnitTypes,_spawnPt,true] call ITW_AtkUnitToGroup;
    _crewGrp deleteGroupWhenEmpty true;
    group _driver setVariable ["itw_hideOnMap",true];
    
    private _cargoUnits = [];
    if (_allowTeammates && {leader _player == _player}) then {
        ITW_RadioTmCount = nil;
        [] remoteExec ["ITW_RadioTeammateMenu",_player];
        waitUntil {sleep 0.001;!isNil "ITW_RadioTmCount"};
        private _unitTypes = [];
        if (typeName ITW_RadioTmCount == "SCALAR") then {
            for "_i" from 1 to ITW_RadioTmCount do {_unitTypes pushBack selectRandom ITW_AllyUnitTypes};
        } else {
            _unitTypes = ITW_RadioTmCount;
        };
        ITW_RadioTmCount = nil;
        private _cargoGrp = grpNull;
        {
            private _unitType = _x;
            private _aiCnt = {!isPlayer _x && {alive _x}} count units group _player;
            if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {
                hint localize "STR_ITW_RADIO_MaxSquadSizeReached";
            };    
            if (isNull _cargoGrp) then {_cargoGrp = createGroup [playerSide,false]};
            private _unit = [_cargoGrp,[_unitType],_spawnPt,true] call ITW_AtkUnitToGroup;
            _cargoUnits pushBack _unit;
        } forEach _unitTypes;
        if (!isNull _cargoGrp) then {_cargoGrp deleteGroupWhenEmpty true};
    };
    [_lzPos, _player, _truckType, [_driver], playerSide, _spawnPt, {group driver _this setVariable ["itw_hideOnMap",true]}, _cargoUnits] call SKL_TruckExtract;
};

ITW_RadioTruckService = {
    params ["_lzPos","_player","_serviceType"];
    private _vehs = switch (_serviceType) do {
        case "ammo":   {
            private _ammo = va_pAmmoClasses;
            if (_ammo isEqualTo []) then {_ammo = va_cAmmoClasses};
            _ammo
        };
        case "fuel":   {
            private _fuel = va_pFuelClasses;
            if (_fuel isEqualTo []) then {_fuel = va_cFuelClasses};
            _fuel
        };
        case "repair": {
            private _repair = va_pRepairClasses;
            if (_repair isEqualTo []) then {_repair = va_cRepairClasses};
            _repair
        };
        default {[]};
    };
    
    if (_vehs isEqualTo []) exitWith {["Command",localize "STR_SKL_TS_NoVehs",false] remoteExec ["SKL_TS_SendMessage",_player]};
    
    private _vehClass = selectRandom _vehs;
    if (isNil "_vehClass") exitWith {diag_log "ERROR POS: ITW_RadioSupportVeh - invalid vehicle class"; _vehClass = "C_Truck_02_box_F"};
    
    private _fromObj = [_lzPos,ITW_OWNER_FRIENDLY] call ITW_ObjGetNearest;
    private _spawnPt = _fromObj#ITW_OBJ_V_SPAWN;
    // we can't spawn here since this is where the attack manager spawns vehicles so move a little away
    private _roads = _spawnPt nearRoads (200) select {_x distance _spawnPt > 20};
    if (_roads isEqualTo []) then {
        _spawnPt = [_spawnPt,20,500,12,0,0,0,[],[_spawnPt,_spawnPt]] call BIS_fnc_findSafePos;
    } else {
        _spawnPt = getPosATL selectRandom _roads;
    };
    private _crewGrp = createGroup [civilian,false];
    private _driver = [_crewGrp,ITW_AllyUnitTypes,_spawnPt,true] call ITW_AtkUnitToGroup;
    
    _crewGrp deleteGroupWhenEmpty true;
    group _driver setVariable ["itw_hideOnMap",true];
    
    [_lzPos, _player, _vehClass, [_driver], playerSide, _spawnPt, {group driver _this setVariable ["itw_hideOnMap",true]}, _serviceType] call SKL_TruckService;
};

ITW_RadioCasServer = {
    params ["_args","_type"];
    private _success = 
        if (_type == "heli") then {_args call SKL_CASHeli}
        else { _args call SKL_CASPlane };
    // if cas not successfully launched, allow another right away
    if (!_success) then {missionNamespace setVariable ["ITW_CasTime",serverTime,true]}; 
};

ITW_RadioCasPlane = {
    params ["_pos"];
    missionNamespace setVariable ["ITW_CasTime",serverTime + ITW_ParamPlayerCAS,true]; 
    private _vehType = selectRandom va_pPlaneClassesAttack;
    if (isNil "_vehType") then {_vehType = selectRandom va_pPlaneClassesDual};
    if (isNil "_vehType") exitWith {hint localize "STR_ITW_RADIO_PlanesNotAvail"};
    private _airportPos = [true,_pos] call ITW_ObjClosestOwnedAirport;
    if (isNil "_airportPos" || {!(typeName _airportPos isEqualTo "ARRAY")}) exitWith {hint localize "STR_ITW_RADIO_NoAirportsAvailable"};
    private _dir = _airportPos getDir _pos;
    [[player,_pos,_dir,west,_vehType],"bomb"] remoteExec ["ITW_RadioCasServer",2];
};

ITW_RadioCasHeli = {
    params ["_pos"];
    missionNamespace setVariable ["ITW_CasTime",serverTime + ITW_ParamPlayerCAS,true];
    private _vehType = selectRandom va_pHeliClassesAttack;
    if (isNil "_vehType") then {_vehType = selectRandom va_pHeliClassesDual};
    if (isNil "_vehType") exitWith {hint localize "STR_ITW_RADIO_NoHelisAvail"}; 
    // prioritize the basic nato/cscat attack helis
    private _allHelis = va_pHeliClassesAttack + va_pHeliClassesDual;
    {if (_x in _allHelis) exitWith {_vehType = _x}} forEach ["B_Heli_Attack_01_dynamicLoadout_F","O_Heli_Attack_02_dynamicLoadout_F"]; 
    private _basePos = ([_pos] call ITW_BaseNearest)#ITW_BASE_POS;
    private _dir = _basePos getDir _pos;
    [[player,_pos,_dir,west,_vehType],"heli"] remoteExec ["ITW_RadioCasServer",2];
};

ITW_RadioUAV = {
    private _largeAvail   = if (va_pUavClassesAttack isEqualTo []) then {"0"} else {"1"};
    private _smallAvail    = if (va_pUavClassesAttackSmall isEqualTo []) then {"0"} else {"1"};
    private _unarmedAvail  = if (va_pUavClassesUnarmed isEqualTo []) then {"0"} else {"1"};
    private _largeEx = "";
    private _smallEx = "";
    
    private _uavTime = missionNamespace getVariable ["ITW_UavTime",0];
    if (serverTime < _uavTime) then {
        _largeAvail = "0";
        _uavTime = round (_uavTime - serverTime);
        _largeEx = " " + (if (_uavTime < 45) then {format [localize "STR_ITW_RADIO_AvailInSecFMT",_uavTime]} else {format [localize "STR_ITW_RADIO_AvailInMinFMT",str round (_uavTime/60)]});
    };
    private _uavTime = missionNamespace getVariable ["ITW_UavSmallTime",0];
    if (serverTime < _uavTime) then {
        _smallAvail = "0";
        _uavTime = round (_uavTime - serverTime);
        _smallEx = " " + (if (_uavTime < 45) then {format [localize "STR_ITW_RADIO_AvailInSecFMT",_uavTime]} else {format [localize "STR_ITW_RADIO_AvailInMinFMT",str round (_uavTime/60)]});
    };
    ITW_RADIO_UAV_MENU = [
        [localize "STR_ITW_RADIO_UavSupport", false],
        [(localize "STR_ITW_RADIO_UavLarge")+_largeEx,   [2], "", -5, [["expression", "ITW_UavTypeAnswer = 'ATK'"]] , "1", _largeAvail],
        [(localize "STR_ITW_RADIO_UavSmall" )+_smallEx , [3], "", -5, [["expression", "ITW_UavTypeAnswer = 'SML'" ]], "1", _smallAvail],
        [localize "STR_ITW_RADIO_UavUnarmed",            [4], "", -5, [["expression", "ITW_UavTypeAnswer = 'UNA'" ]], "1", _unarmedAvail],
        [localize "STR_ITW_COMMON_Quit",                [16], "", -5, [["expression","showCommandingMenu ''"]], "1", "1"]
    ];

    if (isNil "ITW_RadioUavAttackMenu1") then {
        private _menuCreateFn = {
            params ["_uavClasses","_varName"];
            private _header = [[localize "STR_ITW_RADIO_UavSupport", false]];
            private _index = 0;
            private _maxItems = 10;
            private _cnt = _maxItems+2;
            private _menu = +_header;
            private _namesUsed = [];
            {
                private _class = _x;                
                private _className = if (typeName _class == "ARRAY") then {_class#0} else {_class};
                private _name = getText (configFile >> "cfgVehicles" >> _className >> "displayName");
                if (_name in _namesUsed) then {continue};
                _namesUsed pushBack _name;
                if (_cnt > _maxItems) then {
                    if (_index > 0) then {
                        if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"]};
                        _menu pushBack [localize "STR_ITW_COMMON_More",[31], format ["#USER:%1%2",_varName,_index+1], -5, [["expression",""]], "1", "1"];
                        call compile format ["%1%2 = _menu;",_varName,_index];
                    };
                    _menu = +_header;
                    _cnt = 0;
                    _index = _index + 1;
                } else {
                    _cnt = _cnt + 1;
                };          
                _menu pushBack [_name,[_cnt+2], "", -5, [["expression",format ["ITW_UavAnswer = %1;",_forEachIndex]]], "1", "1"];
            } forEach _uavClasses;
            if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"]}
            else {                _menu pushBack [localize "STR_ITW_COMMON_Prev",[16], "", -5, [["expression","ITW_UavAnswer ='BACK'"]], "1", "1"]};
            call compile format ["%1%2 = _menu;",_varName,_index];
        };
        [va_pUavClassesAttack     ,"ITW_RadioUavAttackMenu" ] call _menuCreateFn;
        [va_pUavClassesAttackSmall,"ITW_RadioUavSmallMenu"  ] call _menuCreateFn;
        [va_pUavClassesUnarmed    ,"ITW_RadioUavUnarmedMenu"] call _menuCreateFn;
    };
    
    ITW_UavAnswer = "x";
    while {!(ITW_UavAnswer isEqualTo "")} do {
        ITW_UavTypeAnswer = "";
        showCommandingMenu "#USER:ITW_RADIO_UAV_MENU";
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};
        if (ITW_UavTypeAnswer == "") exitWith {};
        
        ITW_UavAnswer = "";
        private "_whichArray";
        switch (ITW_UavTypeAnswer) do {
            case "ATK": {_whichArray = va_pUavClassesAttack     ; showCommandingMenu "#USER:ITW_RadioUavAttackMenu1" };
            case "SML": {_whichArray = va_pUavClassesAttackSmall; showCommandingMenu "#USER:ITW_RadioUavSmallMenu1"  };
            default     {_whichArray = va_pUavClassesUnarmed    ; showCommandingMenu "#USER:ITW_RadioUavUnarmedMenu1"};
        };
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};
        
        if !(ITW_UavAnswer isEqualTo "") then {
            if (typeName ITW_UavAnswer == "SCALAR") then {
                [_whichArray#ITW_UavAnswer,ITW_UavTypeAnswer == "ATK"] call ITW_RadioUavSpawn;
                ITW_UavAnswer = "";
            };
        };
    };
    ITW_UavTypeAnswer = nil;
    ITW_UavAnswer = nil;
};

ITW_RadioUavSpawn = {
    // call on player's client
    params ["_uavClass","_isLarge"];
    private _className = if (typeName _uavClass == "ARRAY") then {_uavClass#0} else {_uavClass};
    private _spawnPos = [];
    private _spawnDir = -1;
    private _base = [getPos player,ITW_OWNER_FRIENDLY,true,true] call ITW_BaseNearest;
    private _basePos = _base#ITW_BASE_POS;
    private _spawnOption = "CAN_COLLIDE";
    
    if (_className isKindOf "Air") then {
        _spawnPos = if (_isLarge) then {_basePos getPos [30 + random 50,random 360]} else {
            if (player distance _basePos < 500) then {player getPos [500,player getDir _basePos]} else {_basePos getPos [30 + random 50,random 360]};
        };
        _spawnPos set [2,if (_isLarge) then {200} else {100}];
        _spawnOption = "FLY";
    } else {
        if (_className isKindOf "Ship") then {
            private _playerPos = getPosATL player;
            for "_r" from 100 to 1000 step 50 do {
                private _pointsInRing = round (2 * pi * _r / 50);
                private _angleStep = 360 / _pointsInRing;

                for "_i" from 0 to (_pointsInRing - 1) do {
                    private _checkPos = _playerPos getPos [_r, _i * _angleStep];
                    
                    // getTerrainHeightASL returns negative values for depth
                    if (getTerrainHeightASL _checkPos < -3) exitWith {
                        _spawnPos = _checkPos;
                    };
                };
                if (count _spawnPos > 0) exitWith {}; // Stop searching once closest is found
            };
        } else {
            // Land UGV
            private _pos = _basePos getPos [200,_basePos getDir player];
            private _roads = _pos nearRoads ((ITW_ZoneKeepOut/2)) select {_x distance _basePos > 100};
            if (count _roads < 5) then {
                _roads = (_basePos getPos [ITW_ZoneKeepOut*.75,_basePos getDir _pos]) nearRoads ((ITW_ZoneKeepOut/2)+200) select {_x distance _basePos > 100};
            };
            if (count _roads < 5) then {
                _roads = (_basePos getPos [ITW_ZoneKeepOut,_basePos getDir _pos]) nearRoads ((ITW_ZoneKeepOut)+200) select {_x distance _basePos > 100};
            };
            if (count _roads > 0) then {
                private _road = selectRandom _roads;
                _spawnPos = getPosATL _road;
                _spwanDir = getDir _road;
                if ([_spawnDir,_spawnPos getDir player] call ITW_FncAngle > 180) then {_spawnDir = _spawnDir + 180};
            } else {
                _spawnPos = [_pos,0,500,3,0,0.5,0,[],[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
                if (_spawnPos isEqualTo [0,0,0]) then {
                    _spawnPos = [];
                } else {
                    _spawnPos set [2,(getTerrainHeightASL _spawnPos) + 2];
                };
            };
        };
    };
    
    if (_spawnPos isEqualTo []) exitWith {
        diag_log format ["ITW: UAV spawn failed to find spawn position for %1",_className];
        ["Support HQ",localize "STR_ITW_RADIO_UavNoSpawn"] remoteExec ["ITW_RadioSendMessage",0];
    };
    
    if (_spawnDir == -1) then {_spawnDir = _spawnPos getDir player};
    private _uav = [_uavClass,_spawnPos,_spawnDir,1,false,_spawnOption,false] call ITW_VehSpawn;
    
    if (isNull _uav) exitWith {
        diag_log format ["ITW: UAV spawn failed to create vehicle for %1",_className];
        ["Support HQ",localize "STR_ITW_RADIO_UavNoSpawn"] remoteExec ["ITW_RadioSendMessage",0];
    };
    
    if (_spawnOption isEqualTo "FLY" && {_isLarge}) then {_uav setVectorUp [0,0,1]; _uav setVelocityModelSpace [0, 50, 0]};
    
    west createVehicleCrew _uav;
    
    private _wp = group driver _uav addWaypoint [getPosATL _uav,100];
    _wp setWaypointType "LOITER";
    
    if (ITW_ParamPlayerUavTerminal == 0) then {
        private _slotItem = player getslotitemname 612;
        if !(_slotItem isKindOf ["UavTerminal_base", configFile >> "CfgWeapons"]) then {
            // player needs a uav terminal and can only use B_UAVTerminal since player side is west
            player addItem _slotItem;
            player linkItem "B_UAVTerminal";
        };
    };
    
    private _success = player connectTerminalToUAV _uav;
    if (_success) then {
        ["Support HQ",localize "STR_ITW_RADIO_UavLinkActive"] remoteExec ["ITW_RadioSendMessage",0];
    } else {
        diag_log format ["ITW: UAV failed to connect %1 to player's terminal",_className];
        ["Support HQ",localize "STR_ITW_RADIO_UavNoLink"] remoteExec ["ITW_RadioSendMessage",0];
    };
};

ITW_RadioMortar = {
    params ["_pos"];
    private _travelTime = 40;  // time in sec between call and first round landing
    private _mortarRounds = 8 + random 2; // number of rounds in a volley
    private _accuracy = 50;    // how close to the target the round will land
    missionNamespace setVariable ["ITW_MortarTime",serverTime + ITW_ParamPlayerArtillery,true]; 
    ["SentRequestAcknowledgedSGArty"] call ITW_RadioPlayMessage;
    ["HQ",format [localize "STR_ITW_RADIO_OrdinanceInboundFMT",str _travelTime],false] call ITW_RadioSendMessage;
    sleep _travelTime;
    for "_i" from 1 to _mortarRounds do {
        private _posToFireAt = _pos getPos [random _accuracy, random 360];
        _posToFireAt set [2,600];
        private _shell = "Sh_82mm_AMOS" createVehicle _posToFireAt;
        _shell setPosATL _posToFireAt;
        _shell setVelocity [0,0,-50];  
        sleep (1.5 +random 0.5);
    };
};

ITW_RadioSmokeDrop = {
    params ["_pos"];
    private _travelTime = 30;  // time in sec between call and first round landing
    private _rounds = 10 + floor random 5; // number of rounds in a volley
    private _accuracy = 70;    // how close to the target the round will land
    ["SentRequestAcknowledgedSGArty"] call ITW_RadioPlayMessage;
    ["HQ",format [localize "STR_ITW_RADIO_OrdinanceInboundFMT",str _travelTime],false] call ITW_RadioSendMessage;
    sleep _travelTime;
    for "_i" from 1 to _rounds do {
        private _posToFireAt = _pos getPos [random _accuracy, random 360];
        _posToFireAt set [2,100];
        private _shell = "Smoke_120mm_AMOS_White" createVehicle _posToFireAt;
        _shell setPosATL _posToFireAt;
        _shell setVelocity [0,0,-50];  
        sleep 1 + random 0.5;
    };
};

ITW_RadioSendMessage = {
    // call on each client
    params ["_sender","_message",["_playAudio",false]];
    [_sender, format ["%1<br /><br /><br /><br /><br /><br />",_message]] call BIS_fnc_showSubtitle;
    
    if (_playAudio && (getSubtitleOptions select 0)) then {
        _radioArray = [		
            "RadioAmbient2",
            "RadioAmbient6",
            "RadioAmbient8"
        ];
        0 fadeSpeech 1;
        playSound [selectRandom _radioArray, true];
    };
};


ITW_RadioPlayMessage = {
    params ["_sentence"];
	private _speaker = west call bis_fnc_moduleHQ;
	if (isnull _speaker) then { isNil {_speaker = (createGroup west) createunit ["ModuleHQ_F",[10,10,10],[],0,"none"]}};
	_speaker setspeaker speaker _speaker;
	_speaker setpitch 1;
	_speaker setbehaviour behaviour _speaker;
	_speaker globalradio _sentence;
};

["ITW_RadioInit"] call SKL_fnc_CompileFinal;
["ITW_RadioHeliCheck"] call SKL_fnc_CompileFinal;
["ITW_RadioFastTravel"] call SKL_fnc_CompileFinal;
["ITW_RadioVehicleDrop"] call SKL_fnc_CompileFinal;
["ITW_RadioHeliTransport"] call SKL_fnc_CompileFinal;
["ITW_RadioChooseOnMap"] call SKL_fnc_CompileFinal;
["ITW_RadioSupplyDrop"] call SKL_fnc_CompileFinal;
["ITW_RadioFlareDrop"] call SKL_fnc_CompileFinal;
["ITW_RadioLeaderAuthorize"] call SKL_fnc_CompileFinal;
["ITW_RadioLeaderRelinquish"] call SKL_fnc_CompileFinal;
["ITW_RadioLeaderProcess"] call SKL_fnc_CompileFinal;
["ITW_RadioFlareMP"] call SKL_fnc_CompileFinal;
["ITW_RadioLeaderRequest"] call SKL_fnc_CompileFinal;
["ITW_RadioShowFriendlies"] call SKL_fnc_CompileFinal;
["ITW_RadioSupplyDropMoveMP"] call SKL_fnc_CompileFinal;
["ITW_RadioLifeSignScan"] call SKL_fnc_CompileFinal;
["ITW_RadioSquadMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioSquadJoin"] call SKL_fnc_CompileFinal;
["ITW_RadioSquadMerge"] call SKL_fnc_CompileFinal;
["ITW_RadioCasPlane"] call SKL_fnc_CompileFinal;
["ITW_RadioCasHeli"] call SKL_fnc_CompileFinal;
["ITW_RadioMortar"] call SKL_fnc_CompileFinal;
["ITW_RadioSendMessage"] call SKL_fnc_CompileFinal;
["ITW_RadioPlayMessage"] call SKL_fnc_CompileFinal;
["ITW_RadioCommsMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioTeammateMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioTruckTransport"] call SKL_fnc_CompileFinal;
["ITW_RadioCasServer"] call SKL_fnc_CompileFinal;
["ITW_RadioBringAiMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioTeammateParadropMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioSmokeDrop"] call SKL_fnc_CompileFinal;
["ITW_RadioTruckService"] call SKL_fnc_CompileFinal;
["ITW_RadioUAV"] call SKL_fnc_CompileFinal;
["ITW_RadioUavSpawn"] call SKL_fnc_CompileFinal;
["ITW_RadioHaloDropMenu"] call SKL_fnc_CompileFinal;
["ITW_RadioFastTravelHalo"] call SKL_fnc_CompileFinal;