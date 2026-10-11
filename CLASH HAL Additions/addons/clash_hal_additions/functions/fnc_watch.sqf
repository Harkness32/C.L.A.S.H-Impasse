/*
    CLASH_fnc_HALAdd_Watch

    Independent response loop for threat categories HAL classifies but does not
    normally counter-dispatch. This is a *consumer* of HAL state, never an owner
    of HAL transport, logistics, withdrawal, or initialization.

    Candidate pools are filtered before Respond sees them. A group reserved for
    transport/service/withdrawal cannot become an Additions combat responder.
*/

params ["_HQname"];

if (isNil _HQname) exitWith {};
private _HQobj = missionNamespace getVariable _HQname;
if (isNil "_HQobj" || {isNull _HQobj}) exitWith {};
private _HQ = group _HQobj;

diag_log format [
    "CLASHHALADD | watch-start | hq=%1 nativeHALCore=true",
    _HQname
];

while {!isNull _HQ} do
{
    private _reserved = [];
    {
        _reserved append +(_HQ getVariable [_x,[]]);
    } forEach [
        "RydHQ_NoAttack",
        "RydHQ_CargoOnly",
        "RydHQ_CargoG",
        "RydHQ_SupportG",
        "RydHQ_AmmoDrop",
        "RydHQ_Exhausted"
    ];
    _reserved = _reserved arrayIntersect _reserved;

    private _available =
    {
        params ["_groups"];
        private _unique = _groups arrayIntersect _groups;
        _unique select {
            private _group = _x;
            !isNull _group
            && {!(_group in _reserved)}
            && {!(_group getVariable ["ITW_CLASH_ServiceAsset",false])}
            && {!(_group getVariable ["CargoM" + str _group,false])}
        }
    };

    private _snipersG = [
        +(_HQ getVariable ["RydHQ_snipersG",[]])
    ] call _available;

    private _NCrewInfG = [
        (+(_HQ getVariable ["RydHQ_NCrewInfG",[]]))
        - (+(_HQ getVariable ["RydHQ_SpecForG",[]]))
    ] call _available;

    private _LArmorG = [
        +(_HQ getVariable ["RydHQ_LArmorG",[]])
    ] call _available;

    private _HArmorG = [
        +(_HQ getVariable ["RydHQ_HArmorG",[]])
    ] call _available;

    private _cars = [
        (+(_HQ getVariable ["RydHQ_CarsG",[]]))
        - (
            +(_HQ getVariable ["RydHQ_ATInfG",[]])
            + (_HQ getVariable ["RydHQ_AAInfG",[]])
            + (_HQ getVariable ["RydHQ_SupportG",[]])
        )
    ] call _available;

    // Approximation of HAL's internal CAS merge. Transport/service aircraft are
    // removed by the same reservation filter before they can be candidates.
    private _airCAS = [
        +(_HQ getVariable ["RydHQ_RCAS",[]])
        + (_HQ getVariable ["RydHQ_BAirG",[]])
    ] call _available;

    private _categories =
    [
        ["AAInf",    _HQ getVariable ["RydHQ_EnAAinf",[]],    [[_snipersG,0.5,"SNP"],[_LArmorG,1,"ARM"],[_cars,1,"INF"],[_NCrewInfG,0.5,"INF"]], 0,  0, 85],
        ["StaticAA", _HQ getVariable ["RydHQ_EnStaticAA",[]], [[_LArmorG,1,"ARM"],[_HArmorG,1,"ARM"],[_cars,1,"INF"],[_NCrewInfG,0.5,"INF"],[_snipersG,0.5,"SNP"]], 0,  0, 85],
        ["StaticAT", _HQ getVariable ["RydHQ_EnStaticAT",[]], [[_airCAS,2,"AIR"],[_NCrewInfG,0.5,"INF"],[_snipersG,0.5,"SNP"]],                    75, 80,  0],
        ["Support",  _HQ getVariable ["RydHQ_EnSupport",[]],  [[_cars,1,"INF"],[_airCAS,1,"AIR"],[_LArmorG,0.5,"ARM"]],                            75, 80, 85],
        ["Cargo",    _HQ getVariable ["RydHQ_EnCargo",[]],    [[_cars,1,"INF"],[_airCAS,1,"AIR"],[_NCrewInfG,0.5,"INF"]],                          75, 80, 85]
    ];

    {
        _x params [
            "_kind","_threatGroups","_pool",
            "_atrr1","_atrr2","_aarisk"
        ];
        if (count _threatGroups > 0) then
        {
            [
                _threatGroups,_kind,_HQ,_pool,
                _atrr1,_atrr2,_aarisk
            ] call CLASH_fnc_HALAdd_Respond;
        };
    } forEach _categories;

    sleep 20;
};

diag_log format ["CLASHHALADD | watch-stop | hq=%1",_HQname];
