

ITW_vehRepairPoint = {
    // call only on server to initialize a repair point
    if (!isServer) exitWith {_this remoteExec ["ITW_vehRepairPoint",2]};
    
    params ["_pos","_radius",["_enableCode",{true}],["_enableArg",objNull]];
    
    if (isNil "ITW_VehRepairArray") then {
        ITW_VehRepairArray = [];
        [] spawn ITW_vehRepairTask;
    };
    ITW_VehRepairArray pushBack [_pos,_radius,_enableCode,_enableArg];
    publicVariable "ITW_VehRepairArray";
    
};

ITW_vehRepairPointRemove = {
    // call only on server to initialize a repair point
    if (!isServer) exitWith {_this remoteExec ["ITW_vehRepairPointRemove",2]};
    
    params ["_pos","_radius",["_enableCode",{true}],["_enableArg",objNull]];
    
    if !(isNil "ITW_VehRepairArray") then {
        ITW_VehRepairArray = ITW_VehRepairArray - [[_pos,_radius,_enableCode,_enableArg]];
        publicVariable "ITW_VehRepairArray";
    };
};

ITW_vehRepairTask = {
    // task to handle veh repair points, spawn on server only
    scriptName "ITW_vehRepairTask";
    ITW_VehRepairRunning = true;
    while {true} do {
        while {LV_PAUSE} do {sleep 5};
        sleep 8;
        private _vehRepairArray = ITW_VehRepairArray; 
        private _allVehicles = vehicles select {{isPlayer _x} count crew _x > 0 && {!isSimpleObject  _x && {(_x isKindOf "Air" || _x isKindOf "Land") && {alive _x && {speed _x < 2}}}}};
        _vehiclesRepairing = false;
        {
            _x params ["_pos","_radius","_enableCode","_enableArg"];
            if !(_enableArg call _enableCode) then {continue};
            {
                _x params ["_veh"];
                
                // if firing weapon near service point, need to wait for it to cool before servicing
                if (_veh getVariable ["ITW_vehFiredEH",-1] < 0) then {
                    _veh setVariable ["ITW_vehFiredPos",[_pos,_radius]];
                    private _eh = _veh addEventHandler ["Fired", {
                        params ["_veh"];
                        (_veh getVariable ["ITW_vehFiredPos",[[0,0,0],10]]) params ["_pos","_radius"];
                        if (getPosATL _veh distance _pos > _radius) then {
                            _veh removeEventHandler [_thisEvent, _thisEventHandler];
                            _veh setVariable ["ITW_vehFiredEH",nil];
                        } else {
                            // let clients know vehicle has fired recently (use new variable so we aren't sending FiredTime on every firing)
                            if (time > (_veh getVariable ["ITW_vehFiredTime",0])) then {
                                _veh setVariable ["ITW_vehFiredRecently",true,true];
                            };
                            _veh setVariable ["ITW_vehFiredTime",time + 20];
                        };
                    }]; 
                    _veh getVariable ["ITW_vehFiredEH",_eh];
                };
                
                if (_veh getVariable ["ITW_vehFiredRecently",false] && {time > (_veh getVariable ["ITW_vehFiredTime",0])}) then {
                    _veh setVariable ["ITW_vehFiredRecently",false,true];
                };
                
                if !(_veh getVariable ["ITW_vehServicing",false]) then {
                    private _fuel = fuel _veh;
                    private _damage = damage _veh;
                    private _ammo = 1;
                    private _mags = createHashMap;
                    { 
                        _x params ["_classname","_tpath","_ammoCnt"];
                        private _ammoFull = getNumber (configFile >> "CfgMagazines" >> _classname >> "count");
                        if (_classname in _mags) then {
                            _mags get _classname params ["_cnt","_full"];
                            _mags set [_classname,[_ammoCnt+_cnt,_ammoFull+_full]];
                        } else {
                            _mags set [_classname,[_ammoCnt,_ammoFull]];
                        };
                    } forEach magazinesAllTurrets _veh;
                    {
                        _y params ["_cnt","_max"];
                        if (_max > 0) then {
                            private _thisRatio = _cnt/_max;
                            if (_thisRatio < _ammo) then {
                                _ammo = _thisRatio;
                            };
                        };
                    } forEach _mags;
                    
                    if (_fuel < 0.9 || _ammo < 1 || _damage > 0) then {
                        // needs servicing
                        if (!isEngineOn _veh) then {
                            if (time > _veh getVariable ["ITW_vehServiceTime",0] && {time > _veh getVariable ["ITW_vehFiredTime",0]}) then {
                                _veh setVariable ["ITW_vehServicing",true];
                                [_veh, _fuel,_ammo,_damage] remoteExec ["ITW_vehRepairExecute",0];
                            } else {
                                private _hintTime = _veh getVariable ["ITW_repairWaitHintTime",0];
                                if (_hintTime < time && {(getPosATL _veh)#2 < (_pos#2 + 4)}) then {
                                    private _msgId = if (time <= _veh getVariable ["ITW_vehFiredTime",0]) then {1} else {0};
                                    private _vehPlayers = allPlayers select {vehicle _x == _veh};
                                    [_veh,_msgId] remoteExec ["ITW_vehRepairMsg",_vehPlayers];
                                    _veh setVariable ["ITW_repairWaitHintTime",time + 21];
                                };
                            };
                        } else {
                            if (_veh getVariable ["ITW_repairHintTime",0] < time && {(getPosATL _veh)#2 < (_pos#2 + 4)}) then {
                                private _vehPlayers = allPlayers select {vehicle _x == _veh};
                                [3,_veh] remoteExec ["ITW_VehRepairSoundMP",_vehPlayers];
                                _veh setVariable ["ITW_repairHintTime",time + 30];
                            };
                        };
                    };
                };
            } forEach (_allVehicles select {_x distance2D _pos < _radius});
        } forEach _vehRepairArray;
    };
    ITW_VehRepairRunning = nil;
};

ITW_vehRepairMsg = {
    // call on all clients who will receive the message
    params ["_veh","_msgId"];
    private _msg = if (_msgId == 0) then {"STR_ITW_VEH_ServicingTooSoon"} else {"STR_ITW_VEH_ServicingFired"};
    _veh vehicleChat localize _msg;
};

ITW_vehRepairExecute = {
    // run on all clients 
    params ["_veh","_fuel","_ammo","_damage"];
    #define FILL_PER_CYCLE 0.10
    #define CYCLE_TIME     2.7
    private _cancelled = false;
    private _startPercent = _fuel min _ammo min (1 - _damage);
    _startPercent = floor (_startPercent*10)/10; // round to 0.1
    _veh getVariable ["ITW_vehServCancel",[0,0]] params ["_continueTime","_continuePercent"];
    if (time < _continueTime) then {_startPercent = _continuePercent};
    for "_i" from _startPercent to 0.99999 step FILL_PER_CYCLE do {
        [0,_veh] call ITW_VehRepairSoundMP;
        _veh vehicleChat format ["%1 %2%3",localize "STR_ITW_VEH_Servicing",_i * 100,"%"];
        [_veh,_i max _fuel, _i max _ammo max 0.75, (1-_i) min _damage] call ITW_VehRepairMP;
        sleep CYCLE_TIME;
        if (isEngineOn _veh || {_veh getVariable ["ITW_vehFiredRecently",false]}) exitWith {
            _veh vehicleChat format ["%1 %2%3",localize "STR_ITW_VEH_ServicingCanceled",_i*100,"%"];
            _veh setVariable ["ITW_vehServCancel",[time+20,_i]];
            _cancelled = true;
        };
    };
    if (_cancelled) then {
        if (isServer) then {_veh setVariable ["ITW_vehServiceTime",nil]};
    } else {
        [_veh,1,1,0] call ITW_VehRepairMP;
        [1,_veh] call ITW_VehRepairSoundMP;
        sleep 1;
        _veh vehicleChat (localize "STR_ITW_VEH_Servicing" + " 100%");
        sleep 1;
        [2,_veh] call ITW_VehRepairSoundMP;
        // ensure vehicle has a toolkit in inventory
        if !("ToolKit" in (getItemCargo _veh#0)) then {
            _veh addItemCargoGlobal ["ToolKit",1];
        };
        if (isServer) then {_veh setVariable ["ITW_vehServiceTime",time + 60]};
    };
    if (isServer) then {_veh setVariable ["ITW_vehServicing",nil]};
};

ITW_VehRepairMP = {
    // call on all clients where vehicle or a turret is local
    params ["_veh","_fuel","_ammo","_damage"];                         
    if (local _veh) then {
        _veh setFuel _fuel;
        _veh setDamage _damage;
    };
    
    // if I set ammo to anything less than 100%, it will not refill reloads in the vehicle
    // setVehicleAmmoDef will reload the refils, but will remove any pylons.
    // So just don't show ammo filling up and it works
    if (_ammo == 1) then {
        _veh setVehicleAmmo _ammo; // must run where each turret is local, so do it everywhere
    };
};

ITW_VehRepairSoundMP = {
    // call on each client that should hear sound
    params ["_which","_veh"];
    if (!hasInterface) exitWith {};
    if (vehicle player != _veh) exitWith {};
    private _startOffset = 0;
    private _duration = -1;
    private "_sound";
    switch (_which) do {
        case 0: {
            _sound = "A3\Sounds_F\sfx\objects\upload_terminal\Terminal_antena_close.wss";
            _startOffset = 0.2;
        };  
        case 1: {
            _sound = "A3\Sounds_F\sfx\objects\upload_terminal\Terminal_antena_open.wss";
        };
        case 2: {
            _veh vehicleChat localize "STR_ITW_VEH_GoodToGo";
            _sound = "A3\Dubbing_F_oldman\oldman1\017_eve_mechanic_car_ready_b\oldman1_017_eve_mechanic_car_ready_b_MECHANIC_0_Processed.ogg"
        };
        case 3: {
            _veh vehicleChat localize "STR_ITW_VEH_PowerDown";
            _sound = "A3\dubbing_f_bootcamp\boot_m01\d20_Shutdown\boot_m01_d20_shutdown_ADA_2.ogg";
            _startOffset = 1.6;
            _duration = 0.55;
        };
    };  
    private _sndId = playSound3D [_sound, player, true, getPosASL player, 10, 1, 20, _startOffset, true];
    if (_duration > 0) then {
        waitUntil {
            private _sndparams = soundParams _sndId;
            _sndparams isEqualTo [] || {_sndparams#1 >= _duration}
        };
        stopSound _sndId;
    };
};

["ITW_vehRepairPoint"] call SKL_fnc_CompileFinal;
["ITW_vehRepairPointRemove"] call SKL_fnc_CompileFinal;
["ITW_vehRepairExecute"] call SKL_fnc_CompileFinal;
["ITW_vehRepairTask"] call SKL_fnc_CompileFinal;
["ITW_VehRepairSoundMP"] call SKL_fnc_CompileFinal;
["ITW_VehRepairMP"] call SKL_fnc_CompileFinal;
["ITW_vehRepairMsg"] call SKL_fnc_CompileFinal;