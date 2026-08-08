// This script must be run on all clients prior to calls to SKL_HeliExtract (on the server)
// use this in the init:   
//    isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_HeliExtract.sqf";}; 
//
// Setup a comm menu item run on each client: 
//        [player, transport, nil, nil, ""] call BIS_fnc_addCommMenuItem;
// And in the description.ext:
//  class CfgCommunicationMenu
//  {
//  	class transport
//  	{
//  		text = "Call in helicopter transport";		// Text displayed in the menu and in a notification
//  		submenu = "#USER:SKL_HE_SubMenu"; // Submenu opened upon activation (expression is ignored when submenu is not empty.)
//  		expression = "";	// Code executed upon activation
//  		icon = "\a3\Ui_f\data\GUI\Cfg\CommunicationMenu\transport_ca.paa";				// Icon displayed permanently next to the command menu
//  		cursor = "\a3\Ui_f\data\IGUI\Cfg\Cursors\iconCursorSupport_ca.paa";				// Custom cursor displayed when the item is selected
//  		enable = "1";					// Simple expression condition for enabling the item
//  		removeAfterExpressionCall = 0;	// 1 to remove the item after calling
//  	};
//  };
//
//  Now add the code that gets called to setup a new heli
// SKL_HE_NEW_HELI_FN = {
//    _pos = getPosATL player;
//    _heli = "Heli_Light_01_unarmed_base_F";
//    [_pos, _heli, player] call SKL_HeliExtract;
// };
//
// 
// To get helicopters with cargo seats:
// _heliTransports = [];
// {
//     _className = _x;
//     _totalSeats = [_className, true] call BIS_fnc_crewCount; // Number of total seats: crew + cargo/passengers
//     _crewSeats = [_className, false] call BIS_fnc_crewCount; // Number of crew seats only
//     _cargoSeats = _totalSeats - _crewSeats; // Number of total cargo/passenger seats
//     if (_cargoSeats > count playableUnits) then {
//         _heliTransports pushBack _className;
//     };
// } forEach va_pHeliClasses;
// if (count _heliTransports == 0) then {            
//     _heliTransports = ["O_Heli_LigSKL_02_F"];
// };           

#define SKL_HE_DEBUG false

SKL_HE_Helicopters = [];

SKL_HE_SubMenu = [
	[localize "STR_SKL_HE_HelicopterExtract", false],
	[localize "STR_SKL_HE_NewHelicopter", [2], "", -5, [["expression", "[] spawn SKL_HE_New_Heli;"]], "1", "1"]
  //["B-Alpha-1", [3], "#USER:HT-B-Alpha-1-MENU", -5, [], "1", "1"]
];

SKL_HE_HELI_Menu_Fmt = "
    SKL_HE_%1_SubMenu = [
        ['%1', false],
        [localize 'STR_SKL_HE_MoveTo', [2], '', -5, [['expression', '[""%1""] spawn SKL_HE_Move_To;']], '1', '1'],
        [localize 'STR_SKL_HE_AllDone',[3], '', -5, [['expression', '[""%1""] spawn SKL_HE_All_Done;']], '1', '1']
    ]; 
    SKL_HE_SubMenu deleteAt (count SKL_HE_SubMenu - 1);
    SKL_HE_SubMenu pushBack ['%1',[%2],'#USER:SKL_HE_%1_SubMenu',-5,[],'1','1'];
	SKL_HE_SubMenu pushBack [localize 'STR_SKL_HE_NewHelicopter', [%2+1], '', -5, [['expression', '[] spawn SKL_HE_New_Heli;']], '1', '1']

";

SKL_HE_SendMessage = {
    // call on each client
    params ["_sender","_message",["_playAudio",false]];
    [_sender, format ["%1<br /><br /><br /><br /><br /><br />",_message]] call BIS_fnc_showSubtitle;
    if (SKL_HE_DEBUG) then {diag_log format ["SKL_HE_SendMessage: %1: %2",_sender,_message]};
    
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

SKL_HE_New_Heli = {
    private _pos = call SKL_HE_Pos_Select;
    if !(_pos isEqualTo []) then {
        if (isNil "SKL_HE_NEW_HELI_FN") then {
            private _heliType = "Heli_Light_01_unarmed_base_F";
            [_pos, player, _heliType] remoteExec ["SKL_HeliExtract",2];
        } else {
            [_pos,player] remoteExec ["SKL_HE_NEW_HELI_FN",2];
        };
    } else {
        hint localize "STR_SKL_HE_TransportCanceled";
    };
};

SKL_HE_Move_To = {
    params ["_pilotName"];
    private _heli = [_pilotName] call SKL_HE_Veh_From_Pilot;
    if (isNull _heli) exitWith {hint localize "STR_SKL_HE_PilotNotResponding"};
    private _pos = call SKL_HE_Pos_Select;
    if !(_pos isEqualTo []) then {
        [_pos,player,_heli] remoteExec ["SKL_HeliExtract",2];
    };
};
    
SKL_HE_Pos_Select = {
    // hack to work with older missions that don't have SKL_LocationSelection.sqf
    if (isNil "SKL_HE_LocationSelect") then {
        if (fileExists "scripts\Skull\SKL_LocationSelection.sqf") then {
            SKL_HE_LocationSelect = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_LocationSelection.sqf";
        } else {
            SKL_HE_LocationSelect = 0;
        };
    };   
    if (typeName SKL_HE_LocationSelect == "CODE") exitWith {[] call SKL_HE_LocationSelect};
    
    private _pos = [0,0,0];
    if (!visibleMap && {vehicle player == player}) then {
        private _beg = eyePos player;
        private _end = _beg vectorAdd (player weaponDirection currentWeapon player vectorMultiply 3000);
        _pos = terrainIntersectAtASL [_beg,_end];
    };
    if !(_pos isEqualTo [0,0,0]) then {
        _pos set [2,0];
    } else {
        private _hint = localize "STR_SKL_HE_SelectNewLz";
        SKL_HE_Pos = nil;
        // get user selected position   
        onMapSingleClick {
            if (!_alt && !_shift) then {
                SKL_HE_Pos = _pos;
                openMap false; 
            };
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
        };
        onMapSingleClick "";
        hintSilent "";
        if (isNil "SKL_HE_Pos") then {SKL_HE_POS = []};
        _pos = SKL_HE_POS;
    }; 
    _pos
};

SKL_HE_All_Done = {
    params ["_pilotName"];
    if (SKL_HE_DEBUG) then {diag_log ["SKL_HE_All_Done",_pilotName]};    
    private _heli = [_pilotName] call SKL_HE_Veh_From_Pilot;
    if (isNull _heli) exitWith {hint localize "STR_SKL_HE_PilotNotResponding"};
    private _pilot = currentPilot _heli;
    private _crew = _heli getVariable ["HE_HeliCrew",[]];
    private _cargo = (crew _heli select {alive _x}) - _crew - [_pilot];
    private _pilotName = if (isNull _pilot) then {"HQ"} else {str _pilot};
    if (count _cargo > 0) then {
        [_pilotName,localize "STR_SKL_HE_UnableToWithdraw",true] call SKL_HE_SendMessage;
    } else {
        [[],player,_heli] call SKL_HeliExtract;
    };
};

SKL_HE_Veh_From_Pilot = {
    params ["_pilotName"];
    private _heli = objNull;
    {
        private _name = _x getVariable ["SKL_HE_DRIVER","<NONE>"];
        
        if (_name == _pilotName) exitWith {
            _heli = _x;
        };
    } forEach SKL_HE_Helicopters;
    _heli
};

SKL_HE_HelicopterCanFly = {
	params ["_heli","_checkPilot"];
	private _return = true;
    private _pilotOkay = true;
	if (_checkPilot) then { _pilotOkay = alive (currentPilot _heli); };
	if (alive _heli && _pilotOkay) then {
		_damageTypes = [
			["HitEngine",0.8],
			["HitHRotor",0.8],
			["HitVRotor",0.8],
			["HitTransmission",1.0],
			["HitHydraulics",0.9]
		];		
		{
			if (_heli getHitPointDamage (_x select 0) > (_x select 1)) exitWith {
				_return = false; // damaged
			};			
		} forEach _damageTypes;		  
	} else {
		_return = false;
	};
    if (_return) then {
        _return = (fuel _heli) > 0.1; // out of fuel
    };
	_return
};

SKL_HE_UpdateMenu = {
    if (!hasInterface) exitWith {};
    params ["_pilotName"];
    call compile format [SKL_HE_HELI_Menu_Fmt,_pilotName,count SKL_HE_SubMenu];
};

SKL_HE_RemoveMenu = {
    if (!hasInterface) exitWith {};
    params ["_pilotName"];
    private _index = SKL_HE_SubMenu findIf {_x#0 == _pilotName};
    if (_index > 0) then {
        {
           if (_x#0 == _pilotName) exitWith {
               SKL_HE_SubMenu deleteAt _forEachIndex; 
           };
           _x set [1,[_forEachIndex]];
        } forEachReversed SKL_HE_SubMenu;
    };
};

SKL_HE_Marker = {
    // call on all clients to show heli name/position on the map
    params ["_heli","_name"];
    // wait for the heli to be propigated and alive on the clients
    private _timeout = time + 10;
    waitUntil {sleep 1; alive _heli || time > _timeout};
    sleep 1; // wait for pilot as well
    private _readyName = _name + " - " + localize "STR_SKL_HE_Waiting";
    private _marker = createMarkerLocal [format ["sklhem_%1",time],_heli];
    _marker setMarkerShapeLocal "ICON";
    _marker setMarkerTypeLocal "b_air";
    _marker setMarkerTextLocal _name;
    while {[_heli,true] call SKL_HE_HelicopterCanFly} do {
        private _speed = speed _heli;
        if (_speed < 0.01 && {isTouchingGround _heli || getPosATL _heli #2 < 1}) then {
            _marker setMarkerTextLocal _readyName;
        } else {
            _marker setMarkerTextLocal _name;
        };
        _marker setMarkerPosLocal getPosATL _heli;
        private _delay = (if (_speed > 25) then {0.5} else {
                          if (_speed < 1 ) then {10} else {
                          1}});
        sleep _delay;
    };
    deleteMarkerLocal _marker;
};

SKL_HE_HeliSelect = {
    params ["_client","_helis",["_seatCnt",0]];
    _vehType = "Heli_Light_01_unarmed_base_F";
    SKL_HE_HELI_SELECTED = nil;
    [_helis,_seatCnt] remoteExec ["SKL_HE_HeliSelectMP",_client];
    private _timeout = time + 30;
    waitUntil {!isNil "SKL_HE_HELI_SELECTED" || time > _timeout};
    if (! isNil "SKL_HE_HELI_SELECTED") then {
        _vehType = SKL_HE_HELI_SELECTED;
    };
    _vehType
};

SKL_HE_HeliSelectMP = {
    // call on player's client
    // let player choose heli to use from list based on #seats available (returns "" if user cancelled)
    params ["_helis",["_seatCnt",0]]; // _seatCnt == 0 means ask
    
    // create map of [#seats,[heli,heli,...]]
    private _seatMap = createHashMap;
    {
        private _className = _x;
        private _vehType = _x;
        if (typeName _className == "ARRAY") then {_className = _x#0};
        _totalSeats = [_className, true] call BIS_fnc_crewCount; // Number of total seats: crew + cargo/passengers
        _crewSeats = [_className, false] call BIS_fnc_crewCount; // Number of crew seats only
        _cargoSeats = _totalSeats - _crewSeats; // Number of total cargo/passenger seats
        if (_cargoSeats > 0) then {
            private _vehArray = _seatMap getOrDefault [_cargoSeats,[]];
            _vehArray pushBack _vehType;
            _seatMap set [_cargoSeats,_vehArray];
        };       
    } forEach _helis;
    
    private _vehType = "";
    if (count _seatMap < 2) then {
        if (count _seatMap == 0) then {
             _vehType = "Heli_Light_01_unarmed_base_F";
        } else {       
            _vehType = selectRandom (_seatMap get ((keys _seatMap)#0));
        };
    } else {
        private _keys = keys _seatMap;
        _keys sort true;
        if (_seatCnt == 0) then {
            SKL_HE_SEAT_SEL = 0;
            if (fileExists "scripts\skull\SKL_CmdMenu.sqf") then {
                private _title = localize "STR_SKL_HE_HowManySeats";
                private _menu = [];
                {
                    private _num = _x;
                    _menu pushBack ["",str _num, format ["SKL_HE_SEAT_SEL = %1",_num]];
                } forEach _keys;
                if (isNil "SKL_CmdMenu") then {SKL_CmdMenu = compile preprocessFileLineNumbers "scripts\skull\skl_cmdmenu.sqf"};
                [_title,_menu] call SKL_CmdMenu;
            } else {
                SKL_HE_SEAT_MENU = [[localize "STR_SKL_HE_HowManySeats", false]];
                {
                    private _num = _x;
                    SKL_HE_SEAT_MENU pushBack [str _num, [0], "", -5, [["expression",format ["SKL_HE_SEAT_SEL = %1",_num]]],"1","1"];
                } forEach _keys;
                SKL_HE_SEAT_MENU pushBack [localize "STR_SKL_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
                showCommandingMenu "#USER:SKL_HE_SEAT_MENU";
                waitUntil {commandingMenu == ""};
            };
        } else {
            private _validKeys = _keys select {_x >= _seatCnt};
            if (_validKeys isEqualTo []) then {_validKeys = [_key#(count _keys - 1)]}; // use largest
            SKL_HE_SEAT_SEL = selectRandom _validKeys;
        };
        if (SKL_HE_SEAT_SEL > 0) then {
            _vehType = selectRandom (_seatMap get SKL_HE_SEAT_SEL);
        };
    };      
    SKL_HE_HELI_SELECTED = _vehType;
    publicVariableServer "SKL_HE_HELI_SELECTED";
};

SKL_HE_Parachute = {
    params ["_heli","_cargoUnits"];
    private _toggle = true;
    private _sleep = (40/speed _heli) min 0.5; // max of 1/2 sec delay 
    {
        private _unit = _x;
        if (!alive _unit || {vehicle _unit != _heli}) then {continue};
        private _dirTo = getDir _heli;
        private _vPos = getPosASL _heli;
        private _pos = if (_toggle) then {_heli modeltoWorld [7, -30, -20]} else {_heli modeltoWorld [-7, -30, -20]};
        if (_pos#2 < 0) then {_pos set [2,0]};
        _toggle = !_toggle;
        private _para = "Steerable_Parachute_F" createVehicle _pos;
        _unit allowDamage false;
        _para setPos _pos;
        unassignVehicle _unit;
        moveOut _unit;
        private _timeout = time + 3;
        waitUntil {vehicle _unit == _unit || {time > _timeout}};
        _unit moveindriver _para;
        _para lock false;
        sleep _sleep;
    } count _cargoUnits;
    sleep 1;
     {_x allowDamage true} forEach _cargoUnits;
};

SKL_HeliExtract = {
    // spawn on the server if not running on server
    if (!isServer) exitWith {_this remoteExec ["SKL_HeliExtract",2]};

    // init is code that is run on helicopter once it's crew has been added, but before cargo has been added     _heli call _init
    params ["_lzPos","_playerCalling",["_vehType","Heli_Light_01_unarmed_base_F",["",objNull,[]]],["_pilotClass",""],["_pilotSide",playerSide],["_spawnPos",[]],["_init",{}],["_cargoUnits",[]],["_paradrop",false]];
    
    // vehType is ether the string type for new heli, or the actual helicopter for updates
    if (typeName _vehType == "OBJECT") exitWith {
        // Update to already running helicopter, if _lzPos == [] then heli will withdraw
        if (SKL_HE_DEBUG) then {diag_log ["SKL_HeliExtract: update lz",_vehType,_lzPos]};
        private _heli = _vehType;
        _heli setVariable ["NEW_LZ",_lzPos];
        private _callers = _heli getVariable ["SKL_HE_CALLERS",[]];
        _callers pushBackUnique _playerCalling;
        _heli setVariable ["SKL_HE_CALLERS",_callers];
    };
    
    if (SKL_HE_DEBUG) then {diag_log format ["HT: HeliExtract %1", _this]};
     
    if (_spawnPos isEqualTo []) then {
        _spawnPos = _lzPos getPos [2500, random 360];
    };
    _spawnPos set [2, 40];
    
    // Spawn vehicle
    private _texture = false;
    private _anim = false;
    if (typeName _vehType == "ARRAY") then {
        // can be:
        //  "Heli_Class_Name"                                     class name
        //  ["Heli_Class_Name",[texture info],[animation info]]   [class,texture,anim] 
        //       example texture: ["AAF",1]                       string,number
        //       example anim:    ["AddBenches",1,"AddTread",0]   array of string,number,...
        //  array of the above types
        private _cnt = count _vehType;
        if (_cnt < 2) then {
            if (_cnt == 1) then {
                // array of one, so choose the one
                _vehType = _vehType#0;
            } else {
                // empty array, use default heli type
                _vehType = "Heli_Light_01_unarmed_base_F";
            };
        } else {
            if (typeName (_vehType#0) == "STRING" && {typeName (_vehType#1) == "ARRAY" && {typeName (_vehType#1#1 == "SCALAR")}}) then {
                // _vehType is just a single heli with texture/anim, so leave it as is
            } else {
                // array of helis, let player choose based on seats needed
                _vehType = [_playerCalling,_vehType,count _cargoUnits] call SKL_HE_HeliSelect;
            };
        };
    };
    if (_vehType isEqualTo "") exitWith {hint "Heli request cancelled"};        
    if (typeName _vehType == "ARRAY") then {
        _texture = _vehType#1;
        if (count _vehType > 2) then {_anim = _vehType#2};
        _vehType = _vehType#0;
    };
    private _heli = createVehicle [_vehType, _spawnPos, [], 0, "FLY"];
    _heli setPos _spawnPos; // not ATL since it needs to work over water
    createVehicleCrew _heli;	
    private _heliGroup = createGroup [_pilotSide,false];
    (crew _heli) joinSilent _heliGroup;	
    _heliGroup deleteGroupWhenEmpty true;
    sleep 0.05;
    [_heli,_texture,_anim] call BIS_fnc_initVehicle;
    waitUntil {!isNull (currentPilot _heli)};	
    {
        _x addCuratorEditableObjects [[_heli],true]; 
    } forEach allCurators;
    _heli setVariable ["HE_HeliCrew",units _heliGroup,true];
    
    // move pilot to his own group so we can disable autocombat
    private _driver = driver _heli;
    _driver disableAI "MINEDETECTION";
    _driver disableAI "TEAMSWITCH";
    _driver disableAI "FSM";
    _driver setBehaviour "AWARE";
    _driver setSkill ["courage",1];
    _driver allowFleeing 0;
    
    _heliGroup setBehaviour "COMBAT";
    _heliGroup setCombatMode "YELLOW";
    
    if (isNil "SKL_HE_PILOT_NAMES" || {SKL_HE_PILOT_NAMES isEqualTo []}) then {
        private _shuffle = false;
        if (isNil "SKL_HE_PILOT_NAMES") then {_shuffle = true};
        SKL_HE_PILOT_NAMES = ["Magnet","Scarecrow","Duster","Boxer","Piggy","Birdie","Falcon","Mojo","Patriot","Spider","Casper","Dizzy","Eagle"];
        if (_shuffle) then {SKL_HE_PILOT_NAMES = SKL_HE_PILOT_NAMES call BIS_fnc_arrayShuffle};
    };
    private _pilotName = SKL_HE_PILOT_NAMES#0;
    SKL_HE_PILOT_NAMES deleteAt 0;
    _heli setVariable ["SKL_HE_DRIVER",_pilotName,true];
    _heli setVariable ["SKL_HE_CALLERS",[_playerCalling]];
    
    [_pilotName] remoteExec ["SKL_HE_UpdateMenu",0];
    
    SKL_HE_Helicopters pushBack _heli;
    publicVariable "SKL_HE_Helicopters";
    
    _heli call _init;
    
    if !(_cargoUnits isEqualTo []) then {
        _cargoUnits apply {_x moveInAny _heli};
        [_pilotName,_cargoUnits] spawn {
            params ["_pilotName","_cargoUnits"];
            sleep 5;
            private _unitsNotInHeli = _cargoUnits select {vehicle _x == _x};
            if (count _unitsNotInHeli > 0) then {
                {deleteVehicle _x} forEach _unitsNotInHeli;
                [_pilotName,localize "STR_SKL_HE_CargoShort",true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
            };
        };
    };	
    
    private _seats = _heli emptyPositions "Cargo";
    private _text = format [localize "STR_SKL_HE_ExtractUpdateFMT", _pilotName, _seats];
    [_pilotName, _text, true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
        
    [_heli,_pilotName] remoteExec ["SKL_HE_Marker",0,_heli];
    
    sleep 5;
        
    private _break = false;     
    private _allDone = false;
    private _first = true;
    private _exitPos = _lzPos;
    
    while {!(_break || {(_exitPos isEqualTo [])})} do {
        if (!_break && !(_exitPos isEqualTo [])) then {
            _heli engineOn true;
            if (!_first) then {
                if (getPosATL _heli #2 < 0.4) then {
                    [_pilotName, localize "STR_SKL_HE_OnTheMove", true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]]
                } else {
                    [_pilotName, localize "STR_SKL_HE_LzUpdated", true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]]
                };
            };
            _first = false;
            if (_heli distance2D _exitPos > 50) then {
                {deleteWaypoint _x} forEachReversed waypoints _heliGroup;
                private _wpExtract = _heliGroup addWaypoint [_exitPos, 0];
                _wpExtract setWaypointSpeed "FULL";
                _wpExtract setWaypointType "MOVE";
                _wpExtract setWaypointStatements ["TRUE", "vehicle this land 'GET IN'"];
            } else {
                _heli land "GET IN";
            };
            
            // wait for heli to arrive at location
            waitUntil {sleep 1; (((getPosATL _heli) select 2) > 20) || {!(_heli getVariable ["NEW_LZ",0] isEqualTo 0) || {!alive _heli}}};
            _heli allowDamage true;
                   
            if (_paradrop && {!(_cargoUnits isEqualTo [])}) then {
                // parachute cargo and then heli is done
                waitUntil {sleep 3;getPosATL _heli distance2D _exitPos < 150 || {!(_heli getVariable ["NEW_LZ",0] isEqualTo 0) || {!alive _heli}}}; 
                if (getPosATL _heli distance2D _exitPos < 160) then {
                    [_pilotName,localize "STR_SKL_HE_CargoDropped",true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
                    [_heli,_cargoUnits] remoteExec ["SKL_HE_Parachute",_cargoUnits#0];
                    waitUntil {{vehicle _x == _heli && alive _x} count _cargoUnits == 0};
                    _cargoUnits join group _playerCalling;
                    _cargoUnits = [];
                    _paradrop = false;
                    [[],_playerCalling,_heli] call SKL_HeliExtract;
                    sleep 5;
                };
            } else {            
                // try to get heli to stay low while landing by limiting it's speed near enemy
                private _enemySides = [_pilotSide] call BIS_fnc_enemySides;
                private _allEnemies = allUnits select {side _x in _enemySides};
                
                // get closest enemy
                private _enemyDists = _allEnemies apply {[_exitPos distanceSqr _x,_x]};
                _enemyDists sort true;
                private _enemyPos = getPosATL ((_enemyDists#0) param [1,objNull]);
                
                private _speedCheckTime = 0;
                private _inBound = ((_heli distance _enemyPos) > (_exitPos distance _enemyPos));
                
                while {(((getPosATL _heli) select 2) > 10) && {(_heli getVariable ["NEW_LZ",0] isEqualTo 0) && {alive _heli}}} do {
                    if (time > _speedCheckTime) then {
                        _speedCheckTime = time + 5;
                        private _distToAo = _enemyPos distance _heli;
                        private ["_speed","_height"];
                        switch (true) do {
                            case (_distToAo < 1000): {_speed =  80;_height = 20};
                            case (_distToAo < 2500): { // speed 200, height 40 @ 2500
                                _speed = _distToAo/12.5;
                                _height = _distToAo/75 + 6.67;
                            };
                            default{ // speed 500, height 50 @ 3000
                                _speed = _distToAo*0.6 - 1300;
                                _height = _distToAo/50 - 10;
                            };
                        };
                        if (_inBound) then {_heli limitSpeed _speed}; // allow full speed exiting the AO
                        _heli flyInHeight _height;
                    };
                    sleep 1;
                };
                _heli allowDamage false;
            
                waitUntil {sleep 3;getPosATL _heli #2 < 0.4 || {isTouchingGround _heli || {!(_heli getVariable ["NEW_LZ",0] isEqualTo 0) || {!alive _heli}}}};            
                _heli limitSpeed 500;
                _heli flyInHeight 30;
            };
                      
            if ([_heli,true] call SKL_HE_HelicopterCanFly) then {
                if (_heli getVariable ["NEW_LZ",0] isEqualTo 0) then {
                    [_pilotName, localize "STR_SKL_HE_ArrivedAtLz", true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
                    if !(_cargoUnits isEqualTo []) then {
                        // cargo unit now join player group
                        [_cargoUnits] remoteExec ["doGetout",_cargoUnits#0];
                        _cargoUnits join group _playerCalling;
                        _cargoUnits = [];
                    };
                };
            } else {
                _break = true;   
            };
        };
        
        private _newLz = _heli getVariable ["NEW_LZ",nil];
        if (!isNil "_newLz") then {
            _heli land "NONE"; // cancel landing
            _exitPos = _newLz;
            _heli setVariable ["NEW_LZ",nil];
        } else {        
            _heli disableAI "MOVE";
            private _waitTime = time;
            _exitPos = nil;
            waitUntil {
                if (time - _waitTime > 60) then {
                    _waitTime = 1e10;
                    _heli engineOn false;
                };
                if !([_heli,true] call SKL_HE_HelicopterCanFly) exitWith {
                    _break = true;
                    true
                };
                sleep 1;
                _heli setVelocity [0, 0, 0];
                private _newLz = _heli getVariable ["NEW_LZ",nil];
                if (!isNil "_newLz") then {
                    _exitPos = _newLz;
                    _heli setVariable ["NEW_LZ",nil];
                };
                !(isNil "_exitPos")
            };
            _heli enableAI "MOVE";  
        };
    };
   
    // remove action
    [_pilotName] remoteExec ["SKL_HE_RemoveMenu",0];
    SKL_HE_Helicopters = SKL_HE_Helicopters - [_heli];
    publicVariable "SKL_HE_Helicopters";
    
    if (!_break) then {
        [_pilotName, localize "STR_SKL_HE_WeAreDone", true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
        _heli setVariable ["SKL_HE_CALLERS",nil];
        private _exitPos = _spawnPos;
        if (getPosATL _heli distance _exitPos < 1000) then {
            _exitPos = _exitPos getPos [2500, random 360];
        };
        _exitPos set [2, 40];
        {deleteWaypoint _x} forEachReversed waypoints _heliGroup;
        private _wpExit = _heliGroup addWaypoint [_exitPos, 80];
        _wpExit setWaypointType "MOVE";
        _wpExit setWaypointStatements ["TRUE", "private _veh = vehicle this; deleteVehicleCrew _veh; deleteVehicle _veh;"];
        _heli allowDamage true;
        sleep 60;      
    } else {
        private ["_who","_msg"];
        if (!alive _heli || {!alive _driver}) then {
            sleep 10;
            _who = "HQ";
            _msg = format [localize "STR_SKL_HE_LostContactFMT",_pilotName];
        } else {
            _who = _pilotName;
            _msg = format [localize "STR_SKL_HE_WeAreGrounded",_pilotName];
        };
        
        [_who, _msg, true] remoteExec ["SKL_HE_SendMessage",_heli getVariable ["SKL_HE_CALLERS",0]];
    };
    waitUntil {sleep 60; isNull _heli || {_heli distance _x < 500} count allPlayers == 0};
    if (!isNull _heli) then {{deleteVehicle _x} forEach units _heliGroup; deleteVehicle _heli};
};

_compileFinal = {
    params [["_var","",[""]], ["_ns",missionNamespace,[missionNamespace]]];
    private _code = _ns getVariable [_var, 0];
    if (typeName _code != typeName {}) exitWith {};
    _codestr = str _code;
    _codestr = _codestr select [1,count _codestr - 2]; // remove begin and end parenthesizes 
    _code = compileFinal _codestr;
    _ns setVariable [_var, _code];
};
["SKL_HE_SendMessage"] call _compileFinal;
["SKL_HE_New_Heli"] call _compileFinal;
["SKL_HE_Move_To"] call _compileFinal;
["SKL_HE_Pos_Select"] call _compileFinal;
["SKL_HE_All_Done"] call _compileFinal;
["SKL_HE_Veh_From_Pilot"] call _compileFinal;
["SKL_HE_HelicopterCanFly"] call _compileFinal;
["SKL_HE_UpdateMenu"] call _compileFinal;
["SKL_HE_RemoveMenu"] call _compileFinal;
["SKL_HE_Marker"] call _compileFinal;
["SKL_HeliExtract"] call _compileFinal;
["SKL_HE_HeliSelect"] call _compileFinal;
["SKL_HE_HeliSelectMP"] call _compileFinal;
["SKL_HE_Parachute"] call _compileFinal;