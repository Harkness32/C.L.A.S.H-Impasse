#include "defines.hpp"

if (!isServer) exitWith {false};
ITW_CLASH_SpawnArchetypePreInitVersion = 1;
ITW_CLASH_SpawnArchetypePreInitReady = false;

// ITW_Enemy.sqf has just defined its canonical group callback, but preInit has
// deferred only this finalizer. Replace it here so every enemy group snapshots
// the exact unit-class template that exists at native Impasse group creation.
// This includes vehicle-delivered cargo groups, which can otherwise bypass
// ITW_AtkAddInfantryGroup until after transport.
if (isNil "ITW_EnemyGroupCallback") exitWith {
    diag_log "CLASH BOOT | FAILED | spawn-archetype-callback-source-missing";
    false
};

ITW_EnemyGroupCallback = {
    params ["_group"];

    if (!isNull _group) then {
        private _spawnArchetype = +(
            _group getVariable ["ITW_CLASH_SpawnArchetype",[]]
        );
        if (_spawnArchetype isEqualTo []) then {
            private _members = units _group;
            if (_members isNotEqualTo []) then {
                _spawnArchetype = _members apply {toLowerANSI typeOf _x};
                _group setVariable ["ITW_CLASH_SpawnArchetype",+_spawnArchetype];
                _group setVariable ["ITW_CLASH_SpawnStrength",count _spawnArchetype];
                _group setVariable ["ITW_CLASH_SpawnArchetypeCapturedAt",time];

                // The existing reconstitution contract consumes
                // ITW_CLASH_Archetype. Seed it from the immutable native spawn
                // template only when no earlier native path already captured it.
                if ((_group getVariable ["ITW_CLASH_Archetype",[]]) isEqualTo []) then {
                    _group setVariable ["ITW_CLASH_Archetype",+_spawnArchetype];
                };

                if (!isNil "ITW_CLASH_fnc_Log") then {
                    ["spawn-archetype-captured",[
                        if (isNil "ITW_CLASH_fnc_GroupId") then {str _group} else {[_group] call ITW_CLASH_fnc_GroupId},
                        count _spawnArchetype,
                        _spawnArchetype
                    ]] call ITW_CLASH_fnc_Log;
                };
            };
        };
    };

    ITW_EnemyGroups pushBack _group;
    ["enemy-group-callback",_group] call ITW_CLASH_fnc_ObserveGroup;
};

isNil {
    private _deferred = missionNamespace getVariable ["ITW_CLASH_DeferredFinalizers",[]];
    _deferred = _deferred - ["ITW_EnemyGroupCallback"];
    missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];
};

private _finalized = ["ITW_EnemyGroupCallback"] call SKL_fnc_CompileFinal;
ITW_CLASH_SpawnArchetypePreInitReady = _finalized;
if (_finalized) then {
    diag_log format [
        "CLASH BOOT | spawn-archetype-preinit-ready | version=%1 nativeCallback=true",
        ITW_CLASH_SpawnArchetypePreInitVersion
    ];
} else {
    diag_log "CLASH BOOT | FAILED | spawn-archetype-callback-finalization";
};
_finalized
