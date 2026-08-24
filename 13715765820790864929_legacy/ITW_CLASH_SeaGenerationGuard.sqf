#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SeaGenerationGuardStarted",false]) exitWith {true};
ITW_CLASH_SeaGenerationGuardStarted = true;
ITW_CLASH_SeaGenerationGuardVersion = 3;
ITW_CLASH_SeaGenerationGuardReady = false;
ITW_CLASH_SeaGuardMaxRelocation = missionNamespace getVariable [
    "ITW_CLASH_SeaGuardMaxRelocation",1500
];

// ServiceLifecycle is loaded immediately before this file. Install the canonical
// explicit-lease authority layer now, before SeaGuard becomes the outermost
// StageFieldVehicle wrapper.
if (fileExists "ITW_CLASH_ServiceAuthority.sqf") then {
    private _serviceAuthorityLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_ServiceAuthority.sqf";
    if !(_serviceAuthorityLoaded isEqualTo true) then {
        diag_log "CLASH BOOT | WARNING | service-authority-load-failed | lifecycle-v1 retained";
    };
} else {
    diag_log "CLASH BOOT | WARNING | service-authority-missing | lifecycle-v1 retained";
};

if (
    missionNamespace getVariable ["ITW_CLASH_ServiceAuthorityReady",false]
    && {fileExists "ITW_CLASH_ServiceStability.sqf"}
) then {
    private _serviceStabilityLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_ServiceStability.sqf";
    if !(_serviceStabilityLoaded isEqualTo true) then {
        diag_log "CLASH BOOT | WARNING | service-stability-load-failed | authority-only service behavior retained";
    };
} else {
    diag_log "CLASH BOOT | WARNING | service-stability-skipped | authority unavailable or file missing";
};

// Execution quarantine binds only after HAL exposes its Go* tactical functions.
// The guard script waits for that runtime surface, so it can be launched here
// without delaying SeaGuard's synchronous staging wrapper installation.
if (
    missionNamespace getVariable ["ITW_CLASH_ServiceStabilityReady",false]
    && {fileExists "ITW_CLASH_ServiceExecutionGuards.sqf"}
) then {
    [] execVM "ITW_CLASH_ServiceExecutionGuards.sqf";
} else {
    diag_log "CLASH BOOT | WARNING | service-execution-guards-skipped | stability unavailable or file missing";
};

ITW_CLASH_SeaGuard_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["sea-guard-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH SEA GUARD | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_SeaGuard_fnc_AllSeaPoints = {
    private _points = [];
    if (isNil "ITW_SeaPoints") exitWith {_points};
    {
        if (_x isEqualType []) then {
            {
                if (_x isEqualType [] && {count _x >= 2}) then {
                    private _position = +_x;
                    if (count _position < 3) then {_position pushBack 0};
                    if (surfaceIsWater _position) then {
                        _points pushBack _position;
                    };
                };
            } forEach _x;
        };
    } forEach ITW_SeaPoints;
    _points
};

ITW_CLASH_SeaGuard_fnc_SurfacePoint = {
    params ["_position"];
    if !(_position isEqualType [] && {count _position >= 2}) exitWith {[]};
    [_position#0,_position#1,0]
};

ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition = {
    params [["_preferred",[]],["_fallback",[]]];

    private _reference = if (_preferred isNotEqualTo []) then {+_preferred} else {+_fallback};
    if (_reference isEqualTo []) exitWith {[]};
    if (count _reference < 3) then {_reference pushBack 0};

    if (_preferred isNotEqualTo []) then {
        private _position = +_preferred;
        if (count _position < 3) then {_position pushBack 0};
        if (surfaceIsWater _position) exitWith {
            [_position] call ITW_CLASH_SeaGuard_fnc_SurfacePoint
        };
    };
    if (_fallback isNotEqualTo []) then {
        private _position = +_fallback;
        if (count _position < 3) then {_position pushBack 0};
        if (surfaceIsWater _position && {
            _position distance2D _reference <= ITW_CLASH_SeaGuardMaxRelocation
        }) exitWith {
            [_position] call ITW_CLASH_SeaGuard_fnc_SurfacePoint
        };
    };

    private _points = call ITW_CLASH_SeaGuard_fnc_AllSeaPoints;
    _points = _points select {
        _x distance2D _reference <= ITW_CLASH_SeaGuardMaxRelocation
    };
    if (_points isEqualTo []) exitWith {[]};
    private _ordered = [_points,[_reference],{_x distance2D _input0},"ASCEND"] call BIS_fnc_sortBy;
    [_ordered#0] call ITW_CLASH_SeaGuard_fnc_SurfacePoint
};

ITW_CLASH_SeaGuard_fnc_EnsureWater = {
    params ["_veh",["_preferred",[]],["_source","unknown"]];
    if (isNull _veh) exitWith {false};
    if !(_veh isKindOf "Ship") exitWith {true};

    private _current = getPosATL _veh;
    private _reference = if (_preferred isNotEqualTo []) then {+_preferred} else {+_current};
    private _water = [_preferred,_current] call ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition;
    if (_water isEqualTo []) exitWith {
        private _nearestDistance = -1;
        private _points = call ITW_CLASH_SeaGuard_fnc_AllSeaPoints;
        if (_points isNotEqualTo [] && {_reference isNotEqualTo []}) then {
            private _ordered = [_points,[_reference],{_x distance2D _input0},"ASCEND"] call BIS_fnc_sortBy;
            _nearestDistance = round ((_ordered#0) distance2D _reference);
        };
        [if (_nearestDistance > ITW_CLASH_SeaGuardMaxRelocation) then {
            "sea-node-too-far"
        } else {
            "no-local-water-node"
        },[
            typeOf _veh,_source,_preferred,_current,
            ITW_CLASH_SeaGuardMaxRelocation,_nearestDistance
        ]] call ITW_CLASH_SeaGuard_fnc_Log;
        false
    };

    private _from = getPosATL _veh;
    private _distance = _reference distance2D _water;
    // ASL z=0 is the water surface. ATL z=0 over water is seabed-relative and
    // was the source of submerged service boats in v1.
    _veh setPosASL _water;
    _veh setVectorUp (surfaceNormal (getPosATL _veh));
    if (_from distance2D (getPosATL _veh) > 2 || {abs ((getPosASL _veh)#2) > 1}) then {
        ["relocated",[
            typeOf _veh,_source,_from,getPosATL _veh,round _distance,"ASL-surface"
        ]] call ITW_CLASH_SeaGuard_fnc_Log;
    };
    surfaceIsWater (getPosATL _veh) && {
        _distance <= ITW_CLASH_SeaGuardMaxRelocation || {
            _preferred isNotEqualTo [] && {surfaceIsWater _preferred}
        }
    }
};

// Generic Checkbook/ForceGeneration guard. Apply before the current registration
// stack so every downstream tracker and service-home record sees a valid water
// position. A ship with no bounded water node is rejected before billing occurs.
if (!isNil "ITW_CLASH_Generation_fnc_RegisterAsset") then {
    ITW_CLASH_SeaGuard_fnc_RegisterAssetBase = ITW_CLASH_Generation_fnc_RegisterAsset;
    ITW_CLASH_Generation_fnc_RegisterAsset = {
        private _veh = _this param [0,objNull];
        if (!isNull _veh && {_veh isKindOf "Ship"}) then {
            if !([_veh,[],"generated-asset"] call ITW_CLASH_SeaGuard_fnc_EnsureWater) exitWith {false};
        };
        _this call ITW_CLASH_SeaGuard_fnc_RegisterAssetBase
    };
};

// Preserve the native ship position as the preferred local reference. Generic
// Dual-HAL staging may temporarily move the vehicle; the outer guard restores a
// valid local water-surface position or rejects the entire formation atomically.
if (!isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle") then {
    ITW_CLASH_SeaGuard_fnc_StageFieldVehicleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
    ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
        private _vehInfo = _this param [0,[]];
        private _veh = if (_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_VEH}) then {
            _vehInfo#VEHINFO_VEH
        } else {objNull};
        private _original = if (!isNull _veh && {_veh isKindOf "Ship"}) then {
            getPosATL _veh
        } else {[]};

        private _result = _this call ITW_CLASH_SeaGuard_fnc_StageFieldVehicleBase;
        if (!_result || {isNull _veh} || {!(_veh isKindOf "Ship")}) exitWith {_result};

        if !([_veh,_original,"impasse-handoff"] call ITW_CLASH_SeaGuard_fnc_EnsureWater) exitWith {
            private _group = group driver _veh;
            private _class = typeOf _veh;
            private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
            if (!isNil "ITW_CLASH_ServiceAuthority_fnc_ClearLease") then {
                [_veh,_group,"sea-handoff-rejected"] call ITW_CLASH_ServiceAuthority_fnc_ClearLease;
            };
            // Rejected formation is a real failed physical spawn, never a
            // successful service retirement. Delete crew and hull together so
            // a failed boat cannot manufacture stranded infantry.
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _group) then {
                {deleteVehicle _x} forEach units _group;
                if (units _group isEqualTo []) then {deleteGroup _group};
            };
            ["handoff-rejected",[
                _class,_original,"no-bounded-sea-position",_poolId,
                ITW_CLASH_SeaGuardMaxRelocation
            ]] call ITW_CLASH_SeaGuard_fnc_Log;
            false
        };

        // SeaGuard owns only physical water projection. The service-home
        // resolver owns home selection and RTB progress. Record the corrected
        // physical origin only for a live DEPLOYED entry; never rewrite home,
        // ITW_CLASH_ServiceHome, lastDistance, or any RTB watchdog state here.
        if (!isNil "ITW_CLASH_ServicePool") then {
            private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
            if (_poolId isNotEqualTo "" && {!isNil "ITW_CLASH_Service_fnc_FindEntry"}) then {
                private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
                if (_index >= 0 && {_index < count ITW_CLASH_ServicePool}) then {
                    private _entry = ITW_CLASH_ServicePool#_index;
                    if ((_entry getOrDefault ["state",""]) == "DEPLOYED") then {
                        _entry set ["deploymentOrigin",getPosATL _veh];
                        ITW_CLASH_ServicePool set [_index,_entry];
                        ["deployment-origin-refreshed",[
                            typeOf _veh,_poolId,getPosATL _veh,"projection-only"
                        ]] call ITW_CLASH_SeaGuard_fnc_Log;
                    };
                };
            };
        };
        true
    };
};

ITW_CLASH_SeaGenerationGuardReady = true;
diag_log format [
    "CLASH BOOT | sea-generation-guard-ready | version=%1 boundedRelocation=%2 aslSurface=true atomicReject=true serviceAuthority=%3 serviceStability=%4 executionGuardsScheduled=true projectionOnly=true serviceHomeWrites=false",
    ITW_CLASH_SeaGenerationGuardVersion,
    ITW_CLASH_SeaGuardMaxRelocation,
    missionNamespace getVariable ["ITW_CLASH_ServiceAuthorityReady",false],
    missionNamespace getVariable ["ITW_CLASH_ServiceStabilityReady",false]
];
true