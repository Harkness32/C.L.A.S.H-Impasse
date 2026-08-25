// I needed the garage not to place the vehicles on the ground
#define DEBUGLOG if(true)then

#include "\A3\Ui_f\hpp\defineResinclDesign.inc"

ITW_Garage = compile preprocessFileLineNumbers "fn_garage.sqf";
ITW_Arsenal = compile preprocessFileLineNumbers "fn_arsenal.sqf";

uiNamespace setVariable ["skl_fnc_garage",ITW_Garage]; 
uiNamespace setVariable ["skl_fnc_arsenal",ITW_Arsenal]; 
uiNamespace setVariable ["ITW_Garage",ITW_Garage]; 
uiNamespace setVariable ["ITW_Arsenal",ITW_Arsenal]; 
VehicleChooser_GarageFN = ITW_Garage;

uiNamespace setVariable ["RscDisplayGarageSKL_script",{ 
    _mode = _this select 0;
    _params = _this select 1;
    _class = _this select 2;

    _data = missionnamespace getvariable ["skl_fnc_garage_data",nil];
    
    switch _mode do {
        case "onLoad": {
            if (isnil {missionnamespace getvariable "bis_fnc_arsenal_data"}) then {
                startloadingscreen [""];
                ['Init',_params] spawn (uiNamespace getvariable "ITW_garage");
            } else {
                ['Init',_params] call (uiNamespace getvariable "ITW_garage");
            };
        };
        case "onUnload": {
            ['Exit',_params] call (uiNamespace getvariable "ITW_garage");
        };
    };}];

ITW_GarageInit = {
    // call on all clients
    0 spawn ITW_GaragePylonInit;
    
    [missionNamespace, "garageClosed", {
        if (!local BIS_fnc_garage_center) exitWith {diag_log "Error pos: garageClosed EH called on non local machine"};        
        private _veh = BIS_fnc_garage_center;
        private _pos = getPosATL _veh;
        private _shipDir = [_pos,0] call ITW_WarshipGarageDir;
        if (_shipDir != 0) then {_veh setDir _shipDir};
        _pos set [2,_pos#2 + 0.2];
        private _dir = [vectorDir _veh, vectorUp _veh];
        private _pylons = getPylonMagazines _veh;
        
        _crew = [];
        if !(unitIsUAV _veh) then {
            // save crew we want in vehicle
            {
                _x params ["_unit","_role","_cargoIndex","_turretPath"];
                _role = toLowerANSI _role;
                _role = switch (_role) do {
                    case "driver": {[_role,0];};
                    case "cargo": {[_role,_cargoIndex];};
                    case "gunner";
                    case "commander";
                    case "turret": {[_role,_turretPath];};
                    default {[]};
                };
                _crew pushback _role;
                deleteVehicleCrew _unit; // remove the virtual unit
            } foreach (fullcrew _veh);
        };
        deleteVehicleCrew _veh;  
        private _init = [_veh,""] call BIS_fnc_exportVehicle; // needs an empty crew
        private _type = typeOf _veh; 
        deleteVehicle _veh;
        if !(ITW_GARAGE_CANCEL) then {
            [_type,_pos,_dir,_init,_crew,_pylons,player] remoteExec ["ITW_GarageVehSpawn",2];
        };
    }] call BIS_fnc_addScriptedEventHandler;
};
  
ITW_GaragePreload = {
    if !(missionnamespace getvariable ["ITW_garage_preloaded",false]) then {
        // preload garage data  
        missionnamespace setvariable ["ITW_garage_preloaded",true];
        private _fullData = missionnamespace getvariable ["skl_fnc_garage_data",[]]; 
        if (_fullData isEqualTo []) then {
            ["Preload"] spawn ITW_garage;
            waitUntil {
                sleep 0.01;
                _fullData = missionnamespace getvariable ["skl_fnc_garage_data",[]]; 
                !(_fullData isEqualTo [])
            };
        };
        if (ITW_ParamVirtualGarage == 1) then {
            private _data = [];
            private _allVehicles = va_pAllVehicles apply {if (typeName _x isEqualTo "ARRAY") then {_x#0} else {_x}};
            {
                private _tab = []; 
                private _tabData = _x;
                // list of   [p3dModel,[[name,[cfg,cfg,...]], [name,[cfg,cfg...]], ...], p3dModel,[[name,[cfg,cfg,...]], [name,[cfg,cfg...]], ...], ...]
                for "_i" from 1 to count _tabData step 2 do {
                    private _model = _tabData#(_i-1);
                    private _modelData = _tabData#(_i);
                    private _mdata = [];
                    {
                        _x params ["_displayName","_cfgsFull"];
                        private _found = false;
                        {
                            if (configName _x in _allVehicles) exitWith {
                                _found = true;
                            };
                        } forEach _cfgsFull;
                        if (_found) then {
                            _mdata pushBack [_displayName,_cfgsFull];
                        };
                    } forEach _modelData;
                    if !(_mdata isEqualTo []) then {
                        _tab pushBack _model;
                        _tab pushBack _mdata;
                    };
                };           
                _data pushBack _tab; 
            } forEach _fullData; // [[tanks],[ships],[planes],...]
            missionnamespace setvariable ["skl_fnc_garage_data",_data];   
        };
    };
};
    
// need to spawn this in the background before accessing garage
ITW_GaragePylonInit = {
    ITW_PylonWeapons = [];

    _weps = [];
    _arr = (configProperties [configFile >> "CfgVehicles"]) apply {configName _x};
    _fnc_arrayFlatten = {
        private ["_res", "_fnc"];
        _res = [];
        _fnc = {
            {
                if (typeName _x isEqualTo "ARRAY") then [
                    {_x call _fnc; false},
                    {_res pushBackUnique _x; false}
                ];
            } count _this;
        };
        _this call _fnc;
        _res
    };

    {
        _weps append ((_x getCompatiblePylonMagazines 0));
    } forEach _arr;
    sleep 0.01; // let other threads run

    _weps = (_weps call _fnc_arrayFlatten);
    {
        ITW_PylonWeapons pushBack [getText (configFile >> "CfgMagazines" >> _x >> "DisplayName"),_x];
    } forEach _weps;
    sleep 0.01; // let other threads run

    ITW_PylonWeapons sort true; 
};

ITW_GaragePylons = {
    // spawn from garage each time a vehicle is created for viewing
    params ["_display"];
    _ctrls = [];
    
    // try button will become 'reset pylon'
    _display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONTRY ctrlSetText localize "STR_ITW_MISC_ResetPylon";
        
    ctrlPosition (_display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_CONTROLBAR) params ["_cx","_cy","_cw","_ch"];
    private _ctrlThanks = _display ctrlCreate ["RscText", -1];
    _ctrlThanks ctrlSetFontHeight 0.035;
    _ctrlThanks ctrlSetText localize "STR_ITW_MISC_PylonInfo";
    _ctrlThanks ctrlSetPosition [
        _cx,
        _cy - _ch,
        2 * _cw,
        _ch
    ];
    _ctrlThanks ctrlCommit 0;
    _ctrlThanks ctrlShow false;

    private "_veh";
    while {!isNull _display} do {
        waitUntil {_veh = uiNamespace getVariable ["ITW_PylonVehicle",objNull]; !isNull _veh || {isNull _display}};
        uiNamespace setVariable ["ITW_PylonVehicle",objNull];
        if (isNull _display) exitWith {};
        ITW_PylonVeh = _veh;
        
        _pylons = (configProperties [configFile >> "CfgVehicles" >> typeOf _veh >> "Components" >> "TransportPylonsComponent" >> "Pylons"]) apply {configName _x};
        if(count _pylons == 0) then {continue};
        if (isNil "ITW_PylonWeapons") then {};
        _ctrlThanks ctrlShow true;

        _last_loadout = (uiNamespace getVariable format ["ITW_Pylon_Loadout_%1",typeOf _veh]);
        
        {
            _ctrl = _display ctrlCreate ["RscCombo", -1];
            _ctrl ctrlSetTooltip localize "STR_ITW_MISC_SelectWeapon";
            _ctrl ctrlSetBackgroundColor [0,0,0,0.8];
            _ctrl ctrlSetFade 0.2;
            _ctrl ctrlCommit 0;

            _veh animateBay [_forEachIndex, 1];

            if(!isNil "_last_loadout") then {
                _veh setPylonLoadOut [_forEachIndex+1, _last_loadout select _forEachIndex,true];
            };

            _ctrl_index = _forEachIndex;

            _current_wep = (getPylonMagazines (_veh)) select _forEachIndex;

            _selected = -1;

            {
                _ctrl lbAdd (_x select 0);
                _ctrl lbSetData [_forEachIndex, format["%1^%2",_x select 1,_ctrl_index+1]];

                if(_current_wep == (_x select 1)) then {
                    _selected = _forEachIndex;
                };
            } forEach ITW_PylonWeapons;

            _ctrl lbSetCurSel _selected;

            _ctrl ctrlAddEventHandler ["LBSelChanged",{
                _veh = ITW_PylonVeh;
                _ctrl = _this select 0;
                _index = _this select 1;
                _str = (_ctrl lbData _index) splitString "^";
                _pylon_index = parseNumber (_str select 1);
                _class = (_str select 0);

                _veh setPylonLoadOut [_pylon_index, _class,true];

                (uiNamespace setVariable [format ["ITW_Pylon_Loadout_%1",typeOf _veh],getPylonMagazines _veh]);

                playSoundUI ["a3\missions_f_beta\data\sounds\firing_drills\target_pop-down_small.wss"];
            }];

            _ctrl ctrlAddEventHandler ["MouseEnter",{
                (_this) ctrlSetFade 0;
                (_this) ctrlCommit 0;
            }];
            _ctrl ctrlAddEventHandler ["MouseExit",{
                (_this) ctrlSetFade 0.5;
                (_this) ctrlCommit 0;
            }];

            _offset = getArray (configfile >> "CfgVehicles" >> typeOf _veh >> "Components" >> "TransportPylonsComponent" >> "pylons" >> _x >> "UIposition");
            // some vehicles have the offset as a string (ex ["0.06 + 0.02",0.4] )
            {
                if (typeName _x == typeName "") then {
                    _offset set [_forEachIndex,call compile _x];
                };
            } forEach _offset;
            
            _offset_final = +_offset;
            _pos_offset = [-0.33,-0.33,-0.5];
            _multiplyer = [15,15];

            switch (typeOf _veh) do { 
                case 'B_Plane_CAS_01_dynamicLoadout_F': {
                    _offset_final = [_offset select 1,_offset select 0];
                    _pos_offset = [-0.26,-0.36,-0.5];
                    _multiplyer = [25,15];
                };
                case 'B_Heli_Light_01_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),(_offset select 1)];
                    _pos_offset = [0.32,-0.5,-0.5];
                    _multiplyer = [6,6];
                };
                case 'B_Heli_Attack_01_pylons_dynamicLoadout_F';
                case 'B_Heli_Attack_01_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),(_offset select 1)];
                    _pos_offset = [0.33,-0.4,-0.5];
                    _multiplyer = [6,15];
                }; 
                case 'O_Heli_Attack_02_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),(_offset select 1)];
                    _pos_offset = [0.33,-0.33,-0.5];
                    _multiplyer = [13,13];
                };
                case 'B_T_UAV_03_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),-(_offset select 1)];
                    _pos_offset = [0.31,0.33,-0.5];
                    _multiplyer = [10,10];
                };
                case 'O_Heli_Light_02_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),(_offset select 1)];
                    _pos_offset = [0.31,-0.8,-1.6];
                    _multiplyer = [9,1];
                }; 
                case 'B_Heli_light_03_dynamicLoadout_RF';
                case 'I_Heli_light_03_dynamicLoadout_RF';
                case 'I_E_Heli_light_03_dynamicLoadout_RF';
                case 'I_Heli_light_03_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 0),(_offset select 1)];
                    _pos_offset = [0.33,-3,-0.5];
                    _multiplyer = [9,1];
                }; 
                case 'I_Plane_Fighter_03_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 1),(_offset select 0)];
                    _pos_offset = [0.29,-0.33,-0.5];
                    _multiplyer = [15,25];
                };
                case 'B_UAV_02_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 1),(_offset select 0)];
                    _pos_offset = [0.28,-0.22,-0.8];
                    _multiplyer = [25,15];
                };
                case 'O_Plane_CAS_02_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 1),(_offset select 0)];
                    _pos_offset = [0.28,-0.32,-0.8];
                    _multiplyer = [24,100];
                };
                case 'O_T_VTOL_02_infantry_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 1),(_offset select 0)];
                    _pos_offset = [0.28,-0.32,-1.3];
                    _multiplyer = [40,20];
                };
                case 'O_T_VTOL_02_vehicle_dynamicLoadout_F': {
                    _offset_final = [-(_offset select 1),(_offset select 0)];
                    _pos_offset = [0.28,-0.32,-1.3];
                    _multiplyer = [40,20];
                };
            };

            _ctrls pushBack [
                _ctrl,
                _offset_final,
                _pos_offset,
                _multiplyer
            ];
        } forEach _pylons;

        ITW_PylonControls = _ctrls;
        ITW_PylonVeh = _veh;
        
        ["DCON_Garage_FrameEvent", "onEachFrame"] call BIS_fnc_removeStackedEventHandler;
        ["DCON_Garage_FrameEvent", "onEachFrame", {
            _ctrls = ITW_PylonControls;
            _veh = ITW_PylonVeh;

            _width = 0.14;
            _height = 0.05;
            _boost = 0;

            _mouse = getMousePosition;

            {         
                _ctrl = _x select 0;
                _offset = _x select 1;
                _pos_offset = _x select 2;
                _multiplyer = _x select 3;
                _offset_x = _offset select 0;
                _offset_y = _offset select 1;

                _offset_x = _offset_x + (_pos_offset select 0);
                _offset_y = _offset_y + (_pos_offset select 1);

                _offset_x = _offset_x * -1;
                _offset_y = -_offset_y * 1;

                _offset_x = -_offset_x * (_multiplyer select 0);
                _offset_y = _offset_y * (_multiplyer select 1);

                _pos = worldToScreen (_veh modelToWorld [_offset_x,_offset_y,(_pos_offset select 2)]);
                if (count _pos > 1) then {
                    _pos_x = (_pos select 0) - _width/2;
                    _pos_y = (_pos select 1) - _height/2;

                    _dist = 1 - (_mouse distance _pos);

                    if(_dist > 0.94) then {
                        _boost = 0;
                    }
                    else
                    {
                        _boost = 0;
                    };

                    _ctrl ctrlSetPosition [_pos_x,_pos_y - _boost,_width,_height];
                    _ctrl ctrlCommit 0;
                };
            } forEach _ctrls;

        }] call BIS_fnc_addStackedEventHandler;

        waitUntil {isNull _display || {isNil "ITW_PylonVeh" || {isNull ITW_PylonVeh}}};
        {
            ctrlDelete (_x select 0);
        } forEach _ctrls;
        
        _ctrlThanks ctrlShow false;
    };
    ctrlDelete _ctrlThanks;
};

#define IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONINTERFACE	44151
ITW_GarageAddCancelBtn = {
    // Change the 'random' button to a 'cancel' button
    params ["_display"];
    // called in ui namespace
    if (is3DEN) exitWith {};
    ITWGarageDisplay = _display;
    private _ctrlButton = _display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONINTERFACE;
    _ctrlButton ctrlSetText localize "STR_ITW_COMMON_Cancel";
    _ctrlButton ctrlRemoveAllEventHandlers "buttonclick"; 
    _ctrlButton ctrlAddEventHandler ["buttonclick",
        {
            // called in mission namespace
            ITW_GARAGE_CANCEL = true;        
            with uinamespace do {
                ["buttonClose",[ITWGarageDisplay]] call BIS_fnc_Arsenal;
            };                    
        }];
    _ctrlButton ctrlEnable true; 
    _ctrlButton ctrlSetTooltip localize "STR_ITW_CloseGarageWoCreatingVeh";
    missionNamespace setVariable ["ITW_GARAGE_CANCEL",false];
};
            
ITW_GarageVehSpawn = {
    // call on server
    params ["_type","_pos","_dir","_init","_crew","_pylons","_player"];
    sleep 0.5;  
    private _veh = objNull;
    if (_type isKindOf "Ship") then {
        _pos = call ITW_BaseShipSpawnPt; 
        if !(_pos isEqualTo []) then {
            _veh = [_type,_pos,_dir,1,false] call ITW_VehSpawn;
            private _mrkr = createMarkerLocal ["ship"+(str time),_pos];
            _mrkr setMarkerTypeLocal "loc_boat";
            _mrkr setMarkerColorLocal "colorBLUFOR";
            _mrkr setMarkerAlpha 1;
            _veh setVariable ["ShipMarker",_mrkr];
            
            _veh addEventHandler ["GetIn", {
                params ["_vehicle", "_role", "_unit", "_turret"];
                private _mrkr = _vehicle getVariable ["ShipMarker",""];
                deleteMarker _mrkr;
                _vehicle removeEventHandler [_thisEvent,_thisEventHandler]
                }];
        };
    } else {
        _veh = [_type,_pos,_dir,1,false] call ITW_VehSpawn;
    };
    if (!isNull _veh) then {
        _veh call compile _init;
        if !(isNil "ITW_CLASH_PlayerGarage_fnc_OnVehicleSpawned") then {
            [_veh,_player,_type] call
                ITW_CLASH_PlayerGarage_fnc_OnVehicleSpawned;
        };
        if (unitIsUAV _veh) then {
            west createVehicleCrew _veh;
        } else {
            // now add teammates to crew positions
            {                             
                _x params ["_role","_index"];
                private _aiCnt = {!isPlayer _x && {alive _x}} count units group _player;
                if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {cutText [localize "STR_ITW_START_CrewLimited","PLAIN",1]};
                private _units = units group _player;
                [_player,_type] remoteExec ["ITW_AllyRecruit",2];
                waitUntil {sleep 0.1;count units group _player > count _units};
                sleep 1; // short sleep (0.2) had units hopping back out of vehicle
                private _unit = (units group _player - _units)#0;
                private _timeout = time + 2.6;
                switch (_role) do {
                    case "driver":   {[_unit,_veh]          remoteExec ["moveInDriver",_unit]; doStop _unit}; 
                    case "cargo":    {[_unit,[_veh,_index]] remoteExec ["moveInCargo" ,_unit]};
                    case "gunner";    
                    case "commander"; 
                    case "turret":   {[_unit,[_veh,_index]] remoteExec ["moveInTurret",_unit]};
                    default {[]};
                };
            } forEach _crew;
        };
        if !(_pylons isEqualTo []) then { {_veh setPylonLoadOut [_forEachIndex+1, _x,true]} forEach _pylons };
        if (_veh isKindOf "air" && {! unitIsUAV _veh}) then {[_veh,ITW_PlayerSide] remoteExec ["SKL_BlackfishCircle",0,_veh]};
        if (_veh isKindOf "StaticWeapon" || {getNumber (configFile >> "cfgVehicles" >> _type >> "maxSpeed") == 0}) then {
            private _playerBB = 0 boundingBoxReal _player;
            private _staticBB = 0 boundingBoxReal _veh;
            private _playerFront = _playerBB#1#1;  // arrays are [width,length,height]  or [sides,front/back,tall]
            private _staticBack = -(_staticBB#0#1);
            private _staticHeight = -(_staticBB#0#2);
            private _frontDist = _playerFront + _staticBack;
            _veh addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Carry" + "</t>", {
                    params ["_veh", "_player", "_actionId", "_arguments"];
                    _arguments params ["_frontDist","_staticHeight"];
                    _veh attachTo [_player, [0, _frontDist, 0.5 + _staticHeight]];
                    _player playAction "PlayerStand";
                    _player action ["SwitchWeapon",_player,_player,-1];
                    ITW_CarryObj = _veh;
                    _player addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_Drop" + "</t>", { 
                        params ["_player", "_caller", "_actionId", "_arguments"];
                        private _crate = ITW_CarryObj;
                        ITW_CarryObj = objNull;
                        _player setVelocity [0,0,0];
                        _crate setVelocity [0,0,0];
                        detach _crate;
                        sleep 0.5;
                        _player setAnimSpeedCoef 1;
                        _crate setVelocity [0,0,-0.1]; 
                        _player removeAction _actionId;
                    },nil,10,false,true,"","_this == attachedTo ITW_CarryObj",1];
                },[_frontDist,_staticHeight],10,false,true,"","isNull attachedTo _target",_frontDist + 3];
        };
    };
};

ITW_GarageSaveVehicle = {
    // Modified version of BIS_fnc_initVehicleCrew that handles gunners,commanders,copilot
    private ["_center","_path","_custom","_delete","_namespace","_name"];
    _center = _this param [0,player,[objnull]];
    _path = _this param [1,[],[[]]];
    _custom = _this param [2,[],[[]]];
    _delete = _this param [3,false,[false]];

    _namespace = _path param [0,missionnamespace,[missionnamespace,grpnull,objnull]];
    _name = _path param [1,"",[""]];

    //--- Get current values
    private ["_animations","_crew","_export"];
    _animations = [];
    {
        _anim = configname _x;
        _animations pushback [_anim,_center animationphase _anim];
    } foreach (configProperties [configfile >> "CfgVehicles" >> typeof _center >> "animationSources","isclass _x",true]);
    _crew = [];
    {
        _member = _x select 0;
        _role = _x select 1;
        _index = _x#2;
        _turret = _x#3;
        if (_turret isNotEqualTo []) then {
            _index = _turret;
            _role = "turret";
        };
        _crew pushback [typeof _member,_role,_index];
    } foreach fullcrew _center;

    _export = [
        /* 00 */	typeof _center,
        /* 01 */	_animations,
        /* 02 */	getobjecttextures _center,
        /* 03 */	_crew,
        /* 04 */	_custom
    ];

    //--- Store
    private ["_data","_nameID"];
    _data = _namespace getvariable ["bis_fnc_saveVehicle_data",[]];
    _nameID = _data find _name;
    if (_delete) then {
        if (_nameID >= 0) then {
            _data set [_nameID,objnull];
            _data set [_nameID + 1,objnull];
            _data = _data - [objnull];
        };
    } else {
        if (_nameID < 0) then {
            _nameID = count _data;
            _data set [_nameID,_name];
        };
        _data set [_nameID + 1,_export];
    };
    _namespace setvariable ["bis_fnc_saveVehicle_data",_data];
    profilenamespace setvariable ["bis_fnc_saveVehicle_profile",true];
    if !(isnil {profilenamespace getvariable "bis_fnc_saveVehicle_profile"}) then {saveprofilenamespace};

    _export
};

["ITW_GaragePreload"] call SKL_fnc_CompileFinal;
["ITW_GarageAddCancelBtn"] call SKL_fnc_CompileFinal;
["ITW_GaragePylonInit"] call SKL_fnc_CompileFinal;
["ITW_GaragePylons"] call SKL_fnc_CompileFinal;
["ITW_GarageInit"] call SKL_fnc_CompileFinal;
["ITW_GarageVehSpawn"] call SKL_fnc_CompileFinal;
["ITW_GarageSaveVehicle"] call SKL_fnc_CompileFinal;