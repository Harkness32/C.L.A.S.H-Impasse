/*
    CLASH_fnc_HALAdd_Overrides

    Compatibility shim for missions which still call the old Additions override
    entry point. v0.2 deliberately does not replace HALcore, TaskInit, or any
    HAL_* function. Workshop NR6 HAL initializes itself; current C.L.A.S.H.
    mission patches bind narrowly after native HAL exists.
*/

CLASH_HALAdd_SourcePaths = createHashMap;
CLASH_HALAdd_OverridesApplied = [];
CLASH_HALAdd_NativeHALCore = true;

diag_log format [
    "CLASHHALADD | compatibility-mode | halVersion=%1 nativeHALCore=true functionSwaps=0 taskInit=native",
    missionNamespace getVariable ["HAL_Ver","?"]
];

true
