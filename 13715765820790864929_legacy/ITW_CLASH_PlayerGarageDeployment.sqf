if (missionNamespace getVariable ["ITW_CLASH_PlayerGarageModuleLoaded",false]) exitWith {true};
ITW_CLASH_PlayerGarageModuleLoaded = true;
ITW_CLASH_PlayerGarageDeploymentVersion = 2;

ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass = {
    params ["_class",["_side",sideUnknown]];
    if !(_class isEqualType "" && {
        isClass (configFile >> "CfgVehicles" >> _class)
    }) exitWith {false};
    private _supportTypes = getArray (
        configFile >> "CfgVehicles" >> _class >> "availableForSupportTypes"
    );
    if !("Artillery" in _supportTypes) exitWith {false};
    if (_side == sideUnknown || {isNil "ITW_PlayerSide"} || {isNil "ITW_EnemySide"} || {
        isNil "ITW_CLASH_Generation_fnc_GetPool"
    }) exitWith {true};
    private _pool = [_side,"PLAYER_ARTILLERY","GROUND"] call
        ITW_CLASH_Generation_fnc_GetPool;
    _class in _pool
};

ITW_CLASH_PlayerGarage_fnc_ClientPending = {
    params ["_vehicle","_class"];
    if (!hasInterface || {isNull _vehicle}) exitWith {false};
    if !([_class,side group player] call
        ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass
    ) exitWith {false};

    systemChat "C.L.A.S.H. artillery pending deployment; boarding will move it to the artillery zone.";
    diag_log format [
        "CLASH GARAGE | player-artillery-actual-asset-received | player=%1 class=%2 netId=%3",
        profileName,_class,netId _vehicle
    ];
    true
};

ITW_CLASH_PlayerGarage_fnc_ClientResult = {
    params [
        "_status","_vehicle","_class",["_position",[]],
        ["_direction",0],["_reason",""]
    ];
    if (!hasInterface || {isNull _vehicle}) exitWith {false};
    if (typeOf _vehicle != _class) exitWith {false};
    if !(_vehicle getVariable ["ITW_CLASH_PlayerArtyPending",false]) exitWith {false};

    if (_status != "APPROVED" || {_position isEqualTo []}) exitWith {
        _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
        systemChat format ["C.L.A.S.H. artillery deployment deferred: %1",_reason];
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-deferred | player=%1 class=%2 netId=%3 reason=%4",
            profileName,_class,netId _vehicle,_reason
        ];
        false
    };

    if (vehicle player != _vehicle) exitWith {
        _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
        systemChat "C.L.A.S.H. artillery deployment cancelled: board the purchased vehicle and try again.";
        false
    };

    _vehicle setVelocity [0,0,0];
    _vehicle setDir _direction;
    _vehicle setPosATL _position;
    _vehicle setVectorUp surfaceNormal getPosASL _vehicle;
    _vehicle setVariable ["ITW_CLASH_PlayerArtyPending",false,true];
    _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false,true];
    _vehicle setVariable ["ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED",true];
    _vehicle setVariable ["ITW_CLASH_PlayerGarageAsset",true,true];
    _vehicle setVariable [
        "ITW_CLASH_PlayerGarageOwnerUID",getPlayerUID player,true
    ];
    systemChat "C.L.A.S.H. artillery deployed between the rear and forward generation nodes.";
    diag_log format [
        "CLASH GARAGE | player-artillery-client-deployed | player=%1 class=%2 netId=%3 position=%4",
        profileName,_class,netId _vehicle,getPosATL _vehicle
    ];
    true
};

if (isServer) then {
    ITW_CLASH_PlayerGarage_fnc_OnVehicleSpawned = {
        params ["_vehicle","_player","_class"];
        if (!isServer || {isNull _vehicle} || {isNull _player} || {!isPlayer _player}) exitWith {false};
        if (typeOf _vehicle != _class) exitWith {false};

        private _side = side group _player;
        if !([_class,_side] call
            ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass
        ) exitWith {false};

        _vehicle setVariable ["ITW_CLASH_PlayerArtyPending",true,true];
        _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false,true];
        _vehicle setVariable [
            "ITW_CLASH_PlayerArtyDeploymentState","PENDING_PLAYER_BOARD",true
        ];
        _vehicle setVariable ["ITW_CLASH_PlayerGarageAsset",true,true];
        _vehicle setVariable [
            "ITW_CLASH_PlayerGarageOwnerUID",getPlayerUID _player,true
        ];

        [_vehicle,_class] remoteExecCall [
            "ITW_CLASH_PlayerGarage_fnc_ClientPending",_player
        ];
        diag_log format [
            "CLASH GARAGE | player-artillery-actual-asset-pending | player=%1 side=%2 class=%3 netId=%4",
            name _player,_side,_class,netId _vehicle
        ];
        true
    };

    ITW_CLASH_PlayerGarage_fnc_ServerDeploy = {
        params ["_player","_vehicle"];
        if (!isServer || {isNull _player} || {!isPlayer _player} || {
            isNull _vehicle
        }) exitWith {false};
        private _owner = owner _player;
        if (remoteExecutedOwner != _owner) exitWith {
            diag_log format [
                "CLASH GARAGE | rejected-owner | caller=%1 expected=%2 player=%3",
                remoteExecutedOwner,_owner,name _player
            ];
            false
        };

        private _class = typeOf _vehicle;
        private _uid = getPlayerUID _player;
        if !(_vehicle getVariable ["ITW_CLASH_PlayerGarageAsset",false]) exitWith {
            diag_log format [
                "CLASH GARAGE | rejected-provenance | player=%1 class=%2 netId=%3 reason=not-garage-asset",
                name _player,_class,netId _vehicle
            ];
            false
        };
        if !(_vehicle getVariable ["ITW_CLASH_PlayerArtyPending",false]) exitWith {
            false
        };
        if ((_vehicle getVariable ["ITW_CLASH_PlayerGarageOwnerUID",""]) != _uid) exitWith {
            diag_log format [
                "CLASH GARAGE | rejected-provenance | player=%1 class=%2 netId=%3 reason=owner-mismatch",
                name _player,_class,netId _vehicle
            ];
            false
        };

        private _side = side group _player;
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-request | player=%1 side=%2 class=%3 netId=%4",
            name _player,_side,_class,netId _vehicle
        ];
        if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"} || {
            !(_side in [ITW_PlayerSide,ITW_EnemySide])
        }) exitWith {
            ["DEFERRED",_vehicle,_class,[],0,"unsupported-side"] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };
        if !([_class,_side] call ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass) exitWith {
            [
                "DENIED",_vehicle,_class,[],0,
                "class-not-in-side-artillery-pool"
            ] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };
        private _retryAt = _player getVariable ["ITW_CLASH_PlayerArtyDeployRetryAt",0];
        if (time < _retryAt) exitWith {
            ["DEFERRED",_vehicle,_class,[],0,"request-throttled"] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };
        _player setVariable ["ITW_CLASH_PlayerArtyDeployRetryAt",time + 10];

        private _generation = [
            _side,"PLAYER_ARTILLERY","INTERSTITIAL",getPosATL _player
        ] call ITW_CLASH_Generation_fnc_Resolve;
        if ((_generation getOrDefault ["status",""]) != "RESOLVED") exitWith {
            [
                "DEFERRED",
                _vehicle,
                _class,
                [],
                0,
                _generation getOrDefault [
                    "reason","generation-node-unavailable"
                ]
            ] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };

        [
            "APPROVED",
            _vehicle,
            _class,
            +(_generation get "origin"),
            _generation getOrDefault ["direction",0],
            "resolved"
        ] remoteExecCall [
            "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
        ];
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-approved | player=%1 side=%2 class=%3 netId=%4 rear=%5 forward=%6 objective=%7",
            name _player,
            _side,
            _class,
            netId _vehicle,
            _generation get "rearBase",
            _generation get "forwardBase",
            _generation get "objective"
        ];
        true
    };
};

if (hasInterface) then {
    ITW_CLASH_PlayerGarage_fnc_BindPlayer = {
        if (!hasInterface || {isNull player}) exitWith {false};
        if (player getVariable [
            "ITW_CLASH_PlayerGarageGetInBound",false
        ]) exitWith {true};

        player setVariable ["ITW_CLASH_PlayerGarageGetInBound",true];
        player addEventHandler ["GetInMan",{
            params ["_unit","_role","_vehicle","_turret"];
            if (_unit != player || {isNull _vehicle}) exitWith {};
            if !(_vehicle getVariable [
                "ITW_CLASH_PlayerArtyPending",false
            ]) exitWith {};
            if (_vehicle getVariable [
                "ITW_CLASH_PlayerArtyDeployRequestSent",false
            ]) exitWith {};

            _vehicle setVariable [
                "ITW_CLASH_PlayerArtyDeployRequestSent",true
            ];
            diag_log format [
                "CLASH GARAGE | player-artillery-boarding-detected | player=%1 role=%2 class=%3 netId=%4",
                profileName,_role,typeOf _vehicle,netId _vehicle
            ];
            [player,_vehicle] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ServerDeploy",2
            ];
        }];

        player addEventHandler ["Respawn",{
            params ["_unit","_corpse"];
            _unit setVariable ["ITW_CLASH_PlayerGarageGetInBound",false];
            [] call ITW_CLASH_PlayerGarage_fnc_BindPlayer;
        }];
        true
    };

    [] spawn {
        scriptName "ITW_CLASH_PlayerGarageClientBinder";
        waitUntil {
            sleep 0.25;
            !isNull player
        };

        [] call ITW_CLASH_PlayerGarage_fnc_BindPlayer;
        diag_log format [
            "CLASH BOOT | player-garage-artillery-ready | version=%1 state=PENDING_PLAYER_BOARD handoff=native-post-spawn serverResolved=true serverProvenance=true oneShot=true halAdmission=false",
            ITW_CLASH_PlayerGarageDeploymentVersion
        ];
    };
};

true
