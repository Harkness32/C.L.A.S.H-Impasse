#include "defines.hpp"

if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_OneZeroHardeningStarted",false]) exitWith {};
ITW_CLASH_OneZeroHardeningStarted = true;
ITW_CLASH_OneZeroHardeningVersion = 1;

ITW_CLASH_GTFO_PhysicalStallGrace = 180;
ITW_CLASH_GTFO_PhysicalStallCloser = 50;
ITW_CLASH_GTFO_PhysicalStallMoved = 100;
ITW_CLASH_GTFO_PhysicalStallPoll = 15;
ITW_CLASH_OneZeroGTFOProgress = createHashMap;

ITW_CLASH_OneZero_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["one-zero-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH 1.0 | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_OneZero_fnc_WaitFor = {
    params ["_predicate",["_timeout",180]];
    private _deadline = time + _timeout;
    waitUntil {
        sleep 0.25;
        (call _predicate) || {time >= _deadline}
    };
    call _predicate
};

/*
    Recovery failure handback sequencing.

    The v2 GTFO runtime requested a fresh HAL_GoRest before the canonical
    CASEVAC/Ground-MEDEVAC ResumeWithdrawal function had cleared its recovery
    state and reissued the withdrawal handback. The burn-in run proved this seam
    is exercised repeatedly. Replace only that wrapper order:

        canonical recovery unwind -> native HAL rest restart request

    ITW_CLASH_GTFO_fnc_CASEVACResumeBase / GroundResumeBase are the saved
    pre-GTFO wrappers, so existing assignment cleanup remains in the chain.
*/
[] spawn {
    scriptName "ITW_CLASH_OneZero_RecoveryHandbackOrder";

    private _ready = [{
        missionNamespace getVariable ["ITW_CLASH_GTFORuntimeStarted",false] &&
        {!isNil "ITW_CLASH_GTFO_fnc_CASEVACResumeBase"} &&
        {!isNil "ITW_CLASH_GTFO_fnc_GroundResumeBase"} &&
        {!isNil "ITW_CLASH_GTFO_fnc_RequestNativeRestRestart"}
    }] call ITW_CLASH_OneZero_fnc_WaitFor;

    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | one-zero-recovery-handback-timeout";
    };
    if (missionNamespace getVariable ["ITW_CLASH_OneZeroRecoveryHandbackReady",false]) exitWith {};

    ITW_CLASH_CASEVAC_fnc_ResumeWithdrawal = {
        private _group = _this param [1,grpNull];
        private _reason = _this param [2,"unknown"];
        private _result = _this call ITW_CLASH_GTFO_fnc_CASEVACResumeBase;
        ["air",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        _result
    };

    ITW_CLASH_GroundMEDEVAC_fnc_ResumeWithdrawal = {
        private _group = _this param [1,grpNull];
        private _reason = _this param [2,"unknown"];
        private _result = _this call ITW_CLASH_GTFO_fnc_GroundResumeBase;
        ["ground",_group,_reason] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        _result
    };

    ITW_CLASH_OneZeroRecoveryHandbackReady = true;
    diag_log "CLASH BOOT | one-zero-recovery-handback-ready | canonicalUnwindBeforeGoRest=true";
};

/*
    GTFO physical-progress watchdog.

    The existing runtime restart detector intentionally watched the narrow
    Busy=true / Resting=false deadlock. The 36m55s burn-in produced two stronger
    failures: groups could remain in a perfectly valid native Resting state while
    making no physical progress for 20-26+ minutes.

    This observer is state-agnostic. It never creates a waypoint and never clears
    Busy/Resting. If a managed GTFO group neither moves materially nor gets
    materially closer to its immutable rear destination for three minutes, it
    asks the existing bridge to cancel/relaunch HAL's native GoRest.
*/
[] spawn {
    scriptName "ITW_CLASH_OneZero_GTFOPhysicalProgress";

    private _ready = [{
        missionNamespace getVariable ["ITW_CLASH_GTFORuntimeStarted",false] &&
        {!isNil "ITW_CLASH_GTFO_fnc_RequestNativeRestRestart"}
    }] call ITW_CLASH_OneZero_fnc_WaitFor;

    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | one-zero-gtfo-physical-watch-timeout";
    };

    diag_log format [
        "CLASH BOOT | one-zero-gtfo-physical-watch-ready | grace=%1 closer=%2 moved=%3 poll=%4 nativeRestartOnly=true",
        ITW_CLASH_GTFO_PhysicalStallGrace,
        ITW_CLASH_GTFO_PhysicalStallCloser,
        ITW_CLASH_GTFO_PhysicalStallMoved,
        ITW_CLASH_GTFO_PhysicalStallPoll
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_GTFO_PhysicalStallPoll;
        private _activeKeys = [];

        {
            private _group = _x;
            if (isNull _group || {
                !(_group getVariable ["ITW_CLASH_Managed",false]) || {
                    !(_group getVariable ["ITW_CLASH_GTFO",false])
                }
            }) then {continue};

            private _id = [_group] call ITW_CLASH_fnc_GroupId;
            _activeKeys pushBack _id;

            if (
                (_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo "" ||
                {(_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""} ||
                {_group getVariable ["ITW_CLASH_GTFO_RestRestartPending",false]}
            ) then {
                ITW_CLASH_OneZeroGTFOProgress deleteAt _id;
                continue;
            };

            private _destination = _group getVariable ["ITW_CLASH_GTFO_Destination",[]];
            private _leader = leader _group;
            if (_destination isEqualTo [] || {isNull _leader} || {!alive _leader}) then {
                ITW_CLASH_OneZeroGTFOProgress deleteAt _id;
                continue;
            };

            private _distance = _leader distance2D _destination;
            private _arrivalRadius = missionNamespace getVariable [
                "ITW_CLASH_GTFO_ArrivalRadius",
                missionNamespace getVariable ["ITW_CLASH_WithdrawalArrivalRadius",160]
            ];
            if (_distance <= _arrivalRadius) then {
                ITW_CLASH_OneZeroGTFOProgress deleteAt _id;
                continue;
            };

            private _position = getPosATL _leader;
            private _sample = ITW_CLASH_OneZeroGTFOProgress getOrDefault [_id,[]];
            if (_sample isEqualTo []) then {
                ITW_CLASH_OneZeroGTFOProgress set [_id,[time,_distance,+_position]];
                continue;
            };

            _sample params ["_sampleAt","_sampleDistance","_samplePosition"];
            private _closer = (_sampleDistance - _distance) >= ITW_CLASH_GTFO_PhysicalStallCloser;
            private _moved = (_position distance2D _samplePosition) >= ITW_CLASH_GTFO_PhysicalStallMoved;

            if (_closer || {_moved}) then {
                ITW_CLASH_OneZeroGTFOProgress set [_id,[time,_distance,+_position]];
                continue;
            };

            private _stalledFor = time - _sampleAt;
            if (_stalledFor < ITW_CLASH_GTFO_PhysicalStallGrace) then {continue};

            ITW_CLASH_OneZeroGTFOProgress set [_id,[time,_distance,+_position]];
            ["gtfo-physical-stall",[
                _id,
                round _stalledFor,
                round _distance,
                round _sampleDistance,
                round (_position distance2D _samplePosition),
                _group getVariable ["Busy" + str _group,false],
                _group getVariable ["Resting" + str _group,false],
                currentCommand _leader,
                unitReady _leader
            ]] call ITW_CLASH_OneZero_fnc_Log;

            [
                "physical-stall",
                _group,
                format ["physical-no-progress-%1s",round _stalledFor]
            ] call ITW_CLASH_GTFO_fnc_RequestNativeRestRestart;
        } forEach +ITW_CLASH_ManagedGroups;

        {
            if !(_x in _activeKeys) then {
                ITW_CLASH_OneZeroGTFOProgress deleteAt _x;
            };
        } forEach +(keys ITW_CLASH_OneZeroGTFOProgress);
    };
};

/*
    Native HAL GoCapture state guard.

    HAL HQOrders normally seeds target "Capturing..." state before spawning
    HAL_GoCapture. The burn-in nevertheless reached GoCapture's water/cleanup
    exit with that variable nil, where upstream code immediately does
    `_isAttacked select 1` and throws. Repair only malformed/missing bookkeeping
    immediately before invoking the untouched native executor.
*/
[] spawn {
    scriptName "ITW_CLASH_OneZero_GoCaptureStateGuard";

    private _ready = [{
        missionNamespace getVariable ["ITW_CLASH_HALReady",false] &&
        {!isNil "HAL_GoCapture"}
    }] call ITW_CLASH_OneZero_fnc_WaitFor;

    if (!_ready) exitWith {
        diag_log "CLASH BOOT | WARNING | one-zero-gocapture-guard-timeout";
    };
    if (missionNamespace getVariable ["ITW_CLASH_OneZeroGoCaptureGuardReady",false]) exitWith {};

    ITW_CLASH_OneZero_fnc_NativeGoCapture = HAL_GoCapture;

    HAL_GoCapture = {
        private _group = _this param [0,grpNull];
        private _passedSlot = _this param [1,0];
        private _hq = _this param [2,grpNull];
        private _target = _this param [3,objNull];

        if (!isNull _group && {!isNull _hq} && {!isNull _target}) then {
            private _key = "Capturing" + str _target + str _hq;
            private _state = _target getVariable [_key,[]];
            private _valid = _state isEqualType [] && {
                count _state >= 2 && {
                    (_state#0) isEqualType 0 && {(_state#1) isEqualType 0}
                }
            };

            if (!_valid) then {
                private _slot = if (_passedSlot isEqualType 0) then {
                    _passedSlot max 0
                } else {
                    0
                };
                private _seed = [_slot + 1,count units _group];
                _target setVariable [_key,_seed];

                ["hal-capture-state-repaired",[
                    [_group] call ITW_CLASH_fnc_GroupId,
                    _slot,
                    _seed,
                    str _target,
                    [_hq] call ITW_CLASH_fnc_GroupId
                ]] call ITW_CLASH_OneZero_fnc_Log;
            };
        };

        _this call ITW_CLASH_OneZero_fnc_NativeGoCapture
    };

    ITW_CLASH_OneZeroGoCaptureGuardReady = true;
    diag_log "CLASH BOOT | one-zero-gocapture-guard-ready | malformedCapturingStateRepaired=true nativeExecutorPreserved=true";
};

diag_log format [
    "CLASH BOOT | one-zero-hardening-started | version=%1 recoveryOrder=true gtfoPhysicalWatch=true goCaptureGuard=true",
    ITW_CLASH_OneZeroHardeningVersion
];
