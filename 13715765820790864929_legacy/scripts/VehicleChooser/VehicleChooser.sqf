// Vehicle Chooser
//
// _vehsArray = 0 call VehicleChooser - to have user select vehicles - call on server
//
// [_vehsArray, "type","includeTextureAnim"] call VehicleChooser_Get - to get the vehicles
//
//
// _vehsArray: [Tanks,Apcs,Cars,Helicopters,Planes,Statics,Naval,UavUgv]
//    each type will contain arrays of [vehClassName,texture,animation],
//    or [] if no vehicles of that type selected selected
//        texture and anim are arrays of [texture,probability,...] or [anim,probability,...]
//
// The texture/anim can be applied with [_veh,_texture,_anim] call BIS_fnc_initVehicle;
//
// to call a garage function other than the Arma default, set VehicleChooser_GarageFN to the function
#include "\A3\ui_f\hpp\defineDIKCodes.inc"
#include "\A3\Ui_f\hpp\defineResinclDesign.inc"

#define TANK_ID   0
#define APC_ID    1
#define CAR_ID    2
#define HELI_ID   3
#define PLANE_ID  4
#define STATIC_ID 5
#define NAVAL_ID  6
#define UAV_ID    7
#define ID_COUNT  8

VehicleChooser = {
    // call on server only
    // Allows player to choose vehicles using the garage interface
    // parameters:
    //   multiselect:    true to allow player to choose multiple vehicles
    //   playerToChoose: player who will choose, or objNull for vehicleChooser to select someone
    //   factions:       factions for filling in faction vehicles list
    //   loadSaveDelFunctions: if you want to be able to load/save/delete vehicle lists, include functions [loadFn,saveFn,deleteFn]
    //       loadFn :  params ["_saveName"]; return: array of vehicles
    //       saveFn :  params ["_saveName","_arrayOfVehs"];
    //       deleteFn: params ["_saveName"];
    
    params [["_multiselect",false],["_msg",""],["_playerToChoose",objNull],["_factions",[]]];
    if (! isServer) exitWith { diag_log "Error: VehicleChooser called from non-server"; };
    
    missionNamespace setVariable ["VEHICLE_CHOOSER_SELECTED",nil];
    
    if (isNull _playerToChoose) then {
        if (isDedicated) then {
            // if using a dedicated server, use a the first player to choose faction
            waitUntil {count (call BIS_fnc_listPlayers) > 0};
            private _playerClient = owner ((call BIS_fnc_listPlayers)#0);
            [] remoteExec ["VehicleChooser_Wait",-(_playerClient),true];
            [_multiselect,_msg,_factions] remoteExec ["VehicleChooser_Start",_playerClient];
        } else {
            // hosted server, so just let the host choose faction
            [] remoteExec ["VehicleChooser_Wait",-2,true];
            [_multiselect,_msg,_factions] call VehicleChooser_Start;
        };
    } else {
        [] remoteExec ["VehicleChooser_Wait",-(owner _playerToChoose),true];
        [_multiselect,_msg,_factions] remoteExec ["VehicleChooser_Start",_playerToChoose];
    };

    private _allVehicles = [];
    waitUntil {_allVehicles = missionNamespace getVariable ["VEHICLE_CHOOSER_SELECTED",""]; typeName _allVehicles isEqualTo "ARRAY"};
    missionNamespace setVariable ["VEHICLE_CHOOSER_SELECTED",nil,true];

    private _vehArray =
        if (_allVehicles isEqualTo []) then {
            [];
        } else {
            [_allVehicles] call VehicleChooser_Sort;
        };
    missionnamespace setvariable ["skl_fnc_garage_data",[]];
    _vehArray
};

VehicleChooser_Get = {
    params ["_vehArray","_type",["_includeTextureAnim",false]];
    // return: if_includeTextureAnim is false: array of classnames
    //         if_includeTextureAnim is true: array of [vehClassName,[texture,proability],[animation,probability,...]]
    //         or [] if no vehicles of that type were selected
    //
    // _type is one of "Tanks","Apcs","Cars","Helicopters","Planes","Statics","Naval","UavUgv" ( only first letter is actually used )
    if (count _vehArray != ID_COUNT) exitWith {[]};

    private _result =
        switch (toUpperANSI (_type select [0,1])) do {
            case "T": { _vehArray#TANK_ID   };
            case "A": { _vehArray#APC_ID    };
            case "C": { _vehArray#CAR_ID    };
            case "H": { _vehArray#HELI_ID   };
            case "P": { _vehArray#PLANE_ID  };
            case "S": { _vehArray#STATIC_ID };
            case "N": { _vehArray#NAVAL_ID  };
            case "U": { _vehArray#UAV_ID    };
            default {diag_log format ["Error Pos: VehicleChooser_Get called with invalid type (%1)",_type]};
        };
    if !(_includeTextureAnim) then {
        _result = _result apply {_x#0};
    };
    _result
};

VehicleChooser_Sort = {
    params ["_allVehicles"];
    _result = [];
    for "_i" from 1 to ID_COUNT do {_result pushBack []};
    {
        private _className = _x#0;
        private _cfg = configFile >> "CfgVehicles" >> _className;
        if (getNumber (_cfg >> "isUav") != 0) then {
            _result#UAV_ID pushBack _x;
        } else {
            switch (true) do {
                case (_className isKindOf "Helicopter"):  {_result#HELI_ID   pushBack _x};
                case (_className isKindOf "Plane"):       {_result#PLANE_ID  pushBack _x};
                case (_className isKindOf "Ship"):        {_result#NAVAL_ID  pushBack _x};
                case (_className isKindOf "Tank"):        {
                    if (getnumber (_cfg >> "maxspeed") > 0) then { _result#TANK_ID   pushBack _x}
                    else {                                         _result#STATIC_ID pushBack _x};
                };
                case (_className isKindOf "LandVehicle"): {
                    if (getnumber (_cfg >> "maxspeed") == 0) then { _result#STATIC_ID pushBack _x}
                    else {
                        private _cat = (_cfg >> "editorSubcategory") call BIS_fnc_getCfgData;
                        if (["apc", _cat, false] call BIS_fnc_inString) then {_result#APC_ID pushBack _x}
                        else {                                                _result#CAR_ID pushBack _x};
                    };
                };
            };
        };
    } forEach _allVehicles;

    _result;
};

VehicleChooser_Wait = {
    // Can be called on extra clients while other player selects factions
    waitUntil {sleep 1; missionNamespace getVariable ["FACTION_DONE",false]};
};

VehicleChooser_Start = {
    params ["_multiselect","_msg","_factions"];

    if (typeName _factions isEqualTo "STRING") then {_factions = [_factions]};
    _factions = _factions apply {
        private _idx = _x find ":";
        if (_idx < 0) then {toUpperANSI _x} else {toUpperANSI(_x select [0,_idx])};
    };
    _factions = _factions arrayIntersect _factions;

    missionNamespace setVariable ["VehicleChooser_vehArray",[]];
    missionNamespace setVariable ["VehicleChooser_multiSelect",_multiselect];

    if (_multiselect) then {
        // generate vehicle class lists
        "VehChooser" cutText [localize "STR_SKL_VC_ParsingVehicles", "BLACK OUT", 0.001]; //
        private _vehClassesMap = createHashMap; // array of [lower case vehClass,[displayName,[veh,veh,veh...]]
        private _factionVehClassesMap = createHashMap; // array of [lower case vehClass,[displayName,[veh,veh,veh...]]
        {
            private _cfg = _x;
            private _cfgName = configName _cfg;
            private _cfgFaction = (toUpperANSI getText (_cfg >> "faction"));
            private _isFaction = _cfgFaction in _factions;
            {
                if (_cfgName isKindOf _x) exitWith {
                    private _vehClassType = toLowerANSI getText (configFile >> "cfgVehicles" >> _cfgName >> "vehicleclass");
                    private _displayName = getText (configFile >> "cfgVehicleClasses" >> _vehClassType >> "displayName");
                    if !(_displayName isEqualTo "") then {
                        private _dataArray = _vehClassesMap getOrDefault [_vehClassType,["",[]]];
                        if (_dataArray#0 isEqualTo "") then {_dataArray set [0,_displayName]};
                        _dataArray#1 pushBack _cfgName;
                        _vehClassesMap set [_vehClassType,_dataArray];
                        if (_isFaction) then {
                            private _dataArray = _factionVehClassesMap getOrDefault [_vehClassType,["",[]]];
                            if (_dataArray#0 isEqualTo "") then {_dataArray set [0,_displayName]};
                            _dataArray#1 pushBack _cfgName;
                            _factionVehClassesMap set [_vehClassType,_dataArray];
                        };
                    };
                };
                false
            } count ["Car","Tank","Helicopter","Plane","StaticMortar", "StaticMGWeapon", "StaticGrenadeLauncher", "StaticCannon", "StaticAAWeapon", "gm_staticWeapon_base"];
        } forEach ("(getNumber (_x >> 'scope') == 2) || {(getNumber (_x >> 'scope') == 1) && (getNumber (_x >> 'scopeCurator') == 2)}" configClasses (configFile / "CfgVehicles"));
        private _keysV = keys _vehClassesMap;
        _keysV sort true;
        private _keysF = keys _factionVehClassesMap;
        _keysF sort true;
        VehicleChooser_VehClassMap         =_vehClassesMap;
        VehicleChooser_FactionVehClassMap  =_factionVehClassesMap;
        VehicleChooser_VehClassKeys        =_keysV;
        VehicleChooser_FactionVehClassKeys =_keysF;

        "VehChooser" cutText ["", "PLAIN", 0.001];
    };

    private _done = false;
    private _ehID = [missionNamespace, "garageClosed", {missionNamespace setVariable ["VEHICLE_CHOOSER_CLOSED",true]}] call BIS_fnc_addScriptedEventHandler;
    missionNamespace setVariable ["VEHICLE_CHOOSER_CLOSED",false];

    private _emptyType = "RoadCone_F";
    // find flat ground somewhere for garage
    private _pos = getArray(configfile >> "CfgWorlds" >> worldName >> "ilsPosition" );
    if (_pos isEqualTo [] || {_pos isEqualTo [0,0]}) then {
        private _mapRadius = worldSize/2;
        //_pos = [_mapRadius, _mapRadius, 0] findEmptyPosition [0,_mapRadius,"B_Heli_Transport_03_unarmed_F"]; -- Don't use findEmptyPosition with radius > 50, it causes frame drops
        _pos = [[_mapRadius, _mapRadius, 0], 0, _mapRadius, 10, 0, 0.25, 0, [] ,[[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo [] || {_pos isEqualTo [0,0]}) then {_pos = [_mapRadius, _mapRadius, 0]};
    };
    BIS_fnc_garage_center  = createVehicle ["RoadCone_F", _pos, [], 0, "CAN_COLLIDE"];
    if (isNil "VehicleChooser_GarageFN") then {VehicleChooser_GarageFN = BIS_fnc_garage};
    ["Open",[true,BIS_fnc_garage_center]] call VehicleChooser_GarageFN;

    #define CHOICE_LIST_ID  552211
    #define CLASS_LIST_ID   552213
    #define
    private _display = displayNull;
    waitUntil {_display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];! isNil "_display" && {! isNull _display} };
    _display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];

    private _ctrlButtonHide = _display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONINTERFACE;

    if (_multiselect) then {
        // add list showing selected vehicles
        private _x = safezoneX + safezoneW - 35 * (((safezoneW / safezoneH) min 1.2) / 40);
        private _w = 17.0 *                       (((safezoneW / safezoneH) min 1.2) / 40);
        private _y =  6.5 *                       ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25);
        private _h = 23.5 *                       ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25);
        private _topMargin = 1 *                  ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25);
        private _botMargin = _topMargin * 2.5;
        private _marginGap = _topMargin * 0.05;
        private _buttonW = _w/5;
        private _buttonH = _botMargin * 0.9;
        private _buttonSmallH = (_buttonH - _marginGap)/2;
        private _buttonBG = [0,0,0,0.75];
        private _listBG   = [0,0,0,0.50];
        private _headerBG = [0,0,0,0.30];
        private _allUiElements = [];
        
        private _frame = _display ctrlCreate ["RscFrame",-1];
        _frame ctrlSetPosition [_x,_y - _buttonH - _marginGap,_w,_buttonH];
        _frame ctrlSetTextColor _listBG;
        _frame ctrlCommit 0;
        _allUiElements pushBack _frame;
        private _text = _display ctrlCreate ["RscTextNoShadow", -1];
        _text ctrlSetPosition [_x,_y - _buttonH - _marginGap,_w,_buttonH];
        _text ctrlSetText _msg;
        _text ctrlSetTextColor [0,0,0,1];
        _text ctrlSetBackgroundColor [1,1,1,1];
        _text ctrlCommit 0;
        _allUiElements pushBack _text;

        _frame = _display ctrlCreate ["RscFrame",-1];
        _frame ctrlSetPosition [_x,_y,_w,_h + _marginGap];
        _frame ctrlSetTextColor _listBG;
        _frame ctrlCommit 0;
        _allUiElements pushBack _frame;
        private _vcListBox = _display ctrlCreate ["RscListBoxMulti", -1];
        _vcListBox ctrlSetPosition [_x,_y + _topMargin,_w,_h - _topMargin - _botMargin];
        _vcListBox ctrlSetBackgroundColor _listBG;
        _vcListBox ctrlAddEventHandler ["lbdblclick",{if (call VC_ButtonSafe) then {0 spawn VC_ViewVeh};true}];
        _vcListBox ctrlCommit 0;
        _allUiElements pushBack _vcListBox;
        uiNamespace setVariable ["VC_ChoiceListCtrl",_vcListBox];
        _text = _display ctrlCreate ["RscTextNoShadow", -1];
        _text ctrlSetPosition [_x,_y,_w,_topMargin + _marginGap];
        _text ctrlSetText localize "STR_SKL_VC_VehiclesChosen";
        _text ctrlSetTextColor [1,1,1,1];
        _text ctrlSetBackgroundColor _headerBG;
        _text ctrlCommit 0;
        _allUiElements pushBack _text;
        private _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW/8,_y + _h - _buttonH - _marginGap,_buttonW*2.25,_buttonH];
        _button ctrlSetText localize "STR_SKL_VC_AddVehicle";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_AddVeh};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*21/8,_y + _h - _buttonH - _marginGap,_buttonW,_buttonSmallH];
        _button ctrlSetText localize "STR_SKL_VC_Remove";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_RemoveVeh};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*31/8,_y + _h - _buttonH - _marginGap,_buttonW,_buttonSmallH];
        _button ctrlSetText localize "STR_SKL_VC_View";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {0 spawn VC_ViewVeh};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*21/8,_y + _h - _buttonH/2 - _marginGap/2,_buttonW,_buttonSmallH];
        _button ctrlSetText localize "STR_SKL_COMMON_All";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_AllVeh};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*31/8,_y + _h - _buttonH/2 - _marginGap/2,_buttonW,_buttonSmallH];
        _button ctrlSetText "Class"; // localize "STR_SKL_VC_Class";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_ToggleClassVeh};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;

        // add list showing vehicle classes
        _x = safezoneX + safezoneW - 17.5 *(((safezoneW / safezoneH) min 1.2) / 40);
        _h = 20.5 *                        ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25);

        _frame = _display ctrlCreate ["RscFrame",-1];
        _frame ctrlSetPosition [_x,_y,_w,_h + _marginGap*2];
        _frame ctrlSetTextColor _listBG;
        _frame ctrlCommit 0;
        _allUiElements pushBack _frame;
        private _listBox = _display ctrlCreate ["RscListBoxMulti", -1];
        _listBox ctrlSetPosition [_x,_y + _topMargin ,_w,_h - _topMargin - _botMargin - _marginGap];
        _listBox ctrlSetBackgroundColor _listBG;
        _listBox ctrlCommit 0;
        _allUiElements pushBack _listBox;
        uiNamespace setVariable ["VC_VehClassListCtrl",_listBox];
        _text = _display ctrlCreate ["RscTextNoShadow", -1];
        _text ctrlSetPosition [_x,_y,_w,_topMargin + _marginGap];
        _text ctrlSetText localize "STR_SKL_VC_VehicleClasses";
        _text ctrlSetTextColor [1,1,1,1];
        _text ctrlSetBackgroundColor _headerBG;
        _text ctrlCommit 0;
        _allUiElements pushBack _text;
        uiNamespace setVariable ["VC_VehClassTextCtrl",_text];
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW/8,_y + _h - _buttonH - 3*_marginGap,_buttonW,_buttonH/2];
        _button ctrlSetText localize "STR_SKL_COMMON_All";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_AllVehClasses};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        //_button = _display ctrlCreate ["RscButton",-1];
        //_button ctrlSetPosition [_x + _buttonW*11/8,_y + _h - _buttonH - 3*_marginGap,_buttonW,_buttonH/2];
        //_button ctrlSetText "None"; // localize
        //_button ctrlSetBackgroundColor _buttonBG;
        //_button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_NoVehClasses};true}];
        //_button ctrlCommit 0;
        //_allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*21/8,_y + _h - _buttonH - 3*_marginGap,_buttonW,_buttonH/2];
        _button ctrlSetText localize "STR_SKL_VC_Add";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_AddVehClasses};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _buttonW*31/8,_y + _h - _buttonH - 3*_marginGap,_buttonW,_buttonH/2];
        _button ctrlSetText localize "STR_SKL_VC_Remove";
        _button ctrlSetBackgroundColor _buttonBG;
        //_button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_RemoveVehClasses};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        if !(_factions isEqualTo []) then {
            _button = _display ctrlCreate ["RscButton",-1];
            _button ctrlSetPosition [_x + _buttonW/8,_y + _h - _buttonH/2 - _marginGap,_buttonW*19/4,_buttonH/2];
            _button ctrlSetText localize "STR_SKL_VC_ToggleFactionAll";
            _button ctrlSetBackgroundColor _buttonBG;
            _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {call VC_ToggleVehClasses};true}];
            _button ctrlCommit 0;
            _allUiElements pushBack _button;
            call VC_ToggleVehClasses;
        } else {
            _frame ctrlSetPosition [_x,_y,_w,_h + _marginGap - _buttonH/2];
            _frame ctrlCommit 0;
            _allUiElements pushBack _frame;
        };

        // handle the 'hide interface' button and key (backspace)
        VC_AllUiElements = _allUiElements;
        _ctrlButtonHide ctrlAddEventHandler ["buttonclick",{if (call VC_ButtonSafe) then {call VC_HideInterface};true}];
        _display displayAddEventHandler ["keyDown",{
            params ["_display","_key"];
            private _ctrlTemplate = _display displayctrl IDC_RSCDISPLAYARSENAL_TEMPLATE_TEMPLATE;
            private _inTemplate = ctrlfade _ctrlTemplate == 0;
            if (_key == DIK_BACKSPACE && !_inTemplate) then {call VC_HideInterface;};
        }];
        
        // add the ability to load/save/deleteSave of vehicle collections
		_ctrlButtonSave = _display displayctrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONSAVE;
		_ctrlButtonSave ctrlenable false;

		_ctrlButtonLoad = _display displayctrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONLOAD;
		_ctrlButtonLoad ctrlenable false;

		_ctrlButtonExport = _display displayctrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONEXPORT;
		_ctrlButtonExport ctrlenable false;

		_ctrlButtonImport = _display displayctrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONIMPORT;
		_ctrlButtonImport ctrlenable false;

        
        _marginGap = _buttonW/8;
        _x = safezoneX + safezoneW - 35 * (((safezoneW / safezoneH) min 1.2) / 40);
        _y = 31 *                         ((((safezoneW / safezoneH) min 1.2) / 1.2) / 25);
        _w = (2*_buttonW) + (4*_marginGap);
        _h = _buttonSmallH + (2*_marginGap);
        
        _frame = _display ctrlCreate ["RscFrame",-1];
        _frame ctrlSetPosition [_x,_y,_w,_h];
        _frame ctrlSetTextColor _listBG;
        _frame ctrlCommit 0;
        _allUiElements pushBack _frame;
    
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + _marginGap,_y + _marginGap,_buttonW,_buttonSmallH];;
        _button ctrlSetText localize "STR_DISP_INT_LOAD";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {"buttonLoad" call VC_LoadSaveButton};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        
        _button = _display ctrlCreate ["RscButton",-1];
        _button ctrlSetPosition [_x + (3*_marginGap) + _buttonW,_y + _marginGap,_buttonW,_buttonSmallH];
        _button ctrlSetText localize "STR_DISP_INT_SAVE";
        _button ctrlSetBackgroundColor _buttonBG;
        _button ctrlAddEventHandler ["ButtonClick",{if (call VC_ButtonSafe) then {"buttonSave" call VC_LoadSaveButton;true};true}];
        _button ctrlCommit 0;
        _allUiElements pushBack _button;
        
        waitUntil {missionNamespace getVariable ["VEHICLE_CHOOSER_CLOSED",false]};
    } else {
        private _cehid = _ctrlButtonHide ctrlAddEventHandler ["buttonclick",
            'if (call VC_ButtonSafe) then {
                params ["_control"];
                playSoundUI ["Click", 0.75, 1];
                private _textureAnim = [BIS_fnc_arsenal_center] call BIS_fnc_getVehicleCustomization;
                private _type = typeOf BIS_fnc_arsenal_center;
                private _vehArray = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
                _vehArray pushBack [_type,_textureAnim#0,_textureAnim#1];
                with uiNamespace do {["buttonClose",[ctrlparent (_this select 0)]] call bis_fnc_arsenal;};
            };
            true'];
        private _oldText = ctrlText _ctrlButtonHide;
        _ctrlButtonHide ctrlSetText localize "STR_SKL_VC_Select";

        // add message
        "VehicleChooser" cuttext ["<t size='2'><br/><br/><br/><br/><br/><br/><br/><br/>" + _msg + "<br/>" + localize "STR_SKL_VC_UseSelectBtn" + "</t>","PLAIN",-1,true,true];
        waitUntil {missionNamespace getVariable ["VEHICLE_CHOOSER_CLOSED",false]};
        _ctrlButtonHide ctrlRemoveEventHandler ["buttonclick",_cehid];
        "VehicleChooser" cuttext ["","PLAIN",-1];
    };

    deleteVehicle BIS_fnc_garage_center;

    missionNamespace setVariable ["VEHICLE_CHOOSER_SELECTED",missionNamespace getVariable ["VehicleChooser_vehArray",[]],true];
    VehicleChooser_multiSelect = nil;
    VehicleChooser_VehClassMap = nil;
    VehicleChooser_FactionVehClassMap = nil;
    VehicleChooser_vehArray = nil;
    VehicleChooser_VehClassKeys = nil;
    VehicleChooser_FactionVehClassKeys = nil;
};

VC_ButtonSafe = {
    // I was seeing a lot of double and triple button triggers on 'buttonClick' handlers
    if (isNil "VC_buttonTime") then {VC_buttonTime = 0};
    private _okay = time > VC_buttonTime;
    VC_buttonTime = time + 0.45;    
    _okay
};

VC_AddVeh = {
    private _vehArray  = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    playSoundUI ["Click", 0.75, 1];
    private _textureAnim = [BIS_fnc_arsenal_center] call BIS_fnc_getVehicleCustomization;
    private _type = typeOf BIS_fnc_arsenal_center;
    private _index = _vcListBox lbAdd ([getText (configFile >> "CfgVehicles" >> _type >> "DisplayName"),_type] call VC_DisplayText);
    _vcListBox lbSetData [_index,_type];
    _vehArray pushBack [_type,_textureAnim#0,_textureAnim#1];
    _vcListBox ctrlSetScrollValues [1, 0];
};

VC_RemoveVeh = {
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    private _vehArray  = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
    {
        _vehArray deleteAt _x;
        _vcListBox lbDelete _x;
    } forEachReversed lbSelection _vcListBox
};

VC_AllVeh = {
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    for "_i" from 0 to (lbSize _vcListBox - 1) do {
        _vcListBox lbSetSelected [_i, true];
    };
};

VC_DisplayText = {
    params ["_text","_cfgName"];   
    private _showClassName = missionNamespace getVariable ["VC_ShowClassNames",false];
    if (_showClassName) then { _text + "   ["+_cfgName+"]"}
    else                     { _text };
};

VC_ToggleClassVeh = {
    private _showClassName = missionNamespace getVariable ["VC_ShowClassNames",false];
    _showClassName = !_showClassName;
    missionNamespace setVariable ["VC_ShowClassNames",_showClassName];
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    for "_i" from 0 to (lbSize _vcListBox - 1) do {
        private _oldText = _vcListBox lbText _i;
        private _cfgName = _vcListBox lbData _i;
        private _newText = if (_showClassName) then {
            _oldText + "   ["+_cfgName+"]";
        } else {
            _oldText select [0,count _oldText - 5 - count _cfgName];
        };
        _vcListBox lbSetText [_i, _newText];
    };
};

VC_ViewVeh = {
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    private _vehArray  = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
    private _selections = lbSelection _vcListBox;
    if (count _selections == 0) exitWith {};
    private _index = _selections#0;
    private _viewData = _vehArray#_index;
    private _viewClass = _viewData#0;
    private _viewCfg = configFile >> "cfgVehicles" >> _viewClass;
    private _viewModel = getText (_viewCfg >> "model");
    private _sklVersion = true;
    private _data = missionnamespace getVariable "skl_fnc_garage_data";
    if (isNil "_data") then {_data = missionnamespace getVariable "bis_fnc_garage_data";_sklVersion = false;};
    private _done = false;
    private _modelMatch = [];
    private _checkboxTextures = [
        tolower gettext (configfile >> "RscCheckBox" >> "textureUnchecked"),
        tolower gettext (configfile >> "RscCheckBox" >> "textureChecked")
    ];
    private ["_modelIdc","_modelIndex","_classIdc","_classIndex"];
    if (_sklVersion) then {
        {
            private _idc = _x;
            private _tabData = _data#_idc;
            private _cnt = count _tabData;
            // tabData format: [p3dModel,[[name,[cfg,cfg,...]], [name,[cfg,cfg...]], ...], p3dModel,[[name,[cfg,cfg,...]], [name,[cfg,cfg...]], ...], ...]
            for "_i" from 0 to (count _tabData - 1) step 2 do {
                private _model = _tabData#_i;
                private _modelData = _tabData#(_i+1);
                if (_model == _viewModel) then {_modelIdc = _idc; _modelIndex = _i*1000};
                {
                    _x params ["_displayName","_cfgsFull"];
                    private _j = _forEachIndex;
                    {
                        if (configName _x == _viewClass) exitWith {_classIdc = _idc; _classIndex = _i*1000 + _j;_done = true};
                    } forEach _cfgsFull;
                    if (_done) exitWith {};
                } forEach _modelData;
                if (_done) exitWith {};
            };
        } forEach [IDC_RSCDISPLAYGARAGE_TAB_CAR,IDC_RSCDISPLAYGARAGE_TAB_ARMOR,IDC_RSCDISPLAYGARAGE_TAB_HELI,IDC_RSCDISPLAYGARAGE_TAB_PLANE,IDC_RSCDISPLAYGARAGE_TAB_NAVAL,IDC_RSCDISPLAYGARAGE_TAB_STATIC];
    } else {
        {
            private _idc = _x;
            private _tabData = _data#_idc;
            private _cnt = count _tabData;
            for "_index" from 0 to (_cnt-1) step 2 do {
                // tabData format: model, [name,[cfg,cfg,cfg...]],  model, [name,[cfg,cfg,cfg...]], ...
                private _modelData = _tabData#_index;
                private _cfg = _tabData#(_index+1)#0;
                private _className = configName _cfg;
                if (_modelData == _viewModel) then     {_modelIdc = _idc; _modelIndex = _index};
                if (_className == _viewClass) exitWith {_classIdc = _idc; _classIndex = _index;_done = true};
            };
            if (_done) exitWith {};
        } forEach [IDC_RSCDISPLAYGARAGE_TAB_CAR,IDC_RSCDISPLAYGARAGE_TAB_ARMOR,IDC_RSCDISPLAYGARAGE_TAB_HELI,IDC_RSCDISPLAYGARAGE_TAB_PLANE,IDC_RSCDISPLAYGARAGE_TAB_NAVAL,IDC_RSCDISPLAYGARAGE_TAB_STATIC];
    };
    if (!isNil "_classIndex" || {! isNil "_modelIndex"}) then {
        private _idc   = if (isNil "_classIdc"  ) then {_modelIdc  } else {_classIdc  };
        private _index = if (isNil "_classIndex") then {_modelIndex} else {_classIndex};
        
        if (isNil "BIS_fnc_arsenal_campos") then {BIS_fnc_arsenal_campos = [5,0,0,[0,0,0.85]]};
    
        private _display = uiNamespace getVariable ["bis_fnc_arsenal_display",displaynull];
        private _viewListCtrl = _display displayCtrl (IDC_RSCDISPLAYARSENAL_LIST + _idc);
        for "_j" from 0 to lbSize _viewListCtrl do {
            if (_viewListCtrl lbValue _j isEqualTo _index) exitWith {_viewListCtrl lbSetCurSel _j};
        };

        ["TabSelectLeft",[_display,_idc]] call VehicleChooser_GarageFN;
        //--- Textures
        private _textures = _viewData#1;
        private _ctrlListTextures = _display displayCtrl (IDC_RSCDISPLAYARSENAL_LIST + IDC_RSCDISPLAYGARAGE_TAB_SUBTEXTURE);
        private _texture = selectRandomWeighted _textures;
        if (!isNil "_texture") then {
            // Global mobilization doesn't actually match texture to texturesources, 
            // for example texture "gm_gc_army_win" maps to textureSources "gm_gm_win", so play some stupid games
            private _texture2 = if (_texture select [0,3] == "gm_") then {
                private _parts = _texture splitString "_";
                _parts deleteAt 2;
                _parts joinString "_"
            } else {""};
            _ctrlListTextures lbSetCursel -1;
            for "_j" from 0 to (lbSize _ctrlListTextures - 1) do {
                private _lbTexture =_ctrlListTextures lbData _j;
                if (_texture == _lbTexture) then {
                    _ctrlListTextures lbsetcursel  _j;
                };
                if !(_texture2 isEqualTo "") then {
                    if (_texture2 == _lbTexture) then {
                        _ctrlListTextures lbsetcursel  _j;
                    };
                };
            };
        };
        
        //--- Animations
        private _animations = _viewData#2;
        private _ctrlListAnimations = _display displayCtrl (IDC_RSCDISPLAYARSENAL_LIST + IDC_RSCDISPLAYGARAGE_TAB_SUBANIMATION);
        for "_i" from 0 to (count _animations - 1) step 2 do {
            private _anim = _animations#_i;
            private _state = round (_animations#(_i+1));
            for "_j" from 0 to (lbSize _ctrlListAnimations - 1) do {
                if (_anim == (_ctrlListAnimations lbData _j)) exitWith {
                    private _curState = _checkboxTextures find (_ctrlListAnimations lbpicture _j);
                    if (_state != _curState) then {_ctrlListAnimations lbsetcursel  _j};
                };
            };
        } forEach _animations;
    };
};

VC_AllVehClasses = {
    private _listBox = uiNamespace getVariable ["VC_VehClassListCtrl",controlNull];
    for "_i" from 0 to (lbSize _listBox - 1) do {
        _listBox lbSetSelected [_i, true];
    };
};

VC_NoVehClasses = {
    private _listBox = uiNamespace getVariable ["VC_VehClassListCtrl",controlNull];
    for "_i" from 0 to (lbSize _listBox - 1) do {
        _listBox lbSetSelected [_i, false];
    };
};

VC_AddVehClasses = {
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    private _listBox   = uiNamespace getVariable ["VC_VehClassListCtrl",controlNull];
    private _vehArray  = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
    private _text = uiNamespace getVariable ["VC_VehClassTextCtrl",controlNull];
    private _map = switch (_text getVariable ["vc_state",1]) do {
        case 0: { missionNamespace getVariable "VehicleChooser_FactionVehClassMap" };
        case 1: { missionNamespace getVariable "VehicleChooser_VehClassMap" };
    };
    if (isNil "_map") exitWith {};
    private _items = [];
    {
        private _vehClass = _listBox lbData _x;

        private _classes = (_map getOrDefault [_vehClass,["???",["",[]]]])#1;
        {
            private _displayName = getText (configFile >> "cfgVehicles" >> _x >> "displayName");
            _items pushBack [_displayName,_x];
        } forEach _classes;
    } forEach lbSelection _listBox;
    _items sort true;
    {
        _x params ["_displayName","_cfgName"];
        private _cfg = configFile >> "cfgVehicles" >> _cfgName;
        private _index = _vcListBox lbAdd ([_displayName,_cfgName] call VC_DisplayText);
        _vcListBox lbSetData [_index,_cfgName];
        // get base animations and set them all, then overwrite the animationList values
        private _animList = [];
        {
            if (gettext (_x >> "displayName") != "" && {getnumber (_x >> "scope") > 1 || !isnumber (_x >> "scope")}) then {
                _animList pushBack configName _x;
                _animList pushBack getNumber (_x >> "initPhase");
            };
        } foreach (configproperties [_cfg >> "AnimationSources","isclass _x",true]);
        private _configAnimList = getArray (_cfg >> "animationList");
        for "_i" from 0 to (count _configAnimList - 1) step 2 do {
            private _anim = _configAnimList#_i;
            private _anim = _configAnimList#_i;
            private _index = _animList find _anim;
            if (_index >= 0) then {_animList set [_index+1,_configAnimList#(_i+1)]};
        };
        _vehArray pushBack [_cfgName,getArray (_cfg >> "textureList"),_animList];
    } forEach _items;
};

VC_RemoveVehClasses = {
    private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
    private _listBox   = uiNamespace getVariable ["VC_VehClassListCtrl",controlNull];
    private _vehArray  = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
    private _text = uiNamespace getVariable ["VC_VehClassTextCtrl",controlNull];
    private _map = switch (_text getVariable ["vc_state",1]) do {
        case 0: { missionNamespace getVariable "VehicleChooser_FactionVehClassMap" };
        case 1: { missionNamespace getVariable "VehicleChooser_VehClassMap" };
    };
    if (isNil "_map") exitWith {};
    private _items = [];
    {
        private _vehClass = _listBox lbData _x;
        private _classes = (_map getOrDefault [_vehClass,["???",["",[]]]])#1;
        _items = _items + _classes;
    } forEach lbSelection _listBox;
    for "_i" from (lbSize _vcListBox - 1) to 0 step -1 do {
        private _data = _vcListBox lbData _i;
        if (_data in _items) then {
            _vehArray deleteAt _i;
            _vcListBox lbDelete _i;
        };
    };
};

VC_ToggleVehClasses = {
    private _text = uiNamespace getVariable ["VC_VehClassTextCtrl",controlNull];
    private ["_keys","_map"];
    switch (_text getVariable ["vc_state",1]) do {
        case 0: { // switch to 'all'
            _text setVariable ["vc_state",1];
            _text   ctrlSetText localize "STR_SKL_VC_AllVehClasses";
            _keys = missionNamespace getVariable ["VehicleChooser_VehClassKeys",[]];
            _map  = missionNamespace getVariable "VehicleChooser_VehClassMap"
        };
        case 1: { // switch to 'faction'
            _text setVariable ["vc_state",0];
            _text   ctrlSetText localize "STR_SKL_VC_FactionVehClasses";
            _keys = missionNamespace getVariable ["VehicleChooser_FactionVehClassKeys",[]];
            _map  = missionNamespace getVariable "VehicleChooser_FactionVehClassMap";
        };
    };
    if (isNil "_map") exitWith {diag_log "ERROR POS: VC_ToggleVehClasses called when vehClassMap doesn't exist"};
    private _listBox = uiNamespace getVariable ["VC_VehClassListCtrl",controlNull];
    lbClear _listBox;
    {
        private _index = _listBox lbAdd ((_map getOrDefault [_x,["???",[]]])#0);
        _listBox lbSetData [_index,_x];
    } forEach _keys;
};

VC_HideInterface = {
    private _display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];
    private _show = !ctrlShown (_display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_CONTROLBAR);
    {
        private _ctrl = _x;
        _ctrl ctrlShow _show;
        _ctrl ctrlCommit 0.15;
    } forEach VC_AllUiElements;
};

VC_LoadSaveButton = {    
    private _display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];
    private _savedNames = ["GET"] call VC_SaveLoadData;    
    
    switch (_this) do {
        case "buttonLoad": 
        {
            _display setVariable ["saveMode", false];

            private _ctrlTemplate = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_TEMPLATE;
            _ctrlTemplate ctrlSetFade 0;
            _ctrlTemplate ctrlCommit 0;
            _ctrlTemplate ctrlEnable true;

            private _ctrlMouseBlock = _display displayCtrl IDC_RSCDISPLAYARSENAL_MOUSEBLOCK;
            _ctrlMouseBlock ctrlEnable true;
            ctrlsetfocus _ctrlMouseBlock;

            {
                (_display displayCtrl _x) ctrlSetText localize "str_disp_int_load";
            } foreach [IDC_RSCDISPLAYARSENAL_TEMPLATE_TITLE,IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONOK];
            {
                private _ctrl = _display displayCtrl _x;
                _ctrl ctrlShow false;
                _ctrl ctrlEnable false;
            } foreach [IDC_RSCDISPLAYARSENAL_TEMPLATE_TEXTNAME,IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME];
            
            private _ctrlTemplateValue = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_VALUENAME;
            lnbclear _ctrlTemplateValue;
            {
                _ctrlTemplateValue lnbAddRow [_x];
            } forEach _savedNames;
            _ctrlTemplateValue lnbSort [0,false];
            _ctrlTemplateValue ctrlRemoveAllEventHandlers "lbselchanged";
            _ctrlTemplateValue ctrlRemoveAllEventHandlers "lbdblclick";
            _ctrlTemplateValue ctrladdeventhandler ["lbdblclick",{
                private _saveName = _this call VC_GetLoadSaveSelected;
                if (_saveName != "") then {["LOAD",_saveName] call VC_SaveLoadData};
            }];
            
            private _ctrlTemplateButtonOK = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONOK;
            _ctrlTemplateButtonOK ctrlEnable true;
            _ctrlTemplateButtonOK ctrlRemoveAllEventHandlers "buttonclick";
            _ctrlTemplateButtonOK ctrlAddEventHandler ["buttonclick",{
                private _saveName = _this call VC_GetLoadSaveSelected;
                if (_saveName != "") then {["LOAD",_saveName] call VC_SaveLoadData};
            }];
            
            private _ctrlTemplateButtonDelete = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONDELETE;
            _ctrlTemplateButtonDelete ctrlEnable ((lnbsize _ctrlTemplateValue select 0) > 0);
            _ctrlTemplateButtonDelete ctrlRemoveAllEventHandlers "buttonclick";
            _ctrlTemplateButtonDelete ctrlAddEventHandler ["buttonclick",{
                private _saveName = _this call VC_GetLoadSaveSelected;
                if (_saveName != "") then {
                    ["DELETE",_saveName] call VC_SaveLoadData;
                    _savedNames = ["GET"] call VC_SaveLoadData;
                    with uiNamespace do {
                        private _ctrlTemplateValue = (ctrlParent (_this select 0)) displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_VALUENAME;
                        lnbclear _ctrlTemplateValue;
                        {
                            _ctrlTemplateValue lnbAddRow [_x];
                        } forEach _savedNames;
                        _ctrlTemplateValue lnbSort [0,false];
                    };
                };
            }];
        };
    
        ///////////////////////////////////////////////////////////////////////////////////////////
        case "buttonSave": 
        {
            _display setVariable ["saveMode", true];

            private _ctrlTemplate = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_TEMPLATE;
            _ctrlTemplate ctrlSetFade 0;
            _ctrlTemplate ctrlCommit 0;
            _ctrlTemplate ctrlEnable true;
            
            private _ctrlMouseBlock = _display displayCtrl IDC_RSCDISPLAYARSENAL_MOUSEBLOCK;
            _ctrlMouseBlock ctrlEnable true;

            {
                (_display displayCtrl _x) ctrlSetText localize "str_disp_int_save";
            } forEach [IDC_RSCDISPLAYARSENAL_TEMPLATE_TITLE,IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONOK];
            {
                private _ctrl = _display displayCtrl _x;
                _ctrl ctrlShow true;
                _ctrl ctrlEnable true;
            } forEach [IDC_RSCDISPLAYARSENAL_TEMPLATE_TEXTNAME,IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME];
            {
                private _ctrl = _display displayCtrl _x;
                _ctrl ctrlShow false;
                _ctrl ctrlEnable false;
            } forEach [IDC_RSCDISPLAYARSENAL_TEMPLATE_COLUMN2,IDC_RSCDISPLAYARSENAL_TEMPLATE_COLUMN3,IDC_RSCDISPLAYARSENAL_TEMPLATE_COLUMN4,IDC_RSCDISPLAYARSENAL_TEMPLATE_COLUMN5];
            private _ctrlTemplateName = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME;
            ctrlsetfocus _ctrlTemplateName;

            private _ctrlTemplateValue = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_VALUENAME;
            lnbclear _ctrlTemplateValue;
            {
                _ctrlTemplateValue lnbAddRow [_x];
            } forEach _savedNames;
            _ctrlTemplateValue lnbSort [0,false];
            _ctrlTemplateValue lnbsetcurselrow -1;
            _ctrlTemplateValue ctrlRemoveAllEventHandlers "lbselchanged";
            _ctrlTemplateValue ctrlRemoveAllEventHandlers "lbdblclick";
            _ctrlTemplateValue ctrladdeventhandler ["lbdblclick",{
                private _saveName =  with uiNamespace do {ctrlText ((ctrlParent (_this select 0)) displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME)};
                ["SAVE",_saveName] call VC_SaveLoadData;
            }];
            _ctrlTemplateValue ctrladdeventhandler ["lbselchanged",{
                private _display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];
                private _ctrlTemplateName = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME;
                _ctrlTemplateName ctrlSetText (_this call VC_GetLoadSaveSelected);
            }];
            
            private _ctrlTemplateButtonOK = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONOK;
            _ctrlTemplateButtonOK ctrlEnable true;
            _ctrlTemplateButtonOK ctrlRemoveAllEventHandlers "buttonclick";
            _ctrlTemplateButtonOK ctrlAddEventHandler ["buttonclick",{
                private _saveName =  with uiNamespace do {ctrlText ((ctrlParent (_this select 0)) displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME)};
                ["SAVE",_saveName] call VC_SaveLoadData;
            }];
            
            private _ctrlTemplateButtonDelete = _display displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_BUTTONDELETE;
            _ctrlTemplateButtonDelete ctrlEnable ((lnbsize _ctrlTemplateValue select 0) > 0);
            _ctrlTemplateButtonDelete ctrlRemoveAllEventHandlers "buttonclick";
            _ctrlTemplateButtonDelete ctrlAddEventHandler ["buttonclick",{
                private _saveName =  with uiNamespace do {ctrlText ((ctrlParent (_this select 0)) displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_EDITNAME)};
                if (_saveName != "") then {
                    ["DELETE",_saveName] call VC_SaveLoadData;
                    _savedNames = ["GET"] call VC_SaveLoadData;
                    with uiNamespace do {
                        private _ctrlTemplateValue = (ctrlParent (_this select 0)) displayCtrl IDC_RSCDISPLAYARSENAL_TEMPLATE_VALUENAME;
                        lnbclear _ctrlTemplateValue;
                        {
                            _ctrlTemplateValue lnbAddRow [_x];
                        } forEach _savedNames;
                        _ctrlTemplateValue lnbSort [0,false];
                    };
                };
            }];
            
        };
    };
};

VC_GetLoadSaveSelected = {
    private _selected = "";
    with uiNamespace do {
        private _ctrlTemplateValue = (ctrlParent (_this select 0)) displayctrl IDC_RSCDISPLAYARSENAL_TEMPLATE_VALUENAME;
        private _cursel = lnbCurSelRow _ctrlTemplateValue;     
        if (_cursel >= 0) then {
            _selected = _ctrlTemplateValue lnbtext [_cursel,0];
        };
    };
    _selected
};

VC_SaveLoadData = {
    // returns: array of vehicle classes
    params ["_type",["_saveName",""]]; 
    
    private _saves = profileNamespace getVariable ["SKL_VehChooserSaves",createHashMap];
    if (_type isEqualTo "GET") exitWith {keys _saves};
    
    _saveName = trim _saveName;
    if (_saveName == "") exitWith {};
    
    private _hideDialog = true;
    switch (_type) do {
        case "SAVE": {
            private _vehData = missionNamespace getVariable ["VehicleChooser_vehArray",[]];
            _saves set [_saveName,_vehData];
            profileNamespace setVariable ["SKL_VehChooserSaves",_saves];
        };
        case "LOAD": {
            private _vcListBox = uiNamespace getVariable ["VC_ChoiceListCtrl",controlNull];
            lbClear _vcListBox ;
            private _vehData = _saves getOrDefault [_saveName,[]];
            missionNamespace setVariable ["VehicleChooser_vehArray",+_vehData];
            {
                _x params ["_cfgName","_textures","_anims"];
                private _cfg = configFile >> "cfgVehicles" >> _cfgName;
                private _displayName = getText (_cfg >> "displayName");
                private _index = _vcListBox lbAdd ([_displayName,_cfgName] call VC_DisplayText);
                _vcListBox lbSetData [_index,_cfgName];
            } forEach _vehData; 
        };
        case "DELETE": {
            _saves deleteAt _saveName;
            profileNamespace setVariable ["SKL_VehChooserSaves",_saves];
            _hideDialog = false;
        };
        default {diag_log format ["Error Pos: VC_SaveLoadData: invalid type: %1",_type]};
    };

    if (_hideDialog) then {
        private _display = uiNamespace getVariable ["bis_fnc_arsenal_display", displayNull];
        private _ctrlTemplate = _display displayctrl IDC_RSCDISPLAYARSENAL_TEMPLATE_TEMPLATE;
        _ctrlTemplate ctrlsetfade 1;
        _ctrlTemplate ctrlcommit 0;
        _ctrlTemplate ctrlenable false;

        private _ctrlMouseBlock = _display displayctrl IDC_RSCDISPLAYARSENAL_MOUSEBLOCK;
        _ctrlMouseBlock ctrlenable false;
    };
};

VehicleChooser_Debug = {
    private _garageData = missionnamespace getVariable ["skl_fnc_garage_data",[]];
    if (_garageData isEqualTo []) then {
        if (isNil "VehicleChooser_GarageFN") then {VehicleChooser_GarageFN = BIS_fnc_garage};
        ["Preload"] call VehicleChooser_GarageFN;
        _garageData = missionnamespace getVariable "skl_fnc_garage_data";
        if (isNil "_garageData") then {_garageData = missionnamespace getVariable ["bis_fnc_garage_data",[]];};
    };
    0 setOvercast 0;
    0 setFog 0;
    0 setRain 0;
    forceWeatherChange;
    private _date = date;
    _date set [3,12]; // set to noon
    setDate _date;
    private _allVehicles = [];
    {
        private _subData = _x;
        {
            if (typeName _x == "ARRAY") then {
                {
                    _allVehicles pushBack [(configName _x),[]];
                } forEach _x;
            };
        } forEach _subData;
    } forEach _garageData;

    private _vehData = [_allVehicles] call VehicleChooser_Sort;
    private _names = ["TANK","APC","CAR","HELI","PLANE","STATIC","NAVAL","UAV"];
    if (count _names != ID_COUNT) exitWith {diag_log "ERROR POS: VehicleChooser_Debug name array wrong size"};

    diag_log "--------VehicleChooser_Debug---------";
    {
        diag_log (_names # _forEachIndex);
        {
            diag_log format ["  %1",getText(configFile >> "CfgVehicles" >> _x#0 >> "DisplayName")];
        } forEach _x;
    } forEach _vehData;
    diag_log "------------------------------";

    #define SPACING 15
    if (worldName isEqualTo "Altis") then {
        private _pos =[23122,17278,0];
        if (isNil "TEST_VEHS") then {TEST_VEHS = []} else {{deleteVehicle _x} forEach TEST_VEHS};
        {
            {
                _configName = _x#0;
                private _veh = _configName createVehicle [0,0,200];
                _veh enableSimulation false;
                _veh setPosATL _pos;
                TEST_VEHS pushBack (_veh);
                _pos set [1,_pos#1 + SPACING];
                if (_pos#1 > 18119) then {
                    _pos set [1,17278];
                    _pos set [0,_pos#0 + SPACING];
                };
            } forEach _x;
            _pos set [1,17278];
            _pos set [0,_pos#0 + (SPACING*2)];
        } forEach _vehData;
        { _x addCuratorEditableObjects [TEST_VEHS, true]; } forEach allCurators;
    };
};

private _compileFinal = {
    params [["_var","",[""]], ["_ns",missionNamespace,[missionNamespace]]];
    private _code = _ns getVariable [_var, 0];
    if (typeName _code != typeName {}) exitWith {};
    _codestr = str _code;
    _codestr = _codestr select [1,count _codestr - 2]; // remove begin and end parenthesizes
    _code = compileFinal _codestr;
    _ns setVariable [_var, _code];
};
["VehicleChooser"] call _compileFinal;
["VehicleChooser_Get"] call _compileFinal;
["VehicleChooser_Wait"] call _compileFinal;
["VehicleChooser_Start"] call _compileFinal;
["VehicleChooser_Sort"] call _compileFinal;
["VehicleChooser_Debug"] call _compileFinal;
["VC_ButtonSafe"] call _compileFinal;
["VC_AddVeh"] call _compileFinal;
["VC_RemoveVeh"] call _compileFinal;
["VC_AllVeh"] call _compileFinal;
["VC_DisplayText"] call _compileFinal;
["VC_ToggleClassVeh"] call _compileFinal;
["VC_ViewVeh"] call _compileFinal;
["VC_AllVehClasses"] call _compileFinal;
["VC_NoVehClasses"] call _compileFinal;
["VC_AddVehClasses"] call _compileFinal;
["VC_RemoveVehClasses"] call _compileFinal;
["VC_ToggleVehClasses"] call _compileFinal;
["VC_HideInterface"] call _compileFinal;
["VC_LoadSaveButton"] call _compileFinal;
["VC_GetLoadSaveSelected"] call _compileFinal;
["VC_SaveLoadData"] call _compileFinal;
