
Gear_GetArray = {
    // returns array of classnames or nil if empty
    //
    // Params:
    // _types: is string array of type of gear.  Is not case sensative. Can be one of:
    //   smallBackpacks, largeBackpacks      // backpacks by size
    //   weaponBackpacks                     // uav bags, static mg bags, static launchers, scuba, etc
    //   lowArmor, mediumArmor, heavyArmor   // vests, helmets by amount of armor they provide
    
    private _types = _this;
    
    for "_i" from 0 to (count _types - 1) do {
        _types set [_i,toLowerANSI (_types#_i)];
    };
    
    private _return = [];
    private _fullGearArray = Gear_GearArray;
    private _weapons = [];
    if (!isNil "_fullGearArray") then {
        if (typeName _fullGearArray == "ARRAY") then {
            if (count _fullGearArray > 0) then {
                {
                    scopeName "getWeaponsArray";
                    if (!isNil "_x") then {
                        private _gearArrayEntry = _x;
                        private _gearArrayIdentifier = _gearArrayEntry select 0;
                        private _gearArray = _gearArrayEntry select 1;

                        if (_gearArrayIdentifier in _types) then {
                            _return = _return + _gearArray;
                        };
                    };
                } forEach _fullGearArray;
            };
        };
    };
    if (_return isEqualTo []) exitWith {};
    _return
};

Gear_InitArray = {
    // Parmas:
    // _customDLC: list of DLCs to use exclusively or [] to include all weapons (ex  ["gm"])
    params ["_customDLCs",["_removeDLCs",[]]];
    
    if (isNil "Gear_GearArray") then {Gear_GearArray = [];};
    if (count Gear_GearArray == 0) then {
            
        private _smallBackpacks = [];
        private _largeBackpacks = [];
        private _wepaonBackpacks = [];
        private _lowArmor = [];
        private _mediumArmor = [];
        private _heavyArmor = [];
                 
        private _armor = objNull;
        private _vest = [];
        private _headgear = [];
        private _backpack = objNull;
        
        private _cfg = (configFile >> "CfgWeapons");
        for "_i" from 0 to ((count _cfg)-1) do {
            if (isClass ((_cfg select _i) )) then {
                private _cfgName = configName (_cfg select _i);
                _armor = (configFile >> "CfgWeapons" >> _cfgName >> "ItemInfo" >> "HitpointsProtectionInfo");
                if (! isNull _armor) then {
                    private _dlc = configSourceMod (configFile >> "CfgWeapons" >> _cfgName);
                    if (!(_dlc in _removeDLCs) AND ((count _customDLCs == 0) OR (_dlc in _customDLCs))) then {
                        private _hpClasses = (_armor call BIS_fnc_getCfgSubClasses);
                        private _value = 0;
                        { 
                            _value = _value + (getNumber (configFile >> "CfgWeapons" >> _cfgName >> "ItemInfo" >> "HitpointsProtectionInfo" >> _x >> "armor"));
                        } forEach _hpClasses;
                        
                        // I ran a test: (armor value: number in base game)
                        // Headgear        Vests
                        //  0: 130            0: 45
                        //  2:  21           24: 11
                        //  4:  12           36: 10
                        //  6:  30           48: 15
                        //  7:   2           60:  7
                        //  8:  21           64:  1
                        // 10:  24           72:  3
                        // 12:   7           88:  5
                        // 20:   2          204: 12
                        
                        if ("Head" in _hpClasses) then {
                            switch (true) do {
                                case (_value <= 0): { _lowArmor pushBack _cfgName; };
                                case (_value < 10):  { _mediumArmor pushBack _cfgName; };
                                default  { _heavyArmor pushBack _cfgName; };
                            };
                        } else {
                            switch (true) do {
                                case (_value <= 0): { _lowArmor pushBack _cfgName; };
                                case (_value < 50):  { _mediumArmor pushBack _cfgName; };
                                default  { _heavyArmor pushBack _cfgName; };
                            };
                        };
                    };
                };
            };
        };
        
        _cfg = (configFile >> "CfgVehicles");
        for "_i" from 0 to ((count _cfg)-1) do {
            if (isClass ((_cfg select _i) )) then {
                private _cfgName = configName (_cfg select _i);                
                if ((getText (configFile >> "CfgVehicles" >> _cfgName >> "vehicleClass")) == "Backpacks") then { 
                    private _dlc = getText (configFile >> "CfgWeapons" >> _cfgName >> "DLC");
                    if (_dlc == "") then {
                        _dlc = getNumber (configFile >> "CfgWeapons" >> _cfgName >> "appid");
                        if (_dlc == 0) then {
                            _dlc = getText (configFile >> "CfgWeapons" >> _cfgName >> "author");
                        };
                    };                 
                    if (!(_dlc in _removeDLCs) AND ((count _customDLCs == 0) OR (_dlc in _customDLCs))) then {
                        private _maxLoad = getNumber (configFile >> "CfgVehicles" >> _cfgName >> "maximumLoad");
                        // I ran a test: (max load: number in base game)
                        //   0 128  -- these are uav, static mgs, static launchers, scuba, etc
                        //  20   2
                        //  80  19
                        // 120   5
                        // 140   9
                        // 160  44
                        // 200  61
                        // 240  30
                        // 260   6
                        // 280  34
                        // 300  18
                        // 320  74                  
                        switch (true) do {
                            case (_maxLoad <= 0):  { _wepaonBackpacks pushBack _cfgName; };
                            case (_maxLoad < 160): { _smallBackpacks pushBack _cfgName; };
                            default  { _largeBackpacks pushBack _cfgName; };
                        };
                    };
                };
            };
        };            
        Gear_GearArray = [["lowArmor", _lowArmor], ["mediumArmor", _mediumArmor], ["heavyArmor", _heavyArmor], ["smallBackpacks", _smallBackpacks], ["largeBackpacks", _largeBackpacks],["wepaonBackpacks",_wepaonBackpacks]];
        
        {
            _x set [0,toLowerANSI (_x#0)];
        } forEach Gear_GearArray;
    };
};

["Gear_GetArray"] call SKL_fnc_CompileFinal;
["Gear_InitArray"] call SKL_fnc_CompileFinal;
