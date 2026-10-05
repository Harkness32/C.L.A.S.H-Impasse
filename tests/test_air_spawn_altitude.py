"""A jet asked to spawn flying must actually be flying.

Hark: "jets spawn on the ground".

The intent was never wrong. ITW_AtkSpawnOffsetter (ITW_Attack.sqf:2759) puts a
plane at 100m and a helicopter at 40m, and ITW_VEH_IS_AIR is correct - the air
constants 10 and 11 are the lowest in the block, so `<= ITW_TYPE_VEH_AIR_MAX`
selects exactly air.

The gap is the last step: createVehicle's array form places the object on the
SURFACE, and the FLY special sets the vehicle's state rather than reliably
honouring the z it was handed. A helicopter snapped to the ground lifts off and
nobody notices. A jet snapped to the ground at zero airspeed cannot.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def read(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8", errors="replace")


def test_the_air_ring_still_asks_for_altitude():
    """The premise. If this ever stops setting a height, enforcing it later is
    enforcing nothing."""
    attack = read("ITW_Attack.sqf")
    assert '_newPos set [2,if (_type == ITW_TYPE_VEH_AIRPLANE) then {100} else {40}];' in attack


def test_the_air_macro_selects_exactly_air():
    """AIRPLANE 10 and HELI 11 are the lowest constants, TANK 12 upward are
    land, so `<= AIR_MAX` is right. Asserted because it reads backwards."""
    defines = (MISSION / "defines.hpp").read_text(encoding="utf-8", errors="replace")
    assert "#define ITW_TYPE_VEH_AIRPLANE   10" in defines
    assert "#define ITW_TYPE_VEH_HELI       11" in defines
    assert "#define ITW_TYPE_VEH_TANK       12" in defines
    assert "#define ITW_VEH_IS_AIR(VEHTYPE)  (VEHTYPE <= ITW_TYPE_VEH_AIR_MAX)" in defines


def test_fly_enforces_the_requested_height():
    source = read("ITW_Vehicles.sqf")
    assert '_option isEqualTo "FLY"' in source
    assert "_veh setPosATL [_pos#0,_pos#1,_wanted]" in source


def test_it_only_corrects_a_vehicle_that_was_actually_snapped():
    """A no-op wherever the engine already honoured the height, so it costs
    nothing on the paths that were working."""
    source = read("ITW_Vehicles.sqf")
    assert "((getPosATL _veh)#2) < (_wanted * 0.5)" in source


def test_a_plane_also_gets_airspeed():
    """A plane placed at altitude with no airspeed stalls and arrives at the
    ground anyway, which would look like the same bug."""
    source = read("ITW_Vehicles.sqf")
    assert "setVelocityModelSpace" in source
    assert 'isKindOf "Plane"' in source


def test_ground_spawns_are_untouched():
    source = read("ITW_Vehicles.sqf")
    block = source[source.index('_option isEqualTo "FLY"'):]
    block = block[:block.index("sleep 0.05")]
    assert "CAN_COLLIDE" not in block
    assert "(_pos#2) > 10" in block, "no correction for a ground-level request"


def test_the_correction_announces_itself():
    assert "fly-altitude-enforced" in read("ITW_Vehicles.sqf")
