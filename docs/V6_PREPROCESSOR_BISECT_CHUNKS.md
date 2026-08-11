# Chunk boundaries

The diagnostic mirrors cover the complete 2,639-line V6 controller without overlap or gaps:

1. `ITW_CLASH_PP_01.sqf`: lines 1-339
2. `ITW_CLASH_PP_02.sqf`: lines 340-667
3. `ITW_CLASH_PP_03.sqf`: lines 668-1009
4. `ITW_CLASH_PP_04.sqf`: lines 1010-1360
5. `ITW_CLASH_PP_05.sqf`: lines 1361-1596
6. `ITW_CLASH_PP_06.sqf`: lines 1597-1980
7. `ITW_CLASH_PP_07.sqf`: lines 1981-2310
8. `ITW_CLASH_PP_08.sqf`: lines 2311-2639

Boundaries were selected at complete function definitions. Each mirror prepends the same `defines.hpp` include used by the original controller so macro expansion is tested under the same environment.
