
params ["_enemyFaction",["_playerFaction","ALL_NON_ENEMY_FACTIONS"],["_options",[]]];

private _playerFactionIsAllNonEnemy = false;
if (_playerFaction isEqualTo "ALL_NON_ENEMY_FACTIONS") then {_playerFaction = ["BLU_F","CIV_F"];_playerFactionIsAllNonEnemy=true};
// VEHICLE_ARRAYS_COMPLETE will be true upon completion
diag_log "Vehicle Arrays Processing Started";

private _validOptions = [
    "EnsureQuadBike",     // ensure quadbike array is not empty
    "EnsureCarTransport", // ensure EnsureCarTransport is not empty
    "EnsureSupports",     // ensure ammoClasses, fuelClasses, and repairClasses is not empty
    "EnsureBoats",        // ensure at least one boat type
    "NoTrucks"            // remove large trucks from the carClasses & carTransportClasses
];

{
    private _opt = _x;
    if !(_opt in _validOptions) then {
        private _found = "";
        private _optLower = toLowerANSI _opt;
        {
            if (_optLower == toLowerANSI _x) exitWith {
                _found = _x;
            };
        } forEach _validOptions;
        if (_found isEqualTo "") then {
            private _msg = format ["ERROR: VehiclesArrays.sqf: invalid option %1",_opt];
            diag_log _msg;
            [_msg,"ERROR"] call BIS_fnc_guiMessage;
        } else {
            _options set [_forEachIndex,_found];
        };
    };
} forEach _options;

#define MIN_CARGO_SEATS_FOR_TRANSPORT 6
#define MIN_ABS_CARGO_SEATS_FOR_TRANSPORT 4

//va_airports = [];  //airports array in form [ilsPosition,ilsDirection,ilsTaxiOff,ilsTaxiIn] (see Arma_3_Dynamic_Airport_Configuration)

// Car, Heli, Tank, Apc, Plane all are subdivided into
//  va_pXxxxClassesAttack
//  va_pXxxxClassesTransport
//  va_pXxxxClassesDual
// and for va_eXxxx as well

va_pOfficerClasses = [];
va_pCarClasses = [];
va_pQuadBikeClasses = [];
va_pTankClasses = [];
va_pApcClasses = [];
va_pArtyClasses = [];
va_pMortarClasses = [];
va_pHeliClasses = [];
va_pPlaneClasses = [];
va_pShipClasses = [];
va_pFuelClasses = [];
va_pRepairClasses = [];
va_pAmmoClasses = [];
va_pGenericNames = [];
va_pLanguage = [];
va_pUAVClasses = [];
va_pInfClassesForWeights = [];
va_pInfClassWeights = [];
va_pStaticClasses = [];
va_pStaticAAClasses = [];
va_pAAClasses = [];
va_pSubmarineClasses = [];
va_pDriverlessVehicles = [];
va_pAllVehicles = [];

va_eOfficerClasses = [];
va_eCarClasses = [];
va_eQuadBikeClasses = [];
va_eTankClasses = [];
va_eApcClasses = [];
va_eArtyClasses = [];
va_eMortarClasses = [];
va_eHeliClasses = [];
va_ePlaneClasses = [];
va_eShipClasses = [];
va_eFuelClasses = [];
va_eRepairClasses = [];
va_eAmmoClasses = [];
va_eGenericNames = [];
va_eLanguage = [];
va_eUAVClasses = [];
va_eInfClassesForWeights = [];
va_eInfClassWeights = [];
va_eStaticClasses = [];
va_eStaticAAClasses = [];
va_eAAClasses = [];
va_eSubmarineClasses = [];

va_cOfficerClasses = [];
va_cCarClasses = [];
va_cQuadBikeClasses = [];
va_cHeliClasses = [];
va_cPlaneClasses = [];
va_cShipClasses = [];
va_cGenericNames = [];
va_cLanguage = [];
va_cUAVClasses = [];
va_cRepairClasses = [];
va_cAmmoClasses = [];
va_cFuelClasses = [];
va_cSubmarineClasses = [];
 
#define SIDE_NONE      -1
#define SIDE_EAST       0		
#define SIDE_WEST       1		
#define SIDE_RESISTANCE 2
#define SIDE_CIVILIAN   3
private _sideFix = {
    // CSLA DLC has the vehicle side as a string, which is wrong  
    params ["_cfgName","_sideStr"];
    _side = 
        switch (toLowerANSI _sideStr) do {
            case "teast": {SIDE_EAST};
            default {
                diag_log format ["Invalid vehicle side: %1 %2",_cfgName,_sideStr];
                SIDE_NONE
            };
        };
    _side
};

private _playerFactions = [_playerFaction] call FactionConvertToBaseList;
private _enemyFactions = [_enemyFaction] call FactionConvertToBaseList;
private _civFactions = [ITW_CivFaction] call FactionConvertToBaseList;
private _playerSideNum = [_playerFactions,true] call FactionSideNum;
private _enemySideNum = [_enemyFactions,true]  call FactionSideNum;
private _dlcOkay = true;
//([] call FactionDlcId) params ["_customDLCs","_removeDlcs"];
if (isNil "ITW_VehicleDlcs") then {ITW_VehicleDlcs = []};
private _customDLCs = [];
{
    if (typeName _x == "STRING") then {
        _customDLCs pushBack toLowerANSI _x;
    };
} forEach ITW_VehicleDlcs;

{
    private _cfg = _x;
    private _cfgName = configName _cfg;
    
    // vehicles this mission doensn't work with
    if (_cfgName in ["OPTRE_FC_Scarab_Hull_Base","OPTRE_FC_Scarab_Hull_AT","OPTRE_FC_Hull_AA","OPTRE_FC_Hull_Cmdr","OPTRE_FC_Hull_Cmdr_AA"]) then {continue};
    
    if (_cfgName isKindOf "Wreck_Base" || 
        { toUpperANSI ((_cfg >> "vehicleClass") call BIS_fnc_getCfgData)   find "WRECKS" >= 0 ||
        { toUpperANSI ((_cfg >> "editorCategory") call BIS_fnc_getCfgData) find "WRECKS" >= 0
        }}) then {continue};
    
    private _cfgFaction = (toUpperANSI getText (_cfg >> "faction"));
    private _isGlobalCivFaction = if ((_cfgFaction find "CIV_") == 0) then {true} else {false};
    private ["_isPlayerFaction","_isEnemyFaction","_isCivFaction"];
    switch (ITW_ParamVehicles) do {
        case 0: {
            // full
            _isPlayerFaction = !_isGlobalCivFaction;
            _isEnemyFaction  = !_isGlobalCivFaction;
            _isCivFaction = _isGlobalCivFaction;
        };
        case 1: { 
            // side
            private _cfgSide = ((_cfg >> "side") call BIS_fnc_getCfgData);
            if (isNil "_cfgSide") then {_cfgSide = "nil"};
            if (typeName _cfgSide != "SCALAR") then {_cfgSide = [_cfgName,_cfgSide] call _sideFix};    
            _isPlayerFaction = if (_cfgSide in _playerSideNum) then {true} else {false};
            _isEnemyFaction  = if (_cfgSide in _enemySideNum ) then {true} else {false};
            _isCivFaction = _isGlobalCivFaction;
        };
        case 2: {
            // selected DLC
            private _dlc = toLowerANSI configSourceMod _cfg;
            if (/*!(_dlc in _removeDLCs) AND */((count _customDLCs == 0) OR (_dlc in _customDLCs))) then {
                private _cfgSide = ((_cfg >> "side") call BIS_fnc_getCfgData);
                if (isNil "_cfgSide") then {_cfgSide = "nil"};
                if (typeName _cfgSide != "SCALAR") then {_cfgSide = [_cfgName,_cfgSide] call _sideFix};    
                _isPlayerFaction = _cfgSide in _playerSideNum;
                _isEnemyFaction  = _cfgSide in _enemySideNum ;
                _isCivFaction    = _cfgSide == 3/* civilian*/;
            } else {
                _dlcOkay = false;
                _isPlayerFaction = false;
                _isEnemyFaction  = false;
                _isCivFaction = false;
            };
        };
        default {
            // faction
            _isPlayerFaction = _cfgFaction in _playerFactions;
            _isEnemyFaction  = _cfgFaction in _enemyFactions;
            _isCivFaction    = _cfgFaction in _civFactions;
        };
    };
    if (_playerFactionIsAllNonEnemy) then {
        _isPlayerFaction = !_isEnemyFaction;
        if (((_cfgFaction find "CIV_") == 0) or (_cfgFaction == "Default")) then { 
            // civilian vehicle or wreck
            _isPlayerFaction = false;
        }; 
    };

    if (_isEnemyFaction || _isPlayerFaction || _isCivFaction) then {
        if (getNumber (_cfg >> "isUav") != 0) exitWith {
            private _edSubcat = ((_cfg >> "editorSubcategory") call BIS_fnc_getCfgData);
            if ( ["drone", _edSubcat, false] call BIS_fnc_inString ) then {
                if (_isPlayerFaction) then {
                    va_pUAVClasses pushBackUnique _cfgName;
                };
                if (_isEnemyFaction) then {
                    va_eUAVClasses pushBackUnique _cfgName;
                };
                if (_isCivFaction) then {
                    va_cUAVClasses pushBackUnique _cfgName;
                };
            };
        };  
        
        private _exit = false;
        {
            if (_cfgName isEqualTo _x) exitWith {_exit = true};
        } forEach ["vn_o_static_rsna75","CUP_WV_B_CRAM","CUP_WV_B_RAM_Launcher","CUP_WV_B_SS_Launcher"];        
        if (_exit) exitWith {};
        
        {
            if (_cfgName isKindOf _x) exitWith {_exit = true};
        } forEach ["Building","gm_searchlight_base","gm_biber_base"];
        if (_exit) exitWith {};
        
        if (_cfgName isKindOf 'Man') then {	                
            if ( ["officer", _cfgName, false] call BIS_fnc_inString ) then {
                if (_isPlayerFaction) then {
                    va_pOfficerClasses pushBack _cfgName;
                };
                if (_isEnemyFaction) then {
                    va_eOfficerClasses pushBack _cfgName;
                };
                if (_isCivFaction) then {
                    va_cOfficerClasses pushBack _cfgName;
                };
            };
        } else {
            if (getNumber(_cfg >> "hasDriver") == -1) then {
                // ignore driverless vehicles:    if (_isPlayerFaction) then {va_pDriverlessVehicles pushBackUnique _cfgName}; 
                continue
            };
            _checkSubcats = true;
            if (_cfgName isKindOf 'Car') then {				
                _edSubcat = ((_cfg >> "editorSubcategory") call BIS_fnc_getCfgData);
                if (!isNil "_edSubcat") then {
                    if (_edSubcat == "EdSubcat_Drones") then {
                        
                    } else {
                        if (["apc", _edSubcat, false] call BIS_fnc_inString) then {
                            if (_isPlayerFaction) then {
                                va_pApcClasses pushBackUnique _cfgName;
                            } else {
                                if (_isCivFaction) then {
                                    va_eApcClasses pushBackUnique _cfgName;
                                };
                            };
                        } else {
                            if (_cfgName isKindOf "Quadbike_01_base_F" || {_cfgName isKindOf "Motorcycle" || {_cfgName isKindOf "vn_bicycle_base" || {_cfgName isKindOf "gm_wheeled_bicycle_base"}}}) then {
                                if (_isPlayerFaction) then {
                                    va_pQuadBikeClasses pushBackUnique _cfgName;
                                    
                                } else {
                                    if (_isEnemyFaction) then {
                                        va_eQuadBikeClasses pushBackUnique _cfgName;
                                    } else {
                                        if (_isCivFaction) then {
                                            va_cQuadBikeClasses pushBackUnique _cfgName;
                                        };
                                    };
                                };
                            } else {
                                if (_isPlayerFaction) then {
                                    va_pCarClasses pushBackUnique _cfgName;
                                    
                                } else {
                                    if (_isEnemyFaction) then {
                                        va_eCarClasses pushBackUnique _cfgName;
                                    } else {
                                        if (_isCivFaction) then {
                                            va_cCarClasses pushBackUnique _cfgName;
                                        };
                                    };
                                };
                                _checkSubcats = false;	 
                            };
                        };
                    };
                };	
                _pVars = [va_pRepairClasses, va_pAmmoClasses, va_pFuelClasses];
                _eVars = [va_eRepairClasses, va_eAmmoClasses, va_eFuelClasses];
                _cVars = [va_cRepairClasses, va_cAmmoClasses, va_cFuelClasses];
                {
                    if (getNumber (_cfg >> _x) > 100 ) then {
                        if (_isPlayerFaction) then {
                            (_pVars select _forEachIndex) pushBackUnique _cfgName;
                        };
                        if (_isEnemyFaction) then {
                            (_eVars select _forEachIndex) pushBackUnique _cfgName;
                        };
                        if (_isCivFaction) then {
                            (_cVars select _forEachIndex) pushBackUnique _cfgName;
                        };
                    };
                } forEach ["transportRepair","transportAmmo","transportFuel"];                
            } else {
                if (_cfgName isKindOf 'Tank') then {
                    _edSubcat = ((_cfg >> "editorSubcategory") call BIS_fnc_getCfgData);
                    if (
                        !(["artillery", _edSubcat, false] call BIS_fnc_inString) &&
                        {!(["aa", _edSubcat, false] call BIS_fnc_inString) &&
                        {!(_cfgName isKindOf "gm_biber_base")
                    }}) then {
                        if (_isPlayerFaction) then {
                            if (["apc", _edSubcat, false] call BIS_fnc_inString) then {
                                va_pApcClasses pushBackUnique _cfgName;
                            } else {
                                va_pTankClasses pushBackUnique _cfgName;
                            };
                        };
                        if (_isEnemyFaction) then {
                            if (["apc", _edSubcat, false] call BIS_fnc_inString) then {
                                va_eApcClasses pushBackUnique _cfgName;
                            } else {
                                va_eTankClasses pushBackUnique _cfgName;
                            };
                        };
                        _checkSubcats = false;
                    };
                } else {
                    if (_cfgName isKindOf 'Plane') then {
                        if (_isPlayerFaction) then {
                            va_pPlaneClasses pushBackUnique _cfgName;
                        };
                        if (_isEnemyFaction) then {
                            va_ePlaneClasses pushBackUnique _cfgName;
                        };
                        if (_isCivFaction) then {
                            va_cPlaneClasses pushBackUnique _cfgName;
                        };
                        _checkSubcats = false;
                    
                    } else {
                        if (_cfgName isKindOf 'Helicopter') then {
                            if (_isPlayerFaction) then {
                                va_pHeliClasses pushBackUnique _cfgName;
                            };
                            if (_isEnemyFaction) then {
                                va_eHeliClasses pushBackUnique _cfgName;
                            };
                            if (_isCivFaction) then {
                                va_cHeliClasses pushBackUnique _cfgName;
                            };
                            _checkSubcats = false;
                        };
                    };
                };
            };
            if (_checkSubcats) then {
                _pVars = [va_pMortarClasses, va_pStaticClasses, va_pStaticClasses, va_pStaticClasses, va_pStaticClasses, va_pStaticClasses];
                _eVars = [va_eMortarClasses, va_eStaticClasses, va_eStaticClasses, va_eStaticClasses, va_eStaticClasses, va_eStaticClasses];
                {						
                    if (_cfgName isKindOf _x) exitWith {  
                        if (_isPlayerFaction) then {
                            (_pVars select _forEachIndex) pushBackUnique _cfgName;
                        };
                        if (_isEnemyFaction) then {
                            (_eVars select _forEachIndex) pushBackUnique _cfgName;
                        };
                        _checkSubcats = false;
                    };
                } forEach ["StaticMortar", "StaticMGWeapon", "StaticGrenadeLauncher", "StaticCannon", "StaticAAWeapon", "gm_staticWeapon_base"];
            };
            if (_checkSubcats) then {
                _edSubcat = ((_cfg >> "editorSubcategory") call BIS_fnc_getCfgData);
                if (!isNil "_edSubcat") then {                        
                    _pVars = [va_pAAClasses, va_pTankClasses, va_pApcClasses, va_pHeliClasses, va_pPlaneClasses, va_pShipClasses, va_pSubmarineClasses];
                    _eVars = [va_eAAClasses, va_eTankClasses, va_eApcClasses, va_eHeliClasses, va_ePlaneClasses, va_eShipClasses, va_eSubmarineClasses];
                    _cVars = [[]           , []             , []            , va_cHeliClasses, va_cPlaneClasses, va_cShipClasses, va_cSubmarineClasses];
                    {						
                        if ( [_x, _edSubcat, false] call BIS_fnc_inString ) exitWith {
                            if (_isPlayerFaction) then {
                                (_pVars select _forEachIndex) pushBackUnique _cfgName;
                            };
                            if (_isEnemyFaction) then {
                                (_eVars select _forEachIndex) pushBackUnique _cfgName;
                            };
                            if (_isCivFaction && {!((_cVars select _forEachIndex) isEqualTo [])} ) then {
                                (_cVars select _forEachIndex) pushBackUnique _cfgName;
                            };
                        };
                    } forEach ["aa", "tank", "apc", "helicopter", "plane", "boat", "submersible"];					
                };
            };
            
            if ("Artillery" in getArray(_cfg >> "availableForSupportTypes")) then {
                if (_isPlayerFaction) then {
                    va_pArtyClasses pushBackUnique _cfgName;
                };
                if (_isEnemyFaction) then {
                    va_eArtyClasses pushBackUnique _cfgName;
                };
            };
        };
    };
} forEach ("(getNumber (_x >> 'scope') == 2) || {(getNumber (_x >> 'scope') == 1) && (getNumber (_x >> 'scopeCurator') == 2)}" configClasses (configFile / "CfgVehicles"));

// ITW doesn't use AAClasses except for side tasks.  We need to add them into tanks or cars as needed so they get used
{
    private _aaClass = (if (typeName _x == "ARRAY") then {_x#0} else {_x});
    if (_aaClass isKindOf "Tank") then {va_pTankClasses pushBackUnique _aaClass};
    if (_aaClass isKindOf "Car" ) then {va_pApcClasses  pushBackUnique _aaClass};
} forEach va_pAAClasses;
{
    private _aaClass = (if (typeName _x == "ARRAY") then {_x#0} else {_x});
    if (_aaClass isKindOf "Tank") then {va_eTankClasses pushBackUnique _aaClass};
    if (_aaClass isKindOf "Car" ) then {va_eApcClasses  pushBackUnique _aaClass};
} forEach va_eAAClasses;


if ("EnsureCarTransport" in _options) then {
    if (va_eCarTransportClasses isEqualTo []) then { 
        va_eCarTransportClasses = ["I_G_Van_01_fuel_F", "O_G_Van_01_fuel_F", "O_G_Van_01_fuel_F", "B_G_Offroad_01_repair_F", "B_G_Van_01_transport_F", "C_Van_01_fuel_F", "C_Offroad_01_comms_F", "C_Offroad_01_repair_F", "C_Van_02_serviva_F", "C_Truck_02_fuel_F", "C_Truck_02_box_F", "C_Truck_02_transport_F", "C_Truck_02_covered_F","C_Hatchback_01_sport_F"]; 
    };
    if (va_pCarTransportClasses isEqualTo []) then { 
        va_pCarTransportClasses = ["I_G_Van_01_fuel_F", "O_G_Van_01_fuel_F", "O_G_Van_01_fuel_F", "B_G_Offroad_01_repair_F", "B_G_Van_01_transport_F", "C_Van_01_fuel_F", "C_Offroad_01_comms_F", "C_Offroad_01_repair_F", "C_Van_02_serviva_F", "C_Truck_02_fuel_F", "C_Truck_02_box_F", "C_Truck_02_transport_F", "C_Truck_02_covered_F","C_Hatchback_01_sport_F"]; 
    };
};

if ("EnsureSupports" in _options) then {
    if (va_pRepairClasses isEqualTo []) then {va_pRepairClasses = ["C_Truck_02_box_F"]};
    if (va_eRepairClasses isEqualTo []) then {va_eRepairClasses = ["C_Truck_02_box_F"]};
    if (va_pAmmoClasses isEqualTo []) then {va_pAmmoClasses = ["I_Truck_02_ammo_F"]};
    if (va_eAmmoClasses isEqualTo []) then {va_eAmmoClasses = ["I_Truck_02_ammo_F"]};
    if (va_pFuelClasses isEqualTo []) then {va_pFuelClasses = ["C_Truck_02_fuel_F"]};
    if (va_eFuelClasses isEqualTo []) then {va_eFuelClasses = ["C_Truck_02_fuel_F"]};
};

if ("EnsureQuadBike" in _options) then {
    if (va_eQuadBikeClasses isEqualTo []) then {
        if (va_cQuadBikeClasses isEqualTo []) then {
            switch (toLowerANSI worldName) do {
                case "stozec": {va_eQuadBikeClasses = ["CSLA_CIV_JARA250","US85_TT650"]};
                case "vn_khe_sanh";
                case "vn_the_bra";
                case "cam_lao_nam": {va_eQuadBikeClasses = ["vn_o_bicycle_01_nva65","vn_c_wheeled_m151_01"]};
                case "spex_utah_beach";
                case "spex_carentan";
                case "spe_mortain";
                case "spe_normandy": {va_eQuadBikeClasses = ["C_Tractor_01_F"]};
                case "gm_weferlingen_winter";
                case "gm_weferlingen_summer": {va_eQuadBikeClasses = ["gm_ge_army_k125"]};    
                default {
                    if ("vn" in _customDLCs) then {
                        va_eQuadBikeClasses = ["vn_o_bicycle_01_nva65","vn_c_wheeled_m151_01"]; // SOG Prairie Fire
                    } else {
                        if ("gm" in _customDLCs) then {
                            va_eQuadBikeClasses = ["gm_ge_army_k125"]; // global mobilization
                        } else {
                            if ("spe" in _customDLCs) then {
                                va_eQuadBikeClasses = ["C_Tractor_01_F"]; // Spearhead 1944
                            } else {
                                if ("csla" in _customDLCs) then {
                                    va_eQuadBikeClasses = ["CSLA_CIV_JARA250","US85_TT650"]; // CSLA Iron Curtain
                                } else {
                                    va_eQuadBikeClasses = ["C_Quadbike_01_black_F","C_Quadbike_01_blue_F","C_Quadbike_01_red_F","C_Quadbike_01_white_F"];
                                };
                            };
                        };
                    };
                };
            };            
        } else {
            va_eQuadBikeClasses = va_cQuadBikeClasses;
        };
    };
    if (va_pQuadBikeClasses isEqualTo []) then {
        if (va_cQuadBikeClasses isEqualTo []) then {
            switch (toLowerANSI worldName) do {
                case "stozec": {va_pQuadBikeClasses = ["CSLA_CIV_JARA250","US85_TT650"]};
                case "vn_khe_sanh";
                case "vn_the_bra";
                case "cam_lao_nam": {va_pQuadBikeClasses = ["vn_o_bicycle_01_nva65","vn_c_wheeled_m151_01"]};
                case "spex_utah_beach";
                case "spex_carentan";
                case "spe_mortain";
                case "spe_normandy": {va_pQuadBikeClasses = ["C_Tractor_01_F"]};
                case "gm_weferlingen_winter";
                case "gm_weferlingen_summer": {va_pQuadBikeClasses = ["gm_ge_army_k125"]};    
                default {
                    if ("vn" in _customDLCs) then {
                        va_pQuadBikeClasses = ["vn_o_bicycle_01_nva65","vn_c_wheeled_m151_01"]; // SOG Prairie Fire
                    } else {
                        if ("gm" in _customDLCs) then {
                            va_pQuadBikeClasses = ["gm_ge_army_k125"]; // global mobilization
                        } else {
                            if ("spe" in _customDLCs) then {
                                va_pQuadBikeClasses = ["C_Tractor_01_F"]; // Spearhead 1944
                            } else {
                                if ("csla" in _customDLCs) then {
                                    va_pQuadBikeClasses = ["CSLA_CIV_JARA250","US85_TT650"]; // CSLA Iron Curtain
                                } else {
                                    va_pQuadBikeClasses = ["C_Quadbike_01_black_F","C_Quadbike_01_blue_F","C_Quadbike_01_red_F","C_Quadbike_01_white_F"];
                                };
                            };
                        };
                    };
                };
            };
        } else {
            va_pQuadBikeClasses = va_cQuadBikeClasses;
        };
    };
};

// AIRPORTS
//try {
//    _airport = [];
//    _airport pushBack ((configFile >> "CfgWorlds" >> worldName >> "ilsPosition") call BIS_fnc_getCfgData);
//    _airport pushBack ((configFile >> "CfgWorlds" >> worldName >> "ilsDirection") call BIS_fnc_getCfgData);
//    _airport pushBack ((configFile >> "CfgWorlds" >> worldName >> "ilsTaxiOff") call BIS_fnc_getCfgData);
//    _airport pushBack ((configFile >> "CfgWorlds" >> worldName >> "ilsTaxiIn") call BIS_fnc_getCfgData);
//    va_airports pushBack _airport;
//} catch {};
//
//try {
//    {
//        _airport = [];
//        _airport pushBack ((_x >> "ilsPosition") call BIS_fnc_getCfgData);
//        _airport pushBack ((_x >> "ilsDirection") call BIS_fnc_getCfgData);
//        _airport pushBack ((_x >> "ilsTaxiOff") call BIS_fnc_getCfgData);
//        _airport pushBack ((_x >> "ilsTaxiIn") call BIS_fnc_getCfgData);
//        va_airports pushBack _airport;
//    } forEach ("true" configClasses (configFile / "CfgWorlds" / worldName / "SecondaryAirports")); 
//} catch {};

private _GetAmmoFuelRepairFn = {
    private _cars = _this;
    private _ammo = [];
    private _fuel = [];
    private _repair = [];
    {
        private _class = _x;
        if (typeName _x == "ARRAY") then {_class = _x#0}; // class can be [class,texture,anim]
        private _cfg = configFile >> "cfgVehicles" >> _class;
        if (getNumber (_cfg >> "transportAmmo")   > 100) then {_ammo pushBack _x};
        if (getNumber (_cfg >> "transportFuel")   > 100) then {_fuel pushBack _x};
        if (getNumber (_cfg >> "transportRepair") > 100) then {_repair pushBack _x};
    } forEach _cars;

    [_ammo,_fuel,_repair];
};

// handle if player asked to replace some of the vehicles
if (!(ITW_EnemyVehicles isEqualTo [])) then {
    if (ITW_ParamVehicleChooser == 1 || {ITW_ParamVehicleChooser == 3}) then {
        // enemy override
        private _tnk = [ITW_EnemyVehicles,"Tnk",true] call VehicleChooser_Get;
        private _apc = [ITW_EnemyVehicles,"Apc",true] call VehicleChooser_Get;
        private _car = [ITW_EnemyVehicles,"Car",true] call VehicleChooser_Get;
        private _hel = [ITW_EnemyVehicles,"Hel",true] call VehicleChooser_Get;
        private _pla = [ITW_EnemyVehicles,"Pla",true] call VehicleChooser_Get;
        private _nav = [ITW_EnemyVehicles,"Nav",true] call VehicleChooser_Get;
        private _sta = [ITW_EnemyVehicles,"Sta",true] call VehicleChooser_Get;
        private _uav = [ITW_EnemyVehicles,"Uav",true] call VehicleChooser_Get;
        
        va_eTankClasses   = [];
        va_eAAClasses     = [];
        va_eApcClasses    = [];
        va_eCarClasses    = [];
        va_eHeliClasses   = [];
        va_ePlaneClasses  = [];
        va_eShipClasses   = [];
        va_eMortarClasses = [];
        va_eStaticClasses = [];
        va_eQuadBikeClasses = [];
        
        if !(_tnk isEqualTo []) then {va_eTankClasses   = _tnk};
        if !(_apc isEqualTo []) then {va_eApcClasses    = _apc};
        if !(_car isEqualTo []) then {va_eCarClasses    = _car};
        if !(_hel isEqualTo []) then {va_eHeliClasses   = _hel};
        if !(_pla isEqualTo []) then {va_ePlaneClasses  = _pla};
        if !(_nav isEqualTo []) then {va_eShipClasses   = _nav};
        if !(_sta isEqualTo []) then {va_eMortarClasses = _sta; va_eStaticClasses = _sta};
        if !(_uav isEqualTo []) then {va_eUavClasses    = _uav;                           };
        
        if (!(_tnk isEqualTo []) && { (_apc isEqualTo [])}) then {va_eApcClasses = va_eTankClasses};
        if ( (_tnk isEqualTo []) && {!(_apc isEqualTo [])}) then {va_eTankClasses = va_eApcClasses};
        
        private _afrVehs = va_eCarClasses call _GetAmmoFuelRepairFn;
        va_eAmmoClasses   = _afrVehs#0;
        va_eFuelClasses   = _afrVehs#1;
        va_eRepairClasses = _afrVehs#2;
    };

    if (ITW_ParamVehicleChooser == 4 || {ITW_ParamVehicleChooser == 6}) then {
        // enemy add
        private _tnk = [ITW_EnemyVehicles,"Tnk",true] call VehicleChooser_Get;
        private _apc = [ITW_EnemyVehicles,"Apc",true] call VehicleChooser_Get;
        private _car = [ITW_EnemyVehicles,"Car",true] call VehicleChooser_Get;
        private _hel = [ITW_EnemyVehicles,"Hel",true] call VehicleChooser_Get;
        private _pla = [ITW_EnemyVehicles,"Pla",true] call VehicleChooser_Get;
        private _nav = [ITW_EnemyVehicles,"Nav",true] call VehicleChooser_Get;
        private _sta = [ITW_EnemyVehicles,"Sta",true] call VehicleChooser_Get;
        private _uav = [ITW_EnemyVehicles,"Uav",true] call VehicleChooser_Get;
        
        if !(_tnk isEqualTo []) then {va_eTankClasses   = va_eTankClasses   + _tnk};
        if !(_apc isEqualTo []) then {va_eApcClasses    = va_eApcClasses    + _apc};
        if !(_car isEqualTo []) then {va_eCarClasses    = va_eCarClasses    + _car};
        if !(_hel isEqualTo []) then {va_eHeliClasses   = va_eHeliClasses   + _hel};
        if !(_pla isEqualTo []) then {va_ePlaneClasses  = va_ePlaneClasses  + _pla};
        if !(_nav isEqualTo []) then {va_eShipClasses   = va_eShipClasses   + _nav};
        if !(_sta isEqualTo []) then {va_eStaticClasses = va_eStaticClasses + _sta};
        if !(_uav isEqualTo []) then {va_eUavClasses    = va_eUavClasses    + _uav};
        
        if (!(va_eTankClasses isEqualTo []) && { (va_eApcClasses isEqualTo [])}) then {va_eApcClasses = va_eTankClasses};
        if ( (va_eTankClasses isEqualTo []) && {!(va_eApcClasses isEqualTo [])}) then {va_eTankClasses = va_eApcClasses};
        
        private _afrVehs = va_eCarClasses call _GetAmmoFuelRepairFn;
        va_eAmmoClasses   = va_eAmmoClasses   + _afrVehs#0;
        va_eFuelClasses   = va_eFuelClasses   + _afrVehs#1;
        va_eRepairClasses = va_eRepairClasses + _afrVehs#2;
    };
};

if (!(ITW_PlayerVehicles isEqualTo [])) then {
    if (ITW_ParamVehicleChooser == 2 || {ITW_ParamVehicleChooser == 3}) then {
        // player override    
        private _tnk = [ITW_PlayerVehicles,"Tnk",true] call VehicleChooser_Get;
        private _apc = [ITW_PlayerVehicles,"Apc",true] call VehicleChooser_Get;
        private _car = [ITW_PlayerVehicles,"Car",true] call VehicleChooser_Get;
        private _hel = [ITW_PlayerVehicles,"Hel",true] call VehicleChooser_Get;
        private _pla = [ITW_PlayerVehicles,"Pla",true] call VehicleChooser_Get;
        private _nav = [ITW_PlayerVehicles,"Nav",true] call VehicleChooser_Get;
        private _sta = [ITW_PlayerVehicles,"Sta",true] call VehicleChooser_Get;
        private _uav = [ITW_PlayerVehicles,"Uav",true] call VehicleChooser_Get;
        
        va_pTankClasses   = [];
        va_pApcClasses    = [];
        va_pCarClasses    = [];
        va_pHeliClasses   = [];
        va_pPlaneClasses  = [];
        va_pShipClasses   = [];
        va_pMortarClasses = [];
        va_pStaticClasses = [];
        va_pQuadBikeClasses = [];
        va_pAAClasses = [];
        va_pArtyClasses = [];
        va_pDriverlessVehicles = [];
        va_pUAVClasses = [];
        va_pSubmarineClasses = [];
        if !(_tnk isEqualTo []) then {va_pTankClasses   = _tnk;                           };
        if !(_apc isEqualTo []) then {va_pApcClasses    = _apc;                           };
        if !(_car isEqualTo []) then {va_pCarClasses    = _car;                           };
        if !(_hel isEqualTo []) then {va_pHeliClasses   = _hel;                           };
        if !(_pla isEqualTo []) then {va_pPlaneClasses  = _pla;                           };
        if !(_nav isEqualTo []) then {va_pShipClasses   = _nav;                           };
        if !(_sta isEqualTo []) then {va_pMortarClasses = _sta; va_pStaticClasses = _sta; };
        if !(_uav isEqualTo []) then {va_pUavClasses    = _uav;                           };
        
        if (!(_tnk isEqualTo []) && { (_apc isEqualTo [])}) then {va_pApcClasses = va_pTankClasses};
        if ( (_tnk isEqualTo []) && {!(_apc isEqualTo [])}) then {va_pTankClasses = va_pApcClasses};
        
        private _afrVehs = va_pCarClasses call _GetAmmoFuelRepairFn;
        va_pAmmoClasses   = _afrVehs#0;
        va_pFuelClasses   = _afrVehs#1;
        va_pRepairClasses = _afrVehs#2;
    };

    if (ITW_ParamVehicleChooser == 5 || {ITW_ParamVehicleChooser == 6}) then {
        // player add    
        private _tnk = [ITW_PlayerVehicles,"Tnk",true] call VehicleChooser_Get;
        private _apc = [ITW_PlayerVehicles,"Apc",true] call VehicleChooser_Get;
        private _car = [ITW_PlayerVehicles,"Car",true] call VehicleChooser_Get;
        private _hel = [ITW_PlayerVehicles,"Hel",true] call VehicleChooser_Get;
        private _pla = [ITW_PlayerVehicles,"Pla",true] call VehicleChooser_Get;
        private _nav = [ITW_PlayerVehicles,"Nav",true] call VehicleChooser_Get;
        private _sta = [ITW_PlayerVehicles,"Sta",true] call VehicleChooser_Get;
        private _uav = [ITW_PlayerVehicles,"Uav",true] call VehicleChooser_Get;
        
        if !(_tnk isEqualTo []) then {va_pTankClasses   = va_pTankClasses   + _tnk};
        if !(_apc isEqualTo []) then {va_pApcClasses    = va_pApcClasses    + _apc};
        if !(_car isEqualTo []) then {va_pCarClasses    = va_pCarClasses    + _car};
        if !(_hel isEqualTo []) then {va_pHeliClasses   = va_pHeliClasses   + _hel};
        if !(_pla isEqualTo []) then {va_pPlaneClasses  = va_pPlaneClasses  + _pla};
        if !(_nav isEqualTo []) then {va_pShipClasses   = va_pShipClasses   + _nav};
        if !(_sta isEqualTo []) then {va_pStaticClasses = va_pStaticClasses + _sta};
        if !(_uav isEqualTo []) then {va_pUavClasses    = va_pUavClasses    + _uav};
        
        if (!(va_pTankClasses isEqualTo []) && { (va_pApcClasses isEqualTo [])}) then {va_pApcClasses = va_pTankClasses};
        if ( (va_pTankClasses isEqualTo []) && {!(va_pApcClasses isEqualTo [])}) then {va_pTankClasses = va_pApcClasses};
        
        private _afrVehs = va_pCarClasses call _GetAmmoFuelRepairFn;
        va_pAmmoClasses   = va_pAmmoClasses   + _afrVehs#0;
        va_pFuelClasses   = va_pFuelClasses   + _afrVehs#1;
        va_pRepairClasses = va_pRepairClasses + _afrVehs#2;
    };
};

// get static AA weapons as a class too
{
    private _type = if (typeName _x == "ARRAY") then {_x#0} else {_x};
    if (_type isKindOf "StaticAAWeapon") then { 
        va_pStaticAAClasses pushBackUnique _x;
    };
} forEach va_pStaticClasses;
{
    private _type = if (typeName _x == "ARRAY") then {_x#0} else {_x};
    if (_type isKindOf "StaticAAWeapon") then { 
        va_eStaticAAClasses pushBackUnique _x;
    };
} forEach va_eStaticClasses;

// ensure enemy AA if possible
if (va_eAAClasses isEqualTo []) then {
    va_eAAClasses = va_eTankClasses select {
        private _class = if (typeName _x == "ARRAY") then {_x#0} else {_x};
        private _threat = getArray (configFile >> "cfgVehicles" >> _class >> "threat");
        if (count _threat >= 3 && {_threat#2 > 0.9 || {_class in ["B_APC_Tracked_01_AA_F"]}}) then {
            true
        } else {
            false
        };
    };
    if (va_eAAClasses isEqualTo []) then {
        va_eAAClasses = va_eStaticAAClasses;
    };
};

// va_pAllVehicles is used for the garage, so do this before the limit by subclass as that can be too limiting for players
va_pAllVehicles = va_pCarClasses + va_pQuadBikeClasses + va_pTankClasses + va_pApcClasses + va_pHeliClasses + va_pFuelClasses + va_pRepairClasses + va_pAmmoClasses + va_pAAClasses + va_pShipClasses + va_pPlaneClasses + va_pArtyClasses + va_pStaticClasses + va_pMortarClasses + va_pDriverlessVehicles + va_pUAVClasses + va_pSubmarineClasses;

if (false) then {
    // Handle if player wants to limit vehicles by vehicle class 
    
    private _vehicles = [[va_pTankClasses,va_pApcClasses,va_pCarClasses,va_pHeliClasses,va_pPlaneClasses,va_pShipClasses],
                         [va_eTankClasses,va_eApcClasses,va_eCarClasses,va_eHeliClasses,va_ePlaneClasses,va_eShipClasses]];
    if (isServer) then {
        ITW_VehClasses = profileNamespace getVariable [format["ITW_VehicleClasses%1",worldName],[]];// [[],[]] indicates not used, [] indicates it should be selected
        if (ITW_VehClasses isEqualTo []) then {
            private _vehClassesChosen = ITW_VehClasses;
            if (_vehClassesChosen isEqualTo []) then {
                diag_log "ITW: User choosing vehicle classes";
                {
                    private _pOrEArray = _x;
                    private _vehClasses = [];
                    {
                        private _classes = _x;
                        {
                            private _vehClassType = getText (configFile >> "cfgVehicles" >> _x >> "vehicleclass");
                            private _displayName = getText (configFile >> "cfgVehicleClasses" >> _vehClassType >> "displayName");
                            if !(_displayName isEqualTo "") then {_vehClasses pushBack [_displayName,_vehClassType]};
                        } forEach _classes;
                    } forEach _pOrEArray;
                    _vehClasses = _vehClasses arrayIntersect _vehClasses;
                    _vehClassesChosen pushBack ([_vehClasses,objNull,if (_forEachIndex == 0) then {localize "STR_ITW_PARAM_VehicleChooser_Player"} else {localize "STR_ITW_PARAM_VehicleChooser_Enemy"}] call ListChooser);
                } forEach _vehicles;
                profileNamespace setVariable [format["ITW_VehicleClasses%1",worldName],_vehClassesChosen];
            };
            ITW_VehClasses = _vehClassesChosen;
        };
        publicVariable "ITW_VehClasses";
    };
    
    waitUntil {!isNil "ITW_VehClasses"};
    {
        private _pOrEArray = _x;
        private _vehClasses = ITW_VehClasses#_forEachIndex;
        if (_vehClasses isEqualTo []) then {continue};
        {
            private _classes = _x;
            {
                _vehClass = getText (configFile >> "cfgVehicles" >> _x >> "vehicleclass");
                if !(_vehClass in _vehClasses) then {_classes deleteAt _forEachIndex};
            } forEachReversed _classes;
        } forEach _pOrEArray;
    } forEach _vehicles;
//} else {
//    profileNamespace setVariable [format["ITW_VehicleClasses%1",worldName],[]];
};

// split Tank,Apc,Heli,Car into attack/transport/dual
#define ATS_DEBUG comment 
//#define ATS_DEBUG call compile

private _pCarClassesDualAsTransport  = [[],0]; // if no transports, we allow some dual versions to act as transports by removing their ammo
private _eCarClassesDualAsTransport  = [[],0];
private _pHeliClassesDualAsTransport = [[],0];
private _eHeliClassesDualAsTransport = [[],0];
 
private _fnAttackTransportSplit = {
    params ["_varArray","_minCargoSeats"];
    private _array = call compile _varArray;
    private _attack = [];
    private _transport = [];
    private _dual = [];
    ATS_DEBUG 'diag_log ["ATS VEH TYPE",_varArray]';
    {        		
        private _vehType = _x;
        private _class = if (typeName _vehType isEqualTo "STRING") then {_vehType} else {_vehType#0};
        
        // don't allow Warhammer 4k drop pods
        if (_class select [0,13] isEqualTo "TIOW_Drop_Pod") then {continue};
        
        private _cfg = configFile >> "CfgVehicles" >> _class;
        
        // minimum speed requirement of 15 kph && don't use artillery vehicles
        ATS_DEBUG 'diag_log ["ATS",_class,"Speed",getNumber(_cfg >> "maxSpeed"),"ArtyScanner",getNumber(_cfg >> "artilleryScanner")]';
        if (getNumber (_cfg >> "maxSpeed") >= 15 && {getNumber (_cfg >> "artilleryScanner") == 0}) then {
            private _turrets = false;
            private _transportSeats = getNumber (_cfg >> "transportSoldier");
            private _fnc_turretsFFV = 
                {
                    {
                        private _tmags = getArray (_x >> "Magazines");
                        if (getText (_x >> "gun") != "" && {!(_tmags isEqualTo []) && {!("waterCannonMagazine_RF" in _tmags)}}) then {
                            ATS_DEBUG 'diag_log ["gun",getText (_x >> "gun")]';
                            {
                                if (_x isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]) then {continue};
                                private _cfgMag = configFile >> "CfgMagazines" >> _x;
                                private _magCount = getNumber (_cfgMag >> "count");
                                private _ammo = getText (_cfgMag >> "ammo");
                                if ((["FlareCore","SmokeShell","SmokeLauncherAmmo","CMflareAmmo"] findIf {_ammo isKindOf _x}) >=0 ) then {continue};
                                ATS_DEBUG 'diag_log ["ammo",_ammo,_magCount,configName _cfgMag]';
                                if (true) exitWith {_turrets = true};
                            } forEach _tmags;
                        };
                        if (getNumber (_x >> "showAsCargo") > 0) then {_transportSeats = _transportSeats + 1};
                        if (isClass (_x >> "Turrets")) then {_x call _fnc_turretsFFV};
                    } forEach (configProperties [_this >> "Turrets","isClass _x",true]);
                };
                
            private _supportTypes = getArray (_cfg >> "availableForSupportTypes");
            if ("CAS_Bombing" in _supportTypes || {"CAS_Heli" in _supportTypes}) then {_turrets = true};
            
            _cfg call _fnc_turretsFFV; 
            
            // need to check the pylons as well
            if (!_turrets) then {
                private _pylonConfig = _cfg >> "Components" >> "TransportPylonsComponent" >> "Pylons";
                {
                    private _pylonMag = getText (_x >> "attachment"); 
                    if !(_pylonMag isEqualTo "") then {
                        if (_pylonMag isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]) then {continue};
                        private _cfgMag = configFile >> "CfgMagazines" >> _pylonMag;
                        private _magCount = getNumber (_cfgMag >> "count");
                        private _ammo = getText (_cfgMag >> "ammo");
                        if ((["FlareCore","SmokeShell","SmokeLauncherAmmo","CMflareAmmo"] findIf {_ammo isKindOf _x}) >=0 ) then {continue};
                        ATS_DEBUG 'diag_log ["pylon ammo",_ammo,_magCount,configName _cfgMag]';
                        if (true) exitWith {_turrets = true};
                    };
                } forEach (configProperties [_pylonConfig, "isClass _x"]);
            };
            
            // some vehicles in mods get defined with a weapon instead
            if (!_turrets) then {
                private _vmags = getArray (_cfg >> "Magazines");
                if (!(_vmags isEqualTo []) && {!("waterCannonMagazine_RF" in _vmags)}) then {
                    {
                        if (_x isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]) then {continue};
                        private _cfgMag = configFile >> "CfgMagazines" >> _x;
                        private _magCount = getNumber (_cfgMag >> "count");
                        private _ammo = getText (_cfgMag >> "ammo");
                        if ((["FlareCore","SmokeShell","SmokeLauncherAmmo","CMflareAmmo"] findIf {_ammo isKindOf _x}) >=0 ) then {continue};
                        ATS_DEBUG 'diag_log ["weapon mag ammo",_ammo,_magCount,configName _cfgMag]';
                        if (true) exitWith {_turrets = true};
                    } forEach _vmags;
                };
            };
            
            ATS_DEBUG 'diag_log ["ATS",_class,"Seats",_transportSeats,"Turrets",_turrets,"----------------"]';
            if (_turrets) then {
                if (_transportSeats >= _minCargoSeats) then {
                    _dual pushBack _vehType;
                    // now choose a dual with the most seats in case we need it
                    _dualAsTransportVar = (_varArray select [2]) + "DualAsTransport";
                    if (!isNil _dualAsTransportVar) then {
                        private _dualAsTransport = call compile _dualAsTransportVar;
                        if (_transportSeats == (_dualAsTransport#1)) then {
                            (_dualAsTransport#0) pushBackUnique _vehType;
                        } else {
                            if (_transportSeats > (_dualAsTransport#1)) then {
                                _dualAsTransport set [0,[_vehType]];
                                _dualAsTransport set [1,_transportSeats];
                            };
                        };
                    };
                } else {_attack pushBack _vehType};
            } else {
                if (_transportSeats >= _minCargoSeats) then {_transport pushBack _vehType};
            };  
        };
        false
    } count _array;
    call compile format ["%1Attack = _attack;%1Transport = _transport;%1Dual = _dual",_varArray];
};

{
    [_x,MIN_CARGO_SEATS_FOR_TRANSPORT] call _fnAttackTransportSplit;
    if (call compile format ["%1Transport isEqualTo []",_x]) then {
        [_x,MIN_ABS_CARGO_SEATS_FOR_TRANSPORT] call _fnAttackTransportSplit;
    };
} forEach ["va_pCarClasses","va_pTankClasses","va_pApcClasses","va_pHeliClasses","va_pPlaneClasses","va_pShipClasses",
           "va_eCarClasses","va_eTankClasses","va_eApcClasses","va_eHeliClasses","va_ePlaneClasses","va_eShipClasses",
           "va_cCarClasses","va_cHeliClasses","va_cPlaneClasses","va_cShipClasses"];

// we need to split uav/ugv into large/small
//#define UAV_DEBUG call compile
#define UAV_DEBUG comment 
{
    private _varArray = _x;
    private _array = call compile _varArray;
    private _attack = [];
    private _attackSmall = [];
    private _unarmed = [];
    {        		
        private _vehType = _x;
        private _class = if (typeName _vehType isEqualTo "STRING") then {_vehType} else {_vehType#0};
        
        // don't allow Warhammer 4k drop pods
        if (_class select [0,13] isEqualTo "TIOW_Drop_Pod") then {continue};
        
        private _cfg = configFile >> "CfgVehicles" >> _class;
        
        // minimum speed requirement of 15 kph && don't use artillery vehicles
        if (getNumber (_cfg >> "maxSpeed") >= 10 && {getNumber (_cfg >> "artilleryScanner") == 0}) then {
            private _large = false; // large attack uav
            private _small = false; // small attack uav
            
            
            private _fnc_magsCheck = {
                {
                    // first handle special cases
                    if (_x isKindOf ["Laserbatteries",configFile >> "cfgMagazines"]) then {continue};
                    if ([_x,"Probing"] call ITW_FncStartsWith) then {continue};
                    private _cfgMag = configFile >> "CfgMagazines" >> _x;
                    private _magCount = getNumber (_cfgMag >> "count");
                    private _ammo = getText (_cfgMag >> "ammo");
                    if ({_ammo isKindOf _x} count ["FlareCore","SmokeShell"] > 0) then {continue};
                    private _cfgAmmo = configFile >> "CfgAmmo" >> _ammo;
                    private _hit = getNumber (_cfgAmmo >> "hit");
                    private _hitPerMag = _magCount * _hit;
                    if (_hitPerMag > 600) then {
                    UAV_DEBUG 'diag_log ["mag LARGE",_hitPerMag,_magCount,_hit,_ammo]';
                        _large = true;
                    } else {
                        if (_hitPerMag >= 10) then {
                            _small = true;
                        };
                        UAV_DEBUG 'if (_hitPerMag >= 10) then {["mag SMALL",_hitPerMag,_magCount,_hit,_ammo];}else {diag_log ["mag NONE",_x,_hitPerMag,_magCount,_hit,_ammo]}';
                    };
                } forEach _this;
            };
            private _fnc_turretsFFV = {
                {
                    private _tmags = getArray (_x >> "Magazines");
                    if (getText (_x >> "gun") select [0,4] == "main" && {!(_tmags isEqualTo []) && {!("waterCannonMagazine_RF" in _tmags)}}) then {
                        _tmags call _fnc_magsCheck;
                    };
                    if (isClass (_x >> "Turrets")) then {_x call _fnc_turretsFFV};
                } forEach (configProperties [_this >> "Turrets","isClass _x",true]);
            };
            _cfg call _fnc_turretsFFV;
            
            if (!_large && !_small) then {
                UAV_DEBUG 'diag_log ["UavMagCheck",getArray (_cfg >> "Magazines")]';
                (getArray (_cfg >> "Magazines")) call _fnc_magsCheck;
            };
            
            // now handle special cases
            if ([_class,"_HE_RF"] call ITW_FncEndsWith) then {_small = true}; // reaction forces HE grenade uav
            
            private _mapSize = getNumber(_cfg>>"mapSize");
            UAV_DEBUG 'diag_log ["Ammo large",_large,_small]';                     
            UAV_DEBUG 'diag_log ["Map large",_mapSize > 0 && {_mapSize >4},"map small",_large && {_mapSize > 0 && {_mapSize <= 4}}]';
            if (_large && {_mapSize > 0 && {_mapSize <= 4}}) then {_small = true; _large = false};
            if (_mapSize > 4) then {_large = true};
  
            UAV_DEBUG 'diag_log ["--VEH UAV--",getText (_cfg >> "displayName"),_large,_small,_class]';
            if (_large) then {_attack pushBack _vehType} else {
                if (_small) then {_attackSmall pushBack _vehType} else {
                    _unarmed pushBack _vehType;
                };
            };  
        };
        false
    } count _array;
    call compile format ["%1Attack=_attack; %1AttackSmall=_attackSmall; %1Unarmed=_unarmed",_varArray];
} forEach ["va_pUavClasses","va_eUavClasses"];

// we really want transports, so look for smaller ones if needed
for "_i" from (MIN_ABS_CARGO_SEATS_FOR_TRANSPORT-1) to 1 step -1 do {
    private _pEmpty = va_pCarClassesTransport isEqualTo [];
    private _eEmpty = va_eCarClassesTransport isEqualTo [];
    if (!_pEmpty && !_eEmpty) exitWith {};
    if (_pEmpty) then {["va_pCarClasses",_i] call _fnAttackTransportSplit};
    if (_eEmpty) then {["va_eCarClasses",_i] call _fnAttackTransportSplit};
};
for "_i" from (MIN_ABS_CARGO_SEATS_FOR_TRANSPORT-1) to 3 step -1 do {
    private _pEmpty = va_pHeliClassesTransport isEqualTo [];
    private _eEmpty = va_eHeliClassesTransport isEqualTo [];
    if (!_pEmpty && !_eEmpty) exitWith {};
    if (_pEmpty) then {["va_pHeliClasses",_i] call _fnAttackTransportSplit};
    if (_eEmpty) then {["va_eHeliClasses",_i] call _fnAttackTransportSplit};
};

// if no transports, we allow some dual versions to act as transports by removing their ammo
// these 'dualAsTransport' classes are the dual's with the most seats
va_pCarDualAsTransport  = _pCarClassesDualAsTransport #0;
va_eCarDualAsTransport  = _eCarClassesDualAsTransport #0;
va_pHeliDualAsTransport = _pHeliClassesDualAsTransport#0;
va_eHeliDualAsTransport = _eHeliClassesDualAsTransport#0;


// special version (fallback) of civilian transports that can get cleared if player asked for none of this type
if (ITW_ParamCivilianVehicleFallback == 0) then {
    va_cPlaneClassesTransportFallback = [];
    va_cHeliClassesTransportFallback  = [];
    va_cCarClassesTransportFallback   = [];
    va_cShipClassesTransportFallback  = [];
} else {
    va_cPlaneClassesTransportFallback = va_cPlaneClassesTransport;
    va_cHeliClassesTransportFallback  = va_cHeliClassesTransport;
    va_cCarClassesTransportFallback   = va_cCarClassesTransport;
    va_cShipClassesTransportFallback  = va_cShipClassesTransport;
};

// remove types player doesn't want
if (ITW_ParamTransportPlaneSpawnAdjustment == 0) then {va_pPlaneClassesTransport = [];va_ePlaneClassesTransport = [];va_cPlaneClassesTransportFallback = []};
if (ITW_ParamTransportHeliSpawnAdjustment  == 0) then {va_pHeliClassesTransport  = [];va_eHeliClassesTransport  = [];va_cHeliClassesTransportFallback  = [];va_pHeliDualAsTransport = [];va_eHeliDualAsTransport = []};
if (ITW_ParamTransportTankSpawnAdjustment  == 0) then {va_pTankClassesTransport  = [];va_eTankClassesTransport  = []};
if (ITW_ParamTransportApcSpawnAdjustment   == 0) then {va_pApcClassesTransport   = [];va_eApcClassesTransport   = []};
if (ITW_ParamTransportCarSpawnAdjustment   == 0) then {va_pCarClassesTransport   = [];va_eCarClassesTransport   = [];va_cCarClassesTransportFallback   = [];va_pCarDualAsTransport = [];va_eCarDualAsTransport = []};
if (ITW_ParamTransportShipSpawnAdjustment  == 0) then {va_pShipClassesTransport  = [];va_eShipClassesTransport  = [];va_cShipClassesTransportFallback  = []};
if (ITW_ParamAttackPlaneSpawnAdjustment == 0) then {va_pPlaneClassesAttack = [];va_ePlaneClassesAttack = [];va_pPlaneClassesDual = [];va_ePlaneClassesDual = []};
if (ITW_ParamAttackHeliSpawnAdjustment  == 0) then {va_pHeliClassesAttack  = [];va_eHeliClassesAttack  = [];va_pHeliClassesDual  = [];va_eHeliClassesDual  = []};
if (ITW_ParamAttackTankSpawnAdjustment  == 0) then {va_pTankClassesAttack  = [];va_eTankClassesAttack  = [];va_pTankClassesDual  = [];va_eTankClassesDual  = []};
if (ITW_ParamAttackApcSpawnAdjustment   == 0) then {va_pApcClassesAttack   = [];va_eApcClassesAttack   = [];va_pApcClassesDual   = [];va_eApcClassesDual   = []};
if (ITW_ParamAttackCarSpawnAdjustment   == 0) then {va_pCarClassesAttack   = [];va_eCarClassesAttack   = [];va_pCarClassesDual   = [];va_eCarClassesDual   = []};
if (ITW_ParamAttackShipSpawnAdjustment  == 0) then {va_pShipClassesAttack  = [];va_eShipClassesAttack  = [];va_pShipClassesDual  = [];va_eShipClassesDual  = []};

// list of transports, so we can determine if dual can attack (since fallbacks are sometimes just transports)
va_TransportClasses = va_pPlaneClassesTransport + va_ePlaneClassesTransport + va_cPlaneClassesTransportFallback
                    + va_pHeliClassesTransport + va_eHeliClassesTransport + va_cHeliClassesTransportFallback
                    + va_pTankClassesTransport + va_eTankClassesTransport
                    + va_pApcClassesTransport + va_eApcClassesTransport
                    + va_pCarClassesTransport + va_eCarClassesTransport + va_cCarClassesTransportFallback
                    + va_pShipClassesTransport + va_eShipClassesTransport + va_cShipClassesTransportFallback;

if ("NoTrucks" in _options) then {
    {
        if (_x isKindOf "Truck_F") then {
            va_pCarTransportClasses = va_pCarTransportClasses - [_x];
        };
    } forEach va_pCarTransportClasses;
    {
        if (_x isKindOf "Truck_F") then {
            va_pCarClasses = va_pCarClasses - [_x];
        };
    } forEach va_pCarClasses;
    
    {
        if (_x isKindOf "Truck_F") then {
            va_eCarTransportClasses = va_eCarTransportClasses - [_x];
        };
    } forEach va_eCarTransportClasses;
    {
        if (_x isKindOf "Truck_F") then {
            va_eCarClasses = va_eCarClasses - [_x];
        };
    } forEach va_eCarClasses;
    
    {
        if (_x isKindOf "Truck_F") then {
            va_cCarClasses = va_cCarClasses - [_x];
        };
    } forEach va_cCarClasses;
};

if ("EnsureBoats" in _options) then {
    if (va_pShipClasses isEqualTo []) then {va_pShipClasses = [call CustomArsenal_GetBoat]};
    if (va_eShipClasses isEqualTo []) then {va_eShipClasses = [call CustomArsenal_GetBoat]};
};

// Get artillery types
#define MORTAR_DROP_MaxCnt     10
#define MORTAR_DROP_SpacingMin 1.5
va_pArtyAmmo = [["Sh_82mm_AMOS",MORTAR_DROP_MaxCnt,MORTAR_DROP_SpacingMin]]; // array of [ammo,dropCount,timeBetween]
va_eArtyAmmo = [["Sh_82mm_AMOS",MORTAR_DROP_MaxCnt,MORTAR_DROP_SpacingMin]];
if (ITW_ParamArtilleryType > 0) then {
    {
        private _artyClasses = _x;
        private _ammoClasses = [];
        {
            private _artyClass = _x;
            private _weapons = getArray (configFile >> "CfgVehicles" >> _artyClass >> "Turrets" >> "MainTurret" >> "weapons");
            if !(_weapons isEqualTo []) then {
                private _weaponCfg = configFile >> "cfgWeapons" >> (_weapons#0);
                private _reloadTime = getNumber (_weaponCfg >> "reloadTime");
                
                private _mags = getArray (configFile >> "CfgVehicles" >> _artyClass >> "Turrets" >> "MainTurret" >> "magazines");
                _mags = _mags arrayIntersect _mags;
                {
                    private _mag = _x;
                    private _magCfg = configFile >> "CfgMagazines" >> _mag;
                    private _magCnt = getNumber (_magCfg >> "count");
                    private _ammo = getText (_magCfg >> "ammo");
                    private _ammoCfg = configFile >> "CfgAmmo" >> _ammo;
                    private _coneType = getArray (_ammoCfg >> "submunitionConeType");
                    private _hit = getNumber (_ammoCfg >> "hit");
                    if (count _coneType > 1) then {
                        private _cnt = _coneType #1;
                        // check submunitions
                        private _fn_subMunitionHit = {
                            private _subCfg = _this;
                            private _subHit = 0;
                            private _submunition = (_subCfg >> "submunitionAmmo") call BIS_fnc_getCfgData;
                            if !(_submunition isEqualTo "" || {_submunition isEqualTo []}) then {
                                if (typeName _submunition == "STRING") then {_submunition = [_submunition,1]};
                                for "_i" from 0 to (count _submunition - 1) step 2 do {
                                    private _hit = (configFile >> "cfgAmmo" >> (_submunition#_i)) call _fn_subMunitionHit;
                                    private _subVar = _submunition#(_i+1);
                                    _subHit = _subHit + (_subVar * _hit);
                                };
                            } else {
                                _subHit = getNumber (_subCfg >> "hit");
                            };
                            _subHit
                        };
                        
                        _hit = (_ammoCfg call _fn_subMunitionHit) * _cnt;
                    };
                    if (_hit < 50) then {continue};
                    private _guided = getNumber (_ammoCfg >> "autoSeekTarget");
                    if (_guided == 1) then {continue};
                    _ammoClasses pushBack [_ammo,_magCnt,_reloadTime];
                } forEach _mags;
            };
        } forEach _artyClasses;
        //_ammoClasses = _ammoClasses arrayIntersect _ammoClasses;
        if (_ammoClasses isNotEqualTo []) then {
            if (_forEachIndex == 0) then {va_pArtyAmmo = _ammoClasses} else {va_eArtyAmmo = _ammoClasses};
        };
    } forEach [va_pArtyClasses,va_eArtyClasses];
};

// C.L.A.S.H. capability export seam. Impasse remains the owner of faction
// discovery; Checkbook consumes immutable snapshots after this file releases
// several enemy support arrays during its normal cleanup.
ITW_CLASH_PlayerArtilleryClasses = +va_pArtyClasses;
ITW_CLASH_EnemyArtilleryClasses = +va_eArtyClasses;
ITW_CLASH_PlayerAmmoClasses = +va_pAmmoClasses;
ITW_CLASH_EnemyAmmoClasses = +va_eAmmoClasses;
ITW_CLASH_PlayerFuelClasses = +va_pFuelClasses;
ITW_CLASH_EnemyFuelClasses = +va_eFuelClasses;
ITW_CLASH_PlayerRepairClasses = +va_pRepairClasses;
ITW_CLASH_EnemyRepairClasses = +va_eRepairClasses;
ITW_CLASH_PlayerAmmoHeloClasses = va_pHeliClasses select {
    private _class = if (_x isEqualType []) then {_x#0} else {_x};
    private _cfg = configFile >> "CfgVehicles" >> _class;
    getNumber (_cfg >> "transportAmmo") > 100
    || {getNumber (_cfg >> "slingLoadMaxCargoMass") > 0}
};
ITW_CLASH_EnemyAmmoHeloClasses = va_eHeliClasses select {
    private _class = if (_x isEqualType []) then {_x#0} else {_x};
    private _cfg = configFile >> "CfgVehicles" >> _class;
    getNumber (_cfg >> "transportAmmo") > 100
    || {getNumber (_cfg >> "slingLoadMaxCargoMass") > 0}
};
ITW_CLASH_CapabilityPoolsReady = true;

VEHICLE_ARRAYS_COMPLETE = true;

// clean up arrays not used in this mission

va_airports = nil;  //airports array in form [ilsPosition,ilsDirection,ilsTaxiOff,ilsTaxiIn] (see Arma_3_Dynamic_Airport_Configuration)

va_pOfficerClasses = nil;
va_pGenericNames = nil;
va_pLanguage = nil;
//va_pUAVClasses = nil;
va_pInfClassesForWeights = nil;
va_pInfClassWeights = nil;

va_eOfficerClasses = nil;
va_eFuelClasses = nil;
va_eRepairClasses = nil;
va_eAmmoClasses = nil;
va_eGenericNames = nil;
va_eLanguage = nil;
va_eInfClassesForWeights = nil;
va_eInfClassWeights = nil;
va_eSubmarineClasses = nil;

va_cOfficerClasses = nil;
//va_cCarClasses = nil;
va_cQuadBikeClasses = nil;
va_cGenericNames = nil;
va_cLanguage = nil;
va_cUAVClasses = nil;
va_cSubmarineClasses = nil;
diag_log "Vehicle Arrays Processing Complete";

ITW_DebugListVehs = {
    {
        private _newWho = true;
        private _who = _x ;
        {
            private _newVeh = true;
            private _veh = _x;
            private _unassigned = +(call compile ("va_" + (_who select [0,1]) + _veh + "Classes"));
            {
                private _newType = true;
                private _type = _x;
                private _var = call compile ("va_" + (_who select [0,1]) + _veh + "Classes" + _type);
                if (_type == "Transport" && {_var isEqualTo []}) then {
                    private _varName = "va_" + (_who select [0,1]) + _veh + "DualAsTransport";
                    if (!isNil _varName) then {
                        _var = call compile _varName;
                        _type = "Transport (dual w/o ammo)"
                    };
                };
                _unassigned = _unassigned - _var;
                {
                    private _vehClass = if (typeName _x == "ARRAY") then {_x#0} else {_x};
                    if (_newWho)  then {_newWho = false;  diag_log _who};
                    if (_newVeh)  then {_newVeh = false;  diag_log ("  " + _veh)};
                    if (_newType) then {_newType = false; diag_log ("    " + _type)};                
                    diag_log format ["      %1 (%2)",getText (configFile >> "cfgVehicles" >> _vehClass >> "displayName"),_vehClass];
                } forEach _var;
            } forEach ["Attack","Dual","Transport"];
            _newType = true;
            {
                private _vehClass = if (typeName _x == "ARRAY") then {_x#0} else {_x};
                if (_newWho)  then {_newWho = false;  diag_log _who};
                if (_newVeh)  then {_newVeh = false;  diag_log ("  " + _veh)};
                if (_newType) then {_newType = false; diag_log ("    Unassigned")};
                diag_log format ["      %1 (%2)",getText (configFile >> "cfgVehicles" >> _vehClass >> "displayName"),_vehClass];
            } forEach _unassigned;
        } forEach ["Tank","Apc","Car","Heli","Plane","Ship"];
        {
            private _newVeh = true;
            private _veh = _x;
            private _unassigned = +(call compile ("va_" + (_who select [0,1]) + _veh + "Classes"));
            {
                private _newType = true;
                private _type = _x;
                private _var = call compile ("va_" + (_who select [0,1]) + _veh + "Classes" + _type);
                _unassigned = _unassigned - _var;
                {
                    private _vehClass = if (typeName _x == "ARRAY") then {_x#0} else {_x};
                    if (_newWho)  then {_newWho = false;  diag_log _who};
                    if (_newVeh)  then {_newVeh = false;  diag_log ("  " + _veh)};
                    if (_newType) then {_newType = false; diag_log ("    " + _type)};                
                    diag_log format ["      %1 (%2)",getText (configFile >> "cfgVehicles" >> _vehClass >> "displayName"),_vehClass];
                } forEach _var;
            } forEach ["Attack","AttackSmall","Unarmed"];
            _newType = true;
            {
                private _vehClass = if (typeName _x == "ARRAY") then {_x#0} else {_x};
                if (_newWho)  then {_newWho = false;  diag_log _who};
                if (_newVeh)  then {_newVeh = false;  diag_log ("  " + _veh)};
                if (_newType) then {_newType = false; diag_log ("    Unassigned")};
                diag_log format ["      %1 (%2)",getText (configFile >> "cfgVehicles" >> _vehClass >> "displayName"),_vehClass];
            } forEach _unassigned;
        } forEach ["Uav"];
        
        {
            private _newVeh = true;
            private _veh = _x;
            private _var = call compile ("va_" + (_who select [0,1]) + _veh + "Classes");
            {
                private _vehClass = if (typeName _x == "ARRAY") then {_x#0} else {_x};
                if (_newWho)  then {_newWho = false;  diag_log _who};
                if (_newVeh)  then {_newVeh = false;  diag_log ("  " + _veh)};
                diag_log format ["      %1 (%2)",getText (configFile >> "cfgVehicles" >> _vehClass >> "displayName"),_vehClass];
            } forEach _var;
        } forEach ["Static"];
    } forEach ["Player","Enemy"];
};
["ITW_DebugListVehs"] call SKL_fnc_CompileFinal;
