if (isNil "SKL_LocationSelection") then {SKL_LocationSelection = compileFinal preprocessFileLineNumbers "scripts\Skull\SKL_LocationSelection.sqf"};

SKL_BFC_showWaypoint = false; // used for debugging

SKL_BlackfishCircle = {
    // call on all clients & server
    params ["_veh","_playerSide"]; // _veh is an aircraft, _playerside is west, east or independent
    if (hasInterface) then {
        _veh addAction ["<t color='#88dd88'>"+localize "STR_SKL_BF_BlackfishCircle" + "</t>",{
            params ["_target", "_caller", "_actionId", "_arguments"];
            [_target] call SKL_BFC_Menus;
        },nil,1.5,false,true,"","_target isEqualTo vehicle _this && {driver _target != _this && {! isNull (driver _target)}}",-1];
    };
    if (isServer) then {
        [_veh,_playerSide] call SKL_BFC_Load;
    };
};

SKL_BFC_Menus = {
    params ["_veh"];
    BFC_answer = 1; // anything > 0
    while {BFC_answer > 0} do {
        private _driver = driver _veh;
        private _bfcRunning = _veh getVariable ["SKL_BFC_running",false];
        private _bfcRunning01 = if (_bfcRunning) then [{"1"},{"0"}];
        private _bfcStartAllowed01 = if (_bfcRunning && {!(_veh getVariable ["SKL_BFC_startPos",[]] isEqualTo [])}) then [{"1"},{"0"}];
        private _isHostile = _veh getVariable ["SKL_BFC_hostile",false];
        private _canBeHostile01 = if (count (units east - [_driver]) == 0 || {count (units independent - [_driver]) == 0 || {count (units west - [_driver]) == 0}}) then [{"1"},{"0"}];
        BFC_menu1 = [
            [localize "STR_SKL_BF_BlackfishCircle", true],
            [format [localize "STR_SKL_BF_ChooseRadius"   ,"("+str (_veh getVariable "SKL_BFC_radius"  )+")"], [2], "", -5, [["expression","BFC_answer = 1"]], "1", "1"],
            [format [localize "STR_SKL_BF_ChooseAltitude" ,"("+str (_veh getVariable "SKL_BFC_altitude")+")"], [3], "", -5, [["expression","BFC_answer = 2"]], "1", "1"],
            [format [localize "STR_SKL_BF_ChooseDirection","("+((_veh getVariable "SKL_BFC_direction") call SKL_BFC_DirString)+")"], [4], "", -5, [["expression","BFC_answer = 3"]], "1", "1"],
            [localize "STR_SKL_BF_ChooseCenter"                                                    , [5], "", -5, [["expression","BFC_answer = 4"]], "1", "1"],
            [localize "STR_SKL_BF_BlackfishLand"                                                   , [6], "", -5, [["expression","BFC_answer = 5"]], "1", _bfcRunning01],
            [localize "STR_SKL_BF_BlackfishReturn"                                                 , [7], "", -5, [["expression","BFC_answer = 6"]], "1", _bfcStartAllowed01],
            [localize "STR_SKL_BF_Done"                                                            , [8], "", -5, [["expression","BFC_answer = 7"]], "1", _bfcRunning01],
            [""                                                                                    ,  [], "", -1, [["expression", ""]], "1", "1"],
            [localize "STR_SKL_BF_SetPeaceful"                                                     , [9], "", -5, [["expression","BFC_answer = 8"]], if  (_isHostile) then [{"1"},{"0"}], "1"],
            [localize "STR_SKL_BF_SetHostile"                                                      , [9], "", -5, [["expression","BFC_answer = 8"]], if !(_isHostile) then [{"1"},{"0"}], _canBeHostile01],
            [""                                                                                    ,  [], "", -1, [["expression", ""]], "1", "1"],
            [localize "STR_SKL_COMMON_Cancel"                                                      ,[16], "", -5, [["expression","BFC_answer =-1"]], "1", "1"]
        ];
        showCommandingMenu "#USER:BFC_menu1";
        waitUntil {!(commandingMenu isEqualTo "")};
        waitUntil {commandingMenu isEqualTo ""};   
        if (BFC_answer > 0) then {
            switch (BFC_answer) do {
                case 1: { // Radius
                    BFC_answer = 0;
                    BFC_menu1 = [
                        [format [localize "STR_SKL_BF_ChooseRadius",""], true],
                        [" 500m",[2], "", -5, [["expression","BFC_answer =  500"]], "1", "1"],
                        [" 750m",[3], "", -5, [["expression","BFC_answer =  750"]], "1", "1"],
                        ["1000m",[4], "", -5, [["expression","BFC_answer = 1000"]], "1", "1"],
                        ["1250m",[5], "", -5, [["expression","BFC_answer = 1250"]], "1", "1"],
                        ["1500m",[6], "", -5, [["expression","BFC_answer = 1500"]], "1", "1"],
                        ["1750m",[7], "", -5, [["expression","BFC_answer = 1750"]], "1", "1"],
                        ["2000m",[8], "", -5, [["expression","BFC_answer = 2000"]], "1", "1"],
                        ["2250m",[9], "", -5, [["expression","BFC_answer = 2250"]], "1", "1"],
                        ["2500m",[10],"", -5, [["expression","BFC_answer = 2500"]], "1", "1"],
                        ["2750m",[11],"", -5, [["expression","BFC_answer = 2750"]], "1", "1"],
                        ["3000m",[12],"", -5, [["expression","BFC_answer = 3000"]], "1", "1"],
                        [localize "STR_SKL_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"]
                    ];
                    showCommandingMenu "#USER:BFC_menu1";
                    waitUntil {!(commandingMenu isEqualTo "")};
                    waitUntil {commandingMenu isEqualTo ""};   
                    if (BFC_answer > 0) then {
                        [_veh,"SKL_BFC_radius",BFC_answer] call SKL_BFC_Save;
                    };
                    BFC_answer = 1; // keep menu open
                };
                case 2: { // Altitude
                    BFC_answer = 0;
                    BFC_menu1 = [
                        [format [localize "STR_SKL_BF_ChooseAltitude",""], true],
                        [" 250m",[2], "", -5, [["expression","BFC_answer =  250"]], "1", "1"],
                        [" 500m",[3], "", -5, [["expression","BFC_answer =  500"]], "1", "1"],
                        [" 750m",[4], "", -5, [["expression","BFC_answer =  750"]], "1", "1"],
                        ["1000m",[5], "", -5, [["expression","BFC_answer = 1000"]], "1", "1"],
                        ["1250m",[6], "", -5, [["expression","BFC_answer = 1250"]], "1", "1"],
                        ["1500m",[7], "", -5, [["expression","BFC_answer = 1500"]], "1", "1"],
                        ["1750m",[8], "", -5, [["expression","BFC_answer = 1750"]], "1", "1"],
                        ["2000m",[9], "", -5, [["expression","BFC_answer = 2000"]], "1", "1"],
                        ["2250m",[10],"", -5, [["expression","BFC_answer = 2250"]], "1", "1"],
                        ["2500m",[11],"", -5, [["expression","BFC_answer = 2500"]], "1", "1"],
                        [localize "STR_SKL_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"]
                    ];
                    showCommandingMenu "#USER:BFC_menu1";
                    waitUntil {!(commandingMenu isEqualTo "")};
                    waitUntil {commandingMenu isEqualTo ""};   
                    if (BFC_answer > 0) then {
                        [_veh,"SKL_BFC_altitude",BFC_answer] call SKL_BFC_Save;
                    };
                    BFC_answer = 1; // keep menu open
                };
                case 3: { // Direction
                    BFC_answer = 0;
                    BFC_menu1 = [
                        [format [localize "STR_SKL_BF_ChooseDirection",""], true],
                        [localize "STR_SKL_BF_Counterclockwise",[2], "", -5, [["expression","BFC_answer = -1"]], "1", "1"],
                        [localize "STR_SKL_BF_Clockwise"       ,[3], "", -5, [["expression","BFC_answer =  1"]], "1", "1"],
                        [localize "STR_SKL_COMMON_Cancel",[16], "", -3, [["expression", ""]], "1", "1"]
                    ];
                    showCommandingMenu "#USER:BFC_menu1";
                    waitUntil {!(commandingMenu isEqualTo "")};
                    waitUntil {commandingMenu isEqualTo ""};   
                    if (BFC_answer != 0) then {
                        [_veh,"SKL_BFC_direction",BFC_answer] call SKL_BFC_Save;
                    };
                    BFC_answer = 1; // keep menu open
                };
                case 4: { // Center
                    private _pos = [true,localize "STR_SKL_BF_SelectCenter"] call SKL_LocationSelection;
                    if !(_pos isEqualTo []) then {
                        [_veh,_pos] remoteExec ["SKL_BFC_Task",2];
                    };
                    BFC_answer = 0; // close menu
                };
                case 5: { // Land
                    private _pos = [true,localize "STR_SKL_BF_SelectLanding"] call SKL_LocationSelection;
                    if !(_pos isEqualTo []) then {_veh setVariable ["SKL_BFC_land",_pos,2]};
                    BFC_answer = 0; // close menu
                };
                case 6: { // Return
                    _veh setVariable ["SKL_BFC_land",_veh getVariable ["SKL_BFC_startPos",[]],2];
                    BFC_answer = 0; // close menu
                };
                case 7: { // Done
                    [_veh,[]] remoteExec ["SKL_BFC_Task",2];
                    BFC_answer = 0; // close menu
                };
                case 8: { // Toggle Hostile
                    [_veh,"SKL_BFC_hostile",!_isHostile] call SKL_BFC_Save;
                };
            };
        };
    };
};

SKL_BFC_DirString = {
    if (_this < 1) then {localize "STR_SKL_BF_CounterClockwise"} else {localize "STR_SKL_BF_Clockwise"};
};

SKL_BFC_Load = {
    // call on server
    if !(isServer) exitWith {};
    params ["_veh","_playerSide"];
    // the saved variable name should be the same as the set variable name
    _veh setVariable ["SKL_BFC_radius"   ,profileNamespace getVariable ["SKL_BFC_radius"   ,1500],true];
    _veh setVariable ["SKL_BFC_altitude" ,profileNamespace getVariable ["SKL_BFC_altitude" ,1000],true];
    _veh setVariable ["SKL_BFC_direction",profileNamespace getVariable ["SKL_BFC_direction",-1],true];
    _veh setVariable ["SKL_BFC_hostile"  ,profileNamespace getVariable ["SKL_BFC_hostile"  ,false],true];
    _veh setVariable ["SKL_BFC_land",[],true];
    _veh setVariable ["SKL_BFC_playerSide",_playerSide,true];
};

SKL_BFC_Save = {
    // call on a client or server
    params ["_veh","_type","_value"];
    _veh setVariable [_type,_value,true]; // call this on client so that the client gets the update right away so the menus update correctly
    [_type,_value] remoteExec ["SKL_BFC_SaveServer",2]; // saved info is on server only
};

SKL_BFC_SaveServer = {profileNamespace setVariable _this}; // call on server

SKL_BFC_DriverAdjust = {
    // call where driver is local
    params ["_driver","_isBfcActive"];
    if (_isBfcActive) then {
        [_driver] joinSilent group _driver; // force driver to return to formation even if player gave stop command to them
        _driver disableAI "AUTOCOMBAT";
        _driver disableAI "TARGET";
        _driver disableAI "AUTOTARGET";
        _driver disableAI "RADIOPROTOCOL";
        _driver setUnitCombatMode "BLUE";
        group _driver setCombatBehaviour "CARELESS";
        _driver setBehaviour "CARELESS";
    } else {
        _driver enableAI "AUTOCOMBAT";
        _driver enableAI "TARGET";
        _driver enableAI "AUTOTARGET";
        _driver enableAI "RADIOPROTOCOL";
        _driver setUnitCombatMode (combatMode group _driver);
        group _driver setCombatBehaviour "AWARE"; 
        _driver setBehaviour "AWARE"; 
        doStop _driver;
    };
};

SKL_BFC_DriverSetHostile = {
    // called only by server from SKL_BFC_Task
    params ["_veh","_setHostile"];
    private _driver = driver _veh;
    private _oldGroup = group _driver;
    
    private _pilotSide = sideUnknown;
    if (_setHostile) then {
        if (count (units east        - [_driver]) == 0) then {_pilotSide = east       } else {
        if (count (units independent - [_driver]) == 0) then {_pilotSide = independent} else {
        if (count (units west        - [_driver]) == 0) then {_pilotSide = west       }}};
    } else {_pilotSide = civilian};
    if (_pilotSide == sideUnknown) exitWith {_oldGroup};
    
    private _newGroup = createGroup [_pilotSide,true];
    [_driver] joinSilent _newGroup;
    if (_setHostile) then {
        private _playerSide = _veh getVariable "SKL_BFC_playerSide";
        private _enemySide = ([east,west,independent] - [_playerSide,_pilotSide])#0;
        _enemySide  setFriend [_pilotSide,0];
        _pilotSide  setFriend [_enemySide,0];
        _playerSide setFriend [_pilotSide,1];
    };
    _newGroup
};

SKL_BFC_Task = {
    // call on server
    params ["_veh","_center"];
    _veh setVariable ["SKL_BFC_center",_center];
    if (_center isEqualTo []) exitWith {}; // all done with circling but don't want to land
    
    if (!(_veh getVariable ["SKL_BFC_running",false])) then {
        _veh setVariable ["SKL_BFC_running",true,true];
        _veh spawn {
            scriptName "SKL_BFC_Task";
            private _veh = _this;
            _veh setVariable ["SKL_BFC_startPos",if (((getPosATL _veh)#2) < 5) then {getPosATL _veh} else {[]},true];
            private _driver = currentPilot _veh;
            private _originalGroup = group _driver;
            private _group = grpNull;
            private _wasHostile = false;
            [_driver,true] remoteExec ["SKL_BFC_DriverAdjust",_driver];
            private _center = [0,0,0];
            private _prevFlyInHeight = 0;
            while {_veh getVariable "SKL_BFC_Land" isEqualTo [] && {{isPlayer _x} count crew _veh > 0 && {alive _veh && {alive driver _veh}}}} do {
                // setup loiter waypoint
                private _center = _veh getVariable "SKL_BFC_center";
                private _radius = _veh getVariable "SKL_BFC_radius";
                private _alt    = _veh getVariable "SKL_BFC_altitude";
                private _dir    = _veh getVariable "SKL_BFC_direction";
                
                if (isNull _group || {_wasHostile != _veh getVariable "SKL_BFC_hostile"}) then {
                    _wasHostile = _veh getVariable "SKL_BFC_hostile";
                    _group = [_veh,_wasHostile] call SKL_BFC_DriverSetHostile;
                };
                
                { deleteWaypoint _x } forEachReversed waypoints _group;
                if (_center isEqualTo []) exitWith {};
                
                private _wp = _group addWaypoint [_center,0];
                _wp setWaypointType "LOITER";
                _wp setWaypointLoiterRadius _radius;
                _wp setWaypointLoiterAltitude _alt;
                _wp setWaypointLoiterType (if (_dir == 1) then {"CIRCLE"} else {"CIRCLE_L"});
                _wp setWaypointSpeed "LIMITED";
                _wp setWaypointBehaviour "CARELESS";
                
                private _waypointIndex = currentWaypoint _group;
                
                // sometimes driver doesn't get airborne
                sleep 2;
                if !(isEngineOn _veh) then {
                    [_driver,getPosATL _driver getPos [200,getDir _veh]] remoteExec ["doMove",_driver]; 
                    [_veh,true] remoteExec ["engineOn",_veh];
                }; 
                
                // wait for command to do something different
                waitUntil {
                    sleep 1;
                    if !(_veh getVariable "SKL_BFC_center" isEqualTo _center) then {
                        _center = _veh getVariable "SKL_BFC_center"; 
                        if !(_center isEqualTo []) then {_wp setWaypointPosition [_center,0]};
                    };
                    if !(_veh getVariable "SKL_BFC_radius" isEqualTo _radius) then {
                        _radius = _veh getVariable "SKL_BFC_radius";
                        _wp setWaypointLoiterRadius _radius;
                    };
                    if !(_veh getVariable "SKL_BFC_altitude"  isEqualTo _alt) then {
                        _alt= _veh getVariable "SKL_BFC_altitude";
                        _wp setWaypointLoiterAltitude _alt;
                    };
                    if !(_veh getVariable "SKL_BFC_direction" isEqualTo _dir) then {
                        _wp setWaypointLoiterType (if (_dir == 1) then {"CIRCLE"} else {"CIRCLE_L"});
                    };
                    
                    !(_veh getVariable "SKL_BFC_land" isEqualTo []) ||      // told to land
                    {_center isEqualTo [] ||                                // told 'done'
                    {currentWaypoint _group != _waypointIndex ||            // given new circle point
                    {_wasHostile != _veh getVariable "SKL_BFC_hostile" ||   // changed hostility
                    {{isPlayer _x} count crew _veh == 0 ||                  // players ejected or died
                    {!alive _veh || {!alive _driver}}}}}}
                };
            };
            {deleteWaypoint _x} forEachReversed waypoints _group;
            if (alive _driver) then {
                if !(_veh getVariable "SKL_BFC_Land" isEqualTo []) then {
                    [_veh, [_veh getVariable "SKL_BFC_Land","Land",-1,true]] remoteExec ["landAt",_veh];
                    _veh setVariable ["SKL_BFC_Land",[]];
                    private _timeout = time + 120;
                    waitUntil {isTouchingGround _veh || {time > _timeout}};
                    if (alive _veh) then {
                        _veh setDamage 0;
                        [_veh, 1] remoteExec ["setFuel",_veh];
                        [_veh, 1] remoteExec ["setVehicleAmmo",_veh];
                        {if (alive _x) then {_x setDamage 0}} forEach crew _veh;
                    };
                };
                
                [_driver,false] remoteExec ["SKL_BFC_DriverAdjust",_driver];
                if (! isNull _originalGroup) then {
                    [_driver] joinSilent _originalGroup;
                    deleteGroup _group;
                };
            };
            _veh setVariable ["SKL_BFC_running",false,true];
        };
    };
};

if (isNil "SKL_fnc_CompileFinal") exitWith {};
["SKL_BlackfishCircle"] call SKL_fnc_CompileFinal;
["SKL_BFC_Menus"] call SKL_fnc_CompileFinal;
["SKL_BFC_DirString"] call SKL_fnc_CompileFinal;
["SKL_BFC_Load"] call SKL_fnc_CompileFinal;
["SKL_BFC_Save"] call SKL_fnc_CompileFinal;
["SKL_BFC_DriverAdjust"] call SKL_fnc_CompileFinal;
["SKL_BFC_Task"] call SKL_fnc_CompileFinal;
["SKL_BFC_SaveServer"] call SKL_fnc_CompileFinal;
["SKL_BFC_DriverSetHostile"] call SKL_fnc_CompileFinal;