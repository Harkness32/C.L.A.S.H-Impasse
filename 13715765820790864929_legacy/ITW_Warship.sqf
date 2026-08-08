
#include "defines.hpp"

#define WARSHIP_INFO_PARAMS   ["_shipClass","_shipName","_shipSize","_repairPt","_garagePt","_officerPt","_officerDir","_arsenalPt","_arsenalDir","_fastTravelPt","_deckOffset","_dirOffset","_isCarrier"]
#define WARSHIP_ACTIVE_PARAMS ["_shipPoint","_shipDir","_shipIndex","_shipMrk","_repairPoint","_garagePoint","_fastTravelPoint","_attackMap"]
#define WARSHIP_ATK_MAP_AIR 0
#define WARSHIP_ATK_MAP_SEA 1

ITW_WS_Active = []; // array of WARSHIP_ACTIVE_PARAMS   (WARSHIP_INFO_PARAMS)

ITW_WS_WARSHIPS = [ // array of shipInfo,  positions are ASL, warship is at sea level, pos#2 is deck height
    /*                                                                                                            deck  ship    is
       class                      name       size  repair  garage      officerPt  dir  arsenalPt  dir  fastTravel hgt   dir   carrier  */
    ["Land_Carrier_01_base_F"  ,"USS Freedom",183,[0,0,0],[-4,-130,0],[22,-110,0],-90,[22,-115,0], 90,[20,-111,0],-0.16, 180,   true],
    ["Land_Destroyer_01_base_F","USS Liberty",100,[0,0,0],[ 0, -75,0],[ 9, -60,0],180,[12, -60,0], 37,[ 9, -64,0], 0   , 180,   false],
    ["Land_EF_LPD_base"        ,"USS Takmyr" ,100,[0,0,0],[ 0, -78,2],[ 9, -43,0],180,[13, -43,0], 37,[11, -48,0], 10.2,   0,   false]
];

ITW_WarshipAdd = {
    ITW_WsAnswer = -1;
    ITW_WsMenu = [[localize "STR_ITW_MISC_SelectWarship", true]];
    {
        _x params WARSHIP_INFO_PARAMS;
        if (isClass (configFile >> "cfgVehicles" >> _shipClass)) then {
            ITW_WsMenu pushBack [_shipName, [_forEachIndex + 2], "", -5, [["expression",format ["ITW_WsAnswer = %1",_forEachIndex]]], "1", "1"];
        };
    } forEach ITW_WS_WARSHIPS;
    ITW_WsMenu pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
    showCommandingMenu "#USER:ITW_WsMenu";
    waitUntil {!(commandingMenu isEqualTo "")};
    waitUntil {commandingMenu isEqualTo ""};   
    if (ITW_WsAnswer >= 0) then {
        private _posDir = call ITW_WsPickPosDir;
        if !(_posDir isEqualTo []) then {
            [ITW_WsAnswer,_posDir] call ITW_WsPlace;
        };
    };
};

ITW_WarshipMove = {
    private _activeIndex = call ITW_WsSelect;
    if (_activeIndex isEqualTo []) exitWith {[]};
    private _posDir = call ITW_WsPickPosDir;
    if (_posDir isEqualTo []) exitWith {};
    private _shipIndex = [_activeIndex] call ITW_WarshipRemove;
    [_shipIndex,_posDir] call ITW_WsPlace;
};

ITW_WarshipRemove = {
    params [["_activeIndex",-1]];
    if (_activeIndex < 0) then {_activeIndex = 0 call ITW_WsSelect};
    if (_activeIndex < 0 || {_activeIndex >= count ITW_WS_Active}) exitWith {-1};
    
    ITW_WS_Active#_activeIndex params WARSHIP_ACTIVE_PARAMS;
    ITW_WS_WARSHIPS#_shipIndex params WARSHIP_INFO_PARAMS;
    private _objects = _shipPoint nearObjects _shipSize;
    {
        if (! isPlayer _x) then {deleteVehicle _x};
    } forEach _objects;
    
    ITW_WS_AtkHashReset = true;
    publicVariable "ITW_WS_AtkHashReset";
    ITW_WS_Active deleteAt _activeIndex;
    publicVariable "ITW_WS_Active";
    
    // remove repair and garage points
    ITW_Garages = ITW_Garages - [AslToAtl _garagePoint]; publicVariable "ITW_Garages";
    [_repairPoint,_shipSize] call ITW_vehRepairPointRemove;
    
    // remove marker
    deleteMarker _shipMrk;
    
    _shipIndex // return the ship type
};

ITW_WarshipGarageDir = {
    // checks if pos is the warship garage, and if so returns the ship dir (else returns passed in dir)
    params ["_pos","_dir"];
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        if (_pos distance2D _garagePoint < 10) exitWith {_dir = _shipDir};
    } forEach ITW_WS_Active;
    _dir
};

ITW_WarshipCarrierPositions = {
    // returns position of carrier or [] if no carrier 
    private _isFriendly = _this;
    if (!_isFriendly) exitWith {[]};
    if (ITW_WS_Active isEqualTo []) exitWith {[]};
    
    private _carrierPositions = [];
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        ITW_WS_WARSHIPS#_shipIndex params WARSHIP_INFO_PARAMS;
        if (_isCarrier) then {_carrierPositions pushBack _shipPoint};
    } forEach ITW_WS_Active;
    
    _carrierPositions
};

ITW_WarshipGetPos = {
    params ["_warshipIndex"];
    ITW_WS_Active#_warshipIndex params WARSHIP_ACTIVE_PARAMS;
    _shipPoint
};

ITW_WarshipGetBases = {
    private _bases = [];
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        private _pt =  AslToAtl _fastTravelPoint;
        _bases pushBack [_pt,_shipDir,_pt,_pt];
    } forEach ITW_WS_Active;
    _bases
};

ITW_WarshipsAvailable = {
    !(ITW_WS_Active isEqualTo [])
};

ITW_WsPickPosDir = {
    // return [_pos,_dir] user selects or [] if canceled
    private _pos = [true,localize "STR_ITW_MISC_ChooseShipLoc"] call SKL_LocationSelection;
    if (isNil "_pos" || {_pos isEqualTo []}) exitWith {[]};
    private _mrkr = createMarkerLocal ["mWsPos", _pos];
    _mrkr setMarkerColorLocal "ColorBLUE";
    _mrkr setMarkerSizeLocal [1,1];
    _mrkr setMarkerTypeLocal "c_ship";
    
    ITW_DRAW_LINE_PT1 = _pos;
    ITW_DRAW_LINE_PT2 = _pos;
    private _mouseMoveEH = findDisplay 12 displayCtrl 51 ctrlAddEventHandler ["MouseMoving",
        {
            params ["_control", "_xPos", "_yPos", "_mouseOver"];
            ITW_DRAW_LINE_PT2 = (_control ctrlMapScreenToWorld [_xPos,_yPos]);
        }];
    private _drawLineEH = (findDisplay 12 displayCtrl 51) ctrlAddEventHandler ["Draw",
        {
            params ["_controlOrDisplay"];
            _controlOrDisplay drawLine [
                ITW_DRAW_LINE_PT1,
                ITW_DRAW_LINE_PT2,
                [0,0.33,0.66,1],
                7
            ];
        }];
    private _pos2 = [true,localize "STR_ITW_MISC_ChooseShipDir"] call SKL_LocationSelection;
    findDisplay 12  displayCtrl 51 ctrlRemoveEventHandler ["MouseMoving", _mouseMoveEH];
    findDisplay 12  displayCtrl 51 ctrlRemoveEventHandler ["Draw", _drawLineEH];
    deleteMarkerLocal _mrkr;
    if (isNil "_pos2" || {_pos2 isEqualTo []}) exitWith {[]};
    private _dir = _pos getDir _pos2;
    [_pos,_dir];
};

ITW_WsSelect = {
    // return the ITW_WS_Active array index selected or -1 if canceled
    private _count = count ITW_WS_Active;
    if (_count == 0) exitWith {hint localize "STR_ITW_MISC_NoWarships";-1};
    
    private _pos = [true,localize "STR_ITW_MISC_ChooseShip"] call SKL_LocationSelection;
    if (isNil "_pos" || {_pos isEqualTo []}) exitWith {-1};
    
    private _closestIndex = -1;
    private _closestDist = 1e15;
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        private _dist = _pos distanceSqr _shipPoint;
        if (_dist < _closestDist) then {
            _closestDist = _dist;
            _closestIndex = _forEachIndex;
        };
    } forEach ITW_WS_Active;
    _closestIndex
};

ITW_WsPlace = {
    // call on server
    if !(isServer) exitWith {_this remoteExec ["ITW_WsPlace",2]};
    
    
    params ["_shipIndex","_posDir"];
    private _shipInfo = ITW_WS_WARSHIPS#_shipIndex;
    _shipInfo params WARSHIP_INFO_PARAMS;
    _posDir params ["_shipPt","_shipDir"];
    
    private _rotatePos = { 
        params ['_offset','_center','_angle'];
        private _vect = [_offset, -_angle] call BIS_fnc_rotateVector2D;
        private _newPos = _center vectorAdd _vect;
        _newPos
    };
    
    private _warship = _shipClass createVehicle _shipPt; 
    _warship setdir (_shipDir + _dirOffset);   
    _warship setPosASLW [getPosASLW _warship select 0,getPosASLW _warship select 1,0];   
    [_warship] call BIS_fnc_Carrier01PosUpdate;
    sleep 2;
    
    // get height of deck offset (it seems to be slightly different each time
    private _repairPoint = [_repairPt,_shipPt,_shipDir] call _rotatePos;
    private _decks = nearestObjects [_repairPoint,["AirportBase","Helipad_base_F","Land_EF_LPD_hull_01"],_shipSize,false];
    private _deckOffsetASL = if (_decks isEqualTo []) then {_deckOffset} else {(getPosASL (_decks#0))#2 + _deckOffset};
    
    // marker
    private _mrkrName = format ["mWarship%1",time];
    private _shipMrk = createMarkerLocal [_mrkrName, _shipPt];
    _shipMrk setMarkerColorLocal "ColorWEST";
    _shipMrk setMarkerSizeLocal [1,1];
    _shipMrk setMarkerTextLocal _shipName;
    _shipMrk setMarkerType "c_ship";
    
    // Repair
    _repairPoint set [2,_repairPoint#2 + _deckOffsetASL];
    [_repairPoint,_shipSize] call ITW_vehRepairPoint;
    
    // Garage
    private _garagePoint = [_garagePt,_shipPt,_shipDir] call _rotatePos;
    _garagePoint set [2,_garagePoint#2 + _deckOffsetASL + 0.2];
    ITW_Garages pushback (if (_shipClass in ["Land_EF_LPD_base"]) then {_garagePoint} else {AslToAtl _garagePoint}); // some seem to use ASL vs ATL
    publicVariable "ITW_Garages";
    
    // Officer
    private _pos = [_officerPt,_shipPt,_shipDir] call _rotatePos;
    _pos set [2,_pos#2 + _deckOffsetASL];
    private _officer = selectRandom ITW_BaseOfficerTypes createVehicle _pos;
    _officer setDir (_officerDir + _shipDir);
    _officer setPosASL _pos;
    [_officer] call ITW_BaseOfficerSetup; 

    // Arsenal
    _pos = [_arsenalPt,_shipPt,_shipDir] call _rotatePos;
    _pos set [2,_pos#2 + _deckOffsetASL];
    private _va = "Land_OfficeCabinet_02_F" createVehicle _pos;
    _va setDir (_arsenalDir + _shipDir);
    _va setPosASL _pos;
    _va enableSimulationGlobal false;
    [[_va]] remoteExec ["CustomArsenal_AddVAs",0,true];
    [[_va]] remoteExec ["ITW_BaseVaActions",0,true];
    
    // Fast Travel Point
    private _fastTravelPoint = [_fastTravelPt,_shipPt,_shipDir] call _rotatePos;
    _fastTravelPoint set [2,_fastTravelPoint#2 + _deckOffsetASL];
    
    ITW_WS_Active pushBack [_shipPt,_shipDir,_shipIndex,_shipMrk,_repairPoint,_garagePoint,_fastTravelPoint,createHashMap];
    publicVariable "ITW_WS_Active";
    ITW_WS_AtkHashReset = true;
    publicVariable "ITW_WS_AtkHashReset";
};

ITW_WsEnsureVector = {
    params ["_objIndex"];
    private _done = true;
    private _spawnPt = [0,0,0];
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        if !(_objIndex in _attackMap) exitWith {_done = false};
    } count ITW_WS_Active;
    if (_done) exitWith {};
    
    // need to calculate warship vectors to this objectiveport_01_F" createVehicle [0,0,0];
    private _boat = "B_Boat_Transport_01_F" createVehicle _spawnPt;
    _boat allowDamage false;
    private _agent2 = createAgent ["C_man_1", _spawnPt, [], 0, "NONE"];
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
        if (!isNil "ITW_WsPathDist") exitWith {};
        private _prevPos = [0,0,0];
        private _dist = 0;
        {
            if (_forEachIndex > 0) then {
                _dist = _dist + (_x distance2D _prevPos);
            };
            _prevPos = _x;
        } forEach _path;
        if (_dist == 0) then {_dist = 1e10};
        ITW_WsPathDist = _dist;
    }];
    
    {
        _x params WARSHIP_ACTIVE_PARAMS;
        if !(_objIndex in _attackMap) then {
            private _objPt = ITW_Objectives#_objIndex#ITW_OBJ_POS;
            private _distArray = [2e10,2e10]; // numbers more than max _xxDistMin in ITW_WarshipAttackVector
            _distArray set [WARSHIP_ATK_MAP_AIR,_objPt distance _shipPoint];
            private _objSeaPts = ITW_SeaPoints#_objIndex;
            if !(_objSeaPts isEqualTo []) then {
                ITW_WS_WARSHIPS#_shipIndex params WARSHIP_INFO_PARAMS;
                private _seaPt1 = _shipPoint getPos [_shipSize + 50,_shipPoint getDir _objPt];
                private _seaPt2 = _objSeaPts#0;
                _boat setPosASL _seaPt1;
                while {vehicle _agent2 == _agent2} do {
                    _agent2 moveInDriver _boat;
                    sleep 0.2;
                };
                ITW_WsPathDist = nil; // distance, point path-ed to
                _agent2 setDestination [_seaPt2, "LEADER PLANNED", true];
                private _timeout = time + 6;
                waitUntil {time > _timeout || {!isNil "ITW_WsPathDist"}}; 
                doStop _agent2;
                _boat engineOn false;
                if !(isNil "ITW_WsPathDist") then {
                    _distArray set [WARSHIP_ATK_MAP_SEA,ITW_WsPathDist];
                }; 
            };
            _attackMap set [_objIndex,_distArray];        
        };
    } forEach ITW_WS_Active;
    
    _boat deleteVehicleCrew _agent2;
    deleteVehicle _boat;
    deleteVehicle _agent2; // in case agent got out of boat
    
};

ITW_WarshipAttackVector = {
    // given an objective index, return active warship index that can attack that objective or -1, [_airIndex,_seaIndex]
    params ["_objIndex","_isFriendly"];
    if (!_isFriendly || {count ITW_WS_Active == 0}) exitWith {[-1,-1]};
    
    if (!isNil "ITW_WS_AtkHashReset") then {ITW_WS_AtkHash = nil;ITW_WS_AtkHashReset = nil};
    if (isNil "ITW_WS_AtkHash") then {ITW_WS_AtkHash = createHashMap};
    
    if !(_objIndex in ITW_WS_AtkHash) then {
        [_objIndex] call ITW_WsEnsureVector; // make sure _attackMap hashmap has _objIndex setup
        
        private _airDistMin = 1e10; // numbers less than _distArray defaults in ITW_WsEnsureVector
        private _seaDistMin = 1e10;
        private _airClosest = -1;
        private _seaClosest = -1;
        {
            _x params WARSHIP_ACTIVE_PARAMS;;        
            private _atkVector = _attackMap getOrDefault [_objIndex,[2e10,2e10]];
            _dAir = _atkVector#WARSHIP_ATK_MAP_AIR;
            _dSea = _atkVector#WARSHIP_ATK_MAP_SEA;
            if (_dAir < _airDistMin) then {
                _airDistMin = _dAir;
                _airClosest = _forEachIndex;
            };
            if (_dSea > 0 && {_dSea < _seaDistMin}) then {
                _seaDistMin = _dSea;
                _seaClosest = _forEachIndex;
            };
        } forEach ITW_WS_Active;
        
        ITW_WS_AtkHash set [_objIndex,[_airClosest,_seaClosest]];
    };

    private _return = ITW_WS_AtkHash get _objIndex;
    
    _return
};

ITW_WarshipLoad = {
    params ["_warshipData"];
    {
        _x params ["_shipPoint","_shipDir","_shipIndex"];
        ITW_WS_WARSHIPS#_shipIndex params WARSHIP_INFO_PARAMS;
        if (isClass (configFile >> "cfgVehicles" >> _shipClass)) then {
            [_shipIndex,[_shipPoint,_shipDir]] call ITW_WsPlace;
        };
    } forEach _warshipData;
};

ITW_WarshipSave = {
    private _warshipsData = 
        ITW_WS_Active apply {
            _x params WARSHIP_ACTIVE_PARAMS;
            [_shipPoint,_shipDir,_shipIndex]
        };
    _warshipsData
};


["ITW_WarshipAdd"] call SKL_fnc_CompileFinal;
["ITW_WarshipMove"] call SKL_fnc_CompileFinal;
["ITW_WarshipRemove"] call SKL_fnc_CompileFinal;
["ITW_WsPickPosDir"] call SKL_fnc_CompileFinal;
["ITW_WsSelect"] call SKL_fnc_CompileFinal;
["ITW_WsPlace"] call SKL_fnc_CompileFinal;
["ITW_WarshipLoad"] call SKL_fnc_CompileFinal;
["ITW_WarshipSave"] call SKL_fnc_CompileFinal;
["ITW_WarshipGarageDir"] call SKL_fnc_CompileFinal;
["ITW_WarshipCarrierPositions"] call SKL_fnc_CompileFinal;
["ITW_WarshipGetPos"] call SKL_fnc_CompileFinal;
["ITW_WarshipGetBases"] call SKL_fnc_CompileFinal;
["ITW_WarshipsAvailable"] call SKL_fnc_CompileFinal;
["ITW_WsEnsureVector"] call SKL_fnc_CompileFinal;
["ITW_WarshipAttackVector"] call SKL_fnc_CompileFinal;