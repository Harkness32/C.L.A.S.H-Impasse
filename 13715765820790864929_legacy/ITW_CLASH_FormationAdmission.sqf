if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_FormationAdmissionStarted",false]) exitWith {true};

if (isNil "ITW_CLASH_DualHAL_fnc_RegisterGroup") exitWith {
    diag_log "CLASH BOOT | FAILED | formation-admission-register-missing";
    false
};

ITW_CLASH_FormationAdmissionStarted = true;
ITW_CLASH_FormationAdmissionVersion = 1;
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
ITW_CLASH_FormationAdmissionLastAudit = -1000;

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
        (toUpperANSI currentCommand _x) in ["GET IN","GETIN"]
    }) >= 0) exitWith {"get-in-command"};

    ""
};

ITW_CLASH_FormationAdmission_fnc_MembershipSignature = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};
    private _ids = ((units _group) select {alive _x}) apply {
        private _id = _x call BIS_fnc_netId;
        if (_id isEqualTo "") then {str _x} else {_id}
    };
    _ids sort true;
    str _ids
};

ITW_CLASH_FormationAdmission_fnc_IssueBank = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_FormationAdmission_fnc_SideKey;
    private _bank = +(ITW_CLASH_FormationAdmissionBanks getOrDefault [_key,[]]);
    private _issued = 0;

    while {count _bank >= ITW_CLASH_FormationAdmissionMinCombatSize} do {
        private _release = _bank select [0,ITW_CLASH_FormationAdmissionMinCombatSize];
        _bank deleteRange [0,ITW_CLASH_FormationAdmissionMinCombatSize];

        private _spawnPos = +((_release#0)#4);
        if (count _spawnPos < 3) then {_spawnPos pushBack 0};
        if (surfaceIsWater _spawnPos) then {
            _spawnPos = [_spawnPos,0,100,2,0,0.4,0,[],[_spawnPos,_spawnPos]] call
                BIS_fnc_findSafePos;
            if (count _spawnPos < 3) then {_spawnPos pushBack 0};
        };

        private _newGroup = createGroup [_side,false];
        private _created = [];
        {
            _x params ["_class","_loadout","_skill","_rank","","_sourceId"];
            private _unit = _newGroup createUnit [_class,_spawnPos,[],0,"NONE"];
            if (!isNull _unit) then {
                _unit setUnitLoadout _loadout;
                _unit setSkill _skill;
                _unit setRank _rank;
                _created pushBack _unit;
            };
        } forEach _release;

        if (count _created != ITW_CLASH_FormationAdmissionMinCombatSize) then {
            {deleteVehicle _x} forEach _created;
            deleteGroup _newGroup;
            _bank = _release + _bank;
            ["remnant-issue-failed",[
                _key,count _created,ITW_CLASH_FormationAdmissionMinCombatSize
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            break
        };

        ITW_CLASH_FormationAdmissionBankSerial =
            ITW_CLASH_FormationAdmissionBankSerial + 1;
        private _lineage = format [
            "PROVISIONAL-%1-%2",
            _key,ITW_CLASH_FormationAdmissionBankSerial
        ];
        private _archetype = _created apply {toLowerANSI typeOf _x};
        _newGroup setVariable ["ITW_CLASH_ProvisionalFormation",true,true];
        _newGroup setVariable ["ITW_CLASH_Archetype",+_archetype,true];
        _newGroup setVariable ["ITW_CLASH_Lineage",_lineage,true];
        _newGroup setVariable ["ITW_CLASH_FormationAdmissionExempt",true];

        {
            _x addCuratorEditableObjects [_created,true];
        } forEach allCurators;

        private _accepted = [
            _newGroup,"deployment-remnant-provisional"
        ] call ITW_CLASH_DualHAL_fnc_RegisterGroup;

        _newGroup setVariable ["ITW_CLASH_FormationAdmissionExempt",nil];

        ["remnant-issued",[
            _key,
            [_newGroup] call ITW_CLASH_FormationAdmission_fnc_GroupId,
            _lineage,count _created,_archetype,_accepted
        ]] call ITW_CLASH_FormationAdmission_fnc_Log;
        _issued = _issued + 1;
    };

    ITW_CLASH_FormationAdmissionBanks set [_key,_bank];
    _issued
};

ITW_CLASH_FormationAdmission_fnc_Bank = {
    params ["_group",["_source","unknown"]];
    if (isNull _group) exitWith {false};
    if !([_group] call ITW_CLASH_FormationAdmission_fnc_IsOrdinaryInfantry) exitWith {
        false
    };

    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    if (_alive isEqualTo []) exitWith {false};

    private _side = side _group;
    private _key = [_side] call ITW_CLASH_FormationAdmission_fnc_SideKey;
    private _bank = +(ITW_CLASH_FormationAdmissionBanks getOrDefault [_key,[]]);
    private _before = count _bank;
    private _groupId = [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId;

    _group setVariable ["ITW_CLASH_DeploymentRemnant",true,true];
    _group setVariable ["ITW_CLASH_ExcludeHAL",true,true];
    _group setVariable ["ITW_CLASH_FormationAdmissionBanked",true,true];
    _group enableAttack false;
    _group setCombatMode "BLUE";
    _group setBehaviourStrong "CARELESS";
    {deleteWaypoint _x} forEachReversed waypoints _group;

    {
        _bank pushBack [
            typeOf _x,
            getUnitLoadout _x,
            skill _x,
            rank _x,
            getPosATL _x,
            _groupId
        ];
    } forEach _alive;

    ITW_CLASH_FormationAdmissionBanks set [_key,_bank];

    ["remnant-banked",[
        _groupId,_side,_source,count _alive,
        _before,count _bank,
        _alive apply {typeOf _x}
    ]] call ITW_CLASH_FormationAdmission_fnc_Log;

    {deleteVehicle _x} forEach _alive;
    if (units _group isEqualTo []) then {deleteGroup _group};

    [_side] call ITW_CLASH_FormationAdmission_fnc_IssueBank;
    true
};

ITW_CLASH_FormationAdmission_fnc_Gate = {
    params ["_group",["_reason","fielded"]];
    if (isNull _group) exitWith {["REJECT","null-group"]};

    if !(_reason in ["runtime-existing-field","legacy-impasse-cargo-staged"]) exitWith {
        ["ALLOW","not-gated"]
    };
    if ([_group] call ITW_CLASH_FormationAdmission_fnc_IsSpecialist) exitWith {
        ["ALLOW","specialist"]
    };

    private _alive = [_group] call ITW_CLASH_FormationAdmission_fnc_AliveMen;
    private _count = count _alive;
    if (_count == 0) exitWith {["REJECT","no-alive-infantry"]};

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
        ["PENDING",_transition]
    };

    _group setVariable ["ITW_CLASH_FormationAdmissionBlockReason",nil];

    if (_reason isEqualTo "legacy-impasse-cargo-staged") then {
        if (_count < ITW_CLASH_FormationAdmissionMinCombatSize) exitWith {
            if ([_group,_reason] call ITW_CLASH_FormationAdmission_fnc_Bank) then {
                ["BANKED","below-minimum-combat-size"]
            } else {
                ["PENDING","bank-rejected"]
            }
        };
        ["ALLOW","legacy-cargo-valid-size"]
    } else {
        private _signature = [_group] call
            ITW_CLASH_FormationAdmission_fnc_MembershipSignature;
        private _previous = _group getVariable [
            "ITW_CLASH_FormationAdmissionSignature",""
        ];
        private _since = _group getVariable [
            "ITW_CLASH_FormationAdmissionStableSince",-1
        ];

        if (_previous isEqualTo "") exitWith {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionSignature",_signature
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionStableSince",time
            ];
            ["admission-pending",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,_count,_alive apply {typeOf _x},
                "stability-window"
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            ["PENDING","stability-window"]
        };

        if (_signature != _previous) exitWith {
            ["membership-unstable",[
                [_group] call ITW_CLASH_FormationAdmission_fnc_GroupId,
                _reason,
                _group getVariable ["ITW_CLASH_FormationAdmissionLastCount",-1],
                _count,_previous,_signature
            ]] call ITW_CLASH_FormationAdmission_fnc_Log;
            _group setVariable [
                "ITW_CLASH_FormationAdmissionSignature",_signature
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionStableSince",time
            ];
            _group setVariable [
                "ITW_CLASH_FormationAdmissionLastCount",_count
            ];
            ["PENDING","membership-changed"]
        };

        if (_since < 0 || {
            time - _since < ITW_CLASH_FormationAdmissionStableSeconds
        }) exitWith {
            _group setVariable [
                "ITW_CLASH_FormationAdmissionLastCount",_count
            ];
            ["PENDING","stability-window"]
        };

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

        if (_count < ITW_CLASH_FormationAdmissionMinCombatSize) exitWith {
            if ([_group,_reason] call ITW_CLASH_FormationAdmission_fnc_Bank) then {
                ["BANKED","stable-below-minimum-combat-size"]
            } else {
                ["PENDING","bank-rejected"]
            }
        };

        ["ALLOW","stable-valid-size"]
    }
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

        private _event = if (_illegalFresh) then {
            "ILLEGAL-INFANTRY-FORMATION"
        } else {
            if (_shatteredMiss) then {
                "SHATTERED-NOT-WITHDRAWING"
            } else {""}
        };
        if (_event isEqualTo "") then {continue};

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
                waypointType [_group,currentWaypoint _group],
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
