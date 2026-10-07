if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_FormationAdmissionStarted",false]) exitWith {true};

if (isNil "ITW_CLASH_DualHAL_fnc_RegisterGroup") exitWith {
    diag_log "CLASH BOOT | FAILED | formation-admission-register-missing";
    false
};

ITW_CLASH_FormationAdmissionStarted = true;
ITW_CLASH_FormationAdmissionVersion = 2;
ITW_CLASH_FormationAdmissionMinCombatSize = missionNamespace getVariable [
    "ITW_CLASH_FormationAdmissionMinCombatSize",4
];
ITW_CLASH_FormationAdmissionStableSeconds = missionNamespace getVariable [
    "ITW_CLASH_FormationAdmissionStableSeconds",6
];
ITW_CLASH_FormationAdmissionAuditSeconds = missionNamespace getVariable [
    "ITW_CLASH_FormationAdmissionAuditSeconds",10
];
ITW_CLASH_FormationAdmissionAssertRepeat = missionNamespace getVariable [
    "ITW_CLASH_FormationAdmissionAssertRepeat",60
];
ITW_CLASH_FormationAdmissionBanks = createHashMap;
ITW_CLASH_FormationAdmissionBankSerial = 0;
ITW_CLASH_FormationAdmissionBankRetryAt = createHashMap;
ITW_CLASH_FormationAdmissionLastAudit = -1000;
ITW_CLASH_FormationAdmissionLastBankRetry = -1000;
ITW_CLASH_FormationAdmissionBankRetrySeconds = missionNamespace getVariable [
    "ITW_CLASH_FormationAdmissionBankRetrySeconds",10
];

ITW_CLASH_FormationAdmission_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    if (!isNil "ITW_CLASH_DualHAL_fnc_GroupId") exitWith {
        [_group] call ITW_CLASH_DualHAL_fnc_GroupId
    };
    str _group
};

ITW_CLASH_FormationAdmission_fnc_Log = {
    params ["_event",["_payload",[]]];
    diag_log format ["CLASH FORMATION | %1 | %2",_event,_payload];
};

ITW_CLASH_FormationAdmission_fnc_Assert = {
    params ["_event",["_payload",[]]];
    diag_log format ["CLASH ASSERT | %1 | %2",_event,_payload];
};

ITW_CLASH_FormationAdmission_fnc_SideKey = {
    params ["_side"];
    if (!isNil "ITW_CLASH_DualHAL_fnc_SideKey") exitWith {
        [_side] call ITW_CLASH_DualHAL_fnc_SideKey
    };
    toUpperANSI str _side
};

ITW_CLASH_FormationAdmission_fnc_AliveMen = {
    params ["_group"];
    if (isNull _group) exitWith {[]};
    (units _group) select {alive _x && {_x isKindOf "CAManBase"}}
};

ITW_CLASH_FormationAdmission_fnc_IsSpecialist = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    if (_group getVariable ["ITW_CLASH_FormationAdmissionExempt",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_VehicleCrewGroup",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_HALTransportOnly",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_CheckbookAsset",false]) exitWith {true};

    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    if (_alive isEqualTo []) exitWith {false};

    private _classes = [];
    {
        private _pool = missionNamespace getVariable [_x,[]];
        if (_pool isEqualType []) then {
            {
                if (_x isEqualType "") then {
                    _classes pushBackUnique (toLowerANSI _x);
                };
            } forEach _pool;
        };
    } forEach [
        "RHQ_Snipers","RHQ_Recon","RHQ_SpecFor","RHQ_FO",
        "RHQ_ATInf","RHQ_AAInf",
        "RYD_WS_snipers_class","RYD_WS_recon_class","RYD_WS_specFor_class",
        "RYD_WS_FO_class","RYD_WS_ATinf_class","RYD_WS_AAinf_class"
    ];

    if (_classes isEqualTo []) exitWith {false};
    (_alive findIf {
        !((toLowerANSI typeOf _x) in _classes)
    }) < 0
};

ITW_CLASH_FormationAdmission_fnc_IsOrdinaryInfantry = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    if ([_group] call ITW_CLASH_FormationAdmission_fnc_IsSpecialist) exitWith {false};
    if (_group getVariable ["ITW_CLASH_DeploymentRemnant",false]) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};

    private _alive = (units _group) select {alive _x};
    if (_alive isEqualTo []) exitWith {false};
    if ((_alive findIf {!(_x isKindOf "CAManBase")}) >= 0) exitWith {false};
    if ((_alive findIf {vehicle _x != _x}) >= 0) exitWith {false};
    true
};

ITW_CLASH_FormationAdmission_fnc_TransitionReason = {
    params ["_group"];
    if (isNull _group) exitWith {"null-group"};
    if (_group getVariable ["ITW_CLASH_VehicleCrewGroup",false]) exitWith {"vehicle-crew-group"};
    if (_group getVariable ["itwInitGrp",false]) exitWith {"itw-init-group"};
    if (_group getVariable ["itwDelivery",false]) exitWith {"itw-delivery"};
    if (_group getVariable ["ITW_CLASH_ReconstitutionTransit",false]) exitWith {"reconstitution-transit"};
    if (_group getVariable ["ITW_CLASH_AuthorityHold",false]) exitWith {"authority-hold"};

    private _alive = (units _group) select {alive _x};
    if ((_alive findIf {
        _x getVariable ["ITW_CLASH_VehicleCrewUnit",false]
    }) >= 0) exitWith {"vehicle-crew-unit"};
    if ((_alive findIf {vehicle _x != _x}) >= 0) exitWith {"already-mounted"};
    if ((_alive findIf {!isNull assignedVehicle _x}) >= 0) exitWith {"assigned-vehicle"};
    if ((_alive findIf {
        (toUpperANSI (currentCommand _x)) in ["GET IN","GETIN"]
    }) >= 0) exitWith {"get-in-command"};

    ""
};

ITW_CLASH_FormationAdmission_fnc_MembershipSignature = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    private _ids = ((units _group) select {alive _x}) apply {
        private _id = netId _x;
        if (_id isEqualTo "") then {str _x} else {_id}
    };
    _ids sort true;
    str _ids
};

// Bank entries: key -> [side,baseIndex,spawnPos,unitSnapshots,objectiveIndex].
// Snapshots free Impasse AI-cap slots immediately; no field combat groups are
// moved or deleted. On failed provisional admission no snapshots are consumed.
ITW_CLASH_FormationAdmission_fnc_IssueBank = {
    params ["_key"];
    private _entry = ITW_CLASH_FormationAdmissionBanks getOrDefault [_key,[]];
    if (_entry isEqualTo []) exitWith {0};
    _entry params ["_side","_baseIndex","_spawnPos","_records","_objectiveIndex"];
    private _issued = 0;
    private _retry = true;

    while {
        _retry && {count _records >= ITW_CLASH_FormationAdmissionMinCombatSize}
    } do {
        private _release = _records select [
            0,ITW_CLASH_FormationAdmissionMinCombatSize
        ];
        private _newGroup = createGroup [_side,false];
        private _created = [];
        private _accepted = false;

        if (!isNull _newGroup) then {
            {
                _x params [
                    "_class","_loadout","_skill","_rank",
                    "_face","_speaker","_sourceId"
                ];
                private _unit = _newGroup createUnit [
                    _class,_spawnPos,[],3,"NONE"
                ];
                if (!isNull _unit) then {
                    _unit setUnitLoadout _loadout;
                    _unit setSkill _skill;
                    _unit setRank _rank;
                    if (_face isNotEqualTo "") then {_unit setFace _face};
                    if (_speaker isNotEqualTo "") then {
                        _unit setSpeaker _speaker
                    };
                    _created pushBack _unit;
                };
            } forEach _release;

            if (count _created == ITW_CLASH_FormationAdmissionMinCombatSize) then {
                ITW_CLASH_FormationAdmissionBankSerial =
                    ITW_CLASH_FormationAdmissionBankSerial + 1;
                private _lineage = format [
                    "PROVISIONAL-%1-%2",
                    _key,ITW_CLASH_FormationAdmissionBankSerial
                ];
                private _archetype = _created apply {toLowerANSI typeOf _x};
                _newGroup setVariable [
                    "ITW_CLASH_ProvisionalFormation",true,true
                ];
                _newGroup setVariable ["ITW_CLASH_Archetype",+_archetype,true];
                _newGroup setVariable ["ITW_CLASH_Lineage",_lineage,true];
                _newGroup setVariable [
                    "ITW_CLASH_DualHALObjectiveAffinity",_objectiveIndex
                ];
                _newGroup setVariable [
                    "ITW_CLASH_FormationAdmissionExempt",true
                ];
                _accepted = [
                    _newGroup,"deployment-remnant-provisional"
                ] call ITW_CLASH_DualHAL_fnc_RegisterGroup;
                _newGroup setVariable [
                    "ITW_CLASH_FormationAdmissionExempt",nil
                ];

                ["remnant-issue-attempt",[
                    _key,[_newGroup] call
                        ITW_CLASH_FormationAdmission_fnc_GroupId,
                    _lineage,count _created,_archetype,_accepted
                ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            };
        };

        if (_accepted) then {
            _records deleteRange [
                0,ITW_CLASH_FormationAdmissionMinCombatSize
            ];
            _issued = _issued + 1;
            ["remnant-issued",[
                _key,ITW_CLASH_FormationAdmissionMinCombatSize,
                count _records
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            { _x addCuratorEditableObjects [_created,true] } forEach allCurators;
        } else {
            // No money/personnel loss on missing HQ, group cap, spawn failure,
            // or rejected admission. The original snapshots remain banked.
            {deleteVehicle _x} forEach _created;
            if (!isNull _newGroup) then {deleteGroup _newGroup};
            private _nextLog = ITW_CLASH_FormationAdmissionBankRetryAt
                getOrDefault [_key,0];
            if (time >= _nextLog) then {
                ITW_CLASH_FormationAdmissionBankRetryAt set [
                    _key,time + 30
                ];
                ["remnant-issue-deferred",[
                    _key,count _created,count _records,
                    "no-admission-or-spawn-capacity"
                ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            };
            _retry = false;
        };
    };

    _entry set [3,_records];
    ITW_CLASH_FormationAdmissionBanks set [_key,_entry];
    _issued
};

ITW_CLASH_FormationAdmission_fnc_Bank = {
    params ["_group",["_source","unknown"],["_context",[]]];
    if (isNull _group || {!local _group}) exitWith {false};
    if !([_group] call ITW_CLASH_FormationAdmission_fnc_IsOrdinaryInfantry) exitWith {
        false
    };

    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    if (_alive isEqualTo []) exitWith {false};
    if (_source isEqualTo "runtime-existing-field" && {
        (_group getVariable ["ITW_CLASH_ProducedBatch",""]) isEqualTo ""
        && {((_alive#0) getVariable ["ITW_CLASH_ProducerBatch",""])
            isEqualTo ""}
    }) exitWith {false};

    if (_context isEqualTo []) then {
        _context = +(_group getVariable [
            "ITW_CLASH_FormationAdmissionContext",[]
        ]);
    };
    if (_context isEqualTo [] && {
        !isNil "ITW_CLASH_DualHAL_fnc_GetSupportSpawn"
    }) then {
        _context = [
            side _group,"GROUND",getPosATL leader _group
        ] call ITW_CLASH_DualHAL_fnc_GetSupportSpawn;
    };
    if !(_context isEqualType [] && {count _context >= 4}) exitWith {
        ["remnant-bank-deferred",[
            [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
            _source,"support-node-unavailable"
        ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        false
    };

    _context params [
        "_spawnPos","_baseIndex","_objectiveIndex","_spawnSource"
    ];
    if (_spawnPos isEqualTo []) exitWith {false};
    private _side = side _group;
    private _key = format [
        "%1|base:%2",
        [_side] call ITW_CLASH_FormationAdmission_fnc_SideKey,
        _baseIndex
    ];
    // An unresolved base is never allowed to collect an entire side.
    if (_baseIndex < 0) then {
        _key = format ["%1|zone:%2|objective:%3",
            [_side] call ITW_CLASH_FormationAdmission_fnc_SideKey,
            missionNamespace getVariable ["ITW_ZoneIndex",-1],
            _objectiveIndex
        ];
    };

    private _entry = ITW_CLASH_FormationAdmissionBanks getOrDefault
        [_key,[_side,_baseIndex,+_spawnPos,[],_objectiveIndex]];
    private _records = +(_entry#3);
    private _before = count _records;
    private _id = [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId;
    private _newRecords = [];
    {
        _newRecords pushBack [
            typeOf _x,
            getUnitLoadout _x,
            skill _x,
            rank _x,
            face _x,
            speaker _x,
            _id
        ];
    } forEach _alive;
    if (count _newRecords != count _alive) exitWith {false};

    _records append _newRecords;
    _entry set [3,_records];
    ITW_CLASH_FormationAdmissionBanks set [_key,_entry];
    _group setVariable ["ITW_CLASH_DeploymentRemnant",true,true];
    _group setVariable ["ITW_CLASH_ExcludeHAL",true,true];
    _group setVariable ["ITW_CLASH_FormationAdmissionBanked",true,true];

    ["remnant-banked",[
        _id,_side,_source,count _alive,
        _before,count _records,_alive apply {typeOf _x},
        _key,_baseIndex,_objectiveIndex,_spawnSource
    ]] call ITW_CLASH_FormationAdmission_fnc_Log;

    // Only source-confirmed *fresh* deployment fragments enter this bank.
    // Virtualization prevents three idle tail units from blocking Impasse's
    // next spawn attempt at a tight AI population cap.
    {deleteVehicle _x} forEach _alive;
    if (units _group isEqualTo []) then {deleteGroup _group};

    [_key] call ITW_CLASH_FormationAdmission_fnc_IssueBank;
    true
};

ITW_CLASH_FormationAdmission_fnc_ProducerInfo = {
    params ["_group"];
    if (isNull _group) exitWith {["",0,0,false]};
    private _members = units _group;
    if (_members isEqualTo []) exitWith {["",0,0,false]};

    private _batch = _group getVariable [
        "ITW_CLASH_ProducedBatch",
        (_members#0) getVariable ["ITW_CLASH_ProducerBatch",""]
    ];
    private _intent = +(_group getVariable [
        "ITW_CLASH_ProducedIntent",
        (_members#0) getVariable [
            "ITW_CLASH_ProducerPlannedTemplate",[]
        ]
    ]);
    private _sameBatch = _batch isNotEqualTo "" && {
        (_members findIf {
            (_x getVariable ["ITW_CLASH_ProducerBatch",""]) != _batch
        }) < 0
    };
    [
        _batch,
        count _intent,
        _group getVariable ["ITW_CLASH_ProducedStrength",count _members],
        _sameBatch
    ]
};

ITW_CLASH_FormationAdmission_fnc_CargoPreflight = {
    params ["_group",["_context",[]]];
    if (isNull _group || {!local _group}) exitWith {false};
    if ([_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup) exitWith {false};
    if ([_group] call ITW_CLASH_DualHAL_fnc_IsLifecycleReserved) exitWith {
        false
    };
    if (_context isEqualTo [] || {count _context < 4}) exitWith {false};
    private _hq = [_group] call ITW_CLASH_fnc_GetCommanderForGroup;
    if (isNull _hq) exitWith {false};
    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    if (_alive isEqualTo []) exitWith {false};
    ["cargo-preflight-approved",[
        [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
        count _alive,_context#1
    ]] call ITW_CLASH_FormationAdmission_fnc_Log;
    true
};

ITW_CLASH_FormationAdmission_fnc_RuntimeStability = {
    params ["_group","_reason","_alive"];
    private _count = count _alive;
        private _signature = [_group] call
            ITW_CLASH_FormationAdmission_fnc_MembershipSignature;
        private _previous = _group getVariable [
            "ITW_CLASH_FormationAdmissionSignature",""
        ];
        private _since = _group getVariable [
            "ITW_CLASH_FormationAdmissionStableSince",-1
        ];

        if (_previous isEqualTo "" || {_signature != _previous}) exitWith {
            if (_previous isNotEqualTo "") then {
                ["membership-unstable",[
                    [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                    _reason,
                    _group getVariable [
                        "ITW_CLASH_FormationAdmissionLastCount",-1
                    ],
                    _count,_previous,_signature
                ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            } else {
                ["admission-pending",[
                    [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                    _reason,_count,_alive apply {typeOf _x},
                    "stability-window"
                ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            };
            _group setVariable [
                "ITW_CLASH_FormationAdmissionSignature",_signature
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionStableSince",time
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionLastCount",_count
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionStableLogged",nil
            ];
            ["PENDING","membership-changed"]
        };

        if (_since < 0 || {
            time - _since < ITW_CLASH_FormationAdmissionStableSeconds
        }) exitWith {["PENDING","stability-window"]};

        if !(_group getVariable [
            "ITW_CLASH_FormationAdmissionStableLogged",false
        ]) then {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionStableLogged",true
            ];
            ["membership-stable",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,_count,
                round (time - _since),
                ITW_CLASH_FormationAdmissionStableSeconds
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        };

    ["ALLOW","stable-member-signature"]
};

ITW_CLASH_FormationAdmission_fnc_Gate = {
    params ["_group",["_reason","fielded"],["_context",[]]];
    if (isNull _group) exitWith {["REJECT","null-group"]};

    private _gatedReasons = [
        "runtime-existing-field",
        "legacy-impasse-cargo-staged",
        "impasse-spawn-support-corridor",
        "impasse-native-enemy-onfoot"
    ];
    if !(_reason in _gatedReasons) exitWith {["ALLOW","not-gated"]};

    if (_reason isEqualTo "impasse-spawn-support-corridor" && {
        _group getVariable [
            "ITW_CLASH_FormationAdmissionPreflightPassed",false
        ]
    }) exitWith {["ALLOW","preflight-committed"]};

    if (!local _group) exitWith {["PENDING","remote-group"]};
    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    private _count = count _alive;
    if (_count == 0) exitWith {["REJECT","no-alive-infantry"]};

    // An exemption from the 4-man *size* floor never exempts a group from
    // boarding, spawn, CASEVAC, or crew lifecycle ownership.
    private _transition = [_group] call
        ITW_CLASH_FormationAdmission_fnc_TransitionReason;
    if (_transition isNotEqualTo "") exitWith {
        private _previous = _group getVariable [
            "ITW_CLASH_FormationAdmissionBlockReason",""
        ];
        if (_previous != _transition) then {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionBlockReason",_transition
            ];
            ["admission-pending",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,_count,_alive apply {typeOf _x},
                _transition
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        };
        _group setVariable ["ITW_CLASH_FormationAdmissionSignature",nil];
        _group setVariable ["ITW_CLASH_FormationAdmissionStableSince",nil];
        _group setVariable ["ITW_CLASH_FormationAdmissionStableLogged",nil];
        ["PENDING",_transition]
    };

    _group setVariable ["ITW_CLASH_FormationAdmissionBlockReason",nil];

    private _stability = ["ALLOW","not-runtime"];
    if (_reason isEqualTo "runtime-existing-field") then {
        _stability = [_group,_reason,_alive] call
            ITW_CLASH_FormationAdmission_fnc_RuntimeStability;
    };
    // This exit is at FUNCTION scope, not nested inside the 'then' block.
    if ((_stability#0) != "ALLOW") exitWith {_stability};

    if ([_group] call ITW_CLASH_FormationAdmission_fnc_IsSpecialist) exitWith {
        ["ALLOW","specialist"]
    };

    private _original = +(_group getVariable ["ITW_CLASH_Archetype",[]]);
    private _producer = [_group] call
        ITW_CLASH_FormationAdmission_fnc_ProducerInfo;
    _producer params [
        "_producerBatch","_plannedStrength","_producedStrength","_sameBatch"
    ];

    // A truthful original 8-man archetype with two survivors is attrition:
    // preserve it for Shattered Squad, never bank those two survivors.
    if (count _original >= ITW_CLASH_FormationAdmissionMinCombatSize
        && {_count < ITW_CLASH_FormationAdmissionMinCombatSize}) exitWith {
        ["ALLOW","attrited-preexisting-archetype"]
    };

    if (_count >= ITW_CLASH_FormationAdmissionMinCombatSize) exitWith {
        // A scan that first observed one member of a group that later grew to
        // seven must not preserve the stale birth-certificate of one.
        if (count _original < _count && {
            _reason isEqualTo "runtime-existing-field"
        }) then {
            private _corrected = (units _group) apply {
                toLowerANSI typeOf _x
            };
            _group setVariable [
                "ITW_CLASH_Archetype",+_corrected
            ];
            ["archetype-corrected",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                count _original,count _corrected,_reason
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        };
        ["ALLOW","valid-combat-size"]
    };

    // All newly deployed native infantry below four go to the bank, even if
    // the old native helper already stamped a false archetype of size one.
    // Runtime unknowns are held rather than deleting crewmen/specialists of
    // uncertain provenance. A known native producer may be banked after a
    // stable membership window.
    if (_reason isEqualTo "runtime-existing-field" && {
        !_sameBatch
    }) exitWith {
        private _last = _group getVariable [
            "ITW_CLASH_FormationAdmissionUnknownLogged",false
        ];
        if (!_last) then {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionUnknownLogged",true
            ];
            ["admission-pending",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,_count,
                "unknown-small-group-provenance"
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        };
        ["PENDING","unknown-small-group-provenance"]
    };

    if ([_group,_reason,_context] call
        ITW_CLASH_FormationAdmission_fnc_Bank) exitWith {
        ["BANKED","below-minimum-combat-size"]
    };
    ["PENDING","bank-rejected-or-unavailable"]
};

// A damaged real formation can arrive already below Shattered thresholds.
// Initiate withdrawal synchronously before HAL gets a tasking cycle.
ITW_CLASH_FormationAdmission_fnc_ImmediateShattered = {
    params ["_group",["_source","admission"]];
    if (isNull _group) exitWith {false};
    if (_group getVariable ["ITW_CLASH_Withdrawing",false]) exitWith {true};
    if (_group getVariable ["ITW_CLASH_VehicleCrewGroup",false]) exitWith {false};
    if (!isNil "ITW_CLASH_DualHAL_fnc_IsPlayerGroup" && {
        [_group] call ITW_CLASH_DualHAL_fnc_IsPlayerGroup
    }) exitWith {false};

    private _archetype = +(_group getVariable ["ITW_CLASH_Archetype",[]]);
    private _original = count _archetype;
    private _aliveCount = {alive _x} count units _group;
    if (_original < 3 || {_aliveCount < 1} || {
        _aliveCount > missionNamespace getVariable [
            "ITW_CLASH_FormationRecoveryMaxShatteredSurvivors",2
        ]
    } || {(_aliveCount / (_original max 1)) > missionNamespace getVariable [
        "ITW_CLASH_FormationRecoveryMaxShatteredFraction",0.5
    ]}) exitWith {false};

    if (isNil "ITW_CLASH_fnc_StartWithdrawal") exitWith {
        ["SHATTERED-NO-WITHDRAWAL-FUNCTION",[
            [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
            _source,_aliveCount,_original
        ]] call ITW_CLASH_FormationAdmission_fnc_Assert;
        false
    };

    private _withdrawn = [
        _group,"admission-pre-shattered"
    ] call ITW_CLASH_fnc_StartWithdrawal;
    ["shattered-admission",[
        [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
        _source,_aliveCount,_original,_withdrawn
    ]] call ITW_CLASH_FormationAdmission_fnc_Log;
    if (!_withdrawn) then {
        ["SHATTERED-ADMISSION-WITHDRAWAL-FAILED",[
            [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
            _source,_aliveCount,_original
        ]] call ITW_CLASH_FormationAdmission_fnc_Assert;
    };
    _withdrawn
};

ITW_CLASH_FormationAdmission_fnc_RegisterGroupBase =
    ITW_CLASH_DualHAL_fnc_RegisterGroup;

ITW_CLASH_DualHAL_fnc_RegisterGroup = {
    params ["_group",["_reason","fielded"]];
    if (isNull _group) exitWith {false};

    private _decision = [
        _group,_reason
    ] call ITW_CLASH_FormationAdmission_fnc_Gate;
    _decision params ["_state","_why"];
    if (_state != "ALLOW") exitWith {false};

    private _hadArchetype =
        (_group getVariable ["ITW_CLASH_Archetype",[]]) isNotEqualTo [];
    private _result = _this call
        ITW_CLASH_FormationAdmission_fnc_RegisterGroupBase;

    if (_result) then {
        if !(_group getVariable [
            "ITW_CLASH_FormationAdmissionPreflightPassed",false
        ]) then {
            [_group,_reason] call
                ITW_CLASH_FormationAdmission_fnc_ImmediateShattered;
        };
        private _archetype = +(_group getVariable [
            "ITW_CLASH_Archetype",[]
        ]);
        if (!_hadArchetype && {_archetype isNotEqualTo []}) then {
            ["archetype-locked",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,count _archetype,_archetype,_why
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        };
        ["admitted",[
            [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
            side _group,_reason,
            {alive _x} count units _group,
            count _archetype,_why
        ]] call ITW_CLASH_FormationAdmission_fnc_Log;
    };
    _result
};

ITW_CLASH_FormationAdmission_fnc_Audit = {
    if (time - ITW_CLASH_FormationAdmissionLastAudit <
        ITW_CLASH_FormationAdmissionAuditSeconds) exitWith {0};
    ITW_CLASH_FormationAdmissionLastAudit = time;

    private _groups = [];
    if (!isNil "ITW_CLASH_DualHALBLUFORGroups") then {
        _groups append +ITW_CLASH_DualHALBLUFORGroups;
    };
    if (!isNil "ITW_CLASH_DualHALOPFORExtraGroups") then {
        _groups append +ITW_CLASH_DualHALOPFORExtraGroups;
    };
    if (!isNil "ITW_CLASH_ManagedGroups") then {
        _groups append +ITW_CLASH_ManagedGroups;
    };
    _groups = _groups arrayIntersect _groups;

    private _violations = 0;
    {
        private _group = _x;
        if (isNull _group) then {continue};
        if !([_group] call ITW_CLASH_FormationAdmission_fnc_IsOrdinaryInfantry) then {
            continue
        };

        private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
        private _aliveCount = count _alive;
        private _archetype = +(_group getVariable [
            "ITW_CLASH_Archetype",[]
        ]);
        private _original = count _archetype;
        private _source = _group getVariable [
            "ITW_CLASH_AuthorityReason","?"
        ];
        private _hq = if (!isNil "ITW_CLASH_fnc_GetCommanderForGroup") then {
            [_group] call ITW_CLASH_fnc_GetCommanderForGroup
        } else {grpNull};

        private _illegalFresh = (
            _aliveCount > 0
            && {_aliveCount < ITW_CLASH_FormationAdmissionMinCombatSize}
            && {_original < ITW_CLASH_FormationAdmissionMinCombatSize}
        );

        private _shatteredMiss = (
            _original >= 3
            && {_aliveCount > 0}
            && {_aliveCount <= missionNamespace getVariable [
                "ITW_CLASH_FormationRecoveryMaxShatteredSurvivors",2
            ]}
            && {
                (_aliveCount / (_original max 1)) <=
                missionNamespace getVariable [
                    "ITW_CLASH_FormationRecoveryMaxShatteredFraction",0.5
                ]
            }
            && {!(_group getVariable ["ITW_CLASH_Withdrawing",false])}
        );

        // FormationRecovery runs every three seconds; don't call a squad
        // "stuck" before that manager has had a fair opportunity to run.
        if (_shatteredMiss) then {
            private _since = _group getVariable [
                "ITW_CLASH_FormationAdmissionShatteredSince",-1
            ];
            if (_since < 0) then {
                _group setVariable [
                    "ITW_CLASH_FormationAdmissionShatteredSince",time
                ];
                _shatteredMiss = false;
            } else {
                if (time - _since < 8) then {_shatteredMiss = false};
            };
        } else {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionShatteredSince",nil
            ];
        };

        private _event = if (_illegalFresh) then {
            "ILLEGAL-INFANTRY-FORMATION"
        } else {
            if (_shatteredMiss) then {
                "SHATTERED-NOT-WITHDRAWING"
            } else {""}
        };
        if (_event isEqualTo "") then {continue};

        private _waypointIndex = currentWaypoint _group;
        private _wpKind = "NONE";
        if (_waypointIndex >= 0 && {
            _waypointIndex < count waypoints _group
        }) then {
            _wpKind = waypointType [_group,_waypointIndex];
        };
        private _signature = str [
            _event,_aliveCount,_original,_source,
            currentWaypoint _group,
            if (isNull _hq) then {false} else {
                _group in (_hq getVariable ["RydHQ_AttackAv",[]])
            },
            if (isNull _hq) then {false} else {
                _group in (_hq getVariable ["RydHQ_CombatAv",[]])
            }
        ];
        private _last = _group getVariable [
            "ITW_CLASH_FormationAdmissionAssertSignature",""
        ];
        private _next = _group getVariable [
            "ITW_CLASH_FormationAdmissionAssertNext",0
        ];
        if (_signature != _last || {time >= _next}) then {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionAssertSignature",_signature
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionAssertNext",
                time + ITW_CLASH_FormationAdmissionAssertRepeat
            ];
            [_event,[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                side _group,_aliveCount,_original,_source,
                _alive apply {typeOf _x},
                if (isNull _hq) then {false} else {
                    _group in (_hq getVariable ["RydHQ_AttackAv",[]])
                },
                if (isNull _hq) then {false} else {
                    _group in (_hq getVariable ["RydHQ_CombatAv",[]])
                },
                _wpKind,
                _group getVariable ["ITW_CLASH_Withdrawing",false]
            ]] call ITW_CLASH_FormationAdmission_fnc_Assert;
        };
        _violations = _violations + 1;
    } forEach _groups;
    _violations
};

[] spawn {
    scriptName "ITW_CLASH_FormationAdmissionAudit";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_DualHALReady",false]
        || {missionNamespace getVariable ["ITW_GameOver",false]}
    };
    if (missionNamespace getVariable ["ITW_GameOver",false]) exitWith {};

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        sleep 2;
        call ITW_CLASH_FormationAdmission_fnc_Audit;
        if (time - ITW_CLASH_FormationAdmissionLastBankRetry >=
            ITW_CLASH_FormationAdmissionBankRetrySeconds
        ) then {
            ITW_CLASH_FormationAdmissionLastBankRetry = time;
            {
                [_x] call ITW_CLASH_FormationAdmission_fnc_IssueBank;
            } forEach +(keys ITW_CLASH_FormationAdmissionBanks);
        };
    };
};

diag_log format [
    "CLASH BOOT | formation-admission-ready | version=%1 minCombat=%2 stable=%3 audit=%4 remnantBank=true loudDebug=true",
    ITW_CLASH_FormationAdmissionVersion,
    ITW_CLASH_FormationAdmissionMinCombatSize,
    ITW_CLASH_FormationAdmissionStableSeconds,
    ITW_CLASH_FormationAdmissionAuditSeconds
];
true
