// Skull Drag Mod
// Drag a wounded friendly

// don't add this drag if my mod is active, or if ace is in use
if (! isNil "SKLDG_Drag" || {! isNil "ace_dragging_fnc_setDraggable"}) exitWith {diag_log "Drag functionality provided by a mod"};

#define IS_DISABLED(UNIT)  ((lifeState UNIT == "INCAPACITATED") || (UNIT getVariable ['ais_unconscious',false]))

SKLDG_DRAGGING = false;
SKLDG_ActionHandler = objNull;
SKLDG_DRAGTEXT = "";

SKLDG_Drag = {
    params ["_unused", "_dragger", "_actionId", "_arguments"];
    private _wounded = cursorTarget;
    SKLDG_DRAGGING = true;
    private _wasDead = (lifeState _wounded select [0,4]) == "DEAD";
    while {(_wasDead || IS_DISABLED(_wounded)) && SKLDG_DRAGGING} do {
        private _fromProne = false;
        private _attachPt = [0,0,0];
        _dragger addEventHandler [ "AnimDone", {
            params[ "_unit", "_anim" ];
            if (SKLDG_DRAGGING) then 
            {
                if ( _anim == "AmovPpneMrunSnonWnonDb" || _anim == "AcinPknlMwlkSrasWrflDb") then {
                    _unit playMoveNow _anim;
                };
            } else {
                _unit removeEventHandler ["AnimDone",_thisEventHandler];
            };                
        }];
        if (stance _dragger == "PRONE") then {
            _fromProne = true;
            _dragger playMoveNow "AmovPpneMrunSnonWnonDb";
            _attachPt = [0,1.8,0.1];
        } else {
            _dragger playMoveNow "AcinPknlMwlkSrasWrflDb";
            if (!_wasDead) then {[_wounded,"AinjPpneMrunSnonWnonDb_grab"] remoteExec ["switchMove",0];};
            _attachPt = [0,1.1,0.092];
        };
        if (!_wasDead) then {
            // attachTo doesn't work on dead guys, so only add it to wounded
            _wounded attachTo [_dragger, _attachPt];
            _wounded setVectorUp (surfaceNormal position _wounded);
           [_wounded, 180] remoteExec ["setDir",_wounded];
           [_wounded, getPosATL _wounded] remoteExec ["setPosATL",_wounded]; // propigate the setDir over the network
        };
        _timeOut = time + 60;
        _action = _dragger addAction [format [localize "STR_SKL_DRAG_ReleaseInfoFMT",name _wounded], {SKLDG_DRAGGING = false;},_wounded,0,false,true,"","true"];
        sleep 0.5; 
        _zRotMatrix = [[0,0,0,0],[0,0,0,0],[0,0,1,0],[0,0,0,1]];
        waitUntil {
            if (_wasDead) then {
                // attachTo doesn't work on dead guys, so add this to move them
                private _newPos = (_dragger getPos [_attachPt#1,getDir _dragger]);
                _newPos set [2,0 max ((((getPosATL _wounded)#2) + ((getPosATL _dragger)#2))/2)];
                _wounded setPosATL _newPos;
            } else {
                _z = (getPosATL _wounded)#2;
                _z2 = (getPosATL _dragger)#2;     
                if (_z2 > 0.5) then {_z = (_attachPt#2) - 0.1;};             
                if (_z < 0.2 || _z > 0.4) then {
                    _attachPt set [2,(_attachPt#2)-_z];
                    _wounded attachTo [_dragger, _attachPt];
                    [_wounded,180] remoteExec ["setDir",_wounded];
                    // now we need to rotate the ground normal about Z by the dragger angle
                    _dir = getDir _dragger;
                    _normal = surfaceNormal position _wounded;
                    _zRotMatrix set [0,[cos _dir, -(sin _dir), 0, 0]];
                    _zRotMatrix set [1,[sin _dir, cos _dir, 0, 0]];
                    _normal pushBack 1;
                    _upVect = matrixTranspose (_zRotMatrix matrixMultiply matrixTranspose [_normal])#0;
                    _upVect deleteAt 3;
                    if !(local _wounded) then {
                        [_wounded,_upVect] remoteExec ["setVectorUp",_wounded]; // run on client to it stays that way
                    };
                };
            };
            if (inputAction "commandForward" > 0) then {SKLDG_DRAGGING = false;};
            sleep 0.2; 
            (!SKLDG_DRAGGING) || 
            (!_wasDead && !IS_DISABLED(_wounded)) || 
            (!alive (_dragger)) || (IS_DISABLED(_dragger))  || (vehicle _dragger != _dragger) ||
            (time > _timeOut)};
        SKLDG_DRAGGING = false;
        _dragger removeAction _action;
        sleep 0.1;
        detach _wounded;
        if (!_fromProne) then {
            _dragger playMove "amovpknlmstpsraswrfldnon";
            if (!_wasDead) then {[_wounded,"AinjPpneMrunSnonWnonDb_release"] remoteExec ["playMoveNow",_wounded];};
            sleep 2;
            if (IS_DISABLED(_wounded) && !_wasDead) then {
                [_wounded,"unconsciousrevivedefault"] remoteExec ["switchMove",_wounded];
            };
        };
        if (!alive _dragger) then {_dragger switchMove ""; }; //playMoveNow "AinjPpneMstpSnonWnonDnon";};
    };
    SKLDG_DRAGGING = false;
};

SKL_DG_IsDraggable = {
    private _isDraggable = false;
    private _wounded = cursorTarget;
    if (_wounded isKindOf "CAManBase" && !SKLDG_DRAGGING) then {
        if ((player distance _wounded)<3) then {
            private _text = "";
            if (IS_DISABLED(_wounded)) then {
                _isDraggable = true; 
                _text = format ["Drag %1",name _wounded];
            } else { 
                if (lifeState _wounded select [0,4] == "DEAD") then {
                    _isDraggable = true; 
                    _text = "Drag body";
                };
            };
            if (_isDraggable && (_text != SKLDG_DRAGTEXT)) then {
                SKLDG_DRAGTEXT = _text;
                {
                    if (((player actionParams _x) select 1) == "_this call SKLDG_Drag") exitWith { 
                        player setUserActionText [_x,SKLDG_DRAGTEXT];
                    };
                } forEach actionIDs player; 
            };
        };
    };
    _isDraggable
};

SKLDG_fnc_AddAction = {
    params ["_unit", "_corpse"];
    if (_unit != _corpse) then {
        {
            if (((_corpse actionParams _x) select 1) == "_this call SKLDG_Drag") then { _corpse removeAction _x; };
        } forEach actionIDs _corpse; 
    };
    while {alive _unit} do {
        _found = false;
        {
            if ((_unit actionParams _x) select 1 == "_this call SKLDG_Drag") exitWith { _found = true; };
        } forEach actionIDs _unit;
        if (not _found) then {
            _unit addAction [localize "STR_SKL_DRAG_DragWounded",{_this call SKLDG_Drag},nil,1,false,true,"","(player == _target) && {[] call SKL_DG_IsDraggable}",-1];
            //diag_log "*** skl_drag action added";
        };
        sleep 30;
    };
};

SKLDG_FNC_HANDLE = objNull; // ai request thread handler (null if not running)

// add event handler to add the actions
player addEventHandler ["Respawn", { 
                            if (!isNull SKLDG_FNC_HANDLE) then {terminate SKLDG_FNC_HANDLE;};
                            SKLDG_FNC_HANDLE = _this spawn SKLDG_fnc_AddAction;
                        }];
[ missionNamespace, "reviveRevived", {
    params [ "_unit", "_revivor" ];
    if !( isNull _revivor ) then {
        _found = false;
        {
            if ((_unit actionParams _x) select 1 == "_this call SKLDG_Drag") exitWith { _found = true; };
        } forEach actionIDs _unit;
        if (not _found) then {
            _unit addAction [localize "STR_SKL_DRAG_DragWounded",{_this call SKLDG_Drag},nil,1,false,true,"","(player == _target) && {[] call SKL_DG_IsDraggable}",-1];
            //diag_log "*** skl_drag action added";
        };
    };
}] call BIS_fnc_addScriptedEventHandler;
SKLDG_FNC_HANDLE = [player,player] spawn SKLDG_fnc_AddAction;

if (! isNil "SKL_fnc_CompileFinal") then {
["SKLDG_Drag"] call SKL_fnc_CompileFinal;
["SKL_DG_IsDraggable"] call SKL_fnc_CompileFinal;
["SKLDG_fnc_AddAction"] call SKL_fnc_CompileFinal;
};