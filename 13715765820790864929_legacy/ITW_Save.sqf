//
// Save data: [
//    ITW_Objectives  :  [playerDefendIndex, [pt1,pt2,...]
// ]

#include "defines.hpp"

ITW_SaveSem = false;

ITW_NewGameConfirmation = {
    diag_log "ITW: Checking if save game should be erased and new game crated";
    player enableSimulation false;
    ITW_NewGameFlag = nil;
    
    // ** Keypress Method **
    #define DIK_KEY_Y 21
    #define DIK_KEY_N 49    
    waitUntil {! isNull findDisplay 46 && player == player};
    "itw-sg" cutText [localize "STR_ITW_MISC_EraseSavedGame", "BLACK", 0.001,true,true];
    findDisplay 46 displayAddEventHandler ["KeyDown", 
    'params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];
    if (_key == DIK_KEY_Y || _key == DIK_KEY_N) then {
        if (_key == DIK_KEY_Y) then {
            ITW_NewGameFlag = 1;
        } else {
            ITW_NewGameFlag = 0;
        };
        findDisplay 46 displayRemoveEventHandler ["KeyDown",_thisEventHandler];
    };
    true'];
    waitUntil {!isNil "ITW_NewGameFlag"};
    
    // ** Commanding Menu Method **
    //ITW_CONFIRM_MENU = [
    //    ["Create New Game", false],
    //    ["NO, use saved game",   [2], "", -5, [["expression", "ITW_ParamNewGame=0"]], "1", "1"],
    //    ["Yes, ERASE SAVED GAME",[3], "", -5, [["expression", "ITW_ParamNewGame=1"]], "1", "1"]];
    //showCommandingMenu "#USER:ITW_CONFIRM_MENU";
    //sleep 1;
    //waitUntil {!isNil "ITW_ParamNewGame" || commandingMenu == ""};
    //if (isNil "ITW_ParamNewGame") then {ITW_ParamNewGame = 0};
    
    player enableSimulation true;
    publicVariable "ITW_NewGameFlag";
    "itw-sg" cutText ["","PLAIN",0.001];
};

ITW_ParamResetConfimation = {
    params ["_resetType"];
    if (_resetType == 0) exitWith {ITW_ResetFlag = 0;publicVariable "ITW_ResetFlag"};
    waitUntil {!isNull (findDisplay 46)}; 
    diag_log format ["ITW: Checking if params should be reset/games erased (%1)",_resetType];
    player enableSimulation false;
    private _msg = ["","STR_ITW_PARAM_Reset","STR_ITW_PARAM_EraseGame","STR_ITW_PARAM_ResetAndErase"] select _resetType;
    private _warning = "STR_A3_C_in1_notifLeaving_AoA1_title";
    private _response = [localize _msg, localize _warning, localize "STR_ITW_COMMON_Yes", localize "STR_ITW_COMMON_No"] call BIS_fnc_guiMessage;
    if (_response) then {
        ITW_ResetActionComplete = nil;
        ITW_ResetFlag = _resetType;;
        publicVariable "ITW_ResetFlag";
        waitUntil {!isNil "ITW_ResetActionComplete"};  
        private _success = "str_a3_showcase_vehicles_end2_title";
        [localize _msg + " : " + localize _success, localize _success, localize "STR_SKL_COMMON_Okay"] call BIS_fnc_guiMessage;
        private _endType = ["","endParamReset","endEraseSaves","endParamResetEraseSaves"] select _resetType;
        [_endType, true, 0, false, false] remoteExec ["BIS_fnc_endMission",0];
        sleep 1000;
    };
    player enableSimulation true;
    ITW_ResetFlag = 0;
    publicVariable "ITW_ResetFlag";
};

ITW_LoadGame = {
    if (!isServer) exitWith {diag_log "Error pos ITW_LoadGame called from client"};
    params [["_preLoad",false]];
    // returns TRUE if game was retrieved
    

    private _dataObj   = profileNamespace getVariable [format["ITW_SaveObj%1",worldName],[]];
    if (count _dataObj   != 4) exitWith {false};
    
    private _airfield  = profileNamespace getVariable [format["ITW_Airfield%1",worldName],[]];
    private _rallyPoint  = profileNamespace getVariable [format["ITW_RallyPoint%1",worldName],[]];
    private _warships  = profileNamespace getVariable [format["ITW_Warships%1",worldName],[]];
    private _teammates = profileNamespace getVariable [format["ITW_Teammates%1",worldName],[]];
    private _fortifications = profileNamespace getVariable [format["ITW_Fortifications%1",worldName],[[],[]]];
    private _misc = profileNamespace getVariable [format["ITW_Misc%1",worldName],[-1,-1,nil]];
    ITW_storedVehicles = profileNamespace getVariable [format["ITW_StoVeh%1",worldName],[]];
    
    // arrays must be copied so they don't get back-updated when we aren't ready
    private _zoneIndex = _dataObj#0;
    private _objectives = +(_dataObj#1);
    private _bases = +(_dataObj#2);
    private _captured = +(_dataObj#3);
    if (isNil "_zoneIndex" || isNil "_objectives" || isNil "_bases") exitWith {false};
    if (count _objectives < 3 || {count _objectives != count _bases}) exitWith {false};
    // check valid version
    if (count (_objectives#1) == (ITW_OBJ_ARRAY_SIZE - 1)) then {
         // backward compatible with before obj size was part of objectives
        _objectives apply {_x pushBack ITW_ParamObjectiveSize};
    };
    if (count (_objectives#1) != ITW_OBJ_ARRAY_SIZE) exitWith {false};
    
    // backward compatibility
    {
        while {count (_x#ITW_OBJ_ATTACKS) < 6} do {
            _x#ITW_OBJ_ATTACKS pushBack -1;
        };
        while {count (_x#ITW_OBJ_ATK_AVAIL) < 4} do {
            _x#ITW_OBJ_ATK_AVAIL pushBack false;
        };
    } forEach _objectives;
    
    if (_preLoad) exitWith {true};
    if (ITW_ParamNewGame == 1) exitWith {false};
    
    ["itw",[localize "STR_ITW_MISC_LoadingSavedGame", "BLACK OUT", 0.001]] remoteExec ["cutText",0];
    diag_log "ITW: game loading";
    
    if (true) then {
        diag_log ["ZoneIndex",_zoneIndex];
        diag_log ["Objectives",count (_objectives)];
        diag_log ["Airfield",!(_airfield isEqualTo [])];
        diag_log ["Rally Point",!(_rallyPoint isEqualTo [])];
        diag_log ["Warships",count _warships];
        diag_log ["Teammates",count _teammates];
        if (count _fortifications == 2 && {count (_fortifications#1) == 2}) then {
            diag_log ["Fortifications",count (_fortifications#0),count (_fortifications#1#0)];
        } else {diag_log ["Fortifications","old version",count _fortifications]};
    };
    
    private _date      = profileNamespace getVariable [format["ITW_Time%1",worldName],[]];
    
    if (count _date == 5) then {[_date] remoteExec ["setDate",0]};
    
    // handle misc first
    ITW_defendPhaseFlagCount = _misc#0;
    ITW_defendPhaseZoneDone = if (count _misc <= 1) then {-1} else {_misc#1};
    private _targetsAllowed = if (count _misc <= 2) then {[]} else {_misc#2};
    private _sideOps        = if (count _misc <= 3) then {[]} else {_misc#3};
    
    [_targetsAllowed]        call ITW_TargetsLoad;
    [_sideOps]               call ITW_SideOpsLoad;
    [_bases]                 call ITW_BaseLoad; // must be done prior to ITW_ObjLoad
    [_objectives,_zoneIndex,_captured] call ITW_ObjLoad;
    [_airfield]              call ITW_AirfieldLoad;
    [_rallyPoint]            call ITW_RallyPointLoad;
    [_warships]              call ITW_WarshipLoad;
    [_teammates]             call ITW_TeammatesLoad;
    [_fortifications]        call ITW_FortificationsLoad;
    
    // enable auto save feature
    if (isNil "ITW_AutoSaveRunning") then {
        ITW_AutoSaveRunning = true;
        ITW_AutoSaveTime = time + 600; // auto save in 10 minutes
        [] spawn ITW_SaveAutoTask;
    };
    true
};

ITW_SaveGame = {
    if (!isServer) exitWith {_this remoteExec ["ITW_SaveGame",2]};
    params [["_saveType","_none"]];
    if (!isNil "ITW_SaveDisable" && {ITW_SaveDisable}) exitWith {diag_log "ITW: Save disabled";ITW_AutoSaveTime = time + 600};
    if (ITW_ParamAutoSave == 0 && {_saveType != "manual"}) exitWith {};
    
    SEM_LOCK(ITW_SaveSem);
    
    diag_log format ["ITW: game saved (%1)",_saveType];   
    
    ITW_AutoSaveTime = time + 600; // auto save every 10 minutes
    
    // enable auto save feature
    if (ITW_ParamAutoSave == 2 && {isNil "ITW_AutoSaveRunning"}) then {
        ITW_AutoSaveRunning = true;
        [] spawn ITW_SaveAutoTask;
    };
    
    private _airfield = call ITW_AirfieldSave;
    private _rallyPoint = call ITW_RallyPointSave;
    private _warships = call ITW_WarshipSave;
    private _teammates = call ITW_TeammatesSave;
    private _fortifications = call ITW_FortificationsSave;
    private _sideOps = call ITW_SideOpsSave;
    
    private _objData = [ITW_ZoneIndex, +ITW_Objectives, +ITW_Bases, +ITW_ObjContestedState];
    profileNamespace setVariable [format["ITW_SaveObj%1",worldName],_objData];
    profileNamespace setVariable [format["ITW_Airfield%1",worldName],_airfield];
    profileNamespace setVariable [format["ITW_RallyPoint%1",worldName],_rallyPoint];
    profileNamespace setVariable [format["ITW_Warships%1",worldName],_warships];
    profileNamespace setVariable [format["ITW_Teammates%1",worldName],_teammates];
    profileNamespace setVariable [format["ITW_Fortifications%1",worldName],_fortifications];
    profileNamespace setVariable [format["ITW_StoVeh%1",worldName],ITW_storedVehicles];
    profileNamespace setVariable [format["ITW_Misc%1",worldName],[ITW_defendPhaseFlagCount,ITW_defendPhaseZoneDone,ITW_targetsAllowed,_sideOps]];
    profileNamespace setVariable [format["ITW_Time%1",worldName],date];

    // save a few adjustable parameters in case they were adjusted
    profileNamespace setVariable ["ITW_ParamFriendlyAiCntAdjustment",ITW_ParamFriendlyAiCntAdjustment];
    profileNamespace setVariable ["ITW_ParamVehicleSideAdjustment"  ,ITW_ParamVehicleSideAdjustment*10];
    SEM_UNLOCK(ITW_SaveSem);
    
    [] remoteExec ["ITW_SaveGameMP",0];
    if (_saveType in ["manual","zone","start"]) then {saveProfileNamespace;diag_log "saved to disk"};
};

ITW_GetSavedLoadout = {
    // call on each client   
    private _result = [[]];
    if !(isNil "ITW_LoadoutLoaded") exitWith {_result};
    ITW_LoadoutLoaded = true;
    if (!hasInterface) exitWith {_result};
    private _loadoutInfo = profileNamespace getVariable [format["ITW_Loadout%1",worldName],[]];
    if !(_loadoutInfo isEqualTo []) then {   
        _loadoutInfo params ["_faction","_loadout"];
        if (ITW_PlayerFaction isEqualTo _faction) then {_result = _loadout};
    };
    _result
};

ITW_SaveObjectives = {
    if (!isServer) exitWith {_this remoteExec ["ITW_SaveObjectives",2]};
    private _savedObjs = +_this;
    profileNamespace setVariable [format["ITW_SavedObjs%1",worldName],_savedObjs];
};

ITW_LoadObjectives = {
    // call on client with [] call ITW_LoadObjectives, will contact server and get return value
    params [["_client",nil]];
    private _result = [];
    if (isServer) then {
        private _savedObjs = profileNamespace getVariable [format["ITW_SavedObjs%1",worldName],[]];
        if !(isNil "_client") then {
            ITW_SavedObjs = _savedObjs;
            _client publicVariableClient "ITW_SavedObjs";
            ITW_SavedObjs = nil;
        } else {
            _result = +_savedObjs;
        };
    } else {
        ITW_SavedObjs = nil;
        [clientOwner] remoteExec ["ITW_LoadObjectives",2];
        private _timeout = time + 5;
        waitUntil {sleep 0.1;!isNil "ITW_SavedObjs" || time > _timeout};
        if (!isNil "ITW_SavedObjs") then {
            _result = ITW_SavedObjs;
            ITW_SavedObjs = nil;
        };
    };
    _result
};

ITW_LoadTargetsActive = {
    private _misc = profileNamespace getVariable [format["ITW_Misc%1",worldName],[-1,-1,[]]];
    if (count _misc <= 2) then {[]} else {_misc#2};
};

ITW_SaveGameMP = {
    // call on each client
    if (!hasInterface) exitWith {};
    if (isNil "ITW_LoadoutLoaded") exitWith {};
    profileNamespace setVariable [format["ITW_Loadout%1",worldName],[ITW_PlayerFaction,getUnitLoadout player]];
};

ITW_EraseGame = {
    if (!isServer) exitWith {_this remoteExec ["ITW_EraseGame",2]};
    params [["_worldName",worldName]];
    diag_log format ["ITW: game erased (%1)",_worldName];
    ITW_AutoSaveTime = 1e10;
    profileNamespace setVariable [format["ITW_SaveObj%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_SaveObj%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Airfield%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Warships%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Teammates%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Fortifications%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_StoVeh%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Time%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_Misc%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_RallyPoint%1",_worldName],nil];
    profileNamespace setVariable [format["ITW_RandomParams%1",_worldName],nil]; // used by params.sqf
    profileNamespace setVariable [format["ITW_Roles%1",_worldName],nil];        // used by ITW_Base.sqf
    profileNamespace setVariable [format["ITW_EnemyVehicles%1",_worldName],nil]; // used by ITW_Start.sqf
	profileNamespace setVariable [format["ITW_PlayerVehicles%1",_worldName],nil];// used by ITW_Start.sqf
	profileNamespace setVariable [format["ITW_DLCs%1",_worldName],nil];  
    [_worldName] remoteExec ["ITW_EraseGameMP",0];
};

ITW_EraseGameMP = {
    params [["_worldName",worldName]];
    //profileNamespace setVariable [format["ITW_Roles%1",worldName],nil];
    profileNamespace setVariable [format["ITW_Loadout%1",_worldName],nil];        // used by ITW_Start.sqf
    profileNamespace setVariable [format["ITW_TeamatesLocal%1",_worldName],nil];  // used by ITW_Teammates.sqf
};

ITW_SaveAutoTask = {
    scriptName "ITW_SaveAutoTask";
    if (!isServer) exitWith {diag_log "Error pos ITW_SaveAutoTask called from client"};
    waitUntil {!isNil "ITW_AutoSaveTime"};
    while {!ITW_GameOver} do {
        waitUntil {sleep (1 + ITW_AutoSaveTime - time); time >= ITW_AutoSaveTime};
        while {LV_PAUSE} do {sleep 5};
        ["autoSave"] call ITW_SaveGame;
    };    
};

["ITW_NewGameConfirmation"] call SKL_fnc_CompileFinal;
["ITW_LoadGame"] call SKL_fnc_CompileFinal;
["ITW_SaveGame"] call SKL_fnc_CompileFinal;
["ITW_EraseGame"] call SKL_fnc_CompileFinal;
["ITW_SaveAutoTask"] call SKL_fnc_CompileFinal;
["ITW_GetSavedLoadout"] call SKL_fnc_CompileFinal;
["ITW_SaveGameMP"] call SKL_fnc_CompileFinal;
["ITW_EraseGameMP"] call SKL_fnc_CompileFinal;
["ITW_SaveObjectives"] call SKL_fnc_CompileFinal;
["ITW_LoadObjectives"] call SKL_fnc_CompileFinal;
["ITW_LoadTargetsActive"] call SKL_fnc_CompileFinal;
["ITW_ParamResetConfimation"] call SKL_fnc_CompileFinal;