#include "defines.hpp"

ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle = {
    params ["_veh","_crewGroup",["_delay",10]];
    [_veh,_crewGroup,_delay] spawn {
        params ["_veh","_crewGroup","_delay"];
        sleep _delay;
        if (!isNull _veh) then {
            deleteVehicleCrew _veh;
            deleteVehicle _veh;
        };
        if (!isNull _crewGroup && {units _crewGroup isEqualTo []}) then {deleteGroup _crewGroup};
    };
};

ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal = {
    params [
        "_id","_group","_reason",["_veh",objNull],["_crewGroup",grpNull],["_homePos",[]]
    ];
    ITW_CLASH_GroundMEDEVAC_Active deleteAt _id;

    if (!isNull _group) then {
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_State",nil];
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_Vehicle",nil];
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_Pickup",nil];
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_Rally",nil];
        _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
        _group setVariable ["ITW_CLASH_GroundMEDEVAC_RetryAt",time + ITW_CLASH_GroundMEDEVAC_RetryCooldown];
        _group setVariable ["ITW_CLASH_CASEVAC_RetryAt",time + ITW_CLASH_GroundMEDEVAC_AirFallbackDelay];

        private _survivors = units _group select {alive _x};
        {
            if (!isNull _veh && {vehicle _x == _veh}) then {
                unassignVehicle _x;
                _x action ["GetOut",_veh];
            };
        } forEach _survivors;

        // If the rescue vehicle is intact, give survivors a few seconds to
        // physically dismount before restoring the foot-withdrawal waypoint.
        // No moveOut/teleport is used here.
        if (!isNull _veh && {alive _veh}) then {
            private _dismountDeadline = time + 8;
            waitUntil {
                sleep 0.5;
                isNull _group || {
                    (_survivors findIf {alive _x && {vehicle _x == _veh}}) < 0 || {
                        time > _dismountDeadline
                    }
                }
            };
        };
    };

    private _withdrawal = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_withdrawal isNotEqualTo [] && {!isNull _group}) then {
        _withdrawal set [8,-1000];
        ITW_CLASH_Withdrawals set [_id,_withdrawal];
        [_group,_withdrawal#5,_withdrawal#6,_withdrawal#7] call ITW_CLASH_fnc_OrderWithdrawal;
        _withdrawal = ITW_CLASH_Withdrawals getOrDefault [_id,_withdrawal];
        _withdrawal set [8,time];
        ITW_CLASH_Withdrawals set [_id,_withdrawal];
    };

    ["failed",[
        _id,
        if (isNull _group) then {""} else {_group getVariable ["ITW_CLASH_Lineage",_id]},
        _reason
    ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    if (!isNull _veh && {alive _veh} && {!isNull _crewGroup} && {_homePos isNotEqualTo []}) then {
        [_veh,_crewGroup,_homePos,100] call ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle;
        [_veh,_crewGroup,60] call ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle;
    } else {
        [_veh,_crewGroup,5] call ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle;
    };
};

ITW_CLASH_GroundMEDEVAC_fnc_RunExtraction = {
    params [
        "_id","_group","_veh","_crewGroup","_pickup","_rally","_returnPos",
        "_homePos","_originalObjective","_egressObjective","_lineage"
    ];
    scriptName "ITW_CLASH_GroundMEDEVAC_fnc_RunExtraction";

    private _inboundDeadline = time + ITW_CLASH_GroundMEDEVAC_InboundTimeout;
    private _arrived = false;
    private _failed = false;
    private _nextContactCheck = 0;
    while {!_arrived && {!_failed}} do {
        sleep 2;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [_id,_group,"squad-lost-before-pickup",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if (isNull _veh || {!alive _veh} || {!canMove _veh} || {isNull driver _veh}) exitWith {
            [_id,_group,"vehicle-lost-inbound",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) exitWith {
            ITW_CLASH_GroundMEDEVAC_Active deleteAt _id;
            [_veh,_crewGroup,_homePos,100] call ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle;
            [_veh,_crewGroup,10] call ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle;
        };
        if (time > _inboundDeadline) exitWith {
            [_id,_group,"inbound-timeout",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };

        if (time >= _nextContactCheck) then {
            _nextContactCheck = time + 5;
            private _contactDistance = [_group] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
            if (_contactDistance < ITW_CLASH_GroundMEDEVAC_InboundAbortClearance) then {
                ["abort-contact",[
                    _id,_lineage,round _contactDistance,ITW_CLASH_GroundMEDEVAC_InboundAbortClearance
                ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
                [_id,_group,"contact-reestablished",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
                _failed = true;
            };
        };

        if (_veh distance2D _pickup <= 35 && {abs speed _veh < 8}) then {
            _arrived = true;
        };
    };

    if (_failed || {!_arrived} || {isNull _group} || {isNull _veh} || {!alive _veh}) exitWith {};
    doStop (driver _veh);
    _veh limitSpeed 20;
    ["arrived-pickup",[_id,_lineage,_pickup,_rally,typeOf _veh]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    private _boardDeadline = time + ITW_CLASH_GroundMEDEVAC_BoardingTimeout;
    private _loaded = false;
    while {!_loaded} do {
        sleep 2;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [_id,_group,"squad-lost-boarding",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if (isNull _veh || {!alive _veh} || {!canMove _veh} || {isNull driver _veh}) exitWith {
            [_id,_group,"vehicle-lost-boarding",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if (time > _boardDeadline) exitWith {
            [_id,_group,"boarding-timeout",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };

        private _survivors = units _group select {alive _x};
        {
            if (vehicle _x != _veh) then {
                unassignVehicle _x;
                _x assignAsCargo _veh;
                _x doMove getPosATL _veh;
            };
        } forEach _survivors;
        _survivors orderGetIn true;
        _loaded = (_survivors findIf {vehicle _x != _veh}) < 0;
    };

    if (!_loaded || {isNull _group} || {isNull _veh} || {!alive _veh}) exitWith {};
    ["loaded",[_id,_lineage,{alive _x} count units _group,typeOf _veh]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    _group setVariable ["ITW_CLASH_GroundMEDEVAC_State","rtb"];
    _group setVariable ["ITW_CLASH_CASEVAC_State","ground-rtb"];
    private _latest = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_latest isNotEqualTo [] && {(_latest#5) isNotEqualTo []}) then {_returnPos = +(_latest#5)};
    private _roadReturn = [_returnPos] call ITW_CLASH_GroundMEDEVAC_fnc_GetRoadReturnPoint;
    [_veh,_crewGroup,_roadReturn,80] call ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle;
    ["rtb",[
        _id,_lineage,_egressObjective,round (_veh distance2D _returnPos),_roadReturn
    ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    private _returnDeadline = time + ITW_CLASH_GroundMEDEVAC_RTBTimeout;
    private _returned = false;
    while {!_returned} do {
        sleep 2;
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) then {
            _returned = true;
            continue;
        };
        if (isNull _veh || {!alive _veh} || {!canMove _veh} || {isNull driver _veh}) exitWith {
            [_id,_group,"vehicle-lost-rtb",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if (time > _returnDeadline) exitWith {
            [_id,_group,"rtb-timeout",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        };
        if (_veh distance2D _returnPos <= 140) then {_returned = true};
    };

    if (_returned) then {
        private _canonicalDeadline = time + 30;
        waitUntil {
            sleep 1;
            (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [] || {time > _canonicalDeadline}
        };
        private _absorbed = (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [];

        if (!_absorbed && {!isNull _group} && {!isNull _veh} && {alive _veh}) then {
            ["rear-handoff-fallback",[
                _id,_lineage,_egressObjective,round (_veh distance2D _returnPos)
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
            doStop (driver _veh);
            private _survivors = units _group select {alive _x};
            {
                if (vehicle _x == _veh) then {
                    unassignVehicle _x;
                    _x action ["GetOut",_veh];
                };
            } forEach _survivors;
            sleep 5;
            [_id,_group,"rear-absorption-timeout",_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
        } else {
            ["returned",[
                _id,_lineage,_egressObjective,_absorbed,
                if (isNull _veh) then {-1} else {round (_veh distance2D _returnPos)}
            ]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;
            ITW_CLASH_GroundMEDEVAC_Active deleteAt _id;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_GroundMEDEVAC_State",nil];
                _group setVariable ["ITW_CLASH_GroundMEDEVAC_Vehicle",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
            };
            if (!isNull _veh && {alive _veh} && {!isNull _crewGroup}) then {
                [_veh,_crewGroup,_homePos,100] call ITW_CLASH_GroundMEDEVAC_fnc_OrderVehicle;
            };
            // Rear logistics abstracts the empty vehicle after it visibly starts
            // back toward its spawn/home route.
            [_veh,_crewGroup,10] call ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle;
        };
    };
};

true
