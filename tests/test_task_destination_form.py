"""Task destinations a player can actually see (2026-10-27, Hark).

"CSAR markers work telling where the squad is, but once they're in, it doesnt
tell where to go." BIS_fnc_taskSetDestination takes an object, a position, or
[object, precision]. Every CSAR, squad-evac, dispatch and transport job moved
its marker after boarding with [position, true], which is none of those, so
the drop-off marker never appeared. Positions go in plain; the [x, true] form
is kept for objects only.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

CALL = re.compile(r"\[_taskId,\s*\[(?P<dest>.*?),\s*true\]\]\s*call BIS_fnc_taskSetDestination")

# Destinations in the [x, true] form that are objects.
OBJECTS = {
    ("ITW_CLASH_PlayerTaskSupport.sqf", "_target"),
}

POSITIONS = {
    "ITW_CLASH_CSAR.sqf": ["[_taskId,_home] call BIS_fnc_taskSetDestination"],
    "ITW_CLASH_PlayerDemandDispatch.sqf": ["[_taskId,_home] call BIS_fnc_taskSetDestination"],
    "ITW_CLASH_PlayerSquadEvac.sqf": [
        "[_taskId,_lz] call BIS_fnc_taskSetDestination",
        "[_taskId,getPosATL _leader] call BIS_fnc_taskSetDestination",
        "[_taskId,_rally] call BIS_fnc_taskSetDestination",
    ],
    "ITW_CLASH_PlayerTaskRequestTransport.sqf": [
        '[_taskId,_job getOrDefault ["destination",[]]] call BIS_fnc_taskSetDestination',
    ],
}


def test_clash_never_passes_a_position_with_a_precision_flag():
    for path in sorted(MISSION.glob("ITW_CLASH_*.sqf")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in CALL.finditer(text):
            assert (path.name, match.group("dest").strip()) in OBJECTS, (path.name, match.group(0))


def test_the_post_boarding_destinations_are_plain_positions():
    for name, calls in POSITIONS.items():
        text = (MISSION / name).read_text(encoding="utf-8")
        for call in calls:
            assert call in text, (name, call)
