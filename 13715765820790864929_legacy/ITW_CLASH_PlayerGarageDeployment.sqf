if (missionNamespace getVariable ["ITW_CLASH_PlayerGarageModuleLoaded",false]) exitWith {true};
ITW_CLASH_PlayerGarageModuleLoaded = true;
ITW_CLASH_PlayerGarageDeploymentVersion = 3;

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

    systemChat "C.L.A.S.H. artillery pending deployment; enter the driver seat to move it to a cleared artillery zone.";
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

    if (vehicle player != _vehicle || {driver _vehicle != player}) exitWith {
        _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
        systemChat "C.L.A.S.H. artillery deployment cancelled: occupy the driver seat and try again.";
        false
    };
    if (!local _vehicle) exitWith {
        _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
        systemChat "C.L.A.S.H. artillery deployment deferred: vehicle locality has not transferred.";
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-deferred | player=%1 class=%2 netId=%3 reason=vehicle-not-local",
            profileName,_class,netId _vehicle
        ];
        false
    };

    private _destination = +_position;
    if (count _destination < 3) then {_destination pushBack 0};
    _destination set [2,0];

    private _vehicleDamageAllowed = isDamageAllowed _vehicle;
    private _playerDamageAllowed = isDamageAllowed player;
    _vehicle allowDamage false;
    player allowDamage false;
    _vehicle engineOn false;
    _vehicle setVelocity [0,0,0];
    _vehicle setDir _direction;
    _vehicle setVehiclePosition [_destination,[],0,"NONE"];
    _vehicle setVectorUp (surfaceNormal _destination);
    private _settlePosition = getPosATL _vehicle;
    _settlePosition set [2,(_settlePosition#2) + 0.35];
    _vehicle setPosATL _settlePosition;
    _vehicle setVelocity [0,0,0];
    _vehicle setVariable ["ITW_CLASH_PlayerArtyPending",false,true];
    _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false,true];
    _vehicle setVariable ["ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED",true];
    _vehicle setVariable ["ITW_CLASH_PlayerGarageAsset",true,true];
    _vehicle setVariable [
        "ITW_CLASH_PlayerGarageOwnerUID",getPlayerUID player,true
    ];
    systemChat "C.L.A.S.H. artillery deployed between the rear and forward generation nodes.";
    diag_log format [
        "CLASH GARAGE | player-artillery-client-deployed | player=%1 class=%2 netId=%3 requested=%4 actual=%5 protection=2s",
        profileName,_class,netId _vehicle,_destination,getPosATL _vehicle
    ];

    [
        _vehicle,_vehicleDamageAllowed,player,_playerDamageAllowed
    ] spawn {
        params [
            "_vehicle","_vehicleDamageAllowed",
            "_unit","_unitDamageAllowed"
        ];
        sleep 2;
        if (!isNull _vehicle && {local _vehicle}) then {
            _vehicle setVelocity [0,0,0];
            _vehicle allowDamage _vehicleDamageAllowed;
        };
        if (!isNull _unit && {local _unit}) then {
            _unit allowDamage _unitDamageAllowed;
        };
    };
    true
};

if (isServer) then {
    ITW_CLASH_PlayerGarage_fnc_FindSafeDestination = {
        params ["_vehicle","_class","_origin"];
        if (isNull _vehicle || {_origin isEqualTo []} || {
            !isClass (configFile >> "CfgVehicles" >> _class)
        }) exitWith {[]};

        private _box = boundingBoxReal _vehicle;
        private _minimum = _box#0;
        private _maximum = _box#1;
        private _width = abs ((_maximum#0) - (_minimum#0));
        private _length = abs ((_maximum#1) - (_minimum#1));
        private _clearance = (((_width max _length) * 0.75) max 10) min 30;

        private _candidate = [
            _origin,0,450,_clearance,0,0.18,0,[],[_origin,_origin]
        ] call BIS_fnc_findSafePos;
        if (_candidate isEqualTo []) exitWith {[]};

        _candidate = _candidate findEmptyPosition [0,125,_class];
        if (_candidate isEqualTo []) exitWith {[]};
        if (count _candidate < 3) then {_candidate pushBack 0};
        _candidate set [2,0];
        if (surfaceIsWater _candidate) exitWith {[]};

        private _normal = surfaceNormal _candidate;
        if (count _normal < 3 || {(_normal#2) < 0.95}) exitWith {[]};

        private _dynamicBlockers = nearestObjects [
            _candidate,["House","Thing","AllVehicles"],_clearance,true
        ] select {
            _x != _vehicle && {!(_x in crew _vehicle)}
        };
        if !(_dynamicBlockers isEqualTo []) exitWith {[]};

        private _terrainBlockers = nearestTerrainObjects [
            _candidate,
            ["HOUSE","BUILDING","WALL","ROCK","ROCKS","TREE"],
            _clearance,
            false,
            true
        ];
        if !(_terrainBlockers isEqualTo []) exitWith {[]};

        _candidate
    };

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

        if (vehicle _player != _vehicle || {driver _vehicle != _player}) exitWith {
            ["DEFERRED",_vehicle,_class,[],0,"driver-seat-required"] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };

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

        private _rawOrigin = +(_generation get "origin");
        private _safePosition = [
            _vehicle,_class,_rawOrigin
        ] call ITW_CLASH_PlayerGarage_fnc_FindSafeDestination;
        if (_safePosition isEqualTo []) exitWith {
            [
                "DEFERRED",_vehicle,_class,[],0,
                "no-clear-vehicle-sized-deployment-slot"
            ] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            diag_log format [
                "CLASH GARAGE | player-artillery-deployment-deferred | player=%1 side=%2 class=%3 netId=%4 reason=no-clear-vehicle-sized-deployment-slot origin=%5",
                name _player,_side,_class,netId _vehicle,_rawOrigin
            ];
            false
        };

        [
            "APPROVED",
            _vehicle,
            _class,
            _safePosition,
            _generation getOrDefault ["direction",0],
            "resolved-safe"
        ] remoteExecCall [
            "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
        ];
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-approved | player=%1 side=%2 class=%3 netId=%4 rear=%5 forward=%6 objective=%7 origin=%8 safe=%9",
            name _player,
            _side,
            _class,
            netId _vehicle,
            _generation get "rearBase",
            _generation get "forwardBase",
            _generation get "objective",
            _rawOrigin,
            _safePosition
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
            if (toLowerANSI _role != "driver") exitWith {
                systemChat "C.L.A.S.H. artillery pending deployment: enter the driver seat.";
            };
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
            "CLASH BOOT | player-garage-artillery-ready | version=%1 state=PENDING_PLAYER_BOARD handoff=native-post-spawn serverResolved=true serverProvenance=true vehicleSizedClearance=true failClosed=true driverOnly=true physicsGrace=2 oneShot=true halAdmission=false",
            ITW_CLASH_PlayerGarageDeploymentVersion
        ];
    };
};

true
