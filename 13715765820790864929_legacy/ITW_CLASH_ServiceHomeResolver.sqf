#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceHomeResolverStarted",false]) exitWith {true};
ITW_CLASH_ServiceHomeResolverStarted = true;
ITW_CLASH_ServiceHomeResolverVersion = 2;
ITW_CLASH_ServiceHomeResolverReady = false;
ITW_CLASH_ServiceHomeRevalidateInterval = missionNamespace getVariable [
    "ITW_CLASH_ServiceHomeRevalidateInterval",120
];
ITW_CLASH_ServiceHomeChangeThreshold = missionNamespace getVariable [
    "ITW_CLASH_ServiceHomeChangeThreshold",200
];

private _deadline = time + 240;
waitUntil {
    sleep 0.1;
    time >= _deadline || {
        missionNamespace getVariable ["ITW_CLASH_SeaGenerationGuardReady",false]
        && {missionNamespace getVariable ["ITW_CLASH_ServiceStabilityReady",false]}
        && {!isNil "ITW_CLASH_Service_fnc_OrderRTB"}
        && {!isNil "ITW_CLASH_Service_fnc_ReissueRTB"}
        && {!isNil "ITW_CLASH_Service_fnc_RegisterPhysical"}
        && {!isNil "ITW_CLASH_Checkbook_fnc_RegisterTransport"}
        && {!isNil "ITW_CLASH_Generation_fnc_RegisterAsset"}
        && {!isNil "ITW_CLASH_DualHAL_fnc_StageFieldVehicle"}
    }
};
if (time >= _deadline) exitWith {
    diag_log "CLASH BOOT | WARNING | service-home-resolver-bind-timeout";
    false
};

ITW_CLASH_ServiceHome_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_Service_fnc_Log") then {
        ["home-" + _event,_payload] call ITW_CLASH_Service_fnc_Log;
    } else {
        diag_log format ["CLASH SERVICE HOME | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ServiceHome_fnc_PositionValid = {
    params ["_position"];
    _position isEqualType [] && {count _position >= 2} && {
        !(_position isEqualTo []) && {
            !(_position isEqualTo [0,0,0])
        }
    }
};

ITW_CLASH_ServiceHome_fnc_OwnerForSide = {
    params ["_side"];
    if (!isNil "ITW_PlayerSide" && {_side == ITW_PlayerSide}) exitWith {ITW_OWNER_FRIENDLY};
    if (!isNil "ITW_EnemySide" && {_side == ITW_EnemySide}) exitWith {ITW_OWNER_ENEMY};
    ITW_OWNER_UNDEFINDED
};

ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices = {
    params ["_side"];
    if (isNil "ITW_Bases" || {isNil "ITW_Objectives"}) exitWith {[]};
    private _owner = [_side] call ITW_CLASH_ServiceHome_fnc_OwnerForSide;
    if (_owner == ITW_OWNER_UNDEFINDED) exitWith {[]};

    private _indices = [];
    {
        private _objective = _x;
        if ((_objective#ITW_OBJ_OWNER) != _owner) then {continue};
        private _baseIndex = _objective#ITW_OBJ_INDEX;
        if (_baseIndex < 0 || {_baseIndex >= count ITW_Bases}) then {continue};
        private _base = ITW_Bases#_baseIndex;
        if !(_base#ITW_BASE_SPAWNED) then {continue};
        _indices pushBackUnique _baseIndex;
    } forEach ITW_Objectives;
    _indices
};

ITW_CLASH_ServiceHome_fnc_BaseValidForSide = {
    params ["_side","_baseIndex"];
    if (_baseIndex < 0) exitWith {false};
    _baseIndex in ([_side] call ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices)
};

ITW_CLASH_ServiceHome_fnc_BasePoint = {
    params ["_baseIndex",["_mode","GROUND"]];
    if (isNil "ITW_Bases" || {_baseIndex < 0} || {_baseIndex >= count ITW_Bases}) exitWith {[]};
    private _base = ITW_Bases#_baseIndex;
    private _position = [];
    _mode = toUpperANSI _mode;

    if (_mode == "SEA") then {
        _position = +(_base#ITW_BASE_POS);
    } else {
        if (_mode == "GROUND") then {
            private _garage = +(_base#ITW_BASE_GARAGE_POS);
            private _badGarage = _garage isEqualTo []
                || {_garage isEqualTo [-1000,-1000,0]}
                || {_garage isEqualTo [999,999,0]}
                || {_garage isEqualTo [0,0,0]};
            if (!_badGarage) then {_position = _garage};
        };
        if (_position isEqualTo []) then {
            _position = +(_base#ITW_BASE_A_SPAWN);
        };
        if (_position isEqualTo [] || {_position isEqualTo [0,0,0]}) then {
            _position = +(_base#ITW_BASE_POS);
        };
    };

    if (_position isNotEqualTo [] && {count _position < 3}) then {_position pushBack 0};
    _position
};

ITW_CLASH_ServiceHome_fnc_NearestFriendlyBase = {
    params ["_side","_position"];
    private _indices = [_side] call ITW_CLASH_ServiceHome_fnc_FriendlyBaseIndices;
    if (_indices isEqualTo []) exitWith {-1};
    private _ordered = [_indices,[_position],{
        private _base = ITW_Bases#_x;
        (_base#ITW_BASE_POS) distance2D _input0
    },"ASCEND"] call BIS_fnc_sortBy;
    _ordered#0
};

ITW_CLASH_ServiceHome_fnc_SetBaseHint = {
    params ["_veh",["_group",grpNull],"_baseIndex",["_source","unknown"]];
    if (_baseIndex < 0) exitWith {false};
    if (isNull _group && {!isNull _veh}) then {_group = group driver _veh};
    if (!isNull _veh) then {
        _veh setVariable ["ITW_CLASH_ServiceBaseHint",_baseIndex,true];
    };
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_ServiceBaseHint",_baseIndex];
    };

    if (!isNull _veh && {!isNil "ITW_CLASH_Service_fnc_FindEntry"}) then {
        private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
        private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
        if (_index >= 0 && {_index < count ITW_CLASH_ServicePool}) then {
            private _entry = ITW_CLASH_ServicePool#_index;
            _entry set ["baseHint",_baseIndex];
            _entry set ["baseHintSource",_source];
            ITW_CLASH_ServicePool set [_index,_entry];
        };
    };
    ["hint-stored",[
        if (isNull _veh) then {"<none>"} else {typeOf _veh},
        if (isNull _group) then {"<null>"} else {str _group},
        _baseIndex,_source
    ]] call ITW_CLASH_ServiceHome_fnc_Log;
    true
};

ITW_CLASH_ServiceHome_fnc_Resolve = {
    params ["_entry","_currentPos"];
    private _side = _entry getOrDefault ["side",sideUnknown];
    private _mode = toUpperANSI (_entry getOrDefault ["mode","GROUND"]);
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    private _hint = _entry getOrDefault ["baseHint",-1];
    if (_hint < 0 && {!isNull _veh}) then {
        _hint = _veh getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    };
    if (_hint < 0 && {!isNull _group}) then {
        _hint = _group getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    };

    private _baseIndex = -1;
    private _method = "";
    if ([_side,_hint] call ITW_CLASH_ServiceHome_fnc_BaseValidForSide) then {
        _baseIndex = _hint;
        _method = "request-base";
    } else {
        _baseIndex = [_side,_currentPos] call ITW_CLASH_ServiceHome_fnc_NearestFriendlyBase;
        if (_baseIndex >= 0) then {_method = "nearest-base"};
    };

    private _baseResolution = createHashMap;
    if (_baseIndex >= 0) then {
        private _position = [_baseIndex,_mode] call ITW_CLASH_ServiceHome_fnc_BasePoint;
        if ([_position] call ITW_CLASH_ServiceHome_fnc_PositionValid) then {
            if (_mode == "SEA" || {!isNull _veh && {_veh isKindOf "Ship"}}) then {
                private _water = [_position,[]] call ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition;
                if (_water isNotEqualTo []) then {
                    _baseResolution = createHashMapFromArray [
                        ["status","RESOLVED"],["baseIndex",_baseIndex],
                        ["method","water-node"],["position",+_water]
                    ];
                };
            } else {
                _baseResolution = createHashMapFromArray [
                    ["status","RESOLVED"],["baseIndex",_baseIndex],
                    ["method",_method],["position",+_position]
                ];
            };
        };
    };
    if (count _baseResolution > 0) exitWith {_baseResolution};

    ["no-friendly-base",[
        _entry getOrDefault ["id","?"],_side,_hint,_baseIndex,_mode,+_currentPos
    ]] call ITW_CLASH_ServiceHome_fnc_Log;

    private _fallback = [];
    if (!isNull _group) then {
        private _start = _group getVariable ["START" + str _group,[]];
        if ([_start] call ITW_CLASH_ServiceHome_fnc_PositionValid) then {_fallback = +_start};
    };
    if (_fallback isEqualTo []) then {
        private _previous = +(_entry getOrDefault ["homeResolvedPos",[]]);
        if ([_previous] call ITW_CLASH_ServiceHome_fnc_PositionValid) then {_fallback = _previous};
    };
    if (_fallback isEqualTo []) exitWith {
        createHashMapFromArray [["status","UNRESOLVED"],["reason","no-friendly-base"]]
    };

    if (_mode == "SEA" || {!isNull _veh && {_veh isKindOf "Ship"}}) then {
        private _water = [_fallback,[]] call ITW_CLASH_SeaGuard_fnc_ResolveWaterPosition;
        if (_water isEqualTo []) exitWith {
            createHashMapFromArray [["status","UNRESOLVED"],["reason","fallback-start-no-water"]]
        };
        _fallback = _water;
    };
    createHashMapFromArray [
        ["status","RESOLVED"],["baseIndex",-1],
        ["method","fallback-start"],["position",+_fallback]
    ]
};

/*
    Transient groups such as player-flown HAL carriers are not service-pool
    assets, but HAL still consumes START+str(group) as its RTB input. Keep the
    live Impasse base resolver as the sole writer of that shared answer.
*/
ITW_CLASH_ServiceHome_fnc_ResolveTransientGroup = {
    params ["_group","_veh",["_reason","transient"]];
    if (isNull _group || {isNull _veh}) exitWith {
        createHashMapFromArray [["status","UNRESOLVED"],["reason","null-transient"]]
    };

    private _mode = if (_veh isKindOf "Ship") then {"SEA"} else {
        if (_veh isKindOf "Air") then {"AIR"} else {"GROUND"}
    };
    private _hint = _veh getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    if (_hint < 0) then {
        _hint = _group getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    };
    private _entry = createHashMapFromArray [
        ["id","TRANSIENT-" + str _group],
        ["side",side _group],
        ["mode",_mode],
        ["vehicle",_veh],
        ["group",_group],
        ["baseHint",_hint]
    ];

    private _resolved = [_entry,getPosATL _veh] call ITW_CLASH_ServiceHome_fnc_Resolve;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {
        ["transient-unresolved",[
            str _group,typeOf _veh,_mode,_reason,
            _resolved getOrDefault ["reason","unknown"]
        ]] call ITW_CLASH_ServiceHome_fnc_Log;
        _resolved
    };

    private _position = +(_resolved get "position");
    private _baseIndex = _resolved getOrDefault ["baseIndex",-1];
    private _method = _resolved getOrDefault ["method","unknown"];
    if (_baseIndex >= 0) then {
        [_veh,_group,_baseIndex,"transient:" + _reason] call
            ITW_CLASH_ServiceHome_fnc_SetBaseHint;
    };

    _group setVariable ["START" + str _group,+_position];
    _group setVariable ["ITW_CLASH_ServiceHome",+_position];
    ["transient-resolved",[
        str _group,typeOf _veh,_baseIndex,_method,+_position,_reason
    ]] call ITW_CLASH_ServiceHome_fnc_Log;
    _resolved
};

ITW_CLASH_ServiceHome_fnc_ResolveAndStore = {
    params ["_index",["_reason","resolve"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {createHashMap};
    private _entry = ITW_CLASH_ServicePool#_index;
    private _veh = _entry getOrDefault ["vehicle",objNull];
    private _group = _entry getOrDefault ["group",grpNull];
    if (isNull _veh || {isNull _group}) exitWith {createHashMap};

    private _resolved = [_entry,getPosATL _veh] call ITW_CLASH_ServiceHome_fnc_Resolve;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {_resolved};

    private _position = +(_resolved get "position");
    private _baseIndex = _resolved getOrDefault ["baseIndex",-1];
    private _method = _resolved getOrDefault ["method","unknown"];
    _entry set ["homeBaseIndex",_baseIndex];
    _entry set ["homeMethod",_method];
    _entry set ["homeResolvedPos",+_position];
    _entry set ["homeResolvedAt",time];
    _entry set ["home",+_position];
    _entry set ["homeAuthority","IMPASSE_BASE_RESOLVER"];
    if (_baseIndex >= 0) then {
        _entry set ["baseHint",_baseIndex];
        _veh setVariable ["ITW_CLASH_ServiceBaseHint",_baseIndex,true];
        _group setVariable ["ITW_CLASH_ServiceBaseHint",_baseIndex];
    };
    ITW_CLASH_ServicePool set [_index,_entry];

    _group setVariable ["START" + str _group,+_position];
    _group setVariable ["ITW_CLASH_ServiceHome",+_position];

    ["resolved",[
        _entry getOrDefault ["id","?"],_baseIndex,_method,+_position,_reason
    ]] call ITW_CLASH_ServiceHome_fnc_Log;
    _resolved
};

ITW_CLASH_ServiceHome_fnc_RegisterPhysicalBase = ITW_CLASH_Service_fnc_RegisterPhysical;
ITW_CLASH_Service_fnc_RegisterPhysical = {
    private _veh = _this param [0,objNull];
    private _poolIdBefore = if (isNull _veh) then {""} else {
        _veh getVariable ["ITW_CLASH_ServicePoolId",""]
    };
    private _indexBefore = if (_poolIdBefore isEqualTo "") then {-1} else {
        [_poolIdBefore] call ITW_CLASH_Service_fnc_FindEntry
    };
    private _previous = if (_indexBefore >= 0 && {_indexBefore < count ITW_CLASH_ServicePool}) then {
        ITW_CLASH_ServicePool#_indexBefore
    } else {createHashMap};
    private _previousVeh = _previous getOrDefault ["vehicle",objNull];
    private _sameLive = !isNull _veh && {!isNull _previousVeh} && {
        _veh isEqualTo _previousVeh && {alive _previousVeh}
    };
    private _previousResolvedAt = _previous getOrDefault ["homeResolvedAt",0];
    private _previousResolvedPos = +(_previous getOrDefault ["homeResolvedPos",[]]);
    private _previousBaseIndex = _previous getOrDefault ["homeBaseIndex",-1];
    private _previousMethod = _previous getOrDefault ["homeMethod",""];

    private _result = _this call ITW_CLASH_ServiceHome_fnc_RegisterPhysicalBase;
    if (_result isEqualTo "") exitWith {_result};
    private _index = [_result] call ITW_CLASH_Service_fnc_FindEntry;
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {_result};

    private _entry = ITW_CLASH_ServicePool#_index;
    private _group = _entry getOrDefault ["group",grpNull];
    private _rawHome = +(_entry getOrDefault ["home",[]]);
    if (!_sameLive) then {
        if ([_rawHome] call ITW_CLASH_ServiceHome_fnc_PositionValid) then {
            _entry set ["deploymentOrigin",+_rawHome];
        };
        _entry set ["homeResolvedAt",0];
        _entry set ["homeResolvedPos",[]];
        _entry set ["homeBaseIndex",-1];
        _entry set ["homeMethod",""];
        _entry set ["homeAuthority","UNRESOLVED"];
        if (!isNull _group) then {_group setVariable ["ITW_CLASH_ServiceHome",nil]};
    } else {
        if (_previousResolvedAt > 0 && {
            [_previousResolvedPos] call ITW_CLASH_ServiceHome_fnc_PositionValid
        }) then {
            _entry set ["homeResolvedAt",_previousResolvedAt];
            _entry set ["homeResolvedPos",+_previousResolvedPos];
            _entry set ["homeBaseIndex",_previousBaseIndex];
            _entry set ["homeMethod",_previousMethod];
            _entry set ["home",+_previousResolvedPos];
            _entry set ["homeAuthority","IMPASSE_BASE_RESOLVER"];
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_ServiceHome",+_previousResolvedPos];
                _group setVariable ["START" + str _group,+_previousResolvedPos];
            };
        };
    };

    private _hint = if (isNull _veh) then {-1} else {
        _veh getVariable ["ITW_CLASH_ServiceBaseHint",-1]
    };
    if (_hint < 0 && {!isNull _group}) then {
        _hint = _group getVariable ["ITW_CLASH_ServiceBaseHint",-1];
    };
    if (_hint >= 0) then {_entry set ["baseHint",_hint]};
    ITW_CLASH_ServicePool set [_index,_entry];
    _result
};

ITW_CLASH_ServiceHome_fnc_OrderRTBBase = ITW_CLASH_Service_fnc_OrderRTB;
ITW_CLASH_Service_fnc_OrderRTB = {
    params ["_index",["_reason","task-complete"]];
    private _resolved = [_index,"order-rtb:" + _reason] call ITW_CLASH_ServiceHome_fnc_ResolveAndStore;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {false};
    _this call ITW_CLASH_ServiceHome_fnc_OrderRTBBase
};

ITW_CLASH_ServiceHome_fnc_ReissueRTBBase = ITW_CLASH_Service_fnc_ReissueRTB;
ITW_CLASH_ServiceHome_fnc_RefreshRTB = {
    params ["_index",["_reason","watchdog"]];
    if (_index < 0 || {_index >= count ITW_CLASH_ServicePool}) exitWith {false};
    private _before = ITW_CLASH_ServicePool#_index;
    if ((_before getOrDefault ["state",""]) != "RTB") exitWith {false};
    private _oldPosition = +(_before getOrDefault ["homeResolvedPos",_before getOrDefault ["home",[]]]);

    private _resolved = [_index,"rtb-refresh:" + _reason] call ITW_CLASH_ServiceHome_fnc_ResolveAndStore;
    if ((_resolved getOrDefault ["status",""]) != "RESOLVED") exitWith {false};
    private _newPosition = +(_resolved get "position");
    private _moved = _oldPosition isEqualTo [] || {
        _oldPosition distance2D _newPosition >= ITW_CLASH_ServiceHomeChangeThreshold
    };

    if (_moved) then {
        private _result = [_index] call ITW_CLASH_ServiceHome_fnc_ReissueRTBBase;
        if (_result) then {
            private _entry = ITW_CLASH_ServicePool#_index;
            private _veh = _entry getOrDefault ["vehicle",objNull];
            if (!isNull _veh) then {
                _entry set ["lastDistance",_veh distance2D _newPosition];
                _entry set ["lastProgressAt",time];
            };
            ITW_CLASH_ServicePool set [_index,_entry];
            ["waypoint-changed",[
                _entry getOrDefault ["id","?"],_reason,+_oldPosition,+_newPosition,
                if (_oldPosition isEqualTo []) then {-1} else {round (_oldPosition distance2D _newPosition)}
            ]] call ITW_CLASH_ServiceHome_fnc_Log;
        };
        _result
    } else {
        private _entry = ITW_CLASH_ServicePool#_index;
        _entry set ["lastOrderAt",time];
        ITW_CLASH_ServicePool set [_index,_entry];
        ["refreshed-no-waypoint-change",[
            _entry getOrDefault ["id","?"],_reason,+_newPosition,
            ITW_CLASH_ServiceHomeChangeThreshold
        ]] call ITW_CLASH_ServiceHome_fnc_Log;
        true
    }
};

ITW_CLASH_Service_fnc_ReissueRTB = {
    params ["_index"];
    [_index,"watchdog"] call ITW_CLASH_ServiceHome_fnc_RefreshRTB
};

ITW_CLASH_ServiceHome_fnc_RegisterTransportBase = ITW_CLASH_Checkbook_fnc_RegisterTransport;
ITW_CLASH_Checkbook_fnc_RegisterTransport = {
    private _veh = _this param [0,objNull];
    private _group = _this param [1,grpNull];
    private _result = _this call ITW_CLASH_ServiceHome_fnc_RegisterTransportBase;
    if (_result && {!isNull _veh}) then {
        private _baseIndex = [side _group,getPosATL _veh] call ITW_CLASH_ServiceHome_fnc_NearestFriendlyBase;
        if (_baseIndex >= 0) then {
            [_veh,_group,_baseIndex,"transport-registration"] call ITW_CLASH_ServiceHome_fnc_SetBaseHint;
        };
    };
    _result
};

ITW_CLASH_ServiceHome_fnc_RegisterAssetBase = ITW_CLASH_Generation_fnc_RegisterAsset;
ITW_CLASH_Generation_fnc_RegisterAsset = {
    private _veh = _this param [0,objNull];
    private _group = _this param [1,grpNull];
    private _result = _this call ITW_CLASH_ServiceHome_fnc_RegisterAssetBase;
    if (_result && {!isNull _veh} && {
        [_veh] call ITW_CLASH_ServiceAuthority_fnc_HasLease
    }) then {
        private _baseIndex = [side _group,getPosATL _veh] call ITW_CLASH_ServiceHome_fnc_NearestFriendlyBase;
        if (_baseIndex >= 0) then {
            [_veh,_group,_baseIndex,"generated-service-registration"] call ITW_CLASH_ServiceHome_fnc_SetBaseHint;
        };
    };
    _result
};

ITW_CLASH_ServiceHome_fnc_StageFieldVehicleBase = ITW_CLASH_DualHAL_fnc_StageFieldVehicle;
ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {
    private _result = _this call ITW_CLASH_ServiceHome_fnc_StageFieldVehicleBase;
    if (_result) then {
        private _vehInfo = _this param [0,[]];
        if (_vehInfo isEqualType [] && {count _vehInfo > VEHINFO_CREW_GRP}) then {
            private _veh = _vehInfo#VEHINFO_VEH;
            private _group = _vehInfo#VEHINFO_CREW_GRP;
            if (!isNull _veh && {[_veh] call ITW_CLASH_ServiceAuthority_fnc_HasLease}) then {
                private _baseIndex = [side _group,getPosATL _veh] call ITW_CLASH_ServiceHome_fnc_NearestFriendlyBase;
                if (_baseIndex >= 0) then {
                    [_veh,_group,_baseIndex,"field-handoff"] call ITW_CLASH_ServiceHome_fnc_SetBaseHint;
                };
                private _poolId = _veh getVariable ["ITW_CLASH_ServicePoolId",""];
                private _index = [_poolId] call ITW_CLASH_Service_fnc_FindEntry;
                if (_index >= 0 && {_index < count ITW_CLASH_ServicePool}) then {
                    private _entry = ITW_CLASH_ServicePool#_index;
                    if ((_entry getOrDefault ["state",""]) == "DEPLOYED") then {
                        _entry set ["deploymentOrigin",getPosATL _veh];
                        _entry set ["homeResolvedAt",0];
                        _entry set ["homeResolvedPos",[]];
                        _entry set ["homeBaseIndex",-1];
                        _entry set ["homeMethod",""];
                        _entry set ["homeAuthority","UNRESOLVED"];
                        ITW_CLASH_ServicePool set [_index,_entry];
                        _group setVariable ["ITW_CLASH_ServiceHome",nil];
                    };
                };
            };
        };
    };
    _result
};

[] spawn {
    scriptName "ITW_CLASH_ServiceHomeRevalidationWatch";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 5;
        for "_i" from ((count ITW_CLASH_ServicePool) - 1) to 0 step -1 do {
            private _entry = ITW_CLASH_ServicePool#_i;
            if ((_entry getOrDefault ["state",""]) != "RTB") then {continue};
            private _resolvedAt = _entry getOrDefault ["homeResolvedAt",0];
            if (_resolvedAt <= 0 || {
                time - _resolvedAt >= ITW_CLASH_ServiceHomeRevalidateInterval
            }) then {
                [_i,"periodic"] call ITW_CLASH_ServiceHome_fnc_RefreshRTB;
            };
        };
    };
};

ITW_CLASH_ServiceHomeResolverReady = true;
diag_log format [
    "CLASH BOOT | service-home-resolver-ready | version=%1 liveImpasseBases=true baseHintOnly=true rtbResolveAtUse=true periodicRevalidate=%2 changeThreshold=%3 seaGuardProjectionOnly=true startWriteThrough=true transientGroupWriteThrough=true",
    ITW_CLASH_ServiceHomeResolverVersion,
    ITW_CLASH_ServiceHomeRevalidateInterval,
    ITW_CLASH_ServiceHomeChangeThreshold
];
true
