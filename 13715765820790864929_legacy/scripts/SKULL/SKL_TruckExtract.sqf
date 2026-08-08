// This script must be run on all clients prior to calls to SKL_TruckExtract (on the server)
// use this in the init:   
//    isNil {call compile preprocessFileLineNumbers "scripts\Skull\SKL_TruckExtract.sqf";}; 
//
// Setup a comm menu item run on each client: 
//        [player, transport, nil, nil, ""] call BIS_fnc_addCommMenuItem;
// And in the description.ext:
//  class CfgCommunicationMenu
//  {
//  	class transport
//  	{
//  		text = "Call in truck transport";		// Text displayed in the menu and in a notification
//  		submenu = "#USER:SKL_TE_SubMenu"; // Submenu opened upon activation (expression is ignored when submenu is not empty.)
//  		expression = "";	// Code executed upon activation
//  		icon = "\a3\Ui_f\data\GUI\Cfg\CommunicationMenu\transport_ca.paa";				// Icon displayed permanently next to the command menu
//  		cursor = "\a3\Ui_f\data\IGUI\Cfg\Cursors\iconCursorSupport_ca.paa";				// Custom cursor displayed when the item is selected
//  		enable = "1";					// Simple expression condition for enabling the item
//  		removeAfterExpressionCall = 0;	// 1 to remove the item after calling
//  	};
//  };
//
//  Now add the code that gets called to setup a new truck
// SKL_TE_NEW_TRUCK_FN = {
//    params ["_lzPos","_player"];
//    _truck = "C_Van_02_transport_F";
//    [_lzPos, _player, _truck] call SKL_TruckExtract;
// };
//
// 
// To get trucks with cargo seats:
// _truckTransports = [];
// {
//     _className = _x;
//     _totalSeats = [_className, true] call BIS_fnc_crewCount; // Number of total seats: crew + cargo/passengers
//     _crewSeats = [_className, false] call BIS_fnc_crewCount; // Number of crew seats only
//     _cargoSeats = _totalSeats - _crewSeats; // Number of total cargo/passenger seats
//     if (_cargoSeats > count playableUnits) then {
//         _truckTransports pushBack _className;
//     };
// } forEach va_pCarClasses;
// if (count _truckTransports == 0) then {            
//     _truckTransports = ["C_Van_02_transport_F"];
// };           

SKL_TE_DEBUG = false;
SKL_TE_LocationSelection = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_LocationSelection.sqf";

SKL_TE_Trucks = [];

SKL_TE_SubMenu = [
	[localize "STR_SKL_TE_Extract", false],
	[localize "STR_SKL_TE_NewTruck", [2], "", -5, [["expression", "[] spawn SKL_TE_New_Truck;"]], "1", "1"]
  //["B-Alpha-1", [3], "#USER:HT-B-Alpha-1-MENU", -5, [], "1", "1"]
];

SKL_TE_TRUCK_Menu_Fmt = "
    SKL_TE_%1_SubMenu = [
        ['%1', false],
        [localize 'STR_SKL_HE_MoveTo', [2], '', -5, [['expression', '[""%1""] spawn SKL_TE_Move_To;']], '1', '1'],
        [localize 'STR_SKL_HE_AllDone',[3], '', -5, [['expression', '[""%1""] spawn SKL_TE_All_Done;']], '1', '1']
    ]; 
    SKL_TE_SubMenu deleteAt (count SKL_TE_SubMenu - 1);
    SKL_TE_SubMenu pushBack ['%1',[%2],'#USER:SKL_TE_%1_SubMenu',-5,[],'1','1'];
	SKL_TE_SubMenu pushBack [localize 'STR_SKL_TE_NewTruck', [%2+1], '', -5, [['expression', '[] spawn SKL_TE_New_Truck;']], '1', '1']

";

SKL_TE_SendMessage = {
    // call on each client
    params ["_sender","_message",["_playAudio",false]];
    [_sender, format ["%1<br /><br /><br /><br /><br /><br />",_message]] call BIS_fnc_showSubtitle;
    if (SKL_TE_DEBUG) then {diag_log format ["SKL_TE_SendMessage: %1: %2",_sender,_message]};
    
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

SKL_TE_New_Truck = {
    private _pos = [] call SKL_TE_LocationSelection;
    if !(_pos isEqualTo []) then {
        if (isNil "SKL_TE_NEW_TRUCK_FN") then {
            private _truckype = "C_Van_02_transport_F";
            [_pos, player, _truckType] remoteExec ["SKL_TruckExtract",2];
        } else {
            [_pos,player] remoteExec ["SKL_TE_NEW_TRUCK_FN",2];
        };
    } else {
        hint localize "STR_SKL_HE_TransportCanceled";
    };
};

SKL_TE_Move_To = {
    params ["_driverName"];
    private _truck = [_driverName] call SKL_TE_Veh_From_Driver;
    if (isNull _truck) exitWith {hint localize "STR_SKL_TE_NotResponding"};
    private _pos = [] call SKL_TE_LocationSelection;
    if !(_pos isEqualTo []) then {
        [_pos,player,_truck] remoteExec ["SKL_TruckExtract",2];
    };
};

SKL_TE_All_Done = {
    params ["_driverName"];
    if (SKL_TE_DEBUG) then {diag_log ["SKL_TE_All_Done",_driverName]};    
    private _truck = [_driverName] call SKL_TE_Veh_From_Driver;
    if (isNull _truck) exitWith {hint localize "STR_SKL_TE_NotResponding"};
    private _driver = driver _truck;
    private _crew = _truck getVariable ["TE_TruckCrew",[]];
    private _cargo = (crew _truck select {alive _x}) - _crew;
    private _driverName = if (isNull _driver) then {"Command"} else {str _driver};
    if (count _cargo > 0) then {
        [_driverName,localize "STR_SKL_HE_UnableToWithdraw",true] call SKL_TE_SendMessage;
    } else {
        [[],player,_truck] call SKL_TruckExtract;
    };
};

SKL_TE_Veh_From_Driver = {
    params ["_driverName"];
    private _truck = objNull;
    {
        private _name = _x getVariable ["SKL_TE_DRIVER","<NONE>"];
        
        if (_name == _driverName) exitWith {
            _truck = _x;
        };
    } forEach SKL_TE_Trucks;
    _truck
};

SKL_TE_TruckCanMove = {
	params ["_truck","_checkDriver"];
	private _return = true;
    private _driverOkay = true;
	if (_checkDriver) then { _driverOkay = alive (driver _truck); };
	if (alive _truck && _driverOkay) then {
		_return = canMove _truck;		  
	} else {
		_return = false;
	};
    if (_return) then {
        _return = (fuel _truck) > 0.1; // out of fuel
    };
	_return
};

SKL_TE_UpdateMenu = {
    if (!hasInterface) exitWith {};
    params ["_driverName"];
    call compile format [SKL_TE_Truck_Menu_Fmt,_driverName,count SKL_TE_SubMenu];
};

SKL_TE_RemoveMenu = {
    if (!hasInterface) exitWith {};
    params ["_driverName"];
    private _index = SKL_TE_SubMenu findIf {_x#0 == _driverName};
    if (_index > 0) then {
        {
           if (_x#0 == _driverName) exitWith {
               SKL_TE_SubMenu deleteAt _forEachIndex; 
           };
           _x set [1,[_forEachIndex]];
        } forEachReversed SKL_TE_SubMenu;
    };
};

SKL_TE_Marker = {
    // call on all clients to show truck name/position on the map
    params ["_truck","_name"];
    // wait for the truck to be propigated and alive on the clients
    private _timeout = time + 10;
    waitUntil {sleep 1; alive _truck || time > _timeout};
    sleep 1; // wait for driver as well
    private _readyName = _name + " - " + localize "STR_SKL_HE_Waiting";
    private _marker = createMarkerLocal [format ["skltem_%1",time],_truck];
    _marker setMarkerShapeLocal "ICON";
    _marker setMarkerTypeLocal "b_motor_inf";
    _marker setMarkerTextLocal _name;
    while {[_truck,true] call SKL_TE_TruckCanMove} do {
        private _speed = speed _truck;
        if (_truck getVariable ["SKL_TW_WP_DONE",false]) then {
            _marker setMarkerTextLocal _readyName;
        } else {
            _marker setMarkerTextLocal _name;
        };
        _marker setMarkerPosLocal getPosATL _truck;
        private _delay = (if (_speed > 5) then {0.5} else {
                          if (_speed < 1 ) then {5} else {
                          1}});
        sleep _delay;
    };
    deleteMarkerLocal _marker;
};

SKL_TruckExtract = {
    // spawn on the server if not running on server
    if (!isServer) exitWith {_this remoteExec ["SKL_TruckExtract",2]};

    // init is code that is run on helicopter once it's crew has been added, but before cargo has been added     _truck call _init
    params ["_lzPos","_playerCalling",["_vehType","C_Van_02_transport_F"],["_crew",[]],["_driverSide",playerSide],["_spawnPos",[]],["_init",{}],["_cargoUnits",[]]];
    
    // vehType is ether the string type for new truck, or the actual truck for updates
    if (typeName _vehType == "OBJECT") exitWith {
        // Update to already running truck, if _lzPos == [] then truck will withdraw
        if (SKL_TE_DEBUG) then {diag_log ["SKL_TruckExtract: update lz",_vehType,_lzPos]};
        private _truck = _vehType;
        _truck setVariable ["NEW_LZ",_lzPos];
        private _callers = _truck getVariable ["SKL_TE_CALLERS",[]];
        _callers pushBackUnique _playerCalling;
        _truck setVariable ["SKL_TE_CALLERS",_callers];
    };
    
    if (SKL_TE_DEBUG) then {diag_log format ["HT: TruckExtract %1", _this]};
     
    if (_spawnPos isEqualTo []) then {
        _spawnPos = _lzPos getPos [2500, random 360];
    };
    _spawnPos set [2, 20];
    
    // Spawn vehicle
    private _texture = false;
    private _anim = false;
    if (typeName _vehType == "ARRAY") then {
        _texture = _vehType#1;
        if (count _vehType > 2) then {_anim = _vehType#2};
        _vehType = _vehType#0;
    };
    private _truck = _vehType createVehicle _spawnPos;
    sleep 0.05;
    [_truck,_texture,_anim] call BIS_fnc_initVehicle;
    _truck setPos _spawnPos; // not ATL since it needs to work over water
    private "_truckGroup";
    if (_crew isEqualTo []) then {
        createVehicleCrew _truck;
        _truckGroup = createGroup [_driverSide,false];
        (crew _truck) joinSilent _truckGroup;	
        _truckGroup deleteGroupWhenEmpty true;
        waitUntil {!isNull (driver _truck)};	
    } else {
        _crew apply {_x moveInAny _truck};
        _truckGroup = group (_crew#0)
    };
    if !(_cargoUnits isEqualTo []) then {
        _cargoUnits apply {_x moveInAny _truck};
    };	
    {
        _x addCuratorEditableObjects [[_truck],true]; 
    } forEach allCurators;
    _truck setVariable ["TE_TruckCrew",units _truckGroup];
    
    // move pilot to his own group so we can disable autocombat
    private _driver = driver _truck;
    private _driverGroup = createGroup [_driverSide, false];
    _driverGroup deleteGroupWhenEmpty true;
    [_driver] joinSilent _driverGroup;
    _driver disableAI "TARGET";
    _driver disableAI "AUTOTARGET";
    _driver disableAI "AUTOCOMBAT";
    _driver disableAI "SUPPRESSION";
    _driver disableAI "MINEDETECTION";
    _driver disableAI "TEAMSWITCH";
    _driver setCombatMode "BLUE";
    _driver setBehaviour "CARELESS";
    _driver setSkill ["courage",1];
    _driver allowFleeing 0;
        
    _truckGroup setBehaviour "AWARE";
    _truckGroup setCombatMode "YELLOW";
    
    if (isNil "SKL_TE_DRIVER_NAMES" || {SKL_TE_DRIVER_NAMES isEqualTo []}) then {
        private _shuffle = false;
        if (isNil "SKL_TE_DRIVER_NAMES") then {_shuffle = true};
        SKL_TE_DRIVER_NAMES = ["Bull","Joker","Hammer","Lefty","Parrot","Bunny","Wombat","Tractor","Snake","Tug","United","Ducky","Rat"];
        if (_shuffle) then {SKL_TE_DRIVER_NAMES = SKL_TE_DRIVER_NAMES call BIS_fnc_arrayShuffle};
    };
    private _driverName = SKL_TE_DRIVER_NAMES#0;
    SKL_TE_DRIVER_NAMES deleteAt 0;
    _truck setVariable ["SKL_TE_DRIVER",_driverName,true];
    _truck setVariable ["SKL_TE_CALLERS",[_playerCalling]];
    
    [_driverName] remoteExec ["SKL_TE_UpdateMenu",0];
    
    SKL_TE_Trucks pushBack _truck;
    publicVariable "SKL_TE_Trucks";
    
    _truck call _init;
    
    private _seats = _truck emptyPositions "Cargo";
    private _text = format [localize "STR_SKL_HE_ExtractUpdateFMT", _driverName, _seats];
    [_driverName, _text, true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
        
    [_truck,_driverName] remoteExec ["SKL_TE_Marker",0,_truck];
    
    sleep 5;
        
    private _break = false;     
    private _allDone = false;
    private _first = true;
    private _exitPos = _lzPos;
    
    while {!(_break || {(_exitPos isEqualTo [])})} do {
        if (!_break && !(_exitPos isEqualTo [])) then {
            _truck engineOn true;
            if (!_first) then {
                if (getPosATL _truck #2 < 0.4) then {
                    [_driverName, localize "STR_SKL_HE_OnTheMove", true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
                } else {
                    [_driverName, localize "STR_SKL_HE_LzUpdated", true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
                };
            };
            _first = false;
            if (_truck distance2D _exitPos > 50) then {
                _truck setVariable ["SKL_TW_WP_DONE",false,true];
                {deleteWaypoint _x} forEachReversed waypoints _driverGroup;
                private _wpExtract = _driverGroup addWaypoint [_exitPos, 0];
                _wpExtract setWaypointBehaviour "AWARE";
                _wpExtract setWaypointSpeed "NORMAL";
                _wpExtract setWaypointType "MOVE";
                _wpExtract setWaypointStatements ["TRUE", "vehicle this setVariable ['SKL_TW_WP_DONE',true,true]"];
            } else {
                _truck land "GET IN";
            };

            // wait for truck to arrive at location
            private _timeout = time + 15;
            private _curExitPos = _exitPos;
            waitUntil {
                if (time > _timeout) then {_curExitPos = getPosATL _truck}; 
                (speed _truck > 20) || {!(_truck getVariable ["NEW_LZ",0] isEqualTo 0) || {!alive _truck || {!alive driver _truck || {_truck distance _curExitPos < 10}}}}
            };
            _truck allowDamage true;
                       
            waitUntil {sleep 3;_truck distance _curExitPos < 100 || {!(_truck getVariable ["NEW_LZ",0] isEqualTo 0) || {!alive _truck || {!alive driver _truck || {!isEngineOn _truck}}}}};
                        
            if ([_truck,true] call SKL_TE_TruckCanMove) then {
                if (_truck getVariable ["NEW_LZ",0] isEqualTo 0) then {
                    if (_truck distance _exitPos < 200) then {
                        [_driverName, localize "STR_SKL_HE_ArrivedAtLz", true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
                        if !(_cargoUnits isEqualTo []) then {
                            // cargo unit now join player group
                            [_cargoUnits] remoteExec ["doGetout",_cargoUnits#0];
                            _cargoUnits join group _playerCalling;
                            _cargoUnits = [];
                        };
                    } else {
                        [_driverName, localize "STR_SKL_HE_CantReach", true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
                        _truck setVariable ["SKL_TW_WP_DONE",true,true];
                        {deleteWaypoint _x} forEachReversed waypoints _driverGroup;
                    };
                };
            } else {
                _break = true;
            };
        };
        
        private _newLz = _truck getVariable ["NEW_LZ",nil];
        if (!isNil "_newLz") then {
            _truck land "NONE"; // cancel landing
            _exitPos = _newLz;
            _truck setVariable ["NEW_LZ",nil];
        } else {        
            _truck disableAI "MOVE";
            private _waitTime = time;
            _exitPos = nil;
            waitUntil {
                if (time - _waitTime > 60) then {
                    _waitTime = 1e10;
                    _truck engineOn false;
                };
                if !([_truck,true] call SKL_TE_TruckCanMove) exitWith {
                    _break = true;
                    true
                };
                sleep 1;
                _truck setVelocity [0, 0, 0];
                private _newLz = _truck getVariable ["NEW_LZ",nil];
                if (!isNil "_newLz") then {
                    _exitPos = _newLz;
                    _truck setVariable ["NEW_LZ",nil];
                };
                !(isNil "_exitPos")
            };
            _truck enableAI "MOVE";  
        };
    };
   
    // remove action
    [_driverName] remoteExec ["SKL_TE_RemoveMenu",0];
    SKL_TE_Trucks = SKL_TE_Trucks - [_truck];
    publicVariable "SKL_TE_Trucks";
    
    if (!_break) then {
        [_driverName, localize "STR_SKL_HE_WeAreDone", true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
        _truck setVariable ["SKL_TE_CALLERS",nil];
        private _exitPos = _spawnPos;
        if (getPosATL _truck distance _exitPos < 500) then {
            _exitPos = _exitPos getPos [2500, random 360];
        };
        {deleteWaypoint _x} forEachReversed waypoints _driverGroup;
        private _wpExit = _driverGroup addWaypoint [_exitPos, 80];
        _wpExit setWaypointType "MOVE";
        _wpExit setWaypointStatements ["TRUE", "private _veh = vehicle this; deleteVehicleCrew _veh; deleteVehicle _veh;"];
        _truck allowDamage true;
        sleep 60;      
    } else {
        private ["_who","_msg"];
        if (!alive _truck || {!alive _driver}) then {
            sleep 10;
            _who = "HQ";
            _msg = format [localize "STR_SKL_HE_LostContactFMT",_driverName];
        } else {
            _who = _driverName;
            _msg = format [localize "STR_SKL_HE_WeAreGrounded",_driverName];
        };
        
        [_who, _msg, true] remoteExec ["SKL_TE_SendMessage",_truck getVariable ["SKL_TE_CALLERS",0]];
    };
    waitUntil {sleep 60; isNull _truck || {_truck distance _x < 500} count allPlayers == 0};
    if (!isNull _truck) then {{deleteVehicle _x} forEach units _driverGroup; {deleteVehicle _x} forEach units _truckGroup; deleteVehicle _truck;};
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
["SKL_TE_SendMessage"] call _compileFinal;
["SKL_TE_New_Truck"] call _compileFinal;
["SKL_TE_Move_To"] call _compileFinal;
["SKL_TE_All_Done"] call _compileFinal;
["SKL_TE_Veh_From_Driver"] call _compileFinal;
["SKL_TE_TruckCanMove"] call _compileFinal;
["SKL_TE_UpdateMenu"] call _compileFinal;
["SKL_TE_RemoveMenu"] call _compileFinal;
["SKL_TE_Marker"] call _compileFinal;
["SKL_TruckExtract"] call _compileFinal;
