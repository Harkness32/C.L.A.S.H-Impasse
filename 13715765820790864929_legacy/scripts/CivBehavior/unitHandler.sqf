#include "defines.inc"
DEBUG_LOG("UnitHandler",_this);

if (!isServer) exitWith {};
//monitor number of agents and spawn / delete some as needed

params ["_module"];

//make sure initialization is finished
waitUntil
{
    !isNil{_module getVariable "#units"}
};

private _center = _module getVariable ["#center",[]];
private _radius3 = (_module getVariable ["#radius",200]) * 3;
private _units = _module getVariable ["#units",[]];
private _maxUnits = _module getVariable ["#unitCount",0];
private _active = false;
private _aliveUnitCnt = 0;
diag_log format ["CivBehavior: zone started at %1. unit count %2",_center,_maxUnits];

while
{
    _active = _module getVariable ["#active",false];
    _aliveUnitCnt = {!isNull _x && {alive _x}} count _units;
    (_active && _maxUnits > 0) || (!_active && count _units > 0)
}
do
{
    if (_active) then
    {
        if (_aliveUnitCnt < _maxUnits) then
        {
            private _unit = [_module] call CivBeh_fnc_UnitCreate;
            if (!isNull _unit) then {_units pushBack _unit};
        };
    }
    else
    {
        private _unit = selectRandom _units;
        private _deleted = [_module,_unit] call CivBeh_fnc_UnitDelete;

        if (_deleted) then {
            _units = _units - [_unit];
        };
    };
    
    // if units too far from center, then delete them
    private _newCenter = _module getVariable ["#center",[]];
    if !(_center isEqualTo _newCenter) then {
        if (_center distance _newCenter < 800) exitWith {_center = _newCenter};
        // we need to delete the units
        private _deletedUnits = [];
        private _allClear = true;
        {
            if (_x distance _newCenter > _radius3) then {
                private _deleted = [_module,_x] call CivBeh_fnc_UnitDelete;
                if (_deleted) then {
                    _deletedUnits pushBack _x;
                } else {
                    _allClear = false;
                };
            };
        } forEach _units;
        if (_allClear) then {_center = _newCenter};
        _units = _units - _deletedUnits;
    };

    //compact & store units array
    _units = _units select {!isNull _x};
    _module setVariable ["#units",_units];

    sleep 2;
};

diag_log format ["CivBehavior: zone shut down at %1",_center];