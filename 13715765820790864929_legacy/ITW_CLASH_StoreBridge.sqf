/*
    C.L.A.S.H. base store -- CT_WEBBROWSER channel.

    Everything the browser control needs and nothing about the store itself, so
    a second web interface can reuse this file unchanged.

    Engine behaviour this file exists to absorb, all of which fails silently:

    1.  The JSDialog handler MUST return a boolean. The page calls alert(), the
        engine blocks the browser waiting for an answer, and a handler that
        returns nothing leaves it blocked until something calls the
        JSDialogResponse action. A frozen store is the symptom.

    2.  ExecJS sent before the page is up is dropped, not queued. Requests are
        held here until the page announces itself and flushed in order.

    3.  ExecJS reads its input as single-byte text, so a non-ASCII byte arrives
        corrupted. Anything above 127 is escaped to \uXXXX before it is sent.

    4.  The page -> SQF direction is capped at 10240 characters and truncated
        without warning past that. Inbound messages are measured and rejected
        with a named error rather than being parsed as mangled JSON.

    Requires Arma 3 2.20 (CT_WEBBROWSER) and 2.18 (toJSON / fromJSON).
*/

#include "defines.hpp"

ITW_CLASH_StoreBridge_MessageCap = 10240;

/*  ExecJS requests raised before the page is ready, per control. Keyed by
    ctrlIDC because a control reference is not a valid HashMap key. */
if (isNil "ITW_CLASH_StoreBridge_Queues") then {
    ITW_CLASH_StoreBridge_Queues = createHashMap;
};
if (isNil "ITW_CLASH_StoreBridge_Ready") then {
    ITW_CLASH_StoreBridge_Ready = createHashMap;
};

/*  Raw action wrapper. Every ctrlWebBrowserAction call goes through here so the
    ASCII guard cannot be bypassed by accident. */
ITW_CLASH_Store_fnc_WebAction = {
    params ["_control", "_args"];

    if (isNull _control) exitWith { false };
    if !(_args isEqualType []) exitWith { false };

    if ((_args select 0) isEqualTo "ExecJS") then {
        private _codes = toArray (_args select 1);
        if ((_codes findIf { _x > 127 }) != -1) then {
            private _hex = "0123456789abcdef";
            private _script = (_codes apply {
                if (_x < 128) then {
                    toString [_x]
                } else {
                    format [
                        "\u%1%2%3%4",
                        _hex select [floor (_x / 4096) mod 16, 1],
                        _hex select [floor (_x / 256) mod 16, 1],
                        _hex select [floor (_x / 16) mod 16, 1],
                        _hex select [_x mod 16, 1]
                    ]
                }
            }) joinString "";
            _args = ["ExecJS", _script];
        };
    };

    _control ctrlWebBrowserAction _args;
    true
};

/*  Mark a control's page as able to receive JavaScript and flush whatever was
    raised while it was still loading. */
ITW_CLASH_Store_fnc_BridgeMarkReady = {
    params ["_control"];

    if (isNull _control) exitWith { false };

    private _key = str (ctrlIDC _control);
    if (ITW_CLASH_StoreBridge_Ready getOrDefault [_key, false]) exitWith { true };
    ITW_CLASH_StoreBridge_Ready set [_key, true];

    private _queued = ITW_CLASH_StoreBridge_Queues getOrDefault [_key, []];
    ITW_CLASH_StoreBridge_Queues set [_key, []];

    {
        [_control, ["ExecJS", _x]] call ITW_CLASH_Store_fnc_WebAction;
    } forEach _queued;

    if ((count _queued) > 0) then {
        diag_log format [
            "CLASH STORE | BRIDGE | flushed-queued-exec | idc=%1 | count=%2",
            ctrlIDC _control,
            count _queued
        ];
    };

    true
};

ITW_CLASH_Store_fnc_BridgeReset = {
    params ["_control"];

    if (isNull _control) exitWith { false };

    private _key = str (ctrlIDC _control);
    ITW_CLASH_StoreBridge_Ready set [_key, false];
    ITW_CLASH_StoreBridge_Queues set [_key, []];
    true
};

/*  Run JavaScript in the page, holding it until the page can receive it. */
ITW_CLASH_Store_fnc_Exec = {
    params ["_control", "_script"];

    if (isNull _control) exitWith { false };
    if !(_script isEqualType "") exitWith { false };

    private _key = str (ctrlIDC _control);

    if !(ITW_CLASH_StoreBridge_Ready getOrDefault [_key, false]) exitWith {
        private _queued = ITW_CLASH_StoreBridge_Queues getOrDefault [_key, []];
        _queued pushBack _script;
        ITW_CLASH_StoreBridge_Queues set [_key, _queued];
        false
    };

    [_control, ["ExecJS", _script]] call ITW_CLASH_Store_fnc_WebAction
};

/*  Deliver an event and an ALREADY ENCODED JSON payload to the page's
    receive() entry point. The SQF -> page direction carries megabytes, so
    payloads are never chunked in this direction.

    Taking JSON text rather than a HashMap is deliberate: a payload built on the
    server is encoded there and travels to the client as a string, and strings
    cross the network without relying on how any given Arma build serialises a
    HashMap. */
ITW_CLASH_Store_fnc_PushJson = {
    params ["_control", "_event", "_json"];

    if (isNull _control) exitWith { false };
    if !(_json isEqualType "") exitWith { false };

    [
        _control,
        format [
            "if (window.CLASHStore) { window.CLASHStore.receive(%1, %2); }",
            toJSON _event,
            _json
        ]
    ] call ITW_CLASH_Store_fnc_Exec
};

/*  Convenience wrapper for payloads built on the machine that will display
    them, where there is no network hop to worry about. */
ITW_CLASH_Store_fnc_Push = {
    params ["_control", "_event", "_payload"];

    [_control, _event, toJSON _payload] call ITW_CLASH_Store_fnc_PushJson
};

/*  Decode one inbound page message into [event, data], or ["", nil] when it
    cannot be trusted. A message at or over the cap was truncated in transit. */
ITW_CLASH_Store_fnc_BridgeDecode = {
    params ["_message"];

    if !(_message isEqualType "") exitWith {
        diag_log "CLASH STORE | BRIDGE | REJECTED | non-string-message";
        ["", nil]
    };

    if ((count _message) >= ITW_CLASH_StoreBridge_MessageCap) exitWith {
        diag_log format [
            "CLASH STORE | BRIDGE | REJECTED | message-at-engine-cap | length=%1 | cap=%2",
            count _message,
            ITW_CLASH_StoreBridge_MessageCap
        ];
        ["", nil]
    };

    private _decoded = nil;
    private _failed = false;

    /*  fromJSON throws on malformed input, which a truncated message is. */
    try {
        _decoded = fromJSON _message;
    } catch {
        _failed = true;
    };

    if (_failed || { isNil "_decoded" }) exitWith {
        diag_log "CLASH STORE | BRIDGE | REJECTED | malformed-json";
        ["", nil]
    };

    if !(_decoded isEqualType createHashMap) exitWith {
        diag_log "CLASH STORE | BRIDGE | REJECTED | payload-not-object";
        ["", nil]
    };

    private _event = _decoded getOrDefault ["event", ""];
    if !(_event isEqualType "" && { _event isNotEqualTo "" }) exitWith {
        diag_log "CLASH STORE | BRIDGE | REJECTED | missing-event";
        ["", nil]
    };

    private _data = _decoded getOrDefault ["data", createHashMap];
    if !(_data isEqualType createHashMap) then {
        _data = createHashMap;
    };

    [_event, _data]
};
