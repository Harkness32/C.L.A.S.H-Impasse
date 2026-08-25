if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestBootstrapStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestBootstrapStarted = true;
ITW_CLASH_PlayerTaskRequestBootstrapVersion = 2;

if !(fileExists "ITW_CLASH_PlayerTaskRequests.sqf") exitWith {
    diag_log "CLASH BOOT | player-task-request-router-missing | player-initiated tasking disabled";
    false
};

call compile preprocessFileLineNumbers "ITW_CLASH_PlayerTaskRequests.sqf";

private _adapters = [
    ["ARTILLERY","ITW_CLASH_PlayerTaskRequestArtillery.sqf"],
    ["STRIKE","ITW_CLASH_PlayerTaskRequestStrike.sqf"],
    ["RECON","ITW_CLASH_PlayerTaskRequestRecon.sqf"],
    ["TRANSPORT","ITW_CLASH_PlayerTaskRequestTransport.sqf"]
];

{
    _x params ["_name","_file"];
    if (fileExists _file) then {
        call compile preprocessFileLineNumbers _file;
    } else {
        diag_log format [
            "CLASH BOOT | player-task-request-adapter-missing | adapter=%1 file=%2 remainsUnavailable=true",
            _name,_file
        ];
    };
} forEach _adapters;

// Artillery presentation is layered after the ARTILLERY adapter has installed
// its 150 m aim / 250 m acceptance contract. It wraps only client-assignment
// lifecycle seams; the artillery executor and shot accounting remain untouched.
if (fileExists "ITW_CLASH_PlayerArtillerySideMarker.sqf") then {
    private _sideMarkerLoaded = call compile preprocessFileLineNumbers
        "ITW_CLASH_PlayerArtillerySideMarker.sqf";
    if !(_sideMarkerLoaded isEqualTo true) then {
        diag_log "CLASH BOOT | player-artillery-side-marker-load-failed | private gunner marker retained";
    };
} else {
    diag_log "CLASH BOOT | player-artillery-side-marker-missing | private gunner marker retained";
};

diag_log format [
    "CLASH BOOT | player-task-request-bootstrap-ready | version=%1 adapterOriented=true failClosedMissingAdapters=true artillerySideMarkerLayer=true",
    ITW_CLASH_PlayerTaskRequestBootstrapVersion
];

true
