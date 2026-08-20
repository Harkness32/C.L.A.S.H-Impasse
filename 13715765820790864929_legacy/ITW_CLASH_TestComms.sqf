if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_TestCommsStarted",false]) exitWith {true};
ITW_CLASH_TestCommsStarted = true;
ITW_CLASH_TestCommsVersion = 1;
ITW_CLASH_TestCommsEnabled = true;
ITW_CLASH_TestCommsRecoveryRequestCooldown = 90;

/*
    Temporary testing comms surface.

    This deliberately does not alter HAL ownership, tasking, radio density, or
    faction/side relationships. C.L.A.S.H. mirrors a very small event whitelist
    to GLOBAL so a BLUFOR tester can hear what an OPFOR HAL formation is doing.

    Audio reuses NR6 HAL's own CfgRadio recordings. No sound assets are copied or
    redefined here. Remove/disable this module when the observer testing phase is
    complete.
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
    private _text = format [
        "[C.L.A.S.H TEST] HAL: RECON TASKING | %1 (%2) | %3 | %4m",
        _id,toUpperANSI _family,toUpperANSI _mode,_distance
    ];
    private _pool = ["recon-tasking"] call ITW_CLASH_TestComms_fnc_RadioPool;

    [
        "recon-tasking",_commander,_scout,_text,_pool
    ] call ITW_CLASH_TestComms_fnc_Broadcast
};

diag_log format [
    "CLASH BOOT | test-comms-ready | version=%1 global=true halRadio=true recoveryCooldown=%2 events=recovery-request,recon-tasking",
    ITW_CLASH_TestCommsVersion,
    ITW_CLASH_TestCommsRecoveryRequestCooldown
];
true
