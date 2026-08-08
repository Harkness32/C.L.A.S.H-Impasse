// SKL_SmartStaticDefence
//
// Script will cause a static defense gunner to exit his static vehicle and defend himself if enemy get close
//
// Usage: in manned static defense init:  _nil = this execVM "scripts\SKULL\SKL_SmartStaticDefence.sqf"
//
//        from script, call on server:   SKL_SmartStaticDefense = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_SmartStaticDefence.sqf";
//                     parameters veh  or  [veh,bool:autoFillAmmo]   or  [veh,veh,veh,...]  or  [veh,veh,veh,...,bool:autoFillAmmo]
//                                       _veh call SKL_SmartStaticDefense;           // ammo refills when ai enters static
//                                       [_veh,false] call SKL_SmartStaticDefense;   // ammo doesn't refill 
//                                       or
//                                       [_veh,_veh,_veh,...] call SKL_SmartStaticDefense
//                                       [_veh,_veh,_veh,...,ammoRefill] call SKL_SmartStaticDefense
//

//diag_log format ["SKL_SmartStaticDefence s%1",_this];

#define VEH_TYPE_INVALID -1
#define VEH_TYPE_MG  0  // machine gun or cannon
#define VEH_TYPE_MT  1  // mortar
#define VEH_TYPE_AA  2  // anti air
#define VEH_TYPE_AT  3  // anti tank
#define VEH_TYPE_GL  4  // grenade launcher

#define DEBUG(TXT1,TXT2,TXT3) //diag_log format ["SKL_SmartStaticDefense %1 %2 %3",TXT1,TXT2,TXT3]

if (!isServer) exitWith { diag_log "SKL_SmartStaticDefense: Error Pos: called on client"};
    
private _fnProcessParams = {
    private _ammoRefill = true;
    if (typeName _this isEqualTo "OBJECT") then {_this = [_this,true]};
    if (typeName (_this#-1) isEqualTo "BOOL") then {
        _ammoRefill = _this#-1;
        _this deleteAt (count _this - 1);
    };
    {
        private _veh = _x;
        if (_veh isKindOf "Man") then {
            _veh = vehicle _veh;
        };
        private _vehType = VEH_TYPE_INVALID;
        private _distance = 90;
        switch (true) do {
            case (_veh isKindOf "StaticMortar"):          {_vehType = VEH_TYPE_MT; _distance = 90;};
            case (_veh isKindOf "StaticAAWeapon");        
            case (_veh isKindOf "AA_01_base_F"):          {_vehType = VEH_TYPE_AA; _distance = 200};
            case (_veh isKindOf "StaticATWeapon");                                 
            case (_veh isKindOf "AT_01_base_F"):          {_vehType = VEH_TYPE_AT; _distance = 200};
            case (_veh isKindOf "StaticGrenadeLauncher"): {_vehType = VEH_TYPE_GL; _distance = 50};
            case (_veh isKindOf "StaticCannon");
            case (_veh isKindOf "StaticMGWeapon");
            case (_veh isKindOf "StaticWeapon"):          {_vehType = VEH_TYPE_MG; _distance = 3};
        };
        if (_vehType != VEH_TYPE_INVALID ) then {
            DEBUG("started type: ",_vehType,typeOf _veh);
            SKL_SSD_STATICS pushBack [_veh,_vehType,_distance,SKL_SSD_KEY];
            SKL_SSD_KEY = SKL_SSD_KEY + 1;
            _veh setVariable ["SSD_STATIC_TIMEOUT",time+30];
            _veh setVariable ["SSD_STATIC_SKILL",-1];
            _veh setVariable ["SSD_STATIC_BEHAVE",""];
            _veh setVariable ["SSD_STATIC_REAMMO",_ammoRefill];
        } else {
            diag_log format ["SKL_SmartStaticDefense: Error Pos: called with non-static: %1",typeOf _veh];
        };
    } forEach _this;
};

while {!isNil "SKL_SSD_PROCESSING" && {SKL_SSD_PROCESSING}} do {sleep 0.1};
SKL_SSD_PROCESSING = true;    

if (isNil "SKL_SSD_STATICS") then {
    SKL_SSD_STATICS = []; 
    SKL_SSD_GUNNERS = createHashMap; // key:[gunner,mode,behavior,skill]    need to keep an array instead of a veh setvariable in case veh is deleted.
    SKL_SSD_KEY = 0;
    _this call _fnProcessParams;
    0 spawn {
        scriptName "SKL_SmartStaticDefense";
        
        private _checkForEnemies = {
            params ["_gunner","_distance","_vehType"];
            private _safeSide = side _gunner;
            private _targets = (_gunner nearTargets _distance) select {(_x#3) > 0};
            private _count = { 
                private _object = _x#4;
                private _isAircraft = vehicle _object isKindOf "Air";
                (side _gunner) getFriend (side _object) < 0.6 
                   && {_object == vehicle _object  // not in a vehicle
                       || {(_vehType == VEH_TYPE_AA && !_isAircraft) 
                       || {(_vehType == VEH_TYPE_AT && _isAircraft)     
                      }}}
            } count _targets;
            _count > 0
        };
        
        private _mortarPlayers = {
            params ["_gunner"];
            private _veh = vehicle _gunner;
            if (_veh == _gunner) exitWith {};
            if (_veh getVariable ["skl_ssd_shells",""] isEqualTo "") then {
                private _shells = getArray (configFile >> "CfgVehicles" >> typeOf _veh >> "Turrets" >> "MainTurret" >> "magazines");
                if (_shells isEqualTo []) then {_shells = ["8Rnd_82mm_Mo_shells"]};
                _veh setVariable ["skl_ssd_shells",_shells#0];
            };
            private _side = side _gunner;
            {
                private _unit = _x;
                private _exit = false;
                if (alive _x) then {
                    private _targets = _unit targets [true,700,[],0,getPosATL _gunner];
                    if !(_targets isEqualTo []) exitWith {
                        _exit = true;
                        private _cnt = floor random 3;
                        DEBUG("mortar firing",_cnt+1,"rounds"); 
                        for "_i" from 0 to _cnt do {
                            private _target = selectRandom _targets;
                            private _pos = [[[getPosATL _target,75]],[]] call BIS_fnc_randomPos;
                            _gunner doArtilleryFire [_pos, _veh getVariable "skl_ssd_shells", 1];
                            sleep 2;
                        };
                    };
                };
                if (_exit) exitWith {};
            } forEach ((units _side) call BIS_fnc_arrayShuffle); 
        };
        
        private _unassignGunner = {
            params ["_key","_veh"];
            SKL_SSD_GUNNERS getOrDefault [_key,[objNull,"","",-1]] params ["_gunner","_mode","_behaviour","_skill"];
            if (!isNull _gunner) then {
                _gunner setVariable ["LV_PAUSE",false];
                if (_mode != ""     ) then {[(group _gunner),_mode]           remoteExec ["setCombatMode",group _gunner]};
                if (_behaviour != "") then {[_gunner,_behaviour]              remoteExec ["setBehaviour",_gunner]};
                if (_skill > 0      ) then {[_gunner,["spotDistance",_skill]] remoteExec ["setSkill",_gunner]};
                if (vehicle _gunner == _veh) then {
                    _gunner action ["GetOut",_veh];     
                    _gunner remoteExec ["unassignVehicle",_gunner];
                };
            };
            SKL_SSD_GUNNERS deleteAt _key;
        };
        
        while {true} do {
            private _statics = +SKL_SSD_STATICS; // copy so new statics can be added during the loop
            {
                _x params ["_veh","_vehType","_distance","_key"];
                private _assignedGunner = (SKL_SSD_GUNNERS getOrDefault [_key,[objNull,"","",-1]])#0;
                private _resetDist = _distance + 50;
                
                private _someAmmo = if (!isNull gunner _veh && {_vehType == VEH_TYPE_MT}) then {_veh ammo currentmuzzle gunner _veh > 0} else {someAmmo _veh};
                if (canMove _veh && {_someAmmo || {_veh getVariable ["SSD_STATIC_REAMMO",true]}}) then { 
                    if (isPlayer gunner _veh) then {continue};
                    _gunner = gunner _veh;
                    if (alive _gunner) then {
                        if (_gunner != _assignedGunner) then {
                            [_key,_veh] call _unassignGunner;
                            SKL_SSD_GUNNERS set [_key,[_gunner,combatMode group _gunner,behaviour _gunner,_gunner skill "spotDistance"]];
                        };
                        
                        // mortar should get some intel on player's location (0.033 = every 5 minutes or so)
                        if (_vehType == VEH_TYPE_MT && {random 1 < 0.07}) then { _gunner call _mortarPlayers };
                            
                        _veh setVariable ["SSD_STATIC_TIMEOUT",time+30];
                        
                        if ((alive _gunner) && {!_someAmmo || [_gunner,_distance,_vehType] call _checkForEnemies}) then {
                            if (vehicle _gunner != _gunner) then {
                                DEBUG("gunner exiting vehicle",typeOf _veh,""); 
                                [_key,_veh] call _unassignGunner;
                            };
                        };
                    };
                    
                    if (time > (_veh getVariable ["SSD_STATIC_TIMEOUT",0])) then {
                        // static is unmanned for too long
                        if (!isNull _assignedGunner) then {
                            [_key,_veh] call _unassignGunner;
                        };
                        private _newGunner = objNull;
                        private _availableUnits = (units east + units west + units independent) select {alive _x && {!(_x getVariable ["LV_PAUSE",false])}};
                        _availableUnits = _availableUnits - [_assignedGunner];
                        {_availableUnits = _availableUnits - (units group _x)} forEach playableUnits;
                        {
                            private _unit = _x;
                            private _dist = _unit distance2D _veh;
                            private _alive = alive _unit;
                            if (_alive && {gunner _veh == _unit}) exitWith {_newGunner = objNull}; // someone got back in
                            if (_alive && {_dist < 150 && {vehicle _unit == _unit && {_newGunner distance2D _veh > _dist}}}) then {
                                _newGunner = _unit;
                            };
                        } forEach _availableUnits;
                        if !(isNull _newGunner) then {
                            if !([_newGunner,_resetDist,_vehType] call _checkForEnemies) then { 
                                DEBUG("new gunner assigned: ",_newGunner,typeOf _veh);
                                if (count units group _newGunner > 1) then {
                                    [_newGunner] joinSilent grpNull;
                                };
       
                                _newGunner setVariable ["LV_PAUSE",true];
                                SKL_SSD_GUNNERS set [_key,[_newGunner,combatMode group _newGunner,behaviour _newGunner,_newGunner skill "spotDistance"]];
                                [group _newGunner] allowGetIn true;
                                _newGunner assignAsGunner _veh;
                                [[_newGunner],true] remoteExec ["orderGetIn",_newGunner];
                                _veh setVariable ["SSD_STATIC_TIMEOUT",time + 120];
                                if (_veh getVariable ["SSD_STATIC_REAMMO",true]) then {_veh setVehicleAmmo 1};
                            };
                        };
                    } else {
                        if (!isNull _assignedGunner && {isNull _gunner}) then {
                            [[_assignedGunner],true] remoteExec ["orderGetIn",_assignedGunner];
                        };
                    };
                } else {            
                    // static destroyed or out of ammo
                    DEBUG("static taken off line: ",typeOf _veh,"");
                    [_key,_veh] call _unassignGunner;
                    SKL_SSD_STATICS = SKL_SSD_STATICS - [_x];
                };
            } forEach _statics;
            sleep 10;
            while {SKL_SSD_STATICS isEqualTo []} do {sleep 10};
            while {!(isNil "LV_PAUSE") && {LV_PAUSE}} do {sleep 5};
        };
    };
} else {
    _this call _fnProcessParams;
};
SKL_SSD_PROCESSING = false;    