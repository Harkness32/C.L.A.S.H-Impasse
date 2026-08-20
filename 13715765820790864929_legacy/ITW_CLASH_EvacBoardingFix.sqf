#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_EvacBoardingFixStarted",false]) exitWith {};
ITW_CLASH_EvacBoardingFixStarted = true;
ITW_CLASH_EvacBoardingFixVersion = 1;

waitUntil {
    sleep 0.1;
    !isNil "ITW_CLASH_CASEVAC_AirOpsFixVersion" && {
        !isNil "ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base" && {
            !isNil "ITW_CLASH_GroundMEDEVAC_fnc_RunExtraction" && {
                !isNil "ITW_CLASH_fnc_ClearGroupWaypoints"
            }
        }
    }
};

ITW_CLASH_EvacBoarding_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["evac-" + _event,_payload] call ITW_CLASH_fnc_Log;
    };
};

ITW_CLASH_EvacBoarding_fnc_Board = {
    params ["_mode","_id","_lineage","_group","_vehicle","_timeout"];

    if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
        [false,"squad-lost-boarding"]
    };
    if (isNull _vehicle || {!alive _vehicle} || {!canMove _vehicle} || {isNull driver _vehicle}) exitWith {
        [false,if (_mode isEqualTo "air") then {"aircraft-lost-boarding"} else {"vehicle-lost-boarding"}]
    };

    [_group] call ITW_CLASH_fnc_ClearGroupWaypoints;
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "AWARE";

    private _survivors = units _group select {alive _x};
    {
        private _assigned = assignedVehicle _x;
        if (!isNull _assigned && {_assigned != _vehicle}) then {
            unassignVehicle _x;
        };
        if (assignedVehicle _x != _vehicle) then {
            _x assignAsCargo _vehicle;
        };
    } forEach _survivors;
    _survivors orderGetIn true;

    private _startedAt = time;
    private _deadline = time + _timeout;
    private _nextProgress = 0;

    ["boarding-start",[
        _id,_lineage,_mode,typeOf _vehicle,count _survivors,
        _survivors apply {round (_x distance2D _vehicle)}
    ]] call ITW_CLASH_EvacBoarding_fnc_Log;

    while {true} do {
        sleep 1;

        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [false,"squad-lost-boarding"]
        };
        if (isNull _vehicle || {!alive _vehicle} || {!canMove _vehicle} || {isNull driver _vehicle}) exitWith {
            [false,if (_mode isEqualTo "air") then {"aircraft-lost-boarding"} else {"vehicle-lost-boarding"}]
        };

        _survivors = units _group select {alive _x};
        if ((_survivors findIf {vehicle _x != _vehicle}) < 0) exitWith {
            ["boarding-complete",[
                _id,_lineage,_mode,typeOf _vehicle,count _survivors,round (time - _startedAt)
            ]] call ITW_CLASH_EvacBoarding_fnc_Log;
            [true,""]
        };

        if (time > _deadline) exitWith {
            ["boarding-timeout-detail",[
                _id,_lineage,_mode,typeOf _vehicle,round (time - _startedAt),
                _survivors apply {
                    private _assigned = assignedVehicle _x;
                    [
                        typeOf _x,
                        lifeState _x,
                        canMove _x,
                        CONSCIOUS(_x),
                        round (_x distance2D _vehicle),
                        !isNull _assigned,
                        _assigned == _vehicle,
                        vehicle _x == _vehicle
                    ]
                }
            ]] call ITW_CLASH_EvacBoarding_fnc_Log;
            [false,"boarding-timeout"]
        };

        {
            if (vehicle _x == _vehicle) then {continue};
            private _assigned = assignedVehicle _x;
            if (_assigned != _vehicle) then {
                if (!isNull _assigned) then {unassignVehicle _x};
                _x assignAsCargo _vehicle;
                [_x] orderGetIn true;
                ["boarding-assignment-repaired",[
                    _id,_lineage,_mode,typeOf _x,round (_x distance2D _vehicle)
                ]] call ITW_CLASH_EvacBoarding_fnc_Log;
            };
        } forEach _survivors;

        if (time >= _nextProgress) then {
            _nextProgress = time + 5;
            ["boarding-progress",[
                _id,_lineage,_mode,typeOf _vehicle,round (time - _startedAt),
                _survivors apply {
                    private _assigned = assignedVehicle _x;
                    [
                        typeOf _x,
                        lifeState _x,
                        canMove _x,
                        CONSCIOUS(_x),
                        round (_x distance2D _vehicle),
                        _assigned == _vehicle,
                        vehicle _x == _vehicle
                    ]
                }
            ]] call ITW_CLASH_EvacBoarding_fnc_Log;
        };
    }
};

// AirOpsFix keeps ITW_CLASH_CASEVAC_fnc_RunExtraction as the inbound-route
// wrapper and stores the canonical extraction routine in ..._V1Base. Replace
// only that base so explicit LZ routing and LZPadFix remain in force.
ITW_CLASH_CASEVAC_fnc_RunExtraction_V1Base = {
    params [
        "_id","_group","_heli","_crewGroup","_lz","_returnPos",
        "_originalObjective","_egressObjective","_archetype","_lineage","_startedAt"
    ];
    scriptName "ITW_CLASH_CASEVAC_fnc_RunExtraction";

    private _inboundDeadline = time + ITW_CLASH_CASEVAC_InboundTimeout;
    private _smokeThrown = false;
    private _landed = false;
    private _nextContactCheck = 0;

    scopeName "ITW_CLASH_CASEVAC_InboundScope";
    while {!_landed} do {
        sleep 1;
        if (isNull _group || {{alive _x} count units _group == 0}) exitWith {
            [_id,_group,"squad-lost-before-pickup",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (isNull _heli || {!alive _heli} || {!canMove _heli} || {isNull driver _heli}) exitWith {
            [_id,_group,"aircraft-lost-inbound",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) exitWith {
            ITW_CLASH_CASEVAC_Active deleteAt _id;
            [_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
            [_heli,_crewGroup,30] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
        };
        if (time > _inboundDeadline) exitWith {
            [_id,_group,"inbound-timeout",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };

        if (time >= _nextContactCheck) then {
            _nextContactCheck = time + 5;
            private _contactDistance = [_group] call ITW_CLASH_CASEVAC_fnc_GetNearestEnemyDistance;
            if (_contactDistance < ITW_CLASH_CASEVAC_InboundAbortClearance) then {
                ["abort-contact",[
                    _id,_lineage,round _contactDistance,ITW_CLASH_CASEVAC_InboundAbortClearance
                ]] call ITW_CLASH_CASEVAC_fnc_Log;
                [_id,_group,"contact-reestablished",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
                breakOut "ITW_CLASH_CASEVAC_InboundScope";
            };
        };

        private _distance = _heli distance2D _lz;
        if (!_smokeThrown && {_distance <= ITW_CLASH_CASEVAC_SmokeDistance}) then {
            private _smoke = createVehicle [ITW_CLASH_CASEVAC_SmokeClass,_lz,[],0,"CAN_COLLIDE"];
            if (!isNull _smoke) then {_smoke setPosATL _lz};
            _smokeThrown = true;
            ["smoke",[_id,_lineage,_lz,round _distance]] call ITW_CLASH_CASEVAC_fnc_Log;
        };

        if (_distance <= 350) then {
            _heli limitSpeed 90;
            _heli flyInHeight 10;
        };
        if (_distance <= 150) then {_heli land "GET IN"};

        if (_distance <= 120 && {
            isTouchingGround _heli || {(getPosATL _heli)#2 < 2.5 && {abs speed _heli < 8}}
        }) then {
            _landed = true;
        };
    };

    if (!_landed || {isNull _group} || {isNull _heli} || {!alive _heli}) exitWith {};
    ["landed",[_id,_lineage,_lz]] call ITW_CLASH_CASEVAC_fnc_Log;

    // Stop LZPadFix from continuously reissuing landAt while passengers board.
    _group setVariable ["ITW_CLASH_CASEVAC_State","boarding"];
    private _boardResult = [
        "air",_id,_lineage,_group,_heli,ITW_CLASH_CASEVAC_BoardingTimeout
    ] call ITW_CLASH_EvacBoarding_fnc_Board;
    _boardResult params ["_loaded","_boardReason"];
    if (!_loaded) exitWith {
        [_id,_group,_boardReason,_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
    };

    ["loaded",[_id,_lineage,{alive _x} count units _group,typeOf _heli]] call ITW_CLASH_CASEVAC_fnc_Log;

    _group setVariable ["ITW_CLASH_CASEVAC_State","rtb"];
    private _latestEntry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
    if (_latestEntry isNotEqualTo [] && {(_latestEntry#5) isNotEqualTo []}) then {
        _returnPos = +(_latestEntry#5);
    };
    [_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_SendHeliHome;
    ["rtb",[_id,_lineage,_egressObjective,round (_heli distance2D _returnPos)]] call ITW_CLASH_CASEVAC_fnc_Log;

    private _returnDeadline = time + 300;
    private _returned = false;
    while {!_returned} do {
        sleep 2;
        if ((ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo []) then {
            _returned = true;
            continue;
        };
        if (isNull _heli || {!alive _heli} || {!canMove _heli} || {isNull driver _heli}) exitWith {
            [_id,_group,"aircraft-lost-rtb",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (time > _returnDeadline) exitWith {
            [_id,_group,"rtb-timeout",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        };
        if (_heli distance2D _returnPos <= 140) then {_returned = true};
    };

    if (_returned) then {
        private _waitForCanonical = time + 30;
        waitUntil {
            sleep 1;
            (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [] || {time > _waitForCanonical}
        };
        private _absorbed = (ITW_CLASH_Withdrawals getOrDefault [_id,[]]) isEqualTo [];

        if (!_absorbed && {!isNull _group} && {!isNull _heli} && {alive _heli}) then {
            ["rear-handoff-fallback",[
                _id,_lineage,_egressObjective,round (_heli distance2D _returnPos)
            ]] call ITW_CLASH_CASEVAC_fnc_Log;

            _heli land "GET OUT";
            private _landDeadline = time + 20;
            waitUntil {
                sleep 1;
                isNull _heli || {!alive _heli} || {
                    isTouchingGround _heli || {(getPosATL _heli)#2 < 2.5 || {time > _landDeadline}}
                }
            };

            if (!isNull _group && {!isNull _heli} && {alive _heli}) then {
                private _survivors = units _group select {alive _x};
                {
                    if (vehicle _x == _heli) then {
                        unassignVehicle _x;
                        _x action ["GetOut",_heli];
                    };
                } forEach _survivors;
                private _getOutDeadline = time + 15;
                waitUntil {
                    sleep 1;
                    isNull _group || {
                        (_survivors findIf {alive _x && {vehicle _x == _heli}}) < 0 || {time > _getOutDeadline}
                    }
                };
            };

            [_id,_group,"rear-absorption-timeout",_heli,_crewGroup,_returnPos] call ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal;
        } else {
            ["returned",[
                _id,_lineage,_egressObjective,_absorbed,
                if (isNull _heli) then {-1} else {round (_heli distance2D _returnPos)}
            ]] call ITW_CLASH_CASEVAC_fnc_Log;
            ITW_CLASH_CASEVAC_Active deleteAt _id;
            if (!isNull _group) then {
                _group setVariable ["ITW_CLASH_CASEVAC_State",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_Heli",nil];
                _group setVariable ["ITW_CLASH_CASEVAC_LZ",nil];
            };
            [_heli,_crewGroup,15] call ITW_CLASH_CASEVAC_fnc_CleanupHeli;
        };
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

        if (_veh distance2D _pickup <= 35 && {abs speed _veh < 8}) then {_arrived = true};
    };

    if (_failed || {!_arrived} || {isNull _group} || {isNull _veh} || {!alive _veh}) exitWith {};
    doStop (driver _veh);
    _veh limitSpeed 20;
    ["arrived-pickup",[_id,_lineage,_pickup,_rally,typeOf _veh]] call ITW_CLASH_GroundMEDEVAC_fnc_Log;

    _group setVariable ["ITW_CLASH_GroundMEDEVAC_State","boarding"];
    _group setVariable ["ITW_CLASH_CASEVAC_State","ground-boarding"];
    private _boardResult = [
        "ground",_id,_lineage,_group,_veh,ITW_CLASH_GroundMEDEVAC_BoardingTimeout
    ] call ITW_CLASH_EvacBoarding_fnc_Board;
    _boardResult params ["_loaded","_boardReason"];
    if (!_loaded) exitWith {
        [_id,_group,_boardReason,_veh,_crewGroup,_homePos] call ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal;
    };

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
            [_veh,_crewGroup,10] call ITW_CLASH_GroundMEDEVAC_fnc_CleanupVehicle;
        };
    };
};

diag_log format [
    "CLASH BOOT | evac-boarding-fix-ready | version=%1 shared=true repeatedDoMove=false",
    ITW_CLASH_EvacBoardingFixVersion
];
