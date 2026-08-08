#include "defines.hpp"

diag_log "ITW: Start";

"itw" cutText ["","BLACK",0.001];

LV_PAUSE = false;

[false] call FactionSelection_CollectFactions;
    
"itw" cutText ["","PLAIN",0.001];

// determine factions first thing
if (isServer) then {
    west setFriend [resistance,0];
    resistance setFriend [west,0];
    
    // check saved game && verify overwrite  
    if (ITW_ParamResetParamsEraseSave != 0) then {
        private _client = if (hasInterface) then {2} else {0};
        if (_client == 0) then {
            private _players = [];
            while {count _players == 0} do {_players = (allPlayers - entities "HeadlessClient_F")};
            _client = _players#0;
        };
        ITW_ResetFlag = nil;
        [ITW_ParamResetParamsEraseSave] remoteExec ["ITW_ParamResetConfimation",_client];
        waitUntil {!isNil "ITW_ResetFlag"}; 
        if (ITW_ResetFlag > 0 && {ITW_ResetFlag == ITW_ParamResetParamsEraseSave}) then {
            if (ITW_ResetFlag in [1,3]) then {
                // Reset Params
                diag_log "ITW: Resetting Parameters";
                {
                    call compile format ["profileNamespace setVariable ['%1',nil]",_x];
                } forEach ITW_AllParams;
            };
            if (ITW_ResetFlag in [2,3]) then {
                // Erase saved game data
                diag_log "ITW: Erasing Saved Maps";
                {
                    [_x] call ITW_EraseGame;
                } forEach (parsingNamespace getVariable "ITW_SavedMaps");
            };
            
            ITW_ResetActionComplete = 1;
            publicVariable "ITW_ResetActionComplete";
            sleep 1000;
        };
    };
    
    // check saved game && verify overwrite
    private _loadGame = [true] call ITW_LoadGame;    
    if (_loadGame && {ITW_ParamNewGame == 1}) then {
        private _client = if (hasInterface) then {2} else {0};
        if (_client == 0) then {
            private _players = [];
            while {count _players == 0} do {_players = (allPlayers - entities "HeadlessClient_F")};
            _client = _players#0;
        };
        ITW_NewGameFlag = nil;
        [] remoteExec ["ITW_NewGameConfirmation",_client];
        waitUntil {!isNil "ITW_NewGameFlag"};     
        if (ITW_NewGameFlag == 0) then {
            diag_log "ITW: User selected to keep saved game";
            ITW_ParamNewGame = 0;
        } else {
            diag_log "ITW: User selected to erase saved game";
            _loadGame = false;
        };
    };
    
    private _defFactionsP = profileNamespace getVariable [format["ITW_FactionsP%1",worldName],["BLU_F"]];
    private _defFactionsE = profileNamespace getVariable [format["ITW_FactionsE%1",worldName],["OPF_F"]];
    private _defFactionsC = profileNamespace getVariable [format["ITW_FactionsC%1",worldName],["CIV_F"]];
    ITW_PlayerVehicles = [];
    ITW_EnemyVehicles = [];
    ITW_VehicleDlcs = profileNamespace getVariable [format["ITW_Dlcs%1",worldName],0];
    ITW_PlayerFaction = _defFactionsP;
    ITW_EnemyFaction =  _defFactionsE;
    ITW_CivFaction =  _defFactionsC;
    ITW_EnemySide = if ([ITW_EnemyFaction] call FactionSide == east) then {east} else {independent};
    
    private _chooseFaction = ITW_ParamNewGame == 2 || !_loadGame;
    if (!_chooseFaction && {!([[_defFactionsP,_defFactionsE,_defFactionsC]] call FactionCheck)}) then {
        _chooseFaction = true;
        diag_log format ["ITW: Faction check failed. Faction selection triggered: %1",[_defFactionsP,_defFactionsE,_defFactionsC]];
    };
    if (_chooseFaction) then {
        diag_log "ITW: Faction selection...";
        private _checkBoxes = profileNamespace getVariable [format["ITW_FactionsCkBox%1",worldName],[true,false,false]];
        _factionInfo = [_defFactionsP,_defFactionsE,objNull,_defFactionsC,true,_checkBoxes] call FactionSelect;
        
        profileNamespace setVariable [format["ITW_FactionsCkBox%1",worldName],call FactionGetCheckBoxStates];
        profileNamespace setVariable [format["ITW_FactionsP%1",worldName],_factionInfo#0];
        profileNamespace setVariable [format["ITW_FactionsE%1",worldName],_factionInfo#1];
        profileNamespace setVariable [format["ITW_FactionsC%1",worldName],_factionInfo#2];
        
        if (_factionInfo#4) then {
            // Multi Is All checkbox checked
            ITW_PlayerFaction = _factionInfo#0;
            ITW_EnemyFaction  = _factionInfo#1;
            ITW_CivFaction    = _factionInfo#2;
        } else {
            ITW_PlayerFaction = selectRandom (_factionInfo#0);
            ITW_EnemyFaction  = selectRandom (_factionInfo#1);
            ITW_CivFaction    = _factionInfo#2; // we always want civ to use all the selected factions
        };
        ITW_EnemySide = if ([ITW_EnemyFaction] call FactionSide == east) then {east} else {independent};
    
        if (ITW_ParamVehicleChooser == 1 || {ITW_ParamVehicleChooser == 3}) then {
            ITW_EnemyVehicles = [true,localize "STR_ITW_START_ChooseEnemyVeh",objNull,ITW_EnemyFaction] call VehicleChooser;
            diag_log format ["ITW: enemy vehicles override, %1 vehicles",count (ITW_EnemyVehicles select {!(_x isEqualTo [])})];
        };
        if (ITW_ParamVehicleChooser == 2 || {ITW_ParamVehicleChooser == 3}) then {
            ITW_PlayerVehicles = [true,localize "STR_ITW_START_ChoosePlayerVeh",objNull,ITW_PlayerFaction] call VehicleChooser;
            diag_log format ["ITW: player vehicles override, %1 vehicles",count (ITW_PlayerVehicles select {!(_x isEqualTo [])})];
        }; 
        if (ITW_ParamVehicleChooser == 4 || {ITW_ParamVehicleChooser == 6}) then {
            ITW_EnemyVehicles = [true,localize "STR_ITW_START_ChooseEnemyVehAdd",objNull,ITW_EnemyFaction] call VehicleChooser;
            diag_log format ["ITW: enemy vehicles add, %1 vehicles",count (ITW_EnemyVehicles select {!(_x isEqualTo [])})];
        };
        if (ITW_ParamVehicleChooser == 5 || {ITW_ParamVehicleChooser == 6}) then {
            ITW_PlayerVehicles = [true,localize "STR_ITW_START_ChoosePlayerVehAdd",objNull,ITW_PlayerFaction] call VehicleChooser;
            diag_log format ["ITW: player vehicles add, %1 vehicles",count (ITW_PlayerVehicles select {!(_x isEqualTo [])})];
        }; 
        profileNamespace setVariable [format["ITW_EnemyVehicles%1",worldName],ITW_EnemyVehicles];
        profileNamespace setVariable [format["ITW_PlayerVehicles%1",worldName],ITW_PlayerVehicles];  
    } else {
        if (ITW_ParamVehicleChooser in [1,3,4,6]) then {
            ITW_EnemyVehicles  = profileNamespace getVariable [format["ITW_EnemyVehicles%1",worldName] ,[]];
            diag_log format ["ITW: enemy vehicles override, %1 vehicles",count (ITW_EnemyVehicles select {!(_x isEqualTo [])})];
        };
        if (ITW_ParamVehicleChooser in [2,3,5,6]) then {
            ITW_PlayerVehicles = profileNamespace getVariable [format["ITW_PlayerVehicles%1",worldName],[]]; 
            diag_log format ["ITW: player vehicles override, %1 vehicles",count (ITW_PlayerVehicles select {!(_x isEqualTo [])})];
        }; 
    };
    
    private _chooseVehsDLC = (ITW_ParamVehicles == 2 || ITW_ParamVehicles == 5) && {_chooseFaction || typeName ITW_VehicleDlcs == "SCALAR"};
    if (!(ITW_EnemyVehicles isEqualTo []) && !(ITW_PlayerVehicles isEqualTo [])) then {_chooseVehsDLC = false};
    if (typeName ITW_VehicleDlcs == "SCALAR") then {ITW_VehicleDlcs = []};
    if (_chooseVehsDLC) then {
        diag_log "ITW: DLC selection...";
        ([] call FactionDlcId) params ["_onlyDlcs","_removeDlcs"];
        ITW_VehicleDlcs = [ITW_VehicleDlcs,_onlyDlcs] call DlcSelect;
        profileNamespace setVariable [format["ITW_Dlcs%1",worldName],ITW_VehicleDlcs];
    };
    if (ITW_ParamVehicles != 2 &&  ITW_ParamVehicles != 5) then {profileNamespace setVariable [format["ITW_Dlcs%1",worldName],nil]};
    diag_log format ["ITW: Using dlcs %1",ITW_VehicleDlcs];

    if (ITW_ParamTargets != 0 && _chooseFaction) then {
        0 call ITW_TargetsSelection;
    };
    
    publicVariable "ITW_EnemySide";
    publicVariable "ITW_PlayerFaction";
    publicVariable "ITW_EnemyFaction";
    publicVariable "ITW_CivFaction";
    publicVariable "ITW_VehicleDlcs";
    publicVariable "ITW_EnemyVehicles";
    publicVariable "ITW_PlayerVehicles";
} else {
    waitUntil {!isNil "ITW_EnemySide"};
    waitUntil {!isNil "ITW_PlayerFaction"};
    waitUntil {!isNil "ITW_EnemyFaction"};
    waitUntil {!isNil "ITW_CivFaction"};
    waitUntil {!isNil "ITW_EnemyVehicles"};
    waitUntil {!isNil "ITW_PlayerVehicles"};
};
ITW_PlayerSide = west;

private _flagP = toLowerANSI ([ITW_PlayerFaction] call FactionFlag) select [1];
ITW_PlayerFlag = if (fileExists _flagP) then {_flagP} else {"a3\data_f\flags\flag_blue_co.paa"};
private _flagE = toLowerANSI ([ITW_EnemyFaction] call FactionFlag) select [1];
ITW_EnemyFlag = if (fileExists _flagE && {_flagP != _flagE}) then {_flagE} else {"a3\data_f\flags\flag_red_co.paa"};

// Handle non human factions
if (hasInterface) then {
    waitUntil {player == player};
    waitUntil {!isNull (findDisplay 46)};
    0 call ITW_FncNonHumanSwitch;
};

if (hasInterface) then {"itw" cutText [localize "STR_ITW_MISC_ChoosingFaction", "BLACK OUT", 0.001];};

ITW_AIEnemyName = [ITW_EnemyFaction] call FactionName;
diag_log format ["ITW: Factions: player %1  enemy %2 (%3)  civ %4",
    ITW_PlayerFaction,ITW_EnemyFaction,ITW_EnemySide,if (ITW_ParamCivilians==0) then [{"none"},{ITW_CivFaction}]];
    
ITW_AllyUnitTypes = [ITW_PlayerFaction,["Crewman","Diver"],true,call FACTION_UNIT_FALLBACK_SUBF_BLU] call FactionUnits;

[ITW_PlayerFaction,ITW_EnemyFaction,ITW_CivFaction] call ITW_FncSogPrairieFireFix;

call CustomArsenal_Init;

[ITW_ParamVirtualArsenal, ITW_PlayerFaction] call CustomArsenal_Setup;

if (hasInterface) then {
    // --- PLAYERS ---    
    profileNamespace getVariable [format["ITW_Roles%1",worldName],[0,1]] call ITW_BaseResetRoles;

    // temp fix for backward compatibility
    if (ITW_ParamFriendlyRevive == 2) then {ITW_ParamFriendlyRevive = -1;profileNamespace setVariable ["ITW_ParamFriendlyRevive",ITW_ParamFriendlyRevive]};
    if (ITW_ParamFriendlyRevive == -1) then {[player] call BIS_fnc_disableRevive};
    
    enableTeamSwitch false;
    enableSentences true;  
    
    // if hosting, we need to spawn this stuff, so the server stuff can be setup
    [] spawn { 
        
        sleep 2;       
        
        waitUntil{! isNil "VEHICLE_ARRAYS_COMPLETE"};
        waitUntil{! isNil "ITW_GameReady"};
        sleep 1;
        
        // if nighttime, don NVGs
        if (call ITW_FncIsNight) then {
            private _nvgs = [player] call ITW_FncGetNVGs;
            if (_nvgs isEqualTo []) then {
                if (ITW_ParamForceNVGs) then {
                    player linkItem "NVGoggles";
                };
            } else {
                player assignItem (_nvgs#0);
            };
        };
        
        player enableAI "MOVE";
        player switchMove "";
        ([] call ITW_ObjGetPlayerSpawnPtDir) params ["_spawnPos","_spawnDir"];
        player setPosATL _spawnPos;
        player setDir _spawnDir;
        
        if (isNil "ITW_PlayersSpawnedIn") then {
            ITW_PlayersSpawnedIn = true;
            publicVariable "ITW_PlayersSpawnedIn";
        };
        
        "itw" cutText [format [localize "STR_ITW_START_EnemyFactionFMT",ITW_AIEnemyName],"BLACK IN",5];
        
        call ITW_RadioInit;
        0 spawn ITW_ObjFlagHud;
        0 spawn ITW_ObjRedOut;
        call ITW_FortificationsInit;
    
        execVM "briefing.sqf"; // call after player moved to AO
        
        // zoom the map to the AO and disable textures by default first time map is opened
        addMissionEventHandler [ "Map",
            {	
                params ["_isOpened","_isForced"];
                if (_isOpened) then {
                    ctrlActivate ((findDisplay 12) displayCtrl 107); // Auto activate the textures button
                    private _objs = [] call ITW_ObjGetContestedObjs;
                    if (_objs isEqualTo []) exitWith {};
                    if (count _objs == 1) then {_objs = _objs + [ITW_Objectives#0]};
                    private _ptX = 0;
                    private _ptY = 0;
                    private _ptCnt = 0;
                    private _minX = 1e10;
                    private _minY = 1e10;
                    private _maxX = -1e10;
                    private _maxY = -1e10;           
                    {
                        private _pt = _x#ITW_OBJ_POS;
                        private _i = _pt#0;
                        private _j = _pt#1;
                        _ptX = _ptX + _i;
                        _ptY = _ptY + _j; 
                        _ptCnt = _ptCnt + 1;
                        if (_i < _minX) then {_minX = _i};
                        if (_j < _minY) then {_minY = _i};
                        if (_i > _maxX) then {_maxX = _i};
                        if (_j > _maxY) then {_maxY = _i};
                    } forEach _objs;
                    _ptX = _ptX / _ptCnt;
                    _ptY = _ptY / _ptCnt;
                    private _verticalSizeInMeters = 2 * ((_maxY - _minY) max (_maxX - _minX));
                    private _scale = 1.8 * _verticalSizeInMeters / worldsize;
                    mapAnimAdd [0,_scale,[_ptX,_ptY]]; 
                    mapAnimCommit;
                    removeMissionEventHandler ["Map",_thisEventHandler];
                };
            }
        ];
        
        private _addPlayerActions = {
            private _actionNames = actionIDs player apply {(player actionParams _x) #0};
            if (ITW_ParamAddEject == 1) then {
                private _ejectText = "<t color='#ffbbbb'>" + localize "STR_ITW_START_Eject" + "</t>";
                if !(_ejectText in _actionNames) then {
                    player addAction [_ejectText,{moveOut player},nil,0.2,false,true,"",
                        "vehicle _this != _this && {getPosATL _this #2 > 55 && {incapacitatedState _this == ''}}",-1];
                 };
             };
            private _fastTravelText = localize "STR_ITW_START_FastTravelInVeh";
            if !(_fastTravelText in _actionNames) then {
                // add vehicle fast travel from repair points
                player addAction [_fastTravelText,{
                    params ["_target", "_caller", "_actionId", "_arguments"];
                    [] spawn ITW_RadioFastTravel;
                },nil,10,false,true,"","_this != _target && {!(_target isKindOf 'Air') && {speed _target < 2 && {
                    !isNil 'ITW_VehFTPoints' && {!([] isEqualTo (ITW_VehFTPoints select {_x distance _this < 15})) || { 
                    !isNil 'ITW_VehRepairArray' && {!([] isEqualTo (ITW_VehRepairArray select {(_x#0) distance _this < (_x#1)} select {(_x#3) call (_x#2)} )) }}}}}}",0];
            };
            private _towText = localize "STR_ITW_SDO_TowPickVeh";
            if !(_towText in _actionNames) then {
                call ITW_SideOpsTowAddActions;
            };
        };
        call _addPlayerActions;
        player addEventHandler ["Respawn", _addPlayerActions];         
        [ missionNamespace, "reviveRevived",_addPlayerActions] call BIS_fnc_addScriptedEventHandler;
        
        if (ITW_ParamPlayerDeathChance > 0 && {ITW_ParamFriendlyRevive == 1}) then {
            player addEventHandler ["Dammaged",{
                params ["_unit", "_hitSelection", "_damage", "_hitPartIndex", "_hitPoint"];
                if (alive _unit && {_damage >= 1 && {_hitPoint == "Incapacitated" && {lifeState _unit isEqualTo "INCAPACITATED" && {_unit getVariable ["itw_incapTime",0] < time}}}}) then {
                    _unit setVariable ["itw_incapTime",time + 20];
                    if (random 100 < ITW_ParamPlayerDeathChance) then {
                        #define DEATH_REASON_BLEEDOUT 11  // from A3\functions_f_mp_mark\revive\defines.inc
                        bis_revive_deathReason = DEATH_REASON_BLEEDOUT;
                        _unit setDamage 1;
                    };
                };
            }];
        };
        
        player addEventHandler ["GetOutMan", {
            params ["_unit", "_role", "_vehicle", "_turret", "_isEject"];
            if (!local _unit || {vehicle _unit == _vehicle || {!alive _unit || {_unit getVariable ["itwIgnoreGetOut",false]}}}) exitWith {};
            if ((getPos _unit)#2 > 30) then {  // getPos to handle land or sea 
                0 spawn {
                    waitUntil {(getPos player)#2 < 50}; // getPos to handle land or sea 
                    [player] call BIS_fnc_halo; 
                };
                
                // if last player ejected, then teammates should eject too
                private _teammatesInCrew = crew _vehicle select {!(isPlayer _x) && {group _x == group player}};
                if !(_teammatesInCrew isEqualTo []) then {
                    [_vehicle,_teammatesInCrew] spawn {
                        params ["_veh","_units"];
                        private _toggle = true;
                        private _speed = speed _veh;
                        {
                            sleep 1;
                            private _unit = _x;
                            if (!alive _unit) then {continue};
                            _unit setDamage 0;
                            _unit call ITW_FncAceHeal;
                            [_unit, false] remoteExec ["setUnconscious",_x];
                            [_unit, false] remoteExec ["setCaptive",_x];
                            private _dirTo = getDir _veh;
                            private _vPos = getPosASL _veh;
                            private _pos = if (_toggle) then {_veh modeltoWorld [7, -20, -10]} else {_veh modeltoWorld [-7, -20, -10]};
                            if (_pos#2 < 0) then {_pos set [2,0]};
                            _toggle = !_toggle;
                            moveOut _unit;
                            _unit setPosASL _pos;
                            [_unit,_speed] spawn {
                                params ["_unit","_speed"];
                                waitUntil {(getPos _unit)#2 < 50}; // getPos to handle land or sea 
                                [_unit,getPosASL _unit,_speed] call ITW_AtkParachute;
                            };
                        } forEach _units;
                    };
                };
            };
        }];
        
        player addEventHandler ["WeaponAssembled", {
            params ["_unit", "_weapon", "_primaryBag", "_secondaryBag"];
            if (unitIsUAV _weapon) then {
                { deleteVehicle _x } forEach crew _weapon;
                west createVehicleCrew _weapon;
            };
        }];
        
        ITW_ArsenalCheck = {
            params ["_display"];
            private _okay = true;
            private _flag = nearestObject [getPos player,FLAG_TYPE];
            if (!isNull _flag) then {
                if (_flag distance player < 10 && 
                {!(_flag getVariable ["ITW_FlagIsPlayer",true]) ||
                {_flag getVariable ["ITW_FlagPhase",1] < 1}}) then {_okay = false};
            };
            if (!_okay) then {
                hint localize "STR_ITW_START_ArsenalBlocked";
                _display closeDisplay 0;
            };
        };
        
        if (!isNil "CBA_fnc_addEventHandler" && {!isNil "ace_arsenal_fnc_removeVirtualItems"}) then {
            ["ace_arsenal_displayClosed", {player setDamage 0;player call ITW_FncAceHeal;call ITW_TeammatesHeal; 
                    [] call ITW_TeammateArsenalExit;}] call CBA_fnc_addEventHandler;
            ["ace_arsenal_displayOpened", { [] spawn {sleep 0.5; [findDisplay 1127001] call ITW_ArsenalCheck}}] call CBA_fnc_addEventHandler;
        }; 
        [missionNamespace, "arsenalOpened", {
            [uiNamespace getVariable 'RscDisplayArsenal'] call ITW_ArsenalCheck;
        }] call BIS_fnc_addScriptedEventHandler;         	
           
        player addEventHandler ["InventoryClosed", {
            params ["_player", "_container"];
            if ((_player getslotitemname 612) isKindOf ["UavTerminal_base", configFile >> "CfgWeapons"]) then {
                // player can only use B_UAVTerminal since player side is west
                _player linkItem "B_UAVTerminal";
            };
        }];
        
        [missionNamespace, "arsenalClosed", {
            if ((_player getslotitemname 612) isKindOf ["UavTerminal_base", configFile >> "CfgWeapons"]) then {
                // player can only use B_UAVTerminal since player side is west
                _player linkItem "B_UAVTerminal";
            };
            
            private _restocked = "";
            private _healed = "";
            [] call ITW_TeammateArsenalExit;
            
            // add full heal on entering arsenal
            if (damage player > 0.1) then {
                _healed = localize "STR_ITW_START_YouveBeenHealed";
            };
            player setDamage 0;
            player call ITW_FncAceHeal;
            call ITW_TeammatesHeal;
            
            // if leader restocked, then restock AI teammates
            if (leader player == player) then {
                {
                    private _unit = _x;
                    if (!isPlayer _unit) then {
                        private _saved = _unit getVariable ["ITW_loadout",[]];
                        if !(_saved isEqualTo []) then {
                            private _current = getUnitLoadout _unit;
                            private _sameGear = true;
                            for "_i" from 0 to 7 do {
                                if (_i < 6) then {
                                    if (((_saved#_i) isEqualTo []) != ((_current#_i) isEqualTo [])) exitWith {_sameGear = false};
                                    if (_saved#_i#0 != (_current#_i#0)) exitWith {_sameGear = false};
                                } else {
                                    if (_saved#_i != (_current#_i)) exitWith {_sameGear = false};
                                };
                                if (!_sameGear) exitWith {};
                            };
                            if (_sameGear) then {
                                waitUntil {!isSwitchingWeapon _unit}; 
                                _unit setUnitLoadout _saved;
                                _restocked = localize "STR_ITW_START_TeammatesRestocked";
                            } else {
                                _unit setVariable ["ITW_loadout",getUnitLoadout _unit,true];
                            };
                        };
                    };
                } forEach units player;
            };
            
            // notifications
            if !(_restocked isEqualTo "" && {_healed isEqualTo ""}) then {
                [format ["\n\n\n\n%1\n%2",_healed,_restocked],!(_healed isEqualTo "")] spawn {
                    params ["_msg","_flashWhite"];
                    if (_flashWhite) then {
                        cutText ["","WHITE OUT",0.3]; 
                        sleep 0.3;
                        cutText ["","WHITE IN",0.3];
                    };
                    "arsenalClosed" cutText [_msg,"PLAIN"];
                    sleep 4;
                    "arsenalClosed" cutText ["","PLAIN"];
                };
            };
        }] call BIS_fnc_addScriptedEventHandler;         	
        
        addMissionEventHandler ["CommandModeChanged", { 
            params ["_isHighCommand", "_isForced"]; 
            if (_isHighCommand && {!(player in ITW_HcCmdr)}) exitWith {hcShowBar false}; // if not high commander, don't allow entering high command
            setGroupIconsVisible [_isHighCommand,false]; // only show icons on map while in high command
        }];
        
        [missionNamespace, "garageOpened",
            {
                params ["_display", "_toggleSpace"];
                _this spawn ITW_GaragePylons;
            }] call BIS_fnc_addScriptedEventHandler;
        
        call ITW_GarageInit;
         
        Zeus1 addEventHandler ["CuratorGroupPlaced", {
            params ["_curator", "_group"];
            if (side _group == ITW_PlayerSide) then {[_group] remoteExec ["ITW_AllyGroupCallback",2]};
        }];
        
        if (ITW_ParamTeamSwitchAllow > 1) then {
            (findDisplay 46) displayAddEventHandler ["KeyDown", {
                private _override = false;
                if (inputAction "TeamSwitch" > 0) then {0 call ITW_AllyTeamSwitch;_override=true};
                _override
            }];
            //addUserActionEventHandler ["TeamSwitch", "Activate", {0 call ITW_AllyTeamSwitch}];
        };
            
        // hide the uss liberty that the player initially spawned on (only hides locally)
        {
            if (_x isKindOf "Land_Destroyer_01_hull_base_F") then {_x hideObject true};
        } forEach (DESTROYER nearObjects 100);
        
        // Changes to work with various mods
        // HCC (High Command Changer)
        if (!isNil "IGIT_HCC_HC_Groups_Array") then {IGIT_HCC_HC_Groups_Array = []}; // hack for HCC (High Command Converter)
        // UVO (Unit Voice Overs)
        if (!isNil "uvo_main_customVoices") then {
            private _faction = if (typeName ITW_PlayerFaction isEqualTo "STRING") then {ITW_PlayerFaction} else {ITW_PlayerFaction#0};
            private _index = uvo_main_customVoices findIf {_x # 0 == _faction};

            if (_index != -1) then {
                private _voices = (uvo_main_customVoices # _index # 1) select {missionNamespace getVariable ["uvo_main_UVO" + _x,true]};

                if !(_voices isEqualTo []) then {
                    _voices spawn {
                        scriptName "UvoAdjuster";
                        private _voices = _this;
                        private _adjustedPlayers = [];
                        while {true} do {
                            private _allPlayers = allPlayers;
                            {                          
                                private _unit = _x;
                                _voice = selectRandom _voices;
                                _unit setVariable ["UVO_voice",_voice,true];
                                _unit setVariable ["UVO_suppressBuffer",0,true];
                                _unit setVariable ["UVO_allowDeathShouts",missionNamespace getVariable ["uvo_main_UVO" + _voice,true],true];
                                _adjustedPlayers = _allPlayers;
                            } forEach (_allPlayers - _adjustedPlayers);
                            sleep 30;
                        };
                    };
                };
            };
        };
    
        // if player is squad leader, add saved teammates to team (multiple saved teams get lost)
        if (leader player == player) then {[player] remoteExec ["ITW_TeammatesLoad",2]};
        
        // on dedicated servers, the high command icons can be all cyan, so fix that
        0 spawn {
            while {isNil "BIS_marta_mainscope"} do {sleep 5};
            private _logic = BIS_marta_mainscope;
            // BAD:  "rules" == [["o_",[0,1,1,0.8]],["b_",[0,1,1,0.8]],  ["n_",[0,1,1,0.8]],["n_",[0,1,1,0.8]]]  NOTE: 0.8 can vary by 1E-5 or some such
            // GOOD: "rules" == [["o_",[0.5,0,0,1]],["b_",[0,0.3,0.6,1]],["n_",[0,0.5,0,1]],["n_",[0.4,0,0.5,1]]]
            private _rules = _logic getVariable ["rules",[[0,1,1,1]]];
            private _color = _rules#0#1 select [0,3]; // only use first three values for comparision
            if (_color isEqualTo [0,1,1]) then {
                _logic setVariable ["rules",[["o_",[0.5,0,0,1]],["b_",[0,0.3,0.6,1]],["n_",[0,0.5,0,1]],["n_",[0.4,0,0.5,1]]]];
            };
        };
    };
};

if (hasInterface) then {"itw" cutText [localize "STR_ITW_START_ParsingVehicles", "BLACK OUT", 0.001];};
[ITW_EnemyFaction,ITW_PlayerFaction] execVM "VehicleArrays.sqf";

if (ITW_ParamViewDistance > 0) then {setViewDistance ITW_ParamViewDistance; setObjectViewDistance (ITW_ParamViewDistance/2)};

call ITW_TeammatesInit; // needs to be called on all clients & server

if (isServer) then {
    // --- SERVER ---
    // spawn so the player on the server gets black screen
        
    [] spawn {
        private _timeSpeedDay = ITW_ParamTimeMultiplier;
        [ITW_ParamTimeOfDay,_timeSpeedDay/2,_timeSpeedDay] call ITW_FncSetTime;
        [ITW_ParamWeather] call ITW_FncSetWeather;
                
        call ITW_VehiclesInit;
            
        if !(call ITW_LoadGame) then {
            false call ITW_ObjectivesSetup;
        };  
        call ITW_EnemyInit; 
        call ITW_AllyInit;
        0 spawn ITW_FncCleanup;
        
        { _x addCuratorEditableObjects [allPlayers,true]; } forEach allCurators;
                
        if (!hasInterface) then {call ITW_RadioInit};
        ITW_GameReady = true; // indicates enemy/friendly/objectives are setup and ready to play
        publicVariable "ITW_GameReady";
        
        [{LV_PAUSE = true},{LV_PAUSE = false},true] execVM "scripts\skull\SKL_Pause.sqf";
        
        diag_log "ITW: Game started";
        
        if (isDedicated) then {
            addMissionEventHandler ["PlayerDisconnected", { 
                [] spawn {
                    sleep 1; // BIS_fnc_listPlayers still shows the disconnecting player for a bit
                    if ([] call BIS_fnc_listPlayers isEqualTo []) then {
                        diag_log "ITW: Game paused with no players in game";
                        LV_Pause = true;
                        private _damageAbleUnits = [];
                        private _simulatedUnits = [];
                        {
                            if (simulationEnabled _x) then {
                                _simulatedUnits pushBack _x;
                                _x enableSimulation false;
                            };
                            if (isDamageAllowed _x) then {
                                _damageAbleUnits pushBack _x;
                                _x allowDamage false;
                            };
                        } forEach (allUnits + vehicles);
                        
                        while {[] call BIS_fnc_listPlayers isEqualTo []} do {sleep 1};
                                            
                        {_x enableSimulation true} forEach _simulatedUnits;
                        {_x allowDamage true} forEach _damageAbleUnits;
                        LV_Pause = false;
                        diag_log "ITW: Game resumed with some players in game";
                    };
                };
            }];
        };
        
        sleep 10; // wait a bit for the teammates to load in
        ["start"] call ITW_SaveGame; 
    };
};

// Hack to make sure no ai get stuck invulnerable
0 spawn {
    ScriptName "AllowDamage Checker";
    private _damageBlocked = [];
    while {true} do {
        sleep 70;
        while {LV_PAUSE} do {sleep 50};
        private _cnt = 0;
        {
            _cnt = _cnt + 1;
            if (_cnt > 20) then {_cnt = 0; sleep 0.1}; // give up the processor since this is a low priority check of a lot of units
            if (alive _x && {simulationEnabled  _x && {!isDamageAllowed _x && {!isPlayer _x && {side _x in [east,west,independent] && {!(_x getVariable ["itw_dmgBlocked",false])}}}}}) then {
                if (_x in _damageBlocked) then {
                    _x allowDamage true;
                    diag_log format ["AllowDamage Checker: fixed %1 - damage now allowed",str(_x)];
                    _damageBlocked = _damageBlocked - [_x];
                } else {
                    _damageBlocked pushBack _x;
                };
            };
        } forEach allUnits;
    };
};