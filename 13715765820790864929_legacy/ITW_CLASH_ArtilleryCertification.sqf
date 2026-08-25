#include "defines.hpp"

if (!isServer) exitWith {false};
if !(missionNamespace getVariable ["ITW_CLASH_CertificationMode",false]) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ArtilleryCertificationStarted",false]) exitWith {true};
ITW_CLASH_ArtilleryCertificationStarted = true;
ITW_CLASH_ArtilleryCertificationVersion = 1;
ITW_CLASH_CertificationResults = [];

ITW_CLASH_Certification_fnc_Record = {
    params ["_gate","_passed",["_details",[]]];
    private _status = if (_passed) then {"PASS"} else {"FAIL"};
    ITW_CLASH_CertificationResults pushBack [_gate,_status,_details,time];
    diag_log format ["CLASH CERT | %1 | %2 | %3",_status,_gate,_details];
    _passed
};

[] spawn {
    scriptName "ITW_CLASH_ArtillerySOFInterdictionCertification";
    diag_log "CLASH CERT | START | artillery-sof-interdiction-v1";
    private _deadline = time + 900;
    waitUntil {
        sleep 1;
        time >= _deadline || {
            missionNamespace getVariable ["ITW_CLASH_DualHALReady",false] && {
                missionNamespace getVariable ["ITW_CLASH_ForceGenerationReady",false] && {
                    missionNamespace getVariable ["ITW_CLASH_CapabilityPoolsReady",false]
                }
            }
        }
    };
    if (time >= _deadline) exitWith {
        ["BOOT_READY",false,["timeout",900]] call ITW_CLASH_Certification_fnc_Record;
        ITW_CLASH_CertificationComplete = true;
    };
    ["BOOT_READY",true,[]] call ITW_CLASH_Certification_fnc_Record;

    private _logicManaged = allGroups select {
        _x getVariable ["ITW_CLASH_DualHALManaged",false] && {
            ((units _x) findIf {!(_x isKindOf "Logic") && {!(_x isKindOf "VirtualMan_F")}}) < 0
        }
    };
    ["NO_SYSTEM_GROUP_ADMISSION",_logicManaged isEqualTo [],[_logicManaged]] call
        ITW_CLASH_Certification_fnc_Record;

    private _unknownReply = [
        "CERT_UNKNOWN",
        [ITW_PlayerSide] call ITW_CLASH_fnc_GetCommanderForSide,
        createHashMapFromArray [["side",ITW_PlayerSide]],
        "LOW"
    ] call ITW_CLASH_fnc_RequestCapability;
    [
        "CHECKBOOK_V2_TYPED_DENIAL",
        (_unknownReply getOrDefault ["schema",""]) == "ITW_CLASH_CHECKBOOK_RESULT_V2" && {
            (_unknownReply getOrDefault ["status",""]) == "DENIED"
        },
        [_unknownReply]
    ] call ITW_CLASH_Certification_fnc_Record;

    {
        _x params ["_label","_side"];
        private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
        private _node = [
            _side,"ARTILLERY","INTERSTITIAL",getPosATL leader _hq
        ] call ITW_CLASH_Generation_fnc_Resolve;
        private _nodeOK = (_node getOrDefault ["status",""]) == "RESOLVED" && {
            (_node getOrDefault ["rearBase",-1]) != (_node getOrDefault ["forwardBase",-1])
        };
        ["GENERATION_NODE_" + _label,_nodeOK,[_node]] call
            ITW_CLASH_Certification_fnc_Record;

        private _artDeadline = time + 360;
        waitUntil {
            sleep 2;
            time >= _artDeadline || {
                !isNull _hq && {
                    ([_hq getVariable ["RydHQ_ArtG",[]]] call
                        ITW_CLASH_Generation_fnc_UsableGroups) isNotEqualTo []
                }
            }
        };
        private _art = if (isNull _hq) then {[]} else {
            [_hq getVariable ["RydHQ_ArtG",[]]] call
                ITW_CLASH_Generation_fnc_UsableGroups
        };
        ["AI_ARTILLERY_FULFILLED_" + _label,_art isNotEqualTo [],[_art]] call
            ITW_CLASH_Certification_fnc_Record;

        private _outside = _art isNotEqualTo [] && {_nodeOK};
        if (_outside) then {
            private _vehPos = getPosATL (vehicle (leader (_art#0)));
            private _minimum = ITW_CLASH_GenerationSanctuaryRadius * 0.8;
            _outside = _vehPos distance2D (_node get "rearPosition") >= _minimum && {
                _vehPos distance2D (_node get "forwardPosition") >= _minimum
            };
        };
        ["ARTILLERY_OUTSIDE_NODE_SANCTUARIES_" + _label,_outside,[_node,_art]] call
            ITW_CLASH_Certification_fnc_Record;
    } forEach [
        ["FRIENDLY",ITW_PlayerSide],
        ["ENEMY",ITW_EnemySide]
    ];

    private _recognitionDeadline = time + 360;
    waitUntil {
        sleep 5;
        time >= _recognitionDeadline || {
            private _ready = true;
            {
                private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
                if (isNull _hq || {
                    (_hq getVariable ["RydHQ_EnArtG",[]]) isEqualTo []
                }) then {_ready = false};
            } forEach [ITW_PlayerSide,ITW_EnemySide];
            _ready
        }
    };

    {
        _x params ["_label","_side"];
        private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
        private _enemyArt = if (isNull _hq) then {[]} else {
            +(_hq getVariable ["RydHQ_EnArtG",[]])
        };
        private _sof = if (isNull _hq) then {[]} else {
            +(_hq getVariable ["RydHQ_SpecForG",[]])
        };
        ["ENEMY_ARTILLERY_RECOGNIZED_" + _label,_enemyArt isNotEqualTo [],[_enemyArt]] call
            ITW_CLASH_Certification_fnc_Record;
        ["SOF_INTERDICTION_ELIGIBLE_" + _label,
            _enemyArt isNotEqualTo [] && {_sof isNotEqualTo []},
            [_enemyArt,_sof]
        ] call ITW_CLASH_Certification_fnc_Record;
    } forEach [
        ["FRIENDLY",ITW_PlayerSide],
        ["ENEMY",ITW_EnemySide]
    ];

    private _failed = ITW_CLASH_CertificationResults select {_x#1 == "FAIL"};
    ITW_CLASH_CertificationSummary = createHashMapFromArray [
        ["suite","artillery-sof-interdiction-v1"],
        ["passed",_failed isEqualTo []],
        ["passCount",{_x#1 == "PASS"} count ITW_CLASH_CertificationResults],
        ["failCount",count _failed],
        ["results",+ITW_CLASH_CertificationResults],
        ["completedAt",time]
    ];
    ITW_CLASH_CertificationComplete = true;
    publicVariable "ITW_CLASH_CertificationComplete";
    diag_log format [
        "CLASH CERT | COMPLETE | passed=%1 pass=%2 fail=%3",
        ITW_CLASH_CertificationSummary get "passed",
        ITW_CLASH_CertificationSummary get "passCount",
        ITW_CLASH_CertificationSummary get "failCount"
    ];
};

true
