
#include "defines.hpp"
#include "\a3\ui_f\hpp\definecommongrids.inc"

ITW_fortificationObjects = [];
ITW_fortificationFastTravelBoards = []; 

ITW_FortificationsInit = {
    // run on all clients
    
    // setup to capture zeus placed objects as well
    [] spawn {
        scriptName "ITW_FortCuratorObjects";
        while {true} do {
            {
                if (isNil {_x getVariable "hasCuratorPlacedEH"}) then {
                    _x addEventHandler ["CuratorObjectPlaced", {
                        params ["_curator", "_entity"];
                        // save statics,objects,buildings  but no vehicles/units
                        if (_entity isKindOf "Static" || _entity isKindOf "ThingX") then {
                            [_entity] remoteExec ["ITW_FortSaveZeusEntity",2];
                        };
                    }];
                    _x setVariable ["hasCuratorPlacedEH", true];
                };
            } forEach allCurators;
            sleep 10;
        };
    };
};

ITW_FortificationsPlace = {
    private _constructionVeh = _this;
    
    // ensure list is populated
    if (isNil "ITW_FORTIFICATION_INFO") then {
        ITW_FORT_INDEX = 0;
        private _fortInfo = [];
        {
            private _cfg = _x;
            private _type = getText (_cfg >> "vehicleClass");
            if (typeName _type == "") then {
                private _types = getArray (_cfg >> "vehicleClass");
                {_type = _type + _x} forEach _types;
            };
            _type = toLowerANSI _type;
            if ("fortification" in _type || {"military" in _type}) then {
                private _editorCategory    = getText (_cfg >> "editorCategory");
                private _editorSubcategory = getText (_cfg >> "editorSubcategory");
                private _displayName       = getText (_cfg >> "displayName");
                _fortInfo pushBack [getText (configFile >> "cfgEditorCategories" >> _editorCategory >> "displayName"),
                                    getText (configFile >> "cfgEditorSubcategories" >> _editorSubcategory >> "displayName"),
                                    _displayName,
                                    configName _cfg];
            };
        } forEach ("getNumber (_x >> 'scope') == 2 && {getNumber (_x >> 'mapSize') < 15}" configClasses (configFile >> "CfgVehicles"));
        _fortInfo sort true;
        ITW_FORTIFICATION_INFO = _fortInfo;
    };
    
    private _running = true;
    ITW_FORT_ALL_OBS = [];
    while {_running} do {
        private _btnW = 0.042*safeZoneW;
        private _btnH = 0.027*safeZoneH;
        private _margin = 0.1*_btnW;
        private _fontH = GUI_GRID_H * 0.8;
        
        private _display = findDisplay 46 createDisplay "RscDisplayEmpty";
        private _shadow = _display ctrlCreate ["RscText", -1];
        _shadow ctrlSetPosition [safeZoneX,safeZoneY,0.15*safeZoneW + 2*_margin,safeZoneH];
        _shadow ctrlSetBackgroundColor [0.5,0.5,0.5,0.5];
        _shadow ctrlCommit 0;
        
        private _tv = _display ctrlCreate ["RscTree", -1];
        _tv ctrlSetPosition [safeZoneX+_margin,safeZoneY+_margin,0.15*safeZoneW,safeZoneH -2*_btnH - 2*_margin];
        _tv ctrlSetBackgroundColor [0,0,0,0.7];
        _tv ctrlSetFontHeight _fontH;
        _tv ctrlCommit 0;
        
        private _collapseBtn = _display ctrlCreate ["RscButton", -1];
        _collapseBtn ctrlSetPosition [safeZoneX+_margin,safeZoneY + safeZoneH - _btnH*1.8 - _margin,_btnW*0.3,_btnH*0.6];
        _collapseBtn ctrlSetBackgroundColor [0,0,0,0.7];
        _collapseBtn ctrlSetText "<<";
        _collapseBtn ctrlSetFontHeight _fontH;
        _collapseBtn ctrlCommit 0;
        
        private _expandBtn = _display ctrlCreate ["RscButton", -1];
        _expandBtn ctrlSetPosition [safeZoneX + _margin + 0.15*safeZoneW - 0.3*_btnW,safeZoneY + safeZoneH - _btnH*1.8 - _margin,_btnW*0.3,_btnH*0.6];
        _expandBtn ctrlSetBackgroundColor [0,0,0,0.7];
        _expandBtn ctrlSetText ">>";
        _expandBtn ctrlSetFontHeight _fontH;
        _expandBtn ctrlCommit 0;
        
        private _okayBtn = _display ctrlCreate ["RscButton", -1];
        _okayBtn ctrlSetPosition [safeZoneX + _margin + 0.15*safeZoneW - _btnW,safeZoneY + safeZoneH - _btnH - _margin,_btnW,_btnH];
        _okayBtn ctrlSetBackgroundColor [0,0,0,0.7];
        _okayBtn ctrlSetText localize "STR_ITW_FORT_Place";
        _okayBtn ctrlSetFontHeight _fontH;
        _okayBtn ctrlCommit 0;
        
        private _doneBtn = _display ctrlCreate ["RscButton", -1];
        _doneBtn ctrlSetPosition [safeZoneX + _margin + 0.15/2*safeZoneW - _btnW/2,safeZoneY + safeZoneH - _btnH - _margin,_btnW,_btnH];
        _doneBtn ctrlSetBackgroundColor [0,0,0,0.7];
        _doneBtn ctrlSetText localize "STR_ITW_COMMON_Done";
        _doneBtn ctrlSetFontHeight _fontH;
        _doneBtn ctrlCommit 0;
        
        private _cancelBtn = _display ctrlCreate ["RscButton", -1];
        _cancelBtn ctrlSetPosition [safeZoneX + _margin,safeZoneY + safeZoneH - _btnH - _margin,_btnW,_btnH];
        _cancelBtn ctrlSetBackgroundColor [0,0,0,0.7];
        _cancelBtn ctrlSetText localize "STR_ITW_COMMON_Cancel";
        _cancelBtn ctrlSetFontHeight _fontH;
        _cancelBtn ctrlCommit 0;
            
        private _catMap = createHashmap;    
        {
            _x params ["_cat","_sub","_name","_class"];
            private _catInfo = _catMap get _cat;
            private ["_catPath","_subMap"];
            if (isNil "_catInfo") then {
                _catPath = count _catMap;
                _subMap = createHashmap;
                _catMap set [_cat,[_catPath,_subMap]];
                _tv tvAdd [[],_cat];
            } else {
                _catPath = _catInfo#0;
                _subMap = _catInfo#1;
            };
            private _subPath = _subMap get _sub;
            if (isNil "_subPath") then {
                _subPath = count _subMap;
                _subMap set [_sub,_subPath];
                _tv tvAdd [[_catPath],_sub];
            };
            private _path = [_catPath,_subPath];
            private _index = _tv tvAdd [_path,_name];
            _path pushBack _index;
            _tv tvSetData [_path,_class];
            _tv tvSetValue [_path,_forEachIndex+1]; // _id counts from 1 since 0 is the 'no selection case'
            
            if (_forEachIndex == ITW_FORT_INDEX) then {_tv tvSetCurSel _path};
        } forEach ITW_FORTIFICATION_INFO;
        tvExpandAll _tv;
        
        #define TV_BTN_NONE     0
        #define TV_BTN_DONE     1
        #define TV_BTN_OKAY     2
        #define TV_BTN_CANCEL   3
        #define TV_BTN_COLLAPSE 4
        #define TV_BTN_EXPAND   5
        
        _okayBtn ctrlAddEventHandler ["ButtonClick", {
            TV_BtnCtrl = TV_BTN_OKAY;
        }];    
        _doneBtn ctrlAddEventHandler ["ButtonClick", {
            TV_BtnCtrl = TV_BTN_DONE;
        }];
        _cancelBtn ctrlAddEventHandler ["ButtonClick", {
            TV_BtnCtrl = TV_BTN_CANCEL;
        }];  
        _collapseBtn ctrlAddEventHandler ["ButtonClick", {
            TV_BtnCtrl = TV_BTN_COLLAPSE;
        }];    
        _expandBtn ctrlAddEventHandler ["ButtonClick", {
            TV_BtnCtrl = TV_BTN_EXPAND;
        }];  
        
        private _fortIndex = -1;
        private _exitTV = false;
        while {!_exitTV} do {
            _exitTV = true;
            TV_BtnCtrl = TV_BTN_NONE;
            waitUntil {TV_BtnCtrl != TV_BTN_NONE || isNull _display || !alive _constructionVeh || !CONSCIOUS(player)};
            switch (TV_BtnCtrl) do {
                case TV_BTN_CANCEL: {};
                case TV_BTN_DONE:   {[ITW_FORT_ALL_OBS] spawn ITW_FortPlace;ITW_FORT_ALL_OBS = []};
                case TV_BTN_OKAY:   {
                    private _selId = tvCurSel _tv;           
                    private _id = _tv tvValue _selId;
                    if (_id > 0) then {
                        _fortIndex = _id - 1; // _id counts from 1 since 0 is the 'no selection case'
                    };
                };
                case TV_BTN_COLLAPSE: {_exitTV = false; tvCollapseAll _tv};
                case TV_BTN_EXPAND:   {_exitTV = false; tvExpandAll _tv};
            };
        };
        TV_BtnCtrl = nil;
        _display closeDisplay 2;
        
        if (_fortIndex >= 0 && {alive _constructionVeh && {CONSCIOUS(player)}}) then {
            [ITW_FORTIFICATION_INFO,_fortIndex,_constructionVeh] call ITW_FORT_UserPlaceObject;
        } else {
            _running = false;
            {deleteVehicle _x} forEach ITW_FORT_ALL_OBS;
        };
    };
    ITW_FORT_ALL_OBS    = nil;
};

ITW_FORT_UserPlaceObject = {
    // to use this function, define ITW_FORT_ALL_OBS = [].  Each call to this function will add an object to that array if the user placed it.
    // _fortInfo is an array [_category, _subcategory, _name, _class]  only _name and _class are used by this function
    params ["_fortInfo","_fortIndex","_constructionVeh"];
    
    ITW_FORT_USER_OBJS = _fortInfo;
    #define DIK_UP     200
    #define DIK_DOWN   208
    #define DIK_RIGHT  205
    #define DIK_LEFT   203
    #define DIK_SPACE   57
    #define DIK_ENTER   28
    #define DIK_BACK    14
    #define DIK_ESC      1
    #define DIK_DELETE 211
    
    #define FORT_NO_ACTION    0
    #define FORT_DIR_RIGHT    1
    #define FORT_DIR_LEFT     2
    #define FORT_DIR_RIGHT_10 3
    #define FORT_DIR_LEFT_10  4
    #define FORT_PLACE        5
    #define FORT_DONE         6
    #define FORT_NEW_TYPE     7
    
    (ITW_FORT_USER_OBJS#_fortIndex) params ["_cat","_subcat","_name","_class"];
    ITW_FORT_PLACE_INFO = [FORT_NEW_TYPE];
    ITW_FORT_PLACE_INFO pushBack _class;
    ITW_FORT_PLACE_INFO pushBack _name;
    ITW_FORT_INDEX     = _fortIndex;
    ITW_FORT_NAME      = _name;
    ITW_FORT_TEXT_TIME = 0;
    ITW_FORT_CONST_VEH = _constructionVeh;
    ITW_FORT_LOOK_POS  = [0,0,0];
    ITW_FORT_PREVIEW   = objNull;
    ITW_FORT_SHIFT     = false;   
    
    private _mzcHandler = findDisplay 46 displayAddEventHandler ["MouseZChanged", {
        params ["_displayOrControl", "_scroll"];
        private _handled = false;
        if (_scroll > 0) then {ITW_FORT_PLACE_INFO pushBack (if (ITW_FORT_SHIFT) then {FORT_DIR_RIGHT_10} else {FORT_DIR_RIGHT});_handled = true};
        if (_scroll < 0) then {ITW_FORT_PLACE_INFO pushBack (if (ITW_FORT_SHIFT) then {FORT_DIR_LEFT_10 } else {FORT_DIR_LEFT });_handled = true};
        _handled
    }];
    
    private _kuHandler = findDisplay 46 displayAddEventHandler ["KeyUp", {
        params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];
        private _handled = true;               
        ITW_FORT_SHIFT = _shift;
        _handled
    }];
    
    private _kdHandler = findDisplay 46 displayAddEventHandler ["KeyDown", {
        params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];
        private _handled = true;
        ITW_FORT_SHIFT = _shift;
        switch (_key) do {
            case DIK_UP;
            case DIK_DOWN: {  // next/prev fortification
                if (_key == DIK_UP) then {
                    ITW_FORT_INDEX = ITW_FORT_INDEX + 1;
                    if (ITW_FORT_INDEX >= count ITW_FORT_USER_OBJS) then {
                        ITW_FORT_INDEX = 0;
                    };
                } else {
                    ITW_FORT_INDEX = ITW_FORT_INDEX - 1;
                    if (ITW_FORT_INDEX < 0) then {
                        ITW_FORT_INDEX = (count ITW_FORT_USER_OBJS) - 1;
                    };
                };
                ITW_FORT_PLACE_INFO pushBack FORT_NEW_TYPE;
                (ITW_FORT_USER_OBJS#ITW_FORT_INDEX) params ["_cat","_subcat","_name","_class"];
                ITW_FORT_PLACE_INFO pushBack _class;
                ITW_FORT_PLACE_INFO pushBack _name;
            };
            
            case DIK_RIGHT: { // rotate fortification
                ITW_FORT_PLACE_INFO pushBack FORT_DIR_RIGHT;
            };
            case DIK_LEFT: { // rotate fortification
                ITW_FORT_PLACE_INFO pushBack FORT_DIR_LEFT;
            };
            case DIK_SPACE;
            case DIK_ENTER: { // place object
                ITW_FORT_PLACE_INFO pushBack FORT_PLACE;
            };
            case DIK_ESC: {  // done
                ITW_FORT_PLACE_INFO pushBack FORT_DONE;
            };
            default {_handled = false};
        };
        // I got stuck in this handler once so add this for debug
        if (!_handled) then {ITW_FORT_HANG1 = ["ITW_FORT KeyDown",_key,ITW_FORT_PLACE_INFO]};
        
        _handled;
    }];

    private _efHandler = addMissionEventHandler ["EachFrame", {
        scopeName "ITW_FortPlaceEFHandler";
        if (time > ITW_FORT_TEXT_TIME) then {
            "fort" cutText ["<t size='1.6'><br/><br/><br/><br/><br/><br/><br/>"+ITW_FORT_NAME+"</t><br/><t size='1.25'>" + localize "STR_ITW_FORT_Info" + "</t>","PLAIN",-1,true,true];
            ITW_FORT_TEXT_TIME = time + 10;
        };
        private _action = ITW_FORT_PLACE_INFO deleteAt 0;      
        if (player distance ITW_FORT_CONST_VEH > 100) then {
            _action = FORT_DONE;
            playSoundUI ["a3\sounds_f_exp\sfx\debug\sine880hz-10db.wss",1,1,false,1.5];
            hint localize "STR_ITW_FORT_TooFarFromVeh";
        };
        if (!alive ITW_FORT_CONST_VEH || {!CONSCIOUS(player)}) then {_action = FORT_DONE};
        if !(isNil "_action") then {  
            // I got stuck in this handler once so add this for debug
            if (!_handled) then {ITW_FORT_HANG2 = ["ITW_FORT EachFrame",_action,ITW_FORT_PLACE_INFO]}; 
            switch (_action) do {
                case FORT_NO_ACTION:   { };
                case FORT_DIR_RIGHT:   {ITW_FORT_PREVIEW setDir (getDir ITW_FORT_PREVIEW + 1)};
                case FORT_DIR_LEFT:    {ITW_FORT_PREVIEW setDir (getDir ITW_FORT_PREVIEW - 1)};
                case FORT_DIR_RIGHT_10:{ITW_FORT_PREVIEW setDir (getDir ITW_FORT_PREVIEW + 10)};
                case FORT_DIR_LEFT_10: {ITW_FORT_PREVIEW setDir (getDir ITW_FORT_PREVIEW - 10)};
                case FORT_PLACE:       {ITW_FORT_DONE = true; ITW_FORT_ALL_OBS pushBack ITW_FORT_PREVIEW};
                case FORT_DONE: {
                    hideObject ITW_FORT_PREVIEW;
                    deleteVehicle ITW_FORT_PREVIEW;
                    ITW_FORT_DONE = true;
                };
                case FORT_NEW_TYPE: {
                    private _type = ITW_FORT_PLACE_INFO deleteAt 0;
                    private _name = ITW_FORT_PLACE_INFO deleteAt 0;
                    if (isNil "_type" || {typeName _type != "STRING"}) exitWith {diag_log "Error Pos: ITW_FORT_UserPlaceObject: attempt to preview without supplying type";};
                    if !(_type isEqualType "") exitWith {};
                    if (isNil "_name" || {typeName _name != "STRING"}) exitWith {diag_log "Error Pos: ITW_FORT_UserPlaceObject: attempt to preview without supplying type";};
                    if !(_name isEqualType "") then {_name = "structure"};
                    [_type,_name] spawn ITW_FortNext;
                };
            };
        };
        
        if (isNil "ITW_FORT_DONE" || {ITW_FORT_DONE}) exitWith {};
        
        if (isNull ITW_FORT_PREVIEW) exitWith {};
        
        // Get point on /terrain/ the player is looking at
        _ins = lineIntersectsSurfaces [
            eyePos player,
            eyePos player vectorAdd (player weaponDirection primaryWeapon player vectorMultiply 100),
            //AGLToASL positionCameraToWorld [0,0,0],
            //AGLToASL positionCameraToWorld [0,0,1000],
            player,ITW_FORT_PREVIEW,true,1,"NONE","NONE"
        ];
        if (count _ins == 0) exitWith {};
        private _pos = ASLtoAGL ((_ins select 0) select 0);
        if (_pos distance ITW_FORT_LOOK_POS < 0.01) exitWith {};
        if (_pos distance player > 30) exitWith {};
        ITW_FORT_LOOK_POS = _pos;
        ITW_FORT_PREVIEW setPosATL _pos;
        //ITW_FORT_PREVIEW setVectorUp (_chosenIntersection select 1);
    }];

    ITW_FORT_DONE = false;
    waitUntil {isNil "ITW_FORT_DONE" || {ITW_FORT_DONE}};
    private _display = findDisplay 46;
    _display displayRemoveEventHandler ["MouseZChanged",_mzcHandler];
    _display displayRemoveEventHandler ["KeyUp",_kuHandler];
    _display displayRemoveEventHandler ["KeyDown",_kdHandler];
    removeMissionEventHandler ["EachFrame", _efHandler];
    "fort" cutText ["","PLAIN"];
    
    ITW_FORT_DONE       = nil;
    ITW_FORT_PLACE_INFO = nil;
    ITW_FORT_NAME       = nil;
    ITW_FORT_TEXT_TIME  = nil;
    ITW_FORT_CONST_VEH  = nil;
    ITW_FORT_LOOK_POS   = nil;
    ITW_FORT_PREVIEW    = nil;
    ITW_FORT_USER_OBJS  = nil;
};

ITW_FortPlace = {
    params ["_previewObjs"];
    
    private _crates = [];
  
    while {!(_previewObjs isEqualTo [])} do {
        #define BUILD_GROUP_DIST 14
        private _posX = 0;
        private _posY = 0;
        private _previewGroup = [];
        private _obj0 = _previewObjs#0;
        {      
            if (_x distance _obj0 < BUILD_GROUP_DIST) then {
                private _obj = _previewObjs deleteAt _forEachIndex;
                private _pos = getPosATL _obj;
                _posX = _posX + (_pos#0);
                _posY = _posY + (_pos#1);
                _previewGroup pushBack [getPosATL _obj, getDir _obj, typeOf _obj];
               deleteVehicle _obj;
           };
        } forEachReversed _previewObjs;
    
        private _cnt = count _previewGroup;
        private _pos = [_posX/_cnt,_posY/_cnt,0];
        
        private _materials = "Land_WoodenCrate_01_stack_x3_F" createVehicle _pos;
        _materials setDir random 360;
        _materials setPosATL _pos; 
        _crates pushBack [_materials,_previewGroup];
    };
    
    while {!(_crates isEqualTo [])} do {    
        private _hintTime = 0;
        private _timeout = time + 30;
        waitUntil {
            if (time > _hintTime) then {_hintTime = time + 9.5;"fort" cutText [localize "STR_ITW_FORT_ApproachCrates","PLAIN"]};
            sleep 0.5;
            (time > _timeOut) || ({player distance (_x#0) < 3} count _crates > 0) || (!CONSCIOUS(player))
        };
        
        if (time > _timeOut || (!CONSCIOUS(player))) exitWith {
            { 
                deleteVehicle (_x#0);
            } forEach _crates;
            "fort" cutText [localize "STR_ITW_FORT_ConstructionCanceled","PLAIN",0.4];
        };
        
        "fort" cutText ["","PLAIN"];
        
        private _dist = 1e10;
        private _bIndex = -1;
        {
            private _d = player distance (_x#0);
            if (_d < _dist) then {_dist = _d; _bIndex = _forEachIndex};
        } forEach _crates;
        private _build = _crates deleteAt _bIndex;
        _build params ["_materials","_previewGroup"];
        
        if (CONSCIOUS(player)) then {
            player playMoveNow "AinvPknlMstpSnonWnonDr_medic5";
            sleep 2;
            playSound3D ["a3\sounds_f\sfx\ui\vehicles\vehicle_repair.wss", _materials];
            sleep 4;
            if (CONSCIOUS(player)) then {
                playSound3D ["a3\sounds_f\sfx\ui\vehicles\vehicle_repair.wss", _materials];
                sleep 4;
                if (CONSCIOUS(player)) then {
                    player playMoveNow "AinvPknlMstpSnonWnonDnon";
                };
            };
        };
        deleteVehicle _materials;
        waitUntil {isNull _materials};
        
        if (CONSCIOUS(player)) then {
            private _objs = [];
            {
                _x params ["_pos","_dir","_type"];
                private _fort = _type createVehicle _pos;
                _fort setDir _dir;
                _fort setPosATL _pos;
                _objs pushBack _fort;
            } forEach _previewGroup;
            [_objs,true] call ITW_FortAddRemoveMP;
        };
    };
};

ITW_FortNext = {
    params ["_type","_name"];
    hideObject ITW_FORT_PREVIEW;
    deleteVehicle ITW_FORT_PREVIEW;
    ITW_FORT_PREVIEW = createSimpleObject [_type, [0,0,1000], true];
    ITW_FORT_PREVIEW allowDamage false;
    ITW_FORT_NAME = _name;
    ITW_FORT_TEXT_TIME = 0;
};

ITW_FortAddRemoveMP = {
    // runs on server to add/remove objects from fortification list
    params ["_objectArray","_add"];
    if (!isServer) exitWith {_this remoteExec ["ITW_FortAddRemoveMP",2]};
    if (typeName _objectArray != "ARRAY") then {_objectArray = [_objectArray]};
    
    if (_add) then {
        ITW_fortificationObjects append _objectArray;
    } else {
        ITW_fortificationObjects = ITW_fortificationObjects - _objectArray;
        ITW_fortificationFastTravelBoards = ITW_fortificationFastTravelBoards - _objectArray;
        {deleteVehicle _x} forEach _objectArray;
    };
    publicVariable "ITW_fortificationObjects";
};

ITW_FortificationsAdd = {
    params ["_constructionVeh"];
    private _validObjs = ((8 allObjects 0) select {_x distance _constructionVeh < 150}) - ITW_fortificationObjects; 
    private _hintTime = 0;
    private _target = player;
    private _validTarget = false;
    private _name = "";
    private _done = false;
    private _count = 0;
    private _kdHandler = findDisplay 46 displayAddEventHandler ["KeyDown", {
        private _key = _this#1;
        private _handled = false;
        if (_key in [DIK_SPACE,DIK_BACK,DIK_ESC]) then {
            ITW_FORT_KEY = _key;
            _handled = true;
        };
        _handled
    }];
    waitUntil {
        if !(_target isEqualTo cursorTarget) then {
            _target = cursorTarget;
            if (cursorTarget in _validObjs) then {
                _name = getText (configFile >> "cfgVehicles" >> typeOf _target >> "displayName");
                _validTarget = true;
                _hintTime = 0;
            } else {
                _name = "Aim at non-mission object to add";
                if (_validTarget) then {_hintTime = 0};
                _validTarget = false;
            };
        };
        if (time > _hintTime) then {
            _hintTime = time + 9.5;
            "fort" cutText ["<t size='1.5'><br/><br/><br/>"+_name+"<br/><br/>" + localize "STR_ITW_FORT_AddPressSpaceOrBack" + "</t>","PLAIN",1,true,true];
        };
        sleep 0.5;
        if (!isNil "ITW_FORT_KEY") then {
            switch (ITW_FORT_KEY) do {
                case DIK_SPACE: {
                    if (_validTarget) then {
                        [_target,true] call ITW_FortAddRemoveMP;
                        hint (_name + localize "STR_ITW_FORT_Added");
                        _validObjs = _validObjs - [_target];
                        _target = objNull;
                        _count = _count + 1;
                    } else {
                        hint localize "STR_ITW_FORT_NotAimNonMissionObj";
                    };
                };
                case DIK_ESC;
                case DIK_BACK:  {_done = true};
            };
            ITW_FORT_KEY = nil;
        };
        player distance _constructionVeh > 100 || _done
    };
    
    findDisplay 46 displayRemoveEventHandler ["KeyDown",_kdHandler];
    "fort" cutText ["","PLAIN"];
    if (player distance _constructionVeh > 100) then {
        playSoundUI ["a3\sounds_f_exp\sfx\debug\sine880hz-10db.wss",1,1,false,1.5];
        hint (localize "STR_ITW_FORT_TooFarFromVeh" + "  " + str _count + localize "STR_ITW_FORT_ObjsAdded");
    } else {
        hint (str _count + localize "STR_ITW_FORT_ObjsAdded");
    };
};

ITW_FortificationsRemove = {
    params ["_constructionVeh","_all"];
    
    private _validObjs = ITW_fortificationObjects select {_x distance _constructionVeh < 100};
    _validObjs append (ITW_fortificationFastTravelBoards select {_x distance _constructionVeh < 100});
    
    if (_all) then {
        [_validObjs,false] call ITW_FortAddRemoveMP;
        hint (str (count _validObjs) + localize "STR_ITW_FORT_ObjsRemoved");
    } else {
        private _hintTime = 0;
        private _target = player;
        private _validTarget = false;
        private _name = "";
        private _done = false;
        private _count = 0;
        private _kdHandler = findDisplay 46 displayAddEventHandler ["KeyDown", {
            private _key = _this#1;
            private _handled = false;
            if (_key in [DIK_SPACE,DIK_BACK,DIK_ESC]) then {
                ITW_FORT_KEY = _key;
                _handled = true;
            };
            _handled
        }];
        waitUntil {
            if !(_target isEqualTo cursorTarget) then {
                _target = cursorTarget;
                if (cursorTarget in _validObjs) then {
                    _name = getText (configFile >> "cfgVehicles" >> typeOf _target >> "displayName");
                    _validTarget = true;
                    _hintTime = 0;
                } else {
                    _name = "Aim at saved object to delete";
                    if (_validTarget) then {_hintTime = 0};
                    _validTarget = false;
                };
            };
            if (time > _hintTime) then {
                _hintTime = time + 9.5;
                "fort" cutText ["<t size='1.5'><br/><br/><br/>"+_name+"<br/><br/>" + localize "STR_ITW_FORT_DeletePressSpaceOrBack" + "</t>","PLAIN",1,true,true];
            };
            sleep 0.5;
            if (!isNil "ITW_FORT_KEY") then {
                switch (ITW_FORT_KEY) do {
                    case DIK_SPACE: {
                        if (_validTarget) then {
                            [_target,false] call ITW_FortAddRemoveMP;
                            _validObjs = _validObjs - [_target];
                            _target = objNull;
                            _count = _count + 1;
                        } else {
                            hint localize "STR_ITW_FORT_NotAimNonMissionObj";
                        };
                    };
                    case DIK_ESC;
                    case DIK_BACK:  {_done = true};
                };
                ITW_FORT_KEY = nil;
            };
            player distance _constructionVeh > 100 || _done
        };
        
        findDisplay 46 displayRemoveEventHandler ["KeyDown",_kdHandler];
        "fort" cutText ["","PLAIN"];
        if (player distance _constructionVeh > 100) then {
            playSoundUI ["a3\sounds_f_exp\sfx\debug\sine880hz-10db.wss",1,1,false,1.5];
            hint (localize "STR_ITW_FORT_TooFarFromVeh" + "  " + str _count + localize "STR_ITW_FORT_ObjsRemoved");
        } else {
            hint (str _count + " " + localize "STR_ITW_FORT_ObjsRemoved");
        };
    };
};

ITW_FortificationSpawnVeh = {
    params ["_pos"];
    private _pos = +_pos;
    private _end = ATLToASL _pos;
    private _beg = +_end;
    _beg set [2,_beg#2 + 40];
    // _ix will be an array of [intersectPosASL, surfaceNormal, intersectObj, parentObject] or empty array
    private _ix = lineIntersectsSurfaces [_beg,_end,objNull,objNull,true,1,"VIEW","NONE"];
    if !(_ix isEqualTo []) then {_pos = _ix#0};
    _pos set [2,(_pos#2) + 2];
    if (isNil "CONSTRUCTION_VEHICLES") then {
        private _velSelection = [] call ITW_BaseVehicleSelector;
        _velSelection params ["_largeHelis","_smallHelis","_cars","_transportTrucks","_tanks","_apcs","_repairTrucks","_ammoTrucks","_fuelTrucks"];
        CONSTRUCTION_VEHICLES = _repairTrucks;
    };
    private _vehType = selectRandom CONSTRUCTION_VEHICLES;
    private _texture = "";
    private _anim = "";
    if (typeName _vehType == "ARRAY") then {
        _texture = _vehType#1;
        _anim    = _vehType#2;
        _vehType    = _vehType#0;
    };
    private _veh = createVehicle [_vehType,_pos,[],0,"CAN_COLLIDE"];
    _veh allowDamage false;
    _veh setPosATL _pos;
    _veh setVectorUp [0,0,1];
    [_veh,_texture,_anim] call BIS_fnc_initVehicle;
    [_veh] remoteExec ["ITW_FortSpawnVehMP",0,_veh];
    sleep 4;
    _veh allowdamage true;
};

ITW_FortSpawnVehMP = {
    // called on all clients
    if (!hasInterface) exitWith {};
    ITW_fortSem = false;
    
    params ["_veh"];
    _veh addAction ["<t color='#8888ff'>" + localize "STR_ITW_FORT_Construct" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_arguments"];
            ITW_fortSem = true;
            _veh call ITW_FortificationsPlace;
            ITW_fortSem = false;
        },nil,10,false,true,"","ITW_fortSem == false",6]; 
        
    _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_FORT_FastTravel" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_arguments"];
            ITW_fortSem = true;
            _veh call ITW_FortFastTravel;
            ITW_fortSem = false;
        },nil,10,false,true,"","ITW_fortSem == false",6]; 
        
    _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_FORT_Remove" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_arguments"];
            ITW_fortSem = true;
            [_veh,false] call ITW_FortificationsRemove;
            ITW_fortSem = false;
        },nil,10,false,true,"","ITW_fortSem == false",6]; 
    _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_FORT_RemoveAll" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_arguments"];
            ITW_fortSem = true;
            [_veh,true] call ITW_FortificationsRemove;
            ITW_fortSem = false;
        },nil,10,false,true,"","ITW_fortSem == false",6]; 
    _veh setVariable ["itw_icon","loc_truck"];
        
    _veh addAction ["<t color='#aaaadd'>" + localize "STR_ITW_FORT_Add" + "</t>", {
            params ["_veh", "_caller", "_actionId", "_arguments"];
            ITW_fortSem = true;
            [_veh] call ITW_FortificationsAdd;
            ITW_fortSem = false;
        },nil,10,false,true,"","ITW_fortSem == false",6]; 
        
    _veh call ITW_FortVehMapIcon;
};

ITW_FortVehMapIcon = {
    params ["_veh"];
    private _mrkr = "itw_fvm_"+str(time);
    _veh setVariable ["itw_fortVehMrk",_mrkr];
    
    _mrkr = createMarkerLocal [_mrkr, getPosATL _veh];
    _mrkr setMarkerColorLocal "ColorBLUFOR";
    _mrkr setMarkerTypeLocal "loc_truck";
    _mrkr setMarkerSizeLocal [1,1];
    _mrkr setMarkerAlphaLocal 1;

    _veh addEventHandler ["GetIn", {
        _this call ITW_FortVehMapHandler;
    }];
    _veh addEventHandler ["GetOut", { 
        _this call ITW_FortVehMapHandler;
    }];
    _veh addEventHandler ["HandleDamage", {
        _this call ITW_FortVehMapHandler;
    }];
    _veh addEventHandler ["Deleted", {
        deleteMarkerLocal ((_this#0) getVariable ["itw_fortVehMrk",""]);
    }];
};

ITW_FortVehMapHandler = {
    params ["_veh"];
    if (!alive _veh) then {
        deleteMarkerLocal (_veh getVariable ["itw_fortVehMrk",""]);
        _veh removeAllEventHandlers "GetIn";
        _veh removeAllEventHandlers "GetOut";
        _veh removeAllEventHandlers "HandleDamage";
    };
    private _driver = driver _veh;
    if (isNull _driver || {!alive _driver}) then {
        private _mrkr = _veh getVariable ["itw_fortVehMrk",""];
        _mrkr setMarkerPosLocal getPos _veh;
        _mrkr setMarkerAlphaLocal 1;
    } else {
        _veh getVariable ["itw_fortVehMrk",""] setMarkerAlphaLocal 0;
    };
};

ITW_FortificationsGetWeightedStructures = {
    // ensure ITW_FORTIFICATION_BUILDINGS_WEIGHTED is populated
    if (isNil "ITW_FORTIFICATION_BUILDINGS_WEIGHTED") then {
        // use building on the map to generate fortifications
        private _fortInfo = [];
        {
            private _bld = _x;
            if (_bld buildingPos 0 isEqualTo []) then {continue};
            private _cfgName = typeOf _bld;
            if (_cfgName in _fortInfo) then {continue};
            private _cfg = configFile >> "cfgVehicles" >> _cfgName;
            private _type = getText (_cfg >> "vehicleClass");
            if (typeName _type == "") then {
                private _types = getArray (_cfg >> "vehicleClass");
                {_type = _type + _x} forEach _types;
            };
            _type = toLowerANSI _type;           
            if ("fortification" in _type || {"military" in _type}) then {
                _fortInfo pushBack _cfgName;
            };
        } forEach (nearestObjects [[worldSize,worldSize,0], ["building"], worldSize]);
        ITW_FORTIFICATION_BUILDINGS_WEIGHTED = [];
        {
            ITW_FORTIFICATION_BUILDINGS_WEIGHTED pushBack _x;
            ITW_FORTIFICATION_BUILDINGS_WEIGHTED pushBack 1;
        } forEach _fortInfo;
        
        private _addOns = ["Land_BagBunker_Large_F",1,"Land_BagBunker_Small_F",2,"Land_BagBunker_Tower_F",1];
        switch (toLowerANSI worldName) do {
            case "tanoa";
            case "stozec";
            case "enoch";
            case "vn_khe_sanh";
            case "vn_the_bra";
            case "cam_lao_nam": {
                if (isClass (configFile >> "CfgVehicles" >> "Land_BagBunker_01_large_green_F")) then {
                    _addOns = ["Land_BagBunker_01_large_green_F",1,"Land_BagBunker_01_small_green_F",2,"Land_HBarrier_01_tower_green_F",1]
                };
            };
        };
        ITW_FORTIFICATION_BUILDINGS_WEIGHTED append _addOns;
    };
    ITW_FORTIFICATION_BUILDINGS_WEIGHTED
};

ITW_FortFastTravel = {
    // called on client who asked to place FT point
    params ["_constructionVeh"];
    #define ITW_FORT_FT_BOARD  "Land_Noticeboard_F"
    private _cancel = false;
    private _nearestObj = [getPosATL player] call ITW_ObjGetNearest;
    if (!(_nearestObj isEqualTo []) && {player distance (_nearestObj#ITW_OBJ_POS) < (_nearestObj#ITW_OBJ_SIZE + 100)}) exitWith {
        // we only allow the same number of FT points as objectives per zone
        "fort" cutText ["<t size='1.5'><br/><br/><br/>" + localize "STR_ITW_FORT_FtTooClose" + "</t>","PLAIN",1,true,true];
        sleep 10;
        "fort" cutText ["","PLAIN"];
    };
    
    if (count ITW_fortificationFastTravelBoards >= ITW_ParamObjectivesPerZone) then {
        // we only allow the same number of FT points as objectives per zone
        "fort" cutText ["<t size='1.5'><br/><br/><br/>" + localize "STR_ITW_FORT_MaxFtReached" + "</t>","PLAIN",1,true,true];
        ITW_FORT_MENU = [[localize "STR_ITW_FORT_DeleteFtPoint", false]];
        {
            private _name = _x getVariable ["ItwFortFtName","?????"];
            ITW_FORT_MENU pushBack [_name, [2+_forEachIndex], "", -5, [["expression", format ["ITW_FORT_FtDel = %1",_forEachIndex]]], "1", "1"],
        } forEach ITW_fortificationFastTravelBoards;
        ITW_FORT_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"];
        ITW_FORT_FtDel = -1;
        showCommandingMenu "#USER:ITW_FORT_MENU";
        waitUntil {commandingMenu == ""};
        ITW_FORT_MENU = nil;
        if (ITW_FORT_FtDel >= 0) then {
            deleteVehicle (ITW_fortificationFastTravelBoards#ITW_FORT_FtDel);
        } else {
            _cancel = true;
        };
        ITW_FORT_FtDel = nil;
        "fort" cutText ["","PLAIN"];
    };
    if (_cancel) exitWith {};
    
    ITW_FORT_ALL_OBS = [];
    [[["cat","subcat",localize "STR_ITW_FORT_FastTravel",ITW_FORT_FT_BOARD]],0,_constructionVeh] call ITW_FORT_UserPlaceObject;
    if !(ITW_FORT_ALL_OBS isEqualTo []) then {
        private _board = ITW_FORT_ALL_OBS#0;
        private _pos = getPosATL _board;
        private _dir = getDir _board;
        [[[_pos,_dir]]] remoteExec ["ITW_FortFtPlaceServer",2];
        deleteVehicle _board;
    };
    ITW_FORT_ALL_OBS = nil;
};

ITW_FortFtPlaceServer = {
    // call on server
    // _ftInfos is array of [_pos,_dir,[_name.""]], _name should be "" or omitted if this is a new ft point, or the name on mission load
    params ["_ftInfos",["_nameIndex",-1]];
    {
        _x params ["_pos","_dir",["_name",""]];
        _board = ITW_FORT_FT_BOARD createVehicle _pos;
        _board setDir _dir;
        _board setPosATL _pos;
        _board allowDamage false;
        [_board] remoteExec ["ITW_FortFastTravelMP",0];
        
        if (isNil "ITW_FORT_NAMES" || {ITW_FORT_NAMES isEqualTo []}) then {
            private _names = ["Alpha","Bravo","Charlie","Delta","Echo","Foxtrot","Golf","Hotel","India","Juliet","Kilo","Lima","Mike","November","Oscar","Papa","Quebec","Romeo","Sierra","Tango","Uniform","Victor","Whiskey","Xray","Yankee","Zulu"];
            if (_nameIndex > 0) then {
                while {count _names > _nameIndex} do {_names deleteAt 0};
            };
            ITW_FORT_NAMES = _names;
        };
        if (_name isEqualTo "") then {
            _name = ITW_FORT_NAMES#0;
            ITW_FORT_NAMES deleteAt 0;
        };
        private _mrkrName = format ["mFort%1",_name];
        private _ftMrk = createMarkerLocal [_mrkrName, _pos];
        _ftMrk setMarkerColorLocal "ColorWEST";
        _ftMrk setMarkerSizeLocal [1,1];
        _ftMrk setMarkerTextLocal ("FOB " + _name);
        _ftMrk setMarkerType "loc_Bunker";
        
        _board setVariable ["ItwFortFtName",_name,true];
        _board addEventHandler ["Deleted", {
            params ["_board"];
            ITW_fortificationFastTravelBoards = ITW_fortificationFastTravelBoards - [_board];
            publicVariable "ITW_fortificationFastTravelBoards";
            deleteMarker format ["mFort%1",_board getVariable ["ItwFortFtName",""]];
        }];
        
        ITW_fortificationFastTravelBoards pushBack _board;
    } forEach _ftInfos;
    publicVariable "ITW_fortificationFastTravelBoards";
};

ITW_FortFastTravelMP = {
    // call on all clients
    params ["_board"];
    if (!hasInterface) exitWith {};
    
    _board addAction [localize "STR_ITW_BASE_FastTravel",{
            params ["_board", "_player", "_actionId", "_arguments"];
            [] spawn ITW_RadioFastTravel;
        },nil,10,false,true,"","true",8];
};

ITW_FortificationGetBases = {
    private _ftBases = ITW_fortificationFastTravelBoards apply {
        private _dir = getDir _x;
        private _pos = getPosATL _x getPos [3,_dir+180];
        [_pos,_dir+90,_pos,_pos]
    };
    _ftBases
};

ITW_FortSaveZeusEntity = {
    params ["_entity"];
    ITW_fortificationObjects pushBackUnique _entity;
};

ITW_FortificationsSave = {
    ITW_fortificationObjects = ITW_fortificationObjects - [objNull];
    private _objData = ITW_fortificationObjects apply {[typeOf _x,getPosATL _x,getDir _x]};
    private _ftPts = ITW_fortificationFastTravelBoards apply {[getPosATL _x,getDir _x,_x getVariable ["ItwFortFtName",""]]};
    private _ftNamesCnt = if (isNil "ITW_FORT_NAMES") then {-1} else {count ITW_FORT_NAMES};
    private _saveData = [_objData,[_ftPts,_ftNamesCnt]];
    _saveData
};

ITW_FortificationsLoad = {
    params ["_fortifications"];
    _fortifications params ["_objData","_ftData"];
    
    // backwards comaptibility
    if (count _fortifications != 2 || {count (_fortifications#1) != 2}) then {
        _ftData = [[],-1];
        _objData = _fortifications;
    };
    
    ITW_fortificationObjects = [];
    ITW_fortificationFastTravelBoards = [];
    _objs = [];
    {
        _x params ["_type","_pos","_dir"];
        private _fort = _type createVehicle _pos;
        _fort setDir _dir;
        _fort setPosATL _pos;
        _objs pushBack _fort;
    } forEach _objData;
    [_objs,true] call ITW_FortAddRemoveMP;
    
    _ftData call ITW_FortFtPlaceServer;
};


["ITW_FortificationsInit"] call SKL_fnc_CompileFinal;
["ITW_FortificationsPlace"] call SKL_fnc_CompileFinal;
["ITW_FortificationsAdd"] call SKL_fnc_CompileFinal;
["ITW_FortificationsRemove"] call SKL_fnc_CompileFinal;
["ITW_FortificationSpawnVeh"] call SKL_fnc_CompileFinal;
["ITW_FortSpawnVehMP"] call SKL_fnc_CompileFinal;
["ITW_FortificationsGetWeightedStructures"] call SKL_fnc_CompileFinal;
["ITW_FortificationsSave"] call SKL_fnc_CompileFinal;
["ITW_FortificationsLoad"] call SKL_fnc_CompileFinal;
["ITW_FortVehMapIcon"] call SKL_fnc_CompileFinal;
["ITW_FortVehMapHandler"] call SKL_fnc_CompileFinal;
["ITW_FortPlace"] call SKL_fnc_CompileFinal;
["ITW_FortNext"] call SKL_fnc_CompileFinal;
["ITW_FortAddRemoveMP"] call SKL_fnc_CompileFinal;
["ITW_FORT_UserPlaceObject"] call SKL_fnc_CompileFinal;
["ITW_FortFastTravel"] call SKL_fnc_CompileFinal;
["ITW_FortFtPlaceServer"] call SKL_fnc_CompileFinal;
["ITW_FortFastTravelMP"] call SKL_fnc_CompileFinal;
["ITW_FortificationGetBases"] call SKL_fnc_CompileFinal;
["ITW_FortSaveZeusEntity"] call SKL_fnc_CompileFinal;