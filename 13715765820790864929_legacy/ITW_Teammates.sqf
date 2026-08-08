
#define MedicActions ["AinvPknlMstpSnonWnonDnon_medic_1","AinvPknlMstpSnonWnonDnon_medic0","AinvPknlMstpSnonWnonDnon_medic1","AinvPknlMstpSnonWnonDnon_medic2"]
#define MedicActionsProne ["AinvPpneMstpSlayWrflDnon_medicOther"]
#define HitCries ["A3\Sounds_F\characters\human-sfx\Person0\P0_hit_01.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_13.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_12.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_11.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_10.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_09.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_08.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_07.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_06.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_05.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_04.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_03.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_02.wss", "A3\Sounds_F\characters\human-sfx\Person3\P3_hit_01.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_09.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_08.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_07.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_06.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_05.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_04.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_03.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_02.wss", "A3\Sounds_F\characters\human-sfx\Person2\P2_hit_01.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_11.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_10.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_09.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_08.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_07.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_06.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_05.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_04.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_03.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_02.wss", "A3\Sounds_F\characters\human-sfx\Person1\P1_hit_01.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_13.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_12.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_11.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_10.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_09.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_08.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_07.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_06.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_05.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_04.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_03.wss", "A3\Sounds_F\characters\human-sfx\Person0\P0_hit_02.wss"] 

#if __has_include("\z\ace\addons\main\script_component.hpp")
#define ALIVE(unit) (lifeState unit in ["HEALTHY","INJURED"])
#define CONSCIOUS(unit) (!(unit getVariable ["ACE_isUnconscious", false]))
#define UNCONSCIOUS(unit) ((unit getVariable ["ACE_isUnconscious", false]))
#else
#define ALIVE(unit) (alive unit)
#define CONSCIOUS(unit) (lifeState unit in ["HEALTHY","INJURED"])
#define UNCONSCIOUS(unit) (lifeState unit isEqualTo "INCAPACITATED")
#endif
ITW_TM_Debug = false;

if (isNil "LV_PAUSE") then {LV_PAUSE = false};

ITW_TeammatesInit = {
    // call on all clients
    if (isServer) then { 
        ITW_AI_UNITS = [];
        [] spawn ITW_TeammateRevive;
    };
};

ITW_TeammateCreated = {
    // called on each teammate after they are created (called on all clients) Can be called with unit or group
    params ["_unit"];
    if (typeName _unit == "GROUP") exitWith { {_x call ITW_TeammateCreated} forEach units _unit };
    if (isPlayer _unit) exitWith {};
    while {isNil "ITW_ParamFriendlyRevive"} do {sleep 0.5}; // this function can get called on jip before init is complete
    
    if (_unit getVariable ["tmReloadedEH",-1] >= 0) exitWith {};

    private _eh = -1;
    if (isServer) then { 
        ITW_AI_UNITS pushBack _unit;
        // add unit to zeus
        { _x addCuratorEditableObjects [[_unit],true] } forEach allCurators;
        
        if (group _unit getVariable ["tmCommandChangedEH",-1] < 0) then {
            _eh = group _unit addEventHandler ["CommandChanged", {
                params ["_group", "_newCommand"];
                if (_newCommand == "JOIN") then {
                    {
                        if (!isPlayer _x && {!(isNull (_x getVariable ["tmFollowing",objNull])) && {formLeader _x == _x}}) then {
                            _x setVariable ["tmFollowing",nil,true];
                        };
                    } forEach units _group;
                };
            }];
            group _unit setVariable ["tmCommandChangedEH",_eh];
        };
    };
    
    // ensure unit never runs out of ammo or FAK
    _eh = _unit addEventHandler ["Reloaded", {
        params ["_unit", "_weapon", "_muzzle", "_newMagazine", "_oldMagazine"];
        private _mag = _newMagazine#0;
        if !(_mag in (magazines _unit)) then {_unit addMagazines [_mag,1]};
        
        // make sure they have at least 1 FAK
        private _items = items _unit;
        private _found = false;
        #if __has_include("\z\ace\addons\main\script_component.hpp")
            private _aceCnt = 0;
            { 
                private _type = getnumber (configfile >> "cfgweapons" >> _x >> "itemInfo" >> "type");
                if (_type == 401) exitWith {_found = true};
                if (_type == 302) then {_aceCnt = _aceCnt + 1};
                if (_aceCnt > 3) exitWith {_found = true};
            } forEach _items;
            if (!_found) then {
                _unit addItem "ACE_fieldDressing";
                _unit addItem "ACE_plasmaIV";
            };
        #else
            private _item = "FirstAidKit";
            if (isClass (configFile >> "CfgPatches" >> "pir")) then {_item = "PiR_bint"};
            { 
                if (getnumber (configfile >> "cfgweapons" >> _x >> "itemInfo" >> "type") == 401) exitWith {_found = true};
            } forEach _items;
            if (!_found) then {
                _unit addItem _item;
            };
        #endif
    }];
    _unit setVariable ["tmReloadedEH",_eh];
    
    if (local _unit) then {
        _unit doFollow leader _unit;
        _unit allowFleeing 0;
        _unit setSkill (ITW_ParamFriendlySquadSkill);
        _unit setSkill ["courage",1];
    };

    _unit setVariable ["ITW_loadout",getUnitLoadout _unit,true];    

    #if __has_include("\z\ace\addons\main\script_component.hpp")
        #include "\z\ace\addons\main\script_macros.hpp"
        if (ITW_ParamFriendlyRevive == 1) then {
            _unit setUnitTrait ["Medic",true];
            _unit setVariable [QEGVAR(medical,medicClass), 1, true];
            (uniformContainer _unit) addItemCargoGlobal ["ACE_fieldDressing",1];
            (uniformContainer _unit) addItemCargoGlobal ["ACE_plasmaIV",1];
        } else {
            if (_unit getUnitTrait "Medic") then {
                _unit setVariable [QEGVAR(medical,medicClass), 1, true];
                (uniformContainer _unit) addItemCargoGlobal ["ACE_fieldDressing",1];
                (uniformContainer _unit) addItemCargoGlobal ["ACE_plasmaIV",1];
            };
        };
    #else
        if (ITW_ParamFriendlyRevive == 1) then {
            // setup to allow AI to go unconscious
            _eh = _unit addEventHandler ["HandleDamage", {
                // damage handler only activates on client where ai is local
                params ["_unit", "_selection", "_damage", "_source", "_projectile", "_hitIndex", "_instigator", "_hitPoint"];
                private _returnDmg = _damage;
                if (!alive _unit) exitWith {_unit removeEventHandler [_thisEvent, _thisEventHandler]; damage _unit};
                //if (lifeState _unit == "INCAPACITATED") exitWith {damage _unit}; 
                
                if !(_unit getVariable ["tmAICanDie",false]) then {
                    private _veh = vehicle _unit;
                    if (alive _veh && {_damage > 0.8 && {_damage < 8}}) then {
                        // go unconscious
                        _damage = 0.85;
                        _unit spawn {_this setVariable ["ITW_TmOrders",[_this] call ITW_TeammateGetOrders]}; // spawn since it can wait if needed
                        if (lifeState _unit != "INCAPACITATED") then {
                            if (random 100 < ITW_ParamTeammateDeathChance) then {
                                _unit setDamage 1;
                            } else {              
                                _unit setUnconscious true;
                                _unit setCaptive true;
                                [_unit] remoteExec ["ITW_TeammateDown",0];
                            };
                        };
                    };    
                };
                _damage
            }]; 
            _unit setVariable ["tmHandleDamageEH",_eh];
        };
    #endif
    
    if (isNil "ITW_TMLoadoutMenu_1") then {
        private _header = [[localize "STR_ITW_BASE_SelectLoadout", false]];
        private _index = 0;
        private _maxItems = 10;
        private _cnt = _maxItems+2;
        private _menu = +_header;
        waitUntil {!isNil "ITW_AllyUnitTypes"};
        {
            private _unitType = _x;
            private _name = getText (configFile >> "CfgVehicles" >> _unitType >> "displayName");
            if (_cnt > _maxItems) then {
                if (_index > 0) then {
                    if (_index > 1) then {_menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"]};
                    _menu pushBack [localize "STR_ITW_COMMON_More",[31], format ["#USER:ITW_TMLoadoutMenu_%1",_index+1], -5, [["expression",""]], "1", "1"];
                    call compile format ["ITW_TMLoadoutMenu_%1 = _menu;",_index];
                };
                _menu = +_header;
                _cnt = 0;
                _index = _index + 1;
            } else {
                _cnt = _cnt + 1;
            };          
            _menu pushBack [_name,[_cnt+2], "", -5, [["expression",format ["['%1','%2'] spawn ITW_TeammateLoadout;",_x,_name]]], "1", "1"];
        } forEach ITW_AllyUnitTypes;
        _menu pushBack [localize "STR_ITW_COMMON_Back",[17], "", -4, [["expression",""]], "1", "1"];
        call compile format ["ITW_TMLoadoutMenu_%1 = _menu;",_index];
    };
    private _actions = [];
    private _aa = _unit addAction [localize "STR_ITW_BASE_SelectLoadout",{ITW_TeammateLoadoutUnit = _this#0; showCommandingMenu "#USER:ITW_TMLoadoutMenu_1"},nil,1.5,false,false,"","group _this == group _target"]; 
    _actions pushBack _aa;
    _aa = _unit addAction [localize "STR_ITW_TM_FollowMe",{
            params ["_target", "_caller", "_actionId", "_arguments"];
            [_target,_caller] remoteExec ["ITW_TeammateFollow",_target];
        },nil,1.4,false,true,"",
        "group _this == group _target && _target != leader _target && {isNull (_target getVariable ['tmFollowing',objNull])}"];
    _actions pushBack _aa;
    _aa = _unit addAction [localize "STR_ITW_TM_ContinueFollowMe",{
            params ["_target", "_caller", "_actionId", "_arguments"];
            _target spawn ITW_TeammateUnStop
        },nil,1.4,false,true,"",
        "_this isEqualto (_target getVariable ['tmFollowing',objNull]) && {currentCommand _target == 'STOP'}"];
    _actions pushBack _aa;
    _aa = _unit addAction [localize "STR_ITW_TM_StopFollowingMe",{
            params ["_target", "_caller", "_actionId", "_arguments"];
            _target setVariable ["tmFollowing",objNull,true];
        },nil,1.4,false,true,"",
        "_this isEqualto (_target getVariable ['tmFollowing',objNull])"];
    _actions pushBack _aa;
    _aa = _unit addAction [localize "STR_ITW_TM_ResetUnit",{
            params ["_unit", "_player"];
            if (_unit == _player) then {_player = player}; // if called from command bar, player is caller but unit is both params
            [_unit,_player] remoteExec ["ITW_TeammateReset",_unit];
        },nil,1.4,false,true,"",
        "group _this == group _target"];
    _actions pushBack _aa;
    _unit setVariable ["tmActions",_actions];
};

ITW_TeammatesRemove = {
    // call on all clients
    params ["_group"];
    if (isServer) then { 
        ITW_AI_UNITS = ITW_AI_UNITS - (units _group);
    };
    {
        private _unit = _x;
        {_unit removeAction _x} forEach (_unit getVariable ["tmActions",[]]);
        _unit removeEventHandler ["HandleDamage",_unit getVariable ["tmHandleDamageEH",-1]];
        _unit removeEventHandler ["Reloaded",_unit getVariable ["tmReloadedEH",-1]];
        _unit setVariable ["tmActions",nil];
        _unit setVariable ["tmHandleDamageEH",nil];
        _unit setVariable ["tmReloadedEH",nil];
    } forEach units _group;
    _group removeEventHandler ["CommandChanged",_group getVariable ["tmCommandChangedEH",-1]];
    _group setVariable ["tmCommandChangedEH",nil];
};

ITW_TeammateUnStop = {
    params ["_unit"];
    if (currentCommand  _unit == "STOP") then {
        private _grp = group _unit;
        private _grp2 = createGroup west; 
        [_unit] joinSilent _grp2;
        waitUntil {currentCommand  _unit != "STOP"};
        [_unit] joinSilent _grp;
        deleteGroup _grp2;
    };
};

ITW_TeammateFollow = {
    // spawn where ai unit is local
    
    // AI will follow unit, get in/out vehicles and copy stance
    // AI has an action to 'stop following' or group lead can issue 'regroup' to the ai
    // Squad leader can also issue 'stop' command to hold still, issue a move command (or use continue action
    // on the ai) to resume following
    
    params ["_unit", "_player",["_keepClose",false]];
    #define FOLLOW_DIST_VERY_CLOSE 5;
    #define FOLLOW_DIST_CLOSE 15
    #define FOLLOW_DIST_FAR   25
    #define STATE_FOLLOW  1
    #define STATE_GET_IN  2
    #define STATE_IN_VEH  3
    #define STATE_GET_OUT 4
    
    private _followDistClose = if (_keepClose) then {FOLLOW_DIST_VERY_CLOSE} else {FOLLOW_DIST_CLOSE};
    private _followDistFar   = if (_keepClose) then {FOLLOW_DIST_CLOSE     } else {FOLLOW_DIST_FAR  };
    _unit setVariable ["tmFollowing",_player,true];
    if (ITW_TM_Debug) then {diag_log format ["TeammateFollow: %1 following %2",name _unit, name _player]};  
    
    private _prevState = STATE_FOLLOW;
    private _state = STATE_FOLLOW;
    private _timeout = 0;
    
    _unit call ITW_TeammateUnStop;
    
    while {alive _unit && {alive _player && {! isNull (_unit getVariable ["tmFollowing",objNull])}}} do {
        private _dist = _unit distance _player;        
        private _veh = vehicle _player;
        
        switch (_state) do {
            case STATE_FOLLOW: {
                if (_dist > 100) then {_unit setPosATL ([_player,80,_player getDir _unit] call ITW_FncRelPos)};
                if (_veh != _player) exitWith {
                    unassignVehicle _unit;
                    _unit assignAsCargo _veh;
                    _unit doMove (_veh getPos [4, _veh getDir _unit]);
                    _timeout = time + 20;
                    _state = STATE_GET_IN;
                };
                switch (stance _player) do {
                    case "STAND":  {_unit setUnitPos "UP"};
                    case "CROUCH": {_unit setUnitPos "MIDDLE"};
                    case "PRONE":  {_unit setUnitPos "DOWN"};
                    default        {_unit setUnitPos "AUTO"};
                };
                if (_dist > _followDistFar) then {
                    private _pos = (_player getPos [_followDistClose,_player getDir _unit]);
                    _unit doMove _pos;
                    if (ITW_TM_Debug) then {diag_log format ["TeammateFollow: %1 moving to %2",name _unit,_pos]};                  
                };
            };
            case STATE_GET_IN: {
                if (_unit distance _veh < 5 || time > _timeout) then {
                    if (getPosATL _veh #2 < 2) then {
                        _unit moveInAny _veh;
                        sleep 1;
                    };
                    if (vehicle _unit == _unit) then {
                        [_unit,localize "STR_ITW_TM_GoOnWithoutMe"] remoteExec ["groupChat",_player];
                    };
                    _state = STATE_IN_VEH;
                };
                
                if (_veh == _player) exitWith {
                    unassignVehicle _unit;
                    doGetOut _unit;
                    _timeout = time + 5;
                    _state = STATE_GET_OUT;
                };
            };
            case STATE_IN_VEH: {
                if (_veh == _player) then {
                    unassignVehicle _unit;
                    doGetOut _unit;
                    _timeout = time + 5;
                    _state = STATE_GET_OUT;
                };
            };
            case STATE_GET_OUT: {
                if (vehicle _unit == _unit || {time > _timeout}) then {
                    if (time > _timeout) then {
                        moveOut _unit;
                    };
                    _unit call ITW_TeammateUnStop;
                    _state = STATE_FOLLOW;
                };
            };
        };  
        if (ITW_TM_Debug && {_prevState != _state}) then {diag_log format ["TeammateFollow: %1 state change %2 => %3",name _unit,_prevState,_state];_prevState = _state};
        
        sleep 3;
    };
    
    if (ITW_TM_Debug) then {diag_log format ["TeammateFollow: %1 done following (%2,%3,%4)",name _unit,alive _unit,alive _player,_unit getVariable ["tmFollowing",objNull]]};
    
    if (alive _unit) then {
        unassignVehicle _unit;
        doGetOut _unit;
        _unit setUnitPos "AUTO";
        _unit doMove getPosATL _unit;
        _unit doFollow leader _unit;
    };
    if (! isNull (_unit getVariable ["tmFollowing",objNull])) then {
        _unit setVariable ["tmFollowing",nil,true];
    };
};

ITW_TeammateLoadout = {
    params ["_unitType","_name"];
    private _unit = ITW_TeammateLoadoutUnit;
    [_unit,_unitType call ITW_FncGetLoadoutFromClass] call ITW_FncSetUnitLoadout;
    _unit call ITW_TeammateAddFAKs;
    if (primaryWeapon _unit isEqualTo "" && {handgunWeapon _unit isEqualTo ""}) then {
        _unit addMagazines ["10Rnd_9x21_Mag",10];
        _unit addWeapon "hgun_Pistol_01_F";
    };
    sleep 0.015; // YIELD_CPU
    _unit setVariable ["ITW_loadout",getUnitLoadout _unit,true];
    hint format [localize "STR_ITW_TM_LoadoutChangedToFMT",_name];
};

ITW_TeammateAddFAKs = {
    private _unit = _this;
    // if unit has no weapon, then change his loadout
    private _FAK = "FirstAidKit";
    private _MediKit = "MediKit";
    if (isClass (configFile >> "CfgPatches" >> "pir")) then { _FAK = "PiR_bint"; _MediKit = "PiR_apteka"};
    {
        private _type = getNumber (configFile >> "cfgWeapons" >> _x >> "iteminfo" >> "type");
        if (_type == 401) exitWith {_FAK = _x};
    } forEach items _unit;
    private _count = 6;
    while {_count > 0 && _unit canAdd _FAK} do {
        _count = _count - 1;
        _unit addItem _FAK;
    };
    private _ammo = primaryWeaponMagazine _unit;
    if !(_ammo isEqualTo []) then {
        _ammo = _ammo#0;
        _count = 6;
        while {_count > 0 && _unit canAdd _ammo} do {
            _count = _count - 1;
            _unit addItem _ammo;
        };
    };
    if (_unit getUnitTrait "Medic") then {
        _unit addItem _MediKit;
    };
    // ACE: add medical items
    #if __has_include("\z\ace\addons\main\script_component.hpp")
        (uniformContainer _unit) addItemCargoGlobal ["ACE_fieldDressing",1];
        (uniformContainer _unit) addItemCargoGlobal ["ACE_plasmaIV",1];
    #endif 
};

ITW_TeammateArsenal = {
    scriptName "ITW_TeammateArsenalLoadout"; 
    private _teammates = units group player select {!isPlayer _x};
    if (count _teammates == 0) exitWith {hint localize "STR_ITW_TM_NoTeammatesAvail"};
    private _unit = _teammates#0;
    if (count _teammates > 1) then {
        ITW_TA_Index = 0;
        ITW_TM_MENU = [[localize "STR_ITW_RADIO_SelectTeammate", false]];
        {
            ITW_TM_MENU pushBack [name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
        } forEach _teammates;
        showCommandingMenu "#USER:ITW_TM_MENU";
        waitUntil {commandingMenu == ""};
        ITW_TM_MENU = nil;
        _unit = _teammates#ITW_TA_Index;
    };
    
    if (_unit getVariable ["tmLoadAdj",false]) exitWith {
        "teammate" cutText [localize "STR_ITW_TM_OtherAdjustingLoadout","PLAIN"];
        [] spawn {sleep 5; "teammate" cutText ["","PLAIN"];};
    };
    _unit setVariable ["tmLoadAdj",true,true];
    
    // use arsenal to set unit loadout
    private _loadout = getUnitLoadout _unit;
    private _playerLoadout = getUnitLoadout player;
    
    waitUntil {!isSwitchingWeapon _unit}; 
    _unit setUnitLoadout [[],[],[],[uniform _unit,[]],[],[],"","",[],["","","","","",""]];
    waitUntil {!isSwitchingWeapon player}; 
    player setUnitLoadout _loadout;
    
    ITW_TMArsenalExited = false;
    if (isNil "PlpEnhacedArsenalActive") then {PlpEnhacedArsenalActive = "@Enhanced Arsenal" in (getLoadedModsInfo apply {_x#0})};
    private _namespace = if (PlpEnhacedArsenalActive) then {objNull} else {missionNamespace};  
    private _full = if (PlpEnhacedArsenalActive) then {true} else {ITW_ParamVirtualArsenal == 0};
    if (!isNil "ace_arsenal_fnc_removeVirtualItems" && {ITW_ParamAceArsenal == 1}) then {
        [ITW_AceVACabinet, player, ITW_ParamVirtualArsenal == 0] call ace_arsenal_fnc_openBox;
    } else {
        ["Open",_full,_namespace] call BIS_fnc_arsenal;
    };
    waitUntil {ITW_TMArsenalExited};
    
    waitUntil {!isSwitchingWeapon _unit}; 
    waitUntil {!isSwitchingWeapon player};
    private _unitLoadout = getUnitLoadout player;
    _unit setUnitLoadout _unitLoadout;
    player setUnitLoadout _playerLoadout;
    _unit setVariable ["ITW_loadout",_unitLoadout,true];
    _unit setVariable ["tmLoadAdj",false,true];
};

ITW_TeammateArsenalExit = {
    // called whenever the player exits the arsenal
    ITW_TMArsenalExited = true;
};

ITW_TeammateDown = {
    // Called on all clients
    if (isNil "bis_revive_duration") then {
        #define DEFAULT_REVIVE_TIME 6
        if ((missionNamespace getVariable["bis_reviveParam_duration",-100]) == -100) then {bis_revive_duration = getMissionConfigValue ["ReviveDelay",DEFAULT_REVIVE_TIME]} else {missionNamespace getVariable["bis_reviveParam_duration",-100]};
        if (bis_revive_duration <= 0) then {bis_revive_duration = DEFAULT_REVIVE_TIME};
    };
                
    params ["_unit"];
    if (!hasInterface) exitWith {};

    _unit groupChat localize "STR_ITW_TM_ImDone";
    playSound3D [selectRandom HitCries,_unit,false,getPosASL _unit,5,1,200,0,true];

    private _id = addMissionEventHandler ["Draw3D", {
        _thisArgs params ["_unit","_bleedTimeout"];
        if (LV_PAUSE) then {_bleedTimeout = time + bis_revive_bleedOutDuration};
        if (time > _bleedTimeout) then { _unit setDamage 1 };
        if (lifeState _unit == "INCAPACITATED") then {
            private _pos = ASLToAGL getPosASLVisual _unit;
            private _dist = 1 max (player distance _unit);
            private _size = 1 min ((200 - _dist)/200); 
            if (_size > 0.05) then {
                private _alpha = ((_size - 1) * 0.75) + 1;
                _pos set [2,(_pos#2)+0.5];                            
                drawIcon3D ["\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_reviveMedic_ca.paa", [1,1,1,_size], _pos, _size, _size, 0];
            };
        } else {  
            removeMissionEventHandler ["Draw3D", _thisEventHandler];
        }},[_unit,time + bis_revive_bleedOutDuration]];
            
    _actionId = [_unit, format ["Revive %1",name _unit], 
        "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_revive_ca.paa",
        "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_revive_ca.paa", 
        "_this distance _target < 3 && {alive _this && {alive _target}}", 
        "_caller distance _target < 5 && {alive _caller && {alive _target}}", {
            // code start
            ITW_medicStanceAnims = if (stance _caller == "PRONE") then {[MedicActionsProne,"AmovPpneMstpSrasWrflDnon"]} else {[MedicActions,"AinvPknlMstpSnonWnonDnon_medicEnd"]};
            _caller playMoveNow selectRandom (ITW_medicStanceAnims#0);
            _target setVariable ["tmPlayerHealing",true,0];
        }, {
            // code progress
            //params ["_target", "_caller", "_actionId", "_arguments", "_progress", "_maxProgress"];
            if !(animationState _caller in ITW_medicStanceAnims) then {
                _caller playMoveNow selectRandom (ITW_medicStanceAnims#0);
            };
        }, {
            // code complete
            //params ["_target", "_caller", "_actionId", "_arguments"];
            _caller switchMove (ITW_medicStanceAnims#1);
            _target setVariable ["tmPlayerHealing",nil,0];
            _target remoteExec ["ITW_TeammateRevived",_target];
            ITW_medicStanceAnims = nil;
        }, {
            // code interrupted
            _caller switchMove (ITW_medicStanceAnims#1);
            _target setVariable ["tmPlayerHealing",nil,0];
            ITW_medicStanceAnims = nil;
        }, [], bis_revive_duration] call BIS_fnc_holdActionAdd;

    sleep 5;
    // after a few seconds, the ai can be killed
    _unit setVariable ["tmAICanDie",true];
    waitUntil { sleep 1; lifeState _unit != "INCAPACITATED" };
    _unit removeAction _actionId;
    _unit setVariable ["tmAICanDie",false];
};

ITW_TeammateRevive = {
    // runs on server only
    scriptName "ITW_TeammateRevive";
    HasACEMedical = isClass (configFile >> "CfgSounds" >> "ACE_heartbeat_fast_3");
    
    while {true} do {
        sleep 10;
        while {LV_PAUSE} do {sleep 5};
        //private _allPlayersDown = {ALIVE(_x) && {CONSCIOUS(_x)}} count (allPlayers + HeadlessClients) == 0;
            
        if (ITW_ParamTeammateSwitch > 0) then {
            // allow down players to swap into teammates
            {
                private _player = _x;
                private _conscious = CONSCIOUS(_x);
                
                if (_conscious) then {_player setVariable ["tmSwapShowing",false]; continue};
                if (_player getVariable ["tmSwapShowing",false]) then {continue};
                
                private _teammatesAvail = {!isPlayer _x && {ALIVE(_x) && {CONSCIOUS(_x) && {_x distance _player < 1000}}}} count units group _player > 0;
                if (_teammatesAvail) then {
                    _player setVariable ["tmSwapShowing",true];
                    [_player] remoteExec ["ITW_TeammateSwitch",_player];
                };
            } forEach allPlayers;
        };
        
        if (!HasACEMedical && {ITW_ParamFriendlyRevive == 1}) then {
            private _needRevive = [];
            private _canRevive = [];
            
            private _allTeamUnits = allPlayers + ITW_AI_UNITS;
            {
                private _unit = _x;
                if (lifeState _unit == "INCAPACITATED") then {
                    // CHECK: ai already assigned to revive
                    if !(_unit getVariable ["#rev_being_revived", false] || _unit getVariable ["tmPlayerHealing",false]) then {
                        private _aiReviving = _unit getVariable ["tmBeingHealed",objNull];
                        if (isNull _aiReviving) then {
                            _needRevive pushBack _unit;
                        };
                    };
                };
            } forEach _allTeamUnits;
            
            if !(_needRevive isEqualTo []) then {
            
                //// For ITW, we want the Allies to be able to revive if they are nearby, so I added this
                if !(ITW_AllyGroups isEqualTo []) then {
                    ITW_AllyGroups = ITW_AllyGroups - [grpNull];
                    private _playersDown = _needRevive select {isPlayer _x};
                    if (_playersDown isNotEqualTo []) then {
                        private _allyUnits = [];
                        {_allyUnits = _allyUnits + units _x} count ITW_AllyGroups;
                        private _teammatesAvail = _allyUnits select {
                            private _unit = _x;
                            alive _unit && 
                            {_x == vehicle _x &&
                            {isNull (_unit getVariable ["tmHealing",objNull]) &&
                            {{_unit distance _x < 100} count _playersDown > 0 
                        }}}};
                        _canRevive = _teammatesAvail;
                    };
                };
                
                {
                    private _unit = _x;
                    if (lifeState _unit != "INCAPACITATED") then {
                        private _veh = vehicle _unit;
                        if (! isPlayer _unit && 
                           {isNull (_unit getVariable ["tmHealing",objNull]) && 
                           {alive _unit &&
                           {_veh == _unit ||                                        // not in a vehicle OR
                               {(getPosATL _veh #2 < 1 || isTouchingGround _veh) && //   veh is on the ground
                                  {crew _veh findIf {isPlayer _x} < 0 &&            //   no players in the veh
                                  {speed _veh < 1}}}}}}) then {                     //   veh is stopped
                            _canRevive pushBack _unit;
                        };
                    };
                } forEach _allTeamUnits;
                
                private _matrix = [];
                {
                    private _downUnit = _x;
                    {
                        // if ai are in vehicle, only allow them to exit to get up a player
                        if (vehicle _x != _x && {!isPlayer _downUnit}) then {continue};
                        if (_x distance _downUnit < 500) then {
                            _matrix pushBack [_x distance _downUnit,_downUnit,_x];
                        }
                    } forEach _canRevive;
                } forEach _needRevive;
            
                if !(_matrix isEqualTo []) then {
                    // sort by distance
                    _matrix sort true; 
                    
                    // have closest pairs trigger revives
                    private _downs = [];
                    private _heals = [];
                    {
                        private _downUnit = _x#1;
                        private _healer = _x#2;
                        if !(_downUnit in _downs || _healer in _heals) then {
                            _downUnit setVariable ["tmBeingHealed",_healer];
                            _healer setVariable ["tmHealing",_downUnit,2];
                            [_downUnit,_healer] remoteExec ["ITW_TeammateReviveMP",_healer];
                            private _chatType = if (group _healer isEqualTo group _downUnit) then {"groupChat"} else {"sideChat"};
                            [_healer,localize "STR_ITW_TM_GoingToHelp" + " " + name _downUnit] remoteExec [_chatType,0];   
                            _downs pushBack _downUnit;
                            _heals pushBack _healer;
                        };
                    } foreach _matrix;                
                    // if any down units are players, then send a 2nd healer if available
                    _downs = _downs - allPlayers; // remove players from down list so they get handled again
                    {
                        private _downUnit = _x#1;
                        private _healer = _x#2;
                        if !(_downUnit in _downs || _healer in _heals) then {
                            _downUnit setVariable ["tmBeingHealed",_healer];
                            _healer setVariable ["tmHealing",_downUnit,2];
                            [_downUnit,_healer,false] remoteExec ["ITW_TeammateReviveMP",_healer];
                            private _chatType = if (group _healer isEqualTo group _downUnit) then {"groupChat"} else {"sideChat"}; 
                            [_healer,localize "STR_ITW_TM_Covering" + " " + name _downUnit] remoteExec [_chatType,0];  
                            _downs pushBack _downUnit;
                            _heals pushBack _healer;
                        };
                    } forEach _matrix; 
                
                    // if all players are down, the AI takes leadership, but they can block
                    // the healers, so make one of the healers the leader so he will do healing
                    if (count _heals > 0) then {
                        private _healer = _heals#0;
                        if (!(isPlayer leader _healer) && {leader _healer != _healer}) then {
                            private _groupHealer = group _healer;
                            [[_groupHealer,_healer],"selectLeader",_groupHealer] call ITW_FncRemoteLocalGroup;
                        };
                    };               
                };
            };
        };
    
        // clean up dead ai
        {
            if (! alive _x) then {
                ITW_AI_UNITS = ITW_AI_UNITS - [_x];
                [_x] spawn { 
                    params ["_deadUnit"];
                    waitUntil {
                        sleep 30;
                        private _safeToDelete = true;
                        {                      
                            if (_x distance _deadUnit < 1000) exitWith {_safeToDelete = false};
                        } forEach (allPlayers - HeadlessClients);                     
                        _safeToDelete || isNull _deadUnit
                    };                  
                    if (! isNull _deadUnit) then {
                        if (vehicle _deadUnit == _deadUnit) then {deleteVehicle _deadUnit} else {vehicle _deadUnit deleteVehicleCrew _deadUnit};
                    };
                };    
            };
        } forEach ITW_AI_UNITS;        
    };
};

#define STATE_MOVE     0
#define STATE_APPROACH 1
#define STATE_REVIVE   2
#define STATE_DELAY    3
#define STATE_CANCELED 4
#define STATE_DONE     5

ITW_TeammateReviveMP = {
    // Must be run on client where AI is local

    // Perform a revive on the unit
    scopeName "aiRevive";
    params ["_downUnit","_ai",["_isPrimary",true]];                            

    // save the ai current tasking
    private _taskState = [_ai] call ITW_TeammateGetOrders;
    
    // kick it off
    _ai doMove getPosATL _downUnit;

    private _prevState = -1;
    private _state = STATE_MOVE;
    private _timeout = time + 30;
    private _reviveTime = 0;
    private _allowSmoke = _isPrimary;
    if (_allowSmoke) then {
        _allowSmoke = time >= (_ai getVariable ["tmSmoke",time]);
    };
    private _smoke = _allowSmoke && {random 100 < 75};

    private _aiVeh = vehicle _ai;
    if (_aiVeh != _ai) then {
        moveOut _ai;
    };
    
    _ai setVariable ["tmSmoke",time+60];
    if (_isPrimary) then {
        _ai setCaptive true;
        _ai setCombatBehaviour "SAFE";
        _ai disableAI "TARGET";
        _ai disableAI "AUTOTARGET";
        _ai disableAI "SUPPRESSION";
    };
    while { _state != STATE_DONE} do {
        if (!(lifeState _ai == "HEALTHY" || lifeState _ai == "INJURED") 
            || {lifeState _downUnit != "INCAPACITATED" || time > _timeout
            || {_downUnit getVariable ["#rev_being_revived", false]
            || {_downUnit getVariable ["tmPlayerHealing",false]
            || {_ai getVariable ["tmSwitching",false]}}}}) then {
                if (_state == STATE_REVIVE) then {_ai switchMove "AinvPknlMstpSnonWnonDnon_medicEnd"};
                _state = STATE_CANCELED;
        } else {
            if (_downUnit getVariable ["tmApproach",_ai] != _ai) then {
                _state = STATE_DELAY;
            };
        }; 
        if (ITW_TM_Debug && {(_state != _prevState)}) then {
            _prevState = _state;
            diag_log format ["Teammates: Ai Revive %1 reviving %2 state %3",_ai,_downUnit,_state];
        };   
        switch (_state) do {
            case STATE_MOVE: {
                _ai moveTo getPosATL _downUnit;
                if (_ai distance _downUnit < 10 && _smoke) then { 
                    _smoke = false;
                    _ai setVariable ["tmSmoke",time+60];
                    _ai lookAt _downUnit; 
                    private _fPos = getPosATL _ai;
                    _fPos set [2,(_fPos#2)+1];
                    private _speed = (_ai distance2D _downUnit) * 5 / 8;
                    private _dir = _ai getDir _downUnit;
                    private _smoke = "SmokeShell" createVehicle _fPos;
                    _smoke setVelocity [
                        (sin _dir * _speed), 
                        (cos _dir * _speed), 
                        _speed];
                };
                if (_ai distance _downUnit < 12 && {vehicle _downUnit != _downUnit}) then {
                    private _timeout = time + 2;
                    private _veh = vehicle _downUnit;
                    private _radius = (boundingBox _veh #2) * 2 / 3;
                    moveOut _downUnit;
                    waitUntil {vehicle _downUnit == _downUnit || time > _timeout};
                    _downUnit setPosATL ([_veh,_radius,_veh getDir _ai] call ITW_FncRelPos);
                    _ai moveTo getPosATL _downUnit;
                };
                if (_ai distance _downUnit < 5) then { _state = STATE_APPROACH };
                if (moveToFailed _ai) then { _state = STATE_CANCELED };
            };
            case STATE_APPROACH: {
                _downUnit setVariable ["tmApproach",_ai];
                if (_ai distance _downUnit > 1) then { 
                    private _p = _ai getPos [1,_ai getDir _downUnit];
                    _p set [2,(getPosATL _ai)#2 + 0.1];
                    _ai setPosATL ([_ai,0.5,_ai getDir _downUnit] call ITW_FncRelPos);
                };
                _state = STATE_REVIVE;
                _ai disableAI "MOVE";
                _ai disableAI "TARGET";
                _ai disableAI "FSM";
                _ai doWatch _downUnit;
                _ai setDir (_ai getDir _downUnit);
                _ai setPosATL ([_downUnit,1,_downUnit getDir _ai] call ITW_FncRelPos);
                _ai playMoveNow selectRandom MedicActions;
                _ai doWatch _downUnit;
                if (isNil "bis_revive_duration") then {
                    #define DEFAULT_REVIVE_TIME 6
                    bis_revive_duration = if ((missionNamespace getVariable["bis_reviveParam_duration",-100]) == -100) then {getMissionConfigValue ["ReviveDelay",DEFAULT_REVIVE_TIME]} else {missionNamespace getVariable["bis_reviveParam_duration",-100]};
                    if (bis_revive_duration <= 0) then {bis_revive_duration = DEFAULT_REVIVE_TIME};
                };
                #define TYPE_MEDIKIT 619
                private _reviveDuration = bis_revive_duration;
                {
                    if (getNumber (configFile >> "cfgWeapons" >> _x >> "ItemInfo" >> "type") == TYPE_MEDIKIT) exitWith {_reviveDuration = bis_revive_duration / 3};
                } forEach backpackItems _ai;                  
                _reviveTime = time + _reviveDuration + 3;
                _timeout = _reviveTime + 5;
            };
            case STATE_REVIVE: {
                if (time > _reviveTime) then {
                    // trigger arma 3 revive
                    if (isPlayer _downUnit) then {
                        [_downUnit] call ITW_TeammateGetPlayerUp;
                    } else {
                        _downUnit remoteExec ["ITW_TeammateRevived",_downUnit];
                    };
                    sleep 3;
                    // free up ai
                    _ai doWatch objNull;
                    _ai switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
                    // reset revive unit variables
                    _downUnit setVariable ["tmBeingHealed",objNull,2];
                    _ai setVariable ["tmHealing",objNull,2];
                    _state = STATE_DONE;
                } else {
                    if (_ai distance _downUnit > 6) then { 
                        _ai doWatch objNull;
                        _ai switchMove "AinvPknlMstpSnonWnonDnon_medicEnd";
                        _state = STATE_CANCELED 
                    } else {
                        if !(animationState _ai in MedicActions) then {
                            _ai playMoveNow selectRandom MedicActions;
                        };
                    };
                };
            };
            case STATE_DELAY: {};
            case STATE_CANCELED: {
                _ai enableAI "MOVE";
                _ai enableAI "TARGET";
                _ai enableAI "FSM";
                _downUnit setVariable ["tmBeingHealed",objNull,2];
                _ai spawn {sleep 5; _this setVariable ["tmHealing",objNull,2];};
                if (lifeState _ai == "INCAPACITATED") then {
                    _ai switchMove "unconsciousrevivedefault";
                    _ai setUnconscious true;
                };
                _state = STATE_DONE;
            };
        };
        sleep 2;
    };
    //diag_log format ["Teammates: Ai Done Revive %1 reviving %2 state %3",_ai,_downUnit,_state];

     if (_downUnit getVariable ["tmApproach",objNull] == _ai) then {
        _downUnit setVariable ["tmApproach",nil];
     };
    _ai setVariable ["tmHealing",objNull,2];
    [_ai] call ITW_TeammateAiDone;
    sleep 3;
    [_ai,_taskState] call ITW_TeammateSetOrders; // don't need to spawn since this script was spawned
};

ITW_TeammateAiDone = {
    params ["_unit"];
    // unit locality gets switched around when player squad leader goes unconscious, so keep making sure we are on the right client
    if (!local _unit) exitWith {_this remoteExec ["ITW_TeammateAiDone",_unit]};
    
    _unit enableAI "MOVE";
    _unit enableAI "TARGET";
    _unit enableAI "FSM";
    _unit enableAI "AUTOTARGET";
    _unit enableAI "SUPPRESSION";
    _unit setCaptive false;
};

ITW_TeammateGetPlayerUp = {
    params ["_downUnit"];
    // unit locality gets switched around when squad leader goes unconscious, so keep making sure we are on the right client
    if (!local _downUnit) exitWith {[_downUnit] remoteExec ["ITW_TeammateGetPlayerUp",_downUnit]};
    private _isDisabled = _downUnit getVariable ["#rev_state", 0] == 2;
    if (_isDisabled) then {
        ["",1,_downUnit] call BIS_fnc_reviveOnState;
        _downUnit setVariable ["#rev", 1, true];
    }; 
};

ITW_TeammateRevived = {
    // call where unit is local
    private _downUnit = _this;
    // unit locality gets switched around when squad leader goes unconscious, so keep making sure we are on the right client
    if (!local _downUnit) exitWith {
        diag_log "Error pos: ITW_TeammateRevived called where unit is not local";
        _downUnit remoteExec ["ITW_TeammateRevived",_downUnit];
    };
    _downUnit setDamage 0;
    _downUnit setUnconscious false;
    _downUnit setCaptive false;
    private _animState = animationState _downUnit; // sometimes units get their animation state stuck
    sleep 3;
    if (animationState _downUnit == _animState) then {_downUnit switchMove "UnconsciousFaceDown"};
    private _orders = _downUnit getVariable "ITW_TmOrders";
    if (isNil "_orders") then {
        // unit may have changed locality during the 3 second sleep
        if (local _downUnit) then {
            _downUnit doFollow leader _downUnit;
        } else {
            [_downUnit,leader _downUnit] remoteExec ["doFollow",_downUnit];
        };
    } else {
        [_downUnit,_orders] call ITW_TeammateSetOrders;
    };
    
};

ITW_TeammateGetOrders = {
    params ["_unit",["_remoteCaller",-1]];
    
    // unit locality gets switched around when squad leader goes unconscious, so keep making sure we are on the right client
    if (!local _unit) exitWith {
        [_unit,clientOwner] remoteExec ["ITW_TeammateGetOrders",_unit];
        private _timeout = time + 5;
        private _taskState = [];
        _unit setVariable ["ITW_TM_taskState",[]];
        waitUntil {_taskState = _unit getVariable ["ITW_TM_taskState",[]]; _taskState isNotEqualTo [] || time > _timeout};
        _unit setVariable ["ITW_TM_taskState",nil];
        _taskState
    };
    
    private _veh = vehicle _unit;
    private _role = [];

    if (_veh != _unit) then {
        private _crewInfo = fullCrew [_veh,"",true] select {_x#5 == _unit};
        if (_crewInfo isNotEqualTo []) then {
            private _roleType = _crewInfo#0#1;
            _role = [_roleType,_crewInfo#0#(if (_roleType == "turret") then {3} else {2})];
        } else {
            _role = assignedVehicleRole _unit;
        };
    };

    private _taskState = createHashMapFromArray [
        ["command", currentCommand _unit],
        ["destination", (expectedDestination _unit)#0],
        ["target", assignedTarget _unit],
        ["assignedVehicle", _veh],
        ["vehicleRole", _role]
    ];
    
    private _isHolding = (unitReady _unit) && (((expectedDestination _unit)#1) isEqualTo "DoNotPlan");
    if (_isHolding) then {
        _taskState set ["command","MOVE"];
        _taskState set ["destination",getPosATL _unit];
    };
    if (ITW_TM_Debug) then {diag_log ["****** SAVE STATE ******",_unit];{diag_log [_x,_y]} foreach _taskState};

    if (_remoteCaller > 1) then {_unit setVariable ["ITW_TM_taskState",_taskState,_remoteCaller]};
    _taskState
};

ITW_TeammateSetOrders = {
    // spawn where unit is local
    params ["_unit", "_taskState"];
    
    // unit locality gets switched around when squad leader goes unconscious, so keep making sure we are on the right client
    if (!local _unit) exitWith {_this remoteExec ["ITW_TeammateSetOrders",_unit]};
    
    if (ITW_TM_Debug) then {diag_log ["**** LOAD STATE ****",_unit];{diag_log [_x,_y]} foreach _taskState};

    _unit doFollow (leader _unit); // try to reset any stopped or whatever state so he will correctly go back to what he was doing
    
    private _veh  = _taskState get "assignedVehicle";
    private _role = _taskState get "vehicleRole";
    private _cmd  = _taskState get "command";
    private _tgt  = _taskState get "target";
    private _dest = _taskState get "destination";
    
    // Vehicle Assignment
    if (!isNull _veh && {_veh != _unit && {alive _veh}}) then {
        if (_role isEqualTo []) then {_role = ["any"]};
        
        private _roleType = toLowerANSI (_role#0);
        private _roleArg = -1;
        
        if (_roleType in ["cargo","turret"] && {count _role < 2}) then {
            _roleType = "any";
        };
        switch (_roleType) do {
            case "driver":    {_unit assignAsDriver _veh};
            case "gunner":    {_unit assignAsGunner _veh};
            case "commander": {_unit assignAsCommander _veh};
            case "cargo":     {_roleArg = _role#1#0; _unit assignAsCargoIndex [_veh, _roleArg]};
            case "turret":    {_roleArg = _role#1;   _unit assignAsTurret     [_veh, _roleArg]};
            default           {
                // Assign to the first available seat 
                private _emptySeats = fullCrew [_veh, "", true] select {isNull (_x#0)};
                if (_emptySeat isNotEqualTo []) then {
                    private _seatInfo = [0,"cargo"];
                    {
                        private _seatType = _x;
                        private _index = _emptySeats findIf {_x#1 == _seatType};
                        if (_index >= 0) exitWith {_seatInfo = _emptySeats#_index};
                    } forEach ["turret","cargo","commander","gunner","driver"];
                    
                    _roleType = toLowerANSI _seatInfo#1;
                    switch (_roleType) do {
                        case "driver":   {_unit assignAsDriver _veh};
                        case "gunner":   {_unit assignAsGunner _veh};
                        case "commander":{_unit assignAsCommander _veh};
                        case "turret":   {_roleArg = _seatInfo#3; _unit assignAsTurret [_veh, _roleArg]};
                        default          {_roleArg = _seatInfo#2; _unit assignAsCargo _veh};
                    };
                };
            };
        };
        
        [_unit] orderGetIn true; 
        // sometimes doesn't work.
        // I think it's when the AI has taken leadership while player was down and has issued new orders and gotten into a strange state

        // wait for the unit to get in the vehicle
        private _timeout = time + 60;
        private _moveTimeout = time + 10;
        private _prevPos = getPosATL _unit;
        private _cancel = false;
        waitUntil {
            private _pos = getPosATL _unit;
            if (time > _moveTimeout) then {
                _moveTimeout = time + 5;
                if (_prevPos distanceSqr _pos < 1) then {
                    _cancel = true;
                    if (alive _unit && alive _veh) then {
                        switch (_roleType) do {
                            case "driver":   {_unit moveInDriver _veh};
                            case "gunner":   {_unit moveInGunner _veh};
                            case "commander":{_unit moveInCommander _veh};
                            case "turret":   {_unit moveInTurret [_veh, _roleArg]};
                            case "cargo":    {_unit moveInCargo [_veh, _roleArg, true]};
                            default          {_unit moveInAny _veh};
                        };
                    };
                };
                _prevPos = _pos;
            };
            sleep 1;
            _cancel ||
            time > _timeout ||
            !alive _unit ||
            !alive _veh ||
            vehicle _unit isNotEqualTo _unit
        };
    };

    // Target and Stop state
    if (!isNull _tgt) then { _unit doTarget _tgt; } else { _unit doWatch objNull; };

    switch (_cmd) do {
        case "MOVE": {_unit doMove _dest};
        case "WAIT";
        case "STOP": {doStop _unit};
        default      {if (vehicle _unit == _unit) then {_unit doFollow (leader _unit)}}; 
    };
};
                        
ITW_TeammateSwitch = {
    // Allow swapping an incapacitated player with a non-incapacitated AI

    // runs on client where player is local
    params ["_player"];
    
    TEAM_SWAP_DN = 0;
    #define DIK_KEY_T 20
    private _cutTextLayer = -1;
    private _done = false;
    
    private _keyDownEH = findDisplay 46 displayAddEventHandler ["KeyDown", 
        'params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];
        if (TEAM_SWAP_DN == 0 && {_key == DIK_KEY_T && {!_shift && {!_ctrl && {!_alt}}}}) then {TEAM_SWAP_DN = time};
        false'];
    private _keyUpEH = findDisplay 46 displayAddEventHandler ["KeyUp", 
        'params ["_displayOrControl", "_key", "_shift", "_ctrl", "_alt"];
        if (_key == DIK_KEY_T && {!_shift && {!_ctrl && {!_alt}}}) then {TEAM_SWAP_DN = 0};
        false'];
    
    private _prevDnState = false;
    while {!_done} do {
        private _aiUnits = units group _player select {!isPlayer _x && {ALIVE(_x) && {CONSCIOUS(_x) && {_x distance _player < 1000}}}};
        if (_aiUnits isEqualTo []) exitWith {};
        if (! isNull (_player getVariable ["tmApproach",objNull])) exitWith {};
        if (CONSCIOUS(_player)) exitWith {};
        
        if (!(_cutTextLayer in allActiveTitleEffects) || {_prevDnState != (TEAM_SWAP_DN > 0)}) then {
            private _text = if (TEAM_SWAP_DN == 0) then {
                    "<t size='1.5' color='#ffffff'><br/><br/><br/><br/><br/><br/><br/><br/>" + localize "STR_ITW_TM_HoldT" + "</t>"
                } else {
                    "<t size='1.5' color='#88bb88'><br/><br/><br/><br/><br/><br/><br/><br/>" + localize "STR_ITW_TM_HoldT" + "</t>"
                };
            _cutTextLayer = "TeammateSwitch" cutText [_text,"PLAIN",-1,true,true];
        }; 
        _prevDnState = TEAM_SWAP_DN > 0;    
        sleep 0.5;
        _done = TEAM_SWAP_DN > 0 && {time - TEAM_SWAP_DN > 3};
    };
    _cutTextLayer cutText ["","PLAIN",1];
    findDisplay 46 displayRemoveEventHandler ["KeyDown",_keyDownEH];
    findDisplay 46 displayRemoveEventHandler ["KeyDown",_keyUpEH];
    
    if (!_done) exitWith {_player setVariable ["tmSwapShowing",false,2]};
    
    private _aiUnits = units group _player select {!isPlayer _x && {ALIVE(_x) && {CONSCIOUS(_x) && {_x distance _player < 1000}}}} apply {[_x distance _player,_x]};
    if (_aiUnits isEqualTo []) exitWith {_player setVariable ["tmSwapShowing",false,2]};
    _aiUnits sort true;
    private _ai = _aiUnits#0#1;
    _ai setVariable ["tmSwitching",true,0];
        
    if (ITW_TM_Debug) then {diag_log format ["Teammates: TeammateSwitch %1 <> %2",name _player,name _ai]};

    private _stance2Pos = {
        switch (_this) do {
            case "CROUCH": {"MIDDLE"};
            case "PRONE" : {"DOWN"};
            default {"UP"};            
        }
    };

    _player allowDamage false;

    "TSwitch" cutText [localize "STR_ITW_TM_Switching","BLACK OUT",0.5,true,false];
    sleep 0.6;
    
    private _aiPos = getPosATL _ai;
    private _aiDmg = damage _ai;
    private _aiStance = stance _ai;
    private _aiDir = getDir _ai;
    private _playerPos = getPosATL _player;
    private _playerDmg = damage _player;
    private _playerStance = stance _player;
    private _playerDir = getDir _player;

    // detect ai in a vehicle
    private _vehAi = vehicle _ai;
    private _vehSlotAi = [];
    if (_vehAi != _ai) then {
        private _crew = fullCrew _vehAi select {_x#0 == _ai};
        if !(_crew isEqualTo []) then {_vehSlotAi = _crew#0};
        [_ai] remoteExec ["unassignVehicle",_ai];
    };

    // detect player in a vehicle
    private _vehPlayer = vehicle _player;
    private _vehSlotPlayer = [];
    if (_vehPlayer != _player) then {
        private _crew = fullCrew _vehPlayer select {_x#0 == _player};
        if !(_crew isEqualTo []) then {_vehSlotPlayer = _crew#0};
    };

    // revive the player
    moveOut _player;
    private _isDisabled = _player getVariable ["#rev_state", 0] == 2;
    if (_isDisabled) then {
        ["",1,_player] call bis_fnc_reviveOnState;
        _player setVariable ["#rev", 1, true];
    }; 
    sleep 2;
    [_player,""] remoteExec ["switchMove",0];
    
    [_ai,_playerPos,_playerDir,_playerDmg,_vehPlayer,_vehSlotPlayer] remoteExec ["ITW_TeammateSwitchAI",_ai];
    sleep 0.1;

    if (_vehSlotAi isEqualTo []) then {
        _player setDir _aiDir;
        _player setPosATL _aiPos;
    } else {
        private _role = _vehSlotAi#1;
        private _turretPath = _vehSlotAi#3; 
        private _timeout = time + 2;
        waitUntil {vehicle _ai != _vehAi || time > _timeout};
        switch (_role) do {
            case "driver"    : {_player moveInDriver _vehAi};
            case "commander" : {_player moveInCommander _vehAi};
            case "gunner"    : {_player moveInGunner _vehAi};
            case "turret"    : {_player moveInTurret [_vehAi,_turretPath]};
            default            {_player moveInAny _vehAi};
        };
        sleep 1;
        // check if something went wrong and just move the player nearby the vehicle
        if (vehicle _player != _vehAi) then {player setPosATL _aiPos};
    };


    if (ITW_ParamTeammateSwitch == 1) then {
        private _aiLO = getUnitLoadout _ai;
        private _playerLO = getUnitLoadout _player;
        [_player, _aiLO] call ITW_FncSetUnitLoadout;
        [_ai, _playerLO] call ITW_FncSetUnitLoadout;
        _ai setVariable ["ITW_loadout",_playerLO,true];
    };
    sleep 0.25; 

    _player setDamage _aiDmg;
    if (_vehSlotAi isEqualTo []) then {_player setUnitPos (_aiStance call _stance2Pos)};

    sleep 0.5;


    "TSwitch" cutText ["","BLACK IN",0.5,true,false];

    missionNamespace setVariable ["TmTsDone",true,2];

    sleep 5;
    _player allowDamage true;    
    _player setVariable ["tmSwapShowing",false,2]
};

ITW_TeammateSwitchAI = {
    // spawn where ai is local
    params ["_ai","_pos","_dir","_damage","_veh","_vehSlot"];
    if (!local _ai) exitWith {_this remoteExec ["ITW_TeammateSwitchAI",_ai]};
    
    _ai allowDamage false; 
    moveOut _ai;
    private _tmpPos = _pos getPos [5,random 360];
    _tmpPos set [2,(_pos#2) + 0.5];
    _ai setPosATL _tmpPos;
    _ai switchMove "";
    _ai setDir _dir;
    _ai setUnconscious true;
    sleep 0.25;
    _ai setCaptive true;
    _ai setDamage _damage;
    
    if (_vehSlot isEqualTo []) then {
        sleep 1;
        _ai setPosATL _pos;
    } else {
        sleep 2;
        private _role = _vehSlot#1;
        private _turretPath = _vehSlot#3;
        switch (_role) do {
            case "driver"    : {_ai moveInDriver _veh};
            case "commander" : {_ai moveInCommander _veh};
            case "gunner"    : {_ai moveInGunner _veh};
            case "turret"    : {_ai moveInTurret [_veh,_turretPath]};
            default            {_ai moveInAny _veh};
        };
    };
    [_ai] remoteExec ["ITW_TeammateDown",0];
    _ai setVariable ["tmSwitching",false,0];
    sleep 5;
    [_ai,true] remoteExec ["allowDamage",_ai]; // use remoteExec in case ai changed locality during function
};

ITW_TeammatesHeal = {
    if (!isServer) then {
        [] remoteExec ["ITW_TeammatesHeal",2];
    } else {
        if !(isNil "ITW_AI_UNITS") then {
            {
                private _lifestate = lifeState _x;
                if (_lifestate == "HEALTHY" || {_lifestate == "INJURED"}) then {_x setDamage 0};
                _x call ITW_FncAceHeal;
            } forEach ITW_AI_UNITS;
        };
    };
};

ITW_TeammateSaveLocal = {
    private _savedTeam = profileNamespace getVariable [format["ITW_TeammatesLocal%1",worldName],[]];
    ITW_Menu1Answer = 1;
    if !(_savedTeam isEqualTo []) then {
        ITW_Menu1Answer = 0;
        ITW_Menu1 = [
            [localize "STR_ITW_TM_ReplaceTeamSave", true],
            [localize "STR_ITW_COMMON_Yes", [2], "", -5, [["expression","ITW_Menu1Answer = 1"]], "1", "1"],
            [localize "STR_ITW_COMMON_No",  [3], "", -3, [["expression", ""]], "1", "1"]
        ];
        showCommandingMenu "#USER:ITW_Menu1";
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};  
    };
    if (ITW_Menu1Answer == 1) then {
        private _saveInfo = units group player select {!isPlayer _x} apply {[typeOf _x,name _x,getUnitLoadout _x]};
        if (_saveInfo isEqualTo []) exitWith {hint localize "STR_ITW_TM_NoAIInYourGroup"};
        profileNamespace setVariable [format["ITW_TeammatesLocal%1",worldName],_saveInfo];
        hint format [localize "STR_ITW_TM_TeammatesSaveFMT",count _saveInfo];
    };
};

ITW_TeammateLoadLocal = {
    // call on player's machine
    private _saveInfo = profileNamespace getVariable [format["ITW_TeammatesLocal%1",worldName],[]];
    if (_saveInfo isEqualTo []) exitWith {hint localize "STR_ITW_TM_NoSavedTeammates"};
    private _playerTeam = units group player;
    ITW_Menu1Answer = 1;
    if ({!isPlayer _x} count _playerTeam > 0) then {
        ITW_Menu1Answer = 0;
        ITW_Menu1 = [
            [localize "STR_ITW_TM_ReplaceCurrentAi", true],
            [localize "STR_ITW_TM_ReplaceSquad", [2], "", -5, [["expression","ITW_Menu1Answer = 1"]], "1", "1"],
            [localize "STR_ITW_TM_AddToSquad",  [3], "", -5, [["expression", "ITW_Menu1Answer = 2"]], "1", "1"],
            [localize "STR_ITW_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"]
        ];
        showCommandingMenu "#USER:ITW_Menu1";
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};   
        if (ITW_Menu1Answer == 1) then {
            {deleteVehicle _x} forEach _playerTeam;
        };
    };
    if (ITW_Menu1Answer > 0) then {
        private _aiCnt = {!isPlayer _x} count units group player;
        {
            if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {hint localize "STR_ITW_ALLY_MaxSquadSize"};
            private _grpCnt = count units group player;
            private _timeout = time + 2;
            [player,[_x] call ITW_TeammateSaveFix] remoteExec ["ITW_AllyRecruit",2];
            _aiCnt = _aiCnt + 1;
            waitUntil {time > _timeout || {count units group player > _grpCnt}}; // wait so they are in the correct order on command bar
        } forEach _saveInfo;
    };
};

ITW_TeammatesSave = {
    if (isNil "ITW_AI_UNITS" || {ITW_AI_UNITS isEqualTo []}) exitWith {[]};
    ITW_AI_UNITS select {alive _x} apply {[typeOf _x,name _x,getUnitLoadout _x]};
};

ITW_TeammatesLoad = {
    // parameter is array of loadouts to save off info, or a player to add teammates to player's squad
    params ["_teammatesOrPlayer"];  
    if (typeName _teammatesOrPlayer == "ARRAY") exitWith { ITW_TEAMMATES_RELOAD = _teammatesOrPlayer };
    if (isNil "ITW_TEAMMATES_RELOAD") exitWith {};
    private _player = _teammatesOrPlayer;
    private _aiCnt = 0;
    {
        if (_aiCnt >= ITW_ParamFriendlySquadSize) exitWith {};
        private _grpCnt = count units group _player;
        private _timeout = time + 2;
        [_player,[_x] call ITW_TeammateSaveFix] remoteExec ["ITW_AllyRecruit",2];
        _aiCnt = _aiCnt + 1;
        waitUntil {time > _timeout || {count units group _player > _grpCnt}}; // wait so they are in the correct order on command bar
    } forEach ITW_TEAMMATES_RELOAD;
};

ITW_TeammateSaveFix = {
    // fixes to handle backward compatibility
    params ["_info"];
    if (typeName (_info#0) == "ARRAY") then {
        _info = ["","",_info];
    };
    _info
};

ITW_TeammateReplace = {
    // allows player to swap into a teammate
    params ["_player"];
    private _teammates = units group player select {!isPlayer _x};
    if (count _teammates == 0) exitWith {hint localize "STR_ITW_TM_NoTeammatesAvail"};
    private _unit = objNull;
    if (count _teammates > 0) then {
        ITW_TA_Index = -1;
        ITW_TM_MENU = [[localize "STR_ITW_TM_BecomeTeammate", false]];
        {
            ITW_TM_MENU pushBack [name _x,[_forEachIndex+3], "", -5, [["expression",format ["ITW_TA_Index = %1;",_forEachIndex]]], "1", "1"];
        } forEach _teammates;
        ITW_TM_MENU pushBack [localize "STR_ITW_COMMON_Cancel",[16], "", -4, [["expression",""]], "1", "1"];
        showCommandingMenu "#USER:ITW_TM_MENU";
        waitUntil {commandingMenu == ""};
        ITW_TM_MENU = nil;
        if (ITW_TA_Index >= 0) then { 
            _unit = _teammates#ITW_TA_Index;
        };
    };
    if (!isNull _unit) then {
        private _pos = getPosATL _unit;
        
        // detect ai in a vehicle
        private _veh = vehicle _unit;
        private _vehSlot = [];
        if (_veh != _unit) then {
            private _crew = fullCrew _veh select {_x#0 == _unit};
            if !(_crew isEqualTo []) then {_vehSlot = _crew#0}
        };
        
        private _name = name _unit;
        moveOut _unit;
        deleteVehicle _unit;
        
        if (_vehSlot isEqualTo []) then {
            _player setPosATL _pos;
        } else {
            private _role = _vehSlot#1;
            private _turretPath = _vehSlot#3;
            switch (_role) do {
                case "driver"    : {_player moveInDriver _veh};
                case "commander" : {_player moveInCommander _veh};
                case "gunner"    : {_player moveInGunner _veh};
                case "turret"    : {_player moveInTurret [_veh,_turretPath]};
                default            {_player moveInAny _veh};
            };
        };
        [format ["%1 %2 %3",name _player,localize "STR_ITW_TM_Replaced",_name]] remoteExec ["hint",0];
    };
};

ITW_TeammatesSwapTeam = {
    // call on any client - handle if player did a Team Switch with an ai
    params ["_addGroup","_removeGroup"];
    if ({isPlayer _x} count units _removeGroup == 0) then {
        [_removeGroup] remoteExec ["ITW_TeammatesRemove",0];
    };
    [_addGroup] remoteExec ["ITW_TeammateCreated",0,_addGroup];
};

ITW_TeammateReset = {
    // run where unit is local (I think the 'name' command returns the full name on that client)
    params ["_unit", "_player"];
    private _playerGroup = group _player;
    private _loadout = (getUnitLoadout _unit);
    private _id = parseNumber ((str _unit) select [1]);
    _id = _id - 1;
    private _class = (typeOf _unit);
    private _name = name _unit;
    private _face = face _unit;
    private _speaker = speaker _unit;

    private _pos = [(getPos _unit), 0, 50, 1, 0, -1, 0, [], [[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
    if (_pos isEqualTo [0,0,0]) then {
        _pos = [(getPosATL _player), 0, 50, 1, 0, -1, 0, [], [[0,0,0],[0,0,0]]] call BIS_fnc_findSafePos;
    };
    if (_pos isEqualTo [0,0,0]) then {
        _pos = getPosATL _player;
    };

    deleteVehicle _unit;
    [_player,[_class,_name,_loadout,_id,_face,_speaker]] remoteExec ["ITW_AllyRecruit",2];
};
   

["ITW_TeammateCreated"] call SKL_fnc_CompileFinal;
["ITW_TeammateLoadout"] call SKL_fnc_CompileFinal;
["ITW_TeammateDown"] call SKL_fnc_CompileFinal;
["ITW_TeammateRevive"] call SKL_fnc_CompileFinal;
["ITW_TeammateReviveMP"] call SKL_fnc_CompileFinal;
["ITW_TeammateRevived"] call SKL_fnc_CompileFinal;
["ITW_TeammateSwitch"] call SKL_fnc_CompileFinal;
["ITW_TeammatesInit"] call SKL_fnc_CompileFinal;
["ITW_TeammateUnStop"] call SKL_fnc_CompileFinal;
["ITW_TeammateFollow"] call SKL_fnc_CompileFinal;
["ITW_TeammateGetPlayerUp"] call SKL_fnc_CompileFinal;
["ITW_TeammatesHeal"] call SKL_fnc_CompileFinal;
["ITW_TeammateAddFAKs"] call SKL_fnc_CompileFinal;
["ITW_TeammateSaveLocal"] call SKL_fnc_CompileFinal;
["ITW_TeammateLoadLocal"] call SKL_fnc_CompileFinal;
["ITW_TeammatesSave"] call SKL_fnc_CompileFinal;
["ITW_TeammatesLoad"] call SKL_fnc_CompileFinal;
["ITW_TeammateArsenal"] call SKL_fnc_CompileFinal;
["ITW_TeammateArsenalExit"] call SKL_fnc_CompileFinal;
["ITW_TeammateReplace"] call SKL_fnc_CompileFinal;
["ITW_TeammateSaveFix"] call SKL_fnc_CompileFinal;
["ITW_TeammateSwitchAI"] call SKL_fnc_CompileFinal;
["ITW_TeammatesSwapTeam"] call SKL_fnc_CompileFinal;
["ITW_TeammatesRemove"] call SKL_fnc_CompileFinal;
["ITW_TeammateReset"] call SKL_fnc_CompileFinal;
["ITW_TeammateAiDone"] call SKL_fnc_CompileFinal;
["ITW_TeammateGetOrders"] call SKL_fnc_CompileFinal;
["ITW_TeammateSetOrders"] call SKL_fnc_CompileFinal;