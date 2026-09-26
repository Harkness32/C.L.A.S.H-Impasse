#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ServiceCapacityPolicyStarted",false]) exitWith {true};

ITW_CLASH_ServiceCapacityPolicyStarted = true;
ITW_CLASH_ServiceCapacityPolicyVersion = 1;
ITW_CLASH_ServiceCapacityPolicyReady = false;

ITW_CLASH_ServiceCapacity_ExcessSeatWeight = missionNamespace getVariable [
    "ITW_CLASH_ServiceCapacity_ExcessSeatWeight",100
];
ITW_CLASH_ServiceCapacity_TicketWeight = missionNamespace getVariable [
    "ITW_CLASH_ServiceCapacity_TicketWeight",3
];
ITW_CLASH_ServiceCapacity_DualRolePenalty = missionNamespace getVariable [
    "ITW_CLASH_ServiceCapacity_DualRolePenalty",30
];
ITW_CLASH_ServiceCapacity_UnknownPenalty = missionNamespace getVariable [
    "ITW_CLASH_ServiceCapacity_UnknownPenalty",10000
];

if (isNil "ITW_CLASH_ServiceCapacity_ClassCapacityOverrides") then {
    ITW_CLASH_ServiceCapacity_ClassCapacityOverrides = createHashMap;
};
if (isNil "ITW_CLASH_ServiceCapacity_ClassScoreAdjustments") then {
    ITW_CLASH_ServiceCapacity_ClassScoreAdjustments = createHashMap;
};
if (isNil "ITW_CLASH_ServiceCapacity_ContextScoreAdjustments") then {
    ITW_CLASH_ServiceCapacity_ContextScoreAdjustments = createHashMap;
};

ITW_CLASH_ServiceCapacity_fnc_ClassFromVariant = {
    params ["_variant"];
    if (_variant isEqualType []) exitWith {
        if (_variant isEqualTo []) then {""} else {_variant#0}
    };
    if (_variant isEqualType "") exitWith {_variant};
    ""
};

ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats = {
    params ["_class"];
    if !(_class isEqualType "") exitWith {-1};
    if (_class isEqualTo "") exitWith {-1};

    private _key = toLowerANSI _class;
    private _override =
        ITW_CLASH_ServiceCapacity_ClassCapacityOverrides getOrDefault [_key,-1];
    if (_override isEqualType 0 && {_override >= 0}) exitWith {round _override};

    private _cfg = configFile >> "CfgVehicles" >> _class;
    if !(isClass _cfg) exitWith {-1};

    private _capacity = round getNumber (_cfg >> "transportSoldier");
    private _countCargoTurrets = {
        params ["_node"];
        private _count = 0;
        {
            if (getNumber (_x >> "showAsCargo") > 0) then {
                _count = _count + 1;
            };
            if (isClass (_x >> "Turrets")) then {
                _count = _count + ([(_x >> "Turrets")] call _countCargoTurrets);
            };
        } forEach (configProperties [_node,"isClass _x",true]);
        _count
    };
    if (isClass (_cfg >> "Turrets")) then {
        _capacity = _capacity + ([(_cfg >> "Turrets")] call _countCargoTurrets);
    };
    _capacity max 0
};

ITW_CLASH_ServiceCapacity_fnc_ScoreClass = {
    params ["_class","_vehDef","_seatCount",["_context","TRANSPORT"]];
    _seatCount = (round _seatCount) max 1;
    _context = toUpperANSI _context;

    private _capacity = [_class] call
        ITW_CLASH_ServiceCapacity_fnc_ConfigCargoSeats;
    private _capacityKnown = _capacity >= 0;
    if (_capacityKnown && {_capacity < _seatCount}) exitWith {
        [1e12,_capacity,false,0,0]
    };

    private _fitCapacity = if (_capacityKnown) then {_capacity} else {_seatCount + 32};
    private _excessSeats = (_fitCapacity - _seatCount) max 0;

    private _ticketCost = 0;
    private _role = ITW_VEH_ROLE_TRANSPORT;
    if (_vehDef isEqualType [] && {count _vehDef > ITW_VEH_REQD_TICKETS}) then {
        _ticketCost = _vehDef#ITW_VEH_REQD_TICKETS;
        _role = _vehDef#ITW_VEH_ROLE;
    };

    private _score =
        (_excessSeats * ITW_CLASH_ServiceCapacity_ExcessSeatWeight)
        + (_ticketCost * ITW_CLASH_ServiceCapacity_TicketWeight);

    if (_role != ITW_VEH_ROLE_TRANSPORT) then {
        _score = _score + ITW_CLASH_ServiceCapacity_DualRolePenalty;
    };
    if (!_capacityKnown) then {
        _score = _score + ITW_CLASH_ServiceCapacity_UnknownPenalty;
    };

    private _classKey = toLowerANSI _class;
    private _manual =
        ITW_CLASH_ServiceCapacity_ClassScoreAdjustments getOrDefault [_classKey,0];
    if !(_manual isEqualType 0) then {_manual = 0};
    private _contextManual =
        ITW_CLASH_ServiceCapacity_ContextScoreAdjustments getOrDefault [
            _context + "|" + _classKey,0
        ];
    if !(_contextManual isEqualType 0) then {_contextManual = 0};
    _score = _score + _manual + _contextManual;

    private _cfg = configFile >> "CfgVehicles" >> _class;
    private _maxSpeed = if (isClass _cfg) then {
        getNumber (_cfg >> "maxSpeed")
    } else {0};
    _score = _score - ((((_maxSpeed max 0) min 350) / 350));

    [_score,_capacity,_capacityKnown,_ticketCost,_maxSpeed]
};

ITW_CLASH_ServiceCapacity_fnc_RankVariants = {
    params ["_seatCount","_vehDefs",["_mode","ANY"],["_context","TRANSPORT"]];
    _seatCount = (round _seatCount) max 1;
    _mode = toUpperANSI _mode;
    _context = toUpperANSI _context;

    private _ranked = [];
    {
        private _vehDef = _x;
        if !(_vehDef isEqualType [] && {count _vehDef > ITW_VEH_CLASSES}) then {continue};
        {
            private _variant = _x;
            private _class = [_variant] call
                ITW_CLASH_ServiceCapacity_fnc_ClassFromVariant;
            if (_class isEqualTo "") then {continue};
            private _cfg = configFile >> "CfgVehicles" >> _class;
            if !(isClass _cfg) then {continue};

            private _modeOK = switch (_mode) do {
                case "AIR": {_class isKindOf "Helicopter"};
                case "GROUND": {_class isKindOf "LandVehicle"};
                default {true};
            };
            if (!_modeOK) then {continue};

            private _scoreInfo = [
                _class,_vehDef,_seatCount,_context
            ] call ITW_CLASH_ServiceCapacity_fnc_ScoreClass;
            _scoreInfo params [
                "_score","_capacity","_capacityKnown","_ticketCost","_maxSpeed"
            ];
            if (_score >= 1e11) then {continue};

            _ranked pushBack [
                _score,_vehDef,_variant,_class,_capacity,_capacityKnown,
                _ticketCost,_maxSpeed
            ];
        } forEach (_vehDef#ITW_VEH_CLASSES);
    } forEach _vehDefs;

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

ITW_CLASH_ServiceCapacityPolicyReady = true;
diag_log format [
    "CLASH BOOT | service-capacity-policy-ready | version=%1 classnamesHardcoded=false capacityWeighted=true ticketAware=true modOverrides=true",
    ITW_CLASH_ServiceCapacityPolicyVersion
];
true
