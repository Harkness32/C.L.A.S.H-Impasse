if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CheckbookAPIReady",false]) exitWith {true};

ITW_CLASH_CheckbookAPIVersion = 1;

ITW_CLASH_Checkbook_fnc_Response = {
    params [
        ["_status","DENIED"],
        ["_capability","UNKNOWN"],
        ["_asset",objNull],
        ["_reason","unspecified"],
        ["_priority","NORMAL"]
    ];
    createHashMapFromArray [
        ["status",_status],
        ["capability",_capability],
        ["asset",_asset],
        ["reason",_reason],
        ["priority",_priority],
        ["time",time]
    ]
};

/*
    Public compatibility seam between HAL intent and the Impasse checkbook.

    HAL owns the tactical decision to ask. C.L.A.S.H. only normalizes the request
    and dispatches it to an implemented provider. Impasse remains responsible for
    faction/pool/ticket/cap accounting inside that provider.

    V1 implements TRANSPORT only. Future CASEVAC, MEDEVAC, ARTILLERY, CAS, CAP,
    SEAD and LOGISTICS providers can be added without changing HAL's public call.

    Usage:
      private _requirements = createHashMapFromArray [
          ["hq",_hq],
          ["destination",_destination],
          ["mode","AIR"],
          ["seats",8]
      ];
      private _reply = [
          "TRANSPORT",_requestingGroup,_requirements,"NORMAL"
      ] call ITW_CLASH_fnc_RequestCapability;
*/
ITW_CLASH_fnc_RequestCapability = {
    params [
        ["_capability",""],
        ["_requester",grpNull],
        ["_requirements",createHashMap],
        ["_priority","NORMAL"]
    ];

    if !(_capability isEqualType "") exitWith {
        ["DENIED","UNKNOWN",objNull,"invalid-capability",_priority] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    private _capabilityKey = toUpperANSI _capability;

    if (isNull _requester) exitWith {
        ["DENIED",_capabilityKey,objNull,"invalid-requester",_priority] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    if !(_requirements isEqualType createHashMap) exitWith {
        ["DENIED",_capabilityKey,objNull,"invalid-requirements",_priority] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    if !(missionNamespace getVariable ["ITW_CLASH_CheckbookEnabled",true]) exitWith {
        ["DENIED",_capabilityKey,objNull,"checkbook-disabled",_priority] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    switch (_capabilityKey) do {
        case "TRANSPORT": {
            if (isNil "ITW_CLASH_Checkbook_fnc_RequestTransport") exitWith {
                ["DENIED",_capabilityKey,objNull,"provider-unavailable",_priority] call
                    ITW_CLASH_Checkbook_fnc_Response
            };

            private _hq = _requirements getOrDefault ["hq",grpNull];
            if (isNull _hq && {!isNil "ITW_CLASH_fnc_GetCommanderForGroup"}) then {
                _hq = [_requester] call ITW_CLASH_fnc_GetCommanderForGroup;
            };
            private _destination = +(_requirements getOrDefault ["destination",[]]);
            private _mode = toUpperANSI (_requirements getOrDefault ["mode","GROUND"]);
            private _seats = round (_requirements getOrDefault [
                "seats",{alive _x} count units _requester
            ]);
            _seats = _seats max 1;

            if (isNull _hq || {_destination isEqualTo []} || {!(_mode in ["AIR","GROUND"])}) exitWith {
                ["DENIED",_capabilityKey,objNull,"invalid-transport-requirements",_priority] call
                    ITW_CLASH_Checkbook_fnc_Response
            };

            private _asset = [
                _requester,_hq,_destination,_mode,_seats
            ] call ITW_CLASH_Checkbook_fnc_RequestTransport;

            if (isNull _asset) then {
                ["DENIED",_capabilityKey,objNull,"checkbook-declined",_priority] call
                    ITW_CLASH_Checkbook_fnc_Response
            } else {
                ["APPROVED",_capabilityKey,_asset,"provided",_priority] call
                    ITW_CLASH_Checkbook_fnc_Response
            }
        };
        default {
            ["DENIED",_capabilityKey,objNull,"provider-not-implemented",_priority] call
                ITW_CLASH_Checkbook_fnc_Response
        };
    }
};

ITW_CLASH_CheckbookAPIReady = true;
diag_log format [
    "CLASH BOOT | checkbook-api-ready | version=%1 transport=true futureProviders=true impasseTacticalState=false",
    ITW_CLASH_CheckbookAPIVersion
];
true
