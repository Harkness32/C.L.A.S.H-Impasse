#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_GroundMEDEVAC_VehiclePolicyStarted",false]) exitWith {};
ITW_CLASH_GroundMEDEVAC_VehiclePolicyStarted = true;
ITW_CLASH_GroundMEDEVAC_VehiclePolicyVersion = 1;

/*
    Ground MEDEVAC vehicle policy

    C.L.A.S.H. defines the recovery requirement; the active Impasse faction
    supplies the hardware. No faction or vehicle classname is hardcoded here.

    Survivor-count doctrine:
      1-3  = LIGHT requirement
      4-6  = MEDIUM requirement
      7+   = HEAVY requirement

    Selection is continuous rather than a hard bucket lock. Every candidate must
    still be affordable and physically capable of carrying the survivors. Among
    viable classes, prefer the closest cargo fit, soft transport over APC/dual-role
    hardware, medical variants when otherwise comparable, and faster vehicles as
    a small tie-breaker. Post-spawn cargo validation remains authoritative.

    Future faction packages may populate these maps before this script runs:
      ITW_CLASH_GroundMEDEVAC_ClassScoreAdjustments
        classname -> scalar score adjustment (negative = prefer, positive = avoid)
      ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides
        classname -> bool explicit medical classification

    Those are policy hints only. They never bypass tickets, land-vehicle checks,
    or survivor capacity requirements.
*/

ITW_CLASH_GroundMEDEVAC_LightMaxSurvivors = 3;
ITW_CLASH_GroundMEDEVAC_MediumMaxSurvivors = 6;

if (isNil "ITW_CLASH_GroundMEDEVAC_ClassScoreAdjustments") then {
    ITW_CLASH_GroundMEDEVAC_ClassScoreAdjustments = createHashMap;
};
if (isNil "ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides") then {
    ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides = createHashMap;
};

// Ground MEDEVAC itself is loaded asynchronously from init.sqf. Install the
// policy only after the native selector and Impasse vehicle spawner exist.
waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle" && {
        !isNil "ITW_CLASH_GroundMEDEVAC_fnc_Log" && {
            !isNil "ITW_AtkSpawnVeh"
        }
    }
};

ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle_Base = ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle;

ITW_CLASH_GroundMEDEVAC_fnc_ClassFromVariant = {
    params ["_variant"];
    if (_variant isEqualType []) exitWith {
        if (_variant isEqualTo []) then {""} else {_variant#0}
    };
    if (_variant isEqualType "") exitWith {_variant};
    ""
};

ITW_CLASH_GroundMEDEVAC_fnc_IsMedicalClass = {
    params ["_class"];
    if !(_class isEqualType "") exitWith {false};
    if (_class isEqualTo "") exitWith {false};

    private _key = toLowerANSI _class;
    private _override = ITW_CLASH_GroundMEDEVAC_MedicalClassOverrides getOrDefault [_key,-1];
    if (_override isEqualType true) exitWith {_override};

    private _cfg = configFile >> "CfgVehicles" >> _class;
    private _name = toLowerANSI (
        _class + " " + getText (_cfg >> "displayName")
    );
    (_name find "ambulance") >= 0 || {
        (_name find "medical") >= 0 || {(_name find "medevac") >= 0}
    }
};

ITW_CLASH_GroundMEDEVAC_fnc_GetRequirementProfile = {
    params ["_seatCount"];
    if (_seatCount <= ITW_CLASH_GroundMEDEVAC_LightMaxSurvivors) exitWith {"light"};
    if (_seatCount <= ITW_CLASH_GroundMEDEVAC_MediumMaxSurvivors) exitWith {"medium"};
    "heavy"
};

ITW_CLASH_GroundMEDEVAC_fnc_RankVehicleVariants = {
    params ["_seatCount","_candidates"];
    private _profile = [_seatCount] call ITW_CLASH_GroundMEDEVAC_fnc_GetRequirementProfile;
    private _ranked = [];

    {
        private _vehDef = _x;
        {
            private _variant = _x;
            private _class = [_variant] call ITW_CLASH_GroundMEDEVAC_fnc_ClassFromVariant;
            if (_class isEqualTo "") then {continue};

            private _cfg = configFile >> "CfgVehicles" >> _class;
            if !(isClass _cfg) then {continue};

            // transportSoldier is only a pre-spawn estimate. A zero/missing
            // value is kept as a low-priority unknown rather than rejected so
            // unusual mod configs can still pass the authoritative post-spawn
            // emptyPositions "cargo" check.
            private _capacity = round getNumber (_cfg >> "transportSoldier");
            private _capacityKnown = _capacity > 0;
            if (_capacityKnown && {_capacity < _seatCount}) then {continue};

            private _fitCapacity = if (_capacityKnown) then {
                _capacity
            } else {
                _seatCount + 24
            };
            private _excessSeats = (_fitCapacity - _seatCount) max 0;
            private _score = _excessSeats * 20;

            // Ground MEDEVAC operates after the squad has broken contact, so a
            // soft road vehicle should normally beat armor of similar capacity.
            // APCs remain fully valid when they are the sensible/available fit.
            if ((_vehDef#ITW_VEH_TYPE) == ITW_TYPE_VEH_APC) then {
                _score = _score + (switch (_profile) do {
                    case "light": {100};
                    case "medium": {75};
                    default {50};
                });
            };

            // Dedicated transports are preferred over combat vehicles borrowed
            // as casualty carriers when both can satisfy the same requirement.
            if ((_vehDef#ITW_VEH_ROLE) != ITW_VEH_ROLE_TRANSPORT) then {
                _score = _score + 35;
            };

            private _medical = [_class] call ITW_CLASH_GroundMEDEVAC_fnc_IsMedicalClass;
            if (_medical) then {_score = _score - 12};

            // Speed is intentionally only a tie-breaker: capacity/vehicle class
            // must dominate so a fast oversized truck does not beat a correctly
            // sized light carrier merely because its config maxSpeed is higher.
            private _maxSpeed = getNumber (_cfg >> "maxSpeed");
            _score = _score - ((((_maxSpeed max 0) min 200) / 100));

            private _manualAdjustment = ITW_CLASH_GroundMEDEVAC_ClassScoreAdjustments getOrDefault [
                toLowerANSI _class,0
            ];
            if !(_manualAdjustment isEqualType 0) then {_manualAdjustment = 0};
            _score = _score + _manualAdjustment;

            if (!_capacityKnown) then {_score = _score + 500};

            _ranked pushBack [
                _score,_vehDef,_variant,_class,_capacity,_medical,
                _profile,_maxSpeed,_manualAdjustment
            ];
        } forEach (_vehDef#ITW_VEH_CLASSES);
    } forEach _candidates;

    // Avoid relying on nested-array sort semantics. Pull the lowest score each
    // pass; Ground MEDEVAC pools are small enough that clarity beats cleverness.
    private _ordered = [];
    while {_ranked isNotEqualTo []} do {
        private _bestIndex = 0;
        private _bestScore = (_ranked#0)#0;
        for "_i" from 1 to ((count _ranked) - 1) do {
            private _score = (_ranked#_i)#0;
            if (_score < _bestScore) then {
                _bestIndex = _i;
                _bestScore = _score;
            };
        };
        _ordered pushBack (_ranked deleteAt _bestIndex);
    };
    _ordered
};

ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle = {
    params ["_seatCount","_spawnInfo"];
    if (_spawnInfo isEqualTo [] || {
        isNil "ITW_AtkReconstitutionTransportContext" || {
            ITW_AtkReconstitutionTransportContext isEqualTo []
        }
    }) exitWith {[]};

    ITW_AtkReconstitutionTransportContext params [
        "_transport","_dualVeh","_crewTypes","_unitTypes","_side"
    ];
    if (!isNil "ITW_EnemySide" && {_side != ITW_EnemySide}) exitWith {[]};

    // The active faction's live Impasse pool remains authoritative. Ground
    // recovery may exceed the concurrent vehicle count cap, but never tickets.
    private _candidates = (_transport + _dualVeh) select {
        (_x#ITW_VEH_TYPE) in [ITW_TYPE_VEH_CAR,ITW_TYPE_VEH_APC] && {
            (_x#ITW_VEH_REQD_TICKETS) <= (_x#ITW_VEH_CURR_TICKETS)
        }
    };
    if (_candidates isEqualTo []) exitWith {[]};

    private _ranked = [_seatCount,_candidates] call ITW_CLASH_GroundMEDEVAC_fnc_RankVehicleVariants;
    if (_ranked isEqualTo []) exitWith {
        ["vehicle-policy-fallback",[_seatCount,"no-ranked-variant"]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        [_seatCount,_spawnInfo] call ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle_Base
    };

    _spawnInfo params ["_spawnPos","_baseIndex","_spawnSource"];
    private _result = [];
    private _selectedMeta = [];

    {
        if (_result isNotEqualTo []) then {continue};
        _x params [
            "_score","_vehDef","_variant","_class","_estimatedCapacity",
            "_medical","_profile","_maxSpeed","_manualAdjustment"
        ];

        private _countBefore = _vehDef#ITW_VEH_COUNT;
        private _maxConfigured = _vehDef#ITW_VEH_MAX;
        private _bypassingCountCap = _countBefore >= _maxConfigured;

        // Spawn the exact ranked variant while keeping tickets/counts attached
        // to the original Impasse vehicle definition.
        private _spawnDef = +_vehDef;
        _spawnDef set [ITW_VEH_CLASSES,[_variant]];
        private _veh = [
            _spawnDef,_crewTypes,_unitTypes,_side,_spawnPos
        ] call ITW_AtkSpawnVeh;
        if (isNull _veh) then {continue};

        private _crewGroup = group driver _veh;
        if !(_veh isKindOf "LandVehicle") then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        private _actualCapacity = _veh emptyPositions "cargo";
        if (_actualCapacity < _seatCount) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
            if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
            continue;
        };

        ITW_TICKET_SEM_CHECK;
        ITW_VEH_COUNT_INCR(_vehDef);
        _veh setVariable ["ITW_VehDef",_vehDef];
        ITW_TICKET_SEM_CHECK;
        ITW_TICKET_REDUCE(_vehDef);

        _veh setVariable ["ITW_CLASH_GroundMEDEVAC",true,true];
        _crewGroup setVariable ["ITW_CLASH_GroundMEDEVAC",true];
        _crewGroup setVariable ["noHeadless",true];
        _crewGroup setVariable ["itwInitGrp",true,true];
        _crewGroup allowFleeing 0;
        _crewGroup enableAttack false;
        _crewGroup setBehaviourStrong "CARELESS";
        _crewGroup setCombatMode "BLUE";
        _crewGroup setSpeedMode "FULL";
        _veh forceFollowRoad true;
        _veh limitSpeed 90;

        if (!isNil "ITW_AtkVehRemoveMagazines") then {
            [_veh] remoteExec ["ITW_AtkVehRemoveMagazines",_veh];
        };
        ALLOW_DAMAGE(_veh,true);
        {ALLOW_DAMAGE(_x,true)} forEach crew _veh;
        {_x addCuratorEditableObjects [[_veh] + units _crewGroup,true]} forEach allCurators;

        if (_bypassingCountCap) then {
            ["cap-bypass",[
                typeOf _veh,_countBefore,_maxConfigured,_seatCount
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        };

        _result = [_veh,_crewGroup,_vehDef,_baseIndex,_spawnSource,+_spawnPos];
        _selectedMeta = [
            typeOf _veh,_profile,_seatCount,_actualCapacity,_estimatedCapacity,
            _medical,round _score,_maxSpeed,_manualAdjustment,
            _vehDef#ITW_VEH_TYPE,_vehDef#ITW_VEH_ROLE
        ];
    } forEach _ranked;

    if (_result isEqualTo []) exitWith {
        ["vehicle-policy-fallback",[_seatCount,"ranked-spawns-failed"]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        [_seatCount,_spawnInfo] call ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle_Base
    };

    ["vehicle-selected",_selectedMeta] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
    ["spawn-selected",[
        typeOf (_result#0),_baseIndex,_spawnSource,_seatCount,
        _selectedMeta#5,_selectedMeta#1,_selectedMeta#3
    ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
    _result
};

diag_log format [
    "CLASH BOOT | ground-medevac-vehicle-policy-ready | version=%1 routing=capability-score lightMax=%2 mediumMax=%3 factionPool=true",
    ITW_CLASH_GroundMEDEVAC_VehiclePolicyVersion,
    ITW_CLASH_GroundMEDEVAC_LightMaxSurvivors,
    ITW_CLASH_GroundMEDEVAC_MediumMaxSurvivors
];

true