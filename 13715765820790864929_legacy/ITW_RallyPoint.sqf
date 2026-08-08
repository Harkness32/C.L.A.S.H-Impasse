#include "defines.hpp"

ITW_rallyPointBase = objNull;
ITW_rallyPointMarker = "";
ITW_rallyPointObjIdx = -1;
ITW_rallyPointZoneIndex = -1;

#define RALLY_POINT_BOX_TYPE "Land_PaperBox_01_small_stacked_F"

ITW_RallyPointSpawnCrate = {
    params ["_pos"];
    _pos set [2,15];
    private _crate = RALLY_POINT_BOX_TYPE createVehicle _pos;
    _crate allowDamage false;
    _crate setPosATL _pos;
    _crate setVariable ["Deployed",false,true];
    [_crate] remoteExec ["ITW_RallyPointBoxMP",0,_crate];
    ITW_rallyPointBase = _crate;
    publicVariable "ITW_rallyPointBase";
};
        
ITW_RallyPointDelete = {
    if !(isServer) exitWith {0 remoteExec ["ITW_RallyPointDelete",2]};
    deleteVehicle ITW_rallyPointBase;
    ITW_rallyPointBase = objNull;
    publicVariable 'ITW_rallyPointBase';
    deleteMarker ITW_rallyPointMarker;
};

ITW_RallyPointBoxMP = {
    params ["_crate"];
    if (!hasInterface) exitWith {};
    
    0 spawn ITW_rallyPointMarkerUpdater;
    
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_RP_MoveToRallyPoint"+"</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            cutText ["<t size='3'>" + localize "STR_ITW_RP_Instructions", "PLAIN", -1, true, true];
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true])",4]; 
        
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Deploy" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            if !(isNull attachedTo _crate) then {
                private _carrier = attachedTo _crate;
                _carrier setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                sleep 0.5;
                player setAnimSpeedCoef 1;
                _crate setVelocity [0,0,-0.1]; 
            };
            private _obj = [getPosATL _crate,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED] call ITW_ObjGetNearest;
            private _objDist = _obj#ITW_OBJ_POS distance _crate;
            private _objSize = _obj#ITW_OBJ_SIZE;
            if (_objDist > (_objSize + 500)) then {
                [_crate,true] remoteExec ["ITW_RallyPointDeploy",2];
            } else {
                hint localize "STR_ITW_RP_TooClose";
            };
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true])",4]; 
        
    _crate addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Carry" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            _crate attachTo [player, [0, 2, 1]];
            player setAnimSpeedCoef 0.7;
            player playAction "PlayerStand";
            player action ["SwitchWeapon",player,player,-1];
            player addAction ["<t color='#aaaadd'>"+localize "STR_ITW_AF_Drop"+"</t>", { 
                params ["_player", "_caller", "_actionId", "_arguments"];
                private _crate = ITW_RP_CRATE; 
                player setVelocity [0,0,0];
                _crate setVelocity [0,0,0];
                detach _crate;
                sleep 0.5;
                player setAnimSpeedCoef 1;
                _crate setVelocity [0,0,-0.1]; 
                _player removeAction _actionId;
            },nil,10,false,true,"","player == attachedTo ITW_RP_CRATE",4];
        },nil,10,false,true,"","!(_target getVariable ['Deployed',true]) && {(isPlayer _this) && {isNull attachedTo _target}}",4];  
    ITW_RP_CRATE = _crate;
    
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_LoadInVehicle" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            player addAction ["<t color='#ff0000'>" + localize "STR_ITW_AF_SelectVehicle" + "</t>", {
                params ["_target", "_caller", "_actionId", "_crate"];
                player removeAction _actionId;
                private _veh = cursorTarget;
                if (_veh isKindOf "Helicopter") then {
                    hint localize "STR_ITW_AF_UseSlingLoad";
                } else {
                    if ((_veh isKindOf "Land" || _veh isKindOf "Sea") && {alive _veh && {speed _veh < 1 && {boundingBox _veh #2 > 5.5}}}) then {
                        if (!simulationEnabled _veh) then {
                            [_veh,true] remoteExec ["enableSimulationGlobal",2];
                            [_veh,true] remoteExec ["allowDamage",_veh];
                        };
                        private _dimensions = getArray (configOf _veh >> "VehicleTransport" >> "Carrier" >> "cargoBayDimensions");
                        private "_loadPos";
                        if (_dimensions isEqualTo []) then {
                            _loadPos = [0,-1.8,0.3];
                        } else {
                            {
                                if (typeName _x isEqualTo "STRING") then {_dimensions set [_forEachIndex,_veh selectionPosition _x]};
                            } forEach _dimensions;
                            _loadPos = [(_dimensions#0#0 + (_dimensions#1#0))/2,(_dimensions#0#1 + (_dimensions#1#1))/2,(_dimensions#0#2) + 0.8];
                        };
                        _crate attachTo [_veh,_loadPos];
                        [_veh,_crate] remoteExec ["ITW_RallyPointBoxLoadMP",0];
                    } else {
                        hint localize "STR_ITW_AF_NoVehSelected";
                    };
                };
            },_crate,100,true,true,"","_this == _target",4]; 
        },nil,10,false,true,"","!(ITW_rallyPointBase getVariable ['Deployed',false]) && {isNull attachedTo _target}",4]; 
        
    _crate addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_RetractDeployment" + "</t>", {
            params ["_crate", "_caller", "_actionId", "_arguments"];
            ITW_YesNoMenu3 = [
                [localize "STR_ITW_AF_RetractDeployment", true],
                [localize "STR_ITW_COMMON_No",  [], "", -5, [["expression", "hint localize 'STR_ITW_COMMON_OperationCancel'"]], "1", "1"],
                [localize "STR_ITW_COMMON_Yes", [], "", -5, [["expression", 
                    '[objNull,false] remoteExec ["ITW_RallyPointDeploy",2]'
                ]], "1", "1"]
            ];
            showCommandingMenu "#USER:ITW_YesNoMenu3";
        },nil,10,false,true,"","_target getVariable ['Deployed',true]",4];  
};

ITW_RallyPointBoxLoadMP = {
    // call on all clients
    params ["_veh","_crate"];
    if (!hasInterface) exitWith {};
    private _timeout = time + 5;
    waitUntil {simulationEnabled _veh || {time > _timeout}}; 
    sleep 1;
    ITW_RallyPointBoxUnloadActionId = _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_AF_UnloadAfCrate" + "</t>", {
        params ["_veh", "_caller", "_actionId", "_crate"];
        [_veh,false] remoteExec ["allowDamage",_veh];
        playSoundUI ["A3\Sounds_F_Orange\vehicles\soft\Van_02\Van_02_Door_Slide_02.wss", 0.5, 1];
        sleep 1;
        detach _crate;
        _crate setDir getDir _veh;
        private _pos = _veh getPos [((boundingBox _veh)#2)/2 + 3,(getDir _veh) + 180];
        _pos set [2,3];
        _crate setPos _pos;
        [_veh] remoteExec ["ITW_RallyPointBoxUnloadMP",0];
        sleep 3;
        [_veh,true] remoteExec ["allowDamage",_veh];
    },_crate,100,false,true,"","!(isNull attachedTo ITW_rallyPointBase)",8]; 
};

ITW_RallyPointBoxUnloadMP = {
    params ["_veh"];
    if !(isNil "ITW_RallyPointBoxUnloadActionId") then {
        _veh removeAction ITW_RallyPointBoxUnloadActionId;
        ITW_RallyPointBoxUnloadActionId = nil;
    };
};

ITW_rallyPointMarkerUpdater = {
    scriptName "ITW_rallyPointMarkerUpdater";
    // spawn on all clients
    #define ITW_rallyPointMarker "ITW_RallyPoint_mkr"
    if (!hasInterface) exitWith {};
    sleep 1; // make sure all the things we're looking at have been updated over network
    if (getMarkerColor ITW_rallyPointMarker isEqualTo "") then {
        private _mrkr = createMarkerLocal [ITW_rallyPointMarker, getPosATL ITW_rallyPointBase];
        _mrkr setMarkerColorLocal "Color4_FD_F";
        _mrkr setMarkerSizeLocal [0.7,0.7];
        _mrkr setMarkerTypeLocal "mil_join_noshadow";
        _mrkr setMarkerTextLocal localize "STR_ITW_RP_RallyPoint";
    };
    ITW_rallyPointMarker setMarkerColorLocal "Color4_FD_F";
    while {!isNull ITW_rallyPointBase && {!(ITW_rallyPointBase getVariable ["Deployed",false])}} do {
        ITW_rallyPointMarker setMarkerPosLocal getPosATL ITW_rallyPointBase;
        sleep 2;
    };
    if (ITW_rallyPointBase getVariable ["Deployed",false]) then {
        ITW_rallyPointMarker setMarkerPosLocal getPosATL ITW_rallyPointBase;
        ITW_rallyPointMarker setMarkerColorLocal "ColorBLUFOR";
    } else {
        deleteMarkerLocal ITW_rallyPointMarker;
    };
};

ITW_RallyPointDeploy = {
    // call on server
    params ["_crate","_deploy"];
    ITW_rallyPointZoneIndex = -1; // force ITW_rallyPointObjIdx to be recalculated 
    if (_deploy) then {
        _crate setVariable ['Deployed',true,true];
    } else {
        _crate = ITW_rallyPointBase;
        _crate setVariable ['Deployed',false,true];
        [] remoteExec ["ITW_rallyPointMarkerUpdater",0,"RpMrkr"];
    };
};

ITW_RallyPoint_ObjectivePoint = {
    // return the rally point of the given objIndex, or [] if no rally point setup, or rally point is at another objective
    params ["_objIdx"];
    if (isNull ITW_rallyPointBase || {!(ITW_rallyPointBase getVariable ["Deployed",false])}) exitWith {[]};
    
    if (ITW_rallyPointZoneIndex != ITW_ZoneIndex) then {
        ITW_rallyPointObjIdx = ([getPosATL ITW_rallyPointBase,ITW_OWNER_CONTESTED,ITW_OWNER_CONTESTED,false] call ITW_ObjGetNearest)#ITW_OBJ_INDEX;
    };
    private _pos = if (ITW_rallyPointObjIdx == _objIdx) then {getPosATL ITW_rallyPointBase} else {[]};
    _pos
};

ITW_RallyPointLoad = {
    params ["_rallyPointData"];
    if (count _rallyPointData == 2) then {
        _rallyPointData params ["_cratePos","_isDeployed"];
        if !(_cratePos isEqualTo []) then {
            [_cratePos] call ITW_RallyPointSpawnCrate;
            [ITW_rallyPointBase,_isDeployed] call ITW_RallyPointDeploy;
        };
    };
};

ITW_RallyPointSave = {
    private _rallyPointData = 
    if (isNull ITW_rallyPointBase) then {[]}
    else {[getPosATL ITW_rallyPointBase,ITW_rallyPointBase getVariable ['Deployed',false]]};
    _rallyPointData
};

["ITW_RallyPointSpawnCrate"] call SKL_fnc_CompileFinal;
["ITW_RallyPointDelete"] call SKL_fnc_CompileFinal;
["ITW_RallyPointBoxMP"] call SKL_fnc_CompileFinal;
["ITW_RallyPointBoxLoadMP"] call SKL_fnc_CompileFinal;
["ITW_RallyPointBoxUnloadMP"] call SKL_fnc_CompileFinal;
["ITW_rallyPointMarkerUpdater"] call SKL_fnc_CompileFinal;
["ITW_RallyPointDeploy"] call SKL_fnc_CompileFinal;
["ITW_RallyPointLoad"] call SKL_fnc_CompileFinal;
["ITW_RallyPointSave"] call SKL_fnc_CompileFinal;
["ITW_RallyPoint_ObjectivePoint"] call SKL_fnc_CompileFinal;