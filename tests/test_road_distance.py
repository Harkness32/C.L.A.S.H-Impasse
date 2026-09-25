from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def road_distance() -> str:
    return text(MISSION / "ITW_CLASH_RoadDistance.sqf")


def atk_road_map_context() -> str:
    return text(MISSION / "ITW_Attack.sqf")


def init_sqf() -> str:
    return text(MISSION / "init.sqf")


def test_this_is_not_a_whole_map_cached_graph():
    # Deliberate scope boundary: bounded, on-demand, two-point query, not a
    # persistent whole-map road graph. Confirms the file doesn't cache a
    # graph across calls (no module-level graph variable surviving between
    # ITW_CLASH_RoadDistance_fnc_Calculate invocations).
    source = road_distance()
    assert "ITW_CLASH_RoadDistanceMaxNodes" in source
    assert "ITW_CLASH_RoadDistanceMaxDistance" in source
    # the graph state (_knownCost, _open, _visited) is declared private,
    # inside the function - not a persistent missionNamespace structure
    fn_start = source.index("ITW_CLASH_RoadDistance_fnc_Calculate = {")
    fn_end = source.index("\nITW_CLASH_RoadDistanceReady", fn_start)
    fn = source[fn_start:fn_end]
    assert "private _knownCost = createHashMap;" in fn
    assert "private _open = " in fn
    assert "private _visited = [];" in fn


def test_itw_atk_road_map_was_checked_and_confirmed_unusable_for_this():
    # ITW_AtkRoadMap looked promising by name but is a spawn-placement
    # deconfliction cache (nearby roads for scattering newly-spawned
    # vehicles), not a route or distance structure. Confirms the actual
    # source still matches that read, so the documented reasoning for
    # building fresh instead of reusing it stays valid.
    source = atk_road_map_context()
    cache_start = source.index('if (isNil "ITW_AtkRoadMap"  ) then')
    cache_end = source.index("ITW_AtkRoadMap set [[_fromBaseIdxOrPt,_toObjIdx],_roads];", cache_start)
    cache_block = source[cache_start:cache_end]
    assert "nearRoads" in cache_block
    assert "roadsConnectingTo" not in cache_block  # confirms: no adjacency walk, not a graph
    assert "BIS_fnc_sortBy" in cache_block  # sorts by proximity for spawn offsetting, not path order


def test_no_road_access_returns_a_distinct_sentinel_not_zero_or_fallback():
    source = road_distance()
    fn_start = source.index("ITW_CLASH_RoadDistance_fnc_Calculate = {")
    fn_end = source.index("\nITW_CLASH_RoadDistanceReady", fn_start)
    fn = source[fn_start:fn_end]

    assert '_startCandidates isEqualTo [] || {_endCandidates isEqualTo []}' in fn
    assert "exitWith {" in fn
    assert '"no-road-access"' in fn
    # the failure path returns -1, not 0 and not a straight-line fallback -
    # 0 would misread as "adjacent", and silently falling back to straight-
    # line would quietly reintroduce the exact dishonesty this file exists
    # to remove
    no_road_start = fn.index('"no-road-access"')
    no_road_end = fn.index("};", no_road_start)
    no_road_block = fn[no_road_start:no_road_end]
    assert "-1" in no_road_block
    assert "distance2D" not in no_road_block


def test_close_ends_on_the_same_local_cluster_skip_the_graph_search():
    # Two points sharing one nearby road cluster don't need Dijkstra - the
    # short-circuit exists so the search cost is only paid when actually
    # crossing distinct parts of the road network.
    source = road_distance()
    fn_start = source.index("ITW_CLASH_RoadDistance_fnc_Calculate = {")
    fn_end = source.index("\nITW_CLASH_RoadDistanceReady", fn_start)
    fn = source[fn_start:fn_end]
    assert "_startRoad distance2D _endRoad < ITW_CLASH_RoadDistanceSearchRadius" in fn
    shortcut_pos = fn.index("_startRoad distance2D _endRoad")
    dijkstra_pos = fn.index("private _knownCost = createHashMap;")
    assert shortcut_pos < dijkstra_pos


def test_search_is_bounded_on_both_node_count_and_cumulative_distance():
    # Two independent budgets, not one - a road network that's locally dense
    # but globally huge could exhaust a node budget without a distance cap,
    # and vice versa a long chain of sparse intersections could exhaust
    # distance without hitting a node cap.
    source = road_distance()
    fn_start = source.index("ITW_CLASH_RoadDistance_fnc_Calculate = {")
    fn_end = source.index("\nITW_CLASH_RoadDistanceReady", fn_start)
    fn = source[fn_start:fn_end]
    assert "_nodesExpanded < ITW_CLASH_RoadDistanceMaxNodes" in fn
    assert "_currentCost <= ITW_CLASH_RoadDistanceMaxDistance" in fn


def test_uses_real_adjacency_not_a_radius_scan():
    # The whole point versus a naive nearRoads-only approach: actually walk
    # the road network's own connectivity, not just "what's physically
    # nearby" (which would let the search jump across a river if two
    # disconnected roads happen to be close in a straight line).
    source = road_distance()
    assert "roadsConnectingTo" in source


def test_relaxation_only_replaces_a_worse_known_cost():
    source = road_distance()
    fn_start = source.index("ITW_CLASH_RoadDistance_fnc_Calculate = {")
    fn_end = source.index("\nITW_CLASH_RoadDistanceReady", fn_start)
    fn = source[fn_start:fn_end]
    assert "_edgeCost < _known" in fn
    assert "getOrDefault [_key,1e10]" in fn


def test_loaded_early_with_no_force_generation_dependency():
    # Pure geometry - no HAL/Impasse readiness gate needed, unlike almost
    # every other file wired into this boot chain.
    source = init_sqf()
    load_pos = source.index('call compile preprocessFileLineNumbers "ITW_CLASH_RoadDistance.sqf"')
    logistics_pos = source.index('call compile preprocessFileLineNumbers "ITW_CLASH_HALLogistics.sqf"')
    assert load_pos < logistics_pos

    guard_start = source.rindex("if (", 0, load_pos)
    guard_line = source[guard_start:source.index("\n", guard_start)]
    assert "_forceGenerationReady" not in guard_line
    assert "fileExists \"ITW_CLASH_RoadDistance.sqf\"" in guard_line
