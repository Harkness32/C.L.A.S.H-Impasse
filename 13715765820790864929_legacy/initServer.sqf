/*
    Temporary hosted-test observer for HAL air-transport pickup stalls.

    OBSERVER ONLY. This file does not issue/delete waypoints, call land,
    alter AI features, set movement commands, mutate HAL lists, or change
    C.L.A.S.H. ownership. It exists solely to prove where the native SCargo
    air lifecycle stops progressing after embarkation.
*/

if (!isServer) exitWith {};

ITW_CLASH_SCargoAirDiagVersion = 1;
ITW_CLASH_SCargoAirDiagPoll = 1.0;
ITW_CLASH_SCargoAirDiagStallSeconds = 8;
ITW_CLASH_SCargoAirDiagStates = createHashMap;

ITW_CLASH_SCargoAirDiag_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {[_group] call ITW_CLASH_fnc_GroupId};
    str _group
};

ITW_CLASH_SCargoAirDiag_fnc_HQs = {
    private _result = [];
    {
        if (!isNil _x) then {
            private _hq = missionNamespace getVariable [_x,grpNull];
            if (!isNull _hq) then {_result pushBackUnique _hq};
        };
    } forEach ["ITW_CLASH_HALHQ","leaderHQ","leaderHQB"];
    _result
};

ITW_CLASH_SCargoAirDiag_fnc_CurrentWaypoint = {
    params ["_group"];
    private _idx = currentWaypoint _group;
    private _wps = waypoints _group;
    if (_wps isEqualTo [] || {_idx < 0} || {_idx >= count _wps}) exitWith {
        [_idx,"NONE",[],"","",""]
    };
    private _wp = [_group,_idx];
    [
        _idx,
        waypointType _wp,
        waypointPosition _wp,
        waypointBehaviour _wp,
        waypointCombatMode _wp,
        waypointSpeed _wp
    ]
};

ITW_CLASH_SCargoAirDiag_fnc_AssociatedCargo = {
    params ["_carrier"];
    allGroups select {
        !isNull _x
        && {_x getVariable ["CargoChosen",false]}
        && {(_x getVariable ["AssignedCargo" + str _x,objNull]) isEqualTo _carrier}
    }
};

ITW_CLASH_SCargoAirDiag_fnc_Phase = {
    params ["_carrier","_cargoGroups","_wp","_touching","_speed"];
    if (_cargoGroups isEqualTo []) exitWith {"IDLE"};

    private _aliveCargo = [];
    {
        _aliveCargo append ((units _x) select {alive _x});
    } forEach _cargoGroups;

    private _aboard = _aliveCargo select {vehicle _x isEqualTo _carrier};
    private _allAboard = _aliveCargo isNotEqualTo [] && {count _aboard == count _aliveCargo};
    private _wpType = _wp#1;
    private _wpPos = _wp#2;
    private _wpDistance = if (_wpPos isEqualTo []) then {-1} else {_carrier distance2D _wpPos};

    if (_allAboard && {_wpType == "MOVE"} && {_wpDistance > 100}) exitWith {"DELIVERY"};
    if (_allAboard) exitWith {"EMBARKED"};
    if (_touching || {(getPosATL _carrier)#2 < 2} || {abs _speed < 1}) exitWith {"BOARDING"};
    "APPROACH"
};

ITW_CLASH_SCargoAirDiag_fnc_Snapshot = {
    params ["_hq","_group","_carrier"];

    private _pilot = driver _carrier;
    if (isNull _pilot) then {_pilot = assignedDriver _carrier};
    private _wp = [_group] call ITW_CLASH_SCargoAirDiag_fnc_CurrentWaypoint;
    private _wpPos = _wp#2;
    private _wpDistance = if (_wpPos isEqualTo []) then {-1} else {round (_carrier distance2D _wpPos)};
    private _cargoGroups = [_carrier] call ITW_CLASH_SCargoAirDiag_fnc_AssociatedCargo;
    private _touching = isTouchingGround _carrier;
    private _speed = speed _carrier;
    private _phase = [_carrier,_cargoGroups,_wp,_touching,_speed] call ITW_CLASH_SCargoAirDiag_fnc_Phase;

    private _cargoState = _cargoGroups apply {
        private _cg = _x;
        private _alive = (units _cg) select {alive _x};
        [
            [_cg] call ITW_CLASH_SCargoAirDiag_fnc_GroupId,
            _cg getVariable ["CargoChosen",false],
            _cg getVariable ["CargoCheckPending" + str _cg,false],
            count _alive,
            count (_alive select {vehicle _x isEqualTo _carrier})
        ]
    };

    private _actualPassengers = (crew _carrier) select {group _x != _group};
    private _busyName = "Busy" + str _group;
    private _cargoMName = "CargoM" + str _group;

    [
        ["phase",_phase],
        ["hq",[_hq] call ITW_CLASH_SCargoAirDiag_fnc_GroupId],
        ["group",[_group] call ITW_CLASH_SCargoAirDiag_fnc_GroupId],
        ["vehicle",typeOf _carrier],
        ["posATL",getPosATL _carrier],
        ["atl",round ((getPosATL _carrier)#2)],
        ["speed",round _speed],
        ["engineOn",isEngineOn _carrier],
        ["fuel",fuel _carrier],
        ["damage",damage _carrier],
        ["canMove",canMove _carrier],
        ["touchingGround",_touching],
        ["waypoint",_wp],
        ["wpDistance",_wpDistance],
        ["pilot",if (isNull _pilot) then {"<null>"} else {typeOf _pilot}],
        ["pilotCommand",if (isNull _pilot) then {"<null>"} else {currentCommand _pilot}],
        ["pilotReady",if (isNull _pilot) then {false} else {unitReady _pilot}],
        ["pilotExpected",if (isNull _pilot) then {[]} else {expectedDestination _pilot}],
        ["pilotAI",if (isNull _pilot) then {[]} else {[
            _pilot checkAIFeature "TARGET",
            _pilot checkAIFeature "AUTOTARGET",
            _pilot checkAIFeature "MOVE",
            _pilot checkAIFeature "FSM",
            _pilot checkAIFeature "COVER",
            _pilot checkAIFeature "SUPPRESSION"
        ]}],
        ["behaviour",if (isNull _pilot) then {""} else {behaviour _pilot}],
        ["combatBehaviour",if (isNull _pilot) then {""} else {combatBehaviour _pilot}],
        ["combatMode",combatMode _group],
        ["busy",_group getVariable [_busyName,false]],
        ["unable",_group getVariable ["Unable",false]],
        ["cargoM",_group getVariable [_cargoMName,false]],
        ["assignedCargo",count assignedCargo _carrier],
        ["actualPassengers",count _actualPassengers],
        ["cargoGroups",_cargoState],
        ["halLists",[
            ["AirG",_group in (_hq getVariable ["RydHQ_AirG",[]])],
            ["CargoG",_group in (_hq getVariable ["RydHQ_CargoG",[]])],
            ["CargoOnly",_group in (_hq getVariable ["RydHQ_CargoOnly",[]])],
            ["NoAttack",_group in (_hq getVariable ["RydHQ_NoAttack",[]])],
            ["NoRecon",_group in (_hq getVariable ["RydHQ_NoRecon",[]])],
            ["NoDef",_group in (_hq getVariable ["RydHQ_NoDef",[]])]
        ]]
    ]
};

[] spawn {
    scriptName "ITW_CLASH_SCargoAirDiagnostics";

    waitUntil {
        sleep 0.5;
        (missionNamespace getVariable ["ITW_CLASH_HALReady",false])
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    if !(missionNamespace getVariable ["ITW_CLASH_HALReady",false]) exitWith {};

    diag_log format [
        "CLASH SCARGO AIR DIAG | ready | version=%1 observerOnly=true poll=%2 stallSeconds=%3 aiOrder=TARGET,AUTOTARGET,MOVE,FSM,COVER,SUPPRESSION",
        ITW_CLASH_SCargoAirDiagVersion,
        ITW_CLASH_SCargoAirDiagPoll,
        ITW_CLASH_SCargoAirDiagStallSeconds
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_SCargoAirDiagPoll;

        {
            private _hq = _x;
            private _airGroups = +(_hq getVariable ["RydHQ_AirG",[]]);
            private _cargoGroups = +(_hq getVariable ["RydHQ_CargoG",[]]);
            private _cargoOnly = +(_hq getVariable ["RydHQ_CargoOnly",[]]);
            private _candidateGroups = _airGroups select {_x in _cargoGroups || {_x in _cargoOnly}};

            {
                private _group = _x;
                if (isNull _group || {{alive _x} count units _group < 1}) then {continue};

                private _leader = leader _group;
                if (isNull _leader) then {continue};
                private _carrier = assignedVehicle _leader;
                if (isNull _carrier) then {_carrier = vehicle _leader};
                if (isNull _carrier || {!(_carrier isKindOf "Air")}) then {continue};

                private _snapshot = [_hq,_group,_carrier] call ITW_CLASH_SCargoAirDiag_fnc_Snapshot;
                private _phase = (_snapshot#0)#1;
                private _key = str _group;
                private _state = ITW_CLASH_SCargoAirDiagStates getOrDefault [_key,["",-1e10,"",-1e10]];
                _state params ["_lastPhase","_phaseSince","_lastSig","_lastSnapshot"];

                if (_phase != _lastPhase) then {
                    _phaseSince = time;
                    diag_log format ["CLASH SCARGO AIR DIAG | phase | %1",_snapshot];
                };

                private _sig = str [
                    _phase,
                    (_snapshot#11)#1,
                    (_snapshot#12)#1,
                    (_snapshot#16)#1,
                    (_snapshot#17)#1,
                    (_snapshot#24)#1,
                    (_snapshot#25)#1,
                    (_snapshot#26)#1,
                    (_snapshot#27)#1
                ];

                if (_sig != _lastSig || {time - _lastSnapshot >= 5}) then {
                    _lastSig = _sig;
                    _lastSnapshot = time;
                    diag_log format ["CLASH SCARGO AIR DIAG | snapshot | %1",_snapshot];
                };

                private _wp = (_snapshot#12)#1;
                private _wpType = _wp#1;
                private _wpDistance = (_snapshot#13)#1;
                private _touching = (_snapshot#11)#1;
                private _vehSpeed = abs ((_snapshot#7)#1);
                if (
                    _phase == "DELIVERY"
                    && {_wpType == "MOVE"}
                    && {_wpDistance > 100}
                    && {_touching}
                    && {_vehSpeed < 1}
                    && {time - _phaseSince >= ITW_CLASH_SCargoAirDiagStallSeconds}
                ) then {
                    diag_log format ["CLASH SCARGO AIR DIAG | POST-EMBARK-STALLED | heldSeconds=%1 | %2",round (time - _phaseSince),_snapshot];
                };

                ITW_CLASH_SCargoAirDiagStates set [_key,[_phase,_phaseSince,_lastSig,_lastSnapshot]];
            } forEach _candidateGroups;
        } forEach (call ITW_CLASH_SCargoAirDiag_fnc_HQs);
    };
};
