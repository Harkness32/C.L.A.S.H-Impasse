if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CrewRemnantCleanupStarted",false]) exitWith {true};
ITW_CLASH_CrewRemnantCleanupStarted = true;
ITW_CLASH_CrewRemnantCleanupVersion = 1;
ITW_CLASH_CrewRemnantGrace = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantGrace",20
];
ITW_CLASH_CrewRemnantPlayerRadius = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantPlayerRadius",300
];
ITW_CLASH_CrewRemnantMaxSurvivors = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantMaxSurvivors",2
];

ITW_CLASH_CrewRemnant_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["crew-remnant-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH CREW REMNANT | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_CrewRemnant_fnc_RemoveHAL = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    _group setVariable ["Unable",true,true];
    _group setVariable ["BUnable",true,true];
    _group setVariable ["Busy" + str _group,false];
    _group setVariable ["ITW_CLASH_ExcludeHAL",true];

    if (!isNil "ITW_CLASH_Service_fnc_RemoveHALOwnership") exitWith {
        [_group] call ITW_CLASH_Service_fnc_RemoveHALOwnership
    };

    private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
        [_group] call ITW_CLASH_fnc_GetCommanderForGroup
    } else {
        grpNull
    };
    if (!isNull _hq) then {
        {
            private _arr = +(_hq getVariable [_x,[]]);
            _hq setVariable [_x,_arr - [_group]];
        } forEach [
            "RydHQ_Friends","RydHQ_Included","RydHQ_AttackAv","RydHQ_FlankAv",
            "RydHQ_CombatAv","RydHQ_ReconAv","RydHQ_ReconG","RydHQ_CargoG",
            "RydHQ_CargoOnly","RydHQ_NoAttack","RydHQ_NoRecon","RydHQ_NoDef",
            "RydHQ_AirG","RydHQ_DefRes","RydHQ_AmmoSupportG","RydHQ_AmmoDrop",
            "RydHQ_FuelSupportG","RydHQ_RepSupportG"
        ];
    };
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        ITW_CLASH_DualHALBLUFORGroups =
            ITW_CLASH_DualHALBLUFORGroups - [_group];
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        ITW_CLASH_DualHALOPFORExtraGroups =
            ITW_CLASH_DualHALOPFORExtraGroups - [_group];
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_CrewRemnantCleanup";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 5;

        private _groups = [];
        if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
            _groups append ITW_CLASH_DualHALBLUFORGroups;
        };
        if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
            _groups append ITW_CLASH_DualHALOPFORExtraGroups;
        };
        _groups = _groups arrayIntersect _groups;

        {
            private _group = _x;
            if (
                isNull _group
                || {!(_group getVariable ["ITW_CLASH_VehicleCrewGroup",false])}
                || {[_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup}
                || {[_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved}
            ) then {continue};

            private _survivors = units _group select {alive _x};
            if (_survivors isEqualTo []) then {continue};
            if (count _survivors > ITW_CLASH_CrewRemnantMaxSurvivors) then {
                _group setVariable ["ITW_CLASH_CrewRemnantSince",-1];
                continue
            };
            if ((_survivors findIf {
                !(_x getVariable ["ITW_CLASH_VehicleCrewUnit",false])
            }) >= 0) then {
                _group setVariable ["ITW_CLASH_CrewRemnantSince",-1];
                continue
            };

            private _veh = _group getVariable ["ITW_CLASH_CrewVehicle",objNull];
            private _vehicleLost = isNull _veh || {!alive _veh} || {!canMove _veh};
            if (!_vehicleLost) then {
                _group setVariable ["ITW_CLASH_CrewRemnantSince",-1];
                continue
            };

            private _since = _group getVariable ["ITW_CLASH_CrewRemnantSince",-1];
            if (_since < 0) then {
                _group setVariable ["ITW_CLASH_CrewRemnantSince",time];
                [_group] call ITW_CLASH_CrewRemnant_fnc_RemoveHAL;
                ["quarantined",[
                    [_group] call ITW_CLASH_DualHAL_fnc_GroupId,
                    count _survivors,
                    _group getVariable ["ITW_CLASH_CrewSource","?"],
                    if (isNull _veh) then {"<null>"} else {typeOf _veh}
                ]] call ITW_CLASH_CrewRemnant_fnc_Log;
                continue
            };

            if (time - _since < ITW_CLASH_CrewRemnantGrace) then {continue};

            private _players = allPlayers select {
                !(_x isKindOf "HeadlessClient_F")
            };
            if ((_players findIf {
                (_x distance2D leader _group) <
                    ITW_CLASH_CrewRemnantPlayerRadius
            }) >= 0) then {continue};

            ["cleaned",[
                [_group] call ITW_CLASH_DualHAL_fnc_GroupId,
                count _survivors,
                _group getVariable ["ITW_CLASH_CrewSource","?"]
            ]] call ITW_CLASH_CrewRemnant_fnc_Log;

            {deleteVehicle _x} forEach _survivors;
            if (units _group isEqualTo []) then {deleteGroup _group};
        } forEach _groups;
    };
};

ITW_CLASH_CrewRemnantCleanupReady = true;
diag_log format [
    "CLASH BOOT | crew-remnant-cleanup-ready | version=%1 maxSurvivors=%2 grace=%3 playerRadius=%4 vehicleCrewOnly=true",
    ITW_CLASH_CrewRemnantCleanupVersion,
    ITW_CLASH_CrewRemnantMaxSurvivors,
    ITW_CLASH_CrewRemnantGrace,
    ITW_CLASH_CrewRemnantPlayerRadius
];
true
