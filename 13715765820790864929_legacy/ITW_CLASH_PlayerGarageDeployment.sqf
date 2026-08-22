if (missionNamespace getVariable ["ITW_CLASH_PlayerGarageModuleLoaded",false]) exitWith {true};
ITW_CLASH_PlayerGarageModuleLoaded = true;
ITW_CLASH_PlayerGarageDeploymentVersion = 1;

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

ITW_CLASH_PlayerGarage_fnc_ClientResult = {
    params ["_status","_class",["_position",[]],["_direction",0],["_reason",""]];
    if (!hasInterface) exitWith {false};
    private _veh = vehicle player;
    if (isNull _veh || {_veh == player} || {typeOf _veh != _class}) exitWith {false};
    if !(_veh getVariable ["ITW_CLASH_PlayerArtyPending",false]) exitWith {false};

    if (_status != "APPROVED" || {_position isEqualTo []}) exitWith {
        _veh setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
        systemChat format ["C.L.A.S.H. artillery deployment deferred: %1",_reason];
        false
    };

    _veh setVelocity [0,0,0];
    _veh setDir _direction;
    _veh setPosATL _position;
    _veh setVectorUp surfaceNormal getPosASL _veh;
    _veh setVariable ["ITW_CLASH_PlayerArtyPending",false,true];
    _veh setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false,true];
    _veh setVariable ["ITW_CLASH_PlayerArtyDeploymentState","DEPLOYED",true];
    _veh setVariable ["ITW_CLASH_PlayerGarageAsset",true,true];
    _veh setVariable [
        "ITW_CLASH_PlayerGarageOwnerUID",getPlayerUID player,true
    ];
    systemChat "C.L.A.S.H. artillery deployed between the rear and forward generation nodes.";
    true
};

if (isServer) then {
    ITW_CLASH_PlayerGarage_fnc_ServerDeploy = {
        params ["_player","_class"];
        if (!isServer || {isNull _player} || {!isPlayer _player}) exitWith {false};
        private _owner = owner _player;
        if (remoteExecutedOwner != _owner) exitWith {
            diag_log format [
                "CLASH GARAGE | rejected-owner | caller=%1 expected=%2 player=%3",
                remoteExecutedOwner,_owner,name _player
            ];
            false
        };

        private _side = side group _player;
        if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"} || {
            !(_side in [ITW_PlayerSide,ITW_EnemySide])
        }) exitWith {
            ["DEFERRED",_class,[],0,"unsupported-side"] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };
        if !([_class,_side] call ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass) exitWith {
            ["DENIED",_class,[],0,"class-not-in-side-artillery-pool"] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ClientResult",_player
            ];
            false
        };
        private _retryAt = _player getVariable ["ITW_CLASH_PlayerArtyDeployRetryAt",0];
        if (time < _retryAt) exitWith {
            ["DEFERRED",_class,[],0,"request-throttled"] remoteExecCall [
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
                _class,
                [],
                0,
                _generation getOrDefault ["reason","generation-node-unavailable"]
            ] remoteExecCall ["ITW_CLASH_PlayerGarage_fnc_ClientResult",_player];
            false
        };

        [
            "APPROVED",
            _class,
            +(_generation get "origin"),
            _generation getOrDefault ["direction",0],
            "resolved"
        ] remoteExecCall ["ITW_CLASH_PlayerGarage_fnc_ClientResult",_player];
        diag_log format [
            "CLASH GARAGE | player-artillery-deployment-approved | player=%1 side=%2 class=%3 rear=%4 forward=%5 objective=%6",
            name _player,
            _side,
            _class,
            _generation get "rearBase",
            _generation get "forwardBase",
            _generation get "objective"
        ];
        true
    };
};

if (hasInterface) then {
    [] spawn {
        scriptName "ITW_CLASH_PlayerGarageClientBinder";
        waitUntil {
            sleep 0.25;
            !isNil "BIS_fnc_addScriptedEventHandler" && {
                !isNull player
            }
        };

        [missionNamespace,"garageClosed",{
            private _veh = missionNamespace getVariable ["BIS_fnc_garage_center",objNull];
            if (isNull _veh || {_veh == player}) exitWith {};
            if !([typeOf _veh,side group player] call ITW_CLASH_PlayerGarage_fnc_IsArtilleryClass) exitWith {};

            _veh setVariable ["ITW_CLASH_PlayerArtyPending",true];
            _veh setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false];
            _veh setVariable ["ITW_CLASH_PlayerArtyDeploymentState","PENDING_PLAYER_BOARD"];
            systemChat "C.L.A.S.H. artillery pending deployment; boarding will move it to the artillery zone.";
        }] call BIS_fnc_addScriptedEventHandler;

        player addEventHandler ["GetInMan",{
            params ["_unit","_role","_vehicle","_turret"];
            if (_unit != player || {isNull _vehicle}) exitWith {};
            if !(_vehicle getVariable ["ITW_CLASH_PlayerArtyPending",false]) exitWith {};
            if (_vehicle getVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",false]) exitWith {};

            _vehicle setVariable ["ITW_CLASH_PlayerArtyDeployRequestSent",true];
            [player,typeOf _vehicle] remoteExecCall [
                "ITW_CLASH_PlayerGarage_fnc_ServerDeploy",2
            ];
        }];

        diag_log format [
            "CLASH BOOT | player-garage-artillery-ready | version=%1 state=PENDING_PLAYER_BOARD serverResolved=true oneShot=true halAdmission=false",
            ITW_CLASH_PlayerGarageDeploymentVersion
        ];
    };
};

true
