// Better Building Position
//
// Get all building positions, add a few extra if possible, and them fix them up.

params ["_building",["_allowInBetweenPts",true]];

#include "scripts\SKULL\SKL_Semaphore.hpp"

BBPosSem = false;

#define DEBUG false

private _findFloor = {
    params ["_fromPosATL"];

    private _fromPosASL = ATLToASL _fromPosATL;
    _fromPosASL set [2,(_fromPosASL#2)+0.2]; // lift just a little
    private _toPosASL = +_fromPosASL;
    _toPosASL set [2,getTerrainHeightASL _fromPosATL];
    private _surfaces = lineIntersectsSurfaces [_fromPosASL, _toPosASL, objNull, objNull, true, 10, "GEOM", "NONE", true];
    private _building = nearestBuilding _fromPosATL;
    {
        _x params ["_intersectPosASL", "_surfaceNormal", "_intersectObj", "_parentObject"];
        if (isNull _parentObject || {_parentObject == _building}) exitWith {
            _toPosASL set [2,_intersectPosASL#2];
        };
    } forEach _surfaces;
    ASLToATL _toPosASL 
};

private _improvePosition = {
    // Arma's building positions are too close to the walls.  The AI when crouched 
    // or prone stick through the walls.  They then are allowed to fire their guns
    // which are now outside the wall.  This tries to fix that.
     
    params ["_initialPos",["_debug",DEBUG]];
    private _finalPos = _initialPos;
    private _initialHgt = _initialPos#2;
    private _checkDist = 1.2;
    private _distances = [];
    private _dbgPts = [];
    try {
        private _beg = ATLToASL _finalPos;
        _beg set [2,(_beg#2) + 0.3];
        if (isNil "LV_BBPOS_DEBUG") then {LV_BBPOS_DEBUG = false;};
        if (LV_BBPOS_DEBUG) then {_debug = true;};
        if (_debug) then {
            // make sure helpers are not near position
            if !(isNil "LV_BBPOS_HELPER") then {
                {
                    _x setPosATL [0,0,-100];
                } foreach LV_BBPOS_HELPER;
            };
        };  
        for "_a" from 0 to 359 step 90 do {    
            private _dist = 0;
            private _dbgPt = [];
            for "_d" from _checkDist to 0.2 step -0.1 do {
                private _end = _beg getPos [_d,_a];
                _end set [2,_beg#2];
                if (_debug) then {if (_dbgPt isEqualTo []) then {_dbgPt = _end;};};
                if !(lineIntersects [_beg,_end,objNull,objNull]) exitWith {_dist = _d};
            };
            _distances pushBack _dist;
            if (_debug) then { 
                private _pt = _beg getPos [_dist,_a];
                _pt set [2,_beg#2];
                if (_dist >= 1.2) then {_pt set [2,(_pt#2)-0.1];};
                _dbgPts pushBack [_dbgPt,_pt]; 
            };
        };
        // center between opposing walls
        private _dN = _distances#0; 
        private _dE = _distances#1;
        private _dS = _distances#2;
        private _dW = _distances#3;
        if (_dN != _checkDist || {_dS != _checkDist}) then {
            if ((_dN != _checkDist) && (_dS != _checkDist)) then {
                _finalPos = _finalPos getPos [-((_dN + _dS)/2 - _dN) ,0];
            } else {
                if ((_dN == _checkDist) && (_dS != _checkDist)) then {
                    _finalPos = _finalPos getPos [_checkDist - _dS,0];
                } else {
                    _finalPos = _finalPos getPos [_checkDist - _dN,180];
                };
            };
        };
        if (_dE != _checkDist || {_dW != _checkDist}) then {
            if ((_dE != _checkDist) && (_dW != _checkDist)) then {
                _finalPos = _finalPos getPos [-((_dE + _dW)/2 - _dE) ,90];
            } else {
                if ((_dE == _checkDist) && (_dW != _checkDist)) then {
                    _finalPos = _finalPos getPos [_checkDist - _dW,90];
                } else {
                    _finalPos = _finalPos getPos [_checkDist - _dE,270];
                };
            };
        };
    } catch {};
    _finalPos set [2,_initialHgt]; // fix the height
    _finalPos = [_finalPos] call _findFloor; // find the actual floor
    _finalPos
};

private _buildingPositions = [_building] call BIS_fnc_buildingPositions;
_buildingPositions = _buildingPositions select {! isNil "_x"};

if (_allowInBetweenPts && {count _buildingPositions > 3}) then {
    // add some in between locations inside the building
    private _armaPositions = +_buildingPositions;
    private _index = 0;

    _armaPositions = _armaPositions call BIS_fnc_arrayShuffle; 

    private _agent = createAgent ["C_man_1", _armaPositions#0, [], 0, "NONE"];
    _agent hideObject true;

    private _armaPosCnt = count _armaPositions;
    private _loopCnt = (floor (count _armaPositions)/2) min 10; // don't add more than 10 positions on large buildings 
    {
        _loopCnt = _loopCnt - 1;
        if (_loopCnt < 0) exitWith {};
        
        private _pt1 = _x;
        private _rndIndex = _forEachIndex + 1 + floor random (_armaPosCnt - _forEachIndex - 1);
        if(DEBUG) then {diag_log format ["Generating extra bld pt from pos %1 to %2 (max positions: %3)",_forEachIndex,_rndIndex,_armaPosCnt];};
        private _pt2 = _armaPositions#(_rndIndex);
        SEM_LOCK(BBPosSem);
        BetterBuildingPos = [0];
        //_agent = (calculatePath ["man","safe",_pt1,_pt2]);
        _agent setPosATL _pt1;
        private _h = _agent addEventHandler ["PathCalculated", {
            params ["_agent","_path"];  
            _agent removeEventHandler [_thisEvent, _thisEventHandler];        
            private _cnt = count _path;
            private _start = if (_cnt > 3) then {1} else {0};
            private _end = if (_cnt > 3) then {_cnt-2} else {_cnt-1};
            private _index = _start + random (_end - _start);
            if (isNil "BetterBuildingPos") then {diag_log ["Error Pos: BetterBuildingPos invalid path",isNil "_path",if (typeName _path isEqualTo "ARRAY") then {count _path} else {_path},_index, if (typeName _path isEqualTo "ARRAY") then {_path#_index} else {"--"}]};           
            if (BetterBuildingPos isEqualTo [0]) then {BetterBuildingPos = ASLToATL (_path#_index)};
        }]; 
        _agent setDestination [_pt2, "LEADER PLANNED", true];
        private _t = diag_tickTime;   
        private _timeout = time + 1;
        waitUntil {sleep 0.01;!(BetterBuildingPos isEqualTo [0]) || {_timeout < time}};
        if(DEBUG) then {diag_log format ["ExtraBldPt took %1 sec and %2",diag_tickTime - _t,if (BetterBuildingPos isEqualTo [0])then{"Failed"}else{"Succeeded"}];};
        if (count BetterBuildingPos > 0) then {_buildingPositions pushBackUnique BetterBuildingPos};
        BetterBuildingPos = [];
        SEM_UNLOCK(BBPosSem);
    } forEach _armaPositions;
    
    deleteVehicle _agent;
};

{
    if (count _x < 3) then {
        _buildingPositions deleteAt _forEachIndex;
    } else {
        _buildingPositions set [_forEachIndex,[_x] call _improvePosition];
    };
} forEachReversed _buildingPositions;

_buildingPositions 
