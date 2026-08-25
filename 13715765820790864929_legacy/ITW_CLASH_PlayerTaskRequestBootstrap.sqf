if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_PlayerTaskRequestBootstrapStarted",false]) exitWith {true};

ITW_CLASH_PlayerTaskRequestBootstrapStarted = true;
ITW_CLASH_PlayerTaskRequestBootstrapVersion = 1;

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

diag_log format [
    "CLASH BOOT | player-task-request-bootstrap-ready | version=%1 adapterOriented=true failClosedMissingAdapters=true",
    ITW_CLASH_PlayerTaskRequestBootstrapVersion
];

true
