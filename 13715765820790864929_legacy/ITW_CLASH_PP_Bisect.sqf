/*
    Diagnostic-only preprocessor bisect for ITW_CLASH.sqf.
    Chunks are preprocessed and measured, never compiled or executed.
*/
if (!isServer) exitWith {false};

diag_log "CLASH PP | begin | 8 function-boundary chunks";
private _chunks = [
    ["01","ITW_CLASH_PP_01.sqf",1,339],
    ["02","ITW_CLASH_PP_02.sqf",340,667],
    ["03","ITW_CLASH_PP_03.sqf",668,1009],
    ["04","ITW_CLASH_PP_04.sqf",1010,1360],
    ["05","ITW_CLASH_PP_05.sqf",1361,1596],
    ["06","ITW_CLASH_PP_06.sqf",1597,1980],
    ["07","ITW_CLASH_PP_07.sqf",1981,2310],
    ["08","ITW_CLASH_PP_08.sqf",2311,2639]
];

{
    _x params ["_id","_probePath","_lineFrom","_lineTo"];
    private _exists = fileExists _probePath;
    private _raw = if (_exists) then {loadFile _probePath} else {""};
    private _plain = if (_exists) then {preprocessFile _probePath} else {""};
    private _numbered = if (_exists) then {preprocessFileLineNumbers _probePath} else {""};
    diag_log format [
        "CLASH PP | chunk=%1 | exists=%2 | lines=%3-%4 | raw=%5 | preprocess=%6 | lineNumbers=%7",
        _id,
        _exists,
        _lineFrom,
        _lineTo,
        count toArray _raw,
        count toArray _plain,
        count toArray _numbered
    ];
} forEach _chunks;

diag_log "CLASH PP | complete | chunks probed only; none executed";
true
