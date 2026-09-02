from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "13715765820790864929_legacy"


def mission(name: str) -> str:
    return (MISSION / name).read_text(encoding="utf-8")


def test_service_crews_are_exempt_without_replacing_native_impasse_cap_math():
    preinit = mission("preInit.sqf")

    assert '"ITW_AtkAiCount"' in preinit
    assert "ITW_CLASH_Cap_fnc_NativeAtkAiCount = ITW_AtkAiCount;" in preinit
    assert "_native + ([_side] call ITW_CLASH_Cap_fnc_ExemptUnits)" in preinit
    assert 'getVariable ["ITW_CLASH_CapExempt",false]' in preinit
    assert 'getVariable ["ITW_CLASH_CASEVAC",false]' in preinit
    assert 'getVariable ["ITW_CLASH_GroundMEDEVAC",false]' in preinit
    assert 'serviceCrewsExempt=true combatManpowerNative=true' in preinit


def test_service_lifecycle_virtualizes_transport_and_logistics_but_not_artillery():
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")

    assert '"TRANSPORT"' in service
    assert '"LOGISTICS_AMMO"' in service
    assert '"LOGISTICS_FUEL"' in service
    assert '"LOGISTICS_REPAIR"' in service

    service_capabilities = service[
        service.index("ITW_CLASH_Service_fnc_IsCapability ="):
        service.index("ITW_CLASH_Service_fnc_ModeForVehicle =")
    ]
    assert '"ARTILLERY"' not in service_capabilities

    assert 'setVariable ["ITW_CLASH_CapExempt",true]' in service
    assert 'set ["state","RTB"]' in service
    assert 'set ["state","AVAILABLE"]' in service
    assert '"virtualized"' in service
    assert '"reactivated"' in service
    assert '["ticketCost",0]' in service
    assert '["reused",true]' in service
    assert "ITW_CLASH_Service_fnc_MarkTrackerReleased" in service
    assert service.index(
        'if !([_veh] call ITW_CLASH_Service_fnc_MarkTrackerReleased) exitWith {false};'
    ) < service.index("deleteVehicleCrew _veh;")
    assert "artilleryPersistent=true" in service


def test_service_rtb_takes_final_leg_from_hal_and_has_stuck_watchdog():
    service = mission("ITW_CLASH_ServiceLifecycle.sqf")

    assert "ITW_CLASH_Service_fnc_RemoveHALOwnership" in service
    assert "ITW_CLASH_Service_fnc_OrderRTB" in service
    assert 'setWaypointType "MOVE"' in service
    assert 'setWaypointBehaviour "CARELESS"' in service
    assert 'setWaypointCombatMode "BLUE"' in service
    assert "ITW_CLASH_ServiceProgressTimeout = 75;" in service
    assert "ITW_CLASH_ServiceHardStuckTimeout = 210;" in service
    assert '"hal-rtb-takeover"' in service
    assert '"rtb-reissued"' in service
    assert '"stuck-safe-retire"' in service

    # Existing Impasse transports must lose stale assault orders at HAL handoff.
    assert "ITW_CLASH_Service_fnc_StageFieldVehicleBase" in service
    assert "RYD_WPdel" in service
    assert "staleHandoffSanitized=true" in service


def test_reconstitution_origin_and_withdrawal_rally_are_the_forward_fob():
    dispatch = mission("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    gtfo = mission("ITW_CLASH_GTFO_Bookkeeping.sqf")

    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in dispatch
    assert '"RECONSTITUTION","FORWARD"' in dispatch
    assert "ITW_ATTACK_LAND_F" in dispatch
    assert "ITW_ATTACK_LAND_E" in dispatch
    assert '"reconstitution-forward-fob-spawn"' in dispatch
    assert '"reconstitution-forward-fob-ai-spawn"' in dispatch

    assert "ITW_CLASH_GTFO_fnc_RefreshCorridor_SupportBase" in gtfo
    assert "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn" in gtfo
    assert 'setVariable ["RydHQ_RestDecoy",ITW_CLASH_GTFO_RestDecoy]' in gtfo
    assert '"forward-fob-corridor"' in gtfo
    assert "forwardFOB=true" in gtfo


def test_reconstitution_transport_cannot_be_stolen_before_dismount():
    dispatch = mission("ITW_CLASH_ReconstitutionDispatchFix.sqf")
    transit = mission("ITW_CLASH_ReconstitutionTransitFix.sqf")
    dual = mission("ITW_CLASH_DualHALCheckbook.sqf")

    reserve = '_veh setVariable ["ITW_CLASH_ReconstitutionTransport",true,true];'
    add_vehicle = "[_vehInfo,false,false] call ITW_AtkAddVehicle;"
    assert reserve in dispatch
    assert dispatch.index(reserve) < dispatch.index(add_vehicle)
    assert 'getVariable ["ITW_CLASH_ReconstitutionTransport",false]' in dual

    assert "ITW_CLASH_Reconstitution_fnc_ReleaseTransportReservation" in transit
    assert 'setVariable ["ITW_CLASH_ReconstitutionTransport",nil,true]' in transit
    assert '"physical-dismount"' in transit
    assert '"ao-handoff"' in transit
    assert '"reconstitution-transport-released"' in transit
    assert '"forward-fob"' in transit


def test_boats_are_restored_to_bounded_surface_water_or_rejected_atomically():
    sea = mission("ITW_CLASH_SeaGenerationGuard.sqf")
    logistics = mission("ITW_CLASH_HALLogistics.sqf")

    assert 'isKindOf "Ship"' in sea
    assert "ITW_SeaPoints" in sea
    assert "surfaceIsWater" in sea
    assert "ITW_CLASH_SeaGuardMaxRelocation" in sea
    assert '"ITW_CLASH_SeaGuardMaxRelocation",1500' in sea
    assert "_x distance2D _reference <= ITW_CLASH_SeaGuardMaxRelocation" in sea
    assert "_veh setPosASL _water;" in sea
    assert '"ASL-surface"' in sea
    assert '"sea-node-too-far"' in sea
    assert '"no-local-water-node"' in sea
    assert '"impasse-handoff"' in sea
    assert '"generated-asset"' in sea
    assert '"handoff-rejected"' in sea
    assert "deleteVehicleCrew _veh;" in sea
    assert "atomicReject=true" in sea

    # Sea guard is deliberately outermost: service lifecycle first, then water
    # correction around the final StageFieldVehicle/RegisterAsset stack.
    service_load = 'preprocessFileLineNumbers\n        "ITW_CLASH_ServiceLifecycle.sqf"'
    sea_load = 'preprocessFileLineNumbers\n        "ITW_CLASH_SeaGenerationGuard.sqf"'
    assert service_load in logistics
    assert sea_load in logistics
    assert logistics.index(service_load) < logistics.index(sea_load)



def test_air_transport_quarantine_preserves_hal_air_identity_and_is_immediate():
    stability = mission("ITW_CLASH_ServiceStability.sqf")
    authority = mission("ITW_CLASH_ServiceAuthority.sqf")

    assert "ITW_CLASH_ServiceStabilityVersion = 2;" in stability
    quarantine = stability.split(
        "ITW_CLASH_ServiceStability_fnc_EnsureQuarantine = {", 1
    )[1].split("ITW_CLASH_ServiceStability_fnc_RetireBase", 1)[0]
    assert 'forEach ["RydHQ_CargoG","RydHQ_CargoOnly"];' in quarantine
    assert '_veh isKindOf "Air"' in quarantine
    assert 'getVariable ["RydHQ_AirG",[]]' in quarantine
    assert '_hq setVariable ["RydHQ_AirG",_air];' in quarantine
    assert '_changed pushBack "RydHQ_AirG";' in quarantine
    assert "transportAirMembership=true" in stability

    assert "ITW_CLASH_ServiceAuthorityVersion = 3;" in authority
    handoff = authority.split(
        "ITW_CLASH_DualHAL_fnc_StageFieldVehicle = {", 1
    )[1].split("ITW_CLASH_ServiceAuthorityReady = true;", 1)[0]
    immediate = '[_group,"impasse-handoff-immediate"] call'
    assert immediate in handoff
    assert "ITW_CLASH_ServiceStability_fnc_EnsureQuarantine" in handoff
    assert handoff.index(immediate) < handoff.index(
        'if (_result && {!isNull _veh} && {'
    )
    assert "immediateTransportQuarantine=true" in authority
