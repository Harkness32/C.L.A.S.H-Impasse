// Modified version of the CAS module
// Sends a CAS heli to attack the target.

// Arguments:
//   _caller:     player who will receive audio acknowledgements
//   _targetATL:  position to attack
//   _dir:        direction attack craft will be heading as it attacks
//   _side:       side aircraft will be on
//   _heliClass:  heli cfgVehicle class or an array of [_class,_texture,_anim]
//   _delay:      extra delay time 

params ["_caller","_targetATL","_dir",["_side",west],["_heliClass",""],["_delay",20]];

if !(isserver) exitwith {diag_log format ["Error Pos: SKL_CASHeli: Called on client (%1)",_this]; false};

if (_heliClass isEqualTo "") then {_heliClass = "B_Heli_Attack_01_dynamicLoadout_F"};

private _texture = false;
private _anim = false;
if (typeName _heliClass isEqualTo "ARRAY") then {
    _texture = _heliClass#1;
    _anim = _heliClass#2;
    _heliClass = _heliClass#0;
};

private _sayMessage = {
    params ["_player","_sentence"];
	private _speaker = (side _player) call bis_fnc_moduleHQ;
	if (isnull _speaker) then {isNil {_speaker = (creategroup [west,true]) createunit ["ModuleHQ_F",[10,10,10],[],0,"none"]}};
	[_speaker,speaker _speaker] remoteExec ["setspeaker",_player];
	[_speaker,1] remoteExec ["setpitch",_player];
	_speaker setbehaviour behaviour _speaker;
    [_speaker,_sentence] remoteExec ["globalradio",_player];
};

private _heliCfg = configfile >> "cfgVehicles" >> _heliClass;
if !(isclass _heliCfg) exitwith {
    diag_log format ["SKL_CASHeli: Vehicle class '%1' not found",_heliClass]; 
    [_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;
    hint localize "STR_SKL_CAS_NoVehicle";
    false
};

//--- Detect gun
private _weaponCategories = [["missilelauncher"]]; // in search order, first found is used
private _weaponTypes = ["missilelauncher"];
private _weapons = [];
{
    private _wpnTypes = _x;
    {  
        private _heliWeapon = _x;
        if (tolower ((_heliWeapon call bis_fnc_itemType) select 1) in _wpnTypes) then {
            _modes = getarray (configfile >> "cfgweapons" >> _heliWeapon >> "modes");
            if (count _modes > 0) then {
                _mode = _modes select 0;
                if (_mode == "this") then {_mode = _heliWeapon};
                _weapons set [count _weapons,[_heliWeapon,_mode]];
            };
        };
        if !(_weapons isEqualTo []) exitWith {_weaponTypes = _wpnTypes};
    } foreach (_heliClass call bis_fnc_weaponsEntityType);
    if !(_weapons isEqualTo []) exitWith {};
} foreach _weaponCategories;
//if (count _weapons == 0) exitwith {
//    diag_log format ["SKL_CASHeli: No weapon of types %2 found on '%1'",_heliClass,_weaponCategories]; 
//    [_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;
//    hint "CAS Heli unable to comply";
//    false
//};

//--- Play radio
[_caller,"CuratorModuleCAS"] call _sayMessage;

sleep _delay;

private _posATL = _targetATL;
private _pos = +_posATL;

private _dis = 1000;
private _alt = 50;
private _speed = 150 / 3.6;
private _duration = ([0,0] distance [_dis,_alt]) / _speed;
_pos set [2,_pos#2 + getTerrainHeightASL _pos];

//--- Create heli
private _heliPos = _pos getPos [_dis,_dir + 180];
_heliPos set [2,_alt + getTerrainHeightASL _heliPos];
private _heliSide = _side;
private _heliArray = [_heliPos,_dir,_heliClass,_heliSide] call bis_fnc_spawnVehicle;
private _heli = _heliArray select 0;
sleep 0.05;
[_heli,_texture,_anim] call BIS_fnc_initVehicle;
_heli setposASL _heliPos;
//_heli disableAi "move";
_heli disableAI "target";
_heli disableAI "autotarget";
_heli disableAI "autocombat";
_heli setcombatmode "blue";
{_x addCuratorEditableObjects [[_heli],true]} count allCurators;
_heli move _pos;
     
private _wp1 = group driver _heli addWaypoint [_posATL,10];
_wp1 setWaypointBehaviour "COMBAT";
_wp1 setWaypointSpeed "NORMAL";
_wp1 setWaypointCombatMode "RED";
_wp1 setWaypointType "MOVE";
_wp1 setWaypointCompletionRadius 200;
private _wp2 = group driver _heli addWaypoint [_posATL,20];
_wp2 setWaypointType "SAD";
private _wp3 = group driver _heli addWaypoint [_posATL,100];
_wp3 setWaypointType "CYCLE";

//--- Debug - visualize tracers
if (false) then {
    BIS_draw3d = [];
    //{deletemarker _x} foreach allmapmarkers;
    _m = createmarker [str _heli,_pos];
    _m setmarkertype "mil_dot";
    _m setmarkersize [1,1];
    _m setmarkercolor "colorgreen";
    _heli addeventhandler [
        "fired",
        {
            _projectile = _this select 6;
            [_projectile,position _projectile] spawn {
                _projectile = _this select 0;
                _posStart = _this select 1;
                _posEnd = _posStart;
                _m = str _projectile;
                _mColor = "colorred";
                _color = [1,0,0,1];
                if (speed _projectile < 1000) then {
                    _mColor = "colorblue";
                    _color = [0,0,1,1];
                };
                while {!isnull _projectile} do {
                    _posEnd = position _projectile;
                    sleep 0.01;
                };
                createmarker [_m,_posEnd];
                _m setmarkertype "mil_dot";
                _m setmarkersize [1,1];
                _m setmarkercolor _mColor;
                BIS_draw3d set [count BIS_draw3d,[_posStart,_posEnd,_color]];
            };
        }
    ];
    if (isnil "BIS_draw3Dhandler") then {
        BIS_draw3Dhandler = addmissioneventhandler ["draw3d",{{drawline3d _x;} foreach (missionnamespace getvariable ["BIS_draw3d",[]]);}];
    };
};
    
//--- Approach
private _didFire = false;
private _fire = [] spawn {waituntil {false}};
private _fireNull = true;
private _time = time;
private _offset = if ({_x == "missilelauncher"} count _weaponTypes > 0) then {20} else {0};
waituntil {
    private _fireProgress = _heli getvariable ["fireProgress",0];
    
    //--- search order:  laser target, infantry, vehicle
    _target = ((_targetATL nearEntities ["LaserTarget",250]) select {_heliSide getFriend side _x < 0.5}) param [0,objNull];
    if (isNull _target) then {
        _target = ((_targetATL nearEntities ["allVehicles",250]) select {_heliSide getFriend side _x < 0.5}) param [0,objNull];
        if (isNull _target) then {
            _target = ((_targetATL nearEntities ["landVehicles",250]) select {_heliSide getFriend side _x < 0.5}) param [0,objNull];
        };
    };
    _heli reveal lasertarget _target;
    _heli dowatch lasertarget _target;
    _heli dotarget lasertarget _target;
    
    //--- Fire!
    if ((getposasl _heli) distance _pos < 600 && _fireNull) then {
        _heli enableAI "target";
        _heli enableAI "autotarget";
        _heli enableAI "autocombat";
        _heli disableAI "move";

        //--- Reveal nearby enemy
        private _allUnits = allUnits select {_x distance2D _posATL < 200};
        {
            private _crew = _x;
            {_crew reveal _x} count _allUnits; 
        } forEach crew _heli;
        
        _fireNull = false;
        terminate _fire;
        if !(_weapons isEqualTo []) then {
            _fire = [_heli,_weapons,_target] spawn {
                private _heli = _this select 0;
                private _heliDriver = driver _heli;
                private _weapons = _this select 1;
                private _target = _this select 2;
                private _duration = 3;
                private _time = time + _duration;
                waituntil {
                    {
                        _heliDriver fireattarget [_target,(_x select 0)];
                    } foreach _weapons;
                    _heli setvariable ["fireProgress",(1 - ((_time - time) / _duration)) max 0 min 1];
                    sleep 0.1;
                    time > _time || isnull _heli 
                };
                _heli enableAI "move";
                sleep 1;
            };
        };
        _didFire = true;
    };

    sleep 0.01;
    scriptDone _fire || isnull _heli
};
deleteWaypoint _wp1;
_heli enableAI "target";
_heli enableAI "autotarget";
_heli enableAI "autocombat";
_heli setcombatmode "red";

//--- Fire CM
for "_i" from 0 to 1 do {
    driver _heli forceweaponfire ["CMFlareLauncher","Burst"];
    _time = time + 1.1;
    waitUntil {time > _time || isnull _heli};
};

private _timeout = time + 120;

waitUntil {time > _timeout || !canMove _heli || !alive _heli};
  
{deleteWaypoint _x} forEachReversed waypoints group driver _heli;
_heli flyInHeight _alt;
//_heli disableAi "move";
_heli disableAI "target";
_heli disableAI "autotarget";
_heli disableAI "autocombat";
_heli setcombatmode "blue";
_heli move _heliPos;

waitUntil {time > _timeout || _heli distance _pos > _dis || !alive _heli};
if (!alive _heli && !_didFire) then {[_caller,"SentUnitDestroyedHQCASBombing"] call _sayMessage;};

//--- Delete heli
if (alive _heli) then {
    private _group = group _heli;
    private _crew = crew _heli;
    deleteVehicleCrew _heli;
    deleteVehicle _heli;
    deleteGroup _group;
};
true
