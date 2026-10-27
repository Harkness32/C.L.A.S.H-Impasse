"""HAL never sends a player group on recon (2026-10-27, Hark).

Combat employment means attack tasks; combat players were sometimes handed
HAL recon. Two causes: the combat tick deliberately took the group out of
RydHQ_NoRecon, and even the exclusion for non-combat groups was written to the
commander's array only, which HQSitRepB rewrites from RydHQB_NoRecon every
cycle.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"
HAL = ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "HAL"


def code_text(text: str) -> str:
    return re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", text, flags=re.S))


def body_of(source: str, name: str) -> str:
    start = source.index(f"{name} = {{")
    depth = 0
    i = source.index("{", start)
    while i < len(source):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
        i += 1
    raise AssertionError(name)


OBSERVER = code_text((MISSION / "ITW_CLASH_ReconObserver.sqf").read_text(encoding="utf-8"))
GATE = code_text((MISSION / "ITW_CLASH_PlayerTaskStateHardening.sqf").read_text(encoding="utf-8"))


def test_the_native_recon_seam_refuses_every_player_group():
    admit = body_of(OBSERVER, "ITW_CLASH_Recon_fnc_PlayerCombatAllowed")
    assert '[true,"ai-native"]' in admit
    assert '[false,"player-groups-never-get-hal-recon"]' in admit
    # Subscription no longer matters.
    assert "COMBAT" not in admit
    assert "CanAcceptJob" not in admit
    # Both native recon wrappers ask it and reject before HAL's recon runs.
    for wrapper in ["HAL_GoRecon = {", "HAL_GoDefRecon = {"]:
        block = OBSERVER[OBSERVER.index(wrapper):]
        block = block[:block.index("\n    };")]
        assert block.index("ITW_CLASH_Recon_fnc_PlayerCombatAllowed") < block.index("ITW_CLASH_Recon_fnc_RejectPlayerMission")
        assert block.index("ITW_CLASH_Recon_fnc_RejectPlayerMission") < block.index("ITW_CLASH_Recon_fnc_Native")
    assert "ITW_CLASH_ReconPhase0Version = 7;" in OBSERVER


def test_every_player_group_is_in_no_recon_combat_or_not():
    gate = body_of(GATE, "ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission")
    add = gate.index("if !(_group in _noRecon) then {")
    branch = gate.index("if (_combat) then {")
    # The NoRecon entry is made before, and outside, the combat branch.
    assert add < branch
    combat_branch = gate[branch:gate.index("} else {", branch)]
    assert "_noRecon" not in combat_branch
    # CargoOnly still follows the tick.
    assert "_cargoOnly = _cargoOnly - [_group];" in combat_branch


def test_the_exclusion_survives_halts_sitrep_rewrite():
    # HAL's BLUFOR sitrep copies the global into the commander every cycle.
    sitrep = (HAL / "HQSitRepB.sqf").read_text(encoding="utf-8", errors="replace")
    assert '_HQ setVariable ["RydHQ_NoRecon",RydHQB_NoRecon];' in sitrep
    gate = body_of(GATE, "ITW_CLASH_PlayerTasks_fnc_SyncCombatAdmission")
    assert "_hq isEqualTo ITW_CLASH_BLUFORHQ" in gate
    assert 'missionNamespace getVariable ["RydHQB_NoRecon",[]]' in gate
    assert "_global pushBackUnique _group;" in gate
    assert "RydHQB_NoRecon = _global;" in gate


def test_no_recon_also_removes_players_from_hals_fallback_recon_pool():
    # HAL scouts with ordinary infantry (_LMCUA) when it has no recon units;
    # NoRecon is the exclusion there too.
    orders = (HAL / "HQOrders.sqf").read_text(encoding="utf-8", errors="replace")
    lmcua = orders[orders.index("_LMCUA = "):]
    lmcua = lmcua[:lmcua.index("\n")]
    assert 'RydHQ_NoRecon' in lmcua
