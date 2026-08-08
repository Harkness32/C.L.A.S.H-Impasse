params ["_player", "_didJIP"];

if (!isDedicated) then {waitUntil {player == player};};
if ((!isServer) && (player != player)) then {waitUntil {player == player};};
waitUntil {! isNil "ITW_PreInitComplete"}; // wait for the server to catch up

// Code to allow player to fix frozen animation
[] spawn { 
    scriptName "ITW_AnimFreezeFixer";
    AnimFreezeFixer = false;
    while {true} do {
        sleep 15;
        if (!AnimFreezeFixer) then{
            private _id = player addAction [localize "STR_ITW_MISC_ResetAnimation","player switchMove ''",nil,-100,false,true,"","_this == _target"];
            waitUntil {sleep 1;AnimFreezeFixer};
            player removeAction _id;
        } else {
            AnimFreezeFixer = false;
        };
    };
};
player addEventHandler ["AnimChanged", {AnimFreezeFixer = true;}];

hcRemoveAllGroups player;
    
execVM "scripts\SKULL\SKL_Drag.sqf";