#include "defines.hpp"

// Including Instructions:
// To include dlc selection is a mission do the following:
// 1. add a symlink of the skullscripts\Dlcs directory to \scripts\Dlcs in your mission
// 2. add to the top of the description.ext:  #include "scripts\Dlcs\display.hpp"
//    Note that this requires a few includes.  If you get errors add these to the description.ext
//        #include "\a3\ui_f\hpp\definecommongrids.inc"
//        #include "\a3\ui_f\hpp\defineResincl.inc"
//        import RscText;
//        import RscButton;
//        import RscFrame;
//        import RscListBox;
// 3. In preInit.sqf add this line:
//      isNil {call compile preprocessFileLineNumbers "scripts\Dlcs\DlcSelect.sqf";  }; 
// 4. To have the player select dlcs, call DlcSelect on the server:
//    You can supply the player who should choose (default host)

DlcSelect = {
    params [["_selectedDlcIds",[]],["_defaultDlcIds",[]],["_playerToChoose",objNull],["_dlcType","vehicle"]]; 
    //
    // _selectedDlcIds:   the dlcs that will be selected at the start (default [] will use defaultsDlcs)
    // _defaultDlcIds:    the default dlcs that should be enabled
    //_playerToChoose:    which player will choose the dlc, if objNull, then it will be host or a
    //                    (call BIS_fnc_listPlayers)#0;
    //_dlcType:           either "vehicle", "house", or "weapon"
    //   returns an array of DLC ids [id0,id1,id2,id3,id4,id5,..]
    
    // call on server only
    if (! isServer) exitWith { diag_log "Error: DlcSelect called from non-server"; };
    
    missionNamespace setVariable ["DLC_SELECT_DONE", false, true];
    if (_defaultDlcIds isEqualTo []) then {_defaultDlcIds = ["Bohemia Interactive","Expansion","Tank","Orange","ORANGE","Heli"]};
    if (_selectedDlcIds isEqualTo []) then {_selectedDlcIds = _defaultDlcIds};
    
    // server need to report all the available dlc to the clients since the client might have more dlc/maps
    DlcsAllowed = [_dlcType] call DlcSelection_CollectDlcs;
    
    private _selectedDlcs = [];
    private _defaultDlcs = [];
    {
        _x params ["_dlcName","_dlcData"];
        {
            if (_x in _dlcData) exitWith {_selectedDlcs pushBackUnique _dlcName};
        } forEach _selectedDlcIds;
        {
            if (_x in _dlcData) exitWith {_defaultDlcs pushBackUnique _dlcName};
        } forEach _defaultDlcIds;
    } forEach DlcsAllowed;   
 
    if (count DlcsAllowed < 2) then {
        _selectedDlcs = ["Arma 3"];
    } else {
        missionNamespace setVariable ["DLC_SELECTED",_selectedDlcs,true];
        missionNamespace setVariable ["DLC_DEFAULT",_defaultDlcs,true];
        
        publicVariable "DlcsAllowed";
            
        if (isNull _playerToChoose) then {
            if (isDedicated) then {
                // if using a dedicated server, use a the first player to choose dlc
                waitUntil {count (call BIS_fnc_listPlayers) > 0};
                private _player = (call BIS_fnc_listPlayers)#0;
                [] remoteExec ["DlcSelection_Wait",-(owner _player),true];
                [] remoteExec ["DlcSelection_Start",_player];
            } else {
                // hosted server, so just let the host choose dlc
                [] remoteExec ["DlcSelection_Wait",-2,true];
                [] call DlcSelection_Start;
            };
        } else {
            [] remoteExec ["DlcSelection_Wait",-(owner _playerToChoose),true];
            [] remoteExec ["DlcSelection_Start",_playerToChoose];
        };
        waitUntil {sleep 0.5; missionNamespace getVariable ["DLC_SELECT_DONE",false]};
            
        _selectedDlcs = missionNamespace getVariable ["DLC_SELECTED",[]];
    };
    _return = [];
    {
        _x params ["_dlcName","_dlcData"];
        if (_dlcName in _selectedDlcs) then {
            _return append _dlcData;
        };
    } forEach DlcsAllowed;
    _return
};

DlcSelection_Wait = {
    // Can be called on extra clients while other player selects dlc      
    waitUntil {sleep 1; missionNamespace getVariable ["DLC_SELECT_DONE",false]};
};

DlcSelection_Start = {
    // Called on one client - will choose dlc
           
    waitUntil {!isNil "DlcsAllowed"}; // wait until the host has sent the list of allowed dlc
        
    waitUntil {!isNull findDisplay 46};
    createDialog "DlcSelectionScreen";
    waitUntil {!isNull findDisplay DLC_SELECTION_IDD};

    // save the list controls so we can easily grab them later
    private _display = findDisplay DLC_SELECTION_IDD;
    private _listCtrl = _display displayCtrl DLC_SELECTOR_LIST;
    uiNamespace setVariable ["DlcListCtrl",_listCtrl];
        
    ctrlSetFocus (_display displayCtrl DLC_SELECTOR_OKAY);
    
    if (!(isNil "DLC_SELECTION_INFO_TEXT") && {!(DLC_SELECTION_INFO_TEXT isEqualTo "")}) then {
        (_display displayCtrl DLC_SELECTOR_INFO) ctrlSetText DLC_SELECTION_INFO_TEXT;
    };
    if (!(isNil "DLC_SELECTION_TITLE_TEXT") && {!(DLC_SELECTION_TITLE_TEXT isEqualTo "")}) then {
        (_display displayCtrl DLC_SELECTOR_TITLE) ctrlSetText DLC_SELECTION_TITLE_TEXT;
    };
    
    [] call DlcSelection_PopulateListBox;
};

DlcSelection_PopulateListBox = {
    private _listCtrl = uiNamespace getVariable "DlcListCtrl";
    private _selectedDlcs = missionNamespace getVariable "DLC_SELECTED";
    lbClear _listCtrl;
    {
        _x params ["_dlcName","_dlcData"];
        _index = _listCtrl lbAdd _dlcName;
        _listCtrl lbSetSelected [_index,_dlcName in _selectedDlcs];
    } forEach DlcsAllowed;
    
    _listCtrl lbSortBy ["TEXT"];
};

DlcSelection_ListClicked = {
    private _listCtrl = uiNamespace getVariable "DlcListCtrl";
    private _choosenIndexs = lbSelection _listCtrl;
    private _choosenDlcs = [];
    {
        _choosenDlcs pushBack (_listCtrl lbText _x);
    } forEach _choosenIndexs;
    missionNamespace setVariable ["DLC_SELECTED", _choosenDlcs];
};

DlcSelection_ResetClick = {
    private _listCtrl = uiNamespace getVariable "DlcListCtrl";
    private _defaultDlcs = missionNamespace getVariable "DLC_DEFAULT";
    for "_i" from 0 to (lbSize _listCtrl - 1) do {
        private _name = _listCtrl lbText _i;
        _listCtrl lbSetSelected [_i, _name in _defaultDlcs];
    };
    missionNamespace setVariable ["DLC_SELECTED",_defaultDlcs];
};

DlcSelection_Complete = {
    private _selectedDlcs = missionNamespace getVariable "DLC_SELECTED";
    missionNamespace setVariable ["DLC_SELECTED", _selectedDlcs, true];
    missionNamespace setVariable ["DLC_SELECT_DONE", true, true];    
    uiNamespace setVariable ["DlcListCtrl",controlNull];
};

DlcSelection_CollectDlcs = {
    params [["_dlcType","vehicle"]]; // should be "vehicle" or "house" or "weapon"
    private _allDLCs = [];
    private _allDlcData = [];
    private _types = ["Car","Tank", "APC", "Helicopter"];
    private _cfgFile = configFile >> "CfgVehicles";
    switch (_dlcType) do {
        case "house": {_types = ["HouseBase"]};
        case "weapon": {
            _types = ["Throw","PistolCore","RifleCore"];
            _cfgFile = configFile >> "CfgWeapons";
        }; 
    };
    private _ignoredDLC = ["aow","@Task Force Arrowhead Radio (BETA!!!)","@CBA_A3"];
    {
        private _cfg =  _x;
        private _cfgName = configName _x;
        private _found = false;
        {if (_cfgName isKindOf [_x,_cfgFile]) exitWith {_found = true}} forEach _types;
        if (_found) then {
            // only opfor, blufor, independent are considered for vehicles
            if (_dlcType != "vehicle" || {getNumber (_cfg >> "side") < 3}) then {
                private _dlcId = configSourceMod _cfg;
                if !(_dlcId in _allDLCs || {_dlcId in _ignoredDLC}) then {
                    _allDLCs pushBack _dlcId;
                    private _modName = configSourceMod _cfg;
                    switch (toLowerANSI _modName) do {
                        case "expansion"; //apex
                        case "mark";
                        case "tank";
                        case "heli";
                        case "orange";
                        case "argo";   // malden
                        case "kart";
                        case "tacops";
                        case "":      {_modName = "Arma 3"};
                        case "enoch": {_modName = "Contact/Livonia"};
                        case "vn":    {_modName = "SOG Prairie Fire"};
                        case "csla":  {_modName = "CSLA Iron Curtain"};
                        case "ws":    {_modName = "Western Sahara"};
                        case "gm":    {_modName = "Global Mobilization"};
                        case "spe":   {_modName = "Spearhead 1944"};
                    };                    
                    private _index = _allDlcData findIf {_modName == (_x#0)};
                    if (_index < 0) then {
                        _allDlcData pushBack [_modName,[_dlcId]];
                    } else {
                        private _item = _allDlcData#_index;
                        (_item#1) pushBack _dlcId;
                    };
                };
            };
        };
    } forEach ("(getNumber (_x >> 'scope') == 2)" configClasses _cfgFile);
    _allDlcData;
};

DlcSelection_SetInfo = {
    params ["_text",["_title",""]];
    if !(_text isEqualTo "") then {
        DLC_SELECTION_INFO_TEXT = _text;
        publicVariable "DLC_SELECTION_INFO_TEXT";
    };
    if !(_title isEqualTo "") then {
        DLC_SELECTION_TITLE_TEXT = _title;
        publicVariable "DLC_SELECTION_TITLE_TEXT";
    };
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

["DlcSelect"] call SKL_fnc_CompileFinal;
["DlcSelection_Wait"] call SKL_fnc_CompileFinal;
["DlcSelection_Start"] call SKL_fnc_CompileFinal;
["DlcSelection_PopulateListBox"] call SKL_fnc_CompileFinal;
["DlcSelection_ListClicked"] call SKL_fnc_CompileFinal;
["DlcSelection_ResetClick"] call SKL_fnc_CompileFinal;
["DlcSelection_Complete"] call SKL_fnc_CompileFinal;
["DlcSelection_CollectDlcs"] call SKL_fnc_CompileFinal;
["DlcSelection_SetInfo"] call SKL_fnc_CompileFinal;