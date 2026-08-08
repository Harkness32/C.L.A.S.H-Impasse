#include "defines.hpp"

// Including Instructions:
// To include faction is a mission do the following:
// 1. add a symlink of the skullscripts/Factions directory to /scripts/Factions in your mission
// 2. add to the top of the description.ext:  #include "scripts\Factions\display.hpp"
//    Note that this includes a few Rsc items (text,checkbox,listbox,button) which may make ones
//    already included in your mission redundant.  Remove the ones from your mission if error appear.
// 3. In initPlayerLocal.sqf and initServer.sqf add this line (or add in preInit if available):
//      isNil {call compile preprocessFileLineNumbers "scripts\Factions\Factions.sqf";  }; 
// 4. To have the player select factions, call FactionSelect on the server:
//    You can supply the initial selections as well as which player should choose (default host)
//    The _defFactionsC is optional as is _showCiv 
//   
//    if (isServer) then {
//        west setFriend [resistance,0];
//        resistance setFriend [west,0];
//        
//        private _defFactionsP = profileNamespace getVariable [format["INS_FactionsP%1",worldName],[]];
//        private _defFactionsE = profileNamespace getVariable [format["INS_FactionsE%1",worldName],[]];
//        private _defFactionsC = profileNamespace getVariable [format["INS_FactionsC%1",worldName],[]];
//        private _checkBoxes   = profileNamespace getVariable [format["INS_FactionsCkBox%1",worldName],[true,false,false]];
//        
//        _factionInfo = [_defFactionsP,_defFactionsE,objNull,_defFactionsC,true,_checkBoxes] call FactionSelect;
//        
//        profileNamespace setVariable [format["INS_FactionsP%1",worldName],_factionInfo#0];
//        profileNamespace setVariable [format["INS_FactionsE%1",worldName],_factionInfo#1];
//        profileNamespace setVariable [format["INS_FactionsC%1",worldName],_factionInfo#2];
//        profileNamespace setVariable [format["INS_FactionsCkBox%1",worldName],call FactionGetCheckBoxStates];
//        
//        INS_PlayerFaction = _factionInfo#0;
//        INS_EnemyFaction  = _factionInfo#1;
//        INS_CivFaction    = _factionInfo#2;
//        INS_EnemySide     = _factionInfo#3;
//        INS_FactionMultiIsAll = _factionInfo#4;
//        
//        publicVariable "INS_FactionMultiIsAll";
//        publicVariable "INS_EnemySide";
//        publicVariable "INS_PlayerFaction";
//        publicVariable "INS_CivFaction";
//        publicVariable "INS_EnemyFaction";
//    } else {
//        waitUntil {!isNil "INS_EnemySide"};
//        waitUntil {!isNil "INS_PlayerFaction"};
//        waitUntil {!isNil "INS_EnemyFaction"};
//    };
//
//    You can get the map defaults if needed with ["player"] call FactionSelection_Defaults
//        or ["enemy"] call FactionSelection_Defaults
//        or ["civilian"] call FactionSelection_Defaults
//
// 5. If you want to access the Faction functions before calling FactionSelect (above) then add this call
//    first:    [false] call FactionSelection_CollectFactions;   this will collect the faction info ahead of time
//
// 6. Optionally you can change the random button in the arsenal to choose randomly from the faction by
//    adding an arsenal opened event handler
//
//      [missionNamespace, "arsenalOpened", {
//          // Change the 'random' button to a 'faction' button
//          private _ctrlButtonRandom = _display displayCtrl IDC_RSCDISPLAYARSENAL_CONTROLSBAR_BUTTONRANDOM;
//          //_ctrlButtonRandom ctrlSetText "FACTION";
//          _ctrlButtonRandom ctrlRemoveAllEventHandlers "buttonclick"; 
//          _ctrlButtonRandom ctrlAddEventHandler ["buttonclick",
//              {
//                  [player] spawn FactionLoadout;                        
//              }];
//          _ctrlButtonRandom ctrlEnable true; 
//          _ctrlButtonRandom ctrlSetTooltip "Reset loadout to a random unit from your faction";
//      }] call BIS_fnc_addScriptedEventHandler;
//
//    Where FactionLoadout is something like:
//      #include "\a3\ui_f\hpp\defineResinclDesign.inc"
//      FactionLoadout = {
//          params ["_unit",["_faction",INS_PlayerFaction]];//      
//          // switch the unit to a random player faction loadout
//          _switchLoadout = {
//              params ["_unit","_faction"];
//              private _unitClassesWieghted = [_faction,
//                     ["Rifleman",5,"CombatLifeSaver",1,"Grenadier",1,"MachineGunner",1,"Marksman",1]
//                  ] call FactionUnits;
//              // weed out units w/o primary weapon
//              private _cnt = 10;
//              private _unitClass = "";
//              private _loadout = [[]];
//              while {_unitClass == "" && _loadout#0 isEqualTo [] && _cnt > 0} do {
//                  _unitClass = selectRandom selectRandomWeighted _unitClassesWieghted;
//                  if (isNil "_unitClass") then {_unitClass = "B_Soldier_F"};
//                  _loadout = getUnitLoadout _unitClass;
//              };
//              _unit setUnitLoadout _loadout;
//              _unit setVariable ["LoadoutClass",_unitClass];    
//          };
//          [_unit,_faction] call _switchLoadout;
//      };
//
// 7. Other functions you can call:
//      [faction] call FactionUnits        - returns an array of the units in the faction, [] if unknown faction  
//      [faction, roles] call FactionUnits - returns an array of the units in the faction with the 
//                                           given roles.  Roles can be a weighted array. Empty array if unknown faction; 
//      [[faction1,...]] call FactionCheck - checks if the supplied factions are valid, returns false if any don't exist
//      [faction] call FactionRoles        - returns an array of the roles available in the faction
//      [faction] call FactionSide         - returns the side of the given faction.  sideUnknown if unknown faction.
//      [faction] call FactionSideNum      - returns the number of the given faction.  4 if unknown faction.
//      [faction] call FactionName         - returns the display name of the faction.
//      [faction] call FactionFlag         - returns the flag texture for the faction.
//      [text] call FactionSetOkayBtnText  - sets the button on the screen to 'text'. It defaults to 
//                                           'Start Mission' if not changed.  Call this before FactionSelect.
//      [mapname] call FactionDlcId        - returns [_onlyDlcs,_removeDlcs] based on the current map or faction
//                                           where 'onlyDlcs' are the dlc that this map uses and
//                                           'removeDlcs' are dlc to remove when using this map.
//                                           'removeDlcs' is only valid if 'onlyDlcs' is empty.
//                                           not supplying mapname will use the worldName (current map)
//      [factionSide,UnitArray] call FactionSanitizeCivilians - this will remove all weapons from civilians and is necessary
//                                           if a non-civilian faction was chosen.  unitArray is an array of unit objects.
//                                           factionSide, if not civilian, will cause vests and such to be removed as well
//      [faction] call FactionGetCheckBoxStates - returns array of the states of the checkboxes as [perMap,showSubFactions]
//      faction call FactionBase            - return the base faction:  So BLU_F:2 becomes BLU_F
//
// 8. Sub factions can be used as well.  The sub factions are referenced using faction name + colon + index (ex. "BLU_F:0")
//
// 9. Individual units can also be selected into a 'custom' faction.  The faction definition will begin with 'CUSTOM' and a random number
//    followed by a vertical bar for the faction/subfaction and then the unit numbers
//    ex: Nato/Men with a few units: ["'CUSTOM'760|BLU_F:0;25,26,27,28,29,"]
//    ex: Nato with a few units:     ["'CUSTOM'3613|BLU_F;65,66,67,68,"]
//
// 10. Faction data is available.  It is an array of all factions being used (either all factions or 
//    only the ones for the current map as choosen by the player).
// 
//    Faction Data is in the form [[Faction, FactionName, FactionFlag, SideNum, [[subFaction,[[unitClass,role]...],...]], CustomFactionDef]]

#define FACTION_DEBUG(fnc) //diag_log format["%1 %2",fnc,_this]

FactionSelect = {
    FACTION_DEBUG("FactionSelect");
    params [["_initialFactionsP",[]],["_initialFactionsE",[]],["_playerToChoose",objNull],["_initialFactionsC",[]],["_showCivList",false],["_checkBoxes",[true,false,false]],["_playerIsCiv",false]]; 
    // _limitDLC is true to only allow DLCs based on the current map
    //                    or it can be an array of dlc, appid, or authors to use
    // _initialFactionsP: array of default player faction class names, 
    //                    more than one for choosing randomly between them, empty for world defaults
    // _initialFactionsE: array of default enemy faction class names
    //                    more than one for choosing randomly between them, empty for world defaults
    //_playerToChoose:    which player will choose the faction, if objNull, then it will be host or a
    //                    (call BIS_fnc_listPlayers)#0;
    // _initialFactionsC: array of default civilian faction class names
    //                    more than one for choosing randomly between them, empty for world defaults
    // _showCivList:      if set to TRUE, the civilian list will be shown
    // _checkBoxes:       array of default checkbox state [
    //                          _perMap: 'show factions applicable for this map' checkbox checked (default: true)
    //                          _subFactions: subFactions checkbox checked (default: false)
    //                          _multiIsAll: multiselect will use all, unchecked: it will randomly use one
    //                    ]
    // _playerIsCiv:      will show only civilian factions in player slot (don't _showCivList when using this)
    // 
    //
    // returns [ArrayOfSelectedPlayerFactions, ArrayOfSelectedEnemyFactions, ArrayOfSelectedCivFactions, enemySideNum, multiIsAll]
    //         If player wasn't given option to choose civ faction, then ["CIV_F"] will be returned as the civ faction
    
    // call on server only
    if (! isServer) exitWith { diag_log "Error: FactionSelect called from non-server"; };
    
    if !(typeName _checkBoxes == "ARRAY") then {_checkBoxes = [_checkBoxes,false,false]};
    
    missionNamespace setVariable ["FACTION_DONE", false, true];
        
    // server need to report all the available factions to the clients since the client might have more dlc/maps
    [false] call FactionSelection_CollectFactions;
    
    _initialFactionsP call FactionUnits_Check;
    _initialFactionsE call FactionUnits_Check;
    _initialFactionsC call FactionUnits_Check;

    FactionsAllowed = [];
    {
        FactionsAllowed pushBack (_x#0);
    } forEach FactionData;   
    publicVariable "FactionsAllowed";
    missionNamespace setVariable ["FACTION_SELECTED",nil];
    
    if (isNull _playerToChoose) then {
        if (isDedicated) then {        
            // if using a dedicated server, use a the first player to choose faction
            waitUntil {count (call BIS_fnc_listPlayers) > 0};
            private _playerClient = owner ((call BIS_fnc_listPlayers)#0);
            [] remoteExec ["FactionSelection_Wait",-(_playerClient),true];
            [_initialFactionsP,_initialFactionsE,_initialFactionsC,_showCivList,_playerIsCiv,_checkBoxes] remoteExec ["FactionSelection_Start",_playerClient];
        } else {
            // hosted server, so just let the host choose faction
            [] remoteExec ["FactionSelection_Wait",-2,true];
            [_initialFactionsP,_initialFactionsE,_initialFactionsC,_showCivList,_playerIsCiv,_checkBoxes] call FactionSelection_Start;
        };
    } else {
        [] remoteExec ["FactionSelection_Wait",-(owner _playerToChoose),true];
        [_initialFactionsP,_initialFactionsE,_initialFactionsC,_showCivList,_playerIsCiv,_checkBoxes] remoteExec ["FactionSelection_Start",_playerToChoose];
    };
    
    waitUntil {sleep 0.5; missionNamespace getVariable ["FACTION_DONE",false]};
      
    private _result = [];
    private _timeout = time + 10;
    waitUntil {_result = missionNamespace getVariable ["FACTION_SELECTED",[]]; !(_result isEqualTo []) || {time > _timeout}};
    
    if (_result isEqualTo []) then {
        private _factionData = call Factions_GetData;
        _result = [_factionData#0,_factionData#1,["CIV_F"],[_factionData#1] call FactionSideNum,false];   
        diag_log "Factions: Error Pos: user selected faction not present on the server.  Mod mismamatch?";
    };
    
    _result
};

FactionRoles = {
    FACTION_DEBUG("FactionRoles");
    params ["_faction"];
    // given a faction name, return the roles available
    
    if (typeName _faction == "ARRAY") exitWith {
        private _roles = [];
        {
            _roles append ([_x] call FactionRoles);
        } forEach _faction;
        _roles
    };
   
    _faction = _faction call FactionUnits_Check;
    private _subIndex = _faction call Faction_SubIndex;
    
    //private _factionName = toUpperANSI (_factionParts#0);
    private _roles = [];
        
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR: FactionRoles called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
        _roles
    };
    private _roles = [];
    private _idx = [_factionData,_faction] call Faction_FindKey;
    if (_idx >= 0) then {
        private _subFactionsData = _factionData#_idx#4;
        if (_subIndex < 0 || {_subIndex >= count _subFactionsData}) then {
            {
                {
                    _roles pushBackUnique (_x#1);
                } forEach _x#1;
            } forEach _subFactionsData;
        } else {
            {
                _roles pushBackUnique (_x#1);
            } forEach (_subFactionsData#_subIndex#1);
        };
    };
    
    _roles
};

// The Faction unit fallback is an array showing the order to attempt to find units if the request returns []
// 0 or empty = return the empty array 
// 1 = return either BLU_F, OPF_F, IND_F, or CIV_F units for the same side WITHOUT role request 2(will always return something)
// 1.1 = search BLU_F units WITHOUT role request
// 1.2 = search OPF_F units WITHOUT role request
// 1.3 = search IND_F units WITHOUT role request
// 1.4 = search CIV_F units WITHOUT role request
// 2 = search either BLU_F, OPF_F, IND_F, or CIV_F units for the same side using the same role request
// 2.1 = search BLU_F units using the same role request
// 2.2 = search OPF_F units using the same role request
// 2.3 = search IND_F units using the same role request
// 2.4 = search CIV_F units using the same role request
// 3 = search the BASE faction WITHOUT the role requirements
// 4 = search the BASE faction using the same role request
// 5 = search the SUBFaction WITHOUT the role requirements
// all searches start with SUBFaction using role request
FACTION_UNIT_FALLBACK_NONE     = compileFinal "[]";
FACTION_UNIT_FALLBACK_SUBF     = compileFinal "[5,4,3,2,1]";
FACTION_UNIT_FALLBACK_SUBF_BLU = compileFinal "[5,4,3,2.1,1.1]";
FACTION_UNIT_FALLBACK_SUBF_OPF = compileFinal "[5,4,3,2.2,1.2]";
FACTION_UNIT_FALLBACK_SUBF_IND = compileFinal "[5,4,3,2.3,1.3]";
FACTION_UNIT_FALLBACK_SUBF_CIV = compileFinal "[5,4,3,2.4,1.4]";
FACTION_UNIT_FALLBACK_ROLE     = compileFinal "[4,5,3,2,1]";
FACTION_UNIT_FALLBACK_ROLE_BLU = compileFinal "[4,5,3,2.1,1.1]";
FACTION_UNIT_FALLBACK_ROLE_OPF = compileFinal "[4,5,3,2.2,1.2]";
FACTION_UNIT_FALLBACK_ROLE_IND = compileFinal "[4,5,3,2.3,1.3]";
FACTION_UNIT_FALLBACK_ROLE_CIV = compileFinal "[4,5,3,2.4,1.4]";
FACTION_UNIT_FALLBACK_ROLE_REQ = compileFinal "[4]";

FactionUnits = {
    FACTION_DEBUG("FactionUnits");
    params ["_faction",["_roles",[]],["_rolesIsInverted",false],["_fallback",call FACTION_UNIT_FALLBACK_SUBF]];
    // given a faction or array of factions, and a list of roles, return the units that fit those roles
    // _roles can be an array of strings: ["rifleman","Autorifleman","Marksman"]
    //            which will return an array of classes ["B_soldier_AR_F","B_Soldier_SL_F",...]
    //        or a weighted array: [role1,wt,role2,wt]...   ex ["B_soldier_AR_F",5,B_Soldier_SL_F",2,...]
    //            which will return an array designed for selectRandomWeighted [[unit1,unit2,...],wt,[unit3,...],wt,...
    //            to select an random weighted unit use  "selectRandom selectRandomWeighted _returnValue"
    //        or an empty array to return all units in a flat array
    //        Roles are ignored for civilian classes
    // _rolesIsInverted: if this is true, then roles will be a list of roles to NOT allow.
    // _fallback: how to behave if the requested faction/role returns no units
    //
    // ROLES: (others may exists, but at the time of writing these were in base arma + DLCs)
    //   "Assistant"
    //   "CombatLifeSaver"
    //   "Crewman"
    //   "Grenadier"
    //   "MachineGunner"
    //   "Marksman"
    //   "MissileSpecialist"
    //   "Officer"
    //   "RadioOperator"
    //   "Rifleman"
    //   "Sapper"
    //   "SpecialOperative"
    //   "SquadLeader"
    //   "Flamethrower"
    //   "Diver"         // diver role will only show up if specifically asked for
    //
    // Civilian factions will have role "unarmed"
    
    if (typeName _faction == "ARRAY") exitWith {
        private _fallbackSequence = [[0]];
        {
            _fallbackSequence pushBack [_x];
        } forEach _fallback;
        private _units = [];
        {
            if (_units isEqualTo []) then {
                private _arrayFallback = _x;
                {       
                    private _fact = _x;
                    _units append ([_fact,_roles,_rolesIsInverted,_arrayFallback] call FactionUnits);
                } forEach _faction;
            };
         } forEach _fallbackSequence;  
        _units
    };
    
    _faction = _faction call FactionUnits_Check;
    
    private _factionUnits = {
        params ["_faction",["_roles",[]],["_rolesIsInverted",false]];
        private _units = [];
        private _allowDivers = !_rolesIsInverted && {'diver' in _roles};
        private _subIndex = _faction call Faction_SubIndex;
        private _factionParts = _faction splitString ":";
        _faction = toUpperANSI (_factionParts#0);
        
        private _factionData = call Factions_GetData;
        if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
            diag_log "ERROR: FactionUnits called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
            _units
        };
        
        private _isWeighted = false;
        private _allRoles = true;
        if (count _roles > 0) then {
            _allRoles = false;
            if (count _roles > 1) then {
                _isWeighted = typeName (_roles#1) == "SCALAR";
            };
        };
        
        private _roleWeighs = [];
        private _roleNames = [];
        if (_isWeighted) then {
            for "_i" from 0 to count _roles - 1 step 2 do {
                private _name = toLowerANSI(_roles#_i);
                private _wt = (_roles#(_i+1));
                _roleNames pushBack _name;
                _roleWeighs pushBack _wt;
                _units append [[],_wt];
            } forEach _roles;
        } else {
            {
                _roleNames pushBack toLowerANSI _x;
            } forEach _roles;        
        };
        
        private _idx = [_factionData,_faction] call Faction_FindKey;
        if (_idx < 0) exitWith {
            diag_log format ["ERROR: faction not found (%1)",_faction]; {diag_log (_x#0)} forEach _factionData;
            _units
        };
      
        if (_rolesIsInverted) then {_isWeighted = false};
        
        private "_unitsData";
        private _subFactionsData = _factionData#_idx#4;
        if (_subIndex < 0 || {_subIndex >= count _subFactionsData}) then {
            _unitsData = [];
            {
                _unitsData append (_x#1);
            } forEach _subFactionsData;
        } else {
            _unitsData = _subFactionsData#_subIndex#1;
        };
        
        {
            _x params ["_unit","_role"];
            private _roleFound = false;
            if (_allRoles) then {
                _roleFound = true;
            } else {
                _roleFound = _role in _roleNames;
            };
            if (!_allowDivers && {_role == 'diver'}) then {continue};
            
            if ((_roleFound && !_rolesIsInverted) || (!_roleFound && _rolesIsInverted)) then {
                if (_isWeighted) then {
                    private _i = _roleNames find _role;
                    private _wt = _roleWeighs#_i;
                    (_units#(2*_i)) pushBack _unit;
                } else {
                    _units pushBack _unit;
                };
            };
        } forEach _unitsData;
        
        if (_isWeighted) then {
            // weighted units that don't have any of that role, should weight to zero
            for "_i" from 0 to count _units - 1 step 2 do {
                if ((_units#_i) isEqualTo []) then {
                    _units set [_i+1,0];
                };
            };
        };
            
        _units = [_faction,_units] call Faction_CheckUnitList;
        
        _units
    };
    
    private _factionSide = {
        params ["_faction"];
        switch ([_faction] call FactionSide) do {
            case east: {"OPF_F"};
            case west: {"BLU_F"};
            case independent: {"IND_F"};
            case civilian: {"CIV_F"};
            default {"OPF_F"};
        };
    };
    
    private _isWeighted = (count _roles > 1 && {typeName (_roles#1) == "SCALAR"});
    
    private _units = [_faction,_roles,_rolesIsInverted] call _factionUnits;
    {
        if (!(_units isEqualTo []) && {typeName (_units#0) == "ARRAY"}) then { // weighted array list
            private _empty = true;
            {
                if (typeName _x == "SCALAR" && {_x > 0}) exitWith {_empty = false};
            } forEach _units;     
            if (_empty) then {_units = []};
        };
        if !(_units isEqualTo []) exitWith {};
        switch (_x) do {
            case 1;
            case 1.0: {_units = [[_faction] call _factionSide,[],false] call _factionUnits};
            case 1.1: {_units = ["BLU_F",[],false] call _factionUnits};
            case 1.2: {_units = ["OPF_F",[],false] call _factionUnits};
            case 1.3: {_units = ["INF_F",[],false] call _factionUnits};
            case 1.4: {_units = ["CIV_F",[],false] call _factionUnits};
            case 2;
            case 2.0: {_units = [[_faction] call _factionSide,_roles,_rolesIsInverted] call _factionUnits};
            case 2.1: {_units = ["BLU_F",_roles,_rolesIsInverted] call _factionUnits};
            case 2.2: {_units = ["OPF_F",_roles,_rolesIsInverted] call _factionUnits};
            case 2.3: {_units = ["INF_F",_roles,_rolesIsInverted] call _factionUnits};
            case 2.4: {_units = ["CIV_F",_roles,_rolesIsInverted] call _factionUnits};
            case 3: {_units = [_faction call FactionBase,[],false] call _factionUnits};
            case 4: {_units = [_faction call FactionBase,_roles,_rolesIsInverted] call _factionUnits};
            case 5: {_units = [_faction,[],false] call _factionUnits};
            default {};
        };
    } forEach _fallback;

    private _cnt = count _units;
    if (_isWeighted && {_cnt > 0}) then {
        if (_cnt == 1 || {typeName (_units#1) != "SCALAR"}) then {
            _units = [_units,1];
        };
    };
    
    _units;
};

FactionCheck = {
    FACTION_DEBUG("FactionCheck");
    params ["_factionArray"];
    
    if (typeName _factionArray != "ARRAY")  exitWith {
        diag_log format ["ERROR Pos Faction Check: error in parameter, must be an array: %1",_factionArray];
        false
    };
     
    // No factions: FAIL
    if (_factionArray isEqualTo []) exitWith {
        diag_log "ERROR Pos Faction Check: no factions supplied";
        false
    };
    
    // Faction data not setup yet: FAIL
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR Pos Faction Check: FactionUnits called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
        false
    };   
    
    // handle unit selection mode
    if (count _factionArray == 1) then {
    };
    
    // handle mixture of factions as string and array of string 
    private _success = true;
    private _compactFn = {
        if (typeName _this == "STRING") then {
            private _faction = (toUpperANSI _this) call FactionUnits_Check;
            private _idx = [_factionData,_faction] call Faction_FindKey;
            if (_idx < 0) then {
                diag_log format ["ERROR Pos Faction Check: faction not found: %1",_faction]; 
                _success = false
            };
        } else {
            {
                _x call _compactFn;
            } forEach _this;
        };
    };  
    _factionArray call _compactFn;
    
    if (!_success) then {
        diag_log "Available Factions:";
        {
            diag_log (_x#0);
            {
                diag_log (":  " + (_x#0));
            } forEach (_x#4);
        } forEach _factionData;
    };
    _success
};

FactionSide = {
    FACTION_DEBUG("FactionSide");
    params ["_faction"];
    
    _faction = _faction call FactionUnits_Check;
    if (typeName _faction == "ARRAY") exitWith {
        if (count _faction == 0) then {east} else {
            (_faction#0) call FactionSide;
        };
    };
    
    _this call FactionSideNum call BIS_fnc_sideType
};

FactionSideNum = {
    FACTION_DEBUG("FactionSideNum");
    // _returnArray will return an array of sides, if false, only one side number is returned
    params ["_faction",["_returnArray",false]];
    // returns the side nubmer (0:Opfor  1: Blufor  2:Greenfor  3:Civilian)
    if (typeName _faction == "ARRAY") exitWith {
        if (count _faction == 0) then {
            if (_returnArray) then {[0]} else {0};
        } else {
            if (_returnArray) then {
                private _sideNums = [];
                {
                    _sideNums pushBackUnique ([_x] call FactionSideNum);
                } forEach _faction;
                _sideNums
            } else {
                [_faction#0] call FactionSideNum;
            };
        };
    };
    
    _faction = _faction call FactionUnits_Check;
    private _sideNum = sideUnknown call BIS_fnc_sideID;
    
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR: FactionSideNum called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
        _sideNum
    };    
    
    _faction = toUpperANSI _faction;
    
    private _idx = [_factionData,_faction] call Faction_FindKey;
    if (_idx >= 0) then {
        _sideNum = _factionData#_idx#3;
    };
    
    if (_returnArray) then {_sideNum = [_sideNum]};
    
    _sideNum
};
 
FactionName = {
    FACTION_DEBUG("FactionName");
    params ["_faction"];
    // given a faction class, return is display name
    if (isNil "_faction") exitWith {diag_log "Factions: Error Pos: FactionName called with nil faction";"Enemy"};
    _faction = _faction call FactionUnits_Check;
    
    if (typeName _faction == "ARRAY") exitWith {
        if (count _faction == 0) then {"Enemy"} else {
            private _name = [_faction#0] call FactionName;
            if (count _faction == 1) then {_name} else {
                _name + "..."
            };
        };
    };
    
    private _name = "Enemy";
    _faction = toUpperANSI _faction;
    
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR: FactionName called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
        _name
    };
    
    private _factionParts = _faction splitString ":";
    _faction = toUpperANSI (_factionParts#0);
    private _subIndex = _faction call Faction_SubIndex;
    
    private _idx = [_factionData,_faction] call Faction_FindKey;
    private _subFactionsData = _factionData#_idx#4;
    if (_idx >= 0) then {
        if (_subIndex < 0 || {_subIndex > count _subFactionsData}) then {
            _name = (_factionData#_idx#1);
        } else {
            _name = (_factionData#_idx#1) + " : " + _subFactionsData#_subIndex#0;
        };
    };
    
    _name
};

FactionFlag = {
    FACTION_DEBUG("FactionFlag");
    params ["_faction"];
    _faction = _faction call FactionUnits_Check;
    
    if (typeName _faction == "ARRAY") exitWith {
        if (count _faction == 0) then {"\a3\Data_f\Flags\flag_nato_co.paa"} else {
            [_faction#0] call FactionFlag;
        };
    };
    
    private _flag = "";
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR: FactionFlag called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
        "\a3\Data_f\Flags\flag_nato_co.paa"
    };
    _faction = toUpperANSI _faction;
    
    private _idx = [_factionData,_faction] call Faction_FindKey;
    if (_idx >= 0) then {
        _flag = _factionData#_idx#2;
    } else {
        private _cfg = selectRandom ("(isText (_x >> 'flag'))" configClasses (configFile >> "CfgFactionClasses"));
        if (isNil "_cfg") then {
            _flag = "\a3\Data_f\Flags\flag_nato_co.paa";
        } else {
            _flag = getText (_cfg >> 'flag');
        };
    };    
    _flag
};

FactionSetOkayBtnText = {
    params [["_text",""]];
    if (isNil "_text") then { _text = "" };
    FACTION_OKAY_TEXT = _text;
    publicVariable "FACTION_OKAY_TEXT";
};

FactionDlcId = {
    // can pass in a map name, or a faction name (if supplied, the faction name will override the map)
    params [["_worldName",worldname],["_faction",""]];
    _onlyDlcs = [];
    _removeDlcs = [];
    if (_faction isEqualTo "") then {
        switch (toLowerANSI _worldName) do {
            case "gm_weferlingen_summer";
            case "gm_weferlingen_winter": {
                _onlyDlcs = ["gm"];
            };
            case "enoch": {
                _onlyDlcs = ["enoch"];
            };
            case "stozec": { 
                _onlyDlcs = ["csla"];
            };
            case "vn_khe_sanh";
            case "vn_the_bra";
            case "cam_lao_nam": {
                _onlyDlcs = ["vn"]; // wtf? prairie fire doesn't use the dlc member of the class
            };
            case "sefrouramal": {
                _onlyDlcs = ["ws","rf"];
            };
            case "spex_utah_beach";
            case "spex_carentan";
            case "spe_mortain";
            case "spe_normandy": {
                _onlyDlcs = ["spe"];
            };
            case "altis";
            case "stratis";
            case "malden";
            case "tanoa": {
                _removeDlcs = ["csla","gm","spe","vn"];
            };
        };
    } else {
        private _factionUnits = [_faction] call FactionUnits;
        _onlyDlcs = if (_factionUnits isEqualTo []) then {[""]} else {
            [toLowerANSI configSourceMod (configFile >> "CfgVehicles" >> (_factionUnits#0))];
        };
    };
    [_onlyDlcs,_removeDlcs]
};

FactionSanitizeCivilians = {
    // this is best called on the client where units are local, but can be call from anywhere
    // if factionSide != civilian, then any vest is removed
    params ["_factionSide","_units"];
    if (typeName _units == "OBJECT") then {_units = [_units]};
    
    {
        if (_factionSide != civilian) then {
            removeVest _x;
        };
        if (local _x) then {
            removeAllWeapons _x;
        } else {
            [_x] call ["removeAllWeapons",_x];
        };
    } forEach _units;
};
 
FactionGetCheckBoxStates = {
    // return array [CheckBoxPerMap,CheckBoxSubFaction]
    // each it true if checkbox is checked
    [
        missionNamespace getVariable ["FactionCBPerMap",true],
        missionNamespace getVariable ["FactionCBSubFaction",false],
        missionNamespace getVariable ["FactionCBMultiIsAll",false]
    ]
};

Faction_SubIndex = {
    // return the faction sub-index of the given faction
    // ex: 2 is returned for  BLU_F:2 or 'CUSTOM'760|BLU_F:2;25,26,27,28,29
    // ex: -1 is returned for BLU_F   or 'CUSTOM'760|BLU_F;25,26,27,28
    private _subIndex = -1;
    private _factionParts = _this splitString ":";
    if (count _factionParts > 1) then {
        _factionParts = (_factionParts#1) splitString ";";
        _subIndex = parseNumber (_factionParts#0);
    };
    _subIndex
};

FactionBase = {
    // return the base faction of the given faction 
    // ex: BLU_F is base of BLU_F or BLU_F:2 or 'CUSTOM'760|BLU_F:0;25,26,27,28,29, or 'CUSTOM'760|BLU_F;25,26,27,28
    private "_base";
    private _parts = _this splitString ":|;";
    if (count _parts == 0) then {_base = ""} else {
        if (_parts#0 select [0,8] isEqualTo "'CUSTOM'") then {
            if (count _parts > 1) then {
                _base = _parts#1;
            } else {
                private _factionData = missionNamespace getVariable ["FactionData",[]];
                _idx = [_factionData,_parts#0] call Faction_FindKey;
                if (_idx >= 0) then {
                    _base = _factionData#_idx#0;
                } else {
                    diag_log format ["Error Pos: FactionBase unable to find base of faction %1",_this];
                    _base = _this;
                };
            };
        } else {
            _base = _parts#0;
        };
    };
    _base
};

FactionConvertToBaseList = {
    params ["_factionList"];
    private _baseList = [];
    if (typeName _factionList == "STRING") then {_factionList = [_factionList]};
    _baseList  = _factionList apply {_x call FactionBase};
    _baseList = _baseList arrayIntersect _baseList;
    _baseList
};

FactionInBaseList = {
    // checks if a faction is a base faction of a list of factions (ie faction in FactionList, but uses base factions of factionlist)
    params ["_faction","_factionList"];
    _faction = _faction call FactionUnits_Check;
    if (typeName _factionList == "STRING") then {_factionList = [_factionList]};
    if (typeName _faction != "STRING" || {typeName _factionList != "ARRAY"}) exitWith {
        diag_log format ["Faction: Error pos: FactionInBaseList called with invalid arguments (%1)",_this]; 
        false
    };
    _baseFactionList = _factionList apply {_x call FactionBase};
    _faction in _baseFactionList
};
 ////////////////////////////////////////////////////////////////////////////////
 //              Class functions
 ////////////////////////////////////////////////////////////////////////////////

FactionSelection_Wait = {
    // Can be called on extra clients while other player selects factions  
    [false] call FactionSelection_CollectFactions;
    
    waitUntil {sleep 1; missionNamespace getVariable ["FACTION_DONE",false]};
};

FactionSelection_Start = {
    params ["_initialFactionsP","_initialFactionsE","_initialFactionsC","_showCivList",["_playerIsCiv",false],["_checkBoxes",[true,false,false]]];
    // Called on one client - will choose faction
    
    _checkBoxes params [["_perMap",true], ["_subFactions",false], ["_multiIsAll",false]];
    missionNamespace setVariable ["FactionCBPerMap",_perMap,true];
    missionNamespace setVariable ["FactionCBSubFaction",_subFactions,true];
    missionNamespace setVariable ["FactionCBMultiIsAll",_multiIsAll,true];
    
    missionNamespace setVariable ["FactionInitialP",_initialFactionsP];
    missionNamespace setVariable ["FactionInitialE",_initialFactionsE];
    missionNamespace setVariable ["FactionInitialC",_initialFactionsC];
    missionNamespace setVariable ["FactionShowCivList",_showCivList];
           
    waitUntil {!isNil "FactionsAllowed"}; // wait until the host has sent the list of allowed factions
    
    [_perMap] call FactionSelection_CollectFactions;
    
    waitUntil {!isNull findDisplay 46};
    createDialog "FactionSelectionScreen";
    waitUntil {!isNull findDisplay FACTION_SELECTION_IDD};

    // save the list controls so we can easily grab them later
    private _display = findDisplay FACTION_SELECTION_IDD;
    private _listCtrlP = _display displayCtrl FACTION_SELECTOR_LIST_P;
    private _listCtrlE = _display displayCtrl FACTION_SELECTOR_LIST_E;
    private _listCtrlC = _display displayCtrl FACTION_SELECTOR_LIST_C;
    private _textCtrlC = _display displayCtrl FACTION_SELECTOR_TEXT_C;
    private _subCtrl   = _display displayCtrl FACTION_SELECTOR_SUB_FACTIONS;
    private _unitListCtrlP = _display displayCtrl FACTION_UNITS_LIST_P;
    private _unitListCtrlE = _display displayCtrl FACTION_UNITS_LIST_E;
    private _unitListCtrlC = _display displayCtrl FACTION_UNITS_LIST_C;
    private _warningCtrl = _display displayCtrl FACTION_WARNING_TEXT;
    private _pictureCtrl = _display displayCtrl FACTION_PICTURE;
    uiNamespace setVariable ["FactionListCtrlP",_listCtrlP];
    uiNamespace setVariable ["FactionListCtrlE",_listCtrlE];
    uiNamespace setVariable ["FactionListCtrlC",_listCtrlC];
    uiNamespace setVariable ["FactionTextCtrlC",_textCtrlC];
    uiNamespace setVariable ["FactionSubCtrl",_subCtrl];
    uiNamespace setVariable ["FactionUnitListCtrlP",_unitListCtrlP];
    uiNamespace setVariable ["FactionUnitListCtrlE",_unitListCtrlE];
    uiNamespace setVariable ["FactionUnitListCtrlC",_unitListCtrlC];
    uiNamespace setVariable ["FactionWarningCtrl",_warningCtrl];
    uiNamespace setVariable ["FactionPictureCtrl",_pictureCtrl];
        
    _unitListCtrlP ctrlShow false;
    _unitListCtrlE ctrlShow false;
    _unitListCtrlC ctrlShow false;
    _warningCtrl ctrlShow false;
    _pictureCtrl ctrlShow false;
    _display displayCtrl FACTION_SELECTOR_PER_MAP cbSetChecked _perMap;
    _display displayCtrl FACTION_SELECTOR_SUB_FACTIONS cbSetChecked _subFactions;
    _display displayCtrl FACTION_SELECTOR_MULTI_IS_ALL cbSetChecked _multiIsAll;
    _display displayCtrl FACTION_UNITS_BUTTON_C ctrlShow _showCivList;
    
    {
        (_display displayCtrl _x) ctrlSetTooltip localize "STR_SKL_FACTION_TooltipSelectUnits";
    } forEach [FACTION_UNITS_BUTTON_P,FACTION_UNITS_BUTTON_E,FACTION_UNITS_BUTTON_C];
    
    {
        (_display displayCtrl _x) ctrlSetTooltip localize "STR_SKL_FACTION_TooltipPerMap";
    } forEach [FACTION_SELECTOR_PER_MAP,FACTION_SELECTOR_PM_TEXT];
    
    {
        (_display displayCtrl _x) ctrlSetTooltip localize "STR_SKL_FACTION_TooltipMultiselect";
    } forEach [FACTION_SELECTOR_MULTI_IS_ALL,FACTION_SELECTOR_MULTI_TEXT];
    
    if (!(isNil "FACTION_INFO_TEXT") && {!(FACTION_INFO_TEXT isEqualTo "")}) then {
        (_display displayCtrl FACTION_SELECTOR_INFO) ctrlSetText FACTION_INFO_TEXT;
    };
    
    if (!(isNil "FACTION_OKAY_TEXT") && {!(FACTION_OKAY_TEXT isEqualTo "")}) then {
        (_display displayCtrl FACTION_SELECTOR_OKAY) ctrlSetText FACTION_OKAY_TEXT;
    };
    ctrlSetFocus (_display displayCtrl FACTION_SELECTOR_OKAY);
    
    if (_perMap) then {
        // check if desired factions will be hidden by the map specific checkbox
        private _factionData = call Factions_GetData;
        {      
            if (([_factionData,_x] call Faction_FindKey == -1) && (_x in FactionsAllowed)) exitWith {
                _display displayCtrl FACTION_SELECTOR_PER_MAP cbSetChecked false;
                [false] call FactionSelection_CollectFactions;
            }
        } forEach (_initialFactionsP + _initialFactionsE + _initialFactionsC);
    };
    
    [true,_playerIsCiv] call FactionSelection_PopulateListboxes;
};

FactionSelection_CollectFactions = {
    params ["_limitToDlcs"]; // true or false
    FactionCollectionStarted = true;
    missionNamespace setVariable ["IsFactionDataLimited",_limitToDlcs];
    
    // check if we've already collected factions
    if !(missionNamespace getVariable ["FactionData",[]] isEqualTo []) exitWith {};
    
    // some unit are just wrong, so don't use them
    private _classesNotAllowed = ["C_Soldier_VR_F","C_Protagonist_VR_F","B_Soldier_VR_F","O_Soldier_VR_F","I_Soldier_VR_F",
                                  "B_Protagonist_VR_F","O_Protagonist_VR_F","I_Protagonist_VR_F"];
    
    [] call FactionDlcId params [["_onlyDLCs",[]],["_removeDLCs",[]]];
    private _factionsData = [];  
    private _factionsDLCs = createHashMap;

    // Record all factions with valid vehicles
    {
        private _configName = configName _x;
        private _cfgVeh = _x;
        private _factionClass = toUpperANSI ((_cfgVeh >> "faction") call BIS_fnc_GetCfgData);
        if !(_factionClass in ["VIRTUAL_F","WBK_AI","WBK_AI_MELEE"]) then {
            private _factionCheck = if (isNil "FactionsAllowed") then {true} else {_factionClass in FactionsAllowed};
            if (isNull (configFile >> "CfgFactionClasses" >> _factionClass)) then {_factionCheck = false}; // faction isn't defined
            private _classCheck = !(_configName in _classesNotAllowed);
            if (_factionCheck && _classCheck) then {
                private _sideNum = getNumber (configFile >> "CfgFactionClasses" >> _factionClass >> "side");
                private _role = getText (_cfgVeh >> "role");
                if (getArray (_cfgVeh >> "shownUnderwaterSelections") isNotEqualTo []) then {_role = "diver"};
                if (_factionClass == "SKYNET" && {_role == "unarmed"}) then {_role = "rifleman"};
                private _dispName = getText (_cfgVeh >> "displayName");
                if (_role isEqualTo "") then {
                    if !(_dispName isEqualTo "") then {
                        _role = [_dispName] call Factions_RoleFix;
                    };
                } else {
                    if (_role == "rifleman") then { // fix for RHS
                        private _splitName = (toLowerANSI _dispName) splitString " -_,./()[]{}";
                        if ({ _x in _splitName } count ["pilot", "driver", "crew"] > 0) then {_role = "crewman"};
                    };
                    if (toLowerANSI _role == "assault") then {_role == "rifleman"};
                }; 
                //if (isNil "SKL_ROLES") then {SKL_ROLES=[]};
                //SKL_ROLES pushBackUnique _role;
                if (_sideNum >= 0 && {_sideNum <= 3}) then {
                    private _subFaction = getText ( ConfigFile >> "CfgEditorSubcategories" >> getText (_cfgVeh >> "editorSubcategory") >> "displayName");
                    if (_sideNum == 3) then {  
                        // CIVILIANS
                        _index = ([_factionsData, _factionClass] call Faction_FindKey);
                        if (_index == -1) then {
                            private _thisFactionName = ((configFile >> "CfgFactionClasses" >> _factionClass >> "displayName") call BIS_fnc_GetCfgData);
                            private _thisFactionFlag = ((configfile >> "CfgFactionClasses" >> _factionClass >> "flag") call BIS_fnc_GetCfgData);                      
                            if (isNil "_thisFactionFlag") then { _thisFactionFlag = "" };
                            if (_thisFactionFlag == "\CSLA_FIA_cfg\images\FIA_logo.paa") then {_thisFactionFlag = "\csla_misc\signs\flags\fia_flag.paa"};
                            if (_thisFactionFlag == "\gmx\gmx_cdf\gmx_cdf_core\data\gmx_cdf_flag_cdf_co") then {_thisFactionFlag = ""};
                            _factionsData pushBack [_factionClass, _thisFactionName, _thisFactionFlag, _sideNum, [[_subFaction,[[_configName,"unarmed"]]]], ""];
                        } else {                     
                            private _subIndex = ([_factionsData, _factionClass,_subFaction] call Faction_FindSubFaction);
                            if (_subIndex == -1) then {
                                ((_factionsData#_index)#4) pushBack [_subFaction,[[_configName,"unarmed"]]];
                            } else {
                                (((_factionsData#_index)#4)#_subIndex#1) pushBack [_configName,"unarmed"];
                            };
                        };
                        private _array = _factionsDLCs getOrDefault [_factionClass,[],true];
                        _array pushBackUnique (toLowerANSI configSourceMod _cfgVeh);     
                    } else {   
                        private _dispName = getText (configFile >> "CfgFactionClasses" >> _factionClass >> "displayName");
                        private _isZombie = "ZOMBIE" in _factionClass || {"ZOMBIE" in toUpperANSI _dispName || {_configName isKindOf "WBK_C_ExportClass"}};
                        if (_role == "unarmed" && {toLowerANSI (_factionClass select [0,6]) == "acm_i_"}) then {_role = "rifleman"};
                        if (_role != "unarmed" || _isZombie) then {
                            // remove unit types w/o weapons 
                            private _hasWeapons = _isZombie;
                            if (!_hasWeapons) then {
                                // non-civilians must have weapons
                                {
                                    private _wpnType = getNumber (configFile >> "CfgWeapons" >> (_x) >> "type");
                                    if (_wpnType == 1 || _wpnType == 2) exitWith {_hasWeapons = true};
                                } forEach (getArray (_cfgVeh >> "weapons"));    
                            };
                            if (_hasWeapons) then {
                                _index = ([_factionsData, _factionClass] call Faction_FindKey);
                                if (_index == -1 ) then {
                                    private _thisFactionName = ((configFile >> "CfgFactionClasses" >> _factionClass >> "displayName") call BIS_fnc_GetCfgData); 
                                    private _thisFactionFlag = ((configfile >> "CfgFactionClasses" >> _factionClass >> "flag") call BIS_fnc_GetCfgData);
                                    if (isNil "_thisFactionFlag") then { _thisFactionFlag = "" };
                                    if (_thisFactionFlag == "\CSLA_FIA_cfg\images\FIA_logo.paa") then {_thisFactionFlag = "\csla_misc\signs\flags\fia_flag.paa"};
                                    if (_thisFactionFlag == "\gmx\gmx_cdf\gmx_cdf_core\data\gmx_cdf_flag_cdf_co") then {_thisFactionFlag = ""};
                                    if (_thisFactionFlag isEqualTo "") then {
                                        switch (_factionClass) do {
                                            case "SPE_STURM";
                                            case "SPE_WEHRMACHT" : { _thisFactionFlag = "ww2\spe_core_t\data_t\flags\flag_GER_co.paa" };
                                            case "SPE_FFI";
                                            case "SPE_FR_ARMY": {_thisFactionFlag = "ww2\spe_core_t\data_t\flags\flag_FFF_co.paa"};
                                            case "SPE_US_ARMY": {_thisFactionFlag = "ww2\spe_core_t\data_t\flags\flag_USA_co.paa"};
                                        };    
                                    };
                                    _factionsData pushBack [_factionClass, _thisFactionName, _thisFactionFlag, _sideNum, [[_subFaction,[[_configName,toLowerANSI _role]]]], ""];
                                } else {
                                    private _subIndex = ([_factionsData, _factionClass,_subFaction] call Faction_FindSubFaction);
                                    if (_subIndex == -1) then {
                                        ((_factionsData#_index)#4) pushBack [_subFaction,[[_configName,toLowerANSI _role]]];
                                    } else {
                                        (((_factionsData#_index)#4)#_subIndex#1) pushBack [_configName,toLowerANSI _role];
                                    };
                                };   
                                private _array = _factionsDLCs getOrDefault [_factionClass,[],true];
                                _array pushBackUnique (toLowerANSI configSourceMod _cfgVeh);                       
                            };
                        };
                    };
                };
            };
        };
    } forEach ("(configName _x) isKindOf 'CAManBase' && {((_x >> 'scope') call BIS_fnc_GetCfgData) isEqualTo 2}" configClasses (configFile / "CfgVehicles"));
    
    if (["@RHSAFRF",true] call Faction_CheckMod || (!isNil "FactionsAllowed" && {"@RHSAFRF" in FactionsAllowed})) then {
        // rhs Russian Tank Faction (RHS Russian TV) doesn't show since it has no units.  Just add it here
        _factionsData pushBack ["RHS_FACTION_TV", "Russia (TV)", "\rhsafrf\addons\rhs_main\data\flag_rus_co.paa", 0, [["Crew",[["rhs_msv_crew","crewman"],["rhs_msv_crew_commander","crewman"]]]],""];
        _factionsDLCs set ["RHS_FACTION_TV",["@RHSAFRF"]];
    };
    
    // somehow vietnam got added to some CIV_F units, so remove that so it will show on main maps
    private _civs = _factionsDLCs get "CIV_F";
    _civs = _civs - ["vn"];
    _factionsDLCs set ["CIV_F",_civs];
    
    _factionsDataLimited = [];
    {
        private _faction = _x;
        private _dlcs = _y;
        private _use = true;
        if (count _onlyDLCs > 0) then {
            _use = false;
            {
                if (_x in _onlyDLCs) exitWith {_use = true}; 
            } forEach _dlcs;
        } else {
            if (count _removeDLCs > 0) then {
                _use = true;
                {
                    if (_x in _removeDLCs) exitWith {_use = false};
                } forEach _dlcs;
            };
        };     
        if (_use) then {
            private _idx = [_factionsData,_faction] call Faction_FindKey;
            if (_idx >= 0) then {
                _factionsDataLimited pushBack (_factionsData#_idx);
            };
        };
    } forEach _factionsDLCs;   
    missionNamespace setVariable ["FactionData",[_factionsData,[],{_x#1}] call BIS_fnc_sortBy ];
    missionNamespace setVariable ["FactionDataLimited",[_factionsDataLimited,[],{_x#1}] call BIS_fnc_sortBy];
    FactionCollectionComplete = true;
};

Faction_CheckMod = {
    params ["_modWithAtSymbol",["_checkServer",false]];
    private _exists = false;
    private _notifyClient = -1;
    if (typeName _checkServer == "SCALAR") then {
        _notifyClient = _checkServer;
        _checkServer = false;
    } else {
        if (!isServer && {_checkServer}) exitWith {
            missionNamespace setVariable ["FactionCheckMod",nil];
            _this remoteExec ["Faction_CheckMod",2];
            private _timeout = 3;
            waitUntil {!isNil {missionNamespace setVariable ["FactionCheckMod",nil]} || time > _timeout};
            _exists = missionNamespace getVariable ["FactionCheckMod",false];
            missionNamespace setVariable ["FactionCheckMod",nil];
            _exists
        };
    };
    _exists = getLoadedModsInfo findIf {_x#1 isEqualTo _modWithAtSymbol} >= 0;
    if (_notifyClient > 1) then {missionNamespace setVariable ["FactionCheckMod",_exists,_notifyClient]};
    _exists
};

FactionSelection_PopulateListboxes = {
    params [["_resetSelection",false],["_playerIsCiv",0]];
    if (isNil "FACTION_PlayerIsCiv") then {FACTION_PlayerIsCiv = false};
    if (typeName _playerIsCiv != "BOOL") then {_playerIsCiv = FACTION_PlayerIsCiv} else {FACTION_PlayerIsCiv = _playerIsCiv};
    
    private _factionData = call Factions_GetData;
    if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
        diag_log "ERROR: FactionSelection_PopulateListboxes called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
    };
    
    private _listCtrlP = uiNamespace getVariable "FactionListCtrlP";
    private _listCtrlE = uiNamespace getVariable "FactionListCtrlE";
    private _listCtrlC = uiNamespace getVariable "FactionListCtrlC";
    private _textCtrlC = uiNamespace getVariable "FactionTextCtrlC";
    private _showSubFactions = cbChecked (uiNamespace getVariable "FactionSubCtrl");
    
    private ["_initialFactionsP","_initialFactionsE","_initialFactionsC"];
    if (_resetSelection) then {
        _initialFactionsP = (missionNamespace getVariable ["FactionInitialP",[]]) call FactionUnits_Check;
        _initialFactionsE = (missionNamespace getVariable ["FactionInitialE",[]]) call FactionUnits_Check;
        _initialFactionsC = (missionNamespace getVariable ["FactionInitialC",[]]) call FactionUnits_Check;
    } else {
        _initialFactionsP = missionNamespace getVariable ["FACTIONS_SELECTED_P",[]];
        _initialFactionsE = missionNamespace getVariable ["FACTIONS_SELECTED_E",[]];
        _initialFactionsC = missionNamespace getVariable ["FACTIONS_SELECTED_C",[]];
        
        if (!_showSubFactions) then {
            _initialFactionsP = _initialFactionsP apply { _x call FactionBase };
            _initialFactionsP = _initialFactionsP arrayIntersect _initialFactionsP;
            _initialFactionsE = _initialFactionsE apply { _x call FactionBase };
            _initialFactionsE = _initialFactionsE arrayIntersect _initialFactionsE;
            _initialFactionsC = _initialFactionsC apply { _x call FactionBase };
            _initialFactionsC = _initialFactionsC arrayIntersect _initialFactionsC;
        };
    };
    
    if (typeName _initialFactionsP isEqualTo "STRING") then {_initialFactionsP = [_initialFactionsP]};
    if (typeName _initialFactionsE isEqualTo "STRING") then {_initialFactionsE = [_initialFactionsE]};
    if (typeName _initialFactionsC isEqualTo "STRING") then {_initialFactionsC = [_initialFactionsC]};
    {
        private _factions = _x;
        {
            if (typeName _x == "STRING") then { // fix for bug that caused invalid factions, if it shows up we ignore the invalid one
                _factions set [_forEachIndex,(_x splitString "|")#0];  // strip individual unit selections from faction
            };
        } forEach _factions;
    } forEach [_initialFactionsP,_initialFactionsE,_initialFactionsC];
    
    if (_initialFactionsP isEqualTo []) then {
        _initialFactionsP = ["player"] call FactionSelection_Defaults;
    };
    if (_initialFactionsE isEqualTo []) then {
        _initialFactionsE = ["enemy"] call FactionSelection_Defaults;
    };
    if (_initialFactionsC isEqualTo []) then {
        _initialFactionsC = ["civilian"] call FactionSelection_Defaults;
    };
    
    // setup the defaults that we will be returned in case the user doesn't actually change the values
    missionNamespace setVariable ["FACTIONS_SELECTED_P", _initialFactionsP];
    missionNamespace setVariable ["FACTIONS_SELECTED_E", _initialFactionsE];
    missionNamespace setVariable ["FACTIONS_SELECTED_C", _initialFactionsC];
    
    lbClear _listCtrlP;
    lbClear _listCtrlE;
    lbClear _listCtrlC;
    
    private _showCivList = missionNamespace getVariable ["FactionShowCivList",false];
    _listCtrlC ctrlShow _showCivList; 
    _textCtrlC ctrlShow _showCivList; 
    
    {  
        _x params ["_faction","_factionName","_factionFlag","_sideNum","_subFactions"];
        if !(_faction in FactionsAllowed) then {continue};
        
        private _factionIndex = 100 * _forEachIndex;
        private _data = [[_faction,_factionName,_factionFlag,_sideNum]];
        if (_showSubFactions) then {
            {
                _x params ["_subFactionName"];
                _data pushBack [_faction + ":" + str _forEachIndex,"  " + _subFactionName,"",_sideNum];
            } forEach _subFactions;
        };
        
        {
            _x params ["_thisFaction","_thisFactionName","_thisFactionFlag","_thisSideNum"];

            private _SubFactionIndex = _factionIndex + _forEachIndex;
            // Add factions to combo boxes
            private _color = "";
            private _sortIdP = 0;
            private _sortIdE = 0;
            private _sortIdC = 0;
            switch (_thisSideNum) do {
                case 1: { 
                    // west
                    _color = [0, 0.3, 0.6, 1];
                    _sortIdP = 1e6;
                    _sortIdE = 3e6;
                    _sortIdC = 4e6;
                };
                case 0: {
                    // east
                    _color = [0.5, 0, 0, 1];
                    _sortIdP = 3e6;
                    _sortIdE = 1e6;
                    _sortIdC = 3e6;
                };
                case 2: {
                    // independent
                    _color = [0, 0.5, 0, 1];
                    _sortIdP = 2e6;
                    _sortIdE = 2e6;
                    _sortIdC = 2e6;
                };
                case 3: {
                    // civ
                    _color = [0.4, 0, 0.5, 1];
                    _sortIdP = 4e6;
                    _sortIdE = 4e6;
                    _sortIdC = 1e6;
                };  
            }; 
        
            // players
            if ((_thisSideNum == 3) == _playerIsCiv) then {  
                _index = _listCtrlP lbAdd _thisFactionName;                        
                _listCtrlP lbSetData [_index, _thisFaction];
                _listCtrlP lbSetColor [_index, _color];
                _listCtrlP lbSetSelectColor  [_index, _color];
                _listCtrlP lbSetValue [_index, _sortIdP + _SubFactionIndex];
                _listCtrlP lbSetTooltip [_index,_thisFactionName];
                
                if (!isNil "_thisFactionFlag" && !(_thisFaction isEqualTo "IND_L_F")) then {
                    if (count _thisFactionFlag > 0) then {           
                        _listCtrlP lbSetPictureRight [_index, _thisFactionFlag];
                        //_listCtrlP lbSetPictureRightColor [_index, [1, 1, 1, 1]];
                        //_listCtrlP lbSetPictureColorSelected [_index, [1, 1, 1, 1]];
                    };
                };            
                _listCtrlP lbSetSelected [_index,(_thisFaction in _initialFactionsP)];
            };
                
            // enemies
            if (_thisSideNum != 3) then { 
                _index = _listCtrlE lbAdd _thisFactionName;                  
                _listCtrlE lbSetData [_index, _thisFaction];
                _listCtrlE lbSetColor [_index, _color];
                _listCtrlE lbSetSelectColor  [_index, _color];
                _listCtrlE lbSetValue [_index, _sortIdE + _SubFactionIndex];
                _listCtrlE lbSetTooltip [_index,_thisFactionName];
                
                if (!isNil "_thisFactionFlag" && !(_thisFaction isEqualTo "IND_L_F")) then {
                    if (count _thisFactionFlag > 0) then {
                        _listCtrlE lbSetPictureRight [_index, _thisFactionFlag];
                        //_listCtrlE lbSetPictureRightColor [_index, [1, 1, 1, 1]];
                        //_listCtrlE lbSetPictureColorSelected [_index, [1, 1, 1, 1]];
                    };
                };
                _listCtrlE lbSetSelected [_index,(_thisFaction in _initialFactionsE)];
            };
            
            // civilians
            _index = _listCtrlC lbAdd _thisFactionName;                  
            _listCtrlC lbSetData [_index, _thisFaction];
            _listCtrlC lbSetColor [_index, _color];
            _listCtrlC lbSetSelectColor  [_index, _color];
            _listCtrlC lbSetValue [_index, _sortIdC + _SubFactionIndex];
            _listCtrlC lbSetTooltip [_index,_thisFactionName];
            
            if (!isNil "_thisFactionFlag" && !(_thisFaction isEqualTo "IND_L_F")) then {
                if (count _thisFactionFlag > 0) then {
                    _listCtrlC lbSetPictureRight [_index, _thisFactionFlag];
                    //_listCtrlC lbSetPictureRightColor [_index, [1, 1, 1, 1]];
                    //_listCtrlC lbSetPictureColorSelected [_index, [1, 1, 1, 1]];
                };
            };
            _listCtrlC lbSetSelected [_index,(_thisFaction in _initialFactionsC)]; 
        } forEach _data;
    } forEach _factionData;
    
    _listCtrlP lbSortBy ["VALUE",false,false,true];
    _listCtrlE lbSortBy ["VALUE",false,false,true];
    _listCtrlC lbSortBy ["VALUE",false,false,true];
  
    if (lbSelection _listCtrlP isEqualTo []) then {
        private _f = _listCtrlP lbData 0;
        _listCtrlP lbSetSelected [0,true];
        _initialFactionsP = [_f];        
    };
    if (lbSelection _listCtrlE isEqualTo []) then {
        private _f = _listCtrlE lbData 0;
        _listCtrlE lbSetSelected [0,true];
        _initialFactionsE = [_f];
    };  
    if (lbSelection _listCtrlC isEqualTo []) then {
        private _f = _listCtrlC lbData 0;
        _listCtrlC lbSetSelected [0,true];
        _initialFactionsC = [_f];
    };  
    
    // setup the defaults that we will be returned in case the user doesn't actually change the values
    missionNamespace setVariable ["FACTIONS_SELECTED_P", _initialFactionsP];
    missionNamespace setVariable ["FACTIONS_SELECTED_E", _initialFactionsE];
    missionNamespace setVariable ["FACTIONS_SELECTED_C", _initialFactionsC];
};

FactionSelection_PlayerClicked = {
    private _listCtrlP = uiNamespace getVariable "FactionListCtrlP";
    private _factions = [];
    private _choosenIndexs = lbSelection _listCtrlP;
    private _choosenFactions = [];
    {
        _choosenFactions pushBack (_listCtrlP lbData _x);
    } forEach _choosenIndexs;
    missionNamespace setVariable ["FACTIONS_SELECTED_P", _choosenFactions];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_P",nil];
};

FactionSelection_EnemyClicked = {
    private _listCtrlE = uiNamespace getVariable "FactionListCtrlE";
    private _factions = [];
    private _choosenIndexs = lbSelection _listCtrlE;
    private _choosenFactions = [];
    {
        _choosenFactions pushBack (_listCtrlE lbData _x);
    } forEach _choosenIndexs;
    missionNamespace setVariable ["FACTIONS_SELECTED_E", _choosenFactions];
        missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_E",nil];
};

FactionSelection_CivilianClicked = {
    private _listCtrlC = uiNamespace getVariable "FactionListCtrlC";
    private _factions = [];
    private _choosenIndexs = lbSelection _listCtrlC;
    private _choosenFactions = [];
    {
        _choosenFactions pushBack (_listCtrlC lbData _x);
    } forEach _choosenIndexs;
    missionNamespace setVariable ["FACTIONS_SELECTED_C", _choosenFactions];
        missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_C",nil];
};

FactionSelection_Complete = {
    "skl_fs" cutText ["","BLACK",0.001];
    private _factionsP = missionNamespace getVariable ["FACTIONS_SELECTED_P",[]];
    private _factionsE = missionNamespace getVariable ["FACTIONS_SELECTED_E",[]];
    private _factionsC = missionNamespace getVariable ["FACTIONS_SELECTED_C",[]];
    private _unitsP = missionNamespace getVariable ["FACTIONS_UNIT_SELECTED_P",[]];
    private _unitsE = missionNamespace getVariable ["FACTIONS_UNIT_SELECTED_E",[]];
    private _unitsC = missionNamespace getVariable ["FACTIONS_UNIT_SELECTED_C",[]];
        
    private _factionData = call Factions_GetData;
    
    // if base faction selected, deselect the subfactions
    private _remove = [];
    {
        if (":" in _x && {_x call FactionBase in _factionsP}) then {_remove pushBack _x}; 
    } forEach _factionsP;
    if !(_remove isEqualTo []) then {_factionsP = _factionsP - _remove};
    _remove = [];
    {
        if (":" in _x && {_x call FactionBase in _factionsE}) then {_remove pushBack _x}; 
    } forEach _factionsE;
    if !(_remove isEqualTo []) then {_factionsE = _factionsE - _remove};
    _remove = [];
    {
        if (":" in _x && {_x call FactionBase in _factionsC}) then {_remove pushBack _x}; 
    } forEach _factionsC;
    if !(_remove isEqualTo []) then {_factionsC = _factionsC - _remove};
    
    // Verify entries
    {
        private _faction = (_x splitString ":|")#0;
        private _idx = [_factionData,_x] call Faction_FindKey;
        if (_idx == -1 || !(_faction in FactionsAllowed)) then {
            _factionsP = _factionsP - [_x];
        };
    } forEach _factionsP;
    {
        private _faction = (_x splitString ":|")#0;
        private _idx = [_factionData,_x] call Faction_FindKey;
        if (_idx == -1 || !(_faction in FactionsAllowed)) then {
            _factionsE = _factionsE - [_x];
        };
    } forEach _factionsE;
    {
        private _faction = (_x splitString ":|")#0;
        private _idx = [_factionData,_x] call Faction_FindKey;
        if (_idx == -1 || !(_faction in FactionsAllowed)) then {
            _factionsC = _factionsC - [_x];
        };
    } forEach _factionsC;
    
    // Choose value
    if (count _factionsP == 0) then {   
        _factionsP = ["player"] call FactionSelection_Defaults;
    };        
    
    if (count _factionsE == 0) then {   
        _factionsE = ["enemy"] call FactionSelection_Defaults;
    };
    
    if (count _factionsC == 0) then {   
        _factionsC = ["civilian"] call FactionSelection_Defaults;
    };        
    
    private _sideE = 2; // use independent on all sides that aren't opfor
    if ([_factionsE] call FactionSideNum == 0) then {_sideE = 0 }; 
       
    // handle individual unit selections
    if (count _factionsP == 1 && {!(_unitsP isEqualTo [])}) then {_factionsP = [_factionsP,_unitsP] call FactionSelection_CustomName};
    if (count _factionsE == 1 && {!(_unitsE isEqualTo [])}) then {_factionsE = [_factionsE,_unitsE] call FactionSelection_CustomName};
    if (count _factionsC == 1 && {!(_unitsC isEqualTo [])}) then {_factionsC = [_factionsC,_unitsC] call FactionSelection_CustomName};
    
    if (count _factionsP == 1 && {(_factionsP#0) select [0,8] isEqualTo "'CUSTOM'"}) then {_factionsP = [_factionsP] call FactionSelection_CustomDef};
    if (count _factionsE == 1 && {(_factionsE#0) select [0,8] isEqualTo "'CUSTOM'"}) then {_factionsE = [_factionsE] call FactionSelection_CustomDef};
    if (count _factionsC == 1 && {(_factionsC#0) select [0,8] isEqualTo "'CUSTOM'"}) then {_factionsC = [_factionsC] call FactionSelection_CustomDef};
    
    missionNamespace setVariable ["FACTION_SELECTED", [_factionsP,_factionsE,_factionsC,_sideE,missionNamespace getVariable ["FactionCBMultiIsAll",false]], 2];
    sleep 0.5;
    missionNamespace setVariable ["FACTION_DONE", true, true];
    
    uiNamespace setVariable ["FactionListCtrlP",controlNull];
    uiNamespace setVariable ["FactionListCtrlE",controlNull];
    uiNamespace setVariable ["FactionListCtrlC",controlNull];
    
    closeDialog 0;
    sleep 0.5;
    
    "skl_fs" cutText ["","PLAIN",0.001];
};

FactionSelection_CustomDef = {
    params ["_factionArray"];
    private _faction = _factionArray#0;
    private _factionData = missionNamespace getVariable ["FactionData",[]];
    private _idx = _factionData findIf {_x#0 isEqualTo _faction};
    if (_idx >= 0) then {
        private _factionDef = _factionData#_idx#5;
        if !(_factionDef isEqualTo "") then {
            _factionArray = [_factionDef];
        };
    };
    _factionArray
};

FactionSelection_CustomName = {
    params ["_factionArray","_units"];
    private _faction = _factionArray#0;
    if (_faction select [0,8] isEqualTo "'CUSTOM'") exitWith {_factionArray}; // cannot do custom of custom 
    
    private "_cName";
    private _factionData = missionNamespace getVariable ["FactionData",[]];
    while {true} do {
        _cName = "'CUSTOM'" + str floor random 10000;
        if (_factionData findIf {_x#0 isEqualTo _cName} < 0) exitWith {}
    };
    private _semicolonIdx = _faction find ";";
    forceUnicode 1;
    if (_semicolonIdx >= 0) then { _faction = (_faction select [0,_semicolonIdx]) + ";" + (_faction select [_semicolonIdx+1,100]) };
    private _newName = _cName + "|" + _faction + ";";
    {_newName = _newName + str _x + ","} count _units;    
    _newName call FactionUnits_Check; // put new faction into the factionData
    [_newName]
};

FactionSelection_ResetClick = {
    private _listCtrlP = uiNamespace getVariable "FactionListCtrlP";
    private _listCtrlE = uiNamespace getVariable "FactionListCtrlE";
    private _listCtrlC = uiNamespace getVariable "FactionListCtrlC";
    private _unitCtrlP = uiNamespace getVariable "FactionUnitListCtrlP";
    private _unitCtrlE = uiNamespace getVariable "FactionUnitListCtrlE";
    private _unitCtrlC = uiNamespace getVariable "FactionUnitListCtrlC";
    private _pictuCtrl = uiNamespace getVariable "FactionPictureCtrl";
    
    _unitCtrlP ctrlShow false;
    _unitCtrlE ctrlShow false;
    _unitCtrlC ctrlShow false;
    _pictuCtrl ctrlShow false;
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_P",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_E",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_C",nil];
    
    private _choosenFactions = [];    
    private _factions = ["player"] call FactionSelection_Defaults;
    for "_i" from 0 to (lbSize _listCtrlP - 1) do {
        private _data = _listCtrlP lbData _i;
        private _select = _data in _factions;        
        _listCtrlP lbSetSelected [_i, _select];
        if (_select) then {_choosenFactions pushBack _data};
    };
    missionNamespace setVariable ["FACTIONS_SELECTED_P", _choosenFactions];
    
    _choosenFactions = [];
    _factions = ["enemy"] call FactionSelection_Defaults;
    for "_i" from 0 to (lbSize _listCtrlE - 1) do {
        private _data = _listCtrlE lbData _i;
        private _select = _data in _factions;        
        _listCtrlE lbSetSelected [_i, _select];
        if (_select) then {_choosenFactions pushBack _data};
    };
    missionNamespace setVariable ["FACTIONS_SELECTED_E", _choosenFactions];
    
    _choosenFactions = [];
    _factions = ["civilian"] call FactionSelection_Defaults;
    for "_i" from 0 to (lbSize _listCtrlC - 1) do {
        private _data = _listCtrlC lbData _i;
        private _select = _data in _factions;        
        _listCtrlC lbSetSelected [_i, _select];
        if (_select) then {_choosenFactions pushBack _data};
    };
    missionNamespace setVariable ["FACTIONS_SELECTED_C", _choosenFactions];
};

FactionSelection_PerMapChecked = {
    params ["_control", "_checked"];
    missionNamespace setVariable ["FactionCBPerMap",_checked == 1,true];
    [_checked == 1] call FactionSelection_CollectFactions;
    [] call FactionSelection_PopulateListboxes;
    
    private _unitCtrlP = uiNamespace getVariable "FactionUnitListCtrlP";
    private _unitCtrlE = uiNamespace getVariable "FactionUnitListCtrlE";
    private _unitCtrlC = uiNamespace getVariable "FactionUnitListCtrlC";
    private _pictuCtrl = uiNamespace getVariable "FactionPictureCtrl";
    
    _unitCtrlP ctrlShow false;
    _unitCtrlE ctrlShow false;
    _unitCtrlC ctrlShow false;
    _pictuCtrl ctrlShow false;
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_P",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_E",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_C",nil];
    ctrlSetText [FACTION_UNITS_BUTTON_P,"Select Units"];
    ctrlSetText [FACTION_UNITS_BUTTON_E,"Select Units"];
    ctrlSetText [FACTION_UNITS_BUTTON_C,"Select Units"];
};

FactionSelection_SubFactionsChecked = {
    params ["_control", "_checked"];
    missionNamespace setVariable ["FactionCBSubFaction",_checked == 1,true];
    [] call FactionSelection_PopulateListboxes;
    
    private _unitCtrlP = uiNamespace getVariable "FactionUnitListCtrlP";
    private _unitCtrlE = uiNamespace getVariable "FactionUnitListCtrlE";
    private _unitCtrlC = uiNamespace getVariable "FactionUnitListCtrlC";
    private _pictuCtrl = uiNamespace getVariable "FactionPictureCtrl";
    
    _unitCtrlP ctrlShow false;
    _unitCtrlE ctrlShow false;
    _unitCtrlC ctrlShow false;
    _pictuCtrl ctrlShow false;
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_P",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_E",nil];
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_C",nil];
    ctrlSetText [FACTION_UNITS_BUTTON_P,"Select Units"];
    ctrlSetText [FACTION_UNITS_BUTTON_E,"Select Units"];
    ctrlSetText [FACTION_UNITS_BUTTON_C,"Select Units"];
};

FactionSelection_MultiSelectChecked = {
    params ["_control", "_checked"];
    missionNamespace setVariable ["FactionCBMultiIsAll",_checked == 1,true];
    if (_checked == 1) then {
        ctrlSetText[FACTION_SELECTOR_TITLE_2,"Selecting multiple will combine them all."];
    } else {
        ctrlSetText[FACTION_SELECTOR_TITLE_2,"Selecting multiple will choose randomly between them."];
    };
};

FactionSelection_Defaults = {
    params [["_team","enemy"]]; // which is one of player, enemy, civilian
    private _defaultFactions = [];
    
    // ALL FACTIONS SHOULD BE LISTED IN UPPER CASE
    switch (toLowerANSI worldName) do {
        case "gm_weferlingen_summer": { 
            _defaultFactions = [["GM_FC_GE:0","GM_FC_GE:1","GM_FC_GE:3"],["GM_FC_GC:0","GM_FC_GC:1","GM_FC_GC:2","GM_FC_GC:3","GM_FC_PL:0","GM_FC_PL:3"],["GM_FC_GC_CIV","GM_FC_GE_CIV"]];
            // units classnames that end with _win are winter
        };
        
        case "gm_weferlingen_winter": { 
            _defaultFactions = [["GM_FC_GE:2","GM_FC_GE:4"],["GM_FC_GC:4","GM_FC_GC:5","GM_FC_GC:6","GM_FC_GC:7","GM_FC_PL:1","GM_FC_PL:4"],["GM_FC_GC_CIV","GM_FC_GE_CIV"]];
            // units classnames that end with _win are winter
        };
        
        case "stozec": { 
            _defaultFactions = [["US85"],["CSLA","FIA"],["FIA_CIV"]];
            // unit have no roles
        };
        
        case "enoch": { 
            _defaultFactions = [["BLU_W_F"],["OPF_R_F","IND_E_F","IND_L_F"],["CIV_F"]];
        };
        
        case "vn_khe_sanh";
        case "vn_the_bra";
        case "cam_lao_nam": { 
            _defaultFactions = [["B_MACV"],["O_PAVN","O_VC"],["C_VIET"]];
        };
        
        case "sefrouramal": { 
            _defaultFactions = [["BLU_NATO_LXWS","BLU_ION_LXWS"],["OPF_SFIA_LXWS","OPF_TURA_LXWS","IND_SFIA_LXWS","IND_TURA_LXWS"],["IND_TURA_LXWS"]];
        };
        
        case "tanoa": {
            _defaultFactions = [["BLU_T_F"],["OPF_T_F","OPF_G_F","OPF_R_F","IND_F","IND_G_F","IND_C_F","OPF_GEN_F"],["CIV_F","CIV_IDAP_F"]]
        };
        
        case "spex_utah_beach";
        case "spex_carentan";
        case "spe_mortain";
        case "spe_normandy": {
            _defaultFactions = [["SPE_US_ARMY","SPE_FFI","SPE_FR_ARMY"],["SPE_STURM","SPE_WEHRMACHT"],["SPE_CIV"]]
        };
        
        default {
            _defaultFactions = [["BLU_F"],["OPF_F","OPF_G_F","IND_F","IND_G_F","OPF_GEN_F"],["CIV_F","CIV_IDAP_F"]] 
        };
    };
    
    _returnValue =
    switch (toLowerANSI _team) do {
        case "players";
        case "player": { _defaultFactions#0 };
        case "enemies";
        case "enemy": { _defaultFactions#1 };
        case "civ";
        case "civilians";
        case "civilian": { _defaultFactions#2 };
        default { throw format ["Invalid case (%1) in FactionSelection_Defaults.",_team]};
    };
    
    _returnValue
};

Factions_RoleFix = {
    params ["_displayName"];
    _displayName = toLowerANSI _displayName;
    private _role = "rifleman";
    
    // ALL ROLES SHOULD BE LISTED IN lower CASE
    private _translations = [
      ["unarmed"          ,"unarmed"          ],
      ["assistant"        ,"assistant"        ],
      ["rifleman"         ,"rifleman"         ],
      ["combatlifesaver"  ,"combatlifesaver"  ],
      ["crewman"          ,"crewman"          ],
      ["grenadier"        ,"grenadier"        ],
      ["machinegunner"    ,"machinegunner"    ],
      ["marksman"         ,"marksman"         ],
      ["missilespecialist","missilespecialist"],
      ["radiooperator"    ,"radiooperator"    ],
      ["sapper"           ,"sapper"           ],
      ["specialoperative" ,"specialoperative" ],
      ["officer"          ,"officer"          ],      
      ["medic"            ,"combatlifesaver"  ],
      ["cropsman"         ,"combatlifesaver"  ],
      ["diver"            ,"diver"            ],
      ["crew"             ,"crewman"          ],
      ["driver"           ,"crewman"          ],
      ["tank"             ,"crewman"          ],
      ["pilot"            ,"crewman"          ],
      ["gunner"           ,"machinegunner"    ],
      ["mg"               ,"machinegunner"    ],
      ["sniper"           ,"marksman"         ],
      ["spotter"          ,"marksman"         ],
      ["at"               ,"missilespecialist"],
      ["aa"               ,"missilespecialist"],
      ["rto"              ,"radiooperator"    ],
      ["radio"            ,"radiooperator"    ],
      ["sergeant"         ,"rifleman"         ],
      ["ammo"             ,"rifleman"         ],
      ["soldier"          ,"rifleman"         ],
      ["supervisor"       ,"rifleman"         ],
      ["scout"            ,"rifleman"         ],
      ["police"           ,"rifleman"         ],
      ["specfor"          ,"rifleman"         ],
      ["saboteur"         ,"rifleman"         ],
      ["engineer"         ,"sapper"           ],
      ["mechanic"         ,"sapper"           ],
      ["operator"         ,"sapper"           ],
      ["paratrooper"      ,"specialoperative" ],
      ["commander"        ,"officer"          ],
      ["mortarman (m-52)" ,"rifleman"         ],
      ["mortarman (m252)" ,"rifleman"         ],
      ["mount bearer"     ,"rifleman"         ],
      ["sharpshooter"     ,"marksman"         ],
      ["corpsman"         ,"combatlifesaver"  ],
      ["man in t-shirt"   ,"unarmed"          ]
    ];
    _translationRegex = [
      ["michal hor....k \(armed\)" ,"rifleman" ], 
      ["michal hor....k"           ,"unarmed"  ], 
      ["vasil kraj....r"           ,"unarmed"  ],     
      ["vlastimil m..ller"         ,"rifleman" ],
      ["jim ...bj... borland"      ,"rifleman" ],
      ["v..tek finke \(armed\)"    ,"unarmed"  ],
      ["anton..n anderle \(armed\)","unarmed"  ],
      ["martin val....ek"          ,"rifleman" ]
    ];
    
    private _found = false;
    {
        private _idx = _displayName find (_x#0);
        if (_idx >= 0) exitWith { _role = _x#1; _found = true };
    } forEach _translations;
    //diag_log format ["INS: role translated %2 << %1",_displayName,_role];
    
    if (!_found) then {
        {
            if (_displayName regexMatch (_x#0)) exitWith { _role = _x#1; _found = true };
        } forEach _translationRegex;
        
        if (!_found) then {
            diag_log format ["Faction: role translation not found for %1",_displayName];
        };
    };
    _role
};

Faction_FindKey = {
    params ["_array","_key"];   
    // finds index in array at which _key is the zeroth element
    // anything after and including a colon (:) will be removed from key
    // returns -1 if not found
    private _index = -1;
    if (isNil "_key" || {_key isEqualTo "" || {typeName _key != "STRING"}}) exitWith {-1};
    _key = (_key splitString ":|")#0;
    {
        if (_key isEqualTo (_x#0)) exitWith { _index = _forEachIndex };
    } forEach _array;
    _index
};

Faction_FindSubFaction = {
    params ["_data","_faction","_subFaction"];
    // _subFaction is a string
    // finds index of the subFaction, given the data array and the faction
    private _subIndex = -1;
    private _index = [_data,_faction] call Faction_FindKey;
    if (_index >= 0) then {
        {
            if (_subFaction isEqualTo (_x#0)) exitWith { _subIndex = _forEachIndex };
        } forEach (_data#_index#4);
    };
    _subIndex
};

Faction_CheckUnitList = {
    params ["_faction","_unitList"];
    if (_unitList isEqualTo []) exitWith {_unitList};
    
    private _isWeighted = typeName (_unitList#0) == "ARRAY";
    
    // weighted lists with no elements should be weighted zero
    if (_isWeighted) then {
        for "_i" from 0 to (count _unitList - 1) step 2 do {
            if (_unitList#_i isEqualTo []) then {
                _unitList set [_i+1,0];
            };
        };
    };
    
    _unitList;
};

Factions_GetData = {
    
    private _dataLimited = missionNamespace getVariable ["IsFactionDataLimited",false];
    
    private _factionData = if (_dataLimited) then {
            missionNamespace getVariable ["FactionDataLimited",[]];
        } else {
            missionNamespace getVariable ["FactionData",[]]
        };
    _factionData
};

Factions_SetInfo = {
    params ["_text"];
    FACTION_INFO_TEXT = _text;
    publicVariable "FACTION_INFO_TEXT";
};

// deal with jipping
FactionCollectionComplete = false;
FactionCollectionStarted = false;
Factions_WaitDataReady = {
    if (isServer) exitWith {true};
    if (FactionCollectionStarted) then {
        if (!FactionCollectionComplete) then { waitUntil {sleep 1; FactionCollectionComplete} };
    } else {
        [false] call FactionSelection_CollectFactions;
    };
    FactionCollectionComplete
};

//
// options for selecting individual units
//
FactionSelectUnits_Click = {
    // button click to select units
    params ["_which"]; // _which = 'P', 'E', or 'C'
    private _listCtrl = uiNamespace getVariable (switch (_which) do {case "P": {"FactionUnitListCtrlP"};case "E": {"FactionUnitListCtrlE"};case "C": {"FactionUnitListCtrlC"};});
    private _btnIdc = switch (_which) do {case "P": {FACTION_UNITS_BUTTON_P};case "E": {FACTION_UNITS_BUTTON_E};case "C": {FACTION_UNITS_BUTTON_C};};
    private _pictureCtrl = uiNamespace getVariable "FactionPictureCtrl";
    
    if (ctrlText _btnIdc isEqualTo "Cancel") exitWith {
        ctrlSetText [_btnIdc,"Select Units"];
        _listCtrl ctrlShow false;
        _pictureCtrl ctrlShow false;
    };
    
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_"+_which,nil];
    private _factions = missionNamespace getVariable ["FACTIONS_SELECTED_"+_which,[]];
    if (count _factions != 1) exitWith {
        private _warningCtrl = uiNamespace getVariable "FactionWarningCtrl";
        _warningCtrl ctrlSetText "Only one faction must be selected to choose individual units"; 
        _warningCtrl ctrlShow true;
        sleep 5;
        _warningCtrl ctrlShow false;
    };
    if ((_factions#0) select [0,8] isEqualTo "'CUSTOM'") exitWith {
        private _warningCtrl = uiNamespace getVariable "FactionWarningCtrl";
        _warningCtrl ctrlSetText "Cannot select units from a custom faction"; 
        _warningCtrl ctrlShow true;
        sleep 5;
        _warningCtrl ctrlShow false;
    };
    
    // populate and show the list of units
    private _units = [_factions] call FactionUnits;
    ctrlSetText [_btnIdc,"Cancel"];
    lbClear _listCtrl;
    {       
        private _idx = _listCtrl lbAdd getText (configFile >> "CfgVehicles" >> _x >> "displayName");
        _listCtrl lbSetData [_idx,_x];
        _listCtrl lbSetSelected [_idx,true];
    } forEach _units;
    _listCtrl ctrlShow true;
    _pictureCtrl ctrlShow true;
};

FactionUnits_Clicked = {
    // units selection changed
    params ["_which","_selected"]; // _which = 'P', 'E', or 'C'  _selected is just the most recent clicked item
    private _listCtrl = uiNamespace getVariable (switch (_which) do {case "P": {"FactionUnitListCtrlP"};case "E": {"FactionUnitListCtrlE"};case "C": {"FactionUnitListCtrlC"};});
    private _pictureCtrl = uiNamespace getVariable "FactionPictureCtrl";
    private _units = [];
    private _choosenIndexs = lbSelection _listCtrl;
    private _choosenUnits = [];
    {
        _choosenUnits pushBack _x;
    } forEach _choosenIndexs;
    _pictureCtrl ctrlShow true;
    _pictureCtrl ctrlSetText (getText (configFile >> "CfgVehicles" >> (_listCtrl lbData _selected) >> "editorPreview"));
    missionNamespace setVariable ["FACTIONS_UNIT_SELECTED_"+_which, _choosenUnits];
};

FactionUnits_Check = {
    // call to convert faction to units - adds new faction if needed
    // input can be a string or an array of strings
    // faction is    "Faction:subFactID"    or   "'CUSTOM'XXXX|Faction:subFactID;unitID,unitID,"  - where XXXX and items ending in ID are a number
    //         or   ["CustomFaction|Faction:subFactID;unitId,unitId,"]
    //         or   ["Faction:subFactID","Faction:subFactID","Faction:subFactID",...]
    // Note custom factions in an array must be the only array element
    // returns faction name stripped of rebuild data
    private _factionArray = _this;
    private _isArray = typeName _factionArray isEqualTo "ARRAY";
    if (_isArray && {count _factionArray != 1}) exitWith {_factionArray};    
    private _faction = if (_isArray) then {_factionArray#0} else {_factionArray};
    private _parts = _faction splitString "|";
    if (count _parts > 1) then {
        private _factionData = missionNamespace getVariable ["FactionData",[]];
        if (_factionData isEqualTo [] && {! (call Factions_WaitDataReady)}) exitWith {
            diag_log "ERROR: FactionUnits_Check called before factions setup with FactionSelect or FactionSelection_CollectFactions!";
            _faction
        };
        
        private _customName = _parts#0;
        private _idx = [_factionData,_customName] call Faction_FindKey;
        if (_idx >= 0) then {
            _faction = _customName;
        } else {
            private _customFactionDef = _parts#1;
            private _factionParts = _customFactionDef splitString ":;";
            _faction = _factionParts#0;
            
            _idx = [_factionData,_faction] call Faction_FindKey;
            if (_idx >= 0) then {
                private _thisFactionData = _factionData#_idx;                       
                if ((_thisFactionData#5) isEqualTo "") then {
                    private _subIndex = if (count _factionParts > 2) then {parseNumber (_factionParts#1)} else {-1};
                    private _unitIdxArray = (_factionParts#-1) splitString "," apply {parseNumber _x};
                    private _subFactionsData = _thisFactionData#4;
                    private _newSubFactionData = [];
                    if (_subIndex < 0 || {_subIndex > count _subFactionsData}) then {
                        // use entire faction
                        private _unitCntr = 0;
                        {
                            _x params ["_subName","_subUnits"];
                            private _keepUnits = [];
                            {
                                if (_unitCntr in _unitIdxArray) then {_keepUnits pushBack _x};
                                _unitCntr = _unitCntr + 1;
                            } forEach _subUnits;
                            if !(_keepUnits isEqualTo []) then {_newSubFactionData pushBack [_subName,_keepUnits]};
                        } forEach _subFactionsData; 
                    } else {
                       // use just sub faction
                        private _subName = _subFactionsData#_subIndex#0;
                        private _subUnits = _subFactionsData#_subIndex#1;
                        private _keepUnits = [];
                        {
                            if (_forEachIndex in _unitIdxArray) then {_keepUnits pushBack _x};
                        } forEach _subUnits;
                        if !(_keepUnits isEqualTo []) then {_newSubFactionData pushBack [_subName,_keepUnits]};
                    };                
                    if !(_newSubFactionData isEqualTo []) then {
                        private _semiIdx = _customFactionDef find ";";
                        if (_semiIdx >= 0) then {_customFactionDef = (_customFactionDef select [0,_semiIdx]) + ";" + (_customFactionDef select [_semiIdx+1,1e5])};
                        _customFactionDef = _customName + "|" + _customFactionDef;
                        // create custom faction
                        private _customFaction = +_thisFactionData;
                        _customFaction set [0,_customName];
                        _customFaction set [1,"Custom:"+(_customFaction#1)];
                        _customFaction set [4,_newSubFactionData];
                        _customFaction set [5,_customFactionDef];
                        (missionNamespace getVariable ["FactionData",[]]       ) pushBack _customFaction;
                        (missionNamespace getVariable ["FactionDataLimited",[]]) pushBack _customFaction;
                        _faction = _customName;
                    };
                };
            };
        };
        _factionArray = (if (_isArray) then {[_faction]} else {_faction});
    };
    _factionArray
};

_compileFinal = {
    params [["_var","",[""]], ["_ns",missionNamespace,[missionNamespace]]];
    private _code = _ns getVariable [_var, 0];
    if (typeName _code != typeName {}) exitWith {};
    _codestr = str _code;
    _codestr = _codestr select [1,count _codestr - 2]; // remove begin and end parenthesizes 
    _code = compileFinal _codestr;
    _ns setVariable [_var, _code];
};

["FactionSelect"] call _compileFinal;
["FactionRoles"] call _compileFinal;
["FactionUnits"] call _compileFinal;
["FactionCheck"] call _compileFinal;
["FactionSide"] call _compileFinal;
["FactionSideNum"] call _compileFinal;
["FactionName"] call _compileFinal;
["FactionFlag"] call _compileFinal;
["FactionSetOkayBtnText"] call _compileFinal;
["FactionDlcId"] call _compileFinal;
["FactionSanitizeCivilians"] call _compileFinal;
["FactionSelection_Wait"] call _compileFinal;
["FactionSelection_Start"] call _compileFinal;
["FactionSelection_CollectFactions"] call _compileFinal;
["FactionSelection_PopulateListboxes"] call _compileFinal;
["FactionSelection_PlayerClicked"] call _compileFinal;
["FactionSelection_EnemyClicked"] call _compileFinal;
["FactionSelection_CivilianClicked"] call _compileFinal;
["FactionSelection_Complete"] call _compileFinal;
["FactionSelection_ResetClick"] call _compileFinal;
["FactionSelection_PerMapChecked"] call _compileFinal;
["FactionSelection_Defaults"] call _compileFinal;
["Factions_RoleFix"] call _compileFinal;
["Faction_FindKey"] call _compileFinal;
["Faction_FindSubFaction"] call _compileFinal;
["Faction_CheckUnitList"] call _compileFinal;
["Factions_GetData"] call _compileFinal;
["Factions_SetInfo"] call _compileFinal;
["Factions_WaitDataReady"] call _compileFinal;
["FactionGetCheckBoxStates"] call _compileFinal;
["FactionBase"] call _compileFinal;
["FactionConvertToBaseList"] call _compileFinal;
["FactionInBaseList"] call _compileFinal;
["FactionSelection_SubFactionsChecked"] call _compileFinal;
["FactionSelection_MultiSelectChecked"] call _compileFinal;
["FactionUnits_Check"] call _compileFinal;
["FactionUnits_Clicked"] call _compileFinal;
["FactionSelectUnits_Click"] call _compileFinal;
["FactionSelection_CustomDef"] call _compileFinal;
["FactionSelection_CustomName"] call _compileFinal;
["Faction_SubIndex"] call _compileFinal;
["Faction_CheckMod"] call _compileFinal;
