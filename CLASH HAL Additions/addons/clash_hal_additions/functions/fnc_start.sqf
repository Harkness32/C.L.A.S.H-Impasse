/*
    CLASH_fnc_HALAdd_Start

    preInit=1 entry point. v0.2 is intentionally non-invasive: NR6 HAL owns
    HALcore, VarInit, TaskInit and every HAL_* tactical executor. Additions only
    starts its independent threat-response observers after an HQ really exists.
*/

if (!isServer) exitWith {};

call CLASH_fnc_HALAdd_Overrides;

diag_log "CLASHHALADD | start | nativeHALCore=true functionSwaps=0 taskInit=native responderOnly=true";

[] spawn
{
    private _names = [
        "LeaderHQ","LeaderHQB","LeaderHQC","LeaderHQD",
        "LeaderHQE","LeaderHQF","LeaderHQG","LeaderHQH"
    ];

    {
        private _HQname = _x;
        [_HQname] spawn
        {
            params ["_HQname"];
            waitUntil
            {
                sleep 2;
                private _hqObj = missionNamespace getVariable [
                    _HQname,objNull
                ];
                private _hq = if (isNull _hqObj) then {
                    grpNull
                } else {
                    group _hqObj
                };
                !isNull _hq
                && {!isNil "RydxHQ_AllHQ"}
                && {_hq in RydxHQ_AllHQ}
                && {!isNil "RYD_TerraCognita"}
                && {!isNil "RYD_DistOrd"}
                && {!isNil "RYD_AmmoCount"}
                && {!isNil "RYD_GoLaunch"}
                && {!isNil "RYD_Spawn"}
            };
            diag_log format [
                "CLASHHALADD | native-hal-ready | hq=%1",
                _HQname
            ];
            [_HQname] call CLASH_fnc_HALAdd_Watch;
        };
    } forEach _names;
};
