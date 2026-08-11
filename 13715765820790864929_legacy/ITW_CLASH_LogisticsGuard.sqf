#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_LogisticsGuardStarted",false]) exitWith {};

ITW_CLASH_LogisticsGuardStarted = true;
ITW_CLASH_LogisticsHandoffVersion = 1;
ITW_CLASH_WithdrawalArrivalRadius = 150;
ITW_CLASH_PostTransportSettle = 30;

diag_log format [
    "CLASH BOOT | logistics-guard-ready | version=%1 egress=%2 settle=%3",
    ITW_CLASH_LogisticsHandoffVersion,
    ITW_CLASH_WithdrawalArrivalRadius,
    ITW_CLASH_PostTransportSettle
];

while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
    sleep 1;

    // PR #24's transit dispatcher correctly records the live state on the group,
    // but the queue entry can remain stale at waiting-transport.  Make the group
    // variable authoritative so one RC request can own at most one live lift.
    if (!isNil "ITW_AtkReconstitutionTransits") then {
        for "_i" from ((count ITW_AtkReconstitutionTransits) - 1) to 0 step -1 do {
            private _entry = ITW_AtkReconstitutionTransits#_i;
            if (count _entry < 9) then {continue};

            private _grp = _entry#0;
            if (isNull _grp) then {continue};

            private _cachedState = _entry#8;
            private _liveState = _grp getVariable [
                "ITW_CLASH_TransitState",
                _cachedState
            ];
            private _liveVehicle = _grp getVariable [
                "ITW_CLASH_TransitVehicle",
                objNull
            ];
            if (!isNull _liveVehicle && {alive _liveVehicle}) then {
                _liveState = "transport";
                _grp setVariable ["ITW_CLASH_TransitState",_liveState];
            };

            if (_cachedState isNotEqualTo _liveState) then {
                _entry set [8,_liveState];
                ITW_AtkReconstitutionTransits set [_i,_entry];
                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["reconstitution-transit-state-synced",[
                        _entry#1,
                        _entry#4,
                        _cachedState,
                        _liveState,
                        !isNull _liveVehicle && {alive _liveVehicle}
                    ]] call ITW_CLASH_fnc_Log;
                };
            };
        };
    };

    // Freshly delivered normal Impasse infantry should not be adopted by HAL
    // on the same frame their transport finishes unloading.  Watch for the
    // physical in-vehicle -> on-foot transition and hold the group in Impasse's
    // existing spawn-transition state for a short settling window.
    if (!isNil "ITW_EnemySide") then {
        {
            private _grp = _x;
            if (isNull _grp || {side _grp != ITW_EnemySide}) then {continue};
            if (_grp getVariable ["ITW_CLASH_ReconstitutionTransit",false]) then {continue};
            if (_grp getVariable ["ITW_CLASH_Managed",false]) then {continue};
            if (_grp getVariable ["ITW_CLASH_Withdrawing",false]) then {continue};

            private _aliveUnits = (units _grp) select {alive _x};
            if (_aliveUnits isEqualTo []) then {continue};

            private _inVehicle = _aliveUnits findIf {vehicle _x != _x} >= 0;
            if (_inVehicle) then {
                _grp setVariable ["ITW_CLASH_TransportSeen",true];
            } else {
                if (_grp getVariable ["ITW_CLASH_TransportSeen",false]) then {
                    _grp setVariable ["ITW_CLASH_TransportSeen",false];
                    private _settleUntil = time + ITW_CLASH_PostTransportSettle;
                    _grp setVariable ["ITW_CLASH_PostTransportUntil",_settleUntil];
                    _grp setVariable ["itwInitGrp",true,true];

                    if (!isNil "ITW_CLASH_fnc_Log") then {
                        ["transport-handoff-settle",[
                            str _grp,
                            VAR_GET_OBJ_IDX(_grp),
                            ITW_CLASH_PostTransportSettle,
                            count _aliveUnits
                        ]] call ITW_CLASH_fnc_Log;
                    };

                    [_grp,_settleUntil] spawn {
                        params ["_grp","_settleUntil"];
                        sleep ITW_CLASH_PostTransportSettle;
                        if (isNull _grp) exitWith {};
                        if ((_grp getVariable ["ITW_CLASH_PostTransportUntil",0]) > time) exitWith {};

                        _grp setVariable ["ITW_CLASH_PostTransportUntil",nil];
                        _grp setVariable ["itwInitGrp",nil,true];
                        if (!isNil "ITW_CLASH_fnc_Log") then {
                            ["transport-handoff-ready",[
                                str _grp,
                                VAR_GET_OBJ_IDX(_grp),
                                count ((units _grp) select {alive _x})
                            ]] call ITW_CLASH_fnc_Log;
                        };
                    };
                };
            };
        } forEach allGroups;
    };

    // Baseline Impasse gives completed land transports an RTB waypoint at their
    // spawn/support point (radius 220), then another MOVE exactly 1 km beyond it
    // (radius 210).  Prune only that distinctive final pair so KamAZ-style
    // transports terminate at the logistics node instead of wandering into a
    // rear-area town before cleanup.
    {
        private _veh = _x;
        if (!alive _veh || {!(_veh isKindOf "LandVehicle")}) then {continue};
        if ((_veh getVariable ["ITW_VehDef",[]]) isEqualTo []) then {continue};

        private _driver = driver _veh;
        if (isNull _driver) then {continue};
        private _grp = group _driver;
        if (isNull _grp) then {continue};

        private _wps = waypoints _grp;
        private _wpCount = count _wps;
        if (_wpCount < 2) then {continue};

        private _rtbWp = _wps#(_wpCount - 2);
        private _overshootWp = _wps#(_wpCount - 1);
        if ((waypointType _rtbWp) isNotEqualTo "MOVE") then {continue};
        if ((waypointType _overshootWp) isNotEqualTo "MOVE") then {continue};

        private _rtbRadius = waypointCompletionRadius _rtbWp;
        private _overshootRadius = waypointCompletionRadius _overshootWp;
        if (abs (_rtbRadius - 220) > 1) then {continue};
        if (abs (_overshootRadius - 210) > 1) then {continue};

        private _rtbPos = waypointPosition _rtbWp;
        private _overshootPos = waypointPosition _overshootWp;
        private _legDistance = _rtbPos distance2D _overshootPos;
        if (_legDistance < 900 || {_legDistance > 1100}) then {continue};

        deleteWaypoint _overshootWp;
        if (!isNil "ITW_CLASH_fnc_Log") then {
            ["transport-rtb-overshoot-pruned",[
                typeOf _veh,
                str _grp,
                round _legDistance,
                round (_veh distance2D _rtbPos)
            ]] call ITW_CLASH_fnc_Log;
        };
    } forEach vehicles;
};

ITW_CLASH_LogisticsGuardStarted = false;
diag_log "CLASH BOOT | logistics-guard-stopped";
