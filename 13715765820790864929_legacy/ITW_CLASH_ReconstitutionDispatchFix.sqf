if (!isServer) exitWith {};
if (missionNamespace getVariable ["ITW_CLASH_ReconstitutionDispatchFixStarted",false]) exitWith {};
ITW_CLASH_ReconstitutionDispatchFixStarted = true;

// ITW_Attack.sqf intentionally remains the authority for actually selecting,
// spawning, loading, registering and charging for the transport.  Its current
// dispatch function exits a named scope after success before its trailing
// `_dispatched` expression can execute, so a successful call returns nil even
// though the group and vehicle have already entered the transport state.
//
// init.sqf defers only this function's CompileFinal until this repair is in
// place.  Wait for the complete Attack file to finish defining its functions,
// then wrap the original and make the observable live transport state the
// return contract.
waitUntil {
    sleep 0.1;
    !isNil "ITW_AtkDispatchReconstitutionTransport" && {
        !isNil "ITW_AtkDeliveryCntChange"
    }
};
sleep 0.1;

ITW_CLASH_AtkDispatchReconstitutionTransport_V6Base = ITW_AtkDispatchReconstitutionTransport;

ITW_AtkDispatchReconstitutionTransport = {
    params ["_group","_requestId","_objectiveIndex","_lineage"];
    if (!isServer || {isNull _group}) exitWith {false};

    // The base dispatcher owns all side effects. Its return value is ignored
    // because the successful named-scope break currently returns nil.
    _this call ITW_CLASH_AtkDispatchReconstitutionTransport_V6Base;

    private _vehicle = _group getVariable ["ITW_CLASH_TransitVehicle",objNull];
    private _state = _group getVariable ["ITW_CLASH_TransitState",""];
    private _dispatched = (
        _state isEqualTo "transport" && {
            !isNull _vehicle && {alive _vehicle}
        }
    );

    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["reconstitution-dispatch-return",[
            _requestId,
            _lineage,
            _objectiveIndex,
            _dispatched,
            _state,
            if (isNull _vehicle) then {""} else {typeOf _vehicle}
        ]] call ITW_CLASH_fnc_Log;
    };
    _dispatched
};

private _deferred = missionNamespace getVariable [
    "ITW_CLASH_DeferredFinalizers",
    []
];
_deferred = _deferred - ["ITW_AtkDispatchReconstitutionTransport"];
missionNamespace setVariable ["ITW_CLASH_DeferredFinalizers",_deferred];

private _finalized = [
    "ITW_AtkDispatchReconstitutionTransport"
] call SKL_fnc_CompileFinal;

if (_finalized) then {
    diag_log "CLASH BOOT | reconstitution-dispatch-fix-ready | version=1";
} else {
    diag_log "CLASH BOOT | FAILED | reconstitution-dispatch-fix-finalization";
};