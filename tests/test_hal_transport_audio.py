from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def executable_lines(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines()
        if not line.strip().startswith("//")
    )


def test_hal_transport_audio_is_passive_and_restores_native_boarding_cues():
    audio = mission("ITW_CLASH_HALTransportAudio.sqf")
    loader = mission("ITW_CLASH_HALLogistics.sqf")

    assert '["bStart",_carrier] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];' in audio
    assert '["bEnd",_carrier] remoteExec ["ITW_AllyRadioMsg",_nearbyPlayers];' in audio
    assert 'localize "STR_ITW_ALLY_WeAreBoarding"' in audio
    assert 'localize "STR_ITW_ALLY_WeAreIn"' in audio
    assert 'remoteExecCall ["systemChat",_pilot]' in audio
    assert 'isPlayer _pilot' in audio
    assert 'remoteExec ["sideChat",_pilot]' not in audio
    assert 'assignedVehicle _x == _carrier || {vehicle _x == _carrier}' in audio
    assert '_state == "HAL_ASSIGNED"' in audio
    assert '_state == "EMBARKED"' in audio
    assert '"audio-" + _event' in audio

    # This layer is instrumentation/audio only. HAL SCargo remains the sole
    # movement and physical boarding executor. Check executable code rather
    # than comments describing the native HAL behavior we observe.
    executable = executable_lines(audio)
    for forbidden in [
        "assignAsCargo",
        "assignAsDriver",
        "assignAsGunner",
        "orderGetIn",
        "ITW_AllyOrderGetIn",
        "doMove",
        "moveOut",
        "setWaypoint",
        "RYD_WPadd",
        "RYD_WPdel",
    ]:
        assert forbidden not in executable

    assert '[] execVM "ITW_CLASH_HALTransportAudio.sqf";' in loader
    assert "boarding cues are unavailable" in loader
