#include "defines.hpp"

ITW_CLASH_GroundMEDEVAC_fnc_Eligible = {
    params ["_id","_entry"];
    if (_entry isEqualTo [] || {count _entry < 9}) exitWith {[false,[]]};
    if (count ITW_CLASH_GroundMEDEVAC_Active >= ITW_CLASH_GroundMEDEVAC_MaxConcurrent) exitWith {[false,[]]};

    _entry params [
        "_group","_originalObjective","_archetype","_lineage","_startedAt",
        "_destination","_egressObjective","_source","_lastOrder"
    ];
    if (isNull _group || {{alive _x} count units _group == 0}) exitWith {[false,[]]};
    if !(_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {[false,[]]};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {[false,[]]};
    if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {[false,[]]};
    if (time < (_group getVariable ["ITW_CLASH_GroundMEDEVAC_RetryAt",0])) exitWith {[false,[]]};
    private _remnantEvac = _group getVariable ["ITW_CLASH_RemnantEvac",false];
    private _minWithdrawalTime = if (_remnantEvac) then {
        missionNamespace getVariable [
            "ITW_CLASH_RemnantEvacMinWithdrawalTime",
            ITW_CLASH_GroundMEDEVAC_MinWithdrawalTime
        ]
    } else {
        ITW_CLASH_GroundMEDEVAC_MinWithdrawalTime
    };
    if (time - _startedAt < _minWithdrawalTime) exitWith {[false,[]]};
    if (_destination isEqualTo []) exitWith {[false,[]]};

    private _origin = _group getVariable ["ITW_CLASH_CASEVAC_Origin",[]];
    if (_origin isEqualTo []) then {
        _origin = getPosATL leader _group;
        _group setVariable ["ITW_CLASH_CASEVAC_Origin",+_origin];
    };
    private _moved = leader _group distance2D _origin;
    if (!_remnantEvac && {
        _moved < ITW_CLASH_GroundMEDEVAC_MinDisengageDistance
    }) exitWith {[false,[]]};

    private _egressDistance = leader _group distance2D _destination;
    if (_egressDistance < ITW_CLASH_GroundMEDEVAC_MinEgressDistance || {
        _egressDistance > ITW_CLASH_GroundMEDEVAC_MaxPreferredEgressDistance
    }) exitWith {[false,[]]};

    private _objectiveClearance = [
        _group,_originalObjective
    ] call ITW_CLASH_CASEVAC_fnc_GetObjectiveClearance;
    if (_objectiveClearance < ITW_CLASH_GroundMEDEVAC_ObjectiveClearance) exitWith {[false,[]]};

    private _enemyDistance = [_group] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
    if (_enemyDistance < ITW_CLASH_GroundMEDEVAC_EnemyClearance) exitWith {[false,[]]};

    private _survivors = units _group select {alive _x};
    if (_survivors findIf {vehicle _x != _x} >= 0) exitWith {[false,[]]};

    private _spawnInfo = [
        _originalObjective,side _group
    ] call ITW_CLASH_GroundMEDEVAC_fnc_GetGroundSpawn;
    if (_spawnInfo isEqualTo []) exitWith {[false,[]]};
    private _pickupInfo = [_group,_destination] call ITW_CLASH_GroundMEDEVAC_fnc_FindRoadPickup;
    if (_pickupInfo isEqualTo []) exitWith {[false,[]]};

    [true,[
        _group,_originalObjective,+_archetype,_lineage,_startedAt,+_destination,
        _egressObjective,_source,_moved,_enemyDistance,_objectiveClearance,
        _egressDistance,_spawnInfo,_pickupInfo
    ]]
};

ITW_CLASH_GroundMEDEVAC_fnc_Dispatch = {
    params ["_id","_data"];
    _data params [
        "_group","_originalObjective","_archetype","_lineage","_startedAt","_destination",
        "_egressObjective","_source","_moved","_enemyDistance","_objectiveClearance",
        "_egressDistance","_spawnInfo","_pickupInfo"
    ];
    if (isNull _group) exitWith {false};
    if ((_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "") exitWith {false};
    if ((_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo "") exitWith {false};

    // Claim both arbitration gates before vehicle creation can yield.
    _group setVariable ["ITW_CLASH_GroundMEDEVAC_State","ground-spawning"];
    _group setVariable ["ITW_CLASH_CASEVAC_State","ground-spawning"];

    private _survivors = units _group select {alive _x};
    private _vehicleInfo = [
        count _survivors,_spawnInfo,side _group
    ] call ITW_CLASH_GroundMEDEVAC_fnc_SpawnVehicle;
    if (_vehicleInfo isEqualTo []) exitWith {
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_State",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_RetryAt",time + ITW_CLASH_GroundMEDEVAC_AirFallbackDelay];
        ["deferred",[_id,_lineage,"no-ground-vehicle-available"]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        false
    };

    _vehicleInfo params ["_veh","_crewGroup","_vehDef","_baseIndex","_spawnSource","_spawnPos"];
    _pickupInfo params ["_pickup","_rally","_road"];

    _group setVariable ["ITW_CLASH_GroundMEDEVAC_State","inbound"];
    _group setVariable ["ITW_CLASH_GroundMEDEVAC_Vehicle",_veh];
    _group setVariable ["ITW_CLASH_GroundMEDEVAC_Pickup",+_pickup];
    _group setVariable ["ITW_CLASH_GroundMEDEVAC_Rally",+_rally];
    // Reuse CASEVAC's state gate so the air manager cannot claim the same squad.
    _group setVariable ["ITW_CLASH_CASEVAC_State","ground-inbound"];

    private _withdrawal = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_withdrawal isNotEqualTo []) then {
        _withdrawal set [8,time + 1e6];
        ITW_CLASH_Withdrawals set [_id,_withdrawal];
    };

    [_group,_rally] call ITW_CLASH_GroundMEDEVAC_fnc_OrderRally;
    [_veh,_crewGroup,_pickup,25] call ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle;
    ITW_CLASH_GroundMEDEVAC_Active set [
        _id,[_group,_veh,_crewGroup,+_pickup,+_rally,+_destination,time]
    ];

    ["dispatched",[
        _id,_lineage,_originalObjective,_egressObjective,typeOf _veh,
        _baseIndex,_spawnSource,round _moved,round _enemyDistance,
        round _objectiveClearance,round _egressDistance,_pickup,_rally
    ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    [
        _id,_group,_veh,_crewGroup,_pickup,_rally,_destination,_spawnPos,
        _originalObjective,_egressObjective,_lineage
    ] spawn ITW_CLASH_GroundMEDEVAC_fnc_RunExtraction;
    true
};

// Air/ground arbitration. CASEVAC remains authoritative for long routes and for
// any route where ground extraction is unsafe/unavailable. If ground extraction
// is fully eligible and a ground slot is free, suppress air for this cycle;
// GroundMEDEVAC will either dispatch within two seconds or mark itself deferred,
// immediately reopening CASEVAC eligibility.
ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase = ITW_CLASH_CASEVAC_fnc_Eligible;
ITW_CLASH_CASEVAC_fnc_Eligible = {
    params ["_id","_entry"];
    private _air = [_id,_entry] call ITW_CLASH_CASEVAC_fnc_Eligible_GroundMEDEVACBase;
    if !(_air#0) exitWith {_air};

    private _ground = [_id,_entry] call ITW_CLASH_GroundMEDEVAC_fnc_Eligible;
    if (_ground#0) exitWith {
        private _group = (_ground#1)#0;
        private _nextLog = _group getVariable ["ITW_CLASH_GroundMEDEVAC_AirDeferLogAt",0];
        if (time >= _nextLog) then {
            _group setVariable ["ITW_CLASH_GroundMEDEVAC_AirDeferLogAt",time + 30];
            ["air-deferred-ground-preferred",[
                _id,(_ground#1)#3,round ((_ground#1)#11)
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
        };
        [false,[]]
    };
    _air
};

[] spawn {
    scriptName "ITW_CLASH_GroundMEDEVAC_Manager";
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;
        if (isNil "ITW_CLASH_LiveEnabled" || {
            !ITW_CLASH_LiveEnabled || {
                isNil "ITW_CLASH_HALReady" || {
                    !ITW_CLASH_HALReady || {isNil "ITW_CLASH_Withdrawals"}
                }
            }
        }) then {continue};

        // Share the same physical disengagement origin used by CASEVAC.
        {
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_x,[]];
            if (_entry isEqualTo [] || {count _entry < 9}) then {continue};
            private _group = _entry#0;
            if (isNull _group) then {continue};
            if ((_group getVariable ["ITW_CLASH_CASEVAC_Origin",[]]) isEqualTo []) then {
                _group setVariable ["ITW_CLASH_CASEVAC_Origin",getPosATL leader _group];
            };
        } forEach +(keys ITW_CLASH_Withdrawals);

        if (count ITW_CLASH_GroundMEDEVAC_Active >= ITW_CLASH_GroundMEDEVAC_MaxConcurrent) then {continue};

        {
            if (count ITW_CLASH_GroundMEDEVAC_Active >= ITW_CLASH_GroundMEDEVAC_MaxConcurrent) exitWith {};
            private _id = _x;
            if (_id in (keys ITW_CLASH_GroundMEDEVAC_Active)) then {continue};
            private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
            private _eligibility = [_id,_entry] call ITW_CLASH_GroundMEDEVAC_fnc_Eligible;
            if !(_eligibility#0) then {continue};

            ["eligible",[
                _id,(_eligibility#1)#3,
                round ((_eligibility#1)#8),round ((_eligibility#1)#9),
                round ((_eligibility#1)#10),round ((_eligibility#1)#11),
                ((_eligibility#1)#13)#0,((_eligibility#1)#13)#1
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

            [_id,_eligibility#1] call ITW_CLASH_GroundMEDEVAC_fnc_Dispatch;
        } forEach +(keys ITW_CLASH_Withdrawals);
    };

    ITW_CLASH_GroundMEDEVAC_Started = false;
    diag_log "CLASH BOOT | ground-medevac-stopped";
};

true
