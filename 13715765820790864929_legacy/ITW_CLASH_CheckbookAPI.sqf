#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_CheckbookAPIReady",false]) exitWith {true};

ITW_CLASH_CheckbookAPIVersion = 2;
ITW_CLASH_CheckbookProviders = createHashMap;
ITW_CLASH_CheckbookLeases = createHashMap;
ITW_CLASH_CheckbookAPISerial = 0;

/*
    Checkbook V2 is the single state boundary between HAL intent and Impasse
    resources. HAL supplies a capability request. A provider may consult ITW
    faction pools, tickets, caps and generation geography, but it may not choose
    targets, routes, fire missions or recipients.

    Public request signature remains source-compatible with V1:
      [capability, requesterGroup, requirementsHashMap, priority]
          call ITW_CLASH_fnc_RequestCapability

    Every result is a typed HashMap with the same schema, including denials.
*/

ITW_CLASH_Checkbook_fnc_NewRequestId = {
    params ["_capability"];
    ITW_CLASH_CheckbookAPISerial = ITW_CLASH_CheckbookAPISerial + 1;
    format [
        "CB2-%1-%2-%3",
        round (diag_tickTime * 1000),
        ITW_CLASH_CheckbookAPISerial,
        _capability
    ]
};

ITW_CLASH_Checkbook_fnc_Response = {
    params [
        ["_request",createHashMap],
        ["_status","DENIED"],
        ["_assets",[]],
        ["_reason","unspecified"],
        ["_provider","none"],
        ["_billing",createHashMap],
        ["_generation",createHashMap],
        ["_metadata",createHashMap]
    ];

    private _capability = _request getOrDefault ["capability","UNKNOWN"];
    private _priority = _request getOrDefault ["priority","NORMAL"];
    private _side = _request getOrDefault ["side",sideUnknown];
    private _requestId = _request getOrDefault ["id","CB2-invalid"];
    private _safeAssets = _assets select {!isNull _x};

    createHashMapFromArray [
        ["schema","ITW_CLASH_CHECKBOOK_RESULT_V2"],
        ["requestId",_requestId],
        ["status",_status],
        ["capability",_capability],
        ["side",_side],
        ["assets",_safeAssets],
        ["asset",if (_safeAssets isEqualTo []) then {objNull} else {_safeAssets#0}],
        ["reason",_reason],
        ["priority",_priority],
        ["provider",_provider],
        ["billing",_billing],
        ["generation",_generation],
        ["metadata",_metadata],
        ["time",time]
    ]
};

ITW_CLASH_Checkbook_fnc_RegisterProvider = {
    params ["_capability","_provider"];
    if !(_capability isEqualType "" && {_provider isEqualType {}}) exitWith {false};
    private _key = toUpperANSI _capability;
    if (_key isEqualTo "") exitWith {false};
    ITW_CLASH_CheckbookProviders set [_key,_provider];
    true
};

ITW_CLASH_Checkbook_fnc_LeaseKey = {
    params ["_request"];
    format [
        "%1:%2",
        toUpperANSI str (_request getOrDefault ["side",sideUnknown]),
        _request getOrDefault ["capability","UNKNOWN"]
    ]
};

ITW_CLASH_Checkbook_fnc_TryLease = {
    params ["_request",["_seconds",20]];
    private _key = [_request] call ITW_CLASH_Checkbook_fnc_LeaseKey;
    private _busyUntil = ITW_CLASH_CheckbookLeases getOrDefault [_key,0];
    if (diag_tickTime < _busyUntil) exitWith {false};
    ITW_CLASH_CheckbookLeases set [_key,diag_tickTime + (_seconds max 1)];
    true
};

ITW_CLASH_Checkbook_fnc_ReleaseLease = {
    params ["_request"];
    ITW_CLASH_CheckbookLeases deleteAt (
        [_request] call ITW_CLASH_Checkbook_fnc_LeaseKey
    );
    true
};

ITW_CLASH_Checkbook_fnc_NormalizeRequest = {
    params ["_capability","_requester","_requirements","_priority"];
    private _key = if (_capability isEqualType "") then {toUpperANSI _capability} else {"UNKNOWN"};
    private _side = if (_requirements isEqualType createHashMap) then {
        _requirements getOrDefault [
            "side",
            if (isNull _requester) then {sideUnknown} else {side _requester}
        ]
    } else {
        sideUnknown
    };
    private _requestId = [_key] call ITW_CLASH_Checkbook_fnc_NewRequestId;

    createHashMapFromArray [
        ["schema","ITW_CLASH_CHECKBOOK_REQUEST_V2"],
        ["id",_requestId],
        ["capability",_key],
        ["requester",_requester],
        ["requirements",_requirements],
        ["priority",if (_priority isEqualType "") then {toUpperANSI _priority} else {"NORMAL"}],
        ["side",_side],
        ["createdAt",time]
    ]
};

ITW_CLASH_fnc_RequestCapability = {
    params [
        ["_capability",""],
        ["_requester",grpNull],
        ["_requirements",createHashMap],
        ["_priority","NORMAL"]
    ];

    private _request = [
        _capability,_requester,_requirements,_priority
    ] call ITW_CLASH_Checkbook_fnc_NormalizeRequest;

    if !(_capability isEqualType "") exitWith {
        [_request,"DENIED",[],"invalid-capability"] call ITW_CLASH_Checkbook_fnc_Response
    };
    if (isNull _requester) exitWith {
        [_request,"DENIED",[],"invalid-requester"] call ITW_CLASH_Checkbook_fnc_Response
    };
    if !(_requirements isEqualType createHashMap) exitWith {
        [_request,"DENIED",[],"invalid-requirements"] call ITW_CLASH_Checkbook_fnc_Response
    };
    if !(missionNamespace getVariable ["ITW_CLASH_CheckbookEnabled",true]) exitWith {
        [_request,"DENIED",[],"checkbook-disabled"] call ITW_CLASH_Checkbook_fnc_Response
    };

    private _side = _request getOrDefault ["side",sideUnknown];
    if (isNil "ITW_PlayerSide" || {isNil "ITW_EnemySide"} || {
        !(_side in [ITW_PlayerSide,ITW_EnemySide])
    }) exitWith {
        [_request,"DEFERRED",[],"side-identity-unavailable"] call ITW_CLASH_Checkbook_fnc_Response
    };

    private _provider = ITW_CLASH_CheckbookProviders getOrDefault [
        _request get "capability",objNull
    ];
    if !(_provider isEqualType {}) exitWith {
        [_request,"DENIED",[],"provider-not-implemented"] call ITW_CLASH_Checkbook_fnc_Response
    };
    if !([_request] call ITW_CLASH_Checkbook_fnc_TryLease) exitWith {
        [_request,"DEFERRED",[],"provider-busy"] call ITW_CLASH_Checkbook_fnc_Response
    };

    private _reply = _request call _provider;
    [_request] call ITW_CLASH_Checkbook_fnc_ReleaseLease;

    if !(_reply isEqualType createHashMap) exitWith {
        [_request,"FAILED",[],"invalid-provider-result"] call ITW_CLASH_Checkbook_fnc_Response
    };
    _reply
};

ITW_CLASH_Checkbook_fnc_TransportProvider = {
    private _request = _this;
    private _requirements = _request get "requirements";
    private _requester = _request get "requester";
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
        [_request,"DENIED",[],"invalid-transport-requirements","transport-v2"] call
            ITW_CLASH_Checkbook_fnc_Response
    };
    if (isNil "ITW_CLASH_Checkbook_fnc_RequestTransport") exitWith {
        [_request,"DEFERRED",[],"transport-provider-unavailable","transport-v2"] call
            ITW_CLASH_Checkbook_fnc_Response
    };

    private _asset = [
        _requester,
        _hq,
        _destination,
        _mode,
        _seats,
        _request get "id"
    ] call ITW_CLASH_Checkbook_fnc_RequestTransport;

    if (isNull _asset) then {
        [_request,"DENIED",[],"checkbook-declined","transport-v2"] call
            ITW_CLASH_Checkbook_fnc_Response
    } else {
        private _generation = createHashMapFromArray [
            ["profile","FORWARD"],
            ["position",getPosATL _asset]
        ];
        private _metadata = createHashMapFromArray [
            ["mode",_mode],
            ["seats",_seats],
            ["destination",_destination]
        ];
        [_request,"APPROVED",[_asset],"provided","transport-v2",createHashMap,_generation,_metadata] call
            ITW_CLASH_Checkbook_fnc_Response
    }
};

["TRANSPORT",ITW_CLASH_Checkbook_fnc_TransportProvider] call
    ITW_CLASH_Checkbook_fnc_RegisterProvider;

/*
    Impasse establishes ITW_PlayerSide / ITW_EnemySide inside ITW_Start.sqf,
    after mission init has loaded this compatibility layer. Prepare only the
    second commander here; native HAL still owns its own core initialization.
*/
if !(missionNamespace getVariable ["ITW_CLASH_DualHALSideBinderStarted",false]) then {
    ITW_CLASH_DualHALSideBinderStarted = true;
    [] spawn {
        scriptName "ITW_CLASH_DualHAL_SideBinder";
        private _deadline = diag_tickTime + 300;
        waitUntil {
            sleep 0.1;
            diag_tickTime >= _deadline || {
                !isNil "ITW_PlayerSide" && {!isNil "ITW_EnemySide"}
            }
        };

        if (diag_tickTime >= _deadline) exitWith {
            diag_log "CLASH BOOT | WARNING | dual-hal-side-bind-timeout | Impasse sides unavailable";
        };
        if (isNil "ITW_CLASH_DualHAL_fnc_PrepareCommanderB") exitWith {
            diag_log "CLASH BOOT | WARNING | dual-hal-side-bind-missing | PrepareCommanderB unavailable";
        };

        private _prepared = [] call ITW_CLASH_DualHAL_fnc_PrepareCommanderB;
        diag_log format [
            "CLASH BOOT | dual-hal-side-bound | playerSide=%1 enemySide=%2 prepared=%3 commanderB=%4 leaderHQB=%5",
            ITW_PlayerSide,
            ITW_EnemySide,
            _prepared,
            !isNull (missionNamespace getVariable ["ITW_CLASH_BLUFORHQ",grpNull]),
            !isNull (missionNamespace getVariable ["ITW_CLASH_BLUFORLeader",objNull])
        ];
    };
};

ITW_CLASH_CheckbookAPIReady = true;
diag_log format [
    "CLASH BOOT | checkbook-api-ready | version=%1 schema=request/result-v2 providers=registry leases=side-capability impasseTacticalState=false sideBind=deferred-until-impasse-sides",
    ITW_CLASH_CheckbookAPIVersion
];
true
