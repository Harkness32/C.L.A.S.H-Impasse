#include "defines.hpp"

if (!isServer) exitWith {false};
if (isNil "ITW_AllyLoadIntoVehManager" || {isNil "ITW_AllyLoadGrpIntoVeh"}) exitWith {false};

ITW_CLASH_PlayerTransport_fnc_NativeLoadIntoVehManager = ITW_AllyLoadIntoVehManager;
ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh = ITW_AllyLoadGrpIntoVeh;

/*
    Native Impasse proximity ferry selection is retained as the physical pickup
    scanner, but it is no longer a dispatcher. For ordinary friendly infantry a
    successful C.L.A.S.H. Acquire is required before ITW_getInState or waypoint
    state is touched. Standing itwDelivery squads remain a native Impasse case.
*/
ITW_AllyLoadIntoVehManager = {
    scriptName "ITW_AllyLoadIntoVehManager_CLASH";
    while {!ITW_GameOver} do {
        {
            private _veh = _x;
            private _pilot = currentPilot _veh;
            if (!isPlayer _pilot && {units group _pilot findIf {isPlayer _x} == -1}) then {continue};
            if (side _pilot != ITW_PlayerSide) then {continue};
            if (speed _veh > 5) then {continue};
            private _vPos = getPosATL _veh;
            private _isWater = surfaceIsWater _vPos;
            if (_isWater && {_vPos#2 > 4.5}) then {continue};
            if (!_isWater && {!(isTouchingGround _veh) && {_vPos#2 > 2}}) then {continue};
            if (!canMove _veh || {fuel _veh == 0}) then {continue};
            if (isPlayer _pilot && {_veh getVariable ["ITW_BlockAllyEntry",false]}) then {continue};
            if !(_veh getVariable ["ITW_reservedGroups",[]] isEqualTo []) then {continue};
            if (_veh getVariable ["ITW_AllyEntryTimeout",0] > time) then {continue};
            if (_veh getVariable ["ITW_AllyCrewEject",false]) then {continue};
            if (_veh getVariable ["SKL_BFC_running",false]) then {continue};

            private _emptySeats = if (_veh getVariable ["ITW_BlockAllyCrew",true]) then {
                {isNull (_x#5) && {_x#2 >= 0}} count fullCrew [_veh,"",true]
            } else {
                {isNull (_x#5) && {_x#2 >= 0 || {!(_x#3 isEqualTo [])}}} count fullCrew [_veh,"",true]
            };
            if (_emptySeats == 0) then {continue};

            if (isPlayer _pilot && {speed _veh > 6 && {
                _veh getVariable ["ITW_ForceAllyEntry",false] && {ITW_ELEVATION(_vPos) > 6}
            }}) then {
                _veh setVariable ["ITW_ForceAllyEntry",false,true];
            };

            private _objType = if (isPlayer _pilot && {
                _veh getVariable ["ITW_ForceAllyEntry",false]
            }) then {ITW_OWNER_ENEMY} else {ITW_OWNER_CONTESTED};
            private _closestObj = [_vPos,ITW_OWNER_CONTESTED,_objType] call ITW_ObjGetNearest;
            if (_closestObj#ITW_OBJ_POS distance _veh < 1000) then {continue};

            private _onFootAllies = ITW_AllyGroups select {
                private _grp = _x;
                private _leader = leader _grp;
                !(_grp getVariable ["ITW_Garrison",false]) &&
                {!(_grp getVariable ["itwInitGrp",false]) &&
                {vehicle _leader == _leader &&
                {_leader distance _veh < 250 &&
                {isNull getAttackTarget _leader &&
                {!fleeing _leader &&
                {_grp getVariable ["ITW_getInState",-1] == -1}}}}}}
            } apply {[leader _x distance _veh,_x]};
            if (_onFootAllies isEqualTo []) then {continue};

            _onFootAllies sort true;
            private _groupsToLoad = [];
            private _halContractSelected = false;
            {
                if (_halContractSelected) then {continue};
                private _grp = _x#1;
                private _grpSize = count units _grp;
                if (_grpSize > _emptySeats) then {continue};

                private _authorized = true;
                if (!isNil "ITW_CLASH_PlayerTransport_fnc_Acquire") then {
                    _authorized = [_grp,_veh,"player-ferry-boarding"] call
                        ITW_CLASH_PlayerTransport_fnc_Acquire;
                };
                if (!_authorized) then {continue};

                private _halContract = !(_grp getVariable ["itwDelivery",false]) && {
                    ([_grp] call ITW_CLASH_PlayerTransport_fnc_GetContract) isNotEqualTo createHashMap
                };
                _emptySeats = _emptySeats - _grpSize;
                _groupsToLoad pushBack _grp;
                _grp setVariable ["ITW_getInState",0];

                if (_halContract) then {
                    // Preserve HAL objective/task state. The physical executor
                    // uses direct unit commands only; it does not delete HAL's
                    // cargo mission waypoint or rewrite objective affinity.
                    _halContractSelected = true;
                } else {
                    VAR_SET_OBJ_IDX(_grp,_closestObj#ITW_OBJ_INDEX);
                    ITW_DELETE_WAYPOINTS(_grp);
                };
            } forEach _onFootAllies;

            if !(_groupsToLoad isEqualTo []) then {
                _veh setVariable ["ITW_reservedGroups",_groupsToLoad];
                [_veh,_groupsToLoad] spawn ITW_AllyLoadGrpIntoVeh;
            };
        } forEach vehicles;
        sleep 8;
        while {LV_PAUSE} do {sleep 5};
    };
};

/*
    HAL-contract ferry executor. Native Impasse remains untouched for standing
    itwDelivery groups. For a HAL contract, this executor owns only the physical
    board/carry/unload sequence; HAL's mission waypoint and objective affinity are
    preserved from pickup through delivery.
*/
ITW_CLASH_PlayerTransport_fnc_ExecuteHALContract = {
    params ["_veh","_grp"];
    if (isNull _veh || {isNull _grp}) exitWith {false};
    private _reportProgress = isPlayer currentPilot _veh;
    private _units = units _grp select {ALIVE(_x)};
    if (_units isEqualTo []) exitWith {false};

    _veh setVariable ["ITW_groupCntActive",(_veh getVariable ["ITW_groupCntActive",0]) + 1];
    if (_reportProgress) then {
        private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
        ["bStart",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
        [leader _grp,localize "STR_ITW_ALLY_WeAreBoarding"] remoteExec ["sideChat",currentPilot _veh];
    };

    private _leader = leader _grp;
    private _vPos = getPosATL _veh;
    {
        if (_x distance _leader > 200) then {_x setPosATL (getPosATL _leader)};
        _x setDamage 0;
        _x doMove _vPos;
        [_x,_veh] call ITW_AllyOrderGetIn;
    } forEach _units;
    [_units,true] remoteExec ["orderGetIn",_leader];
    _grp setVariable ["ITW_ExitVehicle",false];

    private _timeout = time + 40;
    waitUntil {
        sleep 1;
        if (time > _timeout) then {
            {
                if (alive _x && {vehicle _x == _x}) then {
                    [_x,_veh,true] call ITW_AllyOrderGetIn;
                };
            } forEach _units;
        };
        isNull _veh || {!canMove _veh} || {fuel _veh == 0} ||
        {isNull currentPilot _veh} || {_grp getVariable ["ITW_ExitVehicle",false]} ||
        {{ALIVE(_x) && {vehicle _x != _veh}} count _units == 0} || {time > _timeout + 15}
    };

    private _loaded = !isNull _veh && {canMove _veh} && {fuel _veh > 0} && {
        !isNull currentPilot _veh && {vehicle _leader == _veh}
    };
    if (!_loaded) exitWith {
        _grp leaveVehicle _veh;
        {[_x] remoteExec ["unassignVehicle",_x]} forEach _units;
        _grp setVariable ["ITW_getInState",-1];
        _veh setVariable ["ITW_reservedGroups",nil];
        _veh setVariable ["ITW_groupCntActive",((_veh getVariable ["ITW_groupCntActive",1]) - 1) max 0];
        [_grp,"player-ferry-boarding-failed"] call ITW_CLASH_PlayerTransport_fnc_Release;
        false
    };

    _grp setVariable ["ITW_getInState",1];
    _veh setVariable ["ITW_reservedGroups",nil];
    _veh setVariable ["ITW_transportGroups",[_grp],true];
    if (_reportProgress) then {
        private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
        ["bEnd",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
        if (!isNull driver _veh) then {
            [leader _grp,localize "STR_ITW_ALLY_WeAreIn"] remoteExec ["sideChat",driver _veh];
        };
    };
    [_grp,_veh] call ITW_CLASH_PlayerTransport_fnc_MarkEmbarked;

    private _destination = [_grp,_veh] call
        ITW_CLASH_PlayerTransport_fnc_GetContractDestination;
    private _arrived = false;
    private _aborted = false;
    while {!_arrived && {!_aborted}} do {
        sleep 1;
        if (isNull _veh || {!alive _veh} || {!canMove _veh} || {fuel _veh == 0} || {
            isNull currentPilot _veh
        }) then {
            _aborted = true;
        } else {
            _destination = [_grp,_veh] call
                ITW_CLASH_PlayerTransport_fnc_GetContractDestination;
            if (_destination isEqualTo []) then {
                _aborted = true;
            } else {
                private _low = isTouchingGround _veh || {ITW_ELEVATION_LT(_veh,2)};
                _arrived = (_veh distance2D _destination) <= ITW_CLASH_PlayerTransportDropRadius && {
                    _low && {speed _veh < 5}
                };
            };
        };
    };

    if (_aborted) exitWith {
        _grp setVariable ["ITW_getInState",2];
        _veh setVariable ["ITW_transportGroups",nil,true];
        _veh setVariable ["ITW_groupCntActive",((_veh getVariable ["ITW_groupCntActive",1]) - 1) max 0];
        [_grp,"player-ferry-carrier-lost"] call ITW_CLASH_PlayerTransport_fnc_Release;
        false
    };

    _grp setVariable ["ITW_ExitVehicle",true];
    _grp setVariable ["ITW_getInState",2];
    _grp setVariable ["ITW_CLASH_TransportPhysicalUnloadPending",true];
    if (_reportProgress) then {
        private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
        ["dStart",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
    };

    {
        [_x] remoteExec ["unassignVehicle",_x];
        moveOut _x;
        sleep 1;
    } forEach _units;
    [_units,false] remoteExec ["orderGetIn",_leader];
    [_units,_leader] remoteExec ["doFollow",_leader];
    sleep 1;

    _veh setVariable ["ITW_transportGroups",nil,true];
    _veh setVariable ["ITW_pickupSuccess",nil];
    _veh setVariable ["reported",nil];
    _veh setVariable ["ITW_groupCntActive",((_veh getVariable ["ITW_groupCntActive",1]) - 1) max 0];
    _grp setVariable ["ITW_CLASH_TransportPhysicalUnloadPending",nil];
    _grp setVariable ["ITW_getInState",-1];

    if (_reportProgress && {canMove _veh && {fuel _veh > 0}}) then {
        private _nearbyPlayers = allPlayers select {_veh distance _x < 20};
        ["dEnd",_veh] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];
        if (!isNull driver _veh) then {
            [leader _grp,localize "STR_ITW_ALLY_WereAllOut"] remoteExec ["sideChat",driver _veh];
        };
    };

    [_grp,"player-ferry-delivered"] call ITW_CLASH_PlayerTransport_fnc_Release;
    true
};

ITW_AllyLoadGrpIntoVeh = {
    params ["_veh","_groupsToLoad"];
    private _contractGroups = _groupsToLoad select {
        !(_x getVariable ["itwDelivery",false]) && {
            ([_x,_veh] call ITW_CLASH_PlayerTransport_fnc_GetContractDestination) isNotEqualTo []
        }
    };
    if (_contractGroups isEqualTo []) exitWith {
        _this call ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh
    };

    // Contract selection is intentionally one cargo group per player carrier.
    private _grp = _contractGroups#0;
    [_veh,_grp] call ITW_CLASH_PlayerTransport_fnc_ExecuteHALContract
};

ITW_CLASH_AllyTransportFinalizationWindow = false;
private _managerFinal = ["ITW_AllyLoadIntoVehManager"] call SKL_fnc_CompileFinal;
private _loadFinal = ["ITW_AllyLoadGrpIntoVeh"] call SKL_fnc_CompileFinal;

diag_log format [
    "CLASH BOOT | player-transport-native-bridge-ready | manager=%1 loader=%2 contractGate=true exactContractDestination=true stockRadio=true",
    _managerFinal,_loadFinal
];
_managerFinal && _loadFinal