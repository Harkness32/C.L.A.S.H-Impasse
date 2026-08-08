// SKL_FhMz.sqf   
//
// [type, size, numUnits, trigger, side(optional), skill(optional), cacheable (optional), init(optional)] call SKL_FH_MZ
//
// in init.sqf:       SKL_FH_MZ = compileFinal preprocessFileLineNumbers "scripts\SKL_FhMz.sqf";
// in trigger on act: ["MZ", 300, count playableUnits, thisTrigger] call SKL_FH_MZ
// in trigger on act: ["MZ", [100,300], count playableUnits, thisTrigger] call SKL_FH_MZ
// in trigger on act: [["MI","T"], 300, count playableUnits, thisTrigger] call SKL_FH_MZ
// in trigger on act: [["MZ","T","UR","Marker"], 300, count playableUnits, thisTrigger] call SKL_FH_MZ
// in trigger on act: ["FHG", 300, count playableUnits, thisTrigger] call SKL_FH_MZ
//
// type: either a single item (string) or an array containing items. [mainType, optional option, optional upsmon type, optional marker]  
// The array must have one main item, can have one customization, and can have one upsmon.  
// If the upsmon is there, it can be followed by a marker.
// So the following are valid arrays: ["FH"]  ["FH","U"]  ["FH,"T"]  ["FH","T","U"]  ["FH","U","marker"]  ["FH","T","U","marker"] 
//
//          "FH"     - fillHouse (patrol in and out buildings)
//          "FHI"    - fillHouse patrol inside only
//          "FHG"    - fillHouse garrison (uses UPSMON script, same as ["FHI","UF"])
//          "MZ"     - militarize with infantry and vehicles 
//          "MZI"    - militarize with infantry 
//          "MZV"    - militarize with vehicles
//          "MZA"    - militarize with air vehicles
//          "MZB"    - militarize with boats
//          "MZD"    - militarize with divers
//          "MZO"    - militarize Ocean - divers and boats
//          "MZVS"   - militarize with vehicles stationary (don't patrol)
//          "MZBS"   - militarize with boats stationary (don't patrol)
//      FH and MZ types can be combined with an underscore:
//          "FH_MZI" - both fillHouse and Militarize with infantry
//          "FH_MZV" - both fillHouse and militarize with vehicles
//          "FHI_MZ" - fillHouse inside only and militarize with infantry and vehicles 
//
//      Customization
//          "C script" - dress the units in custom type clothing (next item should be script)
//                       as in ["FH","C call ChangeClothes"] or ["FH","C execVM ChangeDress.sqf"] 
//                       an array of units will be passed to the script (ie  [unit1,unit2] call ChangeClothes) 
//          "G#"     - groups of size # (G1, G2, G10 are 1, 2, or 10 units per group respectively), default is 8
//
//      UPSMON: to use UPSMON, type should be an array of type and upsmon options
//          "U"      - upsmon safe
//			"UA"	 - upsmon aware
//          "US"     - upsmon stealth
//          "UF"     - upsmon fortify
//          "UR"     - upsmon on roads safe
//          "URA"     - upsmon on roads aware
//      If UPSMON is specified using an array, you can add an optional marker to the array for the UPSMON patrol area
//
// size:  The spawn radius in meters.  
//          Can be an single size or array of two sizes.  First is spawn size, the second is patrol size.
//
// count: Number of player units to scale for.  
//          For all players: count playableUnits
//          For the group entering the trigger: count units group (thisList select 0)
//          If count is negative, it indicates to use that exact count.  So a MZV of -2 means spawn 2 vehicles exactly.
//
// trigger: the trigger which indicates radius and center point (usually  thisTrigger)
//          can also be an array [ center, size ] ie.  [ [125,552,1],200]
//
// side:    Optional argument EAST, WEST, RESISTANCE, CIVILIAN (default will be EAST (_SKL_FhMz_enemySide below))
//          can also be string of the above (ie. "East", ...)
//          or a number: (0 = civilian, 1 = blue (NATO), 2 = red (CSAT), 3 = green (AAF)) 								
//                       (1.1 = blue FIA, 2.1 = red FIA, 3.1 = green FIA, 3.2 = green paramilitary, 3.3 = green bandits)
//
// skill:   number from 0 to 1 (or "default")
//
// cacheable: true(default) will despawn units if player gets too far away and respawn when they get close, false will not ever cache the units
//
// init:    the code(string) to run on each unit after it's created.  _this is the unit.
//
// spawnPos: the position to spawn the unit, if [] or not supplied, unit will spawn at an appropriate position in the zone
//
// LV dir:  the location of the LV directory (default is "scripts\LV")

//diag_log format ["SKL_FhMz: %1",_this];

// Check for headless client
if (isNil "HCPresent") then {HCPresent=false};
if (HCPresent) then { // test if HC errored out
    if (isNil "HCName") then {HCName="NOONE"};
    _foundHC = false;
    {
        if (name _x == HCName) exitWith {_foundHC = true;};
    } forEach playableUnits;
    if (!_foundHC) then {HCPresent=false};
};

if ((HCPresent && !hasInterface && !isServer) || (!HCPresent && isServer)) then {
    _this spawn {
    
        params ["_typeArray","_sizeSpawn","_countPlayers","_trig",
                ["_enemySide",2],["_defaultSkillLevel",-1],["_cacheable",true],["_initScript",""],
                ["_spawnPos",[]],["_lvDir","scripts\LV"]];
        
        if (isNil "FHMZ_DONE") then { FHMZ_DONE = 0; }; // it will count as it completes
        
        FHMZ_OptionsArray = ["C","N","G"]; 
        
        // the density of units spawned and is scaled by count argument (enter number for 10 players over 200 m radius)
        _SKL_FhMz_scaleUnitsPer4SqKM = 30;
        // the density of units spawned and is scaled by count argument
        _SKL_FhMz_scaleVehPer4SqKM   =  1;
        // the random percentage.  Spawn will be the number plus up to this percentage of the total
        _SKL_FhMz_randomPercent      = 20;
        // the enemy side to spawn in (west=1, east=2, independent=3)
        _SKL_FhMz_enemySide          =  _enemySide;
        // split into squads of this size or smaller
        _SKL_FhMz_maxSquadSize       = 8;
        // the default enemy skill level 0 to 1 or -1 for "default"
        _SKL_FhMz_defaultSkillLevel  = _defaultSkillLevel;
         
        _SKL_FhMz_scaleUnitsPer4SqKM = ["FHMZ_PARAM_UNITS_P4K",_SKL_FhMz_scaleUnitsPer4SqKM] call BIS_fnc_getParamValue;
        _SKL_FhMz_scaleVehPer4SqKM = ["FHMZ_PARAM_VEHCILES_P4K",_SKL_FhMz_scaleVehPer4SqKM] call BIS_fnc_getParamValue;
        _SKL_FhMz_randomPercent = ["FHMZ_PARAM_RANDOM_PERCENTAGE",_SKL_FhMz_randomPercent] call BIS_fnc_getParamValue;
        _SKL_FhMz_defaultSkillLevel = ["FHMZ_PARAM_AI_SKILL",_SKL_FhMz_defaultSkillLevel] call BIS_fnc_getParamValue;
        _SKL_FhMz_maxSquadSize = ["FHMZ_PARAM_SQUAD_SIZE",_SKL_FhMz_maxSquadSize] call BIS_fnc_getParamValue;
        
       if (_SKL_FhMz_defaultSkillLevel == -1) then {_SKL_FhMz_defaultSkillLevel = "default"};
 
        if (isNil "SKL_FH_MZ_CNTR") then { SKL_FH_MZ_CNTR = 0; };
        _fh_mz_cntr = SKL_FH_MZ_CNTR;
        SKL_FH_MZ_CNTR = SKL_FH_MZ_CNTR + 100;
        
        //diag_log format ["SKL_FH_MZ %1 (%2,%3,%4,%4)",_this,_SKL_FhMz_scaleUnitsPer4SqKM,_SKL_FhMz_scaleVehPer4SqKM,_SKL_FhMz_randomPercent,_SKL_FhMz_defaultSkillLevel];

        private _type = _typeArray;
        _upsmonType = "";
        _upsmonMarker = "";
        _option = "";
        if (typeName _typeArray == "ARRAY") then
        {
            private "_index";
            _type = _typeArray select 0;
            if (count _typeArray > 1) then
            {
                _index = 1;
                if (((_typeArray select 1) select [0,1]) in FHMZ_OptionsArray) then 
                {
                    // an option was included
                    _index = 2;
                    _option = _typeArray select 1;
                };
                if (count _typeArray > _index) then
                {
                    _upsmonType = _typeArray select _index;
                    if (count _typeArray > _index+1) then
                    {
                        _upsmonMarker = _typeArray select (_index + 1);
                        _upsmonMarker setMarkerAlpha 0;
                    };
                };
            };
        };
        
        _sizeSpawn = _sizeSpawn;
        _sizePatrol = _sizeSpawn;
        if (typeName (_sizeSpawn) == "ARRAY") then
        {
            _sizePatrol = _sizeSpawn select 1;
            _sizeSpawn = _sizeSpawn select 0;
        };
        
        _trigPos = [0,0,0];
        _trigSize = 500;
        if (typeName _trig == "ARRAY") then 
        {
            _trigPos = _trig select 0;
            _trigSize = _trig select 1;
        }
        else
        {
            _trigPos = getPosATL _trig;
            _trigSize = (((triggerArea _trig) select 0) + ((triggerArea _trig) select 1))/2;
        };
        
        if (typeName _SKL_FhMz_enemySide == "STRING") then
        {
            _side = toUpper _SKL_FhMz_enemySide;
            switch (_side) do
            {
                case "EAST":       {_side = EAST};
                case "WEST":       {_side = WEST};
                case "RESISTANCE": {_side = RESISTANCE};
                case "CIVILIAN":   {_side = CIVILIAN};
                default            {_side = EAST};
            };
        };
        if (typeName _SKL_FhMz_enemySide == "SIDE") then {
            switch (_SKL_FhMz_enemySide) do
            {
                case EAST:       {_SKL_FhMz_enemySide = 2};
                case WEST:       {_SKL_FhMz_enemySide = 1};
                case RESISTANCE: {_SKL_FhMz_enemySide = 3};
                case CIVILIAN:   {_SKL_FhMz_enemySide = 0};
                default          {_SKL_FhMz_enemySide = 2};
            };
        };
		
				
        private _len = count _initScript;
        if (_len > 2) then {
            if (_initScript select [_len - 1,1] != ";") then {
                _initScript = _initScript + ";";
            };
        };
		
               
        _units_F  = abs _countPlayers;
        _units_MI = abs _countPlayers;
        _units_MV = abs _countPlayers;
        if (_countPlayers >= 0) then
        {
            _units_F  = ceil (_countPlayers * (2*_sizeSpawn/100)^1.8 * _SKL_FhMz_scaleUnitsPer4SqKM/160);
            _units_MI = ceil (_countPlayers * (2*_sizeSpawn/100)^1.8 * _SKL_FhMz_scaleUnitsPer4SqKM/160);
            _units_MV = ceil (_countPlayers * (2*_sizeSpawn/100)^1.8 * _SKL_FhMz_scaleVehPer4SqKM  /160);
        };
        
        if (_sizeSpawn > 0 && _units_F == 0)  then {_units_F  = 1;};
        if (_sizeSpawn > 0 && _units_MI == 0) then {_units_MI = 1;};
        if (_sizeSpawn > 0 && _units_MV == 0) then {_units_MV = 1;};
        
        _mzInfantry = 0;
        _mzVehicle = 0;
        _mzBoats = 0;
        _fhInfantry = 0;
        _inside = 2;
        _ocean = false;
        _air = false;
        _patrol = true;
        _spawnOnly = false;
        _type = toUpper(_type);
        private _types = _type splitString "-_ "; // allow '-' '_' or ' ' to be used as delimiters
        {
            switch (_x) do
            {
                case "FH":     {_fhInfantry = _units_F;};
                case "FHI":    {_fhInfantry = _units_F; _inside = 1};
                case "MZI":    {_mzInfantry = _units_MI;};
                case "MZIS":   {_mzInfantry = _units_MI; _patrol = false;};
                case "MZA":    {_mzVehicle  = _units_MV;_air = true};
                case "MZV":    {_mzVehicle  = _units_MV;};
                case "MZVS":   {_mzVehicle  = _units_MV; _patrol = false;};
                case "MZ":     {_mzInfantry = _units_MI; _mzVehicle = _units_MV;};
                case "MZB":    {_mzVehicle  = _units_MV; _ocean = true};
                case "MZBS":   {_mzVehicle  = _units_MV; _ocean = true; _patrol = false;};
                case "MZD":    {_mzInfantry = _units_MV; _ocean = true};
                case "MZO":    {_mzInfantry = _units_MI; _mzVehicle = _units_MV; _ocean = true};
                case "FHG":    {_fhInfantry = _units_F; _inside = 1; _patrol = false; _spawnOnly = true;};
                default        {_s = format ["Error in SKL_FhMz: invalid type %1 at %2",
                                _type,_trigPos];hint _s; diag_log _s;};
            };
        } forEach _types;
//nul = [[100],[player],600,true,true] execVM "scripts\LV\LV_functions\LV_fnc_simpleCache.sqf";

//        if (_upsmonType != "") then
//        {
//            _spawnOnly = true;
//            _patrol = false;
//            _upsmonOptions = "'SPAWNED', 'SHOWMARKER', 'EXTERNAL_CACHE'";
//            switch (toUpper(_upsmonType)) do
//            {
//                case "U":   { _upsmonOptions = _upsmonOptions + ", 'NOWAIT', 'SAFE'"; };
//                case "UA":  { _upsmonOptions = _upsmonOptions + ", 'NOWAIT', 'AWARE'"; };
//                case "US":  { _upsmonOptions = _upsmonOptions + ", 'NOWAIT', 'STEALTH'"; };
//                case "UF":  { _upsmonOptions = _upsmonOptions + ", 'SAFE', 'FORTIFY', 'NOFOLLOW', 'RANDOMA', 'NOWP2', 'NOSMOKE'";}; 
//                case "UR":  { _upsmonOptions = _upsmonOptions + ", 'NOWAIT', 'SAFE', 'COLUMN', 'ONROAD'"; };
//				case "URA":  { _upsmonOptions = _upsmonOptions + ", 'NOWAIT', 'AWARE', 'ONROAD'"; };
//                default     {_s = format ["Error in SKL_FhMz: invalid upsmon type %1 at %2",
//                            _upsmonType, _trigPos];hint _s; diag_log _s;};  
//            };
//            if (_upsmonMarker == "") then { _upsmonMarker = _mkr; };
//            if (isNil "FHMZ_UPSMON") then { FHMZ_UPSMON = compileFinal preprocessFileLineNumbers 'scripts\UPSMON\UPSMON.sqf';};
//            _initScript = format ["if (_this == (leader (group _this))) then {  [ _this, '%1', %2] call FHMZ_UPSMON;};",_upsmonMarker,_upsmonOptions]; 
////{_x doMove getPosATL _x; _x forceSpeed 1; } foreach units group _this; while {count units group _this != {unitReady _x} count units group _this} do {sleep 0.2;};            
//        };
        // handle old method of NG (no group) or N2 for 2 per group
        if (toUpper _option == "NG") then {_option = "G1";};
        if (toUpper _option == "N2") then {_option = "G2";};
        
        switch (toUpper(_option select [0,1])) do
        { 
            // All options here must appear in FHMZ_OptionsArray above as well
            case "C": { 
                        private _script = _option select [1];
                        _initScript = _initScript + "[_this] " + _script; };
            case "G": {
                        // Units per group G1 = 1 person per group, G2 = 2 per group, ...
                        _SKL_FhMz_maxSquadSize = 1; 
                        _SKL_FhMz_randomPercent = 0; 
                        if (count _option > 1) then {
                            _num = parseNumber (_option select [1]); 
                            if (_num > 1) then {
                                _SKL_FhMz_maxSquadSize = _num; 
                            };
                        };
                      };
        };
        //diag_log format ["SKL_FH_MZ mzI %1, mzV %2, mzB %3, fhI %4, squad_size %5",_mzInfantry,_mzVehicle,_mzBoats,_fhInfantry,_SKL_FhMz_maxSquadSize];
        
        if (isNil "FHMZ_SIMPLECACHE") then { FHMZ_SIMPLECACHE = compileFinal preProcessFileLineNumbers (_lvDir + "\LV_functions\LV_fnc_simpleCache.sqf"); };
        
        _loop = 1;
        _sleepTime = _SKL_FhMz_maxSquadSize * 0.1;
        
        if (_mzInfantry>0 || _mzVehicle>0 ) then
        {
            while {(_mzInfantry>0) || (_mzVehicle>0)} do
            {      
                if (isNil "FHMZ_MILITARIZE") then { FHMZ_MILITARIZE = compileFinal preProcessFileLineNumbers (_lvDir + "\militarize.sqf"); };
                _squad = _mzInfantry Min _SKL_FhMz_maxSquadSize;
                [_trigPos, _SKL_FhMz_enemySide, _sizePatrol, [_squad>0 && !_ocean,_squad>0 && _ocean], [_mzVehicle>0 && !_ocean && !_air,_mzVehicle>0 && _ocean,_air], !_patrol, [_squad,round (_squad * _SKL_FhMz_randomPercent/100)], [_mzVehicle,round (_mzVehicle * _SKL_FhMz_randomPercent/100)], _SKL_FhMz_defaultSkillLevel, nil, _initScript, _fh_mz_cntr, _spawnOnly, _spawnPos] call FHMZ_MILITARIZE;
                                
                if (_cacheable) then //_upsmonType == "") then 
                {
                    [[_fh_mz_cntr], playableUnits, _trigSize, true, true] spawn FHMZ_SIMPLECACHE; 
                };
                
                _fh_mz_cntr = _fh_mz_cntr + 1;
                
                _mzVehicle = 0;
                _mzInfantry = _mzInfantry - _SKL_FhMz_maxSquadSize;
                
                if (_sleepTime >= 0.5) then {sleep _sleepTime;};
            //if (_initScript != "") then {sleep _SKL_FhMz_maxSquadSize};
            };
        };
        
        while {_fhInfantry > 0} do
        {
            if (isNil "FHMZ_FILLHOUSE") then { FHMZ_FILLHOUSE = compileFinal preProcessFileLineNumbers (_lvDir + "\fillHouse.sqf"); };
            _squad = _fhInfantry Min _SKL_FhMz_maxSquadSize;
            [_trigPos, _SKL_FhMz_enemySide, _patrol, _inside, [_squad,round (_squad * _SKL_FhMz_randomPercent/100)], _sizePatrol, _SKL_FhMz_defaultSkillLevel, nil, _initScript, _fh_mz_cntr, _spawnOnly, _spawnPos] call FHMZ_FILLHOUSE;
                        
            if (_cacheable) then //_upsmonType == "") then 
            {
                [[_fh_mz_cntr],playableUnits,_trigSize,true,true] spawn FHMZ_SIMPLECACHE;
            };
            
            _fh_mz_cntr = _fh_mz_cntr + 1;
            
            _fhInfantry = _fhInfantry - _SKL_FhMz_maxSquadSize;
            
            if (_sleepTime >= 0.5) then {sleep _sleepTime;};
            //if (_initScript != "") then {sleep _SKL_FhMz_maxSquadSize};
        };
        FHMZ_DONE = FHMZ_DONE + 1;
    };
};

    