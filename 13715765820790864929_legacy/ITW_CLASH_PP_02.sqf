#include "defines.hpp"

// C.L.A.S.H. V6 preprocessor bisect chunk 2/8.
// Original ITW_CLASH.sqf lines 340-667. Diagnostic only; never executed.

ITW_CLASH_fnc_ClearGroupWaypoints = {
    params ["_group"];
    if (isNull _group) exitWith {false};

    if (!isNil "RYD_WPdel") then {
        [_group] call RYD_WPdel;
    } else {
        {deleteWaypoint _x} forEachReversed waypoints _group;
    };
    true
};

ITW_CLASH_fnc_ApplyObjectiveDoctrine = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};

    private _activeCount = count ITW_CLASH_HALObjectives;
    private _heldCount = count (missionNamespace getVariable ["RydHQ_Taken",[]]);
    private _recovering = _activeCount > _heldCount;
    private _order = if (_recovering) then {"ATTACK"} else {"DEFEND"};
    private _previousOrder = missionNamespace getVariable ["RydHQ_Order",""];
    private _anchors = [];
    {
        private _entry = ITW_CLASH_AnchorGroups getOrDefault [_x,[]];
        if (_entry isNotEqualTo []) then {
            private _group = _entry#0;
            if (!isNull _group && {
                _group getVariable ["ITW_CLASH_Managed",false] && {
                    !(_group getVariable ["ITW_CLASH_Releasing",false])
                }
            }) then {
                _anchors pushBackUnique _group;
            };
        };
    } forEach +(keys ITW_CLASH_AnchorGroups);

    if (_order isEqualTo "ATTACK" && {_previousOrder isNotEqualTo "ATTACK"}) then {
        private _detached = [];
        {
            if (!isNull _x && {
                !(_x in _anchors) && {
                    _x getVariable ["Defending",false]
                }
            }) then {
                _x setVariable ["Defending",false];
                [_x] call ITW_CLASH_fnc_ClearGroupWaypoints;
                _detached pushBack ([_x] call ITW_CLASH_fnc_GroupId);
            };
        } forEach +ITW_CLASH_ManagedGroups;
        if (!isNull ITW_CLASH_HALHQ) then {
            {
                ITW_CLASH_HALHQ setVariable [
                    _x,
                    (ITW_CLASH_HALHQ getVariable [_x,[]]) select {_x in _anchors}
                ];
            } forEach ["RydHQ_DefSpot","RydHQ_Def","RydHQ_DefRes","RydHQ_RecDefSpot"];
        };
        ["recovery-start",[
            ITW_ZoneIndex,
            ITW_CLASH_LastHeldObjectives,
            _activeCount,
            _detached
        ]] call ITW_CLASH_fnc_Log;
    };

    RydHQ_Order = _order;
    RydHQ_Berserk = false;
    RydHQ_AttackAlways = false;
    RydHQ_IdleDef = true;
    RydHQ_DefendObjectives = 1;
    RydHQ_CRDefRes = ITW_CLASH_ReserveRatio;
    RydHQ_NoDef = [];
    RydHQ_NoAttack = +_anchors;
    RydHQ_NoRecon = +_anchors;
    RydHQ_MAtt = true;
    RydHQ_Personality = "COMPETENT";
    RydHQ_Recklessness = 0.5;
    RydHQ_Consistency = 0.5;
    RydHQ_Activity = 0.5;
    RydHQ_Reflex = 0.5;
    RydHQ_Circumspection = 0.5;
    RydHQ_Fineness = 0.5;

    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Order",_order];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Berserk",false];
        ITW_CLASH_HALHQ setVariable ["RydHQ_AttackAlways",false];
        ITW_CLASH_HALHQ setVariable ["RydHQ_IdleDef",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_DefendObjectives",1];
        ITW_CLASH_HALHQ setVariable ["RydHQ_CRDefRes",ITW_CLASH_ReserveRatio];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",[]];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoAttack",+_anchors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoRecon",+_anchors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_MAtt",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Personality","COMPETENT"];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Recklessness",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Consistency",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Activity",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Reflex",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Circumspection",0.5];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Fineness",0.5];
    };

    private _signature = str [
        RydHQ_Order,
        RydHQ_Berserk,
        RydHQ_IdleDef,
        RydHQ_DefendObjectives,
        count RydHQ_NoDef,
        count RydHQ_NoAttack,
        RydHQ_CRDefRes,
        RydHQ_Personality,
        _recovering,
        _heldCount,
        _activeCount
    ];
    if (_signature != ITW_CLASH_LastDoctrineSignature) then {
        ITW_CLASH_LastDoctrineSignature = _signature;
        ["doctrine",[
            _order,
            RydHQ_IdleDef,
            RydHQ_DefendObjectives,
            count RydHQ_NoDef,
            count RydHQ_NoAttack,
            RydHQ_CRDefRes,
            RydHQ_Personality,
            _recovering,
            _heldCount,
            _activeCount
        ]] call ITW_CLASH_fnc_Log;
    };
    true
};

ITW_CLASH_fnc_SyncHALIncluded = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {[]};

    ITW_CLASH_ManagedGroups = ITW_CLASH_ManagedGroups select {
        !isNull _x && {
            !([_x] call ITW_CLASH_fnc_IsCommanderGroup) && {
                count units _x > 0 && {
                    _x getVariable ["ITW_CLASH_Managed",false]
                }
            }
        }
    };

    RydHQ_Included = +ITW_CLASH_ManagedGroups;
    RydHQ_NoDef = [];
    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_Included",+ITW_CLASH_ManagedGroups];
        ITW_CLASH_HALHQ setVariable ["RydHQ_NoDef",[]];
    };
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;
    +ITW_CLASH_ManagedGroups
};

ITW_CLASH_fnc_MirrorObjectives = {
    if (!isServer || {!ITW_CLASH_LiveEnabled}) exitWith {false};
    if (isNil "ITW_Zones" || {isNil "ITW_ZoneIndex"} || {isNil "ITW_Objectives"}) exitWith {
        ["objective-mirror-deferred",[]] call ITW_CLASH_fnc_Log;
        false
    };
    if (ITW_ZoneIndex < 0 || {ITW_ZoneIndex >= count ITW_Zones}) exitWith {
        ["objective-mirror-invalid-zone",[ITW_ZoneIndex,count ITW_Zones]] call ITW_CLASH_fnc_Log;
        false
    };

    {
        if (!isNull _x) then {
            _x setVariable ["SetTakenA",false];
            if (!isNull ITW_CLASH_HALHQ) then {
                _x setVariable [
                    format ["Capturing%1%2",str _x,str ITW_CLASH_HALHQ],
                    nil
                ];
            };
        };
    } forEach ITW_CLASH_HALObjectives;

    private _zoneChanged = ITW_CLASH_LastMirroredZone != ITW_ZoneIndex;
    private _mirrors = [];
    private _taken = [];
    {
        private _objectiveIndex = _x;
        if (_objectiveIndex >= 0 && {_objectiveIndex < count ITW_Objectives}) then {
            private _objective = ITW_Objectives#_objectiveIndex;
            if (count _objective > ITW_OBJ_FLAG) then {
                private _flag = _objective#ITW_OBJ_FLAG;
                if (!isNull _flag) then {
                    private _playerOwned = [_objectiveIndex] call ITW_ObjContestedOwnerIsFriendly;
                    _flag setVariable ["SetTakenA",!_playerOwned];
                    _mirrors pushBack _flag;
                    if (!_playerOwned) then {
                        _taken pushBack _flag;
                    };
                };
            };
        };
    } forEach (ITW_Zones#ITW_ZoneIndex);

    ITW_CLASH_HALObjectives = _mirrors;
    private _heldObjectives = call ITW_CLASH_fnc_GetHeldObjectives;
    private _heldIndices = _heldObjectives apply {_x#0};
    private _previousHeld = if (_zoneChanged) then {[]} else {
        +ITW_CLASH_LastHeldObjectives
    };
    private _lostObjectives = if (_zoneChanged) then {[]} else {
        _previousHeld - _heldIndices
    };
    private _recoveredObjectives = if (_zoneChanged) then {[]} else {
        _heldIndices - _previousHeld
    };

    {
        private _key = [_x] call ITW_CLASH_fnc_AnchorKey;
        [_x,"objective-lost"] call ITW_CLASH_fnc_ClearAnchorSlot;
        private _refill = ITW_CLASH_AnchorRefills getOrDefault [_key,[]];
        if (_refill isNotEqualTo []) then {
            ITW_CLASH_AnchorRefills deleteAt _key;
            ["anchor-refill-cancelled",[
                _x,
                _refill#0,
                "objective-lost"
            ]] call ITW_CLASH_fnc_Log;
        };
    } forEach _lostObjectives;
    ITW_CLASH_LastHeldObjectives = +_heldIndices;
    private _commanderObjective = [_heldObjectives] call ITW_CLASH_fnc_SyncCommanderObjective;

    RydHQ_SimpleMode = true;
    RydHQ_SimpleObjs = +_mirrors;
    RydHQ_Taken = +_taken;
    if (_zoneChanged) then {
        RydHQ_NObj = 1;
    };

    if (!isNull ITW_CLASH_HALHQ) then {
        ITW_CLASH_HALHQ setVariable ["RydHQ_SimpleMode",true];
        ITW_CLASH_HALHQ setVariable ["RydHQ_SimpleObjs",+_mirrors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Objectives",+_mirrors];
        ITW_CLASH_HALHQ setVariable ["RydHQ_Taken",+_taken];
        if (_zoneChanged) then {
            ITW_CLASH_HALHQ setVariable ["RydHQ_NObj",1];
        };
    };
    call ITW_CLASH_fnc_ApplyObjectiveDoctrine;

    if (_lostObjectives isNotEqualTo [] || {
        _recoveredObjectives isNotEqualTo []
    }) then {
        ["objective-ownership",[
            ITW_ZoneIndex,
            _lostObjectives,
            _recoveredObjectives,
            _heldIndices
        ]] call ITW_CLASH_fnc_Log;
    };

    ITW_CLASH_LastMirroredZone = ITW_ZoneIndex;
    private _signature = str [
        ITW_ZoneIndex,
        _mirrors apply {str _x},
        _taken apply {str _x},
        _commanderObjective
    ];
    if (_signature != ITW_CLASH_LastObjectiveSignature) then {
        ITW_CLASH_LastObjectiveSignature = _signature;
        ["objective-mirror",[
            ITW_ZoneIndex,
            ITW_Zones#ITW_ZoneIndex,
            _heldObjectives apply {_x#0},
            _commanderObjective
        ]] call ITW_CLASH_fnc_Log;
    };
    !(_mirrors isEqualTo [])
};

ITW_CLASH_fnc_ClearAnchorSlot = {
    params [["_objectiveIndex",-1],["_reason","unspecified"]];
    private _key = [_objectiveIndex] call ITW_CLASH_fnc_AnchorKey;
    private _entry = ITW_CLASH_AnchorGroups getOrDefault [_key,[]];
    if (_entry isEqualTo []) exitWith {false};

    private _group = _entry#0;
    private _id = _entry#1;
    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_AnchorObjective",nil];
        _group setVariable ["ITW_CLASH_AnchorAssignedAt",nil];
        _group setVariable ["ITW_CLASH_AnchorOrderPending",nil];
        if (!isNull ITW_CLASH_HALHQ) then {
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefSpot",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_Def",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_Def",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_DefRes",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_DefRes",[]]) - [_group]
            ];
            ITW_CLASH_HALHQ setVariable [
                "RydHQ_RecDefSpot",
                (ITW_CLASH_HALHQ getVariable ["RydHQ_RecDefSpot",[]]) - [_group]
            ];
        };
        if (_reason isEqualTo "promoted-replacement") then {
            _group setVariable ["Break",true];
            _group setVariable ["Defending",false];
        };
        if (_reason isEqualTo "objective-lost") then {
            _group setVariable ["Defending",false];
            [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
        };
    };
    ITW_CLASH_AnchorGroups deleteAt _key;
    ["anchor-vacant",[
        _objectiveIndex,
        _id,
        _reason,
        if (isNull _group) then {0} else {
            [units _group] call ITW_CLASH_fnc_CountConscious
        }
    ]] call ITW_CLASH_fnc_Log;
    true
};
