from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def before(text: str, left: str, right: str) -> None:
    assert left in text, left
    assert right in text, right
    assert text.index(left) < text.index(right), (left, right)


def test_boot_loads_transport_before_player_tasks() -> None:
    text = source("init.sqf")
    before(
        text,
        '"ITW_CLASH_PlayerTransportAuthority.sqf"',
        '"ITW_CLASH_PlayerTaskSupport.sqf"',
    )
    assert "playerTransport=%3 playerTasks=%4" in text
    assert "&& {_playerTransportLoaded isEqualTo true}" in text
    assert "&& {_playerTasksLoaded isEqualTo true}" in text


def test_dedicated_client_bridges_native_hal_actions() -> None:
    init = source("initPlayerLocal.sqf")
    client = source("ITW_CLASH_PlayerTaskClient.sqf")
    assert 'execVM "ITW_CLASH_PlayerTaskClient.sqf"' in init
    assert "ITW_CLASH_PlayerTasks_fnc_SetOptInRemote" in client
    assert "ITW_CLASH_PlayerTasks_fnc_CancelRemote" in client
    assert "Action2ct =" in client
    assert "Action3ct =" in client


def test_player_task_support_preserves_hal_authority() -> None:
    text = source("ITW_CLASH_PlayerTaskSupport.sqf")
    assert '"EnableHALActions",true,true' in text
    assert "ITW_CLASH_PlayerTaskOptIn" in text
    assert "ITW_CLASH_PlayerTaskGroups" in text
    assert "ITW_CLASH_DualHALManaged" not in text
    assert "ITW_CLASH_PlayerTasks_fnc_NativeGoAmmoSupp" in text
    assert "_this call ITW_CLASH_PlayerTasks_fnc_NativeGoAmmoSupp" in text


def test_package_contract_is_physical_and_generation_node_bound() -> None:
    text = source("ITW_CLASH_PlayerTaskSupport.sqf")
    assert '"LOGISTICS_PACKAGE_AMMO"' in text
    assert '"REAR_AIR"' in text
    assert "ITW_CLASH_Generation_fnc_Resolve" in text
    assert "_class createVehicle _spawn" in text
    assert "_box setAmmoCargo 1" in text
    assert '"ITW_OUTSTANDING_PACKAGE_CAP_V1"' in text
    assert '["ticketCost",0]' in text
    assert "canSlingLoad" in text


def test_hal_logistics_requests_carrier_and_package() -> None:
    text = source("ITW_CLASH_HALLogistics.sqf")
    assert '[_hq,"LOGISTICS_AMMO","AIR"]' in text
    assert '[_hq,"LOGISTICS_PACKAGE_AMMO","AIR"]' in text
    assert "RydHQ_AmmoBoxes" in text
    assert "physicalAmmoPackage=true" in text


def test_standing_delivery_reserves_before_hal_observation() -> None:
    attack = source("ITW_Attack.sqf")
    before(
        attack,
        '[_grp,"itw-standing-delivery"]',
        "[_grp] call ITW_AtkAddInfantryGroup;",
    )
    sideops = source("ITW_SideOps.sqf")
    before(
        sideops,
        '[_grp,"itw-sideop-delivery"]',
        "[_grp] call ITW_AtkAddInfantryGroup;",
    )


def test_ferry_authority_wraps_native_physical_lifecycle() -> None:
    ally = source("ITW_Ally.sqf")
    before(
        ally,
        '[_grp,_veh,"player-ferry-boarding"]',
        '_grp setVariable ["ITW_getInState",0]',
    )
    before(
        ally,
        '"ITW_CLASH_TransportPhysicalUnloadPending",true',
        'scriptName "ITW_LoadGroupIntoVeh_GetOut"',
    )
    before(
        ally,
        '{_x doMove _toPos} forEach units _grp',
        '[_grp,"player-ferry-delivered"]',
    )
    authority = source("ITW_CLASH_PlayerTransportAuthority.sqf")
    assert '"ITW_CLASH_AuthorityHold",true' in authority
    assert '"ITW_CLASH_TransportPhysicalUnloadPending",false' in authority
    release_start = authority.index("ITW_CLASH_PlayerTransport_fnc_Release =")
    release_end = authority.index("// Observe HAL's actual cargo request", release_start)
    release = authority[release_start:release_end]
    assert 'setVariable ["ITW_CLASH_AuthorityHold",nil]' in release
    assert 'setVariable ["Unable",_group getVariable ["ITW_CLASH_TransportPreviousUnable",false],true]' in release
    assert 'setVariable ["BUnable",_group getVariable ["ITW_CLASH_TransportPreviousBUnable",false],true]' in release


def test_native_high_command_is_gated_under_clash() -> None:
    for name in ("ITW_Attack.sqf", "ITW_Ally.sqf"):
        text = source(name)
        assert "ITW_CLASH_DisableNativeHC" in text


def test_job_completion_requires_real_sling_delivery() -> None:
    text = source("ITW_CLASH_PlayerTaskSupport.sqf")
    assert "ropeAttachedTo _box" in text
    assert "_box distance2D _target <= ITW_CLASH_PlayerAmmoDeliveryRadius" in text
    assert "isTouchingGround _box" in text
    assert "abs speed _box < 5" in text
    assert '"participants",_roster' in text


def test_known_expression_regressions_are_absent() -> None:
    text = source("ITW_CLASH_PlayerTaskSupport.sqf")
    assert "isEqualTo createHashMap" not in text
    assert "(allPlayers findIf {_x distance2D _box < 100}) < 0" in text


def test_native_hal_employment_actions_remain_visible_in_vehicles() -> None:
    text = (ROOT / "NR6 Hal" / "addons" / "nr6_hal" / "TaskInitNR6.sqf").read_text(
        encoding="utf-8"
    )
    for function_name in ("Action1fnc", "Action2fnc", "Action3fnc", "ActionMfnc"):
        start = text.index(f"{function_name} = {{")
        end = text.index("\n};", start)
        block = text[start:end]
        assert "_this isEqualTo _target" in block
        assert "_target isEqualTo (vehicle player)" not in block


def test_player_artillery_deployment_is_vehicle_sized_and_fail_closed() -> None:
    text = source("ITW_CLASH_PlayerGarageDeployment.sqf")
    assert "ITW_CLASH_PlayerGarageDeploymentVersion = 3;" in text
    assert "ITW_CLASH_PlayerGarage_fnc_FindSafeDestination" in text
    assert "boundingBoxReal _vehicle" in text
    assert "BIS_fnc_findSafePos" in text
    assert "findEmptyPosition [0,125,_class]" in text
    assert "surfaceIsWater _candidate" in text
    assert "surfaceNormal _candidate" in text
    assert "nearestObjects" in text
    assert "nearestTerrainObjects" in text
    assert '"no-clear-vehicle-sized-deployment-slot"' in text
    assert "setPosATL _position" not in text
    assert "setVehiclePosition [_destination,[],0,\"NONE\"]" in text
    assert "_vehicle allowDamage false" in text
    assert "player allowDamage false" in text
    assert "sleep 2" in text
    assert "driver _vehicle != player" in text
    assert 'toLowerANSI _role != "driver"' in text
    before(
        text,
        "private _safePosition = [",
        '"resolved-safe"',
    )



def test_clash_snips_native_impasse_ambient_player_ferry() -> None:
    bridge = source("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert "ITW_CLASH_PlayerTransportNativeBridgeVersion = 6;" in bridge
    manager = bridge.split("ITW_AllyLoadIntoVehManager = {", 1)[1].split(
        "ITW_AllyLoadGrpIntoVeh = ITW_CLASH_PlayerTransport_fnc_NativeLoadGrpIntoVeh;",
        1,
    )[0]

    assert '"native-proximity-ferry-disabled"' in manager
    assert '"hal-scargo-sole-dispatch"' in manager
    assert '"no-unsolicited-player-pickup"' in manager
    assert "forEach vehicles" not in manager
    assert "ITW_ObjGetNearest" not in manager
    assert "ITW_reservedGroups" not in manager
    assert "spawn ITW_AllyLoadGrpIntoVeh" not in manager
    assert "nativeITWFerryPreserved=false" in bridge
    assert "ambientProximityFerry=false" in bridge
    assert "unsolicitedPlayerPickup=false" in bridge


def test_hal_scargo_transport_authority_remains_intact_after_native_ferry_snip() -> None:
    authority = source("ITW_CLASH_PlayerTransportAuthority.sqf")
    bridge = source("ITW_CLASH_PlayerTransportNativeBridge.sqf")

    assert "ITW_CLASH_PlayerTransport_fnc_SCargoBase = HAL_SCargo;" in authority
    assert "HAL_SCargo = {" in authority
    assert "_this call ITW_CLASH_PlayerTransport_fnc_SCargoBase" in authority
    assert "ITW_CLASH_PlayerTransport_fnc_ObserveHALDemand" in bridge
    assert "halPhysicalExecutor=true" in bridge
