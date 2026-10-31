if (!hasInterface) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AusterityClientStarted",false]) exitWith {true};

ITW_CLASH_AusterityClientStarted = true;
ITW_CLASH_AusterityClientVersion = 2;

/*
    The reward HUD: the money tab in the bottom right and the + popups.

    It draws what the server sends (ITW_CLASH_Austerity.sqf) and decides
    nothing. The tab appears on the first answer from the server, so with
    Austerity switched off there is no HUD at all.

    Kills pop up small, just under the crosshair, and the older ones step down
    and fade. A finished job pops up larger, well above the crosshair.
*/
ITW_CLASH_AusterityClientRewardHold = 2.2;
ITW_CLASH_AusterityClientJobHold = 4.5;
ITW_CLASH_AusterityClientStep = 0.034;

ITW_CLASH_AusterityClientCash = 0;
ITW_CLASH_AusterityClientSynced = false;
ITW_CLASH_AusterityClientRoll = 0;
ITW_CLASH_AusterityClientKills = [];

ITW_CLASH_AusterityClient_fnc_FormatNumber = {
    params [["_value",0]];
    private _digits = toArray ((round (abs _value)) toFixed 0);
    private _count = count _digits;
    private _text = "";
    {
        if (_forEachIndex > 0 && {((_count - _forEachIndex) mod 3) == 0}) then {
            _text = _text + ",";
        };
        _text = _text + toString [_x];
    } forEach _digits;
    _text
};

ITW_CLASH_AusterityClient_fnc_Display = {
    uiNamespace getVariable ["ITW_CLASH_RewardHudDisplay",displayNull]
};

ITW_CLASH_AusterityClient_fnc_ShowTab = {
    if (!isNull (call ITW_CLASH_AusterityClient_fnc_Display)) exitWith {true};
    ("ITW_CLASH_REWARD_HUD" call BIS_fnc_rscLayer) cutRsc ["ITW_CLASH_RewardHud","PLAIN",0,false];
    true
};

ITW_CLASH_AusterityClient_fnc_SetBalance = {
    params ["_cash"];
    private _display = call ITW_CLASH_AusterityClient_fnc_Display;
    if (isNull _display) exitWith {false};
    (_display displayCtrl 95513) ctrlSetText ("$" + ([_cash] call ITW_CLASH_AusterityClient_fnc_FormatNumber));
    true
};

// The balance counts up, the delta shows above the tab and its edge lights.
ITW_CLASH_AusterityClient_fnc_Earned = {
    params ["_from","_to","_delta"];
    ITW_CLASH_AusterityClientRoll = ITW_CLASH_AusterityClientRoll + 1;
    [_from,_to,_delta,ITW_CLASH_AusterityClientRoll] spawn {
        params ["_from","_to","_delta","_roll"];
        private _display = call ITW_CLASH_AusterityClient_fnc_Display;
        if (isNull _display) exitWith {};
        private _rule = _display displayCtrl 95511;
        private _deltaCtrl = _display displayCtrl 95514;
        _deltaCtrl ctrlSetText ("+" + ([_delta] call ITW_CLASH_AusterityClient_fnc_FormatNumber));
        _deltaCtrl ctrlSetFade 0;
        _deltaCtrl ctrlCommit 0;
        _rule ctrlSetBackgroundColor [0.96,0.84,0.34,1];

        for "_step" from 1 to 12 do {
            if (_roll != ITW_CLASH_AusterityClientRoll) exitWith {};
            [_from + (_to - _from) * (_step / 12)] call ITW_CLASH_AusterityClient_fnc_SetBalance;
            uiSleep 0.03;
        };
        uiSleep 1.6;
        if (_roll != ITW_CLASH_AusterityClientRoll) exitWith {};
        _rule ctrlSetBackgroundColor [0.79,0.56,0.18,1];
        _deltaCtrl ctrlSetFade 1;
        _deltaCtrl ctrlCommit 0.5;
    };
};

ITW_CLASH_AusterityClient_fnc_Expire = {
    params ["_ctrl","_hold"];
    [_ctrl,_hold] spawn {
        params ["_ctrl","_hold"];
        uiSleep _hold;
        if (isNull _ctrl) exitWith {};
        _ctrl ctrlSetFade 1;
        _ctrl ctrlCommit 0.5;
        uiSleep 0.5;
        ITW_CLASH_AusterityClientKills = ITW_CLASH_AusterityClientKills - [_ctrl];
        ctrlDelete _ctrl;
    };
};

ITW_CLASH_AusterityClient_fnc_KillPopup = {
    params ["_display","_delta","_label"];
    private _big = _delta >= 500;
    private _left = safezoneX + safezoneW * 0.3;
    private _w = safezoneW * 0.4;
    private _h = safezoneH * 0.05;
    private _y = safezoneY + safezoneH * 0.535;

    ITW_CLASH_AusterityClientKills = ITW_CLASH_AusterityClientKills select {!isNull _x};
    while {count ITW_CLASH_AusterityClientKills > 2} do {
        ctrlDelete (ITW_CLASH_AusterityClientKills deleteAt 0);
    };
    private _older = count ITW_CLASH_AusterityClientKills;
    {
        _x ctrlSetPosition [
            _left,
            _y + safezoneH * ITW_CLASH_AusterityClientStep * (_older - _forEachIndex),
            _w,_h
        ];
        _x ctrlSetFade 0.45;
        _x ctrlCommit 0.15;
    } forEach ITW_CLASH_AusterityClientKills;

    private _ctrl = _display ctrlCreate ["ITW_CLASH_RewardPopup",-1];
    _ctrl ctrlSetStructuredText parseText format [
        "<t align='center'><t size='%1' font='PuristaBold' color='#F5D657'>+%2</t> <t size='%3' font='PuristaSemiBold'>%4</t></t>",
        if (_big) then {3.6} else {2.9},
        [_delta] call ITW_CLASH_AusterityClient_fnc_FormatNumber,
        if (_big) then {1.55} else {1.45},
        _label
    ];
    _ctrl ctrlSetPosition [_left,_y + safezoneH * 0.012,_w,_h];
    _ctrl ctrlCommit 0;
    _ctrl ctrlSetPosition [_left,_y,_w,_h];
    _ctrl ctrlCommit 0.12;
    ITW_CLASH_AusterityClientKills pushBack _ctrl;
    [_ctrl,ITW_CLASH_AusterityClientRewardHold] call ITW_CLASH_AusterityClient_fnc_Expire;
};

ITW_CLASH_AusterityClient_fnc_JobPopup = {
    params ["_display","_delta","_label"];
    private _ctrl = _display ctrlCreate ["ITW_CLASH_RewardPopup",-1];
    _ctrl ctrlSetStructuredText parseText format [
        "<t align='center' size='1.55' font='PuristaBold'>%1</t><br/><t align='center' size='4.9' font='PuristaBold' color='#F5D657'>+%2</t>",
        _label,
        [_delta] call ITW_CLASH_AusterityClient_fnc_FormatNumber
    ];
    _ctrl ctrlSetPosition [safezoneX + safezoneW * 0.3,safezoneY + safezoneH * 0.233,safezoneW * 0.4,safezoneH * 0.09];
    _ctrl ctrlCommit 0;
    [_ctrl,ITW_CLASH_AusterityClientJobHold] call ITW_CLASH_AusterityClient_fnc_Expire;
};

ITW_CLASH_AusterityClient_fnc_ReceiveCash = {
    params [["_cash",0],["_delta",0],["_label",""],["_kind","sync"]];
    if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {false};

    private _from = ITW_CLASH_AusterityClientCash;
    ITW_CLASH_AusterityClientCash = _cash max 0;
    ITW_CLASH_AusterityClientSynced = true;
    call ITW_CLASH_AusterityClient_fnc_ShowTab;
    if (_delta <= 0) exitWith {
        [ITW_CLASH_AusterityClientCash] call ITW_CLASH_AusterityClient_fnc_SetBalance
    };

    [_from,ITW_CLASH_AusterityClientCash,_delta] call ITW_CLASH_AusterityClient_fnc_Earned;
    private _display = call ITW_CLASH_AusterityClient_fnc_Display;
    if (isNull _display) exitWith {false};
    // A display name is free text; these would break the structured text.
    private _safe = _label regexReplace ["[<>&]",""];
    if (_kind isEqualTo "job") then {
        [_display,_delta,_safe] call ITW_CLASH_AusterityClient_fnc_JobPopup;
    } else {
        [_display,_delta,_safe] call ITW_CLASH_AusterityClient_fnc_KillPopup;
    };
    true
};

// The server loads well after the player; keep asking until it answers.
[] spawn {
    scriptName "ITW_CLASH_AusterityHudStartup";
    waitUntil {uiSleep 0.1; !isNull player};
    for "_attempt" from 1 to 90 do {
        [player] remoteExecCall ["ITW_CLASH_Austerity_fnc_RequestSync",2];
        uiSleep 2;
        if (ITW_CLASH_AusterityClientSynced) exitWith {};
    };
};

true
