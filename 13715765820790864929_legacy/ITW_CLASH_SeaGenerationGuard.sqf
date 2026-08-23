#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_SeaGenerationGuardStarted",false]) exitWith {true};
ITW_CLASH_SeaGenerationGuardStarted = true;
ITW_CLASH_SeaGenerationGuardVersion = 1;
ITW_CLASH_SeaGenerationGuardReady = false;

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

ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition = {
    params [["_preferred",[]],["_fallback",[]]];

    if (_preferred isNotEqualTo []) then {
        private _position = +_preferred;
        if (count _position < 3) then {_position pushBack 0};
        if (surfaceIsWater _position) exitWith {_position};
    };
    if (_fallback isNotEqualTo []) then {
        private _position = +_fallback;
        if (count _position < 3) then {_position pushBack 0};
        if (surfaceIsWater _position) exitWith {_position};
    };

    private _reference = if (_preferred isNotEqualTo []) then {+_preferred} else {+_fallback};
    if (_reference isEqualTo []) then {_reference = [worldSize / 2,worldSize / 2,0]};
    private _points = call ITW_CLASH_SeaGuard_fnc_AllSeaPoints;
    if (_points isEqualTo []) exitWith {[]};
    private _ordered = [_points,[_reference],{_x distance2D _input0},"ASCEND"] call BIS_fnc_sortBy;
    +(_ordered#0)
};

ITW_CLASH_SeaGuard_fnc_EnsureWater = {
    params ["_veh",["_preferred",[]],["_source","unknown"]];
    if (isNull _veh) exitWith {false};
    if !(_veh isKindOf "Ship") exitWith {true};

    private _current = getPosATL _veh;
    if (surfaceIsWater _current && {_preferred isEqualTo []}) exitWith {true};
    private _water = [_preferred,_current] call ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition;
    if (_water isEqualTo []) exitWith {
        ["no-water-node",[typeOf _veh,_source,_preferred,_current]] call ITW_CLASH_SeaGuard_fnc_Log;
        false
    };

    if (_current distance2D _water > 2 || {!surfaceIsWater _current}) then {
        _veh setPosATL _water;
        _veh setVectorUp (surfaceNormal _water);
        ["relocated",[
            typeOf _veh,_source,_current,_water,round (_current distance2D _water)
        ]] call ITW_CLASH_SeaGuard_fnc_Log;
    };
    surfaceIsWater (getPosATL _veh)
};

// Generic Checkbook/ForceGeneration guard. Apply before the current registration
// stack so every downstream tracker and service-home record sees a valid water
// position. A ship with no valid water node is rejected before billing occurs.
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

// Impasse already spawned ships using its native ITW_SeaPoints logic. The
// dual-HAL handoff used to reinterpret every non-air vehicle as GROUND and move
// ships to a FOB staging position. Capture the native position first, let the
// normal handoff perform all authority bookkeeping, then restore/validate the
// boat on water before gameplay can resume.
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
            if (!isNil "ITW_CLASH_Service_fnc_MarkTrackerReleased") then {
                [_veh] call ITW_CLASH_Service_fnc_MarkTrackerReleased;
            };
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _group && {units _group isEqualTo []}) then {deleteGroup _group};
            ["handoff-rejected",[typeOf _veh,_original,"no-valid-sea-position"]] call
                ITW_CLASH_SeaGuard_fnc_Log;
            false
        };

        // The service lifecycle may already have registered a transport/dual
        // ship while the base handoff briefly held it at generic staging. Keep
        // its RTB/virtualization home on the corrected water position too.
        if (!isNil "ITW_CLASH_ServicePool") then {
            private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
            if (_poolId isNotEqualTo "" && {!isNil "ITW_CLASH_Service_fnc_FindEntry"}) then {
                private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
                if (_index >= 0 && {_index < count ITW_CLASH_ServicePool}) then {
                    private _entry = ITW_CLASH_ServicePool#_index;
                    _entry set ["home",getPosATL _veh];
                    _entry set ["lastDistance",0];
                    ITW_CLASH_ServicePool set [_index,_entry];
                    private _group = group driver _veh;
                    if (!isNull _group) then {
                        _group setVariable ["ITW_CLASH_ServiceHome",getPosATL _veh];
                    };
                };
            };
        };
        true
    };
};

ITW_CLASH_SeaGenerationGuardReady = true;
diag_log format [
    "CLASH BOOT | sea-generation-guard-ready | version=%1 impasseHandoff=true generatedAssets=true landFallback=false",
    ITW_CLASH_SeaGenerationGuardVersion
];
true