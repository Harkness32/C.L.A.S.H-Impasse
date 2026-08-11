#include "defines.hpp"

// C.L.A.S.H. V6 IsConscious root-cause replacement.
ITW_CLASH_fnc_IsConscious = {
    params ["_unit"];
    if (isNull _unit || {!alive _unit}) exitWith {false};
    CONSCIOUS(_unit)
};
