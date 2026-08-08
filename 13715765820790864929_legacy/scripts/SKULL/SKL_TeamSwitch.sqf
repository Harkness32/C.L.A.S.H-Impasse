// Allow teamswitching with units on the same side
//
// To use: in description.ext, add:   #include "scripts\SKULL\SKL_TeamSwitch.hpp"
//         in preinit.sqf, add:       isNil {call compile preprocessFileLineNumbers "scripts\SKULL\SKL_TeamSwitch.sqf";}; 
//
// Include the following
//     import RSCTitle;
//     import RscButtonMenu;
//     import RscButtonMenuCancel;
//     import RscButtonMenuOk;
//     import RscListBox;
//     import RscMapControl;
//     import RscPicture;
//     import RscStandardDisplay;
//     import RscText;
//
// It can then be called:  
// [_allowedUnits] call SKL_TeamSwitch    - refreshing the list will not be allowed
// [] call SKL_TeamSwitch                 - all units on the player's side will be used (doesn't work if player unconscious/civilian)
// [_allowedUnitsFn] call SKL_TeamSwitch  - the supplied function will be called to get/refresh the list of allowed units
//                                        - example function (only on foot units):  units side player select {alive _x && {_x == vehicle _x}}
// [_allowedUnitsFn,_preSwitchFn,_postSwitchFn] call SKL_TeamSwitch - pre and post switch functions (params "_player","_ai"]) are allowed
//                                                                    pre and post functions are called where player is local
//
// To call from the TeamSwitch key: 
//    if (hasInterface) then {
//        addUserActionEventHandler ["TeamSwitch", "Activate", {
//            [] spawn SKL_TeamSwitch;
//        }];
//    };

SKL_teamSwitchDebug = false;

#define SKL_TSW_COLOR_OK         [1,1,1,1]
#define SKL_TSW_COLOR_SELECTED   [0,0,0,1]
#define SKL_TSW_COLOR_PLAYER_GRP [0.0,0.3,0.6,1]
#define SKL_TSW_COLOR_BAD        [0.5,0.5,0.5,1]
#define SKL_TSW_MARKER           "skltsw_marker"

#if __has_include("\z\ace\addons\main\script_component.hpp")
#define CONSCIOUS(unit) (!((unit) getVariable ["ACE_isUnconscious", false]))
#else
#define CONSCIOUS(unit) (lifeState (unit) in ["HEALTHY","INJURED"])
#endif

SKL_TeamSwitch = {
    params [["_unitsOrFunction",[]],["_preSwitchFunction",[]],["_postSwitchFunction",[]]];
    // return the display name so caller can detect when player has closed the display (team switch may still be in progress for 5 or more seconds though)
    
    if !(hasInterface) exitWith {diag_log "Error Pos: SKL_TeamSwitch called with no interface"};
   
    if (! isNil "SKL_teamSwitchUnits") exitWith {};
    
    // If player is dead, they can't teamswitch
    if (!alive player) exitWith {};
        
    disableSerialization;
    
    SKL_teamSwitch_GetUnitsFn = nil;
    SKL_teamSwitch_PreSwitchFn = nil;
    SKL_teamSwitch_PostSwitchFn = nil;
    
    if (typeName _unitsOrFunction isEqualTo "CODE") then {
        SKL_teamSwitch_GetUnitsFn = _unitsOrFunction;
        SKL_teamSwitch_PreSwitchFn = _preSwitchFunction;
        SKL_teamSwitch_PostSwitchFn = _postSwitchFunction;
        SKL_teamSwitchUnits = call SKL_teamSwitch_GetUnitsFn;
    } else {
        if (_unitsOrFunction isEqualTo []) then {
            SKL_teamSwitch_GetUnitsFn = {if (side player == civilian) then {[]} else {units side player select {alive _x}}};
            SKL_teamSwitchUnits = call SKL_teamSwitch_GetUnitsFn;
        } else {
            SKL_teamSwitchUnits = _unitsOrFunction;
        };
    };
    
    // something went wrong with the get units function
    if (isNil "SKL_teamSwitchUnits" || {typeName SKL_teamSwitchUnits != "ARRAY"}) exitWith {
        diag_log "Error Pos: SKL_TeamSwitchFn - SKL_teamSwitchUnits undefined";
    };
        
    private _display = createDialog ["SklDisplayTeamSwitch",true];
    if (isNull _display) then {diag_log "ERROR POS: SKL_TeamSwitch - cannot create display"};
    "SklDisplayTeamSwitch"
};

SKL_TeamSwitch_OnLoad = {
    params ["_display"];
    if (SKL_teamSwitchDebug) then {diag_log "SKL_TeamSwitch_OnLoad"};
    [[],"SKL_TSW_Start"] spawn SKL_TeamSwitchFn;
    
};

SKL_TeamSwitch_OnUnLoad = {
    params ["_display", "_exitCode"];
    if (SKL_teamSwitchDebug) then {diag_log ["SKL_TeamSwitch_OnUnLoad",_exitCode]};
    [[],"SKL_TSW_Stop"] spawn SKL_TeamSwitchFn;
};

SKL_TeamSwitchFn = {
    params ["_arrayInput","_mode"];
    // _arrayInput = UI Event Handler params
    
    if (SKL_teamSwitchDebug) then {diag_log ["SKL_TeamSwitchFn",_mode,_arrayInput]};
    
    disableSerialization;
    
    private ["_control"];

    private _display = displayNull;

    if (_mode != "SKL_TSW_Stop") then {
        private _timeout = time + 1;
        while {_display = findDisplay 632;isNull _display && {time < _timeout}} do {sleep 0.01};
        
        // If player is dead, they can't teamswitch
        if (!alive player) then {
            _mode = "SKL_TSW_Close";
            if (SKL_teamSwitchDebug) then {diag_log ["SKL_TeamSwitchFn - player not alive switching mode to ",_mode]};
        };
        
        // No units setup for switching or none alive
        if (isNil "SKL_teamSwitchUnits") then {
            _mode = "SKL_TSW_Close";
            if (SKL_teamSwitchDebug) then {diag_log ["SKL_TeamSwitchFn - SKL_teamSwitchUnits undefined or empty, switch mode to ",_mode]};
        };
    };
    
    switch _mode do {
        case "SKL_TSW_Start": {        
            //Detect if player is dead, if so, remove blackout made by camera script
            if (!(alive player)) then { titleCut["","BLACK IN",0]; };
            
            if (isNil "SKL_teamSwitch_GetUnitsFn") then {_display displayCtrl 505 ctrlShow false};
            
            SKL_TSW_externalCamera = cameraView in ["EXTERNAL","GROUP"];

            SKL_TSW_OldSelectedUnit = objNull;
            SKL_TSW_camTargetUnit = player;
            SKL_TSW_oldcamTargetUnit = player;
            
            [[controlNull],"SKL_TSW_Refresh"] call SKL_TeamSwitchFn;
        };

        case "SKL_TSW_Stop": {
            // return back camera
            if (!isNil "SKL_TSW_switchCam") then {
                private _timeout = time + 2;
                waitUntil {isNil "SKL_TSW_camInAction" || time > _timeout};
                SKL_TSW_switchCam CameraEffect ["Terminate","Back"];
                CamDestroy SKL_TSW_switchCam;
                SKL_TSW_switchCam = nil;
                deleteMarker SKL_TSW_MARKER;
                cuttext ["","black in"];
            };
            
                if (!isNil "SKL_TSW_externalCamera") then {
                if (SKL_TSW_externalCamera) then {
                    player switchCamera "EXTERNAL";
                } else {
                    player switchCamera "INTERNAL";
                };
            };
            
            SKL_TSW_camTargetUnit = nil;
            SKL_TSW_oldcamTargetUnit = nil;
            SKL_TSW_externalCamera = nil;
            SKL_teamSwitchUnits = nil;
            SKL_teamSwitch_GetUnitsFn = nil;
            SKL_teamSwitchClosing = nil;
        };

        case "SKL_TSW_Refresh": {
            _arrayInput params ["_ctrl"];
            if (!isNull _ctrl && {!isNil "SKL_teamSwitch_GetUnitsFn"}) then {
                // update the list of units (_ctrl is null when called from "SKL_TSW_Start" and we don't need to do this)
                SKL_teamSwitchUnits = call SKL_teamSwitch_GetUnitsFn;
            };
            
            private _listBox = _display displayCtrl 101;
            lbClear _listBox;
            {
                private _veh = vehicle _x;
                private _isPlayer = isPlayer _x;
                if (_isPlayer) then {
                    _listBox lbAdd format ["%1:%2  %3",groupId group _x,groupId _x,name _x];
                } else {
                    _listBox lbAdd format ["%1:%2",groupId group _x,groupId _x];
                };
                if (_x != _veh) then {
                    private _picture = getText (configFile >> "cfgVehicles" >> typeOf _veh >> "picture");
                    if (_picture select [0,1] != "\") then {_picture = ""};
                    _listBox lbSetPicture [_foreachindex,_picture];
                    
                    private _rolePicture = switch (true) do {
                        case (_x == driver _veh):    {"\A3\ui_f\data\igui\rscingameui\rscunitinfo\role_driver_ca.paa"};
                        case (_x == commander _veh): {"\A3\ui_f\data\igui\rscingameui\rscunitinfo\role_commander_ca.paa"};
                        case (_x == gunner _veh):    {"\A3\ui_f\data\igui\rscingameui\rscunitinfo\role_gunner_ca.paa"};
                        default                      {""};//{"\A3\ui_f\data\igui\rscingameui\rscunitinfo\role_cargo_ca.paa"};
                    };
                    _listBox lbSetPictureRight [_foreachindex,_rolePicture];
                } else {
                    if (leader _x == _x) then {_listBox lbSetPictureRight [_foreachindex,"\A3\ui_f\data\gui\cfg\ranks\sergeant_gs.paa"]};
                };
                
                if (CONSCIOUS(_x)) then {
                    if (_isPlayer) then {
                        _listBox lbSetColor       [_forEachIndex,SKL_TSW_COLOR_PLAYER_GRP];
                        _listBox lbSetSelectColor [_forEachIndex,SKL_TSW_COLOR_PLAYER_GRP];
                    } else {
                        _listBox lbSetColor       [_forEachIndex,SKL_TSW_COLOR_OK];
                        _listBox lbSetSelectColor [_forEachIndex,SKL_TSW_COLOR_SELECTED];
                    };
                } else {
                    _listBox lbSetColor       [_forEachIndex,SKL_TSW_COLOR_BAD];
                    _listBox lbSetSelectColor [_forEachIndex,SKL_TSW_COLOR_BAD];
                };
                if (player == _x) then {
                    _listBox lbSetCurSel _forEachIndex;
                };
            } forEach SKL_teamSwitchUnits;
        };
        
        case "SKL_TSW_UnitSelected": {
            _arrayInput params ["_ctrl", "_selectedUnitNumber"]; 
            private ["_mapAnimDelay"];

            if (_selectedUnitNumber < (0)) then {
                _selectedUnitNumber = 0;
            };

            // checks if some unit died during selection, if so, last unit from list is selected
            if (!CONSCIOUS(SKL_teamSwitchUnits#_selectedUnitNumber)) exitWith {
                // grey out dead units
                private _listBox = _display displayCtrl 101;
                for "_i" from 0 to (lbSize _listBox - 1) do {
                    private _unit = SKL_teamSwitchUnits#_i;
                    private _color = lbColor [_listBox,_i];
                    if (CONSCIOUS(_unit)) then {
                        if (isPlayer _unit) then {
                            _listBox lbSetColor       [_i,SKL_TSW_COLOR_PLAYER_GRP];
                            _listBox lbSetSelectColor [_i,SKL_TSW_COLOR_PLAYER_GRP];
                        } else {
                            _listBox lbSetColor       [_i,SKL_TSW_COLOR_OK];
                            _listBox lbSetSelectColor [_i,SKL_TSW_COLOR_SELECTED];
                        };
                    } else {
                        _listBox lbSetColor       [_i,SKL_TSW_COLOR_BAD];
                        _listBox lbSetSelectColor [_i,SKL_TSW_COLOR_BAD];
                    };
                };
            };

            private _selectedUnit = SKL_teamSwitchUnits param [_selectedUnitNumber,objNull];
            if (isNull _selectedUnit) exitWith {};
            _vehicleOfSelectedUnit = typeOf (vehicle _selectedUnit);

            if (isPlayer _selectedUnit) then {
                (_display displayCtrl 501) ctrlsettext  localize "STR_TEAM_SWITCH_PLAYER";
            }
            else {
                (_display displayCtrl 501) ctrlsettext  localize "STR_TEAM_SWITCH_AI";
            };
            
            if (isPlayer _selectedUnit) then {
                (_display displayCtrl 504) ctrlEnable false;
            } else {
                (_display displayCtrl 504) ctrlEnable true;
            };

            private _unit_icon = (_display displayctrl 101) lbPicture _selectedUnitNumber;
            (_display displayCtrl 493) ctrlsettext _unit_icon;
            
            (_display displayCtrl 503) ctrlsettext (name _selectedUnit);

            //Is another unit selected?
            if ( _selectedUnit != SKL_TSW_OldSelectedUnit) then {
                if (isNull(SKL_TSW_OldSelectedUnit)) then {
                    _mapAnimDelay = 0;
                } else {
                    _mapAnimDelay = 0.5;
                };

                SKL_TSW_OldSelectedUnit = _selectedUnit;

                // Move map to selected (unit) position;
                private _mapScale = 0.2 + 0.005 * abs( speed vehicle _selectedUnit);
                _mapCtrl = _display displayCtrl 506;
                ctrlMapAnimClear _mapCtrl;
                _mapCtrl ctrlMapAnimAdd [_mapAnimDelay, _mapScale, position _selectedUnit];
                ctrlMapAnimCommit _mapCtrl;
            };
            SKL_TSW_camTargetUnit = _selectedUnit;
            
            //Set marker as selection
            private _unitPos = position _selectedUnit;
            private _marker = SKL_TSW_MARKER;
            if (getMarkerColor _marker == "") then {
                _marker = createMarkerLocal [_marker, _unitPos];
                _marker setMarkerTextLocal "";
                _marker setMarkerTypeLocal "Select";
                _marker setMarkerColorLocal "ColorGreen";
                _marker setMarkerSize [0.5, 0.5];
            } else {
                _marker setMarkerPos _unitPos;
            };
        };

        case "SKL_TSW_MapClick": {
            _arrayInput params ["_ctrl", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
            
            private ["_x", "_closest_unit","_closest_unit_index","_closest_unit_distance","_closest_vehicle"];
            private ["_playableUnit_position","_playableUnit_distance","_cursor_range","_closest_unit_position"];
            //_pos3D = _map ctrlMapScreenToWorld _pos2D

            _mapCtrl = _display displayCtrl 506;
            _pos = _mapCtrl ctrlMapScreenToWorld [_xPos,_yPos];
            _distance = 60;

            _posX = _pos select 0;
            _posY = _pos select 1;

            _closest_unit_distance = 100000; //No unit should be more distant, dull but works;

            for [{_x=(count SKL_teamSwitchUnits) - 1},{_x>=0},{_x=_x-1}] do  {
                _playableUnit_position = position  (SKL_teamSwitchUnits select _x);
                _playableUnit_distance = sqrt ( ((_playableUnit_position select 0) - (_posX) )^2 + ((_playableUnit_position select 1) -  (_posY) ) ^2);

                if (_playableUnit_distance < _closest_unit_distance) then {
                    _closest_unit_index = _x;
                    _closest_unit_distance = _playableUnit_distance;
                };
            };
            _closest_unit = SKL_teamSwitchUnits select _closest_unit_index;
            _closest_vehicle = typeOf (vehicle _closest_unit);

            //Change selection of unit if it is within cursor range
            _cursor_range = 150; //Calculation of cursor range based on the map zoom
            _closest_unit_position = position _closest_unit;

            if (_closest_unit_distance < _cursor_range) then {
                private _listBox = _display displayCtrl 101;
                _listBox lbSetCurSel _closest_unit_index;
            };
          
        };

        case "SKL_TSW_ViewUnit": {
            _arrayInput params ["_ctrl"];
            
            //View unit button pressed for first time;
            SKL_TSW_camInAction = true;
            if (isNil "SKL_TSW_switchCam") then {           
                private _pos = getPos (vehicle SKL_TSW_oldcamTargetUnit);
                _pos set [2,_pos#2 + 20];
                SKL_TSW_switchCam = "camera" CamCreate _pos;
                SKL_TSW_switchCam CameraEffect ["internal","back"];
                (vehicle SKL_TSW_oldcamTargetUnit) switchCamera "EXTERNAL";
                showCinemaBorder false;
            };

            private _pauseTimeAcc = 0.1;
            
            private _p1pos = getPos SKL_TSW_switchCam;
            private _px1 = _p1pos#0;
            private _py1 = _p1pos#1;
            private _pz1 = _p1pos#2;
            private _p2pos = getPos SKL_TSW_camTargetUnit;
            private _px2 = _p2pos#0;
            private _py2 = _p2pos#1;
            private _pz2 = _p2pos#2;
            private _distOriginal = SKL_TSW_camTargetUnit distance SKL_TSW_switchCam;
            SKL_TSW_switchCam camSetTarget vehicle SKL_TSW_camTargetUnit;			
            SKL_TSW_switchCam camSetPos [_px1, _py1 - 8, _pz1 + 20 + _distOriginal/400];
            SKL_TSW_switchCam camCommit 3*(_pauseTimeAcc+0.001);
            waitUntil {camCommitted SKL_TSW_switchCam};
            private _camSpeed = 3;
            if ((_p2pos distance2D SKL_TSW_switchCam) > 50) then {
                private _timeout = time + 5;
                while {((_p2pos distance2D SKL_TSW_switchCam)) > 50 && {time < _timeout}} do {
                    sleep (0.05 * _pauseTimeAcc);
                    if (isNil "SKL_TSW_camTargetUnit") exitWith {};
                    private _dist = _p2pos distance SKL_TSW_switchCam;
                    private _retarder = (_dist * (((180 / (_distOriginal / 100)) / 100)));
                    _retarder = ((_distOriginal/200) - (sin(_retarder)* (_distOriginal/200)-2));
                    _camSpeed = (_dist * (((_retarder / (_distOriginal / 100)) / 100)));
                    SKL_TSW_switchCam camSetPos [_px2, _py2 - 20,(_p2pos select 2) + 20 + (SKL_TSW_camTargetUnit distance SKL_TSW_switchCam)/5];
                    SKL_TSW_switchCam camCommit _camSpeed*(_pauseTimeAcc);
                };
            };

            SKL_TSW_switchCam camSetPos [_px2, _py2 - 20.5,_pz2 + 25.5];
            SKL_TSW_switchCam camCommit _camSpeed*(_pauseTimeAcc+0.001);
            waitUntil {camCommitted SKL_TSW_switchCam};

            SKL_TSW_oldcamTargetUnit = SKL_TSW_camTargetUnit;
            
            SKL_TSW_camInAction = nil;
            _ctrl ctrlEnable true;
        };
        
        case "SKL_TSW_TeamSwitch": {
            if (isPlayer SKL_TSW_OldSelectedUnit) then {
                // not allowed
            } else {
                _display closedisplay 1;
                [SKL_TSW_OldSelectedUnit] call SKL_TeamSwitch_Switch;
            };
        };
        
        case "SKL_TSW_ListDoubleClick": {
            [_arrayInput, 'SKL_TSW_UnitSelected'] spawn SKL_TeamSwitchFn;
            private _viewBtn = _display displayCtrl 502;
            _viewBtn ctrlEnable false; // disable view button so it can't be double hit
            [[_viewBtn], 'SKL_TSW_ViewUnit'] spawn SKL_TeamSwitchFn;
        };
        
        case "SKL_TSW_MapDoubleClick": {
            [_arrayInput, "SKL_TSW_MapClick"] spawn SKL_TeamSwitchFn;
            private _viewBtn = _display displayCtrl 502;
            _viewBtn ctrlEnable false; // disable view button so it can't be double hit
            [[_viewBtn], 'SKL_TSW_ViewUnit'] spawn SKL_TeamSwitchFn;
        };

        case "SKL_TSW_Close": {
            _display closedisplay 1;
        };
        
        default {
            diag_log format ["Error Pos: SKL_TeamSwitchFn called with invalid mode %1 %2",_mode,_arrayInput];
        };
    };
};

SKL_TeamSwitch_Switch = {
    // called where player is local
    params ["_ai"];
    private _player = player;

    if (!isNil "SKL_teamSwitch_PreSwitchFn") then {[_player,_ai] call SKL_teamSwitch_PreSwitchFn};
    
    [_ai,false] remoteExec ["allowDamage",_ai];
    _player allowDamage false;

    "TSwitch" cutText ["","BLACK OUT",0.5,true,false];
    sleep 0.5;
    
    private _aiPos = getPosATL _ai;
    //private _aiDmg = damage _ai;
    private _aiStance = stance _ai;
    private _aiDir = getDir _ai;
    private _aiGrpInfo = [group _ai, groupId _ai];
    private _aiIsLeader = leader _ai == _ai;
    private _playerPos = getPosATL _player;
    private _playerDmg = damage _player;
    private _playerStance = stance _player;
    private _playerDir = getDir _player;
    private _playerGrpInfo = [group _player, groupId _player];
    private _playerIsLeader = leader _player == _player;
    
    // detect ai in a vehicle
    private _vehAi = vehicle _ai;
    private _vehSlotAi = [];
    if (_vehAi != _ai) then {
        // ai is in a vehicle
        private _crew = fullCrew _vehAi select {_x#0 == _ai};
        if !(_crew isEqualTo []) then {_vehSlotAi = _crew#0};
    };

    // detect player in a vehicle
    private _vehPlayer = vehicle _player;
    private _vehSlotPlayer = [];
    if (_vehPlayer != _player) then {
        // player is in a vehicle
        private _crew = fullCrew _vehPlayer select {_x#0 == _player};
        if !(_crew isEqualTo []) then {_vehSlotPlayer = _crew#0};
    };
    
    unassignVehicle _ai;
    unassignVehicle _player; 
    
    // revive the player
    moveOut _player;
    private _isDisabled = _player getVariable ["#rev_state", 0] == 2;
    if (_isDisabled) then {
        ["",1,_player] call bis_fnc_reviveOnState;
        _player setVariable ["#rev", 1, true];
    }; 
    [_player,""] remoteExec ["switchMove",0];
    
    // do some handshaking so two clients can be matched up
    _ai setVariable ["TmSwSwapState",0];
    [_ai,_playerPos,_playerDir,_playerDmg,_vehPlayer,_vehSlotPlayer,_isDisabled,_player] remoteExec ["SKL_TeamSwitch_SwitchAI",_ai];
    while {(_ai getVariable "TmSwSwapState") == 0} do {sleep 0.01};
    waitUntil {vehicle _ai == _ai};
    _ai setVariable ["TmSwSwapStateAI",1,owner _ai];// notify ai client that we've seen the ai exited
    if (_vehSlotAi isEqualTo []) then {
        // ai wasn't in a vehicle
        _player setDir _aiDir;
        _player setPosATL _aiPos;
    } else {
        private _role = _vehSlotAi#1;
        private _cargoIndex = _vehSlotAi#2;
        private _turretPath = _vehSlotAi#3;  
        switch (_role) do {
            case "driver"    : {_player assignAsDriver _vehAi;                  _player moveInDriver _vehAi;              };
            case "commander" : {_player assignAsCommander _vehAi;               _player moveInCommander _vehAi;           };
            case "gunner"    : {_player assignAsGunner _vehAi;                  _player moveInGunner _vehAi;              };
            case "turret"    : {_player assignAsTurret [_vehAi,_turretPath];    _player moveInTurret [_vehAi,_turretPath];};
            default            {_player assignAsCargoIndex [_vehAi,_cargoIndex];_player moveInCargo  [_vehAi,_cargoIndex];};
        };
    };

    [_ai] joinSilent (_playerGrpInfo#0);
    _player joinAsSilent _aiGrpInfo;
    _ai joinAsSilent _playerGrpInfo;
    
    sleep 0.5;
    
    private _stance2Pos = {
        switch (_this) do {
            case "CROUCH": {"MIDDLE"};
            case "PRONE" : {"DOWN"};
            default {"UP"};            
        }
    };
    
    if (_vehSlotAi isEqualTo []) then {_player setUnitPos (_aiStance call _stance2Pos)};
    
    if (_aiIsLeader)     then {[group _player,_player] remoteExec ["selectLeader",group _player]};
    if (_playerIsLeader) then {[group _ai    ,_ai    ] remoteExec ["selectLeader",group _ai    ]};
    
    if (!isNil "SKL_teamSwitch_PostSwitchFn") then {[_player,_ai] call SKL_teamSwitch_PostSwitchFn};

    "TSwitch" cutText ["","BLACK IN",0.5,true,false];

    missionNamespace setVariable ["TmTsDone",true,2];

    sleep 5;
    _player allowDamage true;
    
};

SKL_TeamSwitch_SwitchAI = {
    // spawn where ai is local
    params ["_ai","_pos","_dir","_damage","_veh","_vehSlot","_isDisabled","_player"];
    if (!local _ai) exitWith {_this remoteExec ["ITW_TeammateSwitchAI",_ai]};
    
    unassignVehicle _ai;
    moveOut _ai;
    _ai setPosATL ([_pos,4,0] call ITW_FncRelPos);
    _ai switchMove "";
    _ai setDamage _damage;
    _ai setDir _dir;
    if (_isDisabled) then {_ai setUnconscious true};
    
    // do some handshaking so two clients can be matched up
    waitUntil {vehicle _ai == _ai};
    waitUntil {vehicle _player == _player};
    _ai setVariable ["TmSwSwapStateAI",0];
    _ai setVariable ["TmSwSwapState",1,owner _player]; // notify player's client that we've seen the player exited
    while {(_ai getVariable "TmSwSwapStateAI") == 0} do {sleep 0.01}; // wait for both player's client to see ai out of vehicle

    sleep 0.1;
    if (_isDisabled) then {_ai setCaptive true};
    
    if (_vehSlot isEqualTo []) then {
        _ai setPosATL _pos;
    } else {
        private _role = _vehSlot#1;
        private _cargoIndex = _vehSlot#2;
        private _turretPath = _vehSlot#3;
        switch (_role) do {
            case "driver"    : {_ai moveInDriver _veh;              _ai assignAsDriver _veh};
            case "commander" : {_ai moveInCommander _veh;           _ai assignAsCommander _veh};
            case "gunner"    : {_ai moveInGunner _veh;              _ai assignAsGunner _veh};
            case "turret"    : {_ai moveInTurret [_veh,_turretPath];_ai assignAsTurret [_veh,_turretPath]};
            default            {_ai moveInCargo  [_veh,_cargoIndex];_ai assignAsCargoIndex [_veh,_cargoIndex]};
        };
        if (vehicle _ai == _ai) then {_ai moveInAny _veh};
    };
    if (_isDisabled) then {[_ai] remoteExec ["ITW_TeammateDown",0]};
    _ai setVariable ["tmSwitching",false,0];
    sleep 5;
    [_ai,true] remoteExec ["allowDamage",_ai]; // ai could have changed locality
};

if (! isNil "SKL_fnc_CompileFinal") then {
["SKL_TeamSwitch"] call SKL_fnc_CompileFinal;
["SKL_TeamSwitch_OnLoad"] call SKL_fnc_CompileFinal;
["SKL_TeamSwitch_OnUnLoad"] call SKL_fnc_CompileFinal;
["SKL_TeamSwitchFn"] call SKL_fnc_CompileFinal;
["SKL_TeamSwitch_Switch"] call SKL_fnc_CompileFinal;
["SKL_TeamSwitch_SwitchAI"] call SKL_fnc_CompileFinal;
};