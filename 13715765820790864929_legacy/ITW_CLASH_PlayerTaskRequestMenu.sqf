if (!hasInterface) exitWith {true};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestMenuStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestMenuStarted = true;
ITW_CLASH_PlayerTaskRequestMenuVersion = 1;

ITW_CLASH_PlayerTaskRequestMenu_fnc_ReceiveResponse = {
    params ["_status","_message",["_jobId",""]];
    if (
        isRemoteExecuted
        && {remoteExecutedOwner != 2}
    ) exitWith {false};
    if !(_status isEqualType "" && {_message isEqualType ""}) exitWith {false};

    private _prefix = switch (_status) do {
        case "MATCHED": {"TASK ASSIGNED"};
        case "NO_CAPABILITY": {"NO CAPABILITY"};
        case "NO_TASK": {"NO TASK"};
        case "BUSY": {"BUSY"};
        case "AUTHORITY_HOLD": {"UNAVAILABLE"};
        case "COOLDOWN": {"WAIT"};
        case "UNAVAILABLE": {"UNAVAILABLE"};
        default {"REQUEST"};
    };
    systemChat format ["C.L.A.S.H. HAL %1: %2",_prefix,_message];
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_Request = {
    params ["_requestType"];
    if !(_requestType isEqualType "") exitWith {false};
    if (player != leader group player) exitWith {
        systemChat "C.L.A.S.H. HAL Request: only the group leader can request a task.";
        false
    };
    if !(missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestsReady",false]) exitWith {
        systemChat "C.L.A.S.H. HAL Request: task request router is not ready.";
        false
    };

    [player,toUpperANSI _requestType] remoteExecCall [
        "ITW_CLASH_PlayerTaskRequests_fnc_HandleRemote",2
    ];
    showCommandingMenu "";
    true
};

ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenStrike = {
    ITW_CLASH_PlayerTaskRequestStrikeMenu = [
        ["HAL REQUEST - STRIKE",false],
        [
            "Soft Targets",
            [2],"",-5,
            [["expression","['STRIKE_SOFT'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Light Armor",
            [3],"",-5,
            [["expression","['STRIKE_LIGHT_ARMOR'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Heavy Armor",
            [4],"",-5,
            [["expression","['STRIKE_HEAVY_ARMOR'] call ITW_CLASH_PlayerTaskRequestMenu_fnc_Request"]],
            "1","1"
        ],
        [
            "Back",
            [0],"",-3,
            [["expression","[] call ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenMenu"]],
            "1","1"
        ]
    ];
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

    ITW_CLASH_PlayerTaskRequestMenu = [
        ["C.L.A.S.H. HAL - REQUEST TASK",false],
        [
            "Strike >",
            [2],"",-5,
            [["expression","[] call ITW_CLASH_PlayerTaskRequestMenu_fnc_OpenStrike"]],
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
            if (_active) then {"[ACTIVE] Cancel Current HAL Job"} else {"Cancel Current HAL Job"},
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
        "<t color='#FFD36A'>[C.L.A.S.H.] Request HAL Task</t>",
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
            "Request HAL Task",
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
                "CLASH BOOT | player-task-request-menu-ready | version=%1 separateMenu=true strikeSubmenu=true reconGeneric=true artillery=true transport=true",
                ITW_CLASH_PlayerTaskRequestMenuVersion
            ];
        };
        uiSleep 1;
    };
};

true
