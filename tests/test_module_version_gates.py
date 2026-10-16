"""Every module-version gate must accept the version its module declares.

213475d moved ITW_CLASH_InfantryAuthority.sqf to v5 and left the bootstrap
demanding 4. From then on every boot logged "infantry-authority-ready
version=5" and then "infantry-authority-load-failed": the allocation fix never
loaded and the late finalizers skipped the authority functions. Nothing
failed loudly, which is why this pins the whole class of mistake rather than
the one number.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

DECLARED = re.compile(r"^\s*(ITW_CLASH_\w*Version)\s*=\s*(\d+)\s*;", re.M)
GATE = re.compile(
    r'getVariable\s*\[\s*"(ITW_CLASH_\w*Version)"\s*,\s*-?\d+\s*\]\s*\)\s*(==|>=|>|<=|<)\s*(\d+)'
)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//[^\n]*", " ", source)


def sources():
    for path in sorted(MISSION.glob("*.sqf")):
        yield path.name, strip_comments(path.read_text(encoding="utf-8", errors="replace"))


def declared_versions():
    found = {}
    for name, source in sources():
        for match in DECLARED.finditer(source):
            found.setdefault(match.group(1), []).append((name, int(match.group(2))))
    return found


def gates():
    for name, source in sources():
        for match in GATE.finditer(source):
            yield name, match.group(1), match.group(2), int(match.group(3))


def holds(actual: int, op: str, wanted: int) -> bool:
    return {
        "==": actual == wanted,
        ">=": actual >= wanted,
        ">": actual > wanted,
        "<=": actual <= wanted,
        "<": actual < wanted,
    }[op]


def test_every_gate_accepts_the_declared_version():
    declared = declared_versions()
    checked = 0
    for name, variable, op, wanted in gates():
        assert variable in declared, f"{name}: gate on {variable}, which nothing declares"
        for module, actual in declared[variable]:
            assert holds(actual, op, wanted), (
                f"{name} gates {variable} {op} {wanted} but {module} declares {actual}"
            )
        checked += 1
    # The bootstrap's three gates at least; a regex that matched nothing would
    # make this test pass vacuously.
    assert checked >= 3, checked


def test_the_infantry_authority_gate_is_current():
    bootstrap = strip_comments((MISSION / "ITW_CLASH_SOFDoctrineBootstrap.sqf").read_text(encoding="utf-8"))
    module = (MISSION / "ITW_CLASH_InfantryAuthority.sqf").read_text(encoding="utf-8")
    version = int(re.search(r"ITW_CLASH_InfantryAuthorityVersion = (\d+);", module).group(1))
    assert f'(missionNamespace getVariable ["ITW_CLASH_InfantryAuthorityVersion",-1]) == {version}' in bootstrap
