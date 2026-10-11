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
                !(isNil _HQname) && {
                    !(isNull (missionNamespace getVariable [_HQname,objNull]))
                }
            };
            [_HQname] call CLASH_fnc_HALAdd_Watch;
        };
    } forEach _names;
};
