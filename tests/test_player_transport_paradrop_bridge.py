from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_hal_player_transport_restores_native_itw_paradrop_controls():
    bridge = mission("ITW_CLASH_PlayerTransportNativeBridge.sqf")
    vehicles = mission("ITW_Vehicles.sqf")
    ally = mission("ITW_Ally.sqf")

    # ITW owns the player-facing actions and their shared trigger flag.
    assert 'localize "STR_ITW_VEH_TroopsParachute"' in vehicles
    assert 'localize "STR_ITW_VEH_TroopsEject"' in vehicles
    assert '_veh setVariable ["ITW_AllyCrewEject",true,true];' in vehicles
    assert "ITW_transportGroups" in vehicles

    # Native Impasse uses the same state and native paradrop routine.
    assert 'ITW_AllyParadropCargo = {' in ally
    assert '[_veh,grpNull,[_grp],[]] call ITW_AtkUnloadAirplane;' in ally

    # HAL-observed embarkation mirrors only player-facing ITW passenger state.
    assert 'ITW_CLASH_PlayerTransport_fnc_RegisterITWPassengerState' in bridge
    assert '_groups pushBackUnique _group;' in bridge
    assert '_carrier setVariable ["ITW_transportGroups",_groups,true];' in bridge
    assert 'ITW_CLASH_PlayerTransport_fnc_IsPlayerCarrier' in bridge
    assert 'isPlayer _pilot' in bridge

    # The existing ITW command drives native paradrop/eject execution.
    assert '_carrier getVariable ["ITW_AllyCrewEject",false]' in bridge
    assert '[_carrier,_group] call ITW_AllyParadropCargo;' in bridge
    assert 'moveOut _x;' in bridge
    assert 'ITW_CLASH_PlayerTransport_fnc_UnregisterITWPassengerState' in bridge

    # HAL remains the transport commander: this bridge never invents or removes WPs.
    for forbidden in ["RYD_WPadd", "RYD_WPdel", "addWaypoint", "deleteWaypoint", "setWaypointType"]:
        assert forbidden not in bridge

    assert "itwPassengerStateBridge=true" in bridge
    assert "nativePlayerParadrop=true" in bridge
