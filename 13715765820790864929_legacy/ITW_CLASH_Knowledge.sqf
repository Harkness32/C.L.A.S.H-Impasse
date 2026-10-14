#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_KnowledgeStarted",false]) exitWith {true};

ITW_CLASH_KnowledgeStarted = true;
ITW_CLASH_KnowledgeVersion = 1;
ITW_CLASH_KnowledgeReady = false;

/*
    The knowledge layer: what each side has actually reported, and how sure it
    can be of it.

    HAL keeps an enemy in RydHQ_KnEnemies while any friendly's knowsAbout on it
    stays at 0.05 or above, and that value decays slowly. Everything that read
    that list before this file then took the enemy's LIVE position from the
    object (COLOSSUS's EnemyStrength, AirPicture's Observed). A squad seen once,
    minutes ago, was counted at wherever it really is now. For a verdict that is
    a mild cheat; for authorising an airstrike it is a hard one.

    This layer keeps what was REPORTED instead. For each known enemy, every one
    of our groups that knows about it gives one report through targetKnowledge:
    the position it perceived, when it last saw it, and the engine's own error
    estimate. Reports are never merged - the newest time from one observer and
    the smallest error from another is a perfect observation nobody made. Each
    is projected on its own and the contact keeps the single best.

    Uncertainty is a movement envelope, not a confidence interval:

        R = error + speed x (age + time ahead)

    where the speed is a conservative allowance by class. It is where the target
    could have gone, not where it probably went. It does not trust the engine's
    error to grow with time on its own (an old Bohemia ticket reports it does
    not), and a parked truck still gets the vehicle speed: stationary now is not
    stationary at release. Only real statics get zero.

    The HQ group is never an observer. HAL's Rev.sqf reveals every known enemy
    to it, which would refresh its timestamps without anybody looking.

    Observation only. Nothing here moves, buys, tasks or decides anything, and a
    live enemy position is read in exactly one place: the truth diagnostic,
    which logs reported against actual error so the engine's numbers can be
    checked, and whose result is never fed back.
*/

ITW_CLASH_KnowledgeEnabled = missionNamespace getVariable ["ITW_CLASH_KnowledgeEnabled",true];
ITW_CLASH_KnowledgePoll = missionNamespace getVariable ["ITW_CLASH_KnowledgePoll",10];
// HAL's own known-enemy floor (HAC_fnc2.sqf:271). An observer below it does
// not know the target well enough to report on it.
ITW_CLASH_KnowledgeThreshold = missionNamespace getVariable ["ITW_CLASH_KnowledgeThreshold",0.05];
// Movement allowance, metres per second, by class.
ITW_CLASH_KnowledgeSpeedStatic = missionNamespace getVariable ["ITW_CLASH_KnowledgeSpeedStatic",0];
ITW_CLASH_KnowledgeSpeedInfantry = missionNamespace getVariable ["ITW_CLASH_KnowledgeSpeedInfantry",2];
ITW_CLASH_KnowledgeSpeedVehicle = missionNamespace getVariable ["ITW_CLASH_KnowledgeSpeedVehicle",8];
// Status thresholds.
ITW_CLASH_KnowledgeObservedAge = missionNamespace getVariable ["ITW_CLASH_KnowledgeObservedAge",60];
ITW_CLASH_KnowledgeObservedRadius = missionNamespace getVariable ["ITW_CLASH_KnowledgeObservedRadius",100];
ITW_CLASH_KnowledgeFixedError = missionNamespace getVariable ["ITW_CLASH_KnowledgeFixedError",100];
ITW_CLASH_KnowledgeFixedAge = missionNamespace getVariable ["ITW_CLASH_KnowledgeFixedAge",900];
ITW_CLASH_KnowledgeLeadRadius = missionNamespace getVariable ["ITW_CLASH_KnowledgeLeadRadius",300];
// A position can stay precise long after anyone confirmed something is still
// there. Worth is scaled by this: full, then falling to nothing.
ITW_CLASH_KnowledgeExistenceFull = missionNamespace getVariable ["ITW_CLASH_KnowledgeExistenceFull",120];
ITW_CLASH_KnowledgeExistenceZero = missionNamespace getVariable ["ITW_CLASH_KnowledgeExistenceZero",900];
// A contact moved if its reported position shifted this far between reports,
// and is still moving until it has held still this long.
ITW_CLASH_KnowledgeMovingThreshold = missionNamespace getVariable ["ITW_CLASH_KnowledgeMovingThreshold",30];
ITW_CLASH_KnowledgeMovingSettle = missionNamespace getVariable ["ITW_CLASH_KnowledgeMovingSettle",60];
// How long a look at an empty place counts.
ITW_CLASH_KnowledgeClearedWindow = missionNamespace getVariable ["ITW_CLASH_KnowledgeClearedWindow",300];
// Records older than this are forgotten entirely.
ITW_CLASH_KnowledgeForgetAfter = missionNamespace getVariable ["ITW_CLASH_KnowledgeForgetAfter",900];
// How far a support crew's own knowledge reaches when it nominates candidates.
ITW_CLASH_KnowledgeSensorRange = missionNamespace getVariable ["ITW_CLASH_KnowledgeSensorRange",6000];
ITW_CLASH_KnowledgeSummaryInterval = missionNamespace getVariable ["ITW_CLASH_KnowledgeSummaryInterval",60];
ITW_CLASH_KnowledgeTruthDiagnostic = missionNamespace getVariable ["ITW_CLASH_KnowledgeTruthDiagnostic",true];

// sideKey -> (contactKey -> record)
ITW_CLASH_KnowledgeContacts = createHashMap;
// sideKey -> [[position,time,radius,source],...]
ITW_CLASH_KnowledgeLooks = createHashMap;
// Support crews whose own knowledge nominates candidates (they are not HAL's).
ITW_CLASH_KnowledgeSensorGroups = [];
// Counter-battery fix key -> fixed offset, so a fix is a lead with an error
// rather than the firing position itself.
ITW_CLASH_KnowledgeFixOffsets = createHashMap;
// sideKey|class -> [samples,sumActual,sumError,sumAge,outside]
ITW_CLASH_KnowledgeTruth = createHashMap;
ITW_CLASH_KnowledgeClockAnomalies = 0;
ITW_CLASH_KnowledgeSummaryAt = 0;

ITW_CLASH_Knowledge_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["knowledge-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH KNOWLEDGE | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_Knowledge_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_Knowledge_fnc_ContactKey = {
    params ["_entity"];
    if (isNull _entity) exitWith {""};
    private _key = netId _entity;
    if (_key isEqualTo "" || {_key isEqualTo "0:0"}) then {_key = str _entity};
    _key
};

ITW_CLASH_Knowledge_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
    };
    groupId _group
};

// What kind of target this is, from the object. AIR is never a ground contact.
ITW_CLASH_Knowledge_fnc_Class = {
    params ["_entity"];
    if (isNull _entity) exitWith {""};
    if (_entity isKindOf "Air") exitWith {"AIR"};
    if (_entity isKindOf "CAManBase") exitWith {"INFANTRY"};
    if (_entity isKindOf "StaticWeapon") exitWith {"STATIC"};
    if (
        !isNil "ITW_CLASH_AirPicture_fnc_IsArmoredThreat"
        && {[_entity] call ITW_CLASH_AirPicture_fnc_IsArmoredThreat}
    ) exitWith {"ARMOR"};
    if (_entity isKindOf "LandVehicle" || {_entity isKindOf "Ship"}) exitWith {"VEHICLE"};
    ""
};

ITW_CLASH_Knowledge_fnc_Speed = {
    params ["_class"];
    switch (_class) do {
        case "STATIC": {ITW_CLASH_KnowledgeSpeedStatic};
        case "INFANTRY": {ITW_CLASH_KnowledgeSpeedInfantry};
        default {ITW_CLASH_KnowledgeSpeedVehicle};
    }
};

// COLOSSUS's own weights, so a contact is worth here what it is worth there.
ITW_CLASH_Knowledge_fnc_ClassWorth = {
    params ["_class"];
    switch (_class) do {
        case "INFANTRY": {missionNamespace getVariable ["ITW_CLASH_ColossusWeightInfantry",1]};
        case "ARMOR": {missionNamespace getVariable ["ITW_CLASH_ColossusWeightArmor",3]};
        case "STATIC": {missionNamespace getVariable ["ITW_CLASH_ColossusWeightStatic",0.5]};
        case "VEHICLE": {missionNamespace getVariable ["ITW_CLASH_ColossusWeightVehicle",1.5]};
        default {0};
    }
};

/*
    One observer's report on one target, or [] when it has none worth using.
    The left side of targetKnowledge is a unit; a group's leader speaks for it.
*/
ITW_CLASH_Knowledge_fnc_ReadReport = {
    params ["_observer","_target"];
    if (isNull _observer || {isNull _target}) exitWith {[]};
    private _intel = _observer targetKnowledge _target;
    if !(_intel isEqualType [] && {count _intel >= 7}) exitWith {[]};
    _intel params ["_byGroup","_byUnit","_lastSeen","","","_error","_position"];
    if (!(_byGroup isEqualTo true) && {!(_byUnit isEqualTo true)}) exitWith {[]};
    if !(_lastSeen isEqualType 0) exitWith {[]};
    // A sighting from the future, or before the mission began, means lastSeen
    // is not on the time clock. Counted and logged, never used.
    if (_lastSeen < 0 || {_lastSeen > (time + 1)}) exitWith {
        ITW_CLASH_KnowledgeClockAnomalies = ITW_CLASH_KnowledgeClockAnomalies + 1;
        []
    };
    if !(_position isEqualType [] && {count _position >= 2}) exitWith {[]};
    if !(_error isEqualType 0) then {_error = 0};
    [+_position,_lastSeen,_error max 0]
};

ITW_CLASH_Knowledge_fnc_Uncertainty = {
    params ["_record",["_ahead",0]];
    if (count _record == 0) exitWith {1e10};
    private _speed = [_record getOrDefault ["class",""]] call ITW_CLASH_Knowledge_fnc_Speed;
    private _age = (time - (_record getOrDefault ["seenAt",-1e10])) max 0;
    (_record getOrDefault ["error",0]) + _speed * (_age + (_ahead max 0))
};

ITW_CLASH_Knowledge_fnc_Status = {
    params ["_record"];
    if (count _record == 0) exitWith {"LOST"};
    private _age = (time - (_record getOrDefault ["seenAt",-1e10])) max 0;
    private _r = [_record,0] call ITW_CLASH_Knowledge_fnc_Uncertainty;
    private _sighting = (_record getOrDefault ["source",""]) isEqualTo "SIGHT";
    if (
        _sighting
        && {_age <= ITW_CLASH_KnowledgeObservedAge}
        && {_r <= ITW_CLASH_KnowledgeObservedRadius}
    ) exitWith {"OBSERVED"};
    if (
        _sighting
        && {(_record getOrDefault ["class",""]) isEqualTo "STATIC"}
        && {(_record getOrDefault ["error",1e10]) <= ITW_CLASH_KnowledgeFixedError}
        && {_age <= ITW_CLASH_KnowledgeFixedAge}
    ) exitWith {"FIXED"};
    if (_r <= ITW_CLASH_KnowledgeLeadRadius) exitWith {"LEAD"};
    "LOST"
};

ITW_CLASH_Knowledge_fnc_Existence = {
    params ["_record"];
    if (count _record == 0) exitWith {0};
    private _age = (time - (_record getOrDefault ["seenAt",-1e10])) max 0;
    if (_age <= ITW_CLASH_KnowledgeExistenceFull) exitWith {1};
    private _span = (ITW_CLASH_KnowledgeExistenceZero - ITW_CLASH_KnowledgeExistenceFull) max 1;
    (1 - ((_age - ITW_CLASH_KnowledgeExistenceFull) / _span)) max 0
};

// What a contact is worth to a plan right now: its class, discounted by how
// sure we are it is still there.
ITW_CLASH_Knowledge_fnc_Worth = {
    params ["_record"];
    ([_record getOrDefault ["class",""]] call ITW_CLASH_Knowledge_fnc_ClassWorth)
        * ([_record] call ITW_CLASH_Knowledge_fnc_Existence)
};

ITW_CLASH_Knowledge_fnc_SideContacts = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_Knowledge_fnc_SideKey;
    ITW_CLASH_KnowledgeContacts getOrDefault [_key,createHashMap,true]
};

// Every record this side holds that is not LOST, as [key,record,status].
ITW_CLASH_Knowledge_fnc_Contacts = {
    params ["_side"];
    private _result = [];
    {
        private _status = [_y] call ITW_CLASH_Knowledge_fnc_Status;
        if (_status isNotEqualTo "LOST") then {_result pushBack [_x,_y,_status]};
    } forEach ([_side] call ITW_CLASH_Knowledge_fnc_SideContacts);
    _result
};

ITW_CLASH_Knowledge_fnc_Record = {
    params ["_side","_key"];
    ([_side] call ITW_CLASH_Knowledge_fnc_SideContacts) getOrDefault [_key,createHashMap]
};

/*
    Looks: a place someone of ours had eyes on, and when. The UAV stamps its
    footprint; friendly presence near an objective stamps that objective.
*/
ITW_CLASH_Knowledge_fnc_StampLook = {
    params ["_side","_position",["_radius",800],["_source","eyes"]];
    if (_position isEqualTo []) exitWith {false};
    private _key = [_side] call ITW_CLASH_Knowledge_fnc_SideKey;
    private _looks = ITW_CLASH_KnowledgeLooks getOrDefault [_key,[],true];
    private _index = _looks findIf {
        ((_x#0) distance2D _position) <= 50 && {(_x#2) isEqualTo _radius}
    };
    if (_index >= 0) then {
        (_looks#_index) set [1,time];
    } else {
        _looks pushBack [+_position,time,_radius,_source];
    };
    true
};

// _sources limits which kinds of look count; empty means all of them.
ITW_CLASH_Knowledge_fnc_LookedAt = {
    params ["_side","_position",["_window",-1],["_sources",[]]];
    if (_position isEqualTo []) exitWith {false};
    if (_window < 0) then {_window = ITW_CLASH_KnowledgeClearedWindow};
    private _key = [_side] call ITW_CLASH_Knowledge_fnc_SideKey;
    private _looks = ITW_CLASH_KnowledgeLooks getOrDefault [_key,[]];
    (_looks findIf {
        (time - (_x#1)) <= _window
        && {((_x#0) distance2D _position) <= (_x#2)}
        && {_sources isEqualTo [] || {(_x#3) in _sources}}
    }) >= 0
};

// [observed, fixed, leads, oldest age] inside a radius, by reported position.
ITW_CLASH_Knowledge_fnc_Census = {
    params ["_side","_position","_radius"];
    private _observed = 0;
    private _fixed = 0;
    private _leads = 0;
    private _oldest = 0;
    {
        _x params ["","_record","_status"];
        if (((_record get "position") distance2D _position) > _radius) then {continue};
        switch (_status) do {
            case "OBSERVED": {_observed = _observed + 1};
            case "FIXED": {_fixed = _fixed + 1};
            case "LEAD": {_leads = _leads + 1};
        };
        _oldest = _oldest max (time - (_record get "seenAt"));
    } forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);
    [_observed,_fixed,_leads,round _oldest]
};

ITW_CLASH_Knowledge_fnc_IntelState = {
    params ["_side","_position",["_radius",-1]];
    if (_position isEqualTo []) exitWith {"UNOBSERVED"};
    if (_radius < 0) then {
        _radius = missionNamespace getVariable ["ITW_CLASH_ColossusObjectiveRadius",500];
    };
    ([_side,_position,_radius] call ITW_CLASH_Knowledge_fnc_Census) params [
        "_observed","_fixed","_leads"
    ];
    if ((_observed + _fixed) > 0) exitWith {"RECENT_CONTACT"};
    if (_leads > 0) exitWith {"STALE_CONTACT"};
    if ([_side,_position] call ITW_CLASH_Knowledge_fnc_LookedAt) exitWith {"RECENTLY_CLEARED"};
    "UNOBSERVED"
};

// Enemy strength at a place, counted from reported positions only.
ITW_CLASH_Knowledge_fnc_ReportedStrength = {
    params ["_side","_position","_radius"];
    private _score = 0;
    private _count = 0;
    {
        _x params ["","_record"];
        if (((_record get "position") distance2D _position) > _radius) then {continue};
        _score = _score + ([_record] call ITW_CLASH_Knowledge_fnc_Worth);
        _count = _count + 1;
    } forEach ([_side] call ITW_CLASH_Knowledge_fnc_Contacts);
    [_score,_count]
};

// A support crew group whose own knowledge should nominate candidates.
ITW_CLASH_Knowledge_fnc_RegisterSensorGroup = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    ITW_CLASH_KnowledgeSensorGroups = ITW_CLASH_KnowledgeSensorGroups select {!isNull _x};
    ITW_CLASH_KnowledgeSensorGroups pushBackUnique _group;
    true
};

/*
    The truth diagnostic. The ONLY place in this file that reads where an enemy
    really is, and what it learns goes to the log and nowhere else.
*/
ITW_CLASH_Knowledge_fnc_TruthSample = {
    params ["_sideKey","_record"];
    if (!ITW_CLASH_KnowledgeTruthDiagnostic) exitWith {false};
    private _entity = _record getOrDefault ["entity",objNull];
    if (isNull _entity || {!alive _entity}) exitWith {false};
    private _actual = (_record get "position") distance2D (getPosATL _entity);
    private _r = [_record,0] call ITW_CLASH_Knowledge_fnc_Uncertainty;
    private _bucket = _sideKey + "|" + (_record get "class");
    private _stats = ITW_CLASH_KnowledgeTruth getOrDefault [_bucket,[0,0,0,0,0],true];
    _stats set [0,(_stats#0) + 1];
    _stats set [1,(_stats#1) + _actual];
    _stats set [2,(_stats#2) + (_record get "error")];
    _stats set [3,(_stats#3) + ((time - (_record get "seenAt")) max 0)];
    if (_actual > _r) then {_stats set [4,(_stats#4) + 1]};
    true
};

ITW_CLASH_Knowledge_fnc_Update = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_Knowledge_fnc_SideKey;
    private _contacts = [_side] call ITW_CLASH_Knowledge_fnc_SideContacts;
    private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
        [_side] call ITW_CLASH_fnc_GetCommanderForSide
    };
    private _now = time;

    private _observers = allGroups select {
        side _x isEqualTo _side
        && {_x isNotEqualTo _hq}
        && {!isNull leader _x}
        && {alive leader _x}
    };

    private _candidates = [];
    if (!isNull _hq) then {
        {
            if (!isNull _x) then {
                private _veh = vehicle _x;
                if (alive _veh) then {_candidates pushBackUnique _veh};
            };
        } forEach (_hq getVariable ["RydHQ_KnEnemies",[]]);
    };
    ITW_CLASH_KnowledgeSensorGroups = ITW_CLASH_KnowledgeSensorGroups select {!isNull _x};
    {
        private _sensor = _x;
        if (side _sensor isNotEqualTo _side) then {continue};
        private _leader = leader _sensor;
        if (isNull _leader || {!alive _leader}) then {continue};
        {
            if (!isNull _x) then {
                private _veh = vehicle _x;
                if (alive _veh) then {_candidates pushBackUnique _veh};
            };
        } forEach (_leader targets [true,ITW_CLASH_KnowledgeSensorRange]);
    } forEach ITW_CLASH_KnowledgeSensorGroups;

    private _seen = [];
    {
        private _target = _x;
        private _class = [_target] call ITW_CLASH_Knowledge_fnc_Class;
        if (_class in ["","AIR"]) then {continue};
        private _speed = [_class] call ITW_CLASH_Knowledge_fnc_Speed;

        // Each observer's own report, projected on its own. The best single
        // report wins; nothing is combined across observers.
        private _best = [];
        private _bestR = 1e10;
        private _bestObserver = grpNull;
        {
            private _observerGroup = _x;
            if ((_observerGroup knowsAbout _target) < ITW_CLASH_KnowledgeThreshold) then {continue};
            private _report = [leader _observerGroup,_target] call ITW_CLASH_Knowledge_fnc_ReadReport;
            if (_report isEqualTo []) then {continue};
            _report params ["","_reportSeenAt","_reportError"];
            private _r = _reportError + _speed * ((_now - _reportSeenAt) max 0);
            if (_r < _bestR) then {
                _bestR = _r;
                _best = _report;
                _bestObserver = _observerGroup;
            };
        } forEach _observers;
        if (_best isEqualTo []) then {continue};
        _best params ["_position","_seenAt","_error"];

        private _contactKey = [_target] call ITW_CLASH_Knowledge_fnc_ContactKey;
        _seen pushBack _contactKey;
        private _record = _contacts getOrDefault [_contactKey,createHashMap];
        if (count _record == 0) then {
            _record = createHashMapFromArray [
                ["entity",_target],["class",_class],["source","SIGHT"],
                ["position",_position],["seenAt",_seenAt],["error",_error],
                ["firstSeen",_seenAt],["movedAt",-1e10],["moving",false],
                ["observer",[_bestObserver] call ITW_CLASH_Knowledge_fnc_GroupId]
            ];
            _contacts set [_contactKey,_record];
        } else {
            _record set ["class",_class];
            if (_seenAt > (_record get "seenAt")) then {
                private _shift = (_record get "position") distance2D _position;
                if (_shift > ITW_CLASH_KnowledgeMovingThreshold) then {
                    _record set ["moving",true];
                    _record set ["movedAt",_seenAt];
                } else {
                    if ((_seenAt - (_record get "movedAt")) > ITW_CLASH_KnowledgeMovingSettle) then {
                        _record set ["moving",false];
                    };
                };
            };
            private _heldR = [_record,0] call ITW_CLASH_Knowledge_fnc_Uncertainty;
            if (_bestR <= _heldR || {_seenAt > (_record get "seenAt")}) then {
                _record set ["position",_position];
                _record set ["seenAt",_seenAt];
                _record set ["error",_error];
                _record set ["observer",[_bestObserver] call ITW_CLASH_Knowledge_fnc_GroupId];
            };
        };
        [_key,_record] call ITW_CLASH_Knowledge_fnc_TruthSample;
    } forEach _candidates;

    // Counter-battery fixes become leads. The fix holds the firing position
    // itself, so each gets one fixed offset inside its error: a lead with an
    // error, not a grid square handed over for free.
    if (!isNil "ITW_CLASH_CounterBatteryFixes") then {
        {
            private _fixKey = _x;
            _y params [
                ["_firePosition",[]],["_first",0],["_last",0],["_rounds",0],
                ["_fixError",0],["_shooterClass",""]
            ];
            if (_firePosition isEqualTo []) then {continue};
            private _contactKey = "CB:" + _fixKey;
            _seen pushBack _contactKey;
            private _offset = ITW_CLASH_KnowledgeFixOffsets getOrDefault [_contactKey,[]];
            if (_offset isEqualTo []) then {
                _offset = [random _fixError,random 360];
                ITW_CLASH_KnowledgeFixOffsets set [_contactKey,_offset];
            };
            _offset params ["_offsetDistance","_offsetBearing"];
            private _reported = _firePosition getPos [_offsetDistance,_offsetBearing];
            private _fixClass = if (
                _shooterClass isNotEqualTo "" && {_shooterClass isKindOf "StaticWeapon"}
            ) then {"STATIC"} else {"VEHICLE"};
            _contacts set [_contactKey,createHashMapFromArray [
                ["entity",objNull],["class",_fixClass],["source","COUNTER_BATTERY"],
                ["position",_reported],["seenAt",_last],["error",_fixError],
                ["firstSeen",_first],["movedAt",-1e10],["moving",false],
                ["observer","counter-battery"]
            ]];
        } forEach (ITW_CLASH_CounterBatteryFixes getOrDefault [_key,createHashMap]);
    };

    // Forget what is dead, gone, or too old to matter.
    {
        private _contactKey = _x;
        private _record = _y;
        private _entity = _record getOrDefault ["entity",objNull];
        private _drop = switch (true) do {
            case ((_record get "source") isEqualTo "COUNTER_BATTERY"): {!(_contactKey in _seen)};
            case (isNull _entity || {!alive _entity}): {true};
            case ((_now - (_record get "seenAt")) > ITW_CLASH_KnowledgeForgetAfter): {true};
            default {false};
        };
        if (_drop) then {_contacts deleteAt _contactKey};
    } forEach (+_contacts);

    // Friendly presence near an objective is a look at it.
    if (!isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds" && {!isNil "ITW_Objectives"}) then {
        private _ours = [];
        {
            if (alive _x) then {_ours pushBack (getPosATL vehicle _x)};
        } forEach (units _side);
        private _eyes = missionNamespace getVariable ["ITW_CLASH_AirPictureObservedRadius",800];
        {
            private _index = _x;
            if (_index < 0 || {_index >= count ITW_Objectives}) then {continue};
            private _objectivePos = +(ITW_Objectives#_index#ITW_OBJ_POS);
            if (_objectivePos isEqualTo []) then {continue};
            if ((_ours findIf {(_x distance2D _objectivePos) <= _eyes}) >= 0) then {
                [_side,_objectivePos,_eyes,"friendly"] call ITW_CLASH_Knowledge_fnc_StampLook;
            };
        } forEach (call ITW_CLASH_Generation_fnc_ActiveObjectiveIds);
    };

    private _looks = ITW_CLASH_KnowledgeLooks getOrDefault [_key,[],true];
    ITW_CLASH_KnowledgeLooks set [_key,_looks select {(_now - (_x#1)) <= ITW_CLASH_KnowledgeClearedWindow}];
    true
};

// One line per objective per side, and the truth diagnostic, on a slow clock.
ITW_CLASH_Knowledge_fnc_Summary = {
    params ["_sides"];
    {
        private _side = _x;
        private _hq = if (isNil "ITW_CLASH_fnc_GetCommanderForSide") then {grpNull} else {
            [_side] call ITW_CLASH_fnc_GetCommanderForSide
        };
        private _sign = if (isNull _hq) then {str _side} else {_hq getVariable ["RydHQ_CodeSign","?"]};
        private _radius = missionNamespace getVariable ["ITW_CLASH_ColossusObjectiveRadius",500];
        if (!isNil "ITW_CLASH_Generation_fnc_ActiveObjectiveIds" && {!isNil "ITW_Objectives"}) then {
            {
                private _index = _x;
                if (_index < 0 || {_index >= count ITW_Objectives}) then {continue};
                private _objectivePos = +(ITW_Objectives#_index#ITW_OBJ_POS);
                ([_side,_objectivePos,_radius] call ITW_CLASH_Knowledge_fnc_Census) params [
                    "_observed","_fixed","_leads","_oldest"
                ];
                ["objective",[
                    _sign,_index,
                    [_side,_objectivePos,_radius] call ITW_CLASH_Knowledge_fnc_IntelState,
                    _observed,_fixed,_leads,_oldest
                ]] call ITW_CLASH_Knowledge_fnc_Log;
            } forEach (call ITW_CLASH_Generation_fnc_ActiveObjectiveIds);
        };
        ["side",[
            _sign,
            count ([_side] call ITW_CLASH_Knowledge_fnc_SideContacts),
            count ([_side] call ITW_CLASH_Knowledge_fnc_Contacts),
            count (ITW_CLASH_KnowledgeLooks getOrDefault [[_side] call ITW_CLASH_Knowledge_fnc_SideKey,[]])
        ]] call ITW_CLASH_Knowledge_fnc_Log;
    } forEach _sides;

    // Reported against actual, per side and class. Read-only, then reset.
    {
        _y params ["_samples","_sumActual","_sumError","_sumAge","_outside"];
        if (_samples > 0) then {
            ["truth",[
                _x,_samples,
                round (_sumActual / _samples),
                round (_sumError / _samples),
                round (_sumAge / _samples),
                (round ((_outside / _samples) * 100)) / 100
            ]] call ITW_CLASH_Knowledge_fnc_Log;
        };
    } forEach ITW_CLASH_KnowledgeTruth;
    ITW_CLASH_KnowledgeTruth = createHashMap;

    if (ITW_CLASH_KnowledgeClockAnomalies > 0) then {
        ["clock-anomaly",[ITW_CLASH_KnowledgeClockAnomalies]] call ITW_CLASH_Knowledge_fnc_Log;
        ITW_CLASH_KnowledgeClockAnomalies = 0;
    };
    true
};

[] spawn {
    scriptName "ITW_CLASH_Knowledge";
    waitUntil {
        sleep 1;
        (
            !isNil "ITW_CLASH_fnc_GetCommanderForSide"
            && {missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false]}
        ) || {missionNamespace getVariable ["ITW_GameOver",false]}
    };

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_KnowledgeEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                [_x] call ITW_CLASH_Knowledge_fnc_Update;
            } forEach _sides;
            if ((time - ITW_CLASH_KnowledgeSummaryAt) >= ITW_CLASH_KnowledgeSummaryInterval) then {
                ITW_CLASH_KnowledgeSummaryAt = time;
                [_sides] call ITW_CLASH_Knowledge_fnc_Summary;
            };
        };
        sleep ITW_CLASH_KnowledgePoll;
    };
};

ITW_CLASH_KnowledgeReady = true;
diag_log format [
    "CLASH BOOT | knowledge-ready | version=%1 poll=%2 speeds=%3/%4/%5 observed=%6s/%7m fixed=%8m/%9s lead=%10m existence=%11-%12s cleared=%13s truth=%14 hqObserver=false reportsMerged=false observeOnly=true",
    ITW_CLASH_KnowledgeVersion,
    ITW_CLASH_KnowledgePoll,
    ITW_CLASH_KnowledgeSpeedStatic,
    ITW_CLASH_KnowledgeSpeedInfantry,
    ITW_CLASH_KnowledgeSpeedVehicle,
    ITW_CLASH_KnowledgeObservedAge,
    ITW_CLASH_KnowledgeObservedRadius,
    ITW_CLASH_KnowledgeFixedError,
    ITW_CLASH_KnowledgeFixedAge,
    ITW_CLASH_KnowledgeLeadRadius,
    ITW_CLASH_KnowledgeExistenceFull,
    ITW_CLASH_KnowledgeExistenceZero,
    ITW_CLASH_KnowledgeClearedWindow,
    ITW_CLASH_KnowledgeTruthDiagnostic
];
true
