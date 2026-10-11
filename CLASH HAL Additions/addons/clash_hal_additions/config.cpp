class CfgPatches
{
    class CLASH_HAL_Additions
    {
        author = "CLASH";
        name = "CLASH HAL Additions";
        units[] = {};
        weapons[] = {};
        requiredVersion = 0.1;
        requiredAddons[] = { "NR6_HAL" };
        version = "0.2";
    };
};

// NR6 HAL owns HALcore and TaskInit completely.  This addon is now a consumer
// of HAL's published HQ state and helpers, never a replacement initializer.
// The mission-side C.L.A.S.H. runtime owns its own narrow compatibility patches.
class CfgFunctions
{
    class CLASH
    {
        tag = "CLASH";
        class HALAdd
        {
            class HALAdd_Respond { file = "\clash_hal_additions\functions\fnc_respond.sqf"; };
            class HALAdd_Watch { file = "\clash_hal_additions\functions\fnc_watch.sqf"; };
            class HALAdd_Start { file = "\clash_hal_additions\functions\fnc_start.sqf"; preInit = 1; };

            // Kept as a compatibility symbol for old missions. It is now a
            // deliberate no-op and cannot replace any HAL_* global.
            class HALAdd_Overrides { file = "\clash_hal_additions\functions\fnc_overrides.sqf"; };
        };
    };
};
