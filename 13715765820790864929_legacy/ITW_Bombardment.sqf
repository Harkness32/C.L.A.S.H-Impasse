// Bombardment - artillery and/or smoke barrage at start of zone (ally fired) or start of defend (enemy fired)
#include "defines.hpp"

// ITW_ParamBombardment values
#define BBMT_TYPE_NONE          0
#define BBMT_TYPE_ZONE_SMOKE    1
#define BBMT_TYPE_ZONE_ARTY     2
#define BBMT_TYPE_ZONE_BOTH     3
#define BBMT_TYPE_DEFEND_SMOKE  4
#define BBMT_TYPE_DEFEND_ARTY   5 
#define BBMT_TYPE_DEFEND_BOTH   6
#define BBMT_TYPE_BOTH_SMOKE    7
#define BBMT_TYPE_BOTH_ARTY     8
#define BBMT_TYPE_BOTH_BOTH     9

#define BBMT_DEBUG(msg1,msg2,msg3) //diag_log format ["ITW: BBMT: %1 %2 %3",msg1,msg2,msg3]

#define BBMT_SIZE_MID    100 // bombardment will be centered at this distance
#define BBMT_SIZE_RANGE  100 // bombardment pos will vary by this much from the mid
#define BBMT_SAVE_ZONE   300 // trigger when units with this close of potential bombardment zone

// call on server at start of new zone and start of defend phase
ITW_Bombardment = {
    params ["_type"]; // _type = "zone" or "defend"
    
    if (ITW_ParamBombardment == BBMT_TYPE_NONE) exitWith {};
    if (_type == "zone"   && {ITW_ParamBombardment in [BBMT_TYPE_DEFEND_SMOKE,BBMT_TYPE_DEFEND_ARTY,BBMT_TYPE_DEFEND_BOTH]}) exitWith {};
    if (_type == "defend" && {ITW_ParamBombardment in [BBMT_TYPE_ZONE_SMOKE,  BBMT_TYPE_ZONE_ARTY,  BBMT_TYPE_ZONE_BOTH  ]}) exitWith {};
    
    ITW_BBMT_CURRENT = _type + str ITW_ZoneIndex; // used to cancel other bombardments currently firing when new one called
    
    private _isFriendly = _type == "zone";
    private _objectives = if (_type == "zone") then {ITW_Zones#ITW_ZoneIndex} else {[ITW_defendPhaseObjIdx]};

    {
        if (_type == "zone" && {_x call ITW_ObjContestedOwnerIsFriendly}) then {
            BBMT_DEBUG("Skipped",ITW_Objectives#_x#ITW_OBJ_NAME,_type);
            continue
        }; // skip friendly owned zones on loading saved game
        [_isFriendly,_x,ITW_BBMT_CURRENT] spawn {
            params ["_isFriendly","_objIdx","_safecode"];
            scriptName "ITW_Bombardment";
            private _obj = ITW_Objectives#_objIdx;
            private _objPos = _obj#ITW_OBJ_POS;
            private _objSize = _obj#ITW_OBJ_SIZE;
            BBMT_DEBUG("Started",_obj#ITW_OBJ_NAME,_isFriendly);
            
            sleep 10; // wait at least this long before bombarding
            
            private _triggerSizeSqr = (_objSize + BBMT_SIZE_MID + BBMT_SIZE_RANGE + BBMT_SAVE_ZONE)^2;
            private _side = [ITW_EnemySide,ITW_PlayerSide] select _isFriendly;
            waitUntil {sleep 1;(units _side) findIf {(_x distanceSqr _objPos) < _triggerSizeSqr} != -1};
            
            private _dropCount = switch {true} do {
                case (_objSize <  90): {5};
                case (_objSize < 150): {6};
                case (_objSize < 350): {7};
                case (_objSize < 750): {8};
                default                {9};
            };
            private _extraDrops = 0;
            private _rand = random 100;
            if (_rand < 20) then {_extraDrops = _extraDrops + 1};
            if (_rand < 10) then {_extraDrops = _extraDrops + 1};
            BBMT_DEBUG("Triggered",_obj#ITW_OBJ_NAME,_dropCount);
            
            // Setup Artillery
            private _shells = [va_eArtyAmmo,va_pArtyAmmo] select _isFriendly; // array of [ammo,dropCount,timeBetween]
            private _dropInfo = []; // array of [_pos,_ammo,_delay,_countLeft,_nextDropTime]
            for "_i" from 1 to (_dropCount + _extraDrops) do {
                private _pos = [];
                private _loopCnt = 10;
                while {_pos isEqualTo [] || {surfaceIsWater _pos || {_loopCnt <= 0}}} do {
                    _loopCnt = _loopCnt - 1;
                    if (_i > _dropCount) then {
                         _pos = _objPos getPos [_objSize * (sqrt random 1), random 360] // sqrt random 1 give more even distribution inside circle
                    } else {
                        _pos = _objPos getPos [_objSize + BBMT_SIZE_MID, random 360]
                    };
                };
                _pos set [2,600];
                private _ammoInfo = selectRandom _shells;
                _dropInfo pushBack [_pos,_ammoInfo#0,_ammoInfo#1 * 2,_ammoInfo#2,time + random 10];
            };
            
            // Setup Smokes - get them to be on the side attack is coming from (average air/land directions)
            private _atkTypes = [[ITW_ATTACK_LAND_E,ITW_ATTACK_AIR_E],[ITW_ATTACK_LAND_F,ITW_ATTACK_AIR_F]] select _isFriendly;
            private _landBaseIdx = _obj#ITW_OBJ_ATTACKS#(_atkTypes#0); 
            private _airBaseIdx = _obj#ITW_OBJ_ATTACKS#(_atkTypes#1); 
            if (_landBaseIdx == -1) then {_landBaseIdx = _airBaseIdx};
            private _landBaseIdxDir = _objPos getDir (ITW_Bases#_landBaseIdx#ITW_BASE_POS);
            private _airBaseIdxDir  = _objPos getDir (ITW_Bases#_airBaseIdx#ITW_BASE_POS);
            private _smokeTime = 30 + random 30; // come 30-60 seconds after arty
            for "_i" from 1 to (_dropCount * 2) do {
                private _dir = selectRandom [_landBaseIdxDir,_airBaseIdxDir];
                private _pos = [];
                private _loopCnt = 10;
                while {_pos isEqualTo [] || {surfaceIsWater _pos || {_loopCnt <= 0}}} do {
                    _pos = _objPos getPos [(_objSize max BBMT_SIZE_MID) + BBMT_SIZE_MID/2 , _dir - 110 + random 220];
                };
                private _ammoInfo = selectRandom _shells;
                private _time = time + _smokeTime + random 20 + (if (_i > _dropCount) then {80} else {0}); // smoke lasts around 80 seconds
                for "_i" from -50 to 50 step 50 do {       // smoke fills about 50m radius
                    for "_j" from -50 to 50 step 50 do {
                        private _p = [_pos#0+_i,_pos#1+_j,0];
                        _dropInfo pushBack [_p,"Smoke_120mm_AMOS_White",0,1,_time];
                    };
                };
            };
            
            // Drop the barrage
            while {_dropInfo isNotEqualTo [] && {_safecode == ITW_BBMT_CURRENT}} do {
                sleep 0.2;
                {
                    _x params ["_pos","_ammo","_delay","_countLeft","_nextDropTime"];
                    if (time > _nextDropTime) then {
                        private _rndPos = _pos getPos [BBMT_SIZE_RANGE * (sqrt random 1),random 360];
                        _rndPos set [2,600];
                        private _shell = _ammo createVehicle _rndPos;
                        _shell setPosATL _pos;
                        _shell setVelocity [0,0,-50 - random 5]; // random to keep drops triggered together from landing together
                        _countLeft = _countLeft - 1;
                        if (_countLeft <= 0) then {
                            _dropInfo deleteAt _forEachIndex;
                        } else {
                            _x set [3,_countLeft];
                            _x set [4,time + (_delay * 0.8) + random (_delay * 0.4)];
                        };
                        BBMT_DEBUG("Dropping",_obj#ITW_OBJ_NAME,_x);
                        //private _mrkr = createMarkerLocal [format ["BBMT-%1-%2",time,_forEachIndex],_rndPos];
                        //_mrkr setMarkerTypeLocal "hd_dot";
                        //_mrkr setMarkerColorLocal (if (_ammo == "Smoke_120mm_AMOS_White") then {"ColorBlue"} else {"ColorRed"});
                    };
                } forEachReversed _dropInfo;
            };
            BBMT_DEBUG("Complete",_obj#ITW_OBJ_NAME,_isFriendly);
        };
    } forEach _objectives;
};