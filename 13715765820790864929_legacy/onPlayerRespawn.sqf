params ["_newUnit", "_oldUnit", "_respawn", "_respawnDelay"];
waitUntil {!isNull player};
diag_log format["ITW: Player %1 respawned: %2", name player, _this];

private _curator = getAssignedCuratorLogic _oldUnit; 
if (isNull _curator) then {
    // Find any curator currently assigned to NULL (dead body is gone already)
    {
        if (isNull (getAssignedCuratorUnit _x)) exitWith { _curator = _x; };
    } forEach allCurators;
};
if (! isNull _curator) then { 
    [_curator] remoteExec ["unassignCurator", 2]; 
    // we've got a curator, but the player could die again before it gets assigned use 'player' instead of '_newUnit'          
    [_curator] spawn {
        params ["_curator"];
        waitUntil { sleep 0.5; alive player}; 
        private _timeout = time + 120;
        while {time < _timeout} do {
            sleep 2;
            private _assignedCurator = getAssignedCuratorLogic player; 
            if (isNull _assignedCurator) then {
                [player,_curator] remoteExec ["assignCurator", 2];
            } else {
                _timeout = 0;
            };
        };
    };                                        
} else {
    if (serverCommandAvailable "#lock") then { // player is logged in as admin
        diag_log "ITW: Curator Module malfunction, requesting server recreation...";
        // something went wrong if admin/host doesn't have curator assigned, try to fix it
        [player] remoteExec ["ITW_FncResetZeus",2];
    };
};
            
[_newUnit,_oldUnit] remoteExec ["ITW_AllyHcRespawn",2];

// give new unit the last loaded loadout
private _loadout = player getVariable ["ITW_SavedLoadout",nil];
if (! isNil "_loadout") then { [player,_loadout] call ITW_FncSetUnitLoadout };
    
[player] call ITW_FncSetIdentity;

if (ITW_ParamStamina < 2) then {
    player enableStamina (ITW_ParamStamina == 1);
};

// move them to the spawn location
waitUntil{! isNil "ITW_GameReady"};
([getPosATL _oldUnit] call ITW_ObjGetPlayerSpawnPtDir) params ["_spawnPos","_spawnDir"];
_spawnPos = _spawnPos getPos [2 + random 2,random 360];
player setPosATL _spawnPos;
player setDir _spawnDir;

hideBody _oldUnit;