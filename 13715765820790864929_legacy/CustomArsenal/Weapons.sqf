
Weapons_GetArray = {
    // returns array of [gunCfgName, magazinesArray, _secondaryMags] 
    // except for 'weapons' which returns array of config names
    //
    // Params:
    // _weaponArrayIds: is string array of type of weapons requested.  Can be one of:
    //   pistols
    //   lowrifles, mediumrifles, highrifles             - rifles by damage dealt per shot (caliber)
    //   lowlaunchers, highlaunchers                     - launchers by damage dealt per shot
    //   smallMagRifles, mediumMagRifles, largeMagRifles - rifles by magazine size, mostly (sniper rifles, assault rifles, MGs)
    //   weaponarrays                                    - all weapons
    //   weapons                                         - all weapon class names
    
    private _weaponArrayIds = _this;
    
    private _return = [];
    private _weaponsArray = Weapons_WepaonsArray;
    private _weapons = [];
    if (!isNil "_weaponsArray") then {
        if (typeName _weaponsArray == "ARRAY") then {
            if (count _weaponsArray > 0) then {
                {
                    scopeName "getWeaponsArray";
                    if (!isNil "_x") then {
                        private _weaponsArrayEntry = _x;
                        private _weaponsArrayIdentifier = _weaponsArrayEntry select 0;
                        private _weaponArray = _weaponsArrayEntry select 1;

                        if (_weaponsArrayIdentifier in _weaponArrayIds) then {
                            _return = _return + _weaponArray;
                        };
                    };
                } forEach _weaponsArray;
            };
        };
    };
    if (_return isEqualTo [] && "pistols" in _weaponArrayIds) then {
        // some of the custom DLC don't include pistols, on those, just use some base Altis pistols
        _return = [["hgun_ACPC2_F",["9Rnd_45ACP_Mag"],[]],["hgun_ACPC2_snds_F",["9Rnd_45ACP_Mag"],[]],["hgun_P07_F",["16Rnd_9x21_Mag","16Rnd_9x21_red_Mag","16Rnd_9x21_green_Mag","16Rnd_9x21_yellow_Mag","30Rnd_9x21_Mag","30Rnd_9x21_Red_Mag","30Rnd_9x21_Yellow_Mag","30Rnd_9x21_Green_Mag"],[]],["hgun_P07_snds_F",["16Rnd_9x21_Mag","16Rnd_9x21_red_Mag","16Rnd_9x21_green_Mag","16Rnd_9x21_yellow_Mag","30Rnd_9x21_Mag","30Rnd_9x21_Red_Mag","30Rnd_9x21_Yellow_Mag","30Rnd_9x21_Green_Mag"],[]],["hgun_Rook40_F",["16Rnd_9x21_Mag","16Rnd_9x21_red_Mag","16Rnd_9x21_green_Mag","16Rnd_9x21_yellow_Mag","30Rnd_9x21_Mag","30Rnd_9x21_Red_Mag","30Rnd_9x21_Yellow_Mag","30Rnd_9x21_Green_Mag"],[]],["hgun_Rook40_snds_F",["16Rnd_9x21_Mag","16Rnd_9x21_red_Mag","16Rnd_9x21_green_Mag","16Rnd_9x21_yellow_Mag","30Rnd_9x21_Mag","30Rnd_9x21_Red_Mag","30Rnd_9x21_Yellow_Mag","30Rnd_9x21_Green_Mag"],[]]];
    };
    if (_return isEqualTo []) exitWith {};
    _return
};

Weapons_InitArray = {
    // Parmas:
    // _customDLC: list of DLCs to use exclusively or [] to include all weapons (ex  ["gm"])
    params ["_dlcFilter"];
    _dlcFilter params [["_customDLCs",[]],["_removeDLCs",[]]];
    
    if (isNil "Weapons_WepaonsArray") then {Weapons_WepaonsArray = [];};
    if (count Weapons_WepaonsArray == 0) then {            
        private _pistols = [];
        private _lowrifles = [];
        private _medrifles = [];
        private _highrifles = [];
        private _lowlaunchers = [];
        private _highlaunchers = [];
        
        private _smallMagRifles = [];  // <= 15 rounds (sniper rifles)
        private _mediumMagRifles = []; // 16 - 50 rounds
        private _largeMagRifles = []; // > 50 rounds (MGs)
        
        private _allweapons = [];
        private _allweaponarrays = [];
       
        private _cfg = (configFile >> "CfgWeapons");
        for "_i" from 0 to ((count _cfg)-1) do {
            if (isClass ((_cfg select _i) )) then {
                private _cfgName = configName (_cfg select _i);
                private _gettype = getNumber (configFile >> "CfgWeapons" >> _cfgName >> "type");
                private _magazines = getArray (configFile >> "CfgWeapons" >> _cfgName >> "magazines");
                private _dlc = configSourceMod (configFile >> "CfgWeapons" >> _cfgName);
                if ((_gettype <= 4 AND _gettype > 0) AND (getNumber ((_cfg select _i) >> "scope") == 2) AND (count _magazines != 0) AND 
                    !(_dlc in _removeDLCs) AND ((count _customDLCs == 0) OR (_dlc in _customDLCs))) then {
                    private _secondaryMags = [];
                    {
                        _secondaryMags = _secondaryMags + getArray (_x  >> 'magazines');
                    } forEach (configProperties [(configFile >> "CfgWeapons" >> _cfgName),"isClass _x && {count getArray (_x  >> 'magazines') > 0}"]);                     
                    private _magazine = _magazines select 0;
                    private _ammo = getText (configFile >> "CfgMagazines" >> _magazine >> "ammo");
                    private _hitValue = getNumber (configFile >> "CfgAmmo" >> _ammo >> "hit");
                    private _magCount = getNumber (configFile >> "CfgMagazines" >> _magazine >> "count");
                    
                    if (_hitValue > 1) then {
                        private _weaponArray = [_cfgName, _magazines, _secondaryMags];
     
                        _allweapons pushBack _cfgName;
                        _allweaponarrays pushBack _weaponArray;
     
                        if (_gettype == 2) then {
                            _pistols pushBack _weaponArray;
                        };
     
                        if (_gettype == 1) then {
                            if (_hitValue < 10) then {
                                _lowrifles pushBack _weaponArray;
                            };
     
                            if (_hitValue >= 10 AND _hitValue < 12) then {
                                _medrifles pushBack _weaponArray;
                            };
     
                            if (_hitValue >= 12) then {
                                _highrifles pushBack _weaponArray;
                            };
                           
                            if (_magCount < 16) then {
                                _smallMagRifles pushBack _weaponArray;
                            };
     
                            if (_magCount >= 16 AND _magCount <= 50) then {
                                _mediumMagRifles pushBack _weaponArray;
                            };
     
                            if (_magCount > 50) then {
                                _largeMagRifles pushBack _weaponArray;
                            };
                        };
     
                        _getlock = getnumber (configfile >> "CfgWeapons" >> _cfgName >> "canLock");
     
                        if (_gettype == 4 AND _getlock < 2) then {
                            _lowlaunchers pushBack _weaponArray;
                        };
     
                        if (_gettype == 4 AND _getlock == 2) then {
                            _highlaunchers pushBack _weaponArray;
                        };
                    };
                };
            };
        };
        _weaponsArray = [["pistols", _pistols], ["lowrifles", _lowrifles], ["mediumrifles", _medrifles], ["highrifles", _highrifles], ["lowlaunchers", _lowlaunchers], ["highlaunchers", _highlaunchers], ["smallMagRifles", _smallMagRifles], ["mediumMagRifles",_mediumMagRifles],["largeMagRifles",_largeMagRifles],["weapons", _allweapons],["weaponarrays", _allweaponarrays]];
        Weapons_WepaonsArray = _weaponsArray;
    };
};

["Weapons_GetArray"] call SKL_fnc_CompileFinal;
["Weapons_InitArray"] call SKL_fnc_CompileFinal;
