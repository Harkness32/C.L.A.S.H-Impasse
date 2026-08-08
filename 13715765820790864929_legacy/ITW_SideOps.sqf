// Side Operations

#include "defines.hpp"
#include "defines_gui.hpp"
#include "\a3\ui_f\hpp\definecommongrids.inc"
#include "\a3\ui_f\hpp\definedikcodes.inc"

// These defines need to map to the parameter ITW_ParamSdoEffect values
#define SDO_EFFECT_AI  0
#define SDO_EFFECT_CAP 1
#define SDO_EFFECT_VEH 2
#define SDO_EFFECT_MAX 3

#define SDO_TYPE_MED 0
#define SDO_TYPE_RES 1
#define SDO_TYPE_TOW 2
#define SDO_TYPE_TRA 3

ITW_SdoMainMenu = [
    [localize "STR_ITW_SDO_SideOpsMenu", false],
    [localize "STR_ITW_SDO_Medivac"   , [2], "", -5, [["expression", format ["[player, %1] remoteExec ['ITW_SideOps',2]",SDO_TYPE_MED ]]], "1", "1"],
    [localize "STR_ITW_SDO_Resupply"  , [3], "", -5, [["expression", format ["[player, %1] remoteExec ['ITW_SideOps',2]",SDO_TYPE_RES]]], "1", "1"],
    [localize "STR_ITW_SDO_Tow"       , [4], "", -5, [["expression", format ["[player, %1] remoteExec ['ITW_SideOps',2]",SDO_TYPE_TOW]]], "1", "1"],
    [localize "STR_ITW_SDO_Transport" , [5], "", -5, [["expression", format ["[player, %1] remoteExec ['ITW_SideOps',2]",SDO_TYPE_TRA]]], "1", "1"],
    [localize "STR_ITW_COMMON_Random" , [6], "", -5, [["expression", "[player,-1] remoteExec ['ITW_SideOps',2]"]], "1", "1"],
    [localize "STR_ITW_COMMON_Cancel" ,[16], "", -3, [["expression", ""]], "1", "1"]
];

ITW_SideOps = {
    // called on server to create new sideOps mission
    params ["_requestingPlayer","_missionIdx"];
    
    private _sdoFunction = switch (_missionIdx) do {
        case SDO_TYPE_MED:{ITW_SdoMedivac};
        case SDO_TYPE_RES:{ITW_SdoResupply};
        case SDO_TYPE_TOW:{ITW_SdoTow};
        case SDO_TYPE_TRA:{ITW_SdoTransport};
        default {selectRandom [ITW_SdoMedivac,ITW_SdoResupply,ITW_SdoTow,ITW_SdoTransport]};
    };
    private _effect = if (ITW_ParamSdoEffect >= 0) then {ITW_ParamSdoEffect} else {floor random SDO_EFFECT_MAX}; 
    private "_taskId";
    isNil {
        _taskId = "sdo_task_" + str ITW_sdoTaskCounter;
        ITW_sdoTaskCounter = ITW_sdoTaskCounter + 1;
        ITW_sdoActive set [_taskId,[true,_effect]];
    };
     
    [_requestingPlayer,_taskId] spawn _sdoFunction;
};

ITW_SideOpsNext = {
    // call on server when objectives are created to clear old SideOps missions
    
    if (isNil "ITW_sdoActive") then {
        ITW_sdoActive = createHashmap; // map of [taskId,[isDeletable,advantageType]
        ITW_sdoDoneCallbacks = createHashmap; // map of [taskId,["_tasks","_objects","_markers"]]
        ITW_sdoTaskCounter = 0;
    };
    if (isNil "ITW_sdoAdvantage") then {
        ITW_sdoAdvantage = createHashMap; // this one can be loaded on loading a saved game, map of [type,[timeout,timeout,...]
    };
    
    // destruct previous zone's side ops
    {
        _taskId = _x;
        (ITW_sdoActive get _x) params ["_isDeletable","_effect"];
        if (_isDeletable) then {
            private _info = ITW_sdoDoneCallbacks getOrDefault [_taskId,[]];
            if !(_info isEqualTo []) then {
                _info params ["_tasks","_objects","_markers"];
                if (typeName _tasks   != "ARRAY") then {_tasks   = [_tasks]};
                if (typeName _objects != "ARRAY") then {_objects = [_objects]};
                if (typeName _markers != "ARRAY") then {_markers = [_markers]};
                {if !(_x call BIS_fnc_taskCompleted) then {[_x,"CANCELED",false] call BIS_fnc_taskSetState}} forEach _tasks;
                {{deleteVehicle _x} forEach attachedObjects _x; deleteVehicle _x} forEach _objects;
                {deleteMarker _x} forEach _markers;
            };
            ITW_sdoActive deleteAt _forEachIndex;
        };
    } forEach keys ITW_sdoActive;
};

ITW_SideOpsAdvantage = {
    // call on server, returns 0 to 10 on how much ally advantage the supplied item gets
    params ["_effect"];
    // Effects:
    //   AI   Increases friendly AI 
    //   CAP  Increases effectiveness of allies capturing zones
    //   VEH  Increases friendly vehicle spawn rates
    if (!isServer) exitWith {diag_log "Error Pos: ITW_SideOpsAdvantage called from client"; 0};
    private _return = 0; // no effect
    if (ITW_ParamSdoIntensity == 0) exitWith {_return};
    private _effectNum = switch (toUpperANSI _effect) do {
        case "AI":  {SDO_EFFECT_AI};
        case "CAP": {SDO_EFFECT_CAP};
        case "VEH": {SDO_EFFECT_VEH};
    };
    // isNil acts as semaphore on ITW_sdoAdvantage
    isNil {
        private _adv = ITW_sdoAdvantage getOrDefault [_effectNum,[]];
        {if (time > _x) then {_adv deleteAt _forEachIndex}} forEachReversed _adv;
        _return = ITW_ParamSdoIntensity * (count _adv);
    };
    _return
};

ITW_SdoSetDeconstruct = {
    // call on server
    if (!isServer) exitWith {_this remoteExec ["ITW_SdoSetDeconstruct",2]};
    params ["_taskId","_tasks",["_objects",[]],["_markers",[]]];
    ITW_sdoDoneCallbacks set [_taskId,[_tasks,_objects,_markers]];
};

ITW_SdoSetCompleted = {
    // call on server
    if (!isServer) exitWith {_this remoteExec ["ITW_SdoSetCompleted",2]};
    params ["_taskId"];
    private _info = ITW_sdoActive getOrDefault [_taskId,[]];
    if (_info isEqualTo []) exitWith {diag_log ("Error Pos: ITW_SdoSetCompleted called on non-running task - " + _taskId)};
    _info params ["_isDeletable","_effect"];
    private _currAdvantages = ITW_sdoAdvantage getOrDefault [_effect,[]];
    _currAdvantages pushBack (time + ITW_ParamSdoDuration);
    ITW_sdoAdvantage set [_effect,_currAdvantages];
};

ITW_SdoMarker = {
    // creates a marker of size _size that contains _pos somewhere within it
    // returns marker
    params ["_taskId","_pos","_size",["_subIndex",1],["_exactPos",false]];
    if (typeName _pos == "OBJECT") then {_pos = getPosATL _pos};
    if (typeName _pos == "STRING") then {_pos = getMarkerPos _pos};
    
    private _mrkrPos = if (_exactPos) then {_pos} else {_pos getPos [random _size, random 360]};
    private _mrkr = createMarkerLocal [format ["%1_%2",_taskId,_subIndex],_mrkrPos];
    _mrkr setMarkerSizeLocal [_size,_size];
    _mrkr setMarkerBrushLocal "Solid";
    _mrkr setMarkerShapeLocal "ELLIPSE";
    _mrkr setMarkerColorLocal "ColorOrange";
    _mrkr setMarkerAlpha 0.7;
    
    _mrkr
};

ITW_SideOpsSave = {
    
    private _saveData = +ITW_sdoAdvantage;
    {
        _saveData set [_x,_y apply {_x - time}];
    } forEach _saveData;
    _saveData
};

ITW_SideOpsLoad = {
    params ["_saveData"];
    if !(isNil "ITW_sdoAdvantage") then {diag_log "Error Pos: ITW_SideOpsLoad called after ITW_sdoAdvantage already defined"};
    ITW_sdoAdvantage = createHashmap;
    {
        ITW_sdoAdvantage set [_x,_y apply {_x + time}];
    } forEach _saveData;
};

////////////////////////////////////////////////
//                   Medivac                  //
////////////////////////////////////////////////
ITW_SdoMedivac = {
    // spawn on server  
    params ["_playerRequesting","_taskId"];
    scriptName "ITW_SdoMedivac";

    private _objIdx = selectRandom (ITW_Zones#ITW_ZoneIndex);
    private _obj = ITW_Objectives#_objIdx;
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    
    private _dir = random 360;
    private _unitTypes = [ITW_PlayerFaction,[],false,call FACTION_UNIT_FALLBACK_ROLE_BLU] call FactionUnits;
    private _taskDesc = [localize "STR_ITW_SDO_MedivacDesc",localize "STR_ITW_SDO_Medivac",""];
    private _distMin = _objSize;
    private _distMax = _objSize + 300;
    private _actionText = "str_a3_showcase_gunships_bis_tsksave_marker"; // RESCUE
    
    private _pos = [];
    if (random 1 < 0.5) then { // only  in buildings half the time
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
                if (count _bldPositions >= 0) then {
                    _pos = selectRandom _bldPositions
                };
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
        };
    };
    if (_pos isEqualTo [0]) exitWith {
        [true, _taskId, [localize "STR_ITW_SDO_Failed",localize "STR_ITW_SDO_Failed",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        "itw" cutText [localize "STR_ITW_SDO_Failed","PLAIN"];
        diag_log "ITW: warning: No side ops position found for SdoMedivac";
    };
    
    private _mrkr = [_taskId,_pos,50] call ITW_SdoMarker;
    
    [true, _taskId, _taskDesc, getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    [_taskId,_playerRequesting,nil,nil,true,nil,true,false] remoteExec ["bis_fnc_setTask",_playerRequesting];
    
    // create unit
    private _group = createGroup [civilian,true];
    _group setVariable ["noHeadless",true];
    _group setVariable ["itwInitGrp",true,true];
    private _unit = [_group, _unitTypes, _pos, false] call ITW_AtkUnitToGroup;
    _unit setCombatMode "BLUE";   
    _unit setBehaviour "CARELESS";
    _unit setCaptive true;
    _unit setDamage 0.5;
    _unit setDir random 360;
    _unit setPosATL (_pos);
    _unit setVariable ["itw_dmgBlocked",true];
    removeVest _unit;
    removeBackpack _unit;
    removeHeadgear _unit;
    removeAllWeapons _unit; 
    removeAllAssignedItems  _unit;
    _unit addHeadgear "H_HeadBandage_bloody_F";
    [_unit,["Acts_Injured_Driver_Loop"]] remoteExec ["switchMove",0]; // I've got no idea why some anims require remoteExec and others don't
    {_unit disableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];
    { _x addCuratorEditableObjects [[_unit],true] } forEach allCurators;
    [_group,_actionText] remoteExec ["ITW_TgtRescueMP",0,_group];
    
    [_taskId,_taskId,_unit,_mrkr] call ITW_SdoSetDeconstruct;
    
    private _following = objNull;
    private _baseCheck = 0;
    while {alive _unit} do {
        sleep 2;
        _unit setDamage 0.5; // don't let wounded be healed
        private _rescuer = _unit getVariable ["tgtRescuer",objNull];        
        if (!isNull _rescuer) then {
            //// Free wounded to follow player
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
            _mrkr setMarkerAlpha 0;
            _following = _rescuer;
            private _timeout = time + 5;
            [_taskId,[_unit,true]] call BIS_fnc_taskSetDestination;
            [_unit,_rescuer,true] spawn ITW_TeammateFollow;
            _unit allowDamage true;
        };
        if (!isNull _following && {_following distance _unit > 500}) then {
            //// players died or something, sit down and wait
            {_unit disableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];
            _unit setVariable ["tgtRescued",false,0];
            _unit setVariable ["tmFollowing",objNull,true];
            if (vehicle _unit != _unit) then {moveOut _unit};
            if (getPosASL _unit #2 > -0.5) then { 
                // only sit if not in water
                [_unit, "SIT_LOW", "ASIS"] remoteExec ["BIS_fnc_ambientAnim",0];
            };
            _following = objNull;
        };
        _baseCheck = _baseCheck + 1;
        if (!isNull _following && {_baseCheck > 10 && {vehicle _unit isEqualTo _unit && {isTouchingGround _unit}}}) then {
            _baseCheck = 0;
            private _unitPos = getPosATL _unit;
            private _nearestBase = [_unitPos,ITW_OWNER_FRIENDLY,true,true] call ITW_BaseNearest;
            private _basePos = _nearestBase#ITW_BASE_POS;
            if (_unitPos distanceSqr _basePos < 10000) then {
                //// POWs made it back to base
                [_taskId] call ITW_SdoSetCompleted;
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                deleteMarker _mrkr;
                _unit setVariable ["tmFollowing",objNull,true];
                sleep 5;
                {_unit enableAI _x } forEach ["AUTOTARGET", "TARGET", "FSM", "MOVE", "ANIM"];
                _unit setSpeaker "NoVoice";
                _unit disableAI "RADIOPROTOCOL";
                unassignVehicle _unit;
                if (vehicle _unit != _unit) then {
                    _unit action ["GetOut", vehicle _unit];
                };
                _unit setSpeedMode "FULL";
                _unit setBehaviour "SAFE";
                _unit doMove getPosATL _unit;
                _unit doMove _basePos;
                private _timeout = time + 20;
                waitUntil {sleep 1; time > _timeout || _unit distance _basePos < 5};
                if (damage _unit < 0.9) then {
                    [_unit,["HubWoundedProne_idle1", 0, 0, true]] remoteExec ["switchMove",0]; // unit lays down
                    _timeout = time + 60;
                    waitUntil {sleep 1;time > _timeout || damage _unit > 0.9};
                };
                if (damage _unit > 0.9) then {
                    [_unit,["", 0, 0, true]] remoteExec ["switchMove",0]; // unit now stands up
                    _unit doMove (getPosATL _unit getPos [100, random 360]);
                    sleep 60;
                };
                deleteVehicle _unit;
                deleteGroup _group;
            };
        };
    };
    if !(_taskId call BIS_fnc_taskCompleted) then {[_taskId,"FAILED",true] call BIS_fnc_taskSetState};
    deleteMarker _mrkr;
};

////////////////////////////////////////////////
//                   Resupply                 //
////////////////////////////////////////////////
ITW_SdoResupply = {
    // spawn on server  
    params ["_playerRequesting","_taskId"];
    scriptName "ITW_SdoResupply";
    
    private _deliveryCount = 1 + floor random 2; // how many crates need to be delivered
    
    #define SDO_DELIVER_BOX_TYPES ["Box_NATO_AmmoVeh_F","CargoNet_01_box_F","CargoNet_01_barrels_F","B_CargoNet_01_ammo_F","Land_FoodSacks_01_cargo_brown_F"]
    
    private _objIdx = selectRandom (ITW_Zones#ITW_ZoneIndex);
    private _obj    = ITW_Objectives#_objIdx;
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    private _objName   = _obj#ITW_OBJ_NAME;
    
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
        [true, _taskId, [localize "STR_ITW_SDO_Failed",localize "STR_ITW_SDO_Failed",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        "itw" cutText [localize "STR_ITW_SDO_Failed","PLAIN"];
        diag_log "ITW: warning: No side ops position found for SdoResupply";
    };
    private _mrkr = [_taskId,_deliverPos,50,1,true] call ITW_SdoMarker; 
    [true, _taskId, [localize "STR_ITW_TGT_DeliverToDesc",localize "STR_ITW_SDO_Resupply",""], getMarkerPos _mrkr, "CREATED", -1, false, "", false] call BIS_fnc_taskCreate;
    
    private _crates = [];
    private _taskIds = [_taskId];
    
    private _types = [];
    for "_i" from 1 to _deliveryCount do {
        if (_types isEqualTo []) then {_types = SDO_DELIVER_BOX_TYPES call BIS_fnc_arrayShuffle};
        private _index = count _types - 1;
        private _type = _types#_index;
        _types deleteAt _index;
        
        private _crate = _type createVehicle _spawnPos;
        _crate allowDamage false;
        _crate setDir random 360;
        _crate setVariable ["persistent",true];
        
        private _crateTaskId = _taskId + str _i;
        [true, [_crateTaskId,_taskId], [format [localize "STR_ITW_TGT_deliverDesc",_i],localize "STR_ITW_TGT_deliverTitle",""], _crate, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
        _taskIds pushBack _crateTaskId;
        _crate setVariable ["tgtDeliverInfo",_crateTaskId];
        
        [_crate,_objName,mapGridPosition _deliverPos] remoteExec ["ITW_TgtDeliverMP",0,_crate];
        
        _crates pushBack _crate;
    };
    [_taskIds#1,_playerRequesting,nil,nil,true,nil,true,false] remoteExec ["bis_fnc_setTask",_playerRequesting];
    
    { _x addCuratorEditableObjects [_crates,true] } forEach allCurators;
    
    [_taskId,_taskIds,_crates,_mrkr] call ITW_SdoSetDeconstruct;
    
    private _zoneIndex = ITW_ZoneIndex;
    private _cratesEnroute = [];
    while {_zoneIndex == ITW_ZoneIndex && {!(_crates isEqualTo [])}} do {
        sleep 3;
        {
            private _crate = _x;
            private _isBeingCarried = !(isNull attachedTo _crate && {isNull ropeAttachedTo _crate});
            if (!_isBeingCarried && {_crate inArea _mrkr}) then {
                private _crateTaskId = _crate getVariable ["tgtDeliverInfo",""];
                [_crateTaskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                private _tasksCompleted = true;
                private _freeTask = "";
                {
                    if (_forEachIndex == 0) then {continue}; // first task is the deliver to location
                    if !(_x call BIS_fnc_taskCompleted) exitWith {
                        _tasksCompleted = false;
                        _freeTask = _x;
                    };
                } forEach _taskIds;
                if (_tasksCompleted) then {
                    deleteMarker _mrkr;
                    [_taskId,"SUCCEEDED",false] call BIS_fnc_taskSetState;
                    [_taskId] call ITW_SdoSetCompleted;
                } else {
                    if !(_freeTask isEqualTo "") then {
                        private _player = [getPosATL _crate,allPlayers] call ITW_FncClosest;
                        [_freeTask,nil,nil,nil,true,nil,false,false] remoteExec ["BIS_fnc_setTask",_player];
                    };
                };
                [_crate] remoteExec ["removeAllActions",0,_crate]; 
                _crates deleteAt _forEachIndex;
                sleep 1;
            };
            if (_isBeingCarried && {!(_crate in _cratesEnroute) && {!(isPlayer attachedTo _crate)}}) then {
                private _player = [getPosATL _crate,allPlayers] call ITW_FncClosest;
                if (_player distance _crate < 40) then {
                    _cratesEnroute pushBack _crate;
                    [_taskId,nil,nil,nil,true,nil,false,false] remoteExec ["BIS_fnc_setTask",_player];
                };
            };
            if (!_isBeingCarried && {_crate in _cratesEnroute}) then {
                _cratesEnroute = _cratesEnroute - [_crate]
            };
        } forEachReversed _crates;
    };
};

////////////////////////////////////////////////
//                   Tow                      //
////////////////////////////////////////////////
ITW_SdoTow = {
    // spawn on server  
    params ["_playerRequesting","_taskId"];
    scriptName "ITW_SdoTow";

    private _objIdx = selectRandom (ITW_Zones#ITW_ZoneIndex);
    private _obj = ITW_Objectives#_objIdx;
    private _objCenter = _obj#ITW_OBJ_POS;
    private _objSize   = _obj#ITW_OBJ_SIZE;
    
    private _dir = random 360;
    private _vehType = selectRandom (selectRandom [va_pTankClasses,va_pApcClasses,va_pTankClasses,va_pApcClasses,va_pCarClasses]);
    if (isNil "_vehType") then {_vehType = ""};
    private _vehName = getText (configFile >> "cfgVehicles" >> (if (typeName _vehType == "ARRAY") then {_vehType#0} else {_vehType}) >> "displayName");
    private _taskDesc = [format [localize "STR_ITW_SDO_TowDesc",_vehName],localize "STR_ITW_SDO_Tow",""];
    private _distMin = _objSize;
    private _distMax = _objSize + 800;
    
    private _pos = [];
    _pos = [_objCenter, _distMin, _distMax, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo []) then {
        _pos = [_objCenter, _distMin, _distMax + 250, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        if (_pos isEqualTo []) then {
            _pos = [_objCenter, 0, _distMin, 5, 0, 0.5, 0, ["water"], [[0],[0]]] call BIS_fnc_findSafePos;
        };
        if !(_pos isEqualTo [0]) then {
            _pos set [2,0];
        };
    };
    if (_pos isEqualTo [0] || _vehType isEqualTo "") exitWith {
        [true, _taskId, [localize "STR_ITW_SDO_Failed",localize "STR_ITW_SDO_Failed",""], objNull, "CANCELED", -1, false, "", false] call BIS_fnc_taskCreate;
        "itw" cutText [localize "STR_ITW_SDO_Failed","PLAIN"];
        diag_log "ITW: warning: No side ops position found for SdoTow";
    };
    
    private _mrkr = [_taskId,_pos,50] call ITW_SdoMarker;
    
    // create vehicle
    private _veh = [_vehType,_pos] call ITW_VehCreateVehicle;
    _veh setDamage 0.85;
    _veh allowDamage false;
    _veh setFuel 0;
    _veh lock 2;
    _veh setVariable ["itw_dmgBlocked",true];
    _veh setVariable ["persistent",true];
    { _x addCuratorEditableObjects [[_veh],true] } forEach allCurators;
    
    [true, _taskId, _taskDesc, getMarkerPos _mrkr, "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    [_taskId,_playerRequesting,nil,nil,true,nil,true,false] remoteExec ["bis_fnc_setTask",_playerRequesting];
    
    [_taskId,_taskId,_veh,_mrkr] call ITW_SdoSetDeconstruct;
    
    private _found = false;
    while {alive _veh} do {
        sleep 10;
        _veh setDamage 0.85; // don't let it be repaired
        if (!_found && {playableUnits findIf {_x distance _veh < 10} != -1}) then {
            _found = true;
            deleteMarker _mrkr;
            [_taskId,[_veh,true]] call BIS_fnc_taskSetDestination;
        };
        if (isTouchingGround _veh && {isNull getTowParent _veh}) then {
            private _nearestBase = [_veh,ITW_OWNER_FRIENDLY,true,true] call ITW_BaseNearest;
            private _basePos = _nearestBase#ITW_BASE_POS;
            if (_veh distanceSqr _basePos < 22500) then {
                [_taskId] call ITW_SdoSetCompleted;
                [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
                waitUntil {sleep 10;playableUnits findIf {_x distance _basePos < 600} == -1};
                deleteMarker _mrkr;
                deleteVehicle _veh;
            };
        };
    };
    if !(_taskId call BIS_fnc_taskCompleted) then {
        [_taskId,"FAILED",true] call BIS_fnc_taskSetState;
        deleteMarker _mrkr;
        deleteVehicle _veh;
    };
};

// itw_tow_state: 0 = none, 1 = tow truck, 2 = veh being towed
// itw_tow_truck: on tow truck and veh being towed = [otherTruck,rope];  on player = towTruck while player connecting ropes
ITW_SideOpsTowAddActions = {
	player addAction ["<t color='#ccffcc'>" + localize "STR_ITW_SDO_TowPickVeh"+ "</t>", {
		[] spawn ITW_SdoTowPickVeh;
	}, nil, 0, false, true, "", "false call ITW_SdoTowable"];

	player addAction ["<t color='#ccffcc'>" + localize "STR_ITW_SDO_TowAttach"+ "</t>", {
		[] call ITW_SdoTowAttach;
	}, nil, 0, false, true, "", "true call ITW_SdoTowable"];
    
	player addAction ["<t color='#ccffcc'>" + localize "STR_ITW_SDO_TowDetach"+ "</t>", {
		[] call ITW_SdoTowDetach;
	}, nil, 0, false, true, "", "cursorTarget getVariable ['itw_tow_state',0] != 0"];
};

ITW_SdoTowable = {
    private _playerHasRopes = _this;
    if ((isNull (player getVariable ["itw_tow_truck",objNull])) == _playerHasRopes) exitWith {false};
    
    private _veh = cursorTarget;
    if (!alive _veh) exitWith {false};
    if (_playerHasRopes && {player getVariable ["itw_tow_truck",player] distance _veh > 30}) exitWith {false};
    if (!_playerHasRopes && {!canMove _veh || {fuel _veh == 0}}) exitWith {false};
        
    private _canTow = false;
    if (_veh distanceSqr player < ([49,100] select _playerHasRopes)) then {
        if (_veh getVariable ['itw_tow_state',0] == 0) then {
            _canTow = (_veh isKindOf "Car" || {_veh isKindOf "Tank"|| {_veh isKindOf "Ship"}});
        };
    };
    _canTow
};

ITW_SdoTowPickVeh = {
    // spawn on client
    private _towTruck = cursorTarget;
    _towTruck setVariable ["itw_tow_state",1];
    player setVariable ["itw_tow_truck",_towTruck];
    "itw" cutText [localize "STR_ITW_SDO_TowInstructions","PLAIN"];
    private _timeout = time + 20;
    waitUntil {sleep 1;time > _timeout || isNull (player getVariable ["itw_tow_truck",objNull])};
    "itw" cutText ["","PLAIN",0.1];
    if (!isNull (player getVariable ["itw_tow_truck",objNull])) then {
        player setVariable ["itw_tow_truck",objNull];
        hint localize "STR_ITW_COMMON_OperationCancel";
    };
};

ITW_SdoTowAttach = {
    private _towedVehicle = cursorTarget;
    private _towTruck = player getVariable ["itw_tow_truck",objNull];
    player setVariable ["itw_tow_truck",objNull];
    if (!isNull _towTruck) then {
        private _bbTowing = 0 boundingBoxReal _towTruck;
        private _bbTowed  = 0 boundingBoxReal _towedVehicle;
        private _minTowing = _bbTowing select 0;
        private _minTowed = _bbTowed select 0;
        private _maxTowed = _bbTowed select 1;
        private _towingAttachPoint = [0, 0.5*(_minTowing select 1), (_minTowing select 2) + 0.8];
        private _towedAttachPoint = [0, 0.5*(_maxTowed select 1), (_minTowed select 2) + 0.8];
        
        private _rope = ropeCreate [_towTruck, _towingAttachPoint, _towedVehicle, _towedAttachPoint];
        _towedVehicle setTowParent _towTruck;
        _towedVehicle setVariable ["itw_tow_truck",[_towTruck,_rope]];
        _towTruck     setVariable ["itw_tow_truck",[_towedVehicle,_rope]];
        _towedVehicle setVariable ["itw_tow_state",2];
    } else {
        _towTruck setVariable ["itw_tow_state",0];
    };
};

ITW_SdoTowDetach = {
    private _veh = cursorTarget;
    (_veh getVariable ["itw_tow_truck",[objNull,objNull]]) params ["_otherTruck","_rope"];
    ropeDestroy _rope;
    _otherTruck setVariable ["itw_tow_truck",nil];
    _veh        setVariable ["itw_tow_truck",nil];
    _otherTruck setVariable ["itw_tow_state",0];
    _veh        setVariable ["itw_tow_state",0];
};

////////////////////////////////////////////////
//                   Transport                //
////////////////////////////////////////////////
ITW_SdoTransport = {
    // spawn on server  
    params ["_playerRequesting","_taskId"];
    scriptName "ITW_SdoTransport";

    private _objIdx = selectRandom (ITW_Zones#ITW_ZoneIndex);
    private _obj = ITW_Objectives#_objIdx;
    private _objCenter = _obj#ITW_OBJ_POS;
    while {_obj#ITW_OBJ_ATTACKS isEqualTo EMPTY_OBJ_ATTACKS} do {sleep 1};
    private _baseIdx = _obj#ITW_OBJ_ATTACKS#ITW_ATTACK_LAND_F;
    if (_baseIdx == BASE_INDEX_NONE) then {_baseIdx = _obj#ITW_OBJ_ATTACKS#ITW_ATTACK_AIR_F};
    private _spawnPos = ITW_Bases#_baseIdx#ITW_BASE_A_SPAWN;
        
    // create squad
    private _grp = createGroup [ITW_PlayerSide,false];
    private _units = [];
    waitUntil {!isNil "ITW_AllyUnitTypes"};
    for "_i" from 1 to AI_SQUAD_SIZE do {
        private _unit = [_grp, ITW_AllyUnitTypes, _spawnPos, false] call ITW_AtkUnitToGroup;
        _unit setVariable ["itw_dmgBlocked",true];
        _units pushBack _unit
    };
    _grp deleteGroupWhenEmpty true;
    [_grp] call ITW_AtkAddInfantryGroup;
    [_grp] call ITW_AllyGroupCallback;
    [_grp] call ITW_AllyDelivery;
    
    [true, _taskId, [localize "STR_ITW_SDO_TransportDesc",localize "STR_ITW_SDO_Transport",""], [leader _grp,true], "CREATED", 1, false, "", false] call BIS_fnc_taskCreate;
    [_taskId,_playerRequesting,nil,nil,true,nil,true,false] remoteExec ["bis_fnc_setTask",_playerRequesting];
    
    [_taskId,_taskId,[],[]] call ITW_SdoSetDeconstruct;
    
    private _started = false;
    private _distanceSqr = (_obj#ITW_OBJ_SIZE + 820)^2;
    
    while {alive leader _grp} do {
        sleep 10;
        private _leader = leader _grp;
        private _inVeh = vehicle _leader != _leader;
        if (!_started && {_inVeh}) then {
            {_x setVariable ["itw_dmgBlocked",false]; _x allowDamage true} forEach _units;
            _started = true;
        };
        if (!_inVeh && {_leader distanceSqr (([getPosATL _leader,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest)#ITW_OBJ_POS) < _distanceSqr}) exitWith {};
    };
    if (alive (leader _grp)) then {
        [_taskId] call ITW_SdoSetCompleted;
        [_taskId,"SUCCEEDED",true] call BIS_fnc_taskSetState;
    } else {
        [_taskId,"FAILED",true] call BIS_fnc_taskSetState;
    };
};

["ITW_SideOps"] call SKL_fnc_CompileFinal;
["ITW_SideOpsNext"] call SKL_fnc_CompileFinal;
["ITW_SideOpsAdvantage"] call SKL_fnc_CompileFinal;
["ITW_SdoSetDeconstruct"] call SKL_fnc_CompileFinal;
["ITW_SdoSetCompleted"] call SKL_fnc_CompileFinal;
["ITW_SdoMarker"] call SKL_fnc_CompileFinal;
["ITW_SideOpsSave"] call SKL_fnc_CompileFinal;
["ITW_SideOpsLoad"] call SKL_fnc_CompileFinal;
["ITW_SdoMedivac"] call SKL_fnc_CompileFinal;
["ITW_SdoResupply"] call SKL_fnc_CompileFinal;
["ITW_SdoTow"] call SKL_fnc_CompileFinal;
["ITW_SdoTransport"] call SKL_fnc_CompileFinal;
["ITW_SdoSetTaskCurrent"] call SKL_fnc_CompileFinal;