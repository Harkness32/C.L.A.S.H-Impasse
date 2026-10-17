/*
    C.L.A.S.H. base store -- shared configuration, pricing and funds.

    Loaded on every machine. Holds no catalog and no interface: the catalog is
    server-owned (ITW_CLASH_StoreCatalog.sqf) and the interface is client-owned
    (ITW_CLASH_StoreClient.sqf).

    ===========================================================================
    PRICING -- this is the file you edit to set prices.
    ===========================================================================

    The store ships with the economy OFF, which makes it a faster, better
    looking replacement for the arsenal: everything costs nothing and the cart
    is just a staging list. Nothing else in the mission has a player currency
    to borrow from, so inventing one here would have been a guess.

    To turn it on:

      1.  Set ITW_CLASH_StoreEconomyEnabled to true.
      2.  Give each side a starting balance in ITW_CLASH_StoreStartingFunds.
      3.  Price things. Two levers, cheapest first:

          ITW_CLASH_StoreCategoryPrices   one price for a whole category
          ITW_CLASH_StorePrices           one price for one classname, wins

    Prices are deliberately a flat table rather than anything derived from
    config mass or ballistics. A table is auditable and it is the thing you
    asked to own.
*/

#include "defines.hpp"

ITW_CLASH_STORE_VERSION = "1.0.0";

/* ------------------------------------------------------------- economy -- */

/*  Master switch. False: every price reads 0, the cart never blocks on funds,
    and the interface hides all money. */
if (isNil "ITW_CLASH_StoreEconomyEnabled") then {
    ITW_CLASH_StoreEconomyEnabled = false;
};

/*  Opening balance per side key, used the first time a side's wallet is
    touched. Keys come from ITW_CLASH_Store_fnc_SideKey. */
if (isNil "ITW_CLASH_StoreStartingFunds") then {
    ITW_CLASH_StoreStartingFunds = createHashMapFromArray [
        ["WEST", 0],
        ["EAST", 0],
        ["GUER", 0],
        ["CIV", 0]
    ];
};

/*  Per-category fallback price. Applies to anything without its own entry. */
if (isNil "ITW_CLASH_StoreCategoryPrices") then {
    ITW_CLASH_StoreCategoryPrices = createHashMapFromArray [
        ["primary", 0],
        ["handgun", 0],
        ["secondary", 0],
        ["uniforms", 0],
        ["vests", 0],
        ["headgear", 0],
        ["facewear", 0],
        ["backpacks", 0],
        ["attachments", 0],
        ["ammo", 0],
        ["mines", 0],
        ["misc", 0],
        ["cars", 0],
        ["armor", 0],
        ["helis", 0],
        ["planes", 0],
        ["naval", 0],
        ["static", 0],
        ["other", 0]
    ];
};

/*  Per-classname price. Keys MUST be lowercase; lookups are lowercased.
    Example:
        ITW_CLASH_StorePrices set ["b_mbt_01_cannon_f", 4500];
        ITW_CLASH_StorePrices set ["arifle_mx_f", 120];          */
if (isNil "ITW_CLASH_StorePrices") then {
    ITW_CLASH_StorePrices = createHashMap;
};

/*  Classes that are always free even with the economy on -- medical and
    similar consumables nobody should have to budget for. Lowercase. */
if (isNil "ITW_CLASH_StoreFreeClasses") then {
    ITW_CLASH_StoreFreeClasses = [
        "firstaidkit",
        "ace_fielddressing",
        "ace_elasticbandage",
        "ace_packingbandage",
        "ace_quikclot",
        "ace_tourniquet",
        "ace_morphine",
        "ace_splint",
        "ace_earplugs"
    ];
};

/* ---------------------------------------------------------- categories -- */

/*  [id, label, icon] in the order the icon rail shows them. The icon is a game
    filesystem path; the page asks the engine for it through RequestTexture. */
ITW_CLASH_StoreCategories = [
    ["primary",     "Primary",      "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\PrimaryWeapon_ca.paa"],
    ["handgun",     "Handgun",      "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Handgun_ca.paa"],
    ["secondary",   "Launchers",    "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\SecondaryWeapon_ca.paa"],
    ["uniforms",    "Uniforms",     "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Uniform_ca.paa"],
    ["vests",       "Vests",        "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Vest_ca.paa"],
    ["headgear",    "Headgear",     "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Headgear_ca.paa"],
    ["facewear",    "Facewear",     "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Goggles_ca.paa"],
    ["backpacks",   "Backpacks",    "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\Backpack_ca.paa"],
    ["ammo",        "Ammo",         "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\CargoMagAll_ca.paa"],
    ["mines",       "Mines",        "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\CargoPut_ca.paa"],
    ["misc",        "Items",        "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\CargoMisc_ca.paa"],
    ["cars",        "Cars",         "a3\ui_f\data\map\vehicleicons\iconCar_ca.paa"],
    ["armor",       "Armor",        "a3\ui_f\data\map\vehicleicons\iconTank_ca.paa"],
    ["helis",       "Helicopters",  "a3\ui_f\data\map\vehicleicons\iconHelicopter_ca.paa"],
    ["planes",      "Planes",       "a3\ui_f\data\map\vehicleicons\iconPlane_ca.paa"],
    ["naval",       "Naval",        "a3\ui_f\data\map\vehicleicons\iconShip_ca.paa"],
    ["static",      "Statics",      "a3\ui_f\data\map\vehicleicons\iconStaticMG_ca.paa"],
    ["other",       "Other",        "a3\ui_f\data\map\vehicleicons\iconTruck_ca.paa"]
];

/*  Attachments are purchasable but have no rail entry of their own: they are
    offered alongside the weapon that accepts them. */
ITW_CLASH_StoreCatalogCategories = ITW_CLASH_StoreCategories + [
    ["attachments", "Attachments", "a3\ui_f\data\GUI\Rsc\RscDisplayArsenal\ItemOptic_ca.paa"]
];

ITW_CLASH_StoreGearCategories = [
    "primary", "handgun", "secondary", "uniforms", "vests", "headgear",
    "facewear", "backpacks", "attachments", "ammo", "mines", "misc"
];

ITW_CLASH_StoreVehicleCategories = [
    "cars", "armor", "helis", "planes", "naval", "static", "other"
];

ITW_CLASH_StoreContainers = ["auto", "uniform", "vest", "backpack"];

/*  How close a player must be to a base to use its store. */
if (isNil "ITW_CLASH_StoreAccessRange") then {
    ITW_CLASH_StoreAccessRange = 80;
};

/*  Hard ceilings so one order cannot be used to flood the server. */
ITW_CLASH_StoreMaxCartLines = 120;
ITW_CLASH_StoreMaxLineQuantity = 50;
ITW_CLASH_StoreMaxVehiclesPerOrder = 4;

/* -------------------------------------------------------------- pricing -- */

/*  Cost of one unit of a catalog entry. Returns 0 whenever the economy is off,
    so callers never need to branch on it. */
ITW_CLASH_Store_fnc_PriceOf = {
    params ["_className", "_category", ["_entryKind", "gear"]];

    if (!ITW_CLASH_StoreEconomyEnabled) exitWith { 0 };
    if !(_className isEqualType "") exitWith { 0 };

    private _key = toLowerANSI _className;

    if (_key in ITW_CLASH_StoreFreeClasses) exitWith { 0 };

    if (_key in ITW_CLASH_StorePrices) exitWith {
        private _price = ITW_CLASH_StorePrices get _key;
        if (_price isEqualType 0 && { _price >= 0 }) then { round _price } else { 0 }
    };

    private _fallback = ITW_CLASH_StoreCategoryPrices getOrDefault [_category, 0];
    if (_fallback isEqualType 0 && { _fallback >= 0 }) then { round _fallback } else { 0 }
};

/* ---------------------------------------------------------------- funds -- */

/*  Side wallets. Server-owned: clients only ever read the balance that arrives
    in a payload, and never compute a charge. */
if (isNil "ITW_CLASH_StoreWallets") then {
    ITW_CLASH_StoreWallets = createHashMap;
};

ITW_CLASH_Store_fnc_WalletBalance = {
    params ["_sideKey"];

    if (!ITW_CLASH_StoreEconomyEnabled) exitWith { 0 };

    if !(_sideKey in ITW_CLASH_StoreWallets) then {
        ITW_CLASH_StoreWallets set [
            _sideKey,
            ITW_CLASH_StoreStartingFunds getOrDefault [_sideKey, 0]
        ];
    };

    ITW_CLASH_StoreWallets get _sideKey
};

/*  Take an amount if it is there. Returns true when the balance was reduced.
    Server only: a client call is refused rather than silently succeeding. */
ITW_CLASH_Store_fnc_WalletCharge = {
    params ["_sideKey", "_amount"];

    if (!isServer) exitWith {
        diag_log "CLASH STORE | WALLET | REJECTED | charge-off-server";
        false
    };
    if (!ITW_CLASH_StoreEconomyEnabled) exitWith { true };
    if !(_amount isEqualType 0 && { _amount >= 0 }) exitWith { false };

    private _balance = [_sideKey] call ITW_CLASH_Store_fnc_WalletBalance;
    if (_balance < _amount) exitWith { false };

    ITW_CLASH_StoreWallets set [_sideKey, _balance - _amount];
    diag_log format [
        "CLASH STORE | WALLET | charged | side=%1 | amount=%2 | balance=%3",
        _sideKey,
        _amount,
        _balance - _amount
    ];
    true
};

ITW_CLASH_Store_fnc_WalletCredit = {
    params ["_sideKey", "_amount"];

    if (!isServer) exitWith {
        diag_log "CLASH STORE | WALLET | REJECTED | credit-off-server";
        false
    };
    if (!ITW_CLASH_StoreEconomyEnabled) exitWith { true };
    if !(_amount isEqualType 0 && { _amount >= 0 }) exitWith { false };

    private _balance = [_sideKey] call ITW_CLASH_Store_fnc_WalletBalance;
    ITW_CLASH_StoreWallets set [_sideKey, _balance + _amount];
    true
};

/* ------------------------------------------------------------- helpers -- */

/*  Wallet / catalog key for a side. Impasse puts every player on
    ITW_PlayerSide, which is usually west but is resistance on some of the
    supported maps, so all four sides are named rather than assumed. */
ITW_CLASH_Store_fnc_SideKey = {
    params ["_side"];

    switch (_side) do {
        case east: { "EAST" };
        case resistance: { "GUER" };
        case civilian: { "CIV" };
        default { "WEST" };
    }
};

ITW_CLASH_Store_fnc_CategoryLabel = {
    params ["_category"];

    private _label = _category;
    {
        if ((_x select 0) isEqualTo _category) exitWith { _label = _x select 1; };
    } forEach ITW_CLASH_StoreCatalogCategories;
    _label
};

ITW_CLASH_Store_fnc_IsVehicleCategory = {
    params ["_category"];
    _category in ITW_CLASH_StoreVehicleCategories
};

diag_log format ["CLASH STORE | loaded | version=%1", ITW_CLASH_STORE_VERSION];
