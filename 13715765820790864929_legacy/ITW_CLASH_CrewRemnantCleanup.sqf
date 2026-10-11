if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CrewRemnantCleanupStarted",false]) exitWith {true};
ITW_CLASH_CrewRemnantCleanupStarted = true;
ITW_CLASH_CrewRemnantCleanupVersion = 2;
ITW_CLASH_CrewRemnantGrace = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantGrace",20
];
ITW_CLASH_CrewRemnantPlayerRadius = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantPlayerRadius",300
];
ITW_CLASH_CrewRemnantMaxSurvivors = missionNamespace getVariable [
    "ITW_CLASH_CrewRemnantMaxSurvivors",4
];

/*
    Version 2: the delete step can now be reached.

    Version 1 quarantined a crew and then never saw it again, for two reasons
    that each did the job alone (43 quarantined, 0 cleaned, three RPTs of
    2026-10-10):

      1. The loop walked the two DualHAL lists. Quarantine ends in
         ITW_CLASH_Service_fnc_RemoveHALOwnership, which takes the group out of
         both (ITW_CLASH_ServiceLifecycle.sqf:134).
      2. The loop skips anything ITW_CLASH_DualHAL_fnc_IsLifecycleReserved, and
         that function's first test is ITW_CLASH_ExcludeHAL
         (ITW_CLASH_DualHALCheckbook.sqf:82), which quarantine sets.

    So the module keeps its own list of what it has quarantined, walks that as
    well, and for those groups stops reading its own ExcludeHAL as somebody
    else's reservation. Every other reservation still protects the crew.
*/
ITW_CLASH_CrewRemnantQuarantined = [];

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

/*
    Is this crew somebody else's right now?

    Not quarantined: ask DualHAL, as before. Quarantined: the same question
    without ExcludeHAL, because that flag is ours. The flag names are DualHAL's
    (IsLifecycleReserved); tests/test_crew_remnant_cleanup.py fails if that
    list grows and this one does not.
*/
ITW_CLASH_CrewRemnant_fnc_IsReserved = {
    params ["_group"];
    if !(_group in ITW_CLASH_CrewRemnantQuarantined) exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved
    };
    _group getVariable ["ITW_CLASH_CASEVAC",false]
    || {_group getVariable ["ITW_CLASH_GroundMEDEVAC",false]}
    || {_group getVariable ["ITW_CLASH_ReconstitutionTransit",false]}
    || {_group getVariable ["ITW_CLASH_RecoveryOwned",false]}
    || {_group getVariable ["itwDelivery",false]}
};

/*
    Why the vehicle counts as lost, for the log.

    G36 left a Panther 16 s after its first order and G57 an armed LSV after
    25 s, both at base, and version 1's line could not say what was wrong with
    either vehicle. Hit points at or above half are listed so the next RPT can.
*/
ITW_CLASH_CrewRemnant_fnc_VehicleState = {
    params ["_veh"];
    if (isNull _veh) exitWith {["vehicle-null",[]]};
    if (!alive _veh) exitWith {["vehicle-dead",[]]};

    private _broken = [];
    private _hit = getAllHitPointsDamage _veh;
    if (count _hit > 2) then {
        {
            if (_x >= 0.5) then {
                _broken pushBack [(_hit#0) select _forEachIndex,(round (_x * 100)) / 100];
            };
        } forEach (_hit#2);
    };
    [["vehicle-usable","cannot-move"] select (!canMove _veh),_broken]
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
        // Dead and deleted crews leave the quarantine list here; nothing else
        // removes them.
        ITW_CLASH_CrewRemnantQuarantined = ITW_CLASH_CrewRemnantQuarantined select {
            !isNull _x && {((units _x) findIf {alive _x}) >= 0}
        };
        _groups append ITW_CLASH_CrewRemnantQuarantined;
        _groups = _groups arrayIntersect _groups;

        {
            private _group = _x;
            if (
                isNull _group
                || {!(_group getVariable ["ITW_CLASH_VehicleCrewGroup",false])}
                || {[_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup}
                || {[_group] call ITW_CLASH_CrewRemnant_fnc_IsReserved}
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
                // Listed before HAL ownership goes, so there is no pass on
                // which the crew is in neither place.
                ITW_CLASH_CrewRemnantQuarantined pushBackUnique _group;
                [_group] call ITW_CLASH_CrewRemnant_fnc_RemoveHAL;
                private _state = [_veh] call ITW_CLASH_CrewRemnant_fnc_VehicleState;
                ["quarantined",[
                    [_group] call ITW_CLASH_DualHAL_fnc_GroupId,
                    count _survivors,
                    _group getVariable ["ITW_CLASH_CrewSource","?"],
                    if (isNull _veh) then {"<null>"} else {typeOf _veh},
                    _state#0,
                    _state#1,
                    {vehicle _x != _x} count _survivors
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
                _group getVariable ["ITW_CLASH_CrewSource","?"],
                round (time - _since)
            ]] call ITW_CLASH_CrewRemnant_fnc_Log;

            // deleteVehicleCrew is the engine's command for a man in a seat;
            // deleteVehicle is for a man on foot.
            {
                private _seat = objectParent _x;
                if (isNull _seat) then {
                    deleteVehicle _x;
                } else {
                    _seat deleteVehicleCrew _x;
                };
            } forEach _survivors;
            // units can still list the men on this frame, so the group is told
            // to go when it empties rather than tested for being empty now.
            _group deleteGroupWhenEmpty true;
        } forEach _groups;
    };
};

ITW_CLASH_CrewRemnantCleanupReady = true;
diag_log format [
    "CLASH BOOT | crew-remnant-cleanup-ready | version=%1 maxSurvivors=%2 grace=%3 playerRadius=%4 vehicleCrewOnly=true walksQuarantined=true",
    ITW_CLASH_CrewRemnantCleanupVersion,
    ITW_CLASH_CrewRemnantMaxSurvivors,
    ITW_CLASH_CrewRemnantGrace,
    ITW_CLASH_CrewRemnantPlayerRadius
];
true
