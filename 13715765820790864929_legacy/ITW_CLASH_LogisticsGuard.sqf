#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_LogisticsGuardStarted",false]) exitWith {};

ITW_CLASH_LogisticsGuardStarted = true;
ITW_CLASH_LogisticsHandoffVersion = 4;
ITW_CLASH_WithdrawalArrivalRadius = 150;
ITW_CLASH_WithdrawalWaypointRadius = 100;
ITW_CLASH_PostTransportSettle = 30;

diag_log format [
    "CLASH BOOT | logistics-guard-ready | version=%1 egress=%2 waypoint=%3 settle=%4 symmetricTransportSettle=true reconstitutionDismountReconcile=true unassignLogThrottle=15",
    ITW_CLASH_LogisticsHandoffVersion,
    ITW_CLASH_WithdrawalArrivalRadius,
    ITW_CLASH_WithdrawalWaypointRadius,
    ITW_CLASH_PostTransportSettle
];

while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
    sleep 1;

    // PR #24's transit dispatcher correctly records the live state on the group,
    // but the queue entry can remain stale at waiting-transport. Make the group
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

            // A physically dismounted reconstitution squad can retain Arma's
            // assigned-vehicle relationship after leaving its lift. C.L.A.S.H.
            // correctly rejects assigned vehicle groups, which produced a clean
            // transit arrival but a false reconstitution acknowledgment in the
            // hosted run. Once every survivor is physically on foot, clear that
            // stale assignment before the 10-second transit manager can hand the
            // squad to HAL.
            private _transitUnits = (units _grp) select {alive _x};
            private _transitOnFoot = _transitUnits isNotEqualTo [] && {
                (_transitUnits findIf {vehicle _x != _x}) < 0
            };
            private _assigned = assignedVehicles _grp;
            if (_liveState in ["transport","walking"] && {_transitOnFoot}) then {
                private _managedCargo = -1;
                if (!isNil "ITW_ManagedVehs") then {
                    _managedCargo = ITW_ManagedVehs findIf {
                        count _x > VEHINFO_CARGO_GRPS && {
                            _grp in (_x#VEHINFO_CARGO_GRPS)
                        }
                    };
                };
                if (_assigned isNotEqualTo [] || {_managedCargo >= 0}) then {
                    private _beforeAssigned = count _assigned;
                    private _reconciled = if (!isNil
                        "ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership"
                    ) then {
                        [_grp] call
                            ITW_CLASH_Reconstitution_fnc_ReconcileDismountOwnership
                    } else {
                        {unassignVehicle _x} forEach _transitUnits;
                        [count assignedVehicles _grp,0,true]
                    };
                    _reconciled params [
                        "_afterAssigned","_clearedCargoLinks","_attempted"
                    ];
                    private _nextLog = _grp getVariable [
                        "ITW_CLASH_ReconstitutionUnassignLogAt",0
                    ];
                    if (_attempted && {time >= _nextLog} && {
                        !isNil "ITW_CLASH_fnc_Log"
                    }) then {
                        _grp setVariable [
                            "ITW_CLASH_ReconstitutionUnassignLogAt",time + 15
                        ];
                        ["reconstitution-transport-unassigned",[
                            _entry#1,
                            _entry#4,
                            _liveState,
                            count _transitUnits,
                            _beforeAssigned,
                            _afterAssigned,
                            _clearedCargoLinks
                        ]] call ITW_CLASH_fnc_Log;
                    };
                };
            };

            // Only infer transport from the live vehicle when both cached and
            // group state are still the stale waiting state. If the transit
            // manager has already changed the group to walking after an early
            // dismount, the surviving vehicle must not force it back to transport.
            if (_cachedState isEqualTo "waiting-transport" && {
                _liveState isEqualTo "waiting-transport" && {
                    !isNull _liveVehicle && {alive _liveVehicle}
                }
            }) then {
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

    // Keep the physical foot-withdrawal waypoint stricter than the canonical
    // 150 m rear-absorption envelope. The canonical order creates a waypoint
    // within a 35 m placement radius; pinning it back to the exact egress point
    // with a 100 m completion radius prevents Arma from declaring the waypoint
    // complete just outside the economic absorption boundary.
    if (!isNil "ITW_CLASH_Withdrawals") then {
        {
            private _id = _x;
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
            if (_entry isEqualTo [] || {count _entry < 9}) then {continue};

            private _grp = _entry#0;
            private _destination = _entry#5;
            if (isNull _grp || {_destination isEqualTo []}) then {continue};
            if ((_grp getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") then {continue};
            if ((_grp getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") then {continue};

            private _wps = waypoints _grp;
            if (_wps isEqualTo []) then {continue};
            private _wp = _wps#-1;
            private _wpPos = waypointPosition _wp;
            private _wpRadius = waypointCompletionRadius _wp;
            if (_wpPos distance2D _destination > 1 || {
                abs (_wpRadius - ITW_CLASH_WithdrawalWaypointRadius) > 1
            }) then {
                _wp setWaypointPosition [_destination,0];
                _wp setWaypointCompletionRadius ITW_CLASH_WithdrawalWaypointRadius;
                if !(_grp getVariable ["ITW_CLASH_WithdrawalWaypointHardened",false]) then {
                    _grp setVariable ["ITW_CLASH_WithdrawalWaypointHardened",true];
                    if (!isNil "ITW_CLASH_fnc_Log") then {
                        ["withdrawal-egress-waypoint-hardened",[
                            _id,
                            _grp getVariable ["ITW_CLASH_Lineage",_id],
                            ITW_CLASH_WithdrawalWaypointRadius,
                            ITW_CLASH_WithdrawalArrivalRadius
                        ]] call ITW_CLASH_fnc_Log;
                    };
                };
            };
        } forEach +(keys ITW_CLASH_Withdrawals);
    };

    // Ground MEDEVAC intentionally doStops the driver at pickup so infantry can
    // board safely. Hosted field tests showed that the individual stop order can
    // survive the subsequent RTB group waypoint. If an RTB vehicle is still
    // essentially stationary away from its current route target, reissue the
    // driver's physical move order without teleporting or changing the route.
    if (!isNil "ITW_CLASH_GroundMEDEVAC_Active") then {
        {
            private _id = _x;
            private _active = ITW_CLASH_GroundMEDEVAC_Active getOrDefault [_id,[]];
            if (_active isEqualTo [] || {count _active < 7}) then {continue};
            _active params ["_grp","_veh","_crewGroup"];
            if (isNull _grp || {isNull _veh} || {!alive _veh} || {isNull _crewGroup}) then {continue};
            if ((_grp getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "rtb") then {continue};

            private _driver = driver _veh;
            if (isNull _driver) then {continue};
            private _wps = waypoints _crewGroup;
            if (_wps isEqualTo []) then {continue};
            private _target = waypointPosition (_wps#-1);
            if (_veh distance2D _target <= 100 || {abs speed _veh >= 2}) then {continue};

            private _nextUnstick = _veh getVariable ["ITW_CLASH_GroundMEDEVAC_UnstickAt",0];
            if (time < _nextUnstick) then {continue};
            _veh setVariable ["ITW_CLASH_GroundMEDEVAC_UnstickAt",time + 10];
            _driver doMove _target;
            if (!isNil "ITW_CLASH_fnc_Log") then {
                ["medevac-rtb-driver-unstick",[
                    _id,
                    _grp getVariable ["ITW_CLASH_Lineage",_id],
                    typeOf _veh,
                    round (_veh distance2D _target)
                ]] call ITW_CLASH_fnc_Log;
            };
        } forEach +(keys ITW_CLASH_GroundMEDEVAC_Active);
    };

    // Freshly delivered normal Impasse infantry should not be adopted by HAL
    // on the same frame their transport finishes unloading. Watch for the
    // physical in-vehicle -> on-foot transition, then use C.L.A.S.H.'s existing
    // re-eligibility cooldown while Impasse finishes its own cargo bookkeeping.
    private _supportedSides = [];
    if (!isNil "ITW_PlayerSide") then {_supportedSides pushBackUnique ITW_PlayerSide};
    if (!isNil "ITW_EnemySide") then {_supportedSides pushBackUnique ITW_EnemySide};
    if (_supportedSides isNotEqualTo []) then {
        {
            private _grp = _x;
            if (isNull _grp || {!(side _grp in _supportedSides)}) then {continue};
            if (((units _grp) findIf {isPlayer _x}) >= 0) then {continue};
            if (!isNil "ITW_CLASH_fnc_IsCommanderGroup" && {
                [_grp] call ITW_CLASH_fnc_IsCommanderGroup
            }) then {continue};
            if (_grp getVariable ["ITW_CLASH_ReconstitutionTransit",false]) then {continue};
            if (_grp getVariable ["ITW_CLASH_Managed",false]) then {continue};
            if (_grp getVariable ["ITW_CLASH_DualHALManaged",false]) then {continue};
            if (_grp getVariable ["ITW_CLASH_Withdrawing",false]) then {continue};

            private _aliveUnits = (units _grp) select {alive _x};
            if (_aliveUnits isEqualTo []) then {continue};

            private _inVehicle = _aliveUnits findIf {vehicle _x != _x} >= 0;
            if (_inVehicle) then {
                _grp setVariable ["ITW_CLASH_TransportSeen",true];
            } else {
                if (_grp getVariable ["ITW_CLASH_TransportSeen",false]) then {
                    _grp setVariable ["ITW_CLASH_TransportSeen",false];
                    private _reeligibleAt = (
                        time + ITW_CLASH_PostTransportSettle
                    ) max (_grp getVariable ["ITW_CLASH_ReeligibleAt",0]);
                    _grp setVariable ["ITW_CLASH_ReeligibleAt",_reeligibleAt];

                    if (!isNil "ITW_CLASH_fnc_Log") then {
                        ["transport-handoff-settle",[
                            str _grp,
                            VAR_GET_OBJ_IDX(_grp),
                            ITW_CLASH_PostTransportSettle,
                            count _aliveUnits,
                            side _grp
                        ]] call ITW_CLASH_fnc_Log;
                    };

                    [_grp,_reeligibleAt] spawn {
                        params ["_grp","_reeligibleAt"];
                        private _delay = (_reeligibleAt - time) max 0;
                        sleep _delay;
                        if (isNull _grp) exitWith {};
                        if ((_grp getVariable ["ITW_CLASH_ReeligibleAt",0]) > time) exitWith {};
                        if (!isNil "ITW_CLASH_fnc_Log") then {
                            ["transport-handoff-ready",[
                                str _grp,
                                VAR_GET_OBJ_IDX(_grp),
                                count ((units _grp) select {alive _x}),
                                side _grp
                            ]] call ITW_CLASH_fnc_Log;
                        };
                    };
                };
            };
        } forEach allGroups;
    };

    // Baseline Impasse gives completed land transports an RTB waypoint at their
    // spawn/support point (radius 220), then another MOVE exactly 1 km beyond it
    // (radius 210). Prune only that distinctive final pair so KamAZ-style
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