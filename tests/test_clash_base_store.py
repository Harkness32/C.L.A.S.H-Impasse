"""Static regression assertions for the C.L.A.S.H. base store.

These guard the invariants that CT_WEBBROWSER fails silently on. Every one of
them presents in game as "the menu is dead" or "the menu is frozen" rather than
as an error in the RPT, which is why they are pinned here rather than left to
review.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "13715765820790864929_legacy"

STORE_SQF = (
    "ITW_CLASH_Store.sqf",
    "ITW_CLASH_StoreBridge.sqf",
    "ITW_CLASH_StoreCatalog.sqf",
    "ITW_CLASH_StoreServer.sqf",
    "ITW_CLASH_StoreClient.sqf",
)


def source(name: str) -> str:
    return (LEGACY / name).read_text(encoding="utf-8")


def section(text: str, start: str, end: str | None = None) -> str:
    body = text[text.index(start):]
    if end is not None and end in body[len(start):]:
        body = body[: body.index(end, len(start))]
    return body


# --------------------------------------------------------------- wiring ----


def test_store_files_exist_and_are_loaded_in_the_right_place() -> None:
    pre_init = source("preInit.sqf")
    init_player = source("initPlayerLocal.sqf")

    for name in STORE_SQF + (
        "ui/StoreDialog.hpp",
        "ui/html/store.html",
        "ui/html/store.css",
        "ui/html/store.js",
    ):
        assert (LEGACY / name).is_file(), f"missing {name}"

    # Shared config must be compiled before the catalog and server read its
    # pricing and funds seams.
    for name in (
        "ITW_CLASH_Store.sqf",
        "ITW_CLASH_StoreCatalog.sqf",
        "ITW_CLASH_StoreServer.sqf",
        "ITW_CLASH_StoreBridge.sqf",
    ):
        assert name in pre_init, f"{name} is not loaded from preInit.sqf"

    assert pre_init.index("ITW_CLASH_Store.sqf") < pre_init.index(
        "ITW_CLASH_StoreCatalog.sqf"
    )
    assert pre_init.index("ITW_CLASH_StoreCatalog.sqf") < pre_init.index(
        "ITW_CLASH_StoreServer.sqf"
    )

    # The client is interface-only and belongs in initPlayerLocal.
    assert 'execVM "ITW_CLASH_StoreClient.sqf"' in init_player
    assert "ITW_CLASH_StoreClient.sqf" not in pre_init


def test_page_path_is_allowlisted_and_dialog_is_registered() -> None:
    description = source("description.ext")
    dialog = source("ui/StoreDialog.hpp")
    gui_defines = source("defines_gui.hpp")

    # Without the CfgCommands allowlist the page renders and is never given the
    # A3API binding, so the interface can never talk to SQF.
    assert "class CfgCommands" in description
    assert "allowedHTMLLoadURIs[] +=" in description, "must extend, not replace"
    assert r'"ui\\html\\*"' in description, "doubled backslashes are required"

    assert "#include \"ui\\StoreDialog.hpp\"" in description

    # The control must be the browser type and transparent, or the 3D preview
    # behind it is invisible.
    assert "type = 106" in dialog
    assert "colorBackground[] = {0, 0, 0, 0}" in dialog
    assert "url = \"ui\\html\\store.html\"" in dialog

    assert "ITW_CLASH_STORE_IDD" in gui_defines
    assert "ITW_CLASH_STORE_BROWSER_IDC" in gui_defines


def test_client_includes_the_gui_defines_it_uses() -> None:
    client = source("ITW_CLASH_StoreClient.sqf")

    # The IDD/IDC macros live in defines_gui.hpp; without the include they
    # expand to nothing and every display lookup silently misses.
    assert "ITW_CLASH_STORE_BROWSER_IDC" in client
    assert '#include "defines_gui.hpp"' in client


# -------------------------------------------------------- engine pitfalls ----


def test_jsdialog_handler_returns_a_boolean() -> None:
    client = source("ITW_CLASH_StoreClient.sqf")

    assert 'ctrlAddEventHandler ["JSDialog"' in client

    handler = section(
        client,
        "ITW_CLASH_Store_fnc_HandleUiEvent = {",
        "ITW_CLASH_Store_fnc_ReceiveResponse = {",
    )

    # The engine blocks the browser until the handler answers. Every path must
    # end in a boolean; a frozen store is the symptom of forgetting.
    assert "\n    true\n};" in handler, "handler must return true"
    assert 'if (_event isEqualTo "") exitWith { true };' in handler


def test_execjs_is_ascii_guarded_and_queued_until_the_page_is_up() -> None:
    bridge = source("ITW_CLASH_StoreBridge.sqf")

    # ExecJS reads its input as single-byte text; anything above 127 must be
    # escaped or it arrives corrupted.
    assert "ITW_CLASH_Store_fnc_WebAction" in bridge
    assert "_x > 127" in bridge
    assert r'"\u%1%2%3%4"' in bridge

    # ExecJS raised before the page is ready is dropped, not queued.
    assert "ITW_CLASH_StoreBridge_Queues" in bridge
    assert "ITW_CLASH_Store_fnc_BridgeMarkReady" in bridge

    client = source("ITW_CLASH_StoreClient.sqf")
    # Both readiness signals are wired: the documented event and the page's own
    # first message, because which arrives first is a race.
    assert 'ctrlAddEventHandler ["PageLoaded"' in client
    assert "call ITW_CLASH_Store_fnc_BridgeMarkReady" in client


def test_inbound_message_cap_is_enforced_and_cart_is_chunked() -> None:
    bridge = source("ITW_CLASH_StoreBridge.sqf")
    page = source("ui/html/store.js")
    server = source("ITW_CLASH_StoreServer.sqf")

    # page -> SQF truncates at exactly 10240 characters, silently.
    assert "ITW_CLASH_StoreBridge_MessageCap = 10240" in bridge
    assert "message-at-engine-cap" in bridge

    assert "MESSAGE_CAP = 10240" in page
    assert "CHUNK_BUDGET" in page
    assert "store::cartChunk" in page

    # A part-delivered order must be refused outright, never part-filled.
    assert "ITW_CLASH_Store_fnc_RequestCartChunk" in server
    assert "_missing" in server
    assert "did not arrive intact" in server


def test_checkout_cannot_latch_on_a_lost_reply() -> None:
    page = source("ui/html/store.js")

    # checkoutPending is cleared by the server's verdict. If that verdict never
    # arrives the Purchase button stays disabled for the rest of the session,
    # so a timeout has to release it.
    assert "CHECKOUT_TIMEOUT_MS" in page
    assert "clearCheckoutPending" in page

    checkout = page[page.index("function checkout()"):]
    checkout = checkout[: checkout.index("function clearCheckoutPending")]
    assert "state.checkoutTimer = window.setTimeout" in checkout

    # ...and the verdict path must cancel the timer rather than racing it.
    result = page[page.index("function checkoutResult("):]
    result = result[: result.index("\n  function ")]
    assert "clearCheckoutPending()" in result


def test_texture_stub_is_rejected() -> None:
    page = source("ui/html/store.js")

    # RequestTexture fails by resolving with a short stub that reads as
    # success, so the result must be checked for an actual image.
    assert "isTextureSource" in page
    assert 'indexOf("data:image/") === 0' in page


def test_page_loads_assets_without_script_src() -> None:
    html = source("ui/html/store.html")

    # The page is handed to the browser as a blob: URL and has no resolvable
    # base, so <script src> to a mission path cannot work.
    assert "A3API.RequestFile" in html
    assert "<scriptsrc=" not in html.replace(" ", "")

    # The no-A3API fallback is what makes the page openable in a desktop
    # browser for layout work.
    assert 'typeof A3API !== "undefined"' in html


# ------------------------------------------------------------- authority ----


def test_server_owns_prices_balances_and_delivery() -> None:
    config = source("ITW_CLASH_Store.sqf")
    server = source("ITW_CLASH_StoreServer.sqf")

    # Wallet mutation is server-only and says so at runtime.
    charge = section(
        config,
        "ITW_CLASH_Store_fnc_WalletCharge = {",
        "ITW_CLASH_Store_fnc_WalletCredit = {",
    )
    assert "if (!isServer) exitWith" in charge
    assert "charge-off-server" in charge

    # Nothing is delivered before the charge succeeds.
    checkout = section(server, "ITW_CLASH_Store_fnc_Checkout = {")
    charge_at = checkout.index("ITW_CLASH_Store_fnc_WalletCharge")
    assert charge_at < checkout.index("ITW_CLASH_Store_fnc_SpawnVehicle")
    assert charge_at < checkout.index("ITW_CLASH_Store_fnc_ApplyGear")

    # The catalog is the allowlist: a made-up classname never reaches delivery.
    assert "ITW_CLASH_Store_fnc_FindCatalogItem" in checkout
    assert "is not sold here" in checkout


def test_every_request_is_ownership_checked() -> None:
    server = source("ITW_CLASH_StoreServer.sqf")
    client = source("ITW_CLASH_StoreClient.sqf")

    # One client must not be able to shop as another.
    assert (
        "remoteExecutedOwner > 2 && { remoteExecutedOwner isNotEqualTo _owner }"
        in server
    )
    assert "owner-mismatch" in server
    assert "chunk-owner-mismatch" in server

    # Gear and loadout approval arrive from the server only.
    for function in (
        "ITW_CLASH_Store_fnc_ApplyGear = {",
        "ITW_CLASH_Store_fnc_LoadoutApprove = {",
        "ITW_CLASH_Store_fnc_ReceiveResponse = {",
    ):
        body = section(client, function)[:2000]
        assert "remoteExecutedOwner isNotEqualTo 2" in body, function


def test_access_is_revalidated_on_every_request_not_just_on_open() -> None:
    server = source("ITW_CLASH_StoreServer.sqf")

    for request in (
        "ITW_CLASH_Store_fnc_RequestHydrate = {",
        "ITW_CLASH_Store_fnc_RequestCategory = {",
        "ITW_CLASH_Store_fnc_RequestCheckout = {",
        "ITW_CLASH_Store_fnc_RequestLoadoutApply = {",
    ):
        body = section(server, request)[:1400]
        assert "ITW_CLASH_Store_fnc_ValidateAccess" in body, request

    validate = section(
        server,
        "ITW_CLASH_Store_fnc_ValidateAccess = {",
        "ITW_CLASH_Store_fnc_BuildHydratePayload = {",
    )
    assert "ITW_CLASH_StoreAccessRange" in validate
    assert "ITW_BASE_SPAWNED" in validate
    assert "alive _player" in validate
    assert "ITW_PlayerSide" in validate


# -------------------------------------------------------------- doctrine ----


def test_store_does_not_touch_the_ai_ticket_budget_or_checkbook() -> None:
    joined = "".join(source(name) for name in STORE_SQF)

    # Vehicle tickets are HAL's AI spawn budget. A player purchase must not
    # compete with force generation for one.
    for forbidden in (
        "ITW_VEH_CURR_TICKETS",
        "ITW_VEH_REQD_TICKETS",
        "ITW_TICKET_REDUCE",
        "ITW_CLASH_fnc_RequestCapability",
        "ITW_CLASH_CheckbookProviders",
    ):
        assert forbidden not in joined, f"store must not reference {forbidden}"


def test_catalog_reads_the_pools_the_mission_already_maintains() -> None:
    catalog = source("ITW_CLASH_StoreCatalog.sqf")

    # Inheriting these pools is what makes faction/DLC/map gating free.
    for pool in (
        "BIS_fnc_getVirtualWeaponCargo",
        "BIS_fnc_getVirtualMagazineCargo",
        "BIS_fnc_getVirtualItemCargo",
        "BIS_fnc_getVirtualBackpackCargo",
        "va_pAllVehicles",
    ):
        assert pool in catalog, f"catalog should read {pool}"

    # Impasse is PvE: there is no second player faction, so the enemy arrays
    # must never become a player-purchasable catalog.
    assert "va_eAllVehicles" not in catalog
    assert "va_eCarClasses" not in catalog


def test_pricing_is_a_table_and_ships_disabled() -> None:
    config = source("ITW_CLASH_Store.sqf")

    assert "ITW_CLASH_StoreEconomyEnabled = false" in config
    assert "ITW_CLASH_StorePrices = createHashMap" in config
    assert "ITW_CLASH_StoreCategoryPrices" in config

    # Price resolution: free-list, then exact class, then category, then 0.
    price = section(
        config,
        "ITW_CLASH_Store_fnc_PriceOf = {",
        "ITW_CLASH_Store_fnc_WalletBalance = {",
    )
    assert "if (!ITW_CLASH_StoreEconomyEnabled) exitWith { 0 }" in price
    assert price.index("ITW_CLASH_StoreFreeClasses") < price.index(
        "ITW_CLASH_StorePrices"
    )
    assert price.index("ITW_CLASH_StorePrices") < price.index(
        "ITW_CLASH_StoreCategoryPrices"
    )

    # No derived pricing: that was the part deliberately left out.
    for heuristic in ("boundingBoxReal", '>> "mass"', "BIS_fnc_itemType"):
        assert heuristic not in price


def test_saved_loadouts_are_profile_local_and_priced_through_the_server() -> None:
    client = source("ITW_CLASH_StoreClient.sqf")
    server = source("ITW_CLASH_StoreServer.sqf")

    assert 'profileNamespace setVariable ["ITW_CLASH_StoreLoadouts"' in client
    assert "saveProfileNamespace" in client

    # Loading must not be a free-gear route once the economy is on: only the
    # class list travels, the server charges, and the verdict comes back.
    assert "ITW_CLASH_Store_fnc_LoadoutClassList" in client
    assert '"ITW_CLASH_Store_fnc_RequestLoadoutApply", 2' in client

    apply_request = section(
        server,
        "ITW_CLASH_Store_fnc_RequestLoadoutApply = {",
        "ITW_CLASH_Store_fnc_SpawnVehicle = {",
    )
    assert "ITW_CLASH_Store_fnc_WalletCharge" in apply_request
    assert apply_request.index(
        "ITW_CLASH_Store_fnc_WalletCharge"
    ) < apply_request.index("ITW_CLASH_Store_fnc_LoadoutApprove")


def test_preview_is_a_local_scene_and_never_server_side() -> None:
    client = source("ITW_CLASH_StoreClient.sqf")

    preview = section(
        client,
        "ITW_CLASH_Store_fnc_PreviewOpen = {",
        "ITW_CLASH_Store_fnc_PreviewClose = {",
    )

    # Local only: nothing in the preview may exist for other players.
    assert "createVehicleLocal" in preview
    assert "createVehicle [" not in preview
    assert "worldSize + 1000" in preview, "scene must sit outside the play area"

    # Everything created must be destroyed on unload or it leaks per open.
    close = section(
        client,
        "ITW_CLASH_Store_fnc_PreviewClose = {",
        "ITW_CLASH_Store_fnc_PreviewUpdateCamera = {",
    )
    for created in ("man", "model", "light", "backdrop"):
        assert f'deleteVehicle (_state get "{created}")' in close, created
    assert "camDestroy" in close
    assert 'cameraEffect ["Terminate", "Back"]' in close

    assert "call ITW_CLASH_Store_fnc_PreviewClose" in client


# -------------------------------------------------------------- protocol ----


def test_page_and_sqf_agree_on_the_event_protocol() -> None:
    page = source("ui/html/store.js")
    client = source("ITW_CLASH_StoreClient.sqf")

    emitted = set(re.findall(r'"(store::[a-zA-Z]+)"', page))
    handled = set(re.findall(r'case "(store::[a-zA-Z]+)"', client))

    assert emitted, "page emits no events"
    assert emitted == handled, (
        f"page-only: {sorted(emitted - handled)}, "
        f"sqf-only: {sorted(handled - emitted)}"
    )

    # SQF -> page events the interface must understand.
    for event in ("hydrate", "category", "checkout", "loadouts", "previewStatus"):
        assert f'case "{event}"' in page, f"page cannot receive {event}"


def test_store_functions_are_all_defined() -> None:
    joined = "".join(source(name) for name in STORE_SQF)

    defined = set(
        re.findall(
            r"^\s*(ITW_CLASH_Store_fnc_[A-Za-z0-9_]+)\s*=",
            joined,
            re.MULTILINE,
        )
    )
    referenced = set(re.findall(r"ITW_CLASH_Store_fnc_[A-Za-z0-9_]+", joined))
    referenced |= set(
        re.findall(
            r"ITW_CLASH_Store_fnc_[A-Za-z0-9_]+", source("ui/StoreDialog.hpp")
        )
    )

    assert defined, "no store functions found"
    assert not (referenced - defined), (
        f"referenced but never defined: {sorted(referenced - defined)}"
    )


def test_order_ceilings_are_enforced_server_side() -> None:
    config = source("ITW_CLASH_Store.sqf")
    server = source("ITW_CLASH_StoreServer.sqf")

    for ceiling in (
        "ITW_CLASH_StoreMaxCartLines",
        "ITW_CLASH_StoreMaxLineQuantity",
        "ITW_CLASH_StoreMaxVehiclesPerOrder",
    ):
        assert ceiling in config, f"{ceiling} not defined"
        assert ceiling in server, f"{ceiling} not enforced"


# ------------------------------------------------------- entry points ----


def test_comm_menu_entry_is_a_described_class_added_to_the_unit() -> None:
    # 2026-10-17: called as [class, [text, code]] it logged "Type String,
    # expected Object" (fn_addCommMenuItem line 20) and added nothing.
    client = source("ITW_CLASH_StoreClient.sqf")
    assert '[_unit, "ITW_CLASH_StoreCommMenu"] call BIS_fnc_addCommMenuItem' in client
    assert '"ITW_CLASH_StoreCommMenu",\n            ["Base Store"' not in client
    description = source("description.ext")
    menu = section(description, "class CfgCommunicationMenu")
    store = section(menu, "class ITW_CLASH_StoreCommMenu", "};")
    assert 'expression = "[] call ITW_CLASH_Store_fnc_OpenDialog";' in store
    assert 'submenu = "";' in store
    assert "removeAfterExpressionCall = 0;" in store


def test_entry_points_follow_the_player_across_respawns() -> None:
    client = source("ITW_CLASH_StoreClient.sqf")
    install = section(client, "ITW_CLASH_Store_fnc_InstallEntryPoints = {", "\n};\n")
    assert 'if (_unit getVariable ["ITW_CLASH_StoreEntryInstalled", false]) exitWith { true };' in install
    assert "_unit addAction [" in install
    assert '[_unit, 1, ["ACE_SelfActions"], _action] call ace_interact_menu_fnc_addActionToObject;' in install
    assert "player addAction" not in client
    loop = section(client, 'scriptName "ITW_CLASH_StoreEntryPoints";')
    assert "{ player != _installedFor }" in loop
    assert "[player] call ITW_CLASH_Store_fnc_InstallEntryPoints;" in loop
    assert "_installedFor = player;" in loop
    # The open path still refuses away from a base.
    assert 'hint "You must be at a base to use the store.";' in client
