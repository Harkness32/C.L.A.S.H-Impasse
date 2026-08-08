// Modified version of the CAS module
// Sends a CAS plane to bomb the target.
// If plane doesn't support bombs, the missiles and/or machine guns will be used

// Arguments:
//   _caller:     player who will receive audio acknowledgements
//   _targetATL:  position to attack
//   _dir:        direction attack craft will be heading as it attacks
//   _side:       side aircraft will be on
//   _planeClass: plane's cfgVehicle class or an array of [_class,_texture,_anim]
//   _delay:      extra delay time 
//   _completeCallback: a string or code that will be called on the server once plane has fired on the target 
//                      with arguments [_caller,_targetATL,_plane]

params ["_caller","_targetATL","_dir",["_side",west],["_planeClass",""],["_delay",20],["_completeCallback",""],["_invulnerablePlane",false]];

if !(isserver) exitWith {diag_log format ["Error Pos: SKL_CASPlane: Called on client (%1)",_this]; false};

if (_planeClass isEqualTo "") then {_planeClass = "B_Plane_CAS_01_F"};

private _texture = false;
private _anim = false;
if (typeName _planeClass isEqualTo "ARRAY") then {
    _texture = _planeClass#1;
    _anim = _planeClass#2;
    _planeClass = _planeClass#0;
};


private _sayMessage = {
    params ["_player","_sentence"];
	private _speaker = (side _player) call bis_fnc_moduleHQ;
	if (isNull _speaker) then {isNil {_speaker = (createGroup [west,true]) createUnit ["ModuleHQ_F",[10,10,10],[],0,"none"]}};
	[_speaker,speaker _speaker] remoteExec ["setspeaker",_player];
	[_speaker,1] remoteExec ["setpitch",_player];
	_speaker setBehaviour behaviour _speaker;
    [_speaker,_sentence] remoteExec ["globalRadio",_player];
};

private _planeCfg = configFile >> "cfgvehicles" >> _planeClass;
if !(isclass _planeCfg) exitWith {
    diag_log format ["SKL_CASPlane: Vehicle class '%1' not found",_planeClass]; 
    [_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;
    hint localize "STR_SKL_CAS_NoVehicle";
    false
};

//--- Detect gun
private _weaponCategories = ["bomblauncher","missilelauncher","machinegun"];
private _weaponTypes = [];
private _weapons = [];
private _mgWeapons = [];
private _mgTypes = [];
{  
    private _planeWeapon = _x;
    private _wpnType = toLowerANSI ((_planeWeapon call bis_fnc_itemType) select 1);
    if (_wpnType in _weaponCategories) then {
        _modes = getArray (configFile >> "cfgweapons" >> _planeWeapon >> "modes");
        if (count _modes > 0) then {
            _mode = _modes select 0;
            if (_mode == "this") then {_mode = _planeWeapon};
            if (_wpnType == "machinegun") then {
                _mgWeapons set [count _weapons,[_planeWeapon,_mode]];
                _mgTypes pushBackUnique _wpnType;
            } else {
                _weapons set [count _weapons,[_planeWeapon,_mode]];
                _weaponTypes pushBackUnique _wpnType;
            }
        };
    };
} foreach (_planeClass call bis_fnc_weaponsEntityType);

// make machine guns be the last weapon to fire
_weapons append _mgWeapons;
_weaponTypes append _mgTypes;

if (count _weapons == 0) exitWith {
    diag_log format ["SKL_CASPlane: No weapon of types %2 found on '%1'",_planeClass,_weaponCategories]; 
    [_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;
    hint localize "STR_SKL_CAS_PlaneUnableToComply";
    false
};
private _isBombingOnly = ["bomblauncher"] isEqualTo _weaponTypes;
private _isBombAndMore = "bomblauncher" in _weaponTypes;
//--- Play radio
[_caller,"CuratorModuleCAS"] call _sayMessage;

sleep _delay;

private _posATL = _targetATL;
private _pos = +_posATL;
_pos set [2,(_pos select 2) + getTerrainHeightASL _pos];

private _dis = 3000;
private _alt = 1000;
private _speed = 400 / 3.6;
private _duration = ([0,0] distance [_dis,_alt]) / _speed;

//--- Create plane
private _planePos = _pos getPos [_dis,_dir + 180];
_planePos set [2,(_pos select 2) + _alt];
private _planeSide = _side;
private _planeArray = [_planePos,_dir,_planeClass,_planeSide] call bis_fnc_spawnVehicle;
private _plane = _planeArray select 0;
sleep 0.05;

if (_invulnerablePlane) then {_plane allowDamage false;{_x allowDamage false} foreach crew _plane};
group _plane setVariable ["noHeadless",true];

[_plane,_texture,_anim] call BIS_fnc_initVehicle;
_plane setPosASL _planePos;
_plane move (_pos getPos [_dis,_dir]);
_plane disableAi "move";
_plane disableAi "target";
_plane disableAi "autotarget";
_plane setCombatMode "blue";

private _vectorDir = [_planePos,_pos] call bis_fnc_vectorFromXtoY;
private _velocity = [_vectorDir,_speed] call bis_fnc_vectorMultiply;
_plane setVectorDir _vectorDir;
[_plane,-90 + atan (_dis / _alt),0] call bis_fnc_setpitchbank;
private _vectorUp = vectorUp _plane;

//--- Remove all other weapons;
private _currentWeapons = weapons _plane;
{
    if !(toLowerANSI ((_x call bis_fnc_itemType) select 1) in (_weaponTypes + ["countermeasureslauncher"])) then {
        _plane removeWeapon _x;   
    };
} foreach _currentWeapons;

//--- Cam shake
private _ehFired = _plane addeventhandler [
    "fired",
    {
        _this spawn {
            _plane = _this select 0;
            _plane removeEventHandler ["fired",_plane getVariable ["ehFired",-1]];
            _projectile = _this select 6;
            _plane setVariable ["casFired",true];
            private _target = _plane getVariable ["target",[0,0,0]];
            waitUntil {isNull _projectile};
            if (typeName _target != "ARRAY") then {_target = getPosATL _target};
            [[0.005,4,[_target,200]],"bis_fnc_shakeCuratorCamera"] call bis_fnc_mp;
        };
    }
];
_plane setVariable ["casFired",false];
_plane setVariable ["ehFired",_ehFired];
_plane setVariable ["target",_targetATL];

//--- Approach
private _didFire = false;
private _fire = [] spawn {waitUntil {false}};
private _fireNull = true;
private _time = time;
private _offset = if ({_x == "missilelauncher"} count _weaponTypes > 0) then {20} else {0};
private _target = objNull;
waitUntil {
    private _fireProgress = _plane getVariable ["fireProgress",0];

    //--- Set the plane approach vector
    _plane setVelocityTransformation [
        _planePos, [_pos select 0,_pos select 1,(_pos select 2) + _offset + _fireProgress * 12],
        _velocity, _velocity,
        _vectorDir,_vectorDir,
        _vectorUp, _vectorUp,
        (time - _time) / _duration
    ];
    _plane setVelocity velocity _plane;

    //--- Fire!
    if ((getPosASL _plane) distance _pos < 1000 && _fireNull) then {

        //--- search order:  laser target, vehicle, infantry
        _target = ((_targetATL nearEntities ["LaserTarget",250]) select {_planeSide getFriend side _x < 0.5}) param [0,objNull];
        if (isNull _target) then {
            _target = ((_targetATL nearEntities ["landVehicles",250]) select {_planeSide getFriend side _x < 0.5}) param [0,objNull];
            if (isNull _target) then {
                _target = ((_targetATL nearEntities ["allVehicles",250]) select {_planeSide getFriend side _x < 0.5}) param [0,objNull];
            };
        };
        _plane reveal _target;
        _plane doWatch _target;
        _plane doTarget _target;
        _plane setVariable ["target",_target];

        _fireNull = false;
        terminate _fire;
        _fire = [_plane,_weapons,_target,_isBombingOnly] spawn {
            private _plane = _this select 0;
            private _planeDriver = driver _plane;
            private _weapons = _this select 1;
            private _target = _this select 2;
            private _isBombingOnly = _this select 3;
            private _duration = 4;
            private _time = time + _duration;
            waitUntil {
                {
                    private _fired = _planeDriver fireAtTarget [_target,(_x select 0)];
                    if (!_fired) then {driver _plane forceWeaponFire _x};
                } foreach _weapons;
                _plane setVariable ["fireProgress",(1 - ((_time - time) / _duration)) max 0 min 1];
                sleep 0.1;
                time > _time || _isBombingOnly || isNull _plane 
            };
            sleep 1;
        };
        if (_invulnerablePlane) then {_plane allowDamage true;{_x allowDamage true} foreach crew _plane};
        _didFire = true;
    };

    sleep 0.01;
    scriptDone _fire || isNull _plane
};


_plane setVelocity velocity _plane;
_plane flyinheight _alt;

//--- Fire CM
if ({_x == "bomblauncher"} count _weaponTypes == 0) then {
    _plane removeEventHandler ["fired",_plane getVariable ["ehFired",-1]];
    for "_i" from 0 to 1 do {
        driver _plane forceWeaponFire ["CMFlareLauncher","Burst"];
        _time = time + 1.1;
        waitUntil {time > _time || isNull _plane};
    };
} else {sleep 1.1};
sleep 2;

if !(_plane getVariable ["casFired",false]) then {
    // some planes don't fire anything, so lets add some explosion
    _targetPos = if (isNull _target) then {_targetATL} else {getPosATL _target};
    if (_isBombAndMore) then {
        ("Bo_GBU12_LGB" createVehicle _targetPos) setDamage 1;
    } else {
        ("M_Scalpel_AT" createVehicle _targetPos) setDamage 1;
    };
};

if (_completeCallback isNotEqualTo "" && _completeCallback isNotEqualTo {}) then {
    if (typeName _completeCallback == "STRING") then {
        [_caller,_targetATL,_plane] call compile _completeCallback;
    } else {
        [_caller,_targetATL,_plane] call _completeCallback;
    };
};

_timeout = time + 60;
waitUntil {sleep 1;_plane distance _pos > _dis || !alive _plane || time > _timeout};

if (!alive _plane && !_didFire) then {[_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;};

//--- Delete plane
if (alive _plane) then {
    private _group = group _plane;
    private _crew = crew _plane;
    _plane allowDamage true;
    {_x allowDamage true} foreach _crew;
    deleteVehicleCrew _plane;
    deleteVehicle _plane;
    deleteGroup _group;
};
true