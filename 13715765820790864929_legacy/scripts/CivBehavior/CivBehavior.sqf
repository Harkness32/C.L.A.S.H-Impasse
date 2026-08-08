// Civilian Behavior 
//
// CivBehavior = compileFinal preprocessFileLineNumbers "scripts\CivBehavior\CivBehavior.sqf";
// _handle = [_center,_radius,_number,_types,_unitInit,_path] call CivBehavior;
//
// to cancel and clean up area:  [_handle] call CivBehavior; 
//
// _center:    center point of civilian wandering, _handle returned from previous call to cancel, or [_handle,newCenter] to move the center
// _radius:    radius of civilian wandering
// _unitCount: number of civilians to be present
// _unitTypes: class of units to use as civilians; [] for CIV_F units appropriate to the map; (default [])
// _unitInit:  script to run on unit after created.    '_this' is the unit.  (default {removeAllWeapons _this})
// _unitEnd:   script to run on unit before deletion.  '_this' is the unit.  (default {})
// _path:      path to this file (default is "scripts\CivBehavior\")
#include "defines.inc"

if (!isServer) exitWith {};

params ["_center","_radius","_unitCount",["_unitTypes",[]],["_unitInit",{removeAllWeapons _this}],["_unitEnd",{}],["_path","scripts\CivBehavior\"]];

if (isNil "_center") exitWith {
    diag_log "Civilian Behavior: init: incorrect arguments";
};

// allow canceling civ behavior zones
if (_center isEqualType objNull && {_center isKindOf "Logic"}) exitWith {_center setVariable ["#active",false]};
if (_center isEqualType [] && {_center#0 isEqualType objNull}) exitWith {
    // move the module
    private _module = _center#0;
    _center = _center#1;
    _module setPosATL _center;
    _module setVariable ["#center",_center];
    private _radius = _module getVariable ["#radius",200];
    private _idleBuildings = nearestObjects [_center, ["house","wall","ruins"], _radius]; 
    private _safeBuildings = nearestObjects [_center, ["house","wall","ruins"], _radius*3]; 

    _module setVariable ["#idleSpots",_idleBuildings];
    _module setVariable ["#safeSpots",_safeBuildings];
};

if (_center isEqualType objNull) then {
    _center = getPosATL _center;
};

//check setup validity
if (isNil "_radius" || isNil "_unitCount") exitWith {
    diag_log "Civilian Behavior: init: incorrect arguments";
};

_module = "Logic" createVehicleLocal _center;
_module setVariable ["#active",true];
_module setVariable ["#center",_center];
_module setVariable ["#radius",_radius];
_module setVariable ["#unitCount",_unitCount];
_module setVariable ["#onCreated",_unitInit];
_module setVariable ["#onDeleted",_unitEnd];
_module setVariable ["#path",_path];

//register module specific functions
if (isNil "CivBeh_fnc_main") then {
    [
        _path,
        "CivBeh_fnc_",
        [
            "addThreat",
            "debug",
            "getQueueDelay",
            "getSafeSpot",
            "eventHandlers",
            "main",
            "threatQueue",
            "unitHandler",
            "unitCreate",
            "unitDelete"
        ],
        false
    ]
    call BIS_fnc_loadFunctions;
};

[_module] spawn CivBeh_fnc_unitHandler;

// prepare the safe spots in the zone
private _idleBuildings = nearestObjects [_center, ["house","wall","ruins"], _radius]; 
private _safeBuildings = nearestObjects [_center, ["house","wall","ruins"], _radius*3]; 

_module setVariable ["#idleSpots",_idleBuildings];
_module setVariable ["#safeSpots",_safeBuildings];

//prepare unit types
private _preset = _module getVariable ["#unitPreset",""];
// Automatic selection
if (_unitTypes isEqualTo []) then
{
    private _cfg = configFile >> "CfgVehicles" >> "ModuleCivilianPresence_F" >> "UnitTypes";
    private _cfgUnitTypes = _cfg >> worldName;
    if (isNull _cfgUnitTypes) then { _cfgUnitTypes = _cfg >> "other" };
    _unitTypes = getArray _cfgUnitTypes;
};
_module setVariable ["#debug",DEBUG_VISUAL];
_module setVariable ["#useAgents",false];
_module setVariable ["#unitTypes", _unitTypes];
_module setVariable ["#units",[]];

if (_module getVariable ["#debug",false]) then
{
    private _paramsDraw3D = missionNamespace getVariable ["CivBeh_fnc_CivBehavior_paramsDraw3D",[]];
    private _handle = addMissionEventHandler ["Draw3D",{["debug"] call CivBeh_fnc_debug;}];
    _paramsDraw3D set [_handle,_module];
    CivBeh_fnc_CivBehavior_paramsDraw3D = _paramsDraw3D;
};

_module 