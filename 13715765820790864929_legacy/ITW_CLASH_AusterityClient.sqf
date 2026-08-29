if (!hasInterface) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_AusterityClientStarted",false]) exitWith {true};

ITW_CLASH_AusterityClientStarted = true;
ITW_CLASH_AusterityClientVersion = 1;
ITW_CLASH_AusterityCashLocal = 0;
ITW_CLASH_AusterityCashSynced = false;

ITW_CLASH_AusterityClient_fnc_FormatCash = {
    params [["_cash",0]];
    private _digits = toArray str (round (_cash max 0));
    private _count = count _digits;
    private _text = "";

    {
        if (_forEachIndex > 0 && {
            ((_count - _forEachIndex) mod 3) == 0
        }) then {
            _text = _text + ",";
        };
        _text = _text + toString [_x];
    } forEach _digits;

    "$" + _text
};

ITW_CLASH_AusterityClient_fnc_RefreshHud = {
    private _display = uiNamespace getVariable [
        "ITW_CLASH_AusterityHudDisplay",
        displayNull
    ];
    if (isNull _display) exitWith {false};

    private _cash = missionNamespace getVariable [
        "ITW_CLASH_AusterityCashLocal",
        0
    ];
    (_display displayCtrl 95503) ctrlSetText (
        [_cash] call ITW_CLASH_AusterityClient_fnc_FormatCash
    );
    true
};

ITW_CLASH_AusterityClient_fnc_ReceiveCash = {
    params [["_cash",0],["_delta",0],["_reason","sync"]];
    if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {false};

    missionNamespace setVariable [
        "ITW_CLASH_AusterityCashLocal",
        _cash max 0
    ];
    missionNamespace setVariable [
        "ITW_CLASH_AusterityCashSynced",
        true
    ];

    call ITW_CLASH_AusterityClient_fnc_RefreshHud;

    if (_delta > 0) then {
        systemChat format [
            "HAL TASK COMPLETE  +%1  |  BALANCE %2",
            [_delta] call ITW_CLASH_AusterityClient_fnc_FormatCash,
            [_cash] call ITW_CLASH_AusterityClient_fnc_FormatCash
        ];
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_AusterityHudStartup";
    waitUntil {uiSleep 0.1; !isNull player};

    private _layer = "ITW_CLASH_AUSTERITY_HUD" call BIS_fnc_rscLayer;
    _layer cutRsc ["ITW_CLASH_AusterityHud","PLAIN",0,false];

    for "_attempt" from 1 to 5 do {
        [player] remoteExecCall [
            "ITW_CLASH_Austerity_fnc_RequestSync",
            2
        ];
        uiSleep 1;
        if (missionNamespace getVariable [
            "ITW_CLASH_AusterityCashSynced",
            false
        ]) exitWith {};
    };
};

true
