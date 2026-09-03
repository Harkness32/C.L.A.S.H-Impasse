/* Temporary read-only observer for HAL air-transport pickup stalls. */
if (!isServer) exitWith {};

ITW_CLASH_SCargoAirDiagVersion = 13;
ITW_CLASH_SCargoAirDiagPoll = 1;
ITW_CLASH_SCargoAirDiagStallSeconds = 8;
ITW_CLASH_SCargoAirDiagStates = createHashMap;

ITW_CLASH_SCargoAirDiag_fnc_CargoGroups = {
    params ["_carrier"];
    allGroups select {
        private _g = _x;
        !isNull _g
        && {_g getVariable ["CargoChosen",false]}
        && {(_g getVariable ["AssignedCargo" + str _g,objNull]) isEqualTo _carrier}
    }
};

ITW_CLASH_SCargoAirDiag_fnc_Carriers = {
    private _result = [];
    {
        private _g = _x;
        if (!isNull _g && {_g getVariable ["CargoChosen",false]}) then {
            private _carrier = _g getVariable ["AssignedCargo" + str _g,objNull];
            if (!isNull _carrier && {_carrier isKindOf "Air"}) then {
                _result pushBackUnique _carrier;
            };
        };
    } forEach allGroups;
    _result
};

ITW_CLASH_SCargoAirDiag_fnc_WP = {
    params ["_g"];
    if (isNull _g) exitWith {["<null>",[], -1]};
    private _i = currentWaypoint _g;
    private _wps = waypoints _g;
    if (_wps isEqualTo [] || {_i < 0} || {_i >= count _wps}) exitWith {["NONE",[],_i]};
    private _wp = [_g,_i];
    [waypointType _wp,waypointPosition _wp,_i]
};

ITW_CLASH_SCargoAirDiag_fnc_Snapshot = {
    params ["_carrier"];
    private _cargo = [_carrier] call ITW_CLASH_SCargoAirDiag_fnc_CargoGroups;
    private _cg = if (_cargo isEqualTo []) then {grpNull} else {_cargo#0};
    private _pilot = driver _carrier;
    if (isNull _pilot) then {_pilot = assignedDriver _carrier};
    private _carrierGroup = if (isNull _pilot) then {grpNull} else {group _pilot};
    private _wp = [_carrierGroup] call ITW_CLASH_SCargoAirDiag_fnc_WP;
    private _wpCount = if (isNull _carrierGroup) then {0} else {count (waypoints _carrierGroup)};
    private _groupLeader = if (isNull _carrierGroup) then {objNull} else {leader _carrierGroup};
    private _leaderIsPilot = !isNull _groupLeader
        && {!isNull (driver _carrier)}
        && {_groupLeader isEqualTo (driver _carrier)};
    private _wpPos = _wp#1;
    private _wpDistance = if (_wpPos isEqualTo []) then {-1} else {round (_carrier distance2D _wpPos)};
    private _alive = [];
    { _alive append ((units _x) select {alive _x}); } forEach _cargo;
    private _aboard = _alive select {vehicle _x isEqualTo _carrier};
    private _allAboard = _alive isNotEqualTo [] && {count _aboard == count _alive};
    private _hq = if (
        !isNull _carrierGroup && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}
    ) then {[_carrierGroup] call ITW_CLASH_fnc_GetCommanderForGroup} else {grpNull};
    private _cycle = if (isNull _hq) then {-1} else {_hq getVariable ["RydHQ_Cyclecount",-1]};
    private _hqLZ = !isNull _hq && {_hq getVariable ["RydHQ_LZ",false]};
    private _tempLZ = if (isNull _carrierGroup) then {objNull} else {
        _carrierGroup getVariable ["TempLZ",objNull]
    };
    private _nearLZ = nearestObjects [_carrier,["Land_HelipadEmpty_F"],60];
    private _nearLZDistance = if (_nearLZ isEqualTo []) then {-1} else {
        _carrier distance2D (_nearLZ#0)
    };
    private _injectCycle = _carrier getVariable [
        "ITW_CLASH_CheckbookInjectedCycle",
        if (isNull _carrierGroup) then {-1} else {
            _carrierGroup getVariable ["ITW_CLASH_CheckbookInjectedCycle",-1]
        }
    ];
    [
        ["carrierGroup",if (isNull _carrierGroup) then {"<null>"} else {str _carrierGroup}],
        ["carrier",typeOf _carrier],
        ["posATL",getPosATL _carrier],
        ["alt",round ((getPosATL _carrier)#2)],
        ["speed",round speed _carrier],
        ["engineOn",isEngineOn _carrier],
        ["canMove",canMove _carrier],
        ["touchingGround",isTouchingGround _carrier],
        ["waypoint",_wp],
        ["waypointCount",_wpCount],
        ["wpDistance",_wpDistance],
        ["leaderIsPilot",_leaderIsPilot],
        ["leaderCommand",if (isNull _groupLeader) then {"<null>"} else {currentCommand _groupLeader}],
        ["leaderExpected",if (isNull _groupLeader) then {[]} else {expectedDestination _groupLeader}],
        ["pilotCommand",if (isNull _pilot) then {"<null>"} else {currentCommand _pilot}],
        ["pilotReady",if (isNull _pilot) then {false} else {unitReady _pilot}],
        ["pilotExpected",if (isNull _pilot) then {[]} else {expectedDestination _pilot}],
        ["lastMoveOR",_carrier getVariable ["LastMoveOR",0]],
        ["carrierInAirG",!isNull _hq && {_carrierGroup in (_hq getVariable ["RydHQ_AirG",[]])}],
        ["cargoInNCrewInfG",!isNull _hq && {!isNull _cg} && {_cg in (_hq getVariable ["RydHQ_NCrewInfG",[]])}],
        ["sitrepCycle",_cycle],
        ["injectedCycle",_injectCycle],
        ["sitrepSinceInjection",if (_cycle < 0 || {_injectCycle < 0}) then {-1} else {_cycle - _injectCycle}],
        ["hqLZ",_hqLZ],
        ["tempLZ",if (isNull _tempLZ) then {[]} else {[typeOf _tempLZ,getPosATL _tempLZ,round (_carrier distance2D _tempLZ)]}],
        ["nearHelipadCount",count _nearLZ],
        ["nearHelipadDistance",if (_nearLZDistance < 0) then {-1} else {round _nearLZDistance}],
        ["pilotAI",if (isNull _pilot) then {[]} else {[
            _pilot checkAIFeature "TARGET",
            _pilot checkAIFeature "AUTOTARGET",
            _pilot checkAIFeature "MOVE",
            _pilot checkAIFeature "FSM",
            _pilot checkAIFeature "COVER",
            _pilot checkAIFeature "SUPPRESSION"
        ]}],
        ["behaviour",if (isNull _pilot) then {""} else {behaviour _pilot}],
        ["combatMode",if (isNull _carrierGroup) then {""} else {combatMode _carrierGroup}],
        ["busy",if (isNull _carrierGroup) then {false} else {_carrierGroup getVariable ["Busy" + str _carrierGroup,false]}],
        ["cargoM",if (isNull _carrierGroup) then {false} else {_carrierGroup getVariable ["CargoM" + str _carrierGroup,false]}],
        ["unable",if (isNull _carrierGroup) then {false} else {_carrierGroup getVariable ["Unable",false]}],
        ["allAboard",_allAboard],
        ["assignedCargo",count assignedCargo _carrier],
        ["crew",count crew _carrier],
        ["cargoGroups",_cargo apply {[str _x,count ((units _x) select {alive _x}),count ((units _x) select {vehicle _x isEqualTo _carrier})]}]
    ]
};

[] spawn {
    scriptName "ITW_CLASH_SCargoAirDiagnostics";
    waitUntil {
        sleep 0.5;
        missionNamespace getVariable ["ITW_CLASH_HALReady",false]
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {};

    diag_log format ["CLASH SCARGO AIR DIAG | ready | version=%1 observerOnly=true leaderPilotSpawnTest=true",ITW_CLASH_SCargoAirDiagVersion];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_SCargoAirDiagPoll;
        {
            private _carrier = _x;
            if (isNull _carrier || {!(_carrier isKindOf "Air")}) then {continue};
            private _snap = [_carrier] call ITW_CLASH_SCargoAirDiag_fnc_Snapshot;
            private _cargo = [_carrier] call ITW_CLASH_SCargoAirDiag_fnc_CargoGroups;
            private _phase = if (_cargo isEqualTo []) then {"IDLE"} else {
                private _alive = [];
                {_alive append ((units _x) select {alive _x});} forEach _cargo;
                private _aboard = _alive select {vehicle _x isEqualTo _carrier};
                private _allAboard = _alive isNotEqualTo [] && {count _aboard == count _alive};
                if (_allAboard) then {"EMBARKED"} else {"BOARDING"}
            };
            private _key = str _carrier;
            private _state = ITW_CLASH_SCargoAirDiagStates getOrDefault [_key,["",time,-1e10,-1e10,-1e10]];
            _state params ["_lastPhase","_phaseSince","_lastSnapshot","_lastNoMove","_lastMoveStall"];
            if (_phase != _lastPhase) then {
                _phaseSince = time;
                diag_log format ["CLASH SCARGO AIR DIAG | phase=%1 | %2",_phase,_snap];
            };
            if (time - _lastSnapshot >= 5) then {
                _lastSnapshot = time;
                diag_log format ["CLASH SCARGO AIR DIAG | snapshot | %1",_snap];
            };
            private _snapMap = createHashMapFromArray _snap;
            private _wp = _snapMap getOrDefault ["waypoint",["NONE",[],-1]];
            private _wpType = _wp#0;
            private _wpDistance = _snapMap getOrDefault ["wpDistance",-1];
            private _speed = abs (_snapMap getOrDefault ["speed",0]);
            private _held = time - _phaseSince;
            if (_phase == "EMBARKED" && {_speed < 1} && {_held >= ITW_CLASH_SCargoAirDiagStallSeconds}) then {
                if (_wpType == "MOVE" && {_wpDistance > 100}) then {
                    if (time - _lastMoveStall >= 5) then {
                        _lastMoveStall = time;
                        diag_log format ["CLASH SCARGO AIR DIAG | POST-EMBARK-MOVE-STALLED | heldSeconds=%1 | %2",round _held,_snap];
                    };
                } else {
                    if (time - _lastNoMove >= 5) then {
                        _lastNoMove = time;
                        diag_log format ["CLASH SCARGO AIR DIAG | POST-EMBARK-NO-OUTBOUND-MOVE | heldSeconds=%1 | %2",round _held,_snap];
                    };
                };
            };
            ITW_CLASH_SCargoAirDiagStates set [_key,[_phase,_phaseSince,_lastSnapshot,_lastNoMove,_lastMoveStall]];
        } forEach (call ITW_CLASH_SCargoAirDiag_fnc_Carriers);
    };
};
