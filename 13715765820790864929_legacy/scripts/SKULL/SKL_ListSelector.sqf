/*
    Description: Creates a listbox requester
    Input: Array of strings 
    Optional Inputs:
        Title Text (default " Select One"
        Okay Button Text (default "" ==> localized "Okay" or just "Okay")
        Cancel Button Text  (default "" ==> localized "Cancel" or just "Cancel")
        Middle Button Text  (default "", if != "" then a middle button will be added that acts as a 2nd okay button
        Text Input: true to show a text input box
        Display:    the display to show the seletor on. Defaults to main game display
    Returns: 
      Scalar : if _textInput is false
        'okay' clicked:   Index number 0 based
        'cancel' clicked: -1
        'middle' clicked: all other negative numbers where button clicked = -(_return+2)
      String or Scalar: if _textInput if true
        'okay' clicked:   text entered
        'cancel' clicked: empty string
        'middle' clicked: all other negative numbers where button clicked = -(_return+2)
*/
#include "\a3\ui_f\hpp\definedikcodes.inc"

params [["_stringArray", []],["_titleText"," Select One"],["_okayText",""],["_cancelText",""],["_middleText",""],["_textInput",false],["_topmostDisplay",displayNull]];

#define IDC_LIST_BOX      101
#define IDC_BUTTON_OKAY   200
#define IDC_BUTTON_CANCEL 201
#define IDC_BUTTON_MIDDLE 202
#define IDC_TEXT_INPUT    203

#define LS_TOP      0.05
#define LS_LEFT     0.25
#define LS_WIDTH    0.50
#define LS_HEIGHT   0.90
#define LS_MARGIN   0.01
#define LS_TITLE_H  0.05
#define LS_BTN_W    0.14
#define LS_BTN_H    0.04
#define LS_TXT_H    0.03

disableSerialization;

// IDD 999 is the vanilla engine standard for safe runtime displays
if (isNull _topmostDisplay) then {_topmostDisplay = findDisplay 46};
private _display = _topmostDisplay createDisplay "RscDisplayEmpty";
if (isNull _display) exitWith { diag_log "Error Pos: SKL_ListSelector: Display failed to initialize."; -1 };

// we want to block keys from getting to the game, but allow those used by the listbox
_display displayAddEventHandler ["KeyDown", {
    params ["_display", "_keyCode", "_shift", "_ctrl", "_alt"];
    private _return = true;
    private _listbox = _display displayCtrl IDC_LIST_BOX;   
    private _textBox = _display displayCtrl IDC_TEXT_INPUT; 
    if (focusedCtrl _display == _listbox) then {
        switch (_keyCode) do {
            case DIK_RETURN;
            case DIK_NUMPADENTER;
            case DIK_ESCAPE;
            case DIK_TAB;
            case DIK_UP;
            case DIK_DOWN: {_return = false};
        };
    } else {
        if (focusedCtrl _display == _textBox) then {
            switch (_keyCode) do {
                case DIK_RETURN;
                case DIK_NUMPADENTER;
                case DIK_ESCAPE;
                case DIK_LEFT;
                case DIK_RIGHT;
                case DIK_BACKSPACE;
                case DIK_DELETE;
                case DIK_HOME;
                case DIK_END: {_return = false};
            };
        };
    };
    _return
}]; 

private _background = _display ctrlCreate ["RscText", -1];
_background ctrlSetPosition [LS_LEFT, LS_TOP, LS_WIDTH, LS_HEIGHT]; 
_background ctrlSetBackgroundColor [0, 0, 0, 0.8]; 
_background ctrlCommit 0;

private _title = _display ctrlCreate ["RscText", -1];
_title ctrlSetPosition [LS_LEFT, LS_TOP - LS_TITLE_H, LS_WIDTH, LS_TITLE_H];
_title ctrlSetBackgroundColor [0.7, 0.5, 0.1, 1]; 
_title ctrlSetText _titleText;
_title ctrlCommit 0;

private _listbox = _display ctrlCreate ["RscListBox", IDC_LIST_BOX];
private _hgtMargins = if (_textInput) then {7} else {4};
_listbox ctrlSetPosition [LS_LEFT + LS_MARGIN, LS_TOP + (2*LS_MARGIN), LS_WIDTH - (2*LS_MARGIN), LS_HEIGHT - (_hgtMargins*LS_MARGIN)];
_listbox ctrlCommit 0;
{
    _listbox lbAdd _x;
} forEach _stringArray;
if (_textInput) then {
    _listbox ctrlAddEventHandler ["LBSelChanged", {
        params ["_control", "_selectedIndex"];
        private _textBox = (ctrlParent _control) displayCtrl IDC_TEXT_INPUT;
        _textBox ctrlSetText (_control lbText _selectedIndex);
    }];
};
_listbox lbSetCurSel 0;

private _textBox = _display ctrlCreate ["RscEdit", IDC_TEXT_INPUT];
_textBox ctrlSetPosition [LS_LEFT + LS_MARGIN, LS_TOP + LS_HEIGHT - (4*LS_MARGIN), LS_WIDTH - (2*LS_MARGIN), LS_TXT_H];
_textBox ctrlSetText "";
_textBox ctrlShow _textInput;
_textBox ctrlCommit 0;

if (_okayText == "") then {_okayText = (if (isLocalized "STR_SKL_COMMON_Okay") then {localize "STR_SKL_COMMON_Okay"} else {"Okay"})};
private _btnokay = _display ctrlCreate ["RscButtonMenuOK", IDC_BUTTON_OKAY];
_btnokay ctrlSetPosition [LS_LEFT + LS_WIDTH - LS_BTN_W, LS_TOP + LS_HEIGHT + (2*LS_MARGIN), LS_BTN_W, LS_BTN_H];
_btnokay ctrlSetText _okayText;
_btnokay ctrlCommit 0;
_btnokay ctrlAddEventHandler ["ButtonClick", {
    params ["_ctrl"];
    private _display = ctrlParent _ctrl;
    private _listbox = _display displayCtrl IDC_LIST_BOX;   
    private _textBox = _display displayCtrl IDC_TEXT_INPUT; 
    player setVariable ["SKL_menuSelectedIndex", lbCurSel _listbox];
    player setVariable ["SKL_menuSelectedText",  ctrlText _textBox];
}];

if (_middleText != "") then {
    private _btnMiddle = _display ctrlCreate ["RscButtonMenuOK", IDC_BUTTON_MIDDLE];
    _btnMiddle ctrlSetPosition [LS_LEFT + (LS_WIDTH - LS_BTN_W)/2, LS_TOP + LS_HEIGHT + (2*LS_MARGIN), LS_BTN_W, LS_BTN_H];
    _btnMiddle ctrlSetText _middleText;
    _btnMiddle ctrlCommit 0;
    _btnMiddle ctrlAddEventHandler ["ButtonClick", {
        params ["_ctrl"];
        private _display = ctrlParent _ctrl;
        private _listbox = _display displayCtrl IDC_LIST_BOX;    
        player setVariable ["SKL_menuSelectedIndex", -(lbCurSel _listbox + 2)];
    }];
};

if (_cancelText == "") then {_cancelText = (if (isLocalized "STR_SKL_COMMON_Cancel") then {localize "STR_SKL_COMMON_Cancel"} else {"Cancel"})};
private _btnCancel = _display ctrlCreate ["RscButtonMenuCancel", IDC_BUTTON_CANCEL];
_btnCancel ctrlSetPosition [LS_LEFT, LS_TOP + LS_HEIGHT + (2*LS_MARGIN), LS_BTN_W, LS_BTN_H];
_btnCancel ctrlSetText _cancelText;
_btnCancel ctrlCommit 0;
_btnCancel ctrlAddEventHandler ["ButtonClick", {
    player setVariable ["SKL_menuSelectedIndex", -1];
}];

if (_textInput) then {ctrlSetFocus _textBox} else {ctrlSetFocus _listbox};

player setVariable ["SKL_menuSelectedIndex", nil];

waitUntil { !isNil {player getVariable "SKL_menuSelectedIndex"} || isNull _display };

private _resultIndex = player getVariable ["SKL_menuSelectedIndex", -1];
if (_textInput) then {
    private _resultText = player getVariable ["SKL_menuSelectedText",""];
    if (_resultText != "") then {_resultIndex = _resultText};
};
player setVariable ["SKL_menuSelectedIndex", nil];
player setVariable ["SKL_menuSelectedText", nil];

_display closeDisplay 1; 

_resultIndex // Returns 0-based index or -1 or negative index or string
