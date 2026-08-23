if (!hasInterface) exitWith {true};
if (missionNamespace getVariable [
    "ITW_CLASH_PlayerEmploymentMenuStarted",false
]) exitWith {true};

ITW_CLASH_PlayerEmploymentMenuStarted = true;
ITW_CLASH_PlayerEmploymentMenuVersion = 1;
ITW_CLASH_PlayerEmploymentJobTypes = [
    "COMBAT","TRANSPORT","MEDEVAC","LOGISTICS","ARTILLERY"
];

ITW_CLASH_PlayerEmployment_fnc_Subscriptions = {
    private _group = group player;
    if (isNull _group) exitWith {[]};
    private _subscriptions = +(_group getVariable [
        "ITW_CLASH_PlayerJobSubscriptions",[]
    ]);
    _subscriptions = _subscriptions select {
        _x isEqualType ""
        && {_x in ITW_CLASH_PlayerEmploymentJobTypes}
    };
    _subscriptions arrayIntersect
        ITW_CLASH_PlayerEmploymentJobTypes
};

ITW_CLASH_PlayerEmployment_fnc_ReceiveState = {
    params ["_success","_message","_subscriptions"];
    if (
        isRemoteExecuted
        && {remoteExecutedOwner != 2}
    ) exitWith {false};
    if !(_subscriptions isEqualType []) exitWith {false};

    private _group = group player;
    if (!isNull _group) then {
        _group setVariable [
            "ITW_CLASH_PlayerJobSubscriptions",
            _subscriptions arrayIntersect
                ITW_CLASH_PlayerEmploymentJobTypes
        ];
    };
    if (_message isEqualType "" && {_message isNotEqualTo ""}) then {
        systemChat format [
            "C.L.A.S.H. HAL Employment: %1",_message
        ];
    };
    _success
};

ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription = {
    params ["_jobType"];
    if !(_jobType isEqualType "") exitWith {false};
    _jobType = toUpperANSI _jobType;
    if !(_jobType in ITW_CLASH_PlayerEmploymentJobTypes) exitWith {
        false
    };
    if (player != leader group player) exitWith {
        systemChat (
            "C.L.A.S.H. HAL Employment: only the group leader "
            + "can change the group's job channels."
        );
        false
    };

    private _subscriptions = call
        ITW_CLASH_PlayerEmployment_fnc_Subscriptions;
    [
        player,_jobType,!(_jobType in _subscriptions)
    ] remoteExecCall [
        "ITW_CLASH_PlayerTasks_fnc_SetSubscriptionRemote",2
    ];
    true
};

ITW_CLASH_PlayerEmployment_fnc_ToggleAll = {
    if (player != leader group player) exitWith {
        systemChat (
            "C.L.A.S.H. HAL Employment: only the group leader "
            + "can change the group's job channels."
        );
        false
    };
    private _subscriptions = call
        ITW_CLASH_PlayerEmployment_fnc_Subscriptions;
    private _enable = (
        count (
            _subscriptions arrayIntersect
                ITW_CLASH_PlayerEmploymentJobTypes
        )
        < count ITW_CLASH_PlayerEmploymentJobTypes
    );
    [player,_enable] remoteExecCall [
        "ITW_CLASH_PlayerTasks_fnc_SetAllSubscriptionsRemote",2
    ];
    true
};

ITW_CLASH_PlayerEmployment_fnc_CancelCurrentJob = {
    if (player != leader group player) exitWith {
        systemChat (
            "C.L.A.S.H. HAL Employment: only the group leader "
            + "can cancel the group's current job."
        );
        false
    };
    [player] remoteExecCall [
        "ITW_CLASH_PlayerTasks_fnc_CancelRemote",2
    ];
    true
};

ITW_CLASH_PlayerEmployment_fnc_Label = {
    params ["_jobType","_displayName"];
    private _subscriptions = call
        ITW_CLASH_PlayerEmployment_fnc_Subscriptions;
    format [
        "%1 %2",
        if (_jobType in _subscriptions) then {"[ON]"} else {"[OFF]"},
        _displayName
    ]
};

ITW_CLASH_PlayerEmployment_fnc_OpenMenu = {
    private _subscriptions = call
        ITW_CLASH_PlayerEmployment_fnc_Subscriptions;
    private _allEnabled = (
        count (
            _subscriptions arrayIntersect
                ITW_CLASH_PlayerEmploymentJobTypes
        )
        == count ITW_CLASH_PlayerEmploymentJobTypes
    );
    private _ammoJob = (group player) getVariable [
        "ITW_CLASH_PlayerAmmoJobId",""
    ];
    private _artilleryJob = (group player) getVariable [
        "ITW_CLASH_PlayerArtilleryJobId",""
    ];
    private _jobStatus = if (
        _ammoJob isNotEqualTo "" || {_artilleryJob isNotEqualTo ""}
    ) then {
        "[ACTIVE] Cancel Current HAL Job"
    } else {
        "Cancel Current HAL Job"
    };

    ITW_CLASH_PlayerEmploymentMenu = [
        ["C.L.A.S.H. HAL Employment",false],
        [
            ["COMBAT","Accept Combat Missions"] call
                ITW_CLASH_PlayerEmployment_fnc_Label,
            [2],"",-5,
            [["expression","['COMBAT'] call ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription"]],
            "1","1"
        ],
        [
            ["TRANSPORT","Accept Transport Missions"] call
                ITW_CLASH_PlayerEmployment_fnc_Label,
            [3],"",-5,
            [["expression","['TRANSPORT'] call ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription"]],
            "1","1"
        ],
        [
            ["MEDEVAC","Accept MEDEVAC Missions"] call
                ITW_CLASH_PlayerEmployment_fnc_Label,
            [4],"",-5,
            [["expression","['MEDEVAC'] call ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription"]],
            "1","1"
        ],
        [
            ["LOGISTICS","Accept Logistics Missions"] call
                ITW_CLASH_PlayerEmployment_fnc_Label,
            [5],"",-5,
            [["expression","['LOGISTICS'] call ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription"]],
            "1","1"
        ],
        [
            ["ARTILLERY","Accept Artillery Missions"] call
                ITW_CLASH_PlayerEmployment_fnc_Label,
            [6],"",-5,
            [["expression","['ARTILLERY'] call ITW_CLASH_PlayerEmployment_fnc_ToggleSubscription"]],
            "1","1"
        ],
        [
            if (_allEnabled) then {
                "Disable All Job Types"
            } else {
                "Enable All Job Types"
            },
            [7],"",-5,
            [["expression","[] call ITW_CLASH_PlayerEmployment_fnc_ToggleAll"]],
            "1","1"
        ],
        [
            _jobStatus,
            [8],"",-5,
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
    showCommandingMenu "#USER:ITW_CLASH_PlayerEmploymentMenu";
    true
};

ITW_CLASH_PlayerEmployment_fnc_Install = {
    params ["_unit"];
    if (isNull _unit || {!local _unit}) exitWith {false};
    if (_unit getVariable [
        "ITW_CLASH_PlayerEmploymentEntryInstalled",false
    ]) exitWith {true};

    private _actionId = _unit addAction [
        "<t color='#9FD8FF'>[C.L.A.S.H.] HAL Employment</t>",
        {[] call ITW_CLASH_PlayerEmployment_fnc_OpenMenu},
        nil,
        -4,
        false,
        true,
        "",
        "_this isEqualTo _target",
        0.01
    ];
    _unit setVariable [
        "ITW_CLASH_PlayerEmploymentActionId",_actionId
    ];

    private _commId = [
        _unit,"ITW_CLASH_HALEmployment"
    ] call BIS_fnc_addCommMenuItem;
    _unit setVariable [
        "ITW_CLASH_PlayerEmploymentCommId",_commId
    ];

    if (
        isClass (configFile >> "CfgPatches" >> "ace_main")
        && {!isNil "ace_interact_menu_fnc_createAction"}
        && {!isNil "ace_interact_menu_fnc_addActionToObject"}
    ) then {
        private _aceAction = [
            "ITW_CLASH_HALEmployment",
            "C.L.A.S.H. HAL Employment",
            "",
            {[] call ITW_CLASH_PlayerEmployment_fnc_OpenMenu},
            {true},
            {}
        ] call ace_interact_menu_fnc_createAction;
        [
            _unit,1,["ACE_SelfActions"],_aceAction
        ] call ace_interact_menu_fnc_addActionToObject;
    };

    _unit setVariable [
        "ITW_CLASH_PlayerEmploymentEntryInstalled",true
    ];
    true
};

[] spawn {
    scriptName "ITW_CLASH_PlayerEmploymentMenuInstaller";
    private _installedFor = objNull;
    while {true} do {
        if (
            !isNull player
            && {local player}
            && {player != _installedFor}
        ) then {
            [player] call
                ITW_CLASH_PlayerEmployment_fnc_Install;
            _installedFor = player;
            diag_log format [
                "CLASH BOOT | player-employment-menu-ready | version=%1 commandMenu=true scrollAction=true ace=%2 persistentSubscriptions=true vehicleResets=false leaderAuthority=true",
                ITW_CLASH_PlayerEmploymentMenuVersion,
                isClass (configFile >> "CfgPatches" >> "ace_main")
            ];
        };
        uiSleep 1;
    };
};

true
