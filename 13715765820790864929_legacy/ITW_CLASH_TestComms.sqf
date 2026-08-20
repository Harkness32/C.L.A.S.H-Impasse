if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_TestCommsStarted",false]) exitWith {true};
ITW_CLASH_TestCommsStarted = true;
ITW_CLASH_TestCommsVersion = 1;
ITW_CLASH_TestCommsEnabled = true;
ITW_CLASH_TestCommsRecoveryRequestCooldown = 90;
ITW_CLASH_TestCommsPollInterval = 0.5;

/*
    Temporary testing comms surface.

    This deliberately does not alter HAL ownership, tasking, radio density, or
    faction/side relationships. C.L.A.S.H. mirrors a very small event whitelist
    to GLOBAL so a BLUFOR tester can hear what an OPFOR HAL formation is doing.

    Audio reuses NR6 HAL's own CfgRadio recordings. No sound assets are copied or
    redefined here. The observer below only reads existing C.L.A.S.H./HAL states;
    it does not wrap or replace any recovery, withdrawal, recon, or HAL function.
    Remove/disable this module when the observer testing phase is complete.
*/

ITW_CLASH_TestComms_fnc_RadioPool = {
    params ["_kind"];
    private _pool = [];

    switch (_kind) do {
        case "medevac-request": {
            if (!isNil "RydxHQ_AIC_MedReq" && {RydxHQ_AIC_MedReq isEqualType []}) then {
                _pool = +RydxHQ_AIC_MedReq;
            } else {
                _pool = [
                    "HAC_MedReq1","HAC_MedReq2","HAC_MedReq3",
                    "HAC_MedReq4","HAC_MedReq5"
                ];
            };
        };
        case "recon-tasking": {
            // Native GoRecon has the selected scout leader acknowledge the
            // commander's order with OrdConf. Mirror that same HAL voice family
            // globally while the readable line identifies the actual task.
            if (!isNil "RydxHQ_AIC_OrdConf" && {RydxHQ_AIC_OrdConf isEqualType []}) then {
                _pool = +RydxHQ_AIC_OrdConf;
            } else {
                _pool = [
                    "HAC_OrdConf1","HAC_OrdConf2","HAC_OrdConf3",
                    "HAC_OrdConf4","HAC_OrdConf5"
                ];
            };
        };
    };

    _pool select {
        _x isEqualType "" && {
            isClass (configFile >> "CfgRadio" >> _x)
        }
    }
};

ITW_CLASH_TestComms_fnc_Broadcast = {
    params [
        "_event","_textSpeaker","_radioSpeaker","_text",["_radioPool",[]]
    ];
    if (!ITW_CLASH_TestCommsEnabled) exitWith {false};

    if (!isNull _textSpeaker && {_text isNotEqualTo ""}) then {
        if (isMultiplayer) then {
            [_textSpeaker,_text] remoteExecCall ["globalChat",0];
        } else {
            _textSpeaker globalChat _text;
        };
    };

    private _sentence = "";
    if (!isNull _radioSpeaker && {_radioPool isNotEqualTo []}) then {
        _sentence = selectRandom _radioPool;
        if (isMultiplayer) then {
            [_radioSpeaker,_sentence] remoteExecCall ["globalRadio",0];
        } else {
            _radioSpeaker globalRadio _sentence;
        };
    };

    diag_log format [
        "CLASH COMMS | %1 | textSpeaker=%2 radioSpeaker=%3 radio=%4 text=%5",
        _event,
        if (isNull _textSpeaker) then {"<null>"} else {typeOf _textSpeaker},
        if (isNull _radioSpeaker) then {"<null>"} else {typeOf _radioSpeaker},
        _sentence,
        _text
    ];
    true
};

ITW_CLASH_TestComms_fnc_RecoveryRequest = {
    params [
        "_group","_id",["_mode","ground"],["_survivors",0],["_egressDistance",-1]
    ];
    if (!ITW_CLASH_TestCommsEnabled || {isNull _group}) exitWith {false};

    private _last = _group getVariable ["ITW_CLASH_TestComms_LastRecoveryRequest",-1e10];
    if (time - _last < ITW_CLASH_TestCommsRecoveryRequestCooldown) exitWith {false};
    _group setVariable ["ITW_CLASH_TestComms_LastRecoveryRequest",time];

    private _speaker = leader _group;
    if (isNull _speaker) exitWith {false};
    private _modeText = if (toLowerANSI _mode isEqualTo "air") then {
        "CASEVAC"
    } else {
        "GROUND MEDEVAC"
    };
    private _text = format [
        "[C.L.A.S.H TEST] %1: Command, requesting %2. Survivors: %3 | rear: %4m",
        _id,_modeText,_survivors,round _egressDistance
    ];
    private _pool = ["medevac-request"] call ITW_CLASH_TestComms_fnc_RadioPool;

    [
        "recovery-request",_speaker,_speaker,_text,_pool
    ] call ITW_CLASH_TestComms_fnc_Broadcast
};

ITW_CLASH_TestComms_fnc_ReconTasking = {
    params [
        "_group","_hq",["_mode","offensive"],["_family","sof"],["_destination",[]]
    ];
    if (!ITW_CLASH_TestCommsEnabled || {isNull _group}) exitWith {false};

    private _scout = leader _group;
    if (isNull _scout) exitWith {false};

    private _commander = objNull;
    if (!isNil "ITW_CLASH_HALLeader" && {!isNull ITW_CLASH_HALLeader}) then {
        _commander = ITW_CLASH_HALLeader;
    } else {
        if (!isNull _hq) then {_commander = leader _hq};
    };
    if (isNull _commander) then {_commander = _scout};

    private _id = if (!isNil "ITW_CLASH_fnc_GroupId") then {
        [_group] call ITW_CLASH_fnc_GroupId
    } else {
        str _group
    };
    private _distance = if (_destination isEqualTo []) then {-1} else {
        round (_scout distance2D _destination)
    };
    private _distanceText = if (_distance < 0) then {""} else {
        format [" | %1m",_distance]
    };
    private _text = format [
        "[C.L.A.S.H TEST] HAL: RECON TASKING | %1 (%2) | %3%4",
        _id,toUpperANSI _family,toUpperANSI _mode,_distanceText
    ];
    private _pool = ["recon-tasking"] call ITW_CLASH_TestComms_fnc_RadioPool;

    [
        "recon-tasking",_commander,_scout,_text,_pool
    ] call ITW_CLASH_TestComms_fnc_Broadcast
};

// Observer-only transition mirror. Recovery chatter is keyed to an actual
// inbound state, so the audible request means a recovery asset has genuinely
// committed. Recon chatter is keyed to Recon Phase 0's active-mission registry.
[] spawn {
    scriptName "ITW_CLASH_TestCommsObserver";

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep ITW_CLASH_TestCommsPollInterval;
        if (!ITW_CLASH_TestCommsEnabled) then {continue};

        if (!isNil "ITW_CLASH_Withdrawals") then {
            {
                private _id = _x;
                private _entry = ITW_CLASH_Withdrawals getOrDefault [_id,[]];
                if (_entry isEqualTo [] || {count _entry < 9}) then {continue};
                private _group = _entry#0;
                if (isNull _group || {{alive _x} count units _group == 0}) then {continue};

                private _groundState = _group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""];
                private _casevacState = _group getVariable ["ITW_CLASH_CASEVAC_State",""];
                private _mode = "";
                if (_groundState isEqualTo "inbound" || {_casevacState isEqualTo "ground-inbound"}) then {
                    _mode = "ground";
                } else {
                    if (_casevacState isEqualTo "inbound") then {_mode = "air"};
                };

                private _stateToken = if (_mode isEqualTo "") then {""} else {
                    format ["%1-inbound",_mode]
                };
                private _lastState = _group getVariable ["ITW_CLASH_TestComms_LastRecoveryState",""];
                if !(_stateToken isEqualTo _lastState) then {
                    _group setVariable ["ITW_CLASH_TestComms_LastRecoveryState",_stateToken];
                    if (_stateToken isNotEqualTo "") then {
                        private _survivors = {alive _x} count units _group;
                        private _rearDistance = if ((_entry#5) isEqualTo []) then {-1} else {
                            leader _group distance2D (_entry#5)
                        };
                        [
                            _group,_id,_mode,_survivors,_rearDistance
                        ] call ITW_CLASH_TestComms_fnc_RecoveryRequest;
                    };
                };
            } forEach +(keys ITW_CLASH_Withdrawals);
        };

        if (!isNil "ITW_CLASH_ReconActiveGroups") then {
            {
                private _entry = ITW_CLASH_ReconActiveGroups getOrDefault [_x,[]];
                if (_entry isEqualTo [] || {count _entry < 3}) then {continue};
                _entry params ["_group","_mode","_startedAt"];
                if (isNull _group || {{alive _x} count units _group == 0}) then {continue};

                private _announcedAt = _group getVariable ["ITW_CLASH_TestComms_ReconAnnouncedAt",-1];
                if (_announcedAt isEqualTo _startedAt) then {continue};
                _group setVariable ["ITW_CLASH_TestComms_ReconAnnouncedAt",_startedAt];

                private _family = _group getVariable ["ITW_CLASH_ReconSOFFamily","sof"];
                private _hq = if (!isNil "ITW_CLASH_HALHQ") then {ITW_CLASH_HALHQ} else {grpNull};
                [
                    _group,_hq,_mode,_family,[]
                ] call ITW_CLASH_TestComms_fnc_ReconTasking;
            } forEach +(keys ITW_CLASH_ReconActiveGroups);
        };
    };

    ITW_CLASH_TestCommsStarted = false;
    diag_log "CLASH BOOT | test-comms-stopped";
};

diag_log format [
    "CLASH BOOT | test-comms-ready | version=%1 global=true halRadio=true observerOnly=true poll=%2 recoveryCooldown=%3 events=recovery-request,recon-tasking",
    ITW_CLASH_TestCommsVersion,
    ITW_CLASH_TestCommsPollInterval,
    ITW_CLASH_TestCommsRecoveryRequestCooldown
];
true
