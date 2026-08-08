
#include "defines.hpp"

ITW_FncStartsWith = {
    params ["_string", "_startswith"];
    _string select [0,count _startswith] isEqualTo _startswith
};

ITW_FncEndsWith = {
	params ["_string", "_endswith"];
	_string select [count _string - count _endswith] isEqualTo _endswith
};

ITW_FncPlayerSide = {west};

ITW_FncActiveAllies = {
    (allUnits) select {side _x == (call ITW_FncPlayerSide) && (lifeState _x == "HEALTHY" || lifeState _x == "INJURED" )};
};

ITW_FncActivePlayers = {
    (allPlayers) select {!(_x isKindOf "HeadlessClient_F") && {lifeState _x == "HEALTHY" || lifeState _x == "INJURED"}}
};

ITW_FncAllAllies = {
    (allUnits) select {side _x == (call ITW_FncPlayerSide)}
};

ITW_FncAllActiveUnits = {
    (allUnits) select {lifeState _x == "HEALTHY" || lifeState _x == "INJURED" };
};

ITW_FncActiveEnemies = {
    (allUnits) select {side _x != (call ITW_FncPlayerSide)};    
};

ITW_FncAddCuratorObjects = {
    if (typeName _this != "ARRAY") then {_this = [_this];};
    // empty list means show all objects
    if (count _this == 0) then {
        _this = entities [[], ["Logic","Animal_Base_F"], true, false];
    };
    { _x addCuratorEditableObjects [_this,true] } forEach allCurators;
};

ITW_FncIsNight = {
	private _dawnDusk = date call BIS_fnc_sunriseSunsetTime;
	private _dawnNum = _dawnDusk select 0;
	private _duskNum = _dawnDusk select 1;
    private _hours = (date#3) + ((date#4)/60);
    (_hours < (_dawnNum) || _hours > (_duskNum))
};

ITW_FncSetTime = {	
    // pass in a number: 0=random, 1=dawn, 2=day, 3=dusk, 4=night, 5=random daytime
	params ["_time",["_nightAcceleration",1],["_dayAcceleration",1]];
    private ["_number","_daytime","_nightTime1","_nightTime2","_nightTime"];
	private _date = date;
    
    private _months = [[1,31],[2,28],[3,31],[4,30],[5,31],[6,30],[7,31],[8,31],[9,30],[10,31],[11,30],[12,31]];
    private _monthInfo = selectRandom _months;
    private _month = _monthInfo select 0;
    private _day = floor (random (_monthInfo select 1) + 1);
    private _year = _date#0;
    
    switch (toLower worldName) do {
        case "gm_weferlingen_summer";
        case "gm_weferlingen_winter";
        case "stozec": {
            _year = 1980 + floor random 10;
        };
        
        case "vn_khe_sanh";
        case "vn_the_bra";
        case "cam_lao_nam": {
            _year = 1956 + floor random 19;
        };
        
        case "spex_utah_beach";
        case "spex_carentan";
        case "spe_mortain";
        case "spe_normandy": {
            _month = selectRandom [6,7,8];
            _day = floor (random (_months#(_month-1)#1) + 1);
            _year = 1944;
        };
    };
    
    _date set [0,_year];
    _date set [1,_month];
    _date set [2,_day];
    
	private _dawnDusk = _date call BIS_fnc_sunriseSunsetTime;
	private _dawnNum = _dawnDusk#0;
	private _duskNum = _dawnDusk#1;
	private _dawnHour = floor _dawnNum;
	private _duskHour = floor _duskNum;
	private _dawnMinutes = round ((_dawnNum - _dawnHour) * 60);
	private _duskMinutes = round ((_duskNum - _duskHour) * 60);
    //diag_log format ["ITW: dawn:%1 (%2:%3) dusk:%4 (%5:%6)",_dawnNum,_dawnHour,_dawnMinutes,_duskNum,_duskHour,_duskMinutes]; 
	switch (_time) do {
        case 0: {                                            
            // RANDOM - actually make it more likely daytime
            if (random 100 <= 90) then {
                // day time
                _number = [_dawnNum, _duskNum] call BIS_fnc_randomNum;
                _date set [3, floor _number];  
                _date set [4, round((_number - floor _number) * 60)];  
            } else {
                // night time
                _number = [_duskNum, 24 + _dawnNum] call BIS_fnc_randomNum;
                if (_number >= 24) then {_number = _number - 24;};
                _date set [3, floor _number];  
                _date set [4, round((_number - floor _number) * 60)];  
            };  
        };  
        case 1: {                                                            
            // RANDOM daytime 
            _number = [_dawnNum + 1, _duskNum - 2] call BIS_fnc_randomNum;
            _date set [3, floor _number];  
            _date set [4, round((_number - floor _number) * 60)];  
        };                                                     
		case 2: {
			// DAWN		
			_date set [3, _dawnHour];
			_date set [4, _dawnMinutes];
			_number = dateToNumber _date;
			_number = _number - 0.00005;
			_date = numberToDate [(_date#0), _number];
		};
		case 3: {
			// DAY
			_dayTime = [_dawnNum+1, _duskNum-1] call BIS_fnc_randomNum;
			_date set [3, _dayTime];
		};
		case 4: {
			// DUSK			
			_date set [3, _duskHour-1];
			_date set [4, _duskMinutes];
		};
		case 5: {
			// NIGHT
			_nightTime1 = [(_duskNum + 1), 24] call BIS_fnc_randomNum;
			_nightTime2 = [0, (_dawnNum - 1)] call BIS_fnc_randomNum;
			_nightTime = selectRandom [_nightTime1, _nightTime2];
			_date set [3, _nightTime];
		};                                                               
	};	
    [_date] remoteExec ["setDate",0];
    diag_log format ["ITW: setDate %1 => %2",_time,_date];
    
    if (isServer) then {
        if (_nightAcceleration == _dayAcceleration) then {
            setTimeMultiplier _dayAcceleration;
        } else {
            // adjust time at night or day
            [_dawnNum,_duskNum,_nightAcceleration,_dayAcceleration] spawn {
                scriptName "ITW_FncSetTime - time acceleration";
                params ["_dawnNum","_duskNum","_nightAcceleration","_dayAcceleration"];
                sleep 20; // delay a bit in case we load a game and set the time
                _dawnNum = _dawnNum - 0.5;
                _duskNum = _duskNum + 0.5;
                private _currentAccel = _dayAcceleration;
                setTimeMultiplier _currentAccel;
                while {true} do {
                    while {LV_PAUSE} do {sleep 5};
                    private _delay = 60;
                    private _currentTime = dayTime;
                    
                    if (_currentAccel != _dayAcceleration && {_currentTime >= _dawnNum && {_currentTime < _duskNum}}) then {
                        _currentAccel = _dayAcceleration;
                        setTimeMultiplier _currentAccel;
                    } else {
                        if (_currentAccel == _dayAcceleration && {_currentTime < _dawnNum || {_currentTime >= _duskNum}}) then {
                            _currentAccel = _nightAcceleration;
                            setTimeMultiplier _currentAccel;
                        };
                    };
                    
                    if (_currentAccel == _dayAcceleration) then {
                        _delay = (_duskNum - _currentTime) * 3600;
                    } else {
                        if (_currentTime >= _duskNum) then {
                            _delay = (24 - _currentTime + _dawnNum) * 3600;
                        } else {
                            _delay = (_dawnNum - _currentTime) * 3600;
                        };
                    };
                    _delay = _delay / _currentAccel;          
                    sleep (_delay + 2);
                };
            };
        };
    };
};

ITW_FncSetWeather = {
    params ["_weather"];
    private ["_value"];
    
    switch (_weather) do {
        case 0: {_value = if (random 100 < 90) then {random 0.7} else {0.7 + random 0.4};};
        case 1: {_value = random 0.3;};
        case 2: {_value = 0.3 + random 0.4;};
        case 3: {_value = 0.7 + random 0.4;};
    };
    
    diag_log format ["ITW: Set weather mode %1, value %2",_weather, _value];
    [_value] remoteExec ["ITW_FncMpWeather", 0, true];
};

ITW_FncMpWeather = {    
    params ["_value"];
    skipTime -24; 
    86400 setOvercast (((_value) MIN 1) MAX 0); 
    skipTime 24; 
    0 = [] spawn { sleep 0.1; simulWeatherSync; };
};

ITW_FncGetNVGs = {
    // return the NVG type the unit has (assigned or in cargo) or "" if none available
    params ["_unit"];
    if (isNil "INF_FNC_NVGS") then {
        INF_FNC_NVGS = [];
        {
            INF_FNC_NVGS pushBack configName _x;
        } forEach ("(configName _x) isKindOf ['NVGoggles',configFIle >> 'CfgWeapons']" configClasses (configFile / "CfgWeapons"));
    };
    
    private _nvgs = [];
    {
        if (_x in INF_FNC_NVGS) then {_nvgs pushBack _x};
    } forEach (items _unit + assignedItems _unit);
    _nvgs
};

ITW_FncIsLeadPlayer = {
    params ["_unit"];
    // checks if the player is the group leader, or if the group lead is an AI, then checks if the player is admin
    if (! isPlayer _unit) exitWith {false};              // not a player
    if (leader _unit == _unit) exitWith {true};          // is group leader
    if (isPlayer leader _unit) exitWith {false};         // other player is group leader
    if (serverCommandAvailable "#kick") exitWith {true}; // is admin
    false
};

ITW_FncClosest = {
    params ["_point","_array",["_subElement",-1]];
    // Will return the item from the _array closest to the given _point
    //   _array is array of objects, positions, or arrays (of which _subElement is an object or position)
    //   _point is the object or position to be closest to
    //   _subElement < 0 means the _array is an object or position and the _subElement is ignored
    if (_array isEqualTo []) exitWith {objNull};
    private _list = 
        if (_subElement < 0) then {_array apply {[_point distanceSqr _x,_x]}}
        else {_array apply {[_point distanceSqr (_x#_subElement),_x]}};
    _list sort true;
    (_list#0) param [1,objNull];
};

ITW_FncClosestIndex = {
    params ["_point","_array",["_subElement",-1]];
    // Will return the index of the item from the _array closest to the given _point
    //   _array is array of objects, positions, or arrays (of which _subElement is an object or position)
    //   _point is the object or position to be closest to
    //   _subElement < 0 means the _array is an object or position and the _subElement is ignored
    private _list = 
        if (_subElement < 0) then {_array apply {[_point distanceSqr _x,_x]}}
        else {_array apply {[_point distanceSqr (_x#_subElement),_x]}};
    _list sort true;
    _array find ((_list#0) param [1,objNull])
};

#define TERRAIN_OBJECTS ["MAIN ROAD", "ROAD", "TRACK", "TRAIL" ] 
ITW_RemoveTerrainObjects = {
    // call on all clients & server
    params ["_center","_size",["_ignoreObjects",[]]];
    if (!(_ignoreObjects isEqualTo []) && {typeName (_ignoreObjects#0) == "OBJECT"}) then {_ignoreObjects = _ignoreObjects apply {typeOf _x}};
    _ignoreObjects pushBack "BlockConcrete_F";
    _objs = nearestTerrainObjects [_center, [], _size, false, true];
    _objs = _objs + nearestObjects [_center, ["Static"], _size, false, true];
    _objs = _objs - nearestTerrainObjects [_center, TERRAIN_OBJECTS, _size, false, true];
    // concrete slabs that I added must be seen as terrain objects, so ensure they are not hidden
    _objs = _objs - nearestObjects [_center, _ignoreObjects, _size, false, true];
    {
        _x hideObject true;
        _x allowDamage false;
        {deleteVehicle _x} count (_x getVariable ["tint_house_objects",[]]);
    } forEach _objs;
};

ITW_FncCleanup = {
    scriptName "ITW_FncCleanup";
    if (ITW_ParamCleanupDelay == 0) exitWith {};
    private _removed = [objNull];
    private _maxTime = ITW_ParamCleanupDelay;
    private _minTime = ITW_ParamCleanupDelay/4;
    while {true} do {
        sleep 60;
        while {LV_PAUSE} do {sleep 5};
        {
            if !(isNull _x) then {
                private _grp = group _x;
                deleteVehicle _x; // weaponholders get deleted when the unit who dropped it gets deleted
                if (!isNull _grp && {count (units _grp) == 0}) then {deleteGroup _grp};
            };
        } forEach _removed;
        _removed = [objNull];
        private _numDead = if (ITW_ParamCleanupDelay > 120) then {count allDead} else {1000};
        private _playerDist = switch (true) do {
            case (_numDead < 100): {1500};
            case (_numDead < 200): {1000};
            default                {500};
        };
            
        private _players = allPlayers - HeadlessClients;
        {
            private _unit = _x;
            
            private _cleanTime = _unit getVariable ["itw_cleanupTime",0];
            if (_cleanTime == 0) then {
                _cleanTime = time + _minTime;
                _unit setVariable ["itw_cleanupTime",_cleanTime];
            };
            if (time < _cleanTime) then {continue};
            
            if (!alive _unit) then {
                if ({_x distance _unit < _playerDist} count _players == 0) then {
                    if (_x isKindOf "CAManBase") then {
                        hideBody _unit; 
                        _removed pushBack _unit;
                    } else {
                        deleteVehicle _unit;
                    };
                } else {
                    private _deadTime = _unit getVariable ["ITW_deadTime",0];
                    if (_deadTime == 0) then {
                        _unit setVariable ["ITW_deadTime",time + _maxTime];
                    } else {
                        if (time > _deadTime) then {
                            if (_x isKindOf "CAManBase") then {
                                hideBody _unit; 
                                _removed pushBack _unit;
                            } else {
                                deleteVehicle _unit;
                            };
                        };
                    };
                };
            };
        } forEach allDead;
    };
};

ITW_FncSemWait = {
    // Can be called with an array (local variable) or a string (global variable)
    
    // In the following examples 'done' appears in the log 5 seconds after 'start'
    // LOCAL VARIABLE EXAMPLE
    //  _s = [0]; 
    //  [_s] spawn { params ["_s"]; sleep 5; _s set [0,1] }; 
    //  diag_log "start"; 
    //  [_s,20] call ITW_FncSemWait; 
    //  diag_log "done"
    //  
    // GLOBAL VARIABLE EXAMPLE
    //  S = 0; 
    //  [] spawn { sleep 5; S = 1 }; 
    //  diag_log "start"; 
    //  ["S",20] call ITW_FncSemWait; 
    //  diag_log "done"
    //
    // return TRUE if sem triggered, FALSE if timed out
    //
    params ["_sem","_timeoutSec",["_pollSec",1.0]];
    if (_timeoutSec == 0) then {_timeoutSec = 1e10};
    private _timeUp = time + _timeoutSec;
    switch (typeName _sem) do {
        case "ARRAY": {
            while {time < _timeUp} do {
                sleep _pollSec;
                if (_sem#0 != 0) exitWith {};
            };
        };
        case "STRING": { 
            private _check = compile format ["%1 != 0",_sem];
            while {time < _timeUp} do {
                sleep _pollSec;
                if (call _check) exitWith {};
            };        
        };
        default {diag_log format ["Error pos: ITW_FncSemWait: invalid sem type (%1) args:%2",typeName _sem,_this]};
    };
    time < _timeUp 
};

ITW_FncDelayCall = {
    // call code after a delay - allow a bunch of spawn calls that don't each spawn a new thread
    
    // params ["_args","_code",["_delay",15]]
    
    if (isNil "ITW_DelayData") then {ITW_DelayData = []};
    
    private _delay = if (count _this < 3) then {15} else {_this#2};
    _this set [2,time + _delay];
    ITW_DelayData pushBack _this;
    
    if (isNil "ITW_DelayTask") then {ITW_DelayTask = scriptNull};
    if (scriptDone ITW_DelayTask) then {
        ITW_DelayTask = 0 spawn {  
            scriptName "ITW_FncDelayCall";
            // _doneCount lets the task survive a little while after all 
            // items have been dealt with to give time for new ones to arrive
            private _doneCount = 0;
            while {_doneCount < 10} do {
                sleep 1;
                {
                    _x params ["_args","_code","_timeout"];                
                    if (time > _timeout) then {
                        ITW_DelayData deleteAt _forEachIndex;
                        _args call _code;
                        sleep 0.001; // YIELD_CPU
                    };
                } forEachReversed ITW_DelayData;
                if (ITW_DelayData isEqualTo []) then {
                    _doneCount = _doneCount + 1;
                } else {
                    _doneCount = 0;
                };
            };
        };
    };
};

#define VAR_DEBUG false
ITW_REMOTE_VAR_CNT = 0;
ITW_FncGetRemoteVar = {
    // get a variable from the client where _localObject is local
    params ["_localObject","_varObject","_varName","_defaultValue"];
    if (local _localObject) exitWith {_varObject getVariable [_varName,_defaultValue]};
    ITW_REMOTE_VAR_CNT = ITW_REMOTE_VAR_CNT + 1;
    private _syncId = format ["REMOTE_VAR_%1",ITW_REMOTE_VAR_CNT];
    call compile format ["%1 = nil",_syncId];
    [_varObject,_varName,_defaultValue,_syncId,clientOwner] remoteExec ["ITW_FncGetRemoteVarGet",_localObject];
    private _timeout = time + 5;
    if (VAR_DEBUG) then {diag_log format ["ITW_FncGetRemoteVar: %1 getVariable [%2,%3] where %4 is local (%5)",_varObject,_varName,_defaultValue,_localObject,_syncId]};    
    call compile format ["waitUntil {!isNil '%1' || time > _timeout}; %1",_syncId];
    private _return = call compile format ["if (isNil '%1') then {%2} else {%1}",_syncId,_defaultValue];
    if (VAR_DEBUG) then {diag_log format ["ITW_FncGetRemoteVar: syncId: %1 returning %2",_syncId,_return]};
    _return
};

ITW_FncGetRemoteVarGet = {
    // call where the var we want to read is local
    params ["_varObject","_varName","_defaultValue","_syncId","_client"];
    private _value = _varObject getVariable [_varName,_defaultValue];
    [_syncId,_value] remoteExec ["ITW_FncGetRemoteVarReturn",_client];
    if (VAR_DEBUG) then {diag_log format ["ITW_FncGetRemoteVarGet: remote syncId %1 returning %2 (_this=%3)",_syncId,_value,_this]};
};

ITW_FncGetRemoteVarReturn = {
    // called where we want to get the var
    params ["_syncId","_value"];
    if (VAR_DEBUG) then {diag_log format ["ITW_FncGetRemoteVarReturn: %1",_this]};
    call compile format ["%1 = %2",_syncId,_value];
};

ITW_FncRelPos = {
    // allows for  object getPos [dist,dir] but keeps same altitude
    params ["_p1","_dist","_dir"];
    if (typeName _p1 != "ARRAY") then {_p1 = getPosATL _p1};
    private _pos = _p1 getPos [_dist,_dir];
    _pos set [2,_p1#2];
    _pos
};

ITW_fnc_HeliHasWeapons = {
    private _cfg = 
        if (typeName _this == "STRING") then {configFile >> "CfgVehicles" >> _this}
        else {configFile >> "CfgVehicles" >> typeOf _this};
    private _hasWeapons = false;
    private _nonWeapons = ["SmokeLauncher","Laserdesignator_mounted","FakeHorn","vn_fuel_mi2_launcher","vn_v_launcher_rdg2","vn_v_launcher_m18r"];

    private _wpns = getArray (_cfg >> "weapons");
    {
        {
            _wpns pushBackUnique _x;
        } forEach getArray (_x >> "weapons");
    } forEach (configProperties [(_cfg >> "Turrets"),"true",true]);
    if !(_wpns isEqualTo []) then {
        {
            private _w = _x;
            _hasWeapons = {(_w isKindOf [_x,configFile >> "cfgWeapons"])} count _nonWeapons == 0;
            if (_hasWeapons) exitWith {};
        } forEach _wpns;
    };
    _hasWeapons
};

ITW_fnc_HelipadObject = {
    params ["_posATL",["_type","circle"],["_dir",0]];
    // types: circle, civil, rescue, square, jumpTarget
    // don't rotate helipad after this call
    
    // place invisible helipad so helis will land here
    private _hp = "Land_HelipadEmpty_F" createVehicle _posATL;
    _hp setPosATL _posATL;
    
    // create the visible elevated halipad
    _hp = "UserTexture10m_F" createVehicle _posATL;
    private _texture = switch (toLowerAnsi _type) do {
        case "circle":    {"\A3\Structures_F\Mil\Helipads\Data\HelipadCircle_CA"};
        case "civil":     {"\A3\Structures_F\Mil\Helipads\Data\HelipadCivil_CA"};
        case "rescue":    {"\A3\Structures_F\Mil\Helipads\Data\HelipadRescue_CA"};
        case "square":    {"\A3\Structures_F\Mil\Helipads\Data\HelipadSquare_CA"};
        case "jumptarget":{"\A3\Structures_F\Mil\Helipads\Data\JumpTarget_CA"};
    };
    _hp setObjectTextureGlobal [0,_texture];
    _hp setObjectMaterialGlobal [0, "A3\Structures_F\mil\helipads\Data\helipads.rvmat"];
    
    _yaw = _dir; _pitch = -90; _roll = 0; 
    // [sin _yaw * cos _pitch, cos _yaw * cos _pitch, sin _pitch], 
    // [[sin _roll, -sin _pitch, cos _roll * cos _pitch], -_yaw] call BIS_fnc_rotateVector2D 
    _data = [ [sin _yaw, cos _yaw, -2.28773e+007], 
              [[0, 1, -4.37114e-008], -_yaw] call BIS_fnc_rotateVector2D 
            ]; 
    _hp setPosATL _posATL;
    _hp setVectorDirAndUp _data;
    _hp
};

ITW_FncGetIdentity = {
    params ["_unit",["_getSaved",false]];
    private _identity = if (_getSaved) then {_unit getVariable ["skl_identity",[]]} else {[]};
    if (_identity isEqualTo []) then {
        _identity = [face _unit,speaker _unit];
    };
    _identity
};

ITW_FncSetIdentity = {
    params ["_unit",["_faction",""],["_unitClass",""],["_voiceOnly",false]];
    // give the unit correct face/voice 
 
    private _voice = "";
    private _face = "";
    if (_faction isEqualTo "" && {_unitClass isEqualTo ""}) then {
        private _identity = _unit getVariable ["skl_identity",[]];
        if (_identity isNotEqualTo []) then {
            _face = _identity#0;
            _voice = _identity#1;
            _voiceOnly = _face isEqualTo "";
        };
    };
    if (_face isEqualTo "" && {_unitClass isNotEqualTo "" || _faction isNotEqualTo ""}) then {
        private _factionUnits = [];
        if (_unitClass isEqualTo "") then {
            _factionUnits = [_faction] call FactionUnits;
            _unitClass = selectRandom _factionUnits;
        };
        
        private _cfg = configFile >> "CfgVehicles" >> _unitClass;
        if (!isClass _cfg) exitWith {diag_log format ["Error Pos: ITW_FncSetIdentity called with invalid unit class %1",_unitClass]}; 

        private _identityTypes = getArray (_cfg >> "identityTypes");
        private _validVoices = [];
        private _validFaces = [];
        {
            private _type = _x;
            {
                private _speakerTypes = getArray (_x >> "identityTypes");
                if (_type in _speakerTypes && {getNumber (_x >> "scope") >= 2}) then { 
                    _validVoices pushBackUnique (configName _x);
                };
            } forEach ("true" configClasses (configFile >> "CfgVoice"));

            {
                private _faceTypes = getArray (_x >> "identityTypes");
                if (_type in _faceTypes) then { 
                    _validFaces pushBackUnique (configName _x);
                };
            } forEach ("true" configClasses (configFile >> "CfgFaces" >> "Man_A3"));
        } forEach _identityTypes;

        _voice = if (count _validVoices == 0) then {""} else {selectRandom _validVoices};
        _face  = if (count _validFaces == 0 ) then {""} else {selectRandom _validFaces };
    
        while {_face isEqualTo "Walker239"} do {_face = selectRandom _validFaces};
        _unit setVariable ["skl_identity",[_face,_voice]];
    };
    if (!(_face isEqualTo "") || !(_voice isEqualTo "")) then {
        [_unit,_face,_voice] remoteExec ["ITW_FncSetIdentityMP",0,true];
    };
};

ITW_FncSetIdentityMP = {
    params ["_unit","_face","_speaker"];
    if !(_speaker isEqualTo "")then {try {_unit setSpeaker _speaker} catch {}};
    if !(_face isEqualTo "") then {try {_unit setFace _face}       catch {}};
};

ITW_FncInfiniteAmmo = {
    params ["_unit",["_grenadeLaunchers",false],["_rocketLaunchers",false]];
    _unit setVariable ["ITW_loadout",getUnitLoadout _unit,true];
    _unit setVariable ["ITW_infinteAmmo",[_grenadeLaunchers,_rocketLaunchers]];
    _unit addEventHandler ["Reloaded",{
        params ["_unit", "_weapon", "_muzzle", "_newMagazine", "_oldMagazine"];
        _unit getVariable ["ITW_infinteAmmo",[]] params [["_grenadeLaunchers",false],["_rocketLaunchers",false]];
        private _mag = _oldMagazine#0;
        if (!_rocketLaunchers && {_weapon isEqualTo secondaryWeapon _unit}) exitWith {};   
        if (!_grenadeLaunchers && {_mag isKindOf ["1Rnd_HE_Grenade_shell",configFile >> "CfgMagazines"]})  exitWith {};          
        _unit addMagazine _mag;
    }];    
};

ITW_FncSizeOf = {
    // get size of a class (from cfgVehicles) without having to load a vehicle of that type first
    params ["_className"];
    private _sizeOf = sizeOf _className;
    if (_sizeOf <= 0) then {
        private _veh = createSimpleObject [_className,[0,0,-100],true];
        _sizeOf = ((boundingboxreal _veh select 0) vectordistance (boundingboxreal _veh select 1));
        deleteVehicle _veh;
    };
    _sizeOf
};

ITW_FncAceHeal = {
    if (! isNil "ace_medical_fnc_fullHeal") then {
        _this call ace_medical_fnc_fullHeal;
    } else {
        if (! isNil "ace_medical_treatment_fnc_fullHeal") then {
            [objNull,_this,false] call ace_medical_treatment_fnc_fullHeal;
        };
    };
};

ITW_FncAiHalo = {
    params ["_unit"];
    if (!alive(_unit)) exitWith {};
    if (!local _unit) exitWith {_this remoteExec ["ITW_FncAiHalo",_unit]};
	_para = "Steerable_Parachute_F" createVehicle position _unit;
	_para setPosATL getPosATL _unit;
	_para setdir direction _unit;
	_vel = velocity _unit;
	_unit moveindriver _para;
	_para lock false;
};

ITW_FncVehicleHalo = {
    // spawn where _veh is local
    params ["_veh",["_posATL",[]]];
    scriptName "ITW_FncVehicleHalo";
    if (!local _veh) exitWith {_this remoteExec ["ITW_FncVehicleHalo",_veh]};
    
    if !(_posATL isEqualTo []) then {
        if (surfaceIsWater _posATL) then {
            private _posASL = ATLtoASL _posATL;
            if (_posASL#2 < 30) then {_posASL set [2,30]};
            _veh setPosASL _posASL;
        } else {
            if (_posATL#2 < 30) then {_posATL set [2,30]};
            _veh setPosATL _posATL;
        };
    };
    
    private _safePos = getPosATL _veh; // pos that is safe (over water for ships, over land for cars
    private _isShip = _veh isKindOf "Ship";
    private _saveElev = if (_isShip) then {-1} else {0};
    private _startedOverCorrectTerrain = _isShip == (getTerrainHeightASL  _safePos < _saveElev);
    private _vehCrew = crew _veh;
    
    {
        _x setVariable ["FVH_TARGET",_x checkAIFeature "TARGET"];
        _x setVariable ["FVH_AUTOTARGET",_x checkAIFeature "TARGET"];
        _x disableAI "TARGET";
        _x disableAI "AUTOTARGET";
    } forEach _vehCrew;

    private _parachute = createVehicle ["B_Parachute_02_F", [0,0,0], [], 0, "NONE"];
    _parachute setDir getDir _veh;
    _parachute setPos getPos _veh;
    _veh attachTo [_parachute, [0, 0, 1.5]];  
    	
    _parachute setVectorUp [0,0,1];
    _veh setVectorUp [0,0,1];
    
    private _cntr = 25;
    while {((getPos _veh) select 2) > 5 && // getPos to handle ASL or ATL
            {!(isNull _parachute) && 
            {(count (lineIntersectsWith [getPosASL _veh, (getPosASL _veh) vectorAdd [0, 0, -0.5], _veh, _parachute])) == 0 }}} do {
        sleep 0.2;
        (_veh call BIS_fnc_getPitchBank) params ["_vx","_vy"];
        if (([_vx,_vy] findIf {_x > 80 || {_x < -80}}) != -1) then {	
            _parachute setVectorUp [0,0,1];
            _veh setVectorUp [0,0,1];
        };
        if (velocity _parachute #2 > -1) then {
            _cntr = _cntr - 1;
            if (_cntr == 0) then {detach _veh;deleteVehicle _parachute};
        };
        
        // check if ship blew into land or car blew into sea
        if (!isNull _parachute && _startedOverCorrectTerrain) then {
            private _vpos = getPosATL _parachute;
            if (_isShip == (getTerrainHeightASL  _vpos < _saveElev)) then {
                _safePos = _vpos;
            } else {
                _safePos set [2,(getPosATL _parachute)#2];
                _parachute setDir (_vpos getDir _safePos);
                _parachute setPosATL _safePos;
            };
        };
    };

    _parachute disableCollisionWith _veh;
    _veh setVectorUp [0,0,1];
    _veh setVelocity [0,0,0];
    detach _veh;
    ALLOW_DAMAGE(_veh,false);
    while {!isTouchingGround _veh && {getPos _veh #2 > 4}} do { // getPos to handle ASL or ATL
        _veh setVectorUp [0,0,1];
        _veh setVelocity [0,0,-1]; 
        sleep 0.2;
    };
    if (!isNull _parachute) then {deleteVehicle _parachute};
    sleep 1;
    private _up = surfaceNormal getPosATL _veh; 
    if ((_up vectorCos (vectorUp _veh)) < 0.8) then {              
        _veh setVectorUp _up;
    };
    ALLOW_DAMAGE(_veh,true);
    
    {
        if (_x getVariable ["FVH_TARGET",false])    then {_x enableAI "TARGET"};
        if (_x getVariable ["FVH_AUTOTARGET",false])then {_x enableAI "AUTOTARGET"};
        _x setVariable ["FVH_TARGET",nil];
        _x setVariable ["FVH_AUTOTARGET",nil];
    } forEach _vehCrew;
};

ITW_FncSetUnitLoadout = {
    // some ALIVE factions have restricted uniforms so use this function instead of setUnitLoadout
    params ["_unit","_loadout"];
    // if unit was just spawned in, it may still be loading it's loadout, so wait for that to complete
    private _timeout = time + 2;
    while {time < _timeout && getUnitLoadout _unit isEqualTo [[],[],["hgun_Pistol_01_F","","","",[],[],""],[],[],[],"","",[],["","","","","",""]]} do {sleep 0.01};
    if (isSwitchingWeapon _unit) then {
        if (!canSuspend) exitWith {_this spawn ITW_FncSetUnitLoadout};
        waitUntil {!isSwitchingWeapon _unit};
    };
    _unit setUnitLoadout _loadout;
    private _uniformInfo = _loadout#3;
    if (uniform _unit isEqualTo "" && {count _uniformInfo > 1}) then {
        _unit forceAddUniform (_uniformInfo#0);
        {
            if (count _x > 1) then {
                for "_i" from 1 to (_x#1) do {
                    _unit addItemToUniform _x#0;
                };
            };
        } count (_uniformInfo#1);
    };
    _unit setVariable ["ITW_loadout",getUnitLoadout _unit,true];
};

ITW_FncGetLoadoutFromClass = {
    //  3CB_Factions mod does not return the full loadout when 'getUnitLoadout _class' is called
    //  So this function will get the real loadout of all classes
    params ["_unitClass"];
    private _loadout = getArray (configFile >> "CfgVehicles">> _unitClass >> "ALiVE_orbatCreator_loadout");
    if (_loadout isEqualTo []) then {
        _loadout = getUnitLoadout _unitClass;
    };
    private _uniformInfo = _loadout#3;
    if (count _uniformInfo < 2 || {_uniformInfo#1 isEqualTo []}) then {
        private _addons = unitAddons _unitClass;
        private _found = _uniformInfo isEqualTo []; // units with no uniform info are automatically found
        {
            if ([_x,"UK3CB_Factions_"] call ITW_FncStartsWith) exitWith {_found = true};
        } forEach _addons;        
        if (_found) then {
            if (isNil "LoadoutFromClassHash") then {LoadoutFromClassHash = createHashmap};
            _loadout = LoadoutFromClassHash getOrDefault [_unitClass,[]];
            if (_loadout isEqualTo []) then {
                private _dummyUnit = _unitClass createVehicleLocal [0,0,100];
                private _cnt = 20;
                waitUntil {
                    sleep 0.01;
                    _cnt = _cnt - 1;
                    _loadout = getUnitLoadout _dummyUnit; 
                    private _unif = _loadout#3;
                    _cnt < 0 || {count _unif > 1 && {!(_loadout#3#1 isEqualTo [])}}
                };
                sleep 0.1; // sometimes it's still loading items, so wait a bit more
                _loadout = getUnitLoadout _dummyUnit;
                deleteVehicle _dummyUnit;
                LoadoutFromClassHash set [_unitClass,_loadout];
            };
        };    
    };
    _loadout
};

ITW_FncGetServerAiDifficultySetting = {
    if (isNil "SERVER_AI_DIFFICULTY_SETTING") then {
        private _general = getArray (configfile >> "CfgAISkill" >> "general");
        private _aimingAccuracy = getArray (configfile >> "CfgAISkill" >> "aimingAccuracy");
        if ( ((_general select 0) == 0) and ((_general select 2) == 1) and ((_aimingAccuracy select 0) == 0) and ((_aimingAccuracy select 2) == 1) and
            ((_general select 3) > (_general select 1)) and ((_aimingAccuracy select 3) > (_aimingAccuracy select 1)) ) then {
            private _maxGeneral = _general select 3;
            private _maxAimingAccuracy = _aimingAccuracy select 3;

            // skillFinal "general" for setSkill 1 at Difficulty Skill 0
            private _SFG_for_SS1_at_DS0 = _maxGeneral * 0.8;
            // skillFinal "general" for setSkill 1 at Difficulty Skill 1
            private _SFG_for_SS1_at_DS1 = _maxGeneral;

            // skillFinal "aimingAccuracy" for setSkill 1 at Difficulty Skill 0
            private _SFAA_for_SS1_at_DS0 = _maxAimingAccuracy * 0.8;
            // skillFinal "aimingAccuracy" for setSkill 1 at Difficulty Skill 1
            private _SFAA_for_SS1_at_DS1 = _maxAimingAccuracy;

            private _group = createGroup sideLogic;
            private _logic = _group createUnit ["Logic", [0,0,0], [], 0, "NONE"];

            _logic setSkill 1;
            private _skillFinalG = _logic skillFinal "general";
            private _skillFinalAA = _logic skillFinal "aimingAccuracy";

            private _difficultySkill = (_skillFinalG - _SFG_for_SS1_at_DS0) / (_SFG_for_SS1_at_DS1 - _SFG_for_SS1_at_DS0);
            private _difficultyPrecision = (_skillFinalAA - _SFAA_for_SS1_at_DS0) / (_SFAA_for_SS1_at_DS1 - _SFAA_for_SS1_at_DS0);
            
            deleteVehicle _logic;
            deleteGroup _group;

            SERVER_AI_DIFFICULTY_SETTING = [_difficultySkill, _difficultyPrecision];
        } else {
            SERVER_AI_DIFFICULTY_SETTING = [0.5,0.5];
        };
    };
    SERVER_AI_DIFFICULTY_SETTING#0;
};

ITW_FncSetUnitBehavior = {
    params ["_unit","_behavior"];
    private _newGroup = createGroup side _unit;
    private _oldGroup = group _unit;
    [_unit] joinSilent _newGroup;
    _unit setBehaviour _behavior;
    [_unit] joinSilent _oldGroup;
    deleteGroup _newGroup;
};

ITW_FncRemoteLocalGroup = {
    // use for remoteExec where group is local
    //  _args remoteExec [_cmd,groupOwner _group];
    // but groupOwner only works on the server so use this command
    params ["_args","_cmd","_group"];
    if (isNull _group) exitWith {};
    if (local _group)  exitWith {_args remoteExec [_cmd,clientOwner]};
    if (isServer)      exitWith {_args remoteExec [_cmd,groupOwner _group]};
    _this remoteExec ["ITW_FncRemoteLocalGroup",2];
};

ITW_FncAngle = {
    // shortest angle between two directions (0-360)
    params ["_dir1","_dir2"];
    private _abs = abs (_dir1 - _dir2);
    _abs min (360 - _abs)
};

ITW_FncDirMidpoint = {
    // find the midpoint between two directions
    params ["_angleA", "_angleB"];

    private _diff = ((_angleB - _angleA + 180) % 360 + 360) % 360 - 180;
    private _midpoint = ((_angleA + (_diff / 2)) % 360 + 360) % 360;

    _midpoint 
};

ITW_FncCutTextXY = {
    // like cutext but with x,y args,   remove with: _layer cuttext ["","plain"];
    // X: 0 is 1/4 down the screen, 1 is 1/4 from bottom
    // Y: 0 is center
    params ["_layer","_text","_x","_y"];
    _layer cutrsc ["rscDynamicText","plain"];

    private _display = uinamespace getvariable "BIS_dynamicText";
    private _control = _display displayctrl 9999;
    _control ctrlsetfade 1;
    _control ctrlcommit 0;
    _pos = ctrlposition _control;
    _pos set [0,_x];
    _pos set [1,_y];
    _control ctrlsetposition _pos;

    if (typeName _text == typeName "") then {
        _control ctrlsetstructuredtext parseText _text;
    }
    else {
        _control ctrlsetstructuredtext _text;
    };
    _control ctrlcommit 0;

    _control ctrlsetfade 0;
    _control ctrlcommit 0.5;
};

ITW_FncSogPrairieFireFix = {
    // Fix SOG Prairie Fire chatting if players aren't a blue faction (run on server)
    params ["_playerFaction","_enemyFaction",["_civFaction",""],["_independentFaction",""]];

    if (!isNil "vn_sam_voiceHash") then {
        private _playerSideNum = [_playerFaction] call FactionSideNum;
        private _enemySideNum = [_enemyFaction] call FactionSideNum;
        private _invSideNum = if (_independentFaction isEqualTo "" || {_independentFaction isEqualTo []}) then {_enemySideNum} else {[_independentFaction] call FactionSideNum};
        private _civSideNum = if (_civFaction isEqualTo "" || {_civFaction isEqualTo []}) then {3} else {[_civFaction] call FactionSideNum};
        vn_sam_voiceHash  set [WEST,_playerSideNum];  // default 1
        vn_sam_voiceHash  set [EAST,_enemySideNum];   // default 0 
        vn_sam_voiceHash  set [resistance,_invSideNum]; // default 2 
        vn_sam_voiceHash  set [civilian,_civSideNum]; // default 3 
    };  
};

ITW_FncCloneReplacement = {
    params ["_sourceUnit"];

    // Capture all data from source unit
    private _type = typeOf _sourceUnit;
    private _loadout = getUnitLoadout _sourceUnit;
    private _face = face _sourceUnit;
    private _voice = speaker _sourceUnit;
    private _name = name _sourceUnit;
    private _rank = rank _sourceUnit;
    private _skill = skill _sourceUnit;
    private _pos = getPosATL _sourceUnit vectorAdd [2, 0, 0];
    private _group = group _sourceUnit;
    deleteVehicle _sourceUnit;
    
    // Create the new unit
    private _clone = _group createUnit [_type, _pos, [], 0, "CAN_COLLIDE"];

    _clone setUnitLoadout _loadout;
    _clone setFace _face;
    _clone setSpeaker _voice;
    _clone setRank _rank;
    _clone setSkill _skill;
    _clone setName _name;
    lockIdentity _clone;
};

ITW_FncNonHumanSwitch = {
    private _factionUnits = [ITW_PlayerFaction] call FactionUnits;
    if (_factionUnits isNotEqualTo []) then {
        if (-1 != (_factionUnits findIf {getText (configFile >> "CfgVehicles" >> _x >> "moves") != "CfgMovesMaleSdr"})) then {
            // choose unit type
            private _unitNames = _factionUnits apply {getText (configFile >> "CfgVehicles" >> _x >> "displayName")};
            if (isNil "SKL_ListSelector") then {SKL_ListSelector = compileFinal preprocessFileLineNumbers "scripts\SKULL\SKL_ListSelector.sqf"};
            private _index = [_unitNames,localize "STR_ITW_BASE_ChooseBodyType"] call SKL_ListSelector;
            if (_index >= 0) then {
                // switch player into the player faction
                private _playerPos = getPosASL player;
                private _oldBody = player;
                private _grp = createGroup ITW_PlayerSide;
                private _newBody = _grp createUnit [_factionUnits#_index, [0,0,0], [], 0, "NONE"];
                [_newBody] joinSilent _grp;
                private _identity = [_newBody] call ITW_FncGetIdentity;
                sleep 0.5; // allow new body to fully initialize
                player setPosATL [0,0,0];
                _newBody setPosASL _playerPos;
                selectPlayer _newBody;
                waitUntil {player == _newBody};
                private _assignedCurator = getAssignedCuratorLogic _oldBody;
                if (!isNull _assignedCurator) then {
                    [_assignedCurator] remoteExec ["unassignCurator", 2];
                    sleep 0.05;
                    [_newBody, _assignedCurator] remoteExec ["assignCurator", 2];
                    [_assignedCurator, [[_newBody], true]] remoteExec ["addCuratorEditableObjects", 2];
                };
                deleteVehicle _oldBody;
                player setVariable ["ITW_nonHuman",true];
                [_newBody,_identity#0,_identity#1] remoteExec ["ITW_FncSetIdentityMP",0,true];
            };
        };
    };
};

ITW_FncResetZeus = {
    params ["_admin"];
    if (!isServer) exitWith {diag_log "ITW: Error Pos: ITW_FncResetZeus called on client"};
    if (admin remoteExecutedOwner == 0) exitWith {diag_log format "ITW: Error Pos: ITW_FncResetZeus called by non-admin %1:%2 (%3)",remoteExecutedOwner,_admin,name _admin};
    
    // Server-side cleanup of dead/empty curators
    {
        if (isNull (getAssignedCuratorUnit _x)) then {
            deleteVehicle _x;
        };
    } forEach allCurators;

    // Server-side creation
    private _logicGroup = createGroup sideLogic;
    private _newCurator = _logicGroup createUnit ["ModuleCurator_F", [0,0,0], [], 0, "NONE"];
    
    sleep 0.5; // wait for module to initialize
    
    _admin assignCurator _newCurator;
    call ITW_FncAddCuratorObjects;
};

ITW_FncRotateVeh = {
    params ["_vehicle", "_angle"];
    // rotate a vehicle safely on uneven terrain
    if (!local _vehicle) exitWith {_this remoteExec ["ITW_FncRotateVeh",_vehicle]};
    private _isDmgAllowed = isDamageAllowed _vehicle;
    [_vehicle, false] remoteExec ["enableSimulationGlobal", 2];
    waitUntil {!simulationEnabled _vehicle};
    _vehicle enableSimulationGlobal false;
    _vehicle allowDamage false;
    private _surfaceNormal = surfaceNormal (getPosWorld _vehicle);
    private _orthoDirVector = [sin _angle, cos _angle, 0] vectorCrossProduct _surfaceNormal vectorCrossProduct _surfaceNormal vectorMultiply -1;
    _vehicle setVectorDirAndUp [_orthoDirVector, _surfaceNormal];
    private _pos = getPosASL _vehicle;
    _pos set [2, (_pos select 2) + 3];
    _vehicle setPosASL _pos;
    [_vehicle, true] remoteExec ["enableSimulationGlobal", 2];
    if (_isDmgAllowed) then {
        _vehicle spawn {
            waitUntil {!simulationEnabled _vehicle};
            sleep 2;
            _this allowDamage true;
        };
    };
};

#if ITW_ALLOW_DAMAGE_DEBUG == 1
// debug units that have damage blocked
ITW_FncAllowDamageDEBUG = {
    params ["_who","_allowed",["_file",""],["_line",""]];
    if (!local _who) then {_this remoteExec ["ITW_FncAllowDamage",_who]};
    _who allowDamage _allowed;

    [netId _who,_allowed,_file,_line,clientOwner] remoteExec ["ITW_FncAllowDamageDEBUGServer",2];
};

ITW_FncAllowDamageDEBUGServer = {
    params ["_netId","_allowed","_file","_line","_client"];
    #define DMG_SRV_WATCH_LIMIT 75
    if (isNil "ITW_FNC_DMG_BLOCKED") then {
        ITW_FNC_DMG_BLOCKED = createHashmap;
        ITW_FNC_DMG_BLOCKED_SEM = false;
        0 spawn {
            while {true} do {
                sleep 5;
                waitUntil {!ITW_FNC_DMG_BLOCKED_SEM}; ITW_FNC_DMG_BLOCKED_SEM = true;
                private _remove = [];
                {
                    private _netId = _x;
                    private _who = objectFromNetId _netId;
                    if (alive _who) then {
                        _y params ["_time","_file","_line","_client"];
                        if (time - _time > DMG_SRV_WATCH_LIMIT) then {
                            private _whoStr = if (isNull group _who) then {typeOf _who + ":" + _netId} else {str _who};
                            diag_log format ["DmgBlocked Timeout %1sec %2 (%3#%4 client %5) isDmgAllowed on server:%7",round (time - _time),_whoStr,_file,_line,_client,isDamageAllowed _who];
                            [_who,true] remoteExec ["allowDamage",_who]; // lets force it to allow damage since it's been too long
                            _remove = _netId;
                        };
                    } else {
                        ITW_FNC_DMG_BLOCKED deleteAt _netId;
                    };
                } forEach ITW_FNC_DMG_BLOCKED;
                {ITW_FNC_DMG_BLOCKED deleteAt _x} forEach _remove;
                ITW_FNC_DMG_BLOCKED_SEM = false;
            };
        };
    };
    
    waitUntil {!ITW_FNC_DMG_BLOCKED_SEM}; ITW_FNC_DMG_BLOCKED_SEM = true;
    if (_allowed) then {
        (ITW_FNC_DMG_BLOCKED getOrDefault [_netId,[1e10,"",-1,-1]]) params ["_time","_fileL","_lineL","_clientL"];
        private _t = time - _time;
        private _who = objectFromNetId _netId;
        private _whoStr = if (isNull group _who) then {typeOf _who + ":" + _netId} else {str _who};
        if (_t > DMG_SRV_WATCH_LIMIT) then {diag_log format ["DmgBlocked freed after %1sec %2 (lock: %3#%4 client %5) (free: %6#%7 client %8)",round _t,_whoStr,_fileL,_lineL,_clientL,_file,_line,_client]};
        ITW_FNC_DMG_BLOCKED deleteAt _netId;
    } else {
        ITW_FNC_DMG_BLOCKED set [_netId,[time,_file,_line,_client]];
    };
    ITW_FNC_DMG_BLOCKED_SEM = false;
};
["ITW_FncAllowDamageDEBUG"] call SKL_fnc_CompileFinal;
["ITW_FncAllowDamageDEBUGServer"] call SKL_fnc_CompileFinal;
#endif

["ITW_FncStartsWith"] call SKL_fnc_CompileFinal;
["ITW_FncEndsWith"] call SKL_fnc_CompileFinal;
["ITW_FncPlayerSide"] call SKL_fnc_CompileFinal;
["ITW_FncActiveAllies"] call SKL_fnc_CompileFinal;
["ITW_FncActivePlayers"] call SKL_fnc_CompileFinal;
["ITW_FncAllAllies"] call SKL_fnc_CompileFinal;
["ITW_FncAllActiveUnits"] call SKL_fnc_CompileFinal;
["ITW_FncActiveEnemies"] call SKL_fnc_CompileFinal;
["ITW_FncAddCuratorObjects"] call SKL_fnc_CompileFinal;
["ITW_FncIsNight"] call SKL_fnc_CompileFinal;
["ITW_FncSetTime"] call SKL_fnc_CompileFinal;	
["ITW_FncSetWeather"] call SKL_fnc_CompileFinal;
["ITW_FncMpWeather"] call SKL_fnc_CompileFinal;    
["ITW_FncGetNVGs"] call SKL_fnc_CompileFinal;
["ITW_FncIsLeadPlayer"] call SKL_fnc_CompileFinal;
["ITW_RemoveTerrainObjects"] call SKL_fnc_CompileFinal;
["ITW_FncCleanup"] call SKL_fnc_CompileFinal;
["ITW_FncSemWait"] call SKL_fnc_CompileFinal;
["ITW_FncDelayCall"] call SKL_fnc_CompileFinal;
["ITW_FncGetRemoteVar"] call SKL_fnc_CompileFinal;
["ITW_FncGetRemoteVarGet"] call SKL_fnc_CompileFinal;
["ITW_FncGetRemoteVarReturn"] call SKL_fnc_CompileFinal;
["ITW_FncRelPos"] call SKL_fnc_CompileFinal;
["ITW_fnc_HeliHasWeapons"] call SKL_fnc_CompileFinal;
["ITW_fnc_HelipadObject"] call SKL_fnc_CompileFinal;
["ITW_FncSetIdentity"] call SKL_fnc_CompileFinal;
["ITW_FncSetIdentityMP"] call SKL_fnc_CompileFinal;
["ITW_FncInfiniteAmmo"] call SKL_fnc_CompileFinal;
["ITW_FncAceHeal"] call SKL_fnc_CompileFinal;
["ITW_FncSizeOf"] call SKL_fnc_CompileFinal;
["ITW_FncSetUnitLoadout"] call SKL_fnc_CompileFinal;
["ITW_FncGetLoadoutFromClass"] call SKL_fnc_CompileFinal;
["ITW_FncGetServerAiDifficultySetting"] call SKL_fnc_CompileFinal;
["ITW_FncClosest"] call SKL_fnc_CompileFinal;
["ITW_FncClosestIndex"] call SKL_fnc_CompileFinal;
["ITW_FncSetUnitBehavior"] call SKL_fnc_CompileFinal;
["ITW_FncAiHalo"] call SKL_fnc_CompileFinal;
["ITW_FncVehicleHalo"] call SKL_fnc_CompileFinal;
["ITW_FncRemoteLocalGroup"] call SKL_fnc_CompileFinal;
["ITW_FncSogPrairieFireFix"] call SKL_fnc_CompileFinal;
["ITW_FncAngle"] call SKL_fnc_CompileFinal;
["ITW_FncCloneReplacement"] call SKL_fnc_CompileFinal;
["ITW_FncDirMidpoint"] call SKL_fnc_CompileFinal;
["ITW_FncCutTextXY"] call SKL_fnc_CompileFinal;
["ITW_FncGetIdentity"] call SKL_fnc_CompileFinal;
["ITW_FncNonHumanSwitch"] call SKL_fnc_CompileFinal;
["ITW_FncResetZeus"] call SKL_fnc_CompileFinal;
["ITW_FncRotateVeh"] call SKL_fnc_CompileFinal;
