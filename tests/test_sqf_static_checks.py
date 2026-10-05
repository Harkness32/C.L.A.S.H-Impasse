import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"

# Engine/BIS-provided magic variables that are read without being declared.
MAGIC = {
    "_x", "_y", "_this", "_forEachIndex", "_thisEventHandler", "_thisScript",
    "_exception", "_fnc_scriptName", "_fnc_scriptNameParent", "_thisArgs",
    "_thisScriptedEventHandler", "_thisFSM",
    "_input0",  # BIS_fnc_sortBy's input parameter
}


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def top_level_functions(text: str):
    for match in re.finditer(r"^([A-Za-z_]\w*)\s*=\s*\{", text, re.M):
        start = match.end() - 1
        depth = 0
        i = start
        while i < len(text):
            char = text[i]
            if char == '"':
                j = text.find('"', i + 1)
                while j != -1 and text[j:j + 2] == '""':
                    j = text.find('"', j + 2)
                i = j if j != -1 else len(text)
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        yield match.group(1), text[start:i + 1]


def undefined_locals(path: Path):
    findings = []
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    for name, body in top_level_functions(text):
        no_strings = re.sub(r'"(?:[^"]|"")*"', '""', body)
        declared = {m.lower() for m in MAGIC}
        declared |= {m.lower() for m in re.findall(r"\b(_\w+)\s*=(?!=)", no_strings)}
        declared |= {m.lower() for m in re.findall(r'"(_\w+)"', body)}  # params / private / for "_i"
        used = set(re.findall(r'(?<![\w"])(_\w+)\b', no_strings))
        bad = sorted(u for u in used if u.lower() not in declared)
        if bad:
            findings.append(f"{path.name}:{name}: {bad}")
    return findings


def test_no_clash_function_reads_a_local_it_never_declares():
    # Catches partial renames like _defs/_ranked in the Checkbook transport
    # path, which errored at runtime and silently broke every transport buy.
    findings = []
    for path in sorted(MISSION.glob("ITW_CLASH_*.sqf")):
        findings += undefined_locals(path)
    assert not findings, "\n".join(findings)


def test_no_negation_applied_to_a_namespace_before_getvariable():
    # `!missionNamespace getVariable [...]` negates the namespace, not the
    # value ("Type Namespace, expected Bool") and killed a watcher loop at boot.
    pattern = re.compile(r"!\s*(missionNamespace|uiNamespace|profileNamespace|parsingNamespace)\s+getVariable")
    hits = []
    for path in sorted(MISSION.glob("*.sqf")):
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if pattern.search(line):
                hits.append(f"{path.name}:{number}: {line.strip()}")
    assert not hits, "\n".join(hits)
