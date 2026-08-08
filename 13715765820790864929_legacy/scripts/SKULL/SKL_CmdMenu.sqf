// Mimics the arma commanding menu, but allows for multiple key presses to select items.  Useful when using a list of numbers
// Parameters:
//    Title: string
//    Menu: array of _text, _keys, _expression
//      _text (string) is the text to place for that item
//      _keys (string) is the key or keys that can be pressed to select the item, multiple items must be pressed in order so "1" and "12" are different
//      _expression (string or code) is executed when item is selected
//    Example: ["Select One", [["Title1", "12", "hint '12'"], ["Title2", "5", "hint '5'"}]]
// if you want a return value:
//    call with [_title,_menu] call compile preprocessFileLineNumbers "scripts/skull/skl_CmdMenu.sqf"
//    call in a scheduled environment (canSuspend)
//    will return -1 if no item selected or suspend not allowed

#include "\a3\ui_f\hpp\definedikcodes.inc"

disableSerialization;
params [["_menuTitle",nil,[""]],
        ["_menuData",nil,[[]]],
        ["_dikExitKeys",[DIK_ESCAPE,DIK_BACK],[[]]]];

if (isNil "_menuTitle" || isNil "_menuData") exitWith {diag_log format ["Error Pos: SKL_CmdMenu invalid arguments: %1",_this]};

// Prevent two menus from appearing
private _oldMenu = uiNamespace getVariable ["SKL_CmdMenu_Background", displayNull];
if (!isNull _oldMenu) then {
    private _oldDisplay = ctrlParent _oldMenu;
    if (!isNull _oldDisplay) then { _oldDisplay closeDisplay 2; };
};

SKL_CmdMenu_Buffer = "";
SKL_CmdMenu_Config = _menuData;
SKL_CmdMenu_ExitKeys = _dikExitKeys;
private _actionContextKeys = actionKeys "ActionContext";
SKL_CmdMenu_OkayKeys = [DIK_RETURN,DIK_NUMPADENTER] + _actionContextKeys;
SKL_CmdMenu_Index = -1;
SKL_CmdMenu_TimeoutActive = false;
SKL_CmdMenu_MultiKeyHandler = scriptNull;

private _display = findDisplay 46;
 
private _width = count _menuTitle;
{
    _x params ["_title", "_keys", "_code"];
    _width = _width max count _title;
} forEach _menuData;
_width = _width + 6;
_width = _width * 0.0035;

// Title background
private _titleBack = _display ctrlCreate ["RscText", -1];
_titleBack ctrlSetPosition [
    0.0145 * safeZoneW + safeZoneX, 
    0.35 * safeZoneH + safeZoneY, 
    _width * safeZoneW, 
    0.025 * safeZoneH
];
_titleBack ctrlSetBackgroundColor [0, 0, 0, 0.7];
_titleBack ctrlCommit 0;

// Title
private _titleCtrl = _display ctrlCreate ["RscStructuredText", -1];
_titleCtrl ctrlSetPosition [
    0.015 * safeZoneW + safeZoneX, 
    0.351 * safeZoneH + safeZoneY, 
    _width * safeZoneW, 
    0.025 * safeZoneH
];
_titleCtrl ctrlCommit 0;
_titleCtrl ctrlSetStructuredText parseText format ["<t size='0.8' align='right' color='#FFFFFF' shadow='1' shadowColor='#000000'>%1</t><br/>", _menuTitle];

// Listbox of menu items
private _listCtrl = _display ctrlCreate ["ctrlListBox", -1];//ctrlListNBox RscListBox ctrlListBox RscDisplayGarage_Filter
_listCtrl ctrlSetPosition [
    0.0145 * safeZoneW + safeZoneX, 
    0.10 * safeZoneH + safeZoneY, 
    _width * safeZoneW, 
    0.25 * safeZoneH
];
_listCtrl ctrlSetFont "RobotoCondensed";
_listCtrl ctrlSetFontHeight 0.03;
_listCtrl ctrlCommit 0;

// build the menu
{
    _x params ["_title", "_keys", "_code"];
    private _idx = _listCtrl lbAdd format ["%1  %2", _keys, _title];
    _listCtrl lbSetValue [_idx, _forEachIndex];
} forEach _menuData;

// Focus the first item by default
_listCtrl lbSetCurSel 0;
ctrlSetFocus _listCtrl;

uiNamespace setVariable ["SKL_CmdMenu_Controls",[_listCtrl,_titleBack,_titleCtrl]];

SKL_CmdMenu_DoneFunction = 
{
    params ["_display"];
    _display displayRemoveEventHandler ["KeyDown", SKL_CmdMenu_EH];
    {ctrlDelete _x} forEach (uiNamespace getVariable ["SKL_CmdMenu_Controls", []]);
    uiNamespace setVariable ["SKL_CmdMenu_Controls",nil];
    SKL_CmdMenu_EH = nil;
    SKL_CmdMenu_MouseEH = nil;
    SKL_CmdMenu_ExitKeys = nil;
    SKL_CmdMenu_OkayKeys = nil;
    SKL_CmdMenu_Buffer = nil;
    SKL_CmdMenu_Config = nil;
    SKL_CmdMenu_MultiKeyHandler = nil;
    SKL_CmdMenu_SelectIndex = nil;
    SKL_CmdMenu_DoneFunction = nil;
};

SKL_CmdMenu_SelectIndex = 
{
    params ["_display", "_index"];
    if (_index < 0 || _index >= count SKL_CmdMenu_Config) exitWith {};
    (SKL_CmdMenu_Config select _index) params ["_title", "_keys", "_expression"];
    SKL_CmdMenu_Index = _index;
    if (typeName _expression == "CODE") then {
        call _expression;
    } else {
        call compile _expression;
    };
    [_display] call SKL_CmdMenu_DoneFunction;
};

SKL_CmdMenu_MouseEH = _display displayAddEventHandler ["MouseZChanged", {
    params ["_display", "_wheelChange"];
    private _listCtrl = (uiNamespace getVariable ["SKL_CmdMenu_Controls", [controlNull]])#0;
    if (isNull _listCtrl) exitWith {};
    
    private _curSel = lbCurSel _listCtrl;
    private _newSel = _curSel + (if (_wheelChange < 0) then {1} else {-1});
    _newSel = 0 max _newSel min ((lbSize _listCtrl) - 1);
    
    _listCtrl lbSetCurSel _newSel;
    true;
}];

// Handle if middle mouse is the users selection method
if (132610 in _actionContextKeys) then {
    _listCtrl ctrlAddEventHandler ["MouseButtonDown", {
        params ["_control", "_button", "_xPos", "_yPos", "_shift", "_ctrl", "_alt"];
        if (_button == 2) then { // button 2 is middle mouse click
            private _curSel = lbCurSel _control;
            if (_curSel != -1) then {
                private _display = ctrlParent _control;
                private _actualIndex = _control lbValue _curSel;
                [_display, _actualIndex] call SKL_CmdMenu_SelectIndex;
            };
        };
    }];
};

_listCtrl ctrlAddEventHandler ["LBDblClick", {
    params ["_control", "_selectedIndex"];
    private _display = ctrlParent _control;
    private _actualIndex = _control lbValue _selectedIndex;
    [_display, _actualIndex] call SKL_CmdMenu_SelectIndex;
}];

SKL_CmdMenu_EH = _display displayAddEventHandler ["KeyDown", {
    params ["_display", "_key", "_shift", "_ctrl", "_alt"];
    // event handlers do not return the value in an exitWith, so use a call {  } with breakTo to get it working
    scopeName "keyHandled";
    call {
        if (!isNull SKL_CmdMenu_MultiKeyHandler) then {terminate SKL_CmdMenu_MultiKeyHandler};

        if (_key in SKL_CmdMenu_ExitKeys) then {
            [_display] call SKL_CmdMenu_DoneFunction;
            breakTo "keyHandled";
        };
        
        // Handle selections triggered by Action keys
        if (_key in SKL_CmdMenu_OkayKeys) then {
            private _listCtrl = (uiNamespace getVariable ["SKL_CmdMenu_Controls", [controlNull]])#0;
            if (!isNull _listCtrl) then {
                private _curSel = lbCurSel _listCtrl;
                if (_curSel != -1) then {
                    private _actualIndex = _listCtrl lbValue _curSel;
                    [_display, _actualIndex] call SKL_CmdMenu_SelectIndex;
                };
            };
            breakTo "keyHandled";
        };
        
        private _char = keyName _key;
        _char = _char select [1, (count _char) - 2];
        
        SKL_CmdMenu_Buffer = SKL_CmdMenu_Buffer + _char;
        
        private _exactMatchIndex = -1;
        private _hasPartialMatches = false;
        private _bufferCnt = count SKL_CmdMenu_Buffer;
        {
            _x params ["_title", "_keys", "_expression"];
            if (_keys == SKL_CmdMenu_Buffer) then {
                _exactMatchIndex = _forEachIndex;
            };
            if (_keys != SKL_CmdMenu_Buffer && {(_keys select [0, _bufferCnt]) == SKL_CmdMenu_Buffer}) then {
                _hasPartialMatches = true;
            };
        } forEach SKL_CmdMenu_Config;
        
        // Exact match, no overlapping choices
        if (_exactMatchIndex != -1 && !_hasPartialMatches) then {
            [_display, _exactMatchIndex] call SKL_CmdMenu_SelectIndex;
            breakTo "keyHandled";
        };
        
        // Exact match, longer choices are possible
        if (_exactMatchIndex != -1 && _hasPartialMatches) then {
            SKL_CmdMenu_MultiKeyHandler = [_display, _exactMatchIndex] spawn {
                params ["_display", "_exactMatchIndex"];
                private _currentBuffer = SKL_CmdMenu_Buffer;
                sleep 1.0;
                if (!isNull _display && {SKL_CmdMenu_Buffer == _currentBuffer}) then {
                    [_display, _exactMatchIndex] call SKL_CmdMenu_SelectIndex;
                };
            };
            breakTo "keyHandled";
        };
            
        // reset buffer if random key pressed
        if (_exactMatchIndex == -1 && !_hasPartialMatches) then {
            SKL_CmdMenu_Buffer = "";
            terminate SKL_CmdMenu_MultiKeyHandler;
            breakTo "keyHandled";
        };
    };
    true;
}];

private _return = -1;
if (canSuspend) then {
    waitUntil {isNil "SKL_CmdMenu_EH"};
    _return = SKL_CmdMenu_Index;
    SKL_CmdMenu_Index = nil;
};
_return;
