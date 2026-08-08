
#include "defines.hpp"
#include "defines_gui.hpp"
#include "\a3\ui_f\hpp\definecommongrids.inc"
#include "\a3\ui_f\hpp\definedikcodes.inc"

#define TGT_ACTIVE(ObjId) (ObjId in ITW_targetsActive)

#define TGT_MEDICAL_ACTIONS ["ainvpknlmstpsnonwnondnon_medic_1","ainvpknlmstpsnonwnondnon_medic0","ainvpknlmstpsnonwnondnon_medic1","ainvpknlmstpsnonwnondnon_medic2"]

ITW_Targets = {
    // call on server when objectives are created
    params ["_objIndexes"];
    if (isNil "ITW_targetsAllowed" || {ITW_targetsAllowed isEqualTo []}) then {
        ITW_targetsAllowed = call ITW_LoadTargetsActive;
        private _targetCount = count ITW_targetFunctions;
        while {count ITW_targetsAllowed < _targetCount} do {ITW_targetsAllowed pushBack true};
    };
    private _targetFunctions = [];
    {
        if (ITW_targetsAllowed#_forEachIndex) then {_targetFunctions pushBack (_x#1)};
    } forEach ITW_targetFunctions;
    diag_log format ["ITW: Targets allowed: %1",ITW_targetsAllowed];
    if (_targetFunctions isEqualTo []) exitWith {ITW_ParamTargets = 0};
    
    // for Destroy AA, we need to know if there are any AA available
    if (va_eAAClasses isNotEqualTo []) then {
        private _tgtAAIndex = ITW_targetFunctions findif {_x#0 == "STR_ITW_TGT_AATitle"};
        if (_tgtAAIndex >= 0 && {ITW_targetsAllowed#_tgtAAIndex}) then { // check >=0 because I sometimes shorten the list of functions for testing
            ITW_targetsAllowed set [_tgtAAIndex,false];
        };
    };
    
    // backward compatibility left 0,1,2 so adjust those here
    if (ITW_ParamTargets == 1) then {ITW_ParamTargets = 100};
    if (ITW_ParamTargets == 2) then {ITW_ParamTargets = 200};
    private _targetChance = (ITW_ParamTargets mod 100)/100;
    if (_targetChance == 0) then {_targetChance = 1};
    
    if (isNil "ITW_targetsActive") then {ITW_targetsActive = []};
    if (isNil "ITW_targetsDoneCallbacks") then {ITW_targetsDoneCallbacks = createHashmap};
    
    // destruct previous zone's targets
    {
        private _info = ITW_targetsDoneCallbacks getOrDefault [_x,[]];
        if !(_info isEqualTo []) then {
            _info params ["_tasks","_objects","_markers"];
            if (typeName _tasks   != "ARRAY") then {_tasks   = [_tasks]};
            if (typeName _objects != "ARRAY") then {_objects = [_objects]};
            if (typeName _markers != "ARRAY") then {_markers = [_markers]};
            {if !(_x call BIS_fnc_taskCompleted) then {[_x,"CANCELED",false] call BIS_fnc_taskSetState}} forEach _tasks;
            {{deleteVehicle _x} forEach attachedObjects _x; deleteVehicle _x} forEach _objects;
            {deleteMarker _x} forEach _markers;
        };
    } forEach ITW_targetsActive;
    
    ITW_targetsActive = [];
    
    {
        private _objIdx = _x;      
        private _obj = ITW_Objectives#_objIdx;
        // check if target not already complete (loading save game can cause it to be complete)
        private _idx = ITW_ObjContestedState findIf {_x#ITW_CONT_OBJ_IDX == _objIdx};
        if (_idx >= 0) then {
            private _completeAmount = ITW_ObjContestedState#_idx#ITW_CONT_TARGET_COMPLETE; // -2 no task, -1 not setup, 0 = not captured at all ... 1 = totally captured
            if (_completeAmount == -2) then {continue}; // no task for this objective
            if (_completeAmount > 0.5) then {
                ITW_targetsActive pushBack _objIdx;
                ITW_ObjContestedState#_idx set [ITW_CONT_TARGET_COMPLETE,1];
                private _objTask   = _obj#ITW_OBJ_TASKID;
                private _taskId    = "target_" + str _objIdx;
                [true, [_taskId,_objTask], [localize "STR_ITW_TGT_DoneDesc",localize "STR_ITW_TGT_DoneTitle",""], objNull, "SUCCEEDED", -1, false, "", false] call BIS_fnc_taskCreate; 
            } else {
                if (_completeAmount >= 0 || {random 1 < _targetChance}) then {
                    ITW_targetsActive pushBack _objIdx;
                    ITW_ObjContestedState#_idx set [ITW_CONT_TARGET_COMPLETE,if (_completeAmount >= 0) then {_completeAmount} else {0}];
                    private _tgtFnc = selectRandom _targetFunctions;
                    [_obj] spawn _tgtFnc;
                } else {
                    ITW_ObjContestedState#_idx set [ITW_CONT_TARGET_COMPLETE,-2];
                };
            };
        };
    } forEach _objIndexes;    
};

ITW_TargetAdvantage = {
    // call on server, returns +1, -1, or 0;  +1 indicates friendly get advantage, -1 means enemy get an advantage, 0 neither gets advantage
    params ["_objIdx"];
    if (!isServer) exitWith {diag_log "Error Pos: ITW_TargetAdvantage called from client"; 0};
    private _return = 0; // no effect
    if (ITW_ParamTargets == 0) exitWith {_return};
    private _idx = ITW_ObjContestedState findIf {_x#ITW_CONT_OBJ_IDX == _objIdx};
    if (_idx >= 0) then {
        private _amount = ITW_ObjContestedState#_idx#ITW_CONT_TARGET_COMPLETE;
        if (_amount >= 0) then {
            _return = if (_amount > 0.95) then {  // use '> 0.95' instead of '== 1' so rounding errors of many things equaling 1 isn't an issue
                // friendly advantage (maybe)
                if (ITW_ParamTargets > 200) then {1} else {0};
            } else {
                // enemy advantage
                _amount - 1
            };
        };
    };
    _return
};

ITW_TgtSetDeconstruct = {
    // call on server
    if (!isServer) exitWith {_this remoteExec ["ITW_TgtSetDeconstruct",2]};
    params ["_objIdx","_tasks",["_objects",[]],["_markers",[]]];
    ITW_targetsDoneCallbacks set [_objIdx,[_tasks,_objects,_markers]];
};

ITW_TgtSetCompleted = {
    // call on server
    if (!isServer) exitWith {_this remoteExec ["ITW_TgtSetCompleted",2]};
    params ["_objIdx",["_amount",1]]; // use _amount = -1 for canceled
    {
        private _idx = _x#ITW_CONT_OBJ_IDX;
        if (_idx == _objIdx) exitWith {
            _x set [ITW_CONT_TARGET_COMPLETE,_amount];
            ["target"] call ITW_SaveGame;
        };
    } forEach ITW_ObjContestedState;
};

ITW_TgtCreateMarkerZone = {
    // creates a marker of size _size that contains _pos somewhere within it
    // returns marker
    params ["_objIdx","_pos","_size",["_subIndex",1],["_exactPos",false]];
    if (typeName _pos == "OBJECT") then {_pos = getPosATL _pos};
    if (typeName _pos == "STRING") then {_pos = getMarkerPos _pos};
    
    private _mrkrPos = if (_exactPos) then {_pos} else {_pos getPos [random _size, random 360]};
    private _mrkr = createMarkerLocal [format ["tgt_%1_%2",_objIdx,_subIndex],_mrkrPos];
    _mrkr setMarkerSizeLocal [_size,_size];
    _mrkr setMarkerBrushLocal "Solid";
    _mrkr setMarkerShapeLocal "ELLIPSE";
    _mrkr setMarkerColorLocal "ColorYellow";
    _mrkr setMarkerAlpha 0.75;
    
    _mrkr
};

////////////////////////////////////////////////
//                   DEVICE                   //
////////////////////////////////////////////////
ITW_TgtDevice = {  
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtDevice";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    // set placement of device
    private _pos = [_objCenter, 0, _objSize + 150, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo [0]) then {
        _pos = [_objCenter, 0, _objSize + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    };
    
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtDevice";
    };
    
    _pos set [2,0];
    private _dir = random 360;
    
    // create device
    private _openDevice = "Land_Device_disassembled_F" createVehicle _pos;
    _openDevice allowDamage false;
    _openDevice setDir _dir;
    _openDevice setVectorUp surfaceNormal getPosASL _openDevice;
    _openDevice hideObjectGlobal true;
    
//    _openDevice addEventHandler ["HandleDamage", {
//        params ["_openDevice", "_hitSelection", "_damage", "_hitPartIndex", "_hitPoint", "_shooter", "_projectile"];
//        private _preDamage = damage _openDevice;
//        private _dmgApplied = (_damage - (_preDamage)) * 0.8; // make it a little harder to destroy
//        _preDamage + _dmgApplied
//    }];
    
    private _device = "Land_Device_assembled_F" createVehicle [0,0,0];
    _device allowDamage false;
    _device setDir _dir;
    _device setPosATL getPosATL _openDevice;
    _device setVectorUp surfaceNormal getPosASL _device;
    
    private _mrkr = [_objIdx,_device,100] call ITW_TgtCreateMarkerZone;
    
    _openDevice setVariable ["tgtInfo",[_objIdx,_mrkr,_taskId]];
    
    [true, [_taskId,_objTask], [localize "STR_ITW_TGT_DevDesc",localize "STR_ITW_TGT_DevTitle",""], getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    [_objIdx,_device,_openDevice,_taskId,_mrkr] remoteExec ["ITW_TgtDeviceMP",0,_device];
    
    [_objIdx,_taskId,[_device,_openDevice],_mrkr] call ITW_TgtSetDeconstruct; // deleting devices will trigger ITW_TgtDeviceMP to wrap up if not already complete
};

ITW_TgtDeviceMP = {
    // spawn on all clients
    params ["_objIdx","_device","_openDevice","_taskId","_mrkr"];
    
    scriptName "ITW_TgtDeviceMP";
    
    _openDevice addEventHandler ["Killed",{
        params ["_openDevice", "_killer", "_instigator", "_useEffects"];
        [_openDevice] remoteExec ["ITW_TgtDeviceDestroy",2]; // 'Killed' handler will only trigger on one machine (client or server)
    }];
    
    if !(hasInterface) exitWith {};
    
    private _duration = 40;
    [
        _device,
        localize "STR_ITW_TGT_DevHint",
        "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_loadDevice_ca.paa", "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_loadDevice_ca.paa",
        "_this distance _target < 3 && {!isObjectHidden _target}", "_caller distance _target < 5",
        {
            // code start
            //params ["_target", "_caller", "_actionId", "_arguments"];
        },
        { 
            // code progress
            //params ["_target", "_caller", "_actionId", "_arguments", "_progress", "_maxProgress"];
            if !(toLowerANSI(animationState _caller) in TGT_MEDICAL_ACTIONS) then {
                _caller playMoveNow selectRandom TGT_MEDICAL_ACTIONS;
            }; 
        },
        { 
            // code complete
            //params ["_target", "_caller", "_actionId", "_arguments"];
            if (CONSCIOUS(_caller)) then {
                _caller switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
            };
            [_target,_arguments#0] remoteExec ["ITW_TgtDeviceOpen",2];
        },
        { 
            // code interrupted
            if (CONSCIOUS(_caller)) then {
                _caller switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
            };
        }, [_openDevice], _duration, 1000, false, false, true
    ] call BIS_fnc_holdActionAdd;
    
    // wait for players to get close to device, or device deleted
    waitUntil {sleep 1; !alive _device || {{_x distanceSqr _device < 10000} count allPlayers > 0}};
    private _sound = -1;

    while {isObjectHidden _openDevice && {alive _openDevice}} do { // returns false if device is deleted
        _sound = playSound3D ["a3\sounds_f_epc\device\device_assembled_loop.wss", _device, false, getPosASL _device, 1, 1, 0, 0, true];
        waitUntil {soundParams _sound isEqualTo [] || isObjectHidden _device};
    };
    stopSound _sound;
    if (alive _openDevice) then {
        playSound3D ["a3\sounds_f\sfx\objects\upload_terminal\terminal_antena_open.wss", _device, false, getPosASL _device, 1, 1, 0, 0, true];
    };
    while {alive _openDevice} do  { // returns false if device is deleted
        _sound = playSound3D ["a3\sounds_f_epc\device\device_disassembled_loop.wss", _device, false, getPosASL _device, 1, 1, 0, 0, true];
        waitUntil {soundParams _sound isEqualTo [] || {!alive _openDevice}};
    };
    stopSound _sound;
    
    if (!isNull _openDevice) then {
        playSound3D ["a3\sounds_f_jets\vehicles\air\plane_fighter_01\b_plane_fighter_01_engine_start_ext.wss", _device,false,getPosASL _device,1,1.5,0,0,true];
    };
    
};

ITW_TgtDeviceOpen = {
    // run on server
    params ["_device","_openDevice"];
    scriptName "ITW_TgtDeviceOpen";
    
    _device hideObjectGlobal true;
    _openDevice hideObjectGlobal false;
    _openDevice allowDamage true; 
};

ITW_TgtDeviceDestroy = {
    // run on server
    params ["_openDevice"];
    scriptName "ITW_TgtDeviceDestroy";
    _openDevice getVariable ["tgtInfo",[-1,"",""]] params ["_objIdx","_mrkr","_taskId"];
    [_objIdx] call ITW_TgtSetCompleted;
    [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
    deleteMarker _mrkr;
    private _charge = createMine ["DemoCharge_F", getPosATL _openDevice, [], 0];
    _charge hideObject true;
    private _smoke = "test_EmptyObjectForSmoke" createVehicle getPosATL _openDevice;
    _smoke attachTo[_openDevice, [0,0,0]];
    sleep 9;
    _charge setDamage 1;
};

////////////////////////////////////////////////
//                   CACHE                    //
////////////////////////////////////////////////
ITW_TgtCache = {
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtCache";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    // set placement of cache
    private _pos = [];
    private _buildings = [_objCenter,_objSize] call ITW_GrsnBuilding;
    if !(_buildings isEqualTo []) then {
        private _cnt = 100;
        private _bldgsTried = [];
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            _bldg = selectRandom (_buildings - _bldgsTried);
            if (isNil "_bldg" || {isNull _bldg}) exitWith {};
            _bldgsTried pushBack _bldg;
            _bldPositions = [_bldg,false] call ITW_GrsnGetBuildingPositions;
            if (count _bldPositions > 0) then {_pos = selectRandom _bldPositions};
        };
    };
    if (_pos isEqualTo []) then {
        _pos = [_objCenter, 0, _objSize+150, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo []) then {
            _pos = [_objCenter, 0, _objSize + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        };
        if !(_pos isEqualTo [0]) then {_pos set [2,0]};
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtCache";
    };
    
    private _dir = random 360;
    _pos set [2,(_pos#2) + 0.5];
    
    // create cache
    private _cache = createVehicle ["Box_FIA_Support_F", _pos, [], 0, "CAN_COLLIDE"];
    _cache allowDamage false;
    _cache setDir _dir;
    
    private _mrkr = [_objIdx,_cache,50] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], [localize "STR_ITW_TGT_CacheDesc",localize "STR_ITW_TGT_CacheTitle",""], getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    clearItemCargoGlobal _cache;
    clearMagazineCargoGlobal _cache;
    clearWeaponCargoGlobal _cache;
    clearBackpackCargoGlobal _cache;
    
    if !(alive _cache) exitWith {
        [_taskId,"CANCELED",true] call BIS_fnc_taskSetState;
        deleteMarker _mrkr;
        deleteVehicle _cache;
    };
    
    _cache setVariable ["tgtInfo",[_objIdx,_mrkr,_taskId]];
    
    [_cache] remoteExec ["ITW_TgtCacheMP",0,_cache];
    
    [_objIdx,_taskId,_cache,_mrkr] call ITW_TgtSetDeconstruct;
    
    sleep 20;
    _cache allowDamage true;
};

ITW_TgtCacheMP = {
    // call on all clients
    // needed since the 'Killed' EH is only triggered on client that killed it
    params ["_cache"];
    scriptName "ITW_TgtCacheMP";
    _cache addEventHandler ["Killed", {
        params ["_cache", "_killer", "_instigator", "_useEffects"];
        [_cache] remoteExec ["ITW_TgtCacheDestroyed",2];
    }];
};

ITW_TgtCacheDestroyed = {
    // call on server
    params ["_cache"];
    scriptName "ITW_TgtCacheDestroyed";
    (_cache getVariable ["tgtInfo",[-1,""]]) params ["_objIdx","_mrkr","_taskId"];
    [_objIdx] call ITW_TgtSetCompleted;
    deleteMarker _mrkr;
    [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
};

////////////////////////////////////////////////
//                   INTEL                    //
////////////////////////////////////////////////
ITW_TgtIntelAcquire = {
    // spawn on server  
    params ["_obj"];
    [_obj,"ACQUIRE"] call ITW_TgtIntel;
};

ITW_TgtIntelDownload = {
    // spawn on server  
    params ["_obj"];
    [_obj,"DOWNLOAD"] call ITW_TgtIntel;
};

ITW_TgtIntel = {
    // spawn on server  
    params ["_obj","_type"];
    scriptName "ITW_TgtIntel";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    // set placement of intel
    private _pos = [];
    private _buildings = [_objCenter,_objSize] call ITW_GrsnBuilding;
    if !(_buildings isEqualTo []) then {
        private _cnt = 100;
        private _bldgsTried = [];
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            _bldg = selectRandom (_buildings - _bldgsTried);
            if (isNil "_bldg" || {isNull _bldg}) exitWith {};
            _bldgsTried pushBack _bldg;
            _bldPositions = [_bldg,false] call ITW_GrsnGetBuildingPositions;
            if (count _bldPositions > 0) then {_pos = selectRandom _bldPositions};
        };
    };
    if (_pos isEqualTo []) then {
        _pos = [_objCenter, 0, _objSize+150, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo []) then {
            _pos = [_objCenter, 0, _objSize + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        };
        if !(_pos isEqualTo [0]) then {_pos set [2,0]};
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtIntel";
    };
    
    private _dir = random 360;
    private _objects = [];
    private ["_taskDesc","_intelType","_intelPos"];
    switch (_type) do {
        case "ACQUIRE": {
            _taskDesc = [localize "STR_ITW_TGT_IntelGetDesc",localize "STR_ITW_TGT_IntelGetTitle",""];
            _intelType = ITW_SUITCASE;
            _intelPos = _pos;
        };
        case "DOWNLOAD": {
            _taskDesc = [localize "STR_ITW_TGT_IntelDownloadDesc",localize "STR_ITW_TGT_IntelDownloadTitle",""];
            // create table
            _table = createVehicle ["Land_CampingTable_small_F", _pos, [], 0, "CAN_COLLIDE"];
            _table allowDamage false;
            _table setDir _dir;
            _objects pushBack _table;
            
            _intelType = "Land_Laptop_03_black_F";
            _intelPos = getPosATL _table;
            _intelPos = [_intelPos#0,_intelPos#1,_intelPos#2 + 0.81365];
        };
    };
    
    
    // create intel
    _intel = createVehicle [_intelType, [0,0,100], [], 0, "CAN_COLLIDE"];
    _intel allowDamage false;
    _intel setVectorUp [0,0,1];
    _intel setDir _dir;
    _intel setPosATL _intelPos;
    _objects pushBack _intel;
    
    private _mrkr = [_objIdx,_intel,50] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], _taskDesc, getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    _intel setVariable ["tgtInfo",[_objIdx,_mrkr,_taskId],true];
    
    [_intel,_type] remoteExec ["ITW_TgtIntelMP",0,_intel];
    
    [_objIdx,_taskId,_objects,_mrkr] call ITW_TgtSetDeconstruct;
};

ITW_TgtIntelMP = {
    // call on all clients
    params ["_intel","_type"];
    scriptName "ITW_TgtIntelMP";
    switch (_type) do {
        case "ACQUIRE": {
            _intel addAction [localize "STR_ITW_TGT_IntelGetTitle", {
                params ["_intel", "_caller", "_actionId", "_arguments"];
                _intel attachto [_caller,[0.25,0,-0.2],"pelvis"];
                [_intel,90] remoteExec ["setDir",_intel];
                (_intel getVariable ["tgtInfo",[-1,"",""]]) params ["_objIdx","_mrkr","_taskId"];
                [_taskId, [localize "STR_ITW_TGT_IntelGetDesc", localize "STR_ITW_TGT_IntelDeliverTitle", ""]] call BIS_fnc_taskSetDescription;
                [_taskId, [_intel,true]] call BIS_fnc_taskSetDestination;
                deleteMarker _mrkr;
                [_taskId call BIS_fnc_taskParent,false] call BIS_fnc_taskSetCurrent;
                _taskId call BIS_fnc_taskSetCurrent;
                
                private _dropAction = _caller addAction [localize "STR_ITW_TGT_IntelDrop", {
                    params ["_player", "_caller", "_actionId", "_intel"];
                    detach _intel;
                    _intel setVariable ["itw_dropIntelAction",nil];
                    _player removeAction _actionId;
                },_intel,10,false,true,"","_target == _this",1];
                _intel setVariable ["itw_dropIntelAction",_dropAction];
                
                _caller addEventHandler ["Killed", {
                    params ["_player", "_killer", "_instigator", "_useEffects"];
                    {
                        private _intel = _x;
                        if (typeOf _intel == ITW_SUITCASE) then {
                            detach _intel;
                            private _pos = [_player, 0, 5, 4, 0, 0, 0, [], [[0],[0]]] call BIS_fnc_findSafePos;
                            if (_pos isEqualTo [0]) then {
                                _pos = getPosATL _player;
                            } else {
                                _pos set [2,0];
                            };
                            _intel setPosAtl _pos;
                            _player removeAction (_intel getVariable ["itw_dropIntelAction",-1]);
                            _intel setVariable ["itw_dropIntelAction",nil];
                        };
                    } forEach attachedObjects _player;
                }];
                
            },_dropAction,10,true,true,"","isNull (attachedTo _target)",4];
        };
        
        case "DOWNLOAD": {
            [
                _intel,
                localize "STR_ITW_TGT_IntelDownloadTitle",
                "", "",
                "true", "true",
                { /* code started  */ },
                { /* code progress */ },
                { // code completed
                    params ["_intel", "_caller", "_actionId", "_arguments"];
                    (_intel getVariable ["tgtInfo",[-1,""]]) params ["_objIdx","_mrkr","_taskId"];
                    [_objIdx] remoteExec ["ITW_TgtSetCompleted",2];
                    deleteMarker _mrkr;
                    [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                },
                { /* code interrupted */ },
                [], 10, 1000, true, false, true, 4
            ] call BIS_fnc_holdActionAdd;
        };
    };
    
};

ITW_TgtIntelDeliver = {
    // call on server
    params ["_player"];
    {
        private _intel = _x;
        if (typeOf _intel == ITW_SUITCASE) then {
            (_intel getVariable ["tgtInfo",[-1,""]]) params ["_objIdx","_mrkr","_taskId"];
            [_objIdx] call ITW_TgtSetCompleted;
            [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
            [_intel] remoteExec ["ITW_TgtIntelDropRemove",_player]; // this will delete the intel once complete
        };
    } forEach attachedObjects _player;
};

ITW_TgtIntelDropRemove = {
    // call on player's client
    params ["_intel"];
    player removeAction (_intel getVariable ["itw_dropIntelAction",-1]);
    deleteVehicle _intel;
};


////////////////////////////////////////////////
//              RADAR, FUEL DEPOT             //
////////////////////////////////////////////////
ITW_TgtRadar = {  
    // spawn on server  
    params ["_obj"];
    [_obj,"RADAR"] call ITW_TgtDestroy;
};

ITW_TgtFuelDepot = {  
    // spawn on server  
    params ["_obj"];
    [_obj,"FUEL"] call ITW_TgtDestroy;
};

ITW_TgtDestroyAA = {
    // spawn on server  
    params ["_obj"];
    [_obj,"AA"] call ITW_TgtDestroy;
};

ITW_TgtDestroy = {
    // called on server
    params ["_obj","_type"];
    scriptName "ITW_TgtDestroy";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    if (_type == "AA" && {isNil "va_eAAClasses" || {va_eAAClasses isEqualTo []}}) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No AA vehicles found for TgtDestroy AA";
    };
    
    // set placement of radar
    private _pos = [];
    if (_pos isEqualTo []) then {
        _pos = [_objCenter, 0, _objSize + 150, 24, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo [0]) then {
            YIELD_CPU;
            _pos = [_objCenter, 0, _objSize + 250, 24, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
            if (_pos isEqualTo [0]) then {
                YIELD_CPU;
                _pos = [_objCenter, 0, _objSize + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
            };
        };
        if !(_pos isEqualTo [0]) then {
            _pos set [2,0];
        };
    };
    
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtDestroy";
    };
    
    private _dir = random 360;
    
    // create target
    private ["_target","_objects","_mrkDesc"];
    switch (_type) do {
        case "RADAR": {
            _target = createVehicle ["Land_MobileRadar_01_radar_F", _pos, [], 0, "CAN_COLLIDE"];
            _target allowDamage false;
            _target setVectorUp  [0,0,1];
            _target setDir _dir;
            
            private _base = createVehicle ["Land_PierConcrete_01_16m_F", _pos, [], 0, "CAN_COLLIDE"];
            _base allowDamage false;
            _base setVectorUp  [0,0,1];
            _base attachTo [_target,[0,-5,-11.7]];
            _base setDir 90;
            
            _objects = [_target,_base];
            
            _mrkDesc = [localize "STR_ITW_TGT_RadarDesc",localize "STR_ITW_TGT_RadarTitle",""];
        };
        case "FUEL": {
            _objects = [];
            private _angle = random 360;
            
            private _rotatePos = { 
                params ['_offset','_center','_angle'];
                private _vect = [_offset, _angle] call BIS_fnc_rotateVector2D;
                private _newPos = _center vectorAdd _vect;
                _newPos
            };

            // _vehData: [_type, _relPos, _dir]
            private _data = [
                ['Land_MetalBarrel_F', [0.498169,-0.36875,0], 359.957],
                ['Land_MetalBarrel_F', [1.13635, -0.45566,0], 359.959],
                ['Land_MetalBarrel_F', [0.4729,  -1.05234,0], 359.128],
                ['Land_MetalBarrel_F', [1.10242, -1.1417 ,0], 359.366],
                ['Land_MetalBarrel_F', [-1.13635, -0.45566,0], 359.959],
                ['Land_MetalBarrel_F', [-0.4729,  -1.05234,0], 359.128],
                ['Land_MetalBarrel_F', [-0.498169,-0.36875,0], 359.957],
                ['Land_MetalBarrel_F', [-1.10242, -1.1417 ,0], 359.366],
                ['CargoNet_01_barrels_F', [-0.598877,0.822266,0], 359.795],
                ['CargoNet_01_barrels_F', [0.917358,0.822266,0], 0.265417],
                ['Land_SandbagBarricade_01_F', [-0.282715,2.09668,0], 0],
                ['Land_SandbagBarricade_01_F', [1.68933,2.12109,0], 0],
                ['Land_SandbagBarricade_01_F', [2.55737,1.35938,0], 90.72],
                ['Land_SandbagBarricade_01_F', [2.55701,-0.612793,0], 90.72],
                ['Land_SandbagBarricade_01_F', [-2.52478,-0.712402,0], 269.758],
                ['Land_SandbagBarricade_01_F', [-2.5575,1.25928,0], 269.758],
                ['Land_SandbagBarricade_01_F', [-1.73682,2.0542,0], 0],
                ['Land_SandbagBarricade_01_half_F', [1.78235,-2.12158,0], 181.185],
                ['Land_Shed_06_F', [0,0,0], 90]
            ];
            {
                _x params ['_type','_relPos','_dir'];
                private _p = [_relPos,_pos,_angle] call _rotatePos;
                _obj = _type createVehicle _p;
                _obj allowDamage false;
                _obj setDir (_dir - _angle);
                _obj setVectorUp surfaceNormal getPosASL _obj;
                _obj setPosATL _p;
                _objects pushBack _obj;
                if (_forEachIndex == 0) then {
                    // 1st object is the one that must be destroyed
                    _target = _obj;
                    _target addEventHandler ["Killed", {
                        params ["_target", "_killer", "_instigator", "_useEffects"];
                        private _smoke = "test_EmptyObjectForFireBig" createVehicle getPosATL _target;
                        _smoke attachTo[_target, [0,0,0]];
                    }];
                } else {
                    _obj setVariable ["itw_fuelTarget",_target];
                    _obj addEventHandler ["Killed", {
                        _this spawn {
                            params ["_obj", "_killer", "_instigator", "_useEffects"];
                            sleep 1;
                            private _target = _obj getVariable ["itw_fuelTarget",objNull];
                            if (alive _target) then {
                                [] remoteExec ["ITW_TgtFuelHint",[_killer,_instigator]];
                                sleep 2;
                                deleteVehicle _obj;
                            };
                        };
                    }];
                };
            } forEach _data;
            
            _mrkDesc = [localize "STR_ITW_TGT_FuelDesc",localize "STR_ITW_TGT_FuelTitle",""];
        };
        case "AA": {
            private _angle = random 360;
            
            private _rotatePos = { 
                params ['_offset','_center','_angle'];
                private _vect = [_offset, _angle] call BIS_fnc_rotateVector2D;
                private _newPos = _center vectorAdd _vect;
                _newPos
            };
            
            if (isNil "ITW_TGT_crewTypes") then {
                ITW_TGT_unitTypes =   ([ITW_EnemyFaction,["Crewman","Diver"],true,call FACTION_UNIT_FALLBACK_SUBF_OPF] call FactionUnits) apply {toLowerANSI _x};
                ITW_TGT_crewTypes =   ([ITW_EnemyFaction,["Crewman"],false,call FACTION_UNIT_FALLBACK_ROLE_REQ] call FactionUnits) apply {toLowerANSI _x};
                if (ITW_TGT_crewTypes isEqualTo []) then {ITW_TGT_crewTypes = ITW_TGT_unitTypes};
            };
            _target = [va_eAAClasses,ITW_TGT_crewTypes,ITW_TGT_unitTypes,ITW_EnemySide,_pos,-1] call ITW_AtkSpawnVeh;
            _target allowDamage false;
            _target setPosATL _pos;
            [_target,_angle] call ITW_FncRotateVeh;
            sleep 1;
            _target setPosATL _pos;
            sleep 1;
            _target setFuel 0; 
            {
                _x disableAI "MOVE";
                _x disableAI "PATH";
            } forEach (crew _target);
            _target lock 3; // crew cannot get out, players cannot get in
            _target allowCrewInImmobile true;
            _target setCaptive true; // allies will not fire on the vehicle, players need to destroy it
            _target setVariable ["itw_delete_objs",crew _target];
            _objects = [_target];
            
            // _vehData: [_type, _relPos, _dir]
            private _data = [
                ['Land_SandbagBarricade_01_F',      [-8,9,0],180],
                ['Land_SandbagBarricade_01_hole_F', [-6,9,0],180],
                ['Land_SandbagBarricade_01_F',      [-4,9,0],180],
                ['Land_SandbagBarricade_01_hole_F', [-2,9,0],180],
                ['Land_SandbagBarricade_01_F',      [ 0,9,0],180],
                ['Land_SandbagBarricade_01_hole_F', [ 2,9,0],180],
                ['Land_SandbagBarricade_01_F',      [ 4,9,0],180],
                ['Land_SandbagBarricade_01_hole_F', [ 6,9,0],180],
                //['Land_SandbagBarricade_01_F',      [ 8,9,0],180], // leave a space to walk through
                
                ['Land_SandbagBarricade_01_F',      [9,-8,0],90],
                ['Land_SandbagBarricade_01_hole_F', [9,-6,0],90],
                ['Land_SandbagBarricade_01_F',      [9,-4,0],90],
                ['Land_SandbagBarricade_01_hole_F', [9,-2,0],90],
                ['Land_SandbagBarricade_01_F',      [9, 0,0],90],
                ['Land_SandbagBarricade_01_hole_F', [9, 2,0],90],
                ['Land_SandbagBarricade_01_F',      [9, 4,0],90],
                ['Land_SandbagBarricade_01_hole_F', [9, 6,0],90],
                ['Land_SandbagBarricade_01_F',      [9, 8,0],90],
                
                ['Land_SandbagBarricade_01_F',      [-8,-9,0],0],
                ['Land_SandbagBarricade_01_hole_F', [-6,-9,0],0],
                ['Land_SandbagBarricade_01_F',      [-4,-9,0],0],
                ['Land_SandbagBarricade_01_hole_F', [-2,-9,0],0],
                ['Land_SandbagBarricade_01_F',      [ 0,-9,0],0],
                ['Land_SandbagBarricade_01_hole_F', [ 2,-9,0],0],
                ['Land_SandbagBarricade_01_F',      [ 4,-9,0],0],
                ['Land_SandbagBarricade_01_hole_F', [ 6,-9,0],0],
                ['Land_SandbagBarricade_01_F',      [ 8,-9,0],0],
                
                ['Land_SandbagBarricade_01_F',      [-9,-8,0],-90],
                ['Land_SandbagBarricade_01_hole_F', [-9,-6,0],-90],
                ['Land_SandbagBarricade_01_F',      [-9,-4,0],-90],
                ['Land_SandbagBarricade_01_hole_F', [-9,-2,0],-90],
                ['Land_SandbagBarricade_01_F',      [-9, 0,0],-90],
                ['Land_SandbagBarricade_01_hole_F', [-9, 2,0],-90],
                ['Land_SandbagBarricade_01_F',      [-9, 4,0],-90],
                ['Land_SandbagBarricade_01_hole_F', [-9, 6,0],-90],
                ['Land_SandbagBarricade_01_F',      [-9, 8,0],-90]
            ];
            {
                _x params ['_type','_relPos','_dir'];
                private _p = [_relPos,_pos,_angle] call _rotatePos;
                _obj = _type createVehicle _p;
                _obj allowDamage false;
                _obj setDir (_dir - _angle);
                _obj setVectorUp surfaceNormal getPosASL _obj;
                _obj setPosATL _p;
                _objects pushBack _obj;
            } forEach _data;
            
            _mrkDesc = [localize "STR_ITW_TGT_AADesc",localize "STR_ITW_TGT_AATitle",""];
        };
    };
            
    [_pos,24,_objects] remoteExec ["ITW_RemoveTerrainObjects",0,true];
    
    private _mrkr = [_objIdx,_pos,100] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], _mrkDesc, getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    { _x addCuratorEditableObjects [[_target],true] } forEach allCurators;
    if !(alive _target) exitWith {
        [_taskId,"CANCELED",true] call BIS_fnc_taskSetState;
        deleteMarker _mrkr;
        _objects apply {deleteVehicle _x};
    };
    
    _target setVariable ["tgtInfo",[_objIdx,_mrkr,_taskId]];
    
    _target addEventHandler ["Killed", {
        params ["_target", "_killer", "_instigator", "_useEffects"];
        (_target getVariable ["tgtInfo",[-1,""]]) params ["_objIdx","_mrkr","_taskId"];
        {deleteVehicle _x} forEach (_target getVariable ["itw_delete_objs",[]]);
        [_objIdx] call ITW_TgtSetCompleted;
        deleteMarker _mrkr;
        [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
    }];
        
    sleep 10;
    _target allowDamage true;
    _objects apply {_x allowDamage true};
    sleep 5;
    
    [_objIdx,_taskId,_objects,_mrkr] call ITW_TgtSetDeconstruct;
};

////////////////////////////////////////////////
//                   DISHES                   //
////////////////////////////////////////////////
ITW_TgtDishes = {  
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtDishes";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    private _count     = switch (true) do {case (_objSize < 200): {2}; case (_objSize < 400): {3}; case (_objSize < 700): {4}; default {5};};
    private _dishes    = [];
    private _markers   = [];
    private _blacklist = ["water"];
    
    for "_i" from 1 to _count do {
        private _pos = [_objCenter, 0, _objSize+150, 4, 0, 0.5, 0, _blacklist, [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo [0]) then {
            _pos = [_objCenter, 0, _objSize + 250, 4, 0, 0.5, 0, _blacklist, [[0],[0]]] call BIS_fnc_findSafePos;
        };
        
        if (_pos isEqualTo [0]) exitWith {};
        
        _pos set [2,0];
        _blacklist pushBack [_pos,100];
        
        private _type = selectRandom ["Land_SatelliteAntenna_01_F","SatelliteAntenna_01_Black_F","SatelliteAntenna_01_Olive_F","SatelliteAntenna_01_Sand_F"];
        private _dir = random 360;
        
        // create dish
        private _dish = createVehicle [_type, _pos, [], 0, "CAN_COLLIDE"];
        _dish allowDamage false;
        _pos set [2,0];
        _dish setPosATL _pos;
        _dish setVectorUp surfaceNormal getPosASL _dish;
        _dish enableSimulationGlobal false;
        
        private _mrkr = [_objIdx,_dish,50,_i] call ITW_TgtCreateMarkerZone;
        _markers pushBack _mrkr;
        
        private _subTaskId = _taskId + str _i;
        [true, [_subTaskId,_objTask], [localize "STR_ITW_TGT_dishDesc",localize "STR_ITW_TGT_dishTitle",""], getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
        
        _dish setVariable ["tgtInfo",[_mrkr,_subTaskId],true];
        
        _dishes pushBack _dish;
    };
    
    if (count _dishes == 0) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtDishes";
    };
    
    [_objIdx,_dishes] remoteExec ["ITW_TgtDishesMP",0,_dishes#0];
    [_objIdx,_taskId,_dishes,_markers] call ITW_TgtSetDeconstruct;
};

#define DishState_UnHacked 0
#define DishState_Hacking  1
#define DishState_Hacked   2
ITW_TgtDishesMP = {
    // call on all clients
    params ["_objIdx","_dishes"];
    if (!hasInterface) exitWith {};
    {
        private _dish = _x;
        private _light = "Sign_Sphere100cm_Geometry_F" createVehicleLocal [0,0,0];
        _light attachTo [_dish,[0,0.27,0.41]];
        _light setObjectScale 0.1; 
        _dish setVariable ["attachedLight", _light];
        
        private _duration = 20;
        [
            _dish,
            localize "STR_ITW_TGT_DishHint",
            "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_connect_ca.paa", "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_connect_ca.paa",
            "_this distance _target < 3 && {!isObjectHidden _target}", "_caller distance _target < 5",
            {
                // code start
                //params ["_target", "_caller", "_actionId", "_arguments"];
                [_target,DishState_Hacking] remoteExec ["ITW_TgtDishColorMP",0,_target];
            },
            { 
                // code progress
                //params ["_target", "_caller", "_actionId", "_arguments", "_progress", "_maxProgress"];
                if !(toLowerANSI(animationState _caller) in TGT_MEDICAL_ACTIONS) then {
                    _caller playMoveNow selectRandom TGT_MEDICAL_ACTIONS;
                }; 
            },
            { 
                // code complete
                //params ["_target", "_caller", "_actionId", "_arguments"];
                [_target,_actionId] call BIS_fnc_holdActionRemove;
                if (CONSCIOUS(_caller)) then {
                    _caller switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
                };
                
                _arguments params ["_objIdx","_count"];
                _target getVariable ["tgtInfo",[-1,"",1]] params ["_mrkr","_taskId"];
                private _parentTask = _taskId call BIS_fnc_taskParent;
                private _tasksComplete = 1;
                {
                    if (_x call BIS_fnc_taskCompleted) then {_tasksComplete = _tasksComplete + 1};
                } forEach (_parentTask call BIS_fnc_taskChildren);
                [_objIdx,_tasksComplete/_count] remoteExec ["ITW_TgtSetCompleted",2];
                deleteMarker _mrkr;
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                
                [_target,DishState_Hacked] remoteExec ["ITW_TgtDishColorMP",0,_target];
            },
            { 
                // code interrupted
                //params ["_target", "_caller", "_actionId", "_arguments"];
                if (CONSCIOUS(_caller)) then {
                    _caller switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
                };
                [_target,DishState_UnHacked] remoteExec ["ITW_TgtDishColorMP",0,_target];
            }, [_objIdx,count _dishes], _duration, 1000, false, false, true
        ] call BIS_fnc_holdActionAdd;
    } forEach _dishes;
    [_dishes] call ITW_TgtDishSoundsMP;
};

ITW_TgtDishColorMP = {
    // call on each client
    params ["_dish","_state"];
    private _light = _dish getVariable ["attachedLight",objNull];
    if (isNull _light) exitWith {};
    private _color = switch (_state) do {
        case DishState_UnHacked: { "#(rgb,8,8,3)color(1,0,0,1)"};
        case DishState_Hacking : { "#(rgb,8,8,3)color(1,1,0,1)"};
        case DishState_Hacked  : { "#(rgb,8,8,3)color(0,1,0,1)"};
        default {[1,1,1]};
    };
    _light setObjectTexture [0, _color];
    _light
};

ITW_TgtDishSoundsMP = {
    // call on all clients 
    params ["_dishes"];
    scriptName "ITW_TgtDishSoundsMP";
    if (isNil "TgtDishSoundsSem") then {
        TgtDishSoundsSem = false;
        TgtDishSounds = [];
    };
    
    SEM_LOCK(TgtDishSoundsSem);
    
    if (isNil "TgtThreadRunning") then {
        TgtThreadRunning = true;
        0 spawn {
            private _running = true;
            while {_running} do {
                sleep 10;
                SEM_LOCK(TgtDishSoundsSem);
                {
                    _x params ["_dish","_snd","_light"];
                    if (alive _dish) then {
                        if (player distanceSqr _dish < 360000) then { // player within 400m
                            stopSound _snd;
                            _snd = playSound3D ["a3\sounds_f\sfx\objects\upload_terminal\upload_terminal_loop.wss", _dish, false, getPosASL _dish, 1.5, 1, 0, 0, true];
                            _x set [1,_snd];
                        };
                    } else {
                        TgtDishSounds deleteAt _forEachIndex;
                        deleteVehicle _light;
                    };
                } forEachReversed TgtDishSounds;
                if (TgtDishSounds isEqualTo []) then {_running = false;TgtThreadRunning = nil};
                SEM_UNLOCK(TgtDishSoundsSem);
            };
        };
    };
    
    {
        private _dish = _x;
        private _snd = -1;
        private _light = [_dish,DishState_UnHacked] call ITW_TgtDishColorMP;
        TgtDishSounds pushBack [_dish,_snd,_light];
    } forEach _dishes;
    
    SEM_UNLOCK(TgtDishSoundsSem);
};

////////////////////////////////////////////////
//                   DELIVER                  //
////////////////////////////////////////////////
ITW_TgtDeliver = {  
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtDeliver";
    
    #define TGT_DELIVER_COUNT     3 // how many crates need to be delivered
    #define TGT_DELIVER_BOX_TYPES ["Box_NATO_AmmoVeh_F","CargoNet_01_box_F","CargoNet_01_barrels_F","B_CargoNet_01_ammo_F","Land_FoodSacks_01_cargo_brown_F"]
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _objName   = _obj#ITW_OBJ_NAME;
    private _taskId    = "target_" + str _objIdx + "_"; 
    
    private _base = [_objCenter] call ITW_BaseNearest;
    [_base] call ITW_BaseEnsure;
    private _basePos = _base#ITW_BASE_POS;
    private _baseDir = _base#ITW_BASE_DIR;
    private _spawnPos = _basePos getPos [57,_baseDir + 180];
    
    private _deliverPos = [_objCenter getPos [_objSize + 100,_objCenter getDir _spawnPos], 0, _objSize + 50, 2, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    if (_deliverPos isEqualTo [0]) then {
        _deliverPos = [_objCenter, 0, _objSize + 250, 2, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    };
    if (_deliverPos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtDeliver";
    };
    private _mrkr = [_objIdx,_deliverPos,50,1,true] call ITW_TgtCreateMarkerZone; 
    [true, [_taskId,_objTask], [localize "STR_ITW_TGT_DeliverToDesc",localize "STR_ITW_TGT_DeliverToTitle",""], getMarkerPos _mrkr, "CREATED", -1, false, "", false] call BIS_fnc_taskCreate;
    
    private _crates = [];
    private _taskIds = [_taskId];
    
    private _types = [];
    for "_i" from 1 to TGT_DELIVER_COUNT do {
        if (_types isEqualTo []) then {_types = TGT_DELIVER_BOX_TYPES call BIS_fnc_arrayShuffle};
        private _index = count _types - 1;
        private _type = _types#_index;
        _types deleteAt _index;
        
        private _crate = _type createVehicle _spawnPos;
        _crate allowDamage false;
        _crate setDir random 360;
        
        private _crateTaskId = _taskId + str _i;
        [true, [_crateTaskId,_objTask], [format [localize "STR_ITW_TGT_deliverDesc",_i],localize "STR_ITW_TGT_deliverTitle",""], _crate, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
        _taskIds pushBack _crateTaskId;
        
        _crate setVariable ["tgtDeliverMrkr",_mrkr,true];
        _crate setVariable ["tgtDeliverInfo",[_objIdx,_crateTaskId,_taskId]];
        
        [_crate,_objName,mapGridPosition _deliverPos] remoteExec ["ITW_TgtDeliverMP",0,_crate];
        
        _crates pushBack _crate;
    };
    
    
    [_objIdx,_taskIds,_crates,_mrkr] call ITW_TgtSetDeconstruct;
    
    private _zoneIndex = ITW_ZoneIndex;
    private _count = count _crates;
    private _cratesEnroute = [];
    while {_zoneIndex == ITW_ZoneIndex && {!(_crates isEqualTo [])}} do {
        sleep 3;
        {
            private _crate = _x;
            private _isBeingCarried = !(isNull attachedTo _crate && {isNull ropeAttachedTo _crate});
            if (!_isBeingCarried && {_crate inArea (_crate getVariable ['tgtDeliverMrkr',[[0,0,0],1,1]])}) then {
                (_crate getVariable ["tgtDeliverInfo",[-1,"",""]]) params ["_objIdx","_taskId","_toTaskId"];
                private _parentTask = _taskId call BIS_fnc_taskParent;

                private _tasksComplete = 1;
                private _freeTask = "";
                {
                    if ([_x,"target_"] call ITW_FncStartsWith && {_x call BIS_fnc_taskCompleted}) then {
                        _tasksComplete = _tasksComplete + 1;
                    } else {
                        if (_x != _taskId) then {_freeTask = _x};
                    };
                } forEach (_parentTask call BIS_fnc_taskChildren);
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                if (_tasksComplete == _count) then {
                    private _mrkr = _crate getVariable ["tgtDeliverMrkr",""];
                    deleteMarker _mrkr;
                    [_toTaskId,"SUCCEEDED",false] call BIS_fnc_taskSetState;
                } else {
                    private _player = [getPosATL _crate,allPlayers] call ITW_FncClosest;
                    if !(_freeTask isEqualTo "") then {[_freeTask,nil,nil,nil,true,nil,false,false] remoteExec ["BIS_fnc_setTask",_player]};
                };
                [_objIdx,_tasksComplete/_count] remoteExec ["ITW_TgtSetCompleted",2];
    
                [_crate] remoteExec ["removeAllActions",0,_crate]; 
                _crates deleteAt _forEachIndex;
                sleep 1;
            };
            if (_isBeingCarried && {!(_crate in _cratesEnroute) && {!(isPlayer attachedTo _crate)}}) then {
                private _player = [getPosATL _crate,allPlayers] call ITW_FncClosest;
                if (_player distance _crate < 40) then {
                    (_crate getVariable ["tgtDeliverInfo",[-1,"",""]]) params ["_objIdx","_taskId","_toTaskId"];
                    _cratesEnroute pushBack _crate;
                    [_toTaskId,nil,nil,nil,true,nil,false,false] remoteExec ["BIS_fnc_setTask",_player];
                };
            };
            if (!_isBeingCarried && {_crate in _cratesEnroute}) then {
                _cratesEnroute = _cratesEnroute - [_crate]
            };
        } forEachReversed _crates;

    };
};

ITW_TgtDeliverMP = {
    params ["_crate","_objName","_gridLoc"];
    
    if (!hasInterface) exitWith {};
        
    _crate addAction ["<t color='#aaaadd'>"+ localize "STR_ITW_TGT_DeliverTo" + " " + _objName + " : " + str _gridLoc + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
        },nil,10,false,true,"","true",4];
        
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Carry" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            _crate attachTo [player, [0, 2, 1]];
            player setAnimSpeedCoef 0.7;
            player playAction "PlayerStand";
            player action ["SwitchWeapon",player,player,-1];
            
            player addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Drop" + "</t>", {
                params ["_unit", "_caller", "_actionId", "_arguments"];
                _arguments params ["_crate"];
                player removeAction _actionId;
                _caller setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                sleep 0.5;
                _caller setAnimSpeedCoef 1;
                _crate setVelocity [0,0,-0.1];
            },[_crate],10,false,true,"","true",4];
        },nil,10,false,true,"","isNull attachedTo _target",4];  
    
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_LoadInVehicle" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            player addAction ["<t color='#ff0000'>" + localize "STR_ITW_AF_SelectVehicle" + "</t>", {
                params ["_target", "_caller", "_actionId", "_crate"];
                player removeAction _actionId;
                private _veh = cursorTarget;
                if ((_veh isKindOf "Helicopter" || _veh isKindOf "Land" || _veh isKindOf "Sea") && {alive _veh && {speed _veh < 1}}) then {
                    if (!simulationEnabled _veh) then {
                        [_veh,true] remoteExec ["enableSimulationGlobal",2];
                        [_veh,true] remoteExec ["allowDamage",_veh];
                    };   
                    private _success = _veh setVehicleCargo _crate;
                    if (_success) then {
                        [_veh,_crate] remoteExec ["ITW_TgtDeliverLoadMP",0,_crate];
                    } else {
                        if (_veh isKindOf "Helicopter") then {
                            hint localize "STR_ITW_AF_UseSlingLoad";
                        } else {
                            private _bbox = boundingBox _veh;
                            if (_veh getVariable ["tgtActionId",-1] != -1 || {_bbox#2 < 5.5}) then {
                                hint localize "STR_ITW_AF_NoVehSpace";
                            } else {
                                // allow vehicles that aren't technically allowed to carry stuff to carry it anyway
                                private _dimensions = getArray (configOf _veh >> "VehicleTransport" >> "Carrier" >> "cargoBayDimensions");
                                private "_loadPos";
                                if (_dimensions isEqualTo []) then {
                                    _loadPos = [0,-1.8,-0.3];
                                } else {
                                    {
                                        if (typeName _x isEqualTo "STRING") then {_dimensions set [_forEachIndex,_veh selectionPosition _x]};
                                    } forEach _dimensions;
                                    _loadPos = [(_dimensions#0#0 + (_dimensions#1#0))/2,(_dimensions#0#1 + (_dimensions#1#1))/2,(_dimensions#0#2) + 0.3];
                                };
                                _crate attachTo [_veh,_loadPos];
                                private _crateVertHgt = (getPosATL _crate)#2;
                                if (_crateVertHgt < 0) then {
                                    // some vehicles put the create under the vehicle
                                    _loadPos set [2,1-_crateVertHgt];
                                    _crate attachTo [_veh,_loadPos];
                                };
                                [_veh,_crate] remoteExec ["ITW_TgtDeliverLoadMP",0,_crate];
                                _veh setVariable ["tgtForcedDelivery",true,true];
                            };
                        };
                    };
                } else {
                    hint localize "STR_ITW_AF_NoVehSelected";
                };
            },_crate,100,true,true,"","_this == _target",4]; 
        },nil,10,false,true,"","isNull attachedTo _target",4]; 
};


ITW_TgtDeliverLoadMP = {
    // call on all clients
    params ["_veh","_crate"];
    if (!hasInterface) exitWith {};
    scriptName "ITW_TgtDeliverLoadMP";
    private _timeout = time + 5;
    waitUntil {simulationEnabled _veh || {time > _timeout}}; 
    sleep 1;
    private _actionId = _veh getVariable ["tgtActionId",-1];
    if (_actionId < 0) then {
        _actionId = _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_UnloadAfCrate" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_crate"];
            playSoundUI ["A3\Sounds_F_Orange\vehicles\soft\Van_02\Van_02_Door_Slide_02.wss", 0.5, 1];
            if (_veh getVariable ["tgtForcedDelivery",false]) then {
                _veh setVariable ["tgtForcedDelivery",nil,true];
                [_veh,false] remoteExec ["allowDamage",_veh];
                sleep 1;
                detach _crate;
                _crate setDir getDir _veh;
                private _pos = _veh getPos [((boundingBox _veh)#2)/2 + 3,(getDir _veh) + 180];
                _pos set [2,3];
                _crate setPos _pos;
                _crate setVelocity [0,0,-0.1]; 
                [_veh] remoteExec ["ITW_TgtDeliverUnloadMP",0];
                sleep 2;
                [_veh,true] remoteExec ["allowDamage",_veh];
            } else {
                _veh setVehicleCargo objNull;
            };
            [_veh] remoteExec ["ITW_TgtDeliverUnloadMP",0];
        },_crate,100,false,true,"","true",8];
        _veh setVariable ["tgtActionId",_actionId];
    };
};

ITW_TgtDeliverUnloadMP = {
    params ["_veh"];
    private _actionId = _veh getVariable ["tgtActionId",-1];
    if (_actionId >= 0) then {
        _veh removeAction _actionId;
        _veh setVariable ["tgtActionId",nil];
    };
};

////////////////////////////////////////////////
//                   RECON                    //
////////////////////////////////////////////////
ITW_TgtRecon = {
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtRecon";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    // set placement of device to recon
    private _pos = [_objCenter, 0, _objSize+50, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo [0]) then {
        _objSize = _objSize + 150;
        _pos = [_objCenter, 0, _objSize, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtRecon";
    };
    _pos set [2,0];
    
    private _dir = random 360;
    
    // create device
    private _device = createVehicle ["Land_Device_assembled_F",_pos, [], 0, "CAN_COLLIDE"];
    _device allowDamage false;
    _device setDir _dir;
    
    { _x addCuratorEditableObjects [[_device],true] } forEach allCurators;
    
    private _mrkr = [_objIdx,_objCenter,_objSize+100,1,true] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], [localize "STR_ITW_TGT_ReconDesc",localize "STR_ITW_TGT_ReconTitle",""], getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
        
    if !(alive _device) exitWith {
        [_taskId,"CANCELED",true] call BIS_fnc_taskSetState;
        deleteMarker _mrkr;
        deleteVehicle _device;
    };
    
    _device setVariable ["tgtInfo",[_objIdx,_mrkr,_taskId]];
    
    [_device] remoteExec ["ITW_TgtReconMP",0,_device];
    
    [_objIdx,_taskId,_device,_mrkr] call ITW_TgtSetDeconstruct;
};

ITW_TgtReconMP = {
    // call on all clients
    // wait for player to aim at device for a period of time, then let server know
    params ["_device"];
    scriptName "ITW_TgtReconMP";
    if (!hasInterface) exitWith {};
    
    private _timeViewed = 0;
    private _requiredTime = 10;
    private _checkInterval = 1;

    while {alive _device && _timeViewed < _requiredTime} do {
        // Check if the local player is looking directly at the target object
        if (cursorTarget == _device) then {
            _timeViewed = _timeViewed + _checkInterval;
        } else {
            _timeViewed = 0; // player looked away
        };
        sleep _checkInterval;
    };

    if (_timeViewed >= _requiredTime) then {
        [_device,player] remoteExec ["ITW_TgtReconTrigger",2];
        private _targetATL = getPosATL _device;
        private _laserTarget = "LaserTargetW" createVehicleLocal _targetATL;
        _laserTarget setPosATL _targetATL;
        private _vehType = selectRandom va_pPlaneClassesAttack;
        if (isNil "_vehType") then {_vehType = selectRandom va_pPlaneClassesDual};
        if (isNil "_vehType") then  {
            [player,_targetATL,objNull] remoteExec ["ITW_TgtReconBombsAway",2];
        } else {
            private _pos = getPosATL _device;
            private _airportPos = [true,_pos] call ITW_ObjClosestOwnedAirport;
            if (isNil "_airportPos") then {_airportPos = [_targetATL,ITW_OWNER_FRIENDLY] call ITW_ObjGetNearest};
            private _dir = _airportPos getDir _pos;
            [[player,_pos,_dir,west,_vehType,5,"call ITW_TgtReconBombsAway",true],"bomb"] remoteExec ["ITW_RadioCasServer",2];
        };
        ["HQ",localize "STR_ITW_TGT_ReconInbound",true] call SKL_HE_SendMessage
    };
};

ITW_TgtReconBombsAway = {
    // called on server
    params ["_caller","_targetATL","_plane"];
    if (isNull _plane) then {
        // no plane, just fake it
        sleep 40;
    };
    missionNamespace setVariable [format ["itw_tgt_recon_%1", getPlayerUID _caller],true];
};

ITW_TgtReconTrigger = {
    // call on server
    params ["_device","_player"];
    scriptName "ITW_TgtReconTrigger";
    
    private _varId = format ["itw_tgt_recon_%1", getPlayerUID _player];
    missionNamespace setVariable [_varId,false];
    
    _device allowDamage true;
    
    private _timeout = time + 60;
    waitUntil {sleep 1; time > _timeout || missionNamespace getVariable [_varId,false]};
    
    sleep 5;
    if (alive _device) then {("Bo_GBU12_LGB" createVehicle getPosATL _device) setDamage 1};
    _device setDamage 1;
    
    (_device getVariable ["tgtInfo",[-1,""]]) params ["_objIdx","_mrkr","_taskId"];
    [_objIdx] call ITW_TgtSetCompleted;
    deleteMarker _mrkr;
    [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
};


////////////////////////////////////////////////
//                   FOB                      //
////////////////////////////////////////////////
ITW_TgtFob = {
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtFob";
    
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    private _fobRadius = 150;
    
    private _pos = [_objCenter, _objSize, _objSize + 300, 20, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo [0]) then {
        _pos = [_objCenter, _objSize, _objSize + 300, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo [0]) then {
            _pos = [_objCenter, _objSize/2, _objSize + 300, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
            if (_pos isEqualTo [0]) then {
                _pos = [_objCenter, 0, _objSize + 500, 1, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
            };
        };
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtFob";
    };
    _pos set [2,0];
        
    private _mrkr = [_objIdx,_pos,_fobRadius,1,true] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], [localize "STR_ITW_TGT_FobDesc",localize "STR_ITW_TGT_FobTitle",""], getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    [_objIdx,_taskId,[],_mrkr] call ITW_TgtSetDeconstruct;
    
    private _prevFortObjCnt = count ITW_fortificationObjects;
    while {!(_taskId call BIS_fnc_taskCompleted)} do {
        sleep 10;
        if (_prevFortObjCnt != count ITW_fortificationObjects) then {
            _prevFortObjCnt = count ITW_fortificationObjects;
            private _objects = ITW_fortificationObjects select {_x distance _pos < _fobRadius};
            if (count _objects > 1) then {
                [_objIdx] call ITW_TgtSetCompleted;
                deleteMarker _mrkr;
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
            };
        };
    };
};

////////////////////////////////////////////////
//                   Rescue                   //
////////////////////////////////////////////////
ITW_TgtRescue = {
    // spawn on server  
    params ["_obj"];
    scriptName "ITW_TgtRescue";
      
    private _type = selectRandom ["PILOT","POW"];

    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objIdx    = _obj#ITW_OBJ_INDEX;
    private _objTask   = _obj#ITW_OBJ_TASKID;
    private _taskId    = "target_" + str _objIdx;    
    
    private _dir = random 360;
    private ["_taskDesc","_unitTypes","_unitCount","_distMin","_distMax","_actionText"];
    switch (_type) do {
        case "PILOT": {
            _unitTypes = [ITW_PlayerFaction,["Crewman"],false,call FACTION_UNIT_FALLBACK_ROLE_BLU] call FactionUnits;
            _unitCount = 1;
            _taskDesc = [localize "STR_ITW_TGT_RescuePilotDesc",localize "STR_ITW_TGT_RescuePilotTitle",""];
            _distMin = _objSize;
            _distMax = _objSize + 300;
            _actionText = "STR_ITW_TGT_RescueActionPilot";
        };
        case "POW": {
            _unitTypes = [ITW_PlayerFaction,[],false,call FACTION_UNIT_FALLBACK_ROLE_BLU] call FactionUnits;
            _unitCount = round (2 + random 4);
            _taskDesc = [format [localize "STR_ITW_TGT_RescuePowsDesc",_unitCount],localize "STR_ITW_TGT_RescuePowsTitle",""];
            _distMin = 0;
            _distMax = _objSize;
            _actionText = "STR_ITW_TGT_RescueActionPOW";
        };
    };
    
    private _positions = [];
    private _pos = [];
    private _buildings = [_objCenter,_distMax] call ITW_GrsnBuilding;
    if (_distMin > 0) then {_buildings = _buildings select {_x distance _objCenter > _distMin}};
    if !(_buildings isEqualTo []) then {
        private _cnt = 100;
        private _bldgsTried = [];
        while {_pos isEqualTo [] && {_cnt > 0}} do {
            _cnt = _cnt - 1;
            _bldg = selectRandom (_buildings - _bldgsTried);
            if (isNil "_bldg" || {isNull _bldg}) exitWith {};
            _bldgsTried pushBack _bldg;
            _bldPositions = [_bldg,false] call ITW_GrsnGetBuildingPositions;
            if (count _bldPositions >= _unitCount) then {
                _bldPositions = _bldPositions call BIS_fnc_arrayShuffle;
                for "_i" from 1 to _unitCount do {_positions pushBack (_bldPositions deleteAt 0)};
                _pos = _positions#0;
            };
        };
    };
    if (_pos isEqualTo []) then {
        _pos = [_objCenter, _distMin, _distMax, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo []) then {
            _pos = [_objCenter, _distMin, _distMax + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        };
        if !(_pos isEqualTo [0]) then {
            _pos set [2,0];
            _positions pushBack _pos;
            for "_i" from 2 to _unitCount do {
                _positions pushBack (_pos getPos [2,30 * _i]);
            };
        };
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, [_taskId,_objTask], [localize "STR_ITW_TGT_NoDesc",localize "STR_ITW_TGT_NoTitle",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        diag_log "ITW: warning: No target position found for TgtRescue";
    };
    
    private _mrkr = [_objIdx,_pos,50] call ITW_TgtCreateMarkerZone;
    
    [true, [_taskId,_objTask], _taskDesc, getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    
    // create units
    private _units = [];
    private _group = createGroup [civilian,true];
    _group setVariable ["noHeadless",true];
    _group setVariable ["itwInitGrp",true,true];
    for "_i" from 0 to _unitCount-1 do {
        private _unit = [_group, _unitTypes, _pos, false] call ITW_AtkUnitToGroup;
        _unit setCombatMode "BLUE";   
        _unit setBehaviour "CARELESS";
        _unit setCaptive true;
        _unit setDamage 0.5;
        _unit setVariable ["itw_dmgBlocked",true];
        switch (_type) do {
            case "PILOT": {
                _unit setDir random 360;
                _unit setPosATL (_positions#_i);
                _unit removeWeapon (primaryWeapon _unit);
                _unit removeWeapon (secondaryWeapon _unit);
                removeAllAssignedItems  _unit;
                [_unit,["Acts_Injured_Driver_Loop"]] remoteExec ["switchMove",0]; // I've got no idea why some anims require remoteExec and others don't
            };
            case "POW": {
                private _dir = random 360;
                _unit setDir _dir;
                _unit setPosATL ((_positions#_i) getPos [-1,_dir+20]);
                removeAllWeapons _unit; 
                removeGoggles _unit;
                removeHeadgear _unit;
                removeVest _unit;
                removeBackpack _unit;
                removeAllWeapons _unit;
                removeAllAssignedItems  _unit;
                [_unit,["Acts_ExecutionVictim_Loop"]] remoteExec ["switchMove",0];
            };
        };
        {_unit disableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];

        _units pushBack _unit;
    };
    { _x addCuratorEditableObjects [_units,true] } forEach allCurators;
    [_group,_actionText] remoteExec ["ITW_TgtRescueMP",0,_group];
    
    [_objIdx,_taskId,_units,_mrkr] call ITW_TgtSetDeconstruct;
    
    private _following = objNull;
    private _baseCheck = 0;
    private _unit0 = _units#0;
    while {alive _unit0} do {
        sleep 2;
        private _rescuers = _units apply {_x getVariable ["tgtRescuer",objNull]} select {!isNull _x};        
        if (count _rescuers > 0) then {
            //// Free POW
            private _rescuer = _rescuers#0;
            {
                private _unit = _x;
                _unit setVariable ["tgtRescuer",nil];
                _unit setVariable ["tgtRescued",true,0];
                {_unit enableAI _x } forEach ["MOVE", "ANIM"];
                switch (toLowerANSI animationState _unit) do {
                    case "acts_injured_driver_loop":  {[_unit,["AidlPsitMstpSnonWnonDnon_ground00", 0, 0, true]] remoteExec ["switchMove",0]}; // pilot
                    case "Acts_ExecutionVictim_Loop": {[_unit,["AidlPknlMstpSnonWnonDnon_AI"      , 0, 0, true]] remoteExec ["switchMove",0]}; // pow
                    default                           {[_unit,["AidlPsitMstpSnonWnonDnon_ground00", 0, 0, true]] remoteExec ["switchMove",0]}; // after stopping
                };
                sleep 0.25;
                [_unit,["", 0, 0, true]] remoteExec ["switchMove",0]; // unit now stands up
                sleep 0.25;
                [_unit] remoteExec ["BIS_fnc_ambientAnim__terminate",0];
                [_unit,_rescuer,true] spawn ITW_TeammateFollow;
            } forEach _units;
            _mrkr setMarkerAlpha 0;
            _following = _rescuer;
            private _timeout = time + 5;
            [_taskId,[_unit0,true]] call BIS_fnc_taskSetDestination;
        };
        if (!isNull _following && {_units findIf {_following distance _x < 500} == -1}) then {
            //// players died or something, POWs sit down and wait
            {
                private _unit = _x;
                {_unit disableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];
                _unit setVariable ["tgtRescued",false,0];
                _unit setVariable ["tmFollowing",objNull,true];
                if (vehicle _unit != _unit) then {moveOut _unit};
                if (getPosASL _unit #2 > -0.5) then { 
                    // only sit if not in water
                    [_unit, "SIT_LOW", "ASIS"] remoteExec ["BIS_fnc_ambientAnim",0];
                };
            } forEach _units;
            _following = objNull;
        };
        _baseCheck = _baseCheck + 1;
        if (!isNUll _following && {_baseCheck > 10 && {vehicle _unit0 isEqualTo _unit0 && {isTouchingGround _unit0}}}) then {
            _baseCheck = 0;
            private _unitPos = getPosATL _unit0;
            private _nearestBase = [_unitPos,ITW_OWNER_FRIENDLY,true,true] call ITW_BaseNearest;
            private _basePos = _nearestBase#ITW_BASE_POS;
            if (_unitPos distanceSqr _basePos < 10000) exitWith {
                //// POWs made it back to base
                [_objIdx] call ITW_TgtSetCompleted;
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                deleteMarker _mrkr;
                {_x setVariable ["tmFollowing",objNull,true]} forEach _units;
                sleep 5;
                {
                    private _unit = _x;
                    {_unit enableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];
                    _unit setSpeaker "NoVoice";
                    _unit disableAI "RADIOPROTOCOL";
                    unassignVehicle _unit;
                    if (vehicle _unit != _unit) then {
                        _unit action ["GetOut", vehicle _unit];
                    };
                    _unit setDamage 0;
                    _unit setSpeedMode "FULL";
                    _unit setBehaviour "SAFE";
                    _unit doMove getPosATL _unit;
                    _unit doMove (getPosATL _unit getPos [100, random 360]);
                } forEach _units;
                sleep 60;
                {deleteVehicle _x} forEach _units;
                deleteGroup _group;
            };
        };
    };
    
    deleteMarker _mrkr;
};

ITW_TgtRescueMP = {
    // call on all clients
    params ["_group","_actionText"];
    scriptName "ITW_TgtRescueMP";
    {
        private _unit = _x;
        _unit addAction ["<t color='#fff000'>" + localize _actionText + "</t>", {
            params ["_unit", "_player", "_actionId", "_args"];
            _unit setVariable ["tgtRescuer",_player,2];
        },nil,100,true,true,"","!(_target getVariable ['tgtRescued',false])",4];
        _unit addAction [localize "STR_ITW_TM_FollowMe",{
            params ["_target", "_caller", "_actionId", "_arguments"];
            [_target,_caller] remoteExec ["ITW_TeammateFollow",_target];
        },nil,1.4,false,true,"",
        "group _this == group _target && _target != leader _target && {isNull (_target getVariable ['tmFollowing',objNull])}"];
    } forEach units _group;
};

///////////////////////////////////
//     Choose Targets To Use     //
///////////////////////////////////
ITW_TargetsSelection = {
    // call on server
    if (!isNil "ITW_targetsAllowed") exitWith {diag_log "Error Pos: WARNING ITW_TargetsSelection ITW_targetsAllowed preset for testing"};
    ITW_targetsAllowed = call ITW_LoadTargetsActive;
    if (ITW_targetsAllowed isEqualTo []) then {ITW_targetsAllowed = ITW_targetFunctions apply {true}};
    if (count ITW_targetsAllowed < count ITW_targetFunctions) then {
        private _trueCnt = count (ITW_targetsAllowed select {_x});
        private _default = _trueCnt >= (count ITW_targetsAllowed)/2;
        while {count ITW_targetsAllowed < count ITW_targetFunctions} do {ITW_targetsAllowed pushBack _default};
    };
    if (count ITW_targetsAllowed > count ITW_targetFunctions) then {
        ITW_targetsAllowed resize count ITW_targetFunctions;
    };
    publicVariable "ITW_targetsAllowed";
    
    if (isDedicated) then {
        // if using a dedicated server, use a the first player to choose dlc
        waitUntil {count (call BIS_fnc_listPlayers) > 0};
        private _player = (call BIS_fnc_listPlayers)#0;
        [] remoteExec ["ITW_TargetsSelection_Wait",-(owner _player),true];
        [] remoteExec ["ITW_TargetsSelection_Start",_player];
    } else {
        // hosted server, so just let the host choose dlc
        [] remoteExec ["ITW_TargetsSelection_Wait",-2,true];
        [] call ITW_TargetsSelection_Start;
    };
    waitUntil {sleep 0.5; missionNamespace getVariable ["ITW_TGT_SELECT_DONE",false]};
};

ITW_TargetsSelection_Wait = {
    // Can be called on extra clients while other player selects dlc
    "itw" cutText ["","BLACK",0.01];
    waitUntil {sleep 1; missionNamespace getVariable ["ITW_TGT_SELECT_DONE",false]};
};

ITW_TargetsSelection_Start = {
    // Called on one client - will choose dlc
    "itw" cutText ["","BLACK",0.01];
    
    waitUntil {!isNil "ITW_targetsAllowed"}; // wait until the host has sent the list of allowed dlc
    waitUntil {!isNull findDisplay 46};
    
    createDialog  ["ITWEmptyDialog",true];
    private _display = findDisplay ITW_EMPTY_DIALOG_ID;
  
    private _itemCount = count ITW_targetFunctions;
    private _rowHeight = GUI_GRID_H;
    private _padding = GUI_GRID_H/3;
    private _menuWidth = 16 * GUI_GRID_W;
    private _menuHeight = (1.6 * GUI_GRID_H) + (_itemCount * (_rowHeight + _padding));
    private _posX = (safeZoneW / 2 + safeZoneX) - (_menuWidth / 2);
    private _posY = (safeZoneH / 2 + safeZoneY) - (_menuHeight / 2);
   
    private _ctrlTitle = _display ctrlCreate ["RscText", -1];
    _ctrlTitle ctrlSetPosition [_posX + (2*GUI_GRID_W), _posY - (2*GUI_GRID_H), _menuWidth, 2*GUI_GRID_H];
    _ctrlTitle ctrlSetText localize "STR_ITW_TGT_SelectTargetTypes";
    _ctrlTitle ctrlSetFontHeight (GUI_GRID_H * 1.2);
    _ctrlTitle ctrlSetBackgroundColor [0, 0, 0, 0.8];
    _ctrlTitle ctrlCommit 0;
 
    private _ctrlGroup = _display ctrlCreate ["RscControlsGroup", -1];
    _ctrlGroup ctrlSetPosition [_posX, _posY, _menuWidth, _menuHeight];
    _ctrlGroup ctrlCommit 0;

    // Populate the rows

    {
        private _text = localize (_x#0);
        private _currentIndex = _forEachIndex;
        private _yOffset = _currentIndex * (_rowHeight + _padding);
        
        private _cb = _display ctrlCreate ["RscCheckBox", -1, _ctrlGroup];
        _cb ctrlSetPosition [0, _yOffset, _rowHeight, _rowHeight];
        
        private _initState = ITW_targetsAllowed select _currentIndex;
        _cb cbSetChecked _initState;
        
        _cb ctrlAddEventHandler ["CheckedChanged", {
            params ["_control", "_checked"];
            private _idx = _control getVariable "itemIndex";
            ITW_targetsAllowed set [_idx, (_checked == 1)];
        }];
    
        // Store the index on the control so the EH knows which array element to toggle
        _cb setVariable ["itemIndex", _currentIndex];        
        _cb ctrlCommit 0;
        
        private _t = _display ctrlCreate ["RscText", -1, _ctrlGroup];
        _t ctrlSetPosition [_rowHeight, _yOffset, _menuWidth * 0.8, _rowHeight];
        _t ctrlSetText _text;
        _t ctrlSetBackgroundColor [0.2, 0.2, 0.2, 0.5];
        _t ctrlCommit 0;

    } forEach ITW_targetFunctions;
    
    private _btnContinue = _display ctrlCreate ["RscButtonMenu", -1];
    private _buttonWidth = 4 * GUI_GRID_W;
    private _buttonHeight = 1.5 * GUI_GRID_H;
    _btnContinue ctrlSetPosition [_posX + (_menuWidth - _buttonWidth)/2, _posY + _menuHeight + (2*GUI_GRID_H), _buttonWidth, _buttonHeight];
    _btnContinue ctrlSetStructuredText parseText ("<t align='center'>"+ localize "STR_SKL_COMMON_Okay"+"</t>");
    _btnContinue ctrlSetBackgroundColor [0.65, 0.44, 0.09, 0.8];
    _btnContinue ctrlAddEventHandler ["ButtonClick", {
        closeDialog 0;
    }];
    _btnContinue ctrlCommit 0;
    ctrlSetFocus _btnContinue;
    
    private _keyHandler = _display displayAddEventHandler ["KeyDown", {
        params ["_display", "_keyCode", "_shift", "_ctrl", "_alt"];
        if (_keyCode == DIK_RETURN || _keyCode == DIK_NUMPADENTER) then {
            closeDialog 0;
            true 
        } else {
            false
        };
    }];
    waitUntil {sleep 0.5; isNull findDisplay ITW_EMPTY_DIALOG_ID};
    _display displayRemoveEventHandler ["KeyDown", _keyHandler];
    publicVariableServer "ITW_targetsAllowed";
    missionNamespace setVariable ["ITW_TGT_SELECT_DONE",true,true];
};

ITW_TargetsLoad = {
    params ["_targetsAllowed"];
    if (isNil "ITW_targetsAllowed" || {ITW_targetsAllowed isEqualTo []}) then {
        ITW_targetsAllowed = _targetsAllowed;
    };
};

//////////////////////////////
//     LIST ALL TARGETS     //
//////////////////////////////

// order is important, add new items to the end
ITW_targetFunctions = [
                       ["STR_ITW_TGT_DevTitle"          ,ITW_TgtDevice],
                       ["STR_ITW_TGT_CacheTitle"        ,ITW_TgtCache],
                       ["STR_ITW_TGT_DishTitle"         ,ITW_TgtDishes],
                       ["STR_ITW_TGT_RadarTitle"        ,ITW_TgtRadar],
                       ["STR_ITW_TGT_DeliverTitle"      ,ITW_TgtDeliver],
                       ["STR_ITW_TGT_FuelTitle"         ,ITW_TgtFuelDepot],
                       ["STR_ITW_TGT_IntelDeliverTitle" ,ITW_TgtIntelAcquire],
                       ["STR_ITW_TGT_IntelDownloadTitle",ITW_TgtIntelDownload],
                       ["STR_ITW_TGT_ReconTitle"        ,ITW_TgtRecon],
                       ["STR_ITW_TGT_FobTitle"          ,ITW_TgtFob],
                       ["STR_ITW_TGT_RescueTitle"       ,ITW_TgtRescue],
                       ["STR_ITW_TGT_AATitle"           ,ITW_TgtDestroyAA]
                      ];

["ITW_Targets"] call SKL_fnc_CompileFinal;
["ITW_TargetAdvantage"] call SKL_fnc_CompileFinal;
["ITW_TgtSetDeconstruct"] call SKL_fnc_CompileFinal;
["ITW_TgtSetCompleted"] call SKL_fnc_CompileFinal;
["ITW_TgtCreateMarkerZone"] call SKL_fnc_CompileFinal;
["ITW_TgtDevice"] call SKL_fnc_CompileFinal;
["ITW_TgtDeviceOpen"] call SKL_fnc_CompileFinal;
["ITW_TgtDeviceMP"] call SKL_fnc_CompileFinal;
["ITW_TgtCache"] call SKL_fnc_CompileFinal;
["ITW_TgtRadar"] call SKL_fnc_CompileFinal;
["ITW_TgtDishes"] call SKL_fnc_CompileFinal;
["ITW_TgtDishesMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDishColorMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDishSoundsMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDeliver"] call SKL_fnc_CompileFinal;
["ITW_TgtDeliverMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDeliverLoadMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDeliverUnloadMP"] call SKL_fnc_CompileFinal;
["ITW_TgtDeviceDestroy"] call SKL_fnc_CompileFinal;
["ITW_TgtCacheMP"] call SKL_fnc_CompileFinal;
["ITW_TgtCacheDestroyed"] call SKL_fnc_CompileFinal;
["ITW_TgtIntelAcquire"] call SKL_fnc_CompileFinal;
["ITW_TgtIntelDownload"] call SKL_fnc_CompileFinal;
["ITW_TgtIntel"] call SKL_fnc_CompileFinal;
["ITW_TgtIntelMP"] call SKL_fnc_CompileFinal;
["ITW_TgtIntelDeliver"] call SKL_fnc_CompileFinal;
["ITW_TgtFuelDepot"] call SKL_fnc_CompileFinal;
["ITW_TgtDestroy"] call SKL_fnc_CompileFinal;
["ITW_TgtIntelDropRemove"] call SKL_fnc_CompileFinal;
["ITW_TargetsSelection"] call SKL_fnc_CompileFinal;
["ITW_TargetsSelection_Wait"] call SKL_fnc_CompileFinal;
["ITW_TargetsSelection_Start"] call SKL_fnc_CompileFinal;
["ITW_TargetsLoad"] call SKL_fnc_CompileFinal;
["ITW_TgtDestroyAA"] call SKL_fnc_CompileFinal;
["ITW_TgtRecon"] call SKL_fnc_CompileFinal;
["ITW_TgtReconMP"] call SKL_fnc_CompileFinal;
["ITW_TgtReconBombsAway"] call SKL_fnc_CompileFinal;
["ITW_TgtReconTrigger"] call SKL_fnc_CompileFinal;
["ITW_TgtFob"] call SKL_fnc_CompileFinal;
["ITW_TgtRescue"] call SKL_fnc_CompileFinal;
["ITW_TgtRescueMP"] call SKL_fnc_CompileFinal;
