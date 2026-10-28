if (!hasInterface) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestMenuStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestMenuStarted = true;
ITW_CLASH_PlayerTaskRequestMenuVersion = 3;

ITW_CLASH_PlayerTaskRequestMenu_fnc_ReceiveResponse = {
    params ["_status","_message",["_jobId",""]];
    if (
        isRemoteExecuted
        && {remoteExecutedOwner != 2}
    ) exitWith {false};
    if !(_status isEqualType "" && {_message isEqualType ""}) exitWith {false};

    systemChat format ["C.L.A.S.H.: %1",_message];
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_Request = {
    params ["_requestType"];
    if !(_requestType isEqualType "") exitWith {false};
    if (player != leader group player) exitWith {
        systemChat "C.L.A.S.H.: Only the group leader can request tasks.";
        false
    };
    if !(missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsReady",false]) exitWith {
        systemChat "C.L.A.S.H.: Task requests are not ready yet.";
        false
    };

    [player,toUpperANSI _requestType] remoteExecCall [
        "ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote",2
    ];
    showCommandingMenu "";
    true
};

// Commanding-menu submenus must be linked through the submenuName field.
// Opening a second #USER menu from the parent entry's expression races the
// engine closing the parent after CMD_EXECUTE and causes the new menu to flash
// open and immediately disappear. Build the submenu before the parent is shown
// and let the command-menu engine own the transition instead.
ITW_CLASH_PlayerTaskRequestMenu_fnc_BuildStrike = {
    ITW_CLASH_PlayerTaskRequestStrikeMenu = [
        ["STRIKE",false],
        [
            "Soft Targets",
            [2],"",-5,
            [["expression","['STRIKE_SOFT'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Light Armour",
            [3],"",-5,
            [["expression","['STRIKE_LIGHT_ARMOR'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Heavy Armour",
            [4],"",-5,
            [["expression","['STRIKE_HEAVY_ARMOR'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Back",
            [0],"",-4,
            [],
            "1","1"
        ]
    ];
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenStrike = {
    call ITW_CLASH_PlayerTaskRequestMenu_fnc_BuildStrike;
    showCommandingMenu "#USER:ITW_CLASH_PlayerTaskRequestStrikeMenu";
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenMenu = {
    private _active = false;
    if (!isNil "ITW_CLASH_PlayerTasks_fnc_HasActiveJob") then {
        _active = [group player] call ITW_CLASH_PlayerTasks_fnc_HasActiveJob;
    } else {
        _active = (group player) getVariable ["ITW_CLASH_PlayerHasActiveHALJob",false];
    };

    call ITW_CLASH_PlayerTaskRequestMenu_fnc_BuildStrike;

    ITW_CLASH_PlayerTaskRequestMenu = [
        ["C.L.A.S.H. REQUEST TASK",false],
        [
            "Strike >",
            [2],"#USER:ITW_CLASH_PlayerTaskRequestStrikeMenu",-5,
            [],
            "1","1"
        ],
        [
            "Recon",
            [3],"",-5,
            [["expression","['RECON'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Artillery",
            [4],"",-5,
            [["expression","['ARTILLERY'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Transport",
            [5],"",-5,
            [["expression","['TRANSPORT'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            if (_active) then {"[ACTIVE] Cancel Current Job"} else {"Cancel Current Job"},
            [6],"",-5,
            [["expression","[] call ITW_CLASH_PlayerEmployment_fnc_CancelCurrentJob"]],
            "1","1"
        ],
        [
            "Close",
            [0],"",-3,
            [["expression","showCommandingMenu ''"]],
            "1","1"
        ]
    ];
    showCommandingMenu "#USER:ITW_CLASH_PlayerTaskRequestMenu";
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_Install = {
    params ["_unit"];
    if (isNull _unit || {!local _unit}) exitWith {false};
    if (_unit getVariable ["ITW_CLASH_PlayerTaskRequestEntryInstalled",false]) exitWith {true};

    private _actionId = _unit addAction [
        "<t color='#FFD36A'>[C.L.A.S.H.] Request Task</t>",
        {[] call ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenMenu},
        nil,
        -4.1,
        false,
        true,
        "",
        "_this isEqualTo _target",
        0.01
    ];
    _unit setVariable ["ITW_CLASH_PlayerTaskRequestActionId",_actionId];

    private _commId = [
        _unit,"ITW_CLASH_HALTaskRequest"
    ] call BIS_fnc_addCommMenuItem;
    _unit setVariable ["ITW_CLASH_PlayerTaskRequestCommId",_commId];

    if (
        isClass (configFile >> "CfgPatches" >> "ace_main")
        && {!isNil "ace_interact_menu_fnc_createAction"}
        && {!isNil "ace_interact_menu_fnc_addActionToObject"}
    ) then {
        private _aceAction = [
            "ITW_CLASH_HALTaskRequest",
            "Request Task",
            "",
            {[] call ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenMenu},
            {true},
            {}
        ] call ace_interact_menu_fnc_createAction;
        [
            _unit,1,["ACE_SelfActions"],_aceAction
        ] call ace_interact_menu_fnc_addActionToObject;
    };

    _unit setVariable ["ITW_CLASH_PlayerTaskRequestEntryInstalled",true];
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerTaskRequestMenuInstaller";
    private _installedFor = objNull;
    while {true} do {
        if (
            !isNull player
            && {local player}
            && {player != _installedFor}
        ) then {
            [player] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Install;
            _installedFor = player;
            diag_log format [
                "CLASH BOOT | player-task-request-menu-ready | version=%1 separateMenu=true strikeSubmenu=true nativeSubmenuLink=true reconGeneric=true artillery=true transport=true",
                ITW_CLASH_PlayerTaskRequestMenuVersion
            ];
        };
        uiSleep 1;
    };
};

true
