from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def test_menu_is_always_loaded_and_has_three_entry_points() -> None:
    init = source("initPlayerLocal.sqf")
    menu = source("ITW_CLASH_PlayerEmploymentMenu.sqf")
    description = source("description.ext")

    assert 'execVM "ITW_CLASH_PlayerEmploymentMenu.sqf"' in init
    assert "ITW_CLASH_PlayerEmployment_fnc_OpenMenu" in menu
    assert "addAction" in menu
    assert "BIS_fnc_addCommMenuItem" in menu
    assert "ace_interact_menu_fnc_addActionToObject" in menu
    assert "class ITW_CLASH_HALEmployment" in description


def test_all_job_types_are_visible_and_persistent() -> None:
    menu = source("ITW_CLASH_PlayerEmploymentMenu.sqf")
    support = source("ITW_CLASH_PlayerTaskSupport.sqf")
    for job_type in (
        "COMBAT",
        "TRANSPORT",
        "MEDEVAC",
        "LOGISTICS",
        "ARTILLERY",
    ):
        assert f'"{job_type}"' in menu
        assert f'"{job_type}"' in support

    assert "ITW_CLASH_PlayerJobSubscriptions" in menu
    assert "ITW_CLASH_PlayerJobSubscriptions" in support
    assert "vehicleResets=false" in menu
    assert "GetInMan" not in menu
    assert "GetOutMan" not in menu


def test_server_owns_subscription_mutation() -> None:
    support = source("ITW_CLASH_PlayerTaskSupport.sqf")
    menu = source("ITW_CLASH_PlayerEmploymentMenu.sqf")

    assert "ITW_CLASH_PlayerTasks_fnc_SetSubscriptionRemote" in support
    assert "remoteExecutedOwner == owner _player" in support
    assert "leader group _player == _player" in support
    assert '"ITW_CLASH_PlayerTasks_fnc_SetSubscriptionRemote",2' in menu
    assert '"ITW_CLASH_PlayerTasks_fnc_SetAllSubscriptionsRemote",2' in menu


def test_specialist_consumers_use_specific_channels() -> None:
    support = source("ITW_CLASH_PlayerTaskSupport.sqf")
    artillery = source("ITW_CLASH_PlayerArtilleryTasks.sqf")

    assert '[_group,"LOGISTICS"] call' in support
    assert '[_providerGroup,"LOGISTICS"] call' in support
    assert '[_group,"ARTILLERY"] call' in artillery
    assert '"ITW_CLASH_PlayerTaskOptIn",false' not in artillery


def test_subscription_is_not_reset_by_vehicle_or_completion() -> None:
    menu = source("ITW_CLASH_PlayerEmploymentMenu.sqf")
    support = source("ITW_CLASH_PlayerTaskSupport.sqf")
    artillery = source("ITW_CLASH_PlayerArtilleryTasks.sqf")

    assert "ITW_CLASH_PlayerJobSubscriptions" not in (
        artillery[artillery.index("ITW_CLASH_PlayerArtillery_fnc_FinishJob = {") :]
    )
    assert "ITW_CLASH_PlayerJobSubscriptions" not in (
        support[support.index("ITW_CLASH_PlayerTasks_fnc_PlayerAmmoJob = {") :]
    )
    assert "vehicle player" not in menu
    assert "assignedVehicle player" not in menu


def test_capability_changes_availability_without_changing_willingness() -> None:
    support = source("ITW_CLASH_PlayerTaskSupport.sqf")
    assert "ITW_CLASH_PlayerTasks_fnc_HasExecutableSubscription" in support
    assert "ITW_CLASH_PlayerTasks_fnc_HasPassengerCapacity" in support
    assert "ITW_CLASH_PlayerTasks_fnc_HasArtilleryCapability" in support
    assert "ITW_CLASH_PlayerTasks_fnc_GetSlingVehicle" in support
    assert '"ITW_CLASH_PlayerTaskOptIn",_active,true' in support
    assert '"Unable",!_executable,true' in support
