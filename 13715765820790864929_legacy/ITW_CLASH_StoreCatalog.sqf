/*
    C.L.A.S.H. base store -- catalog. Server only.

    The store does NOT invent its own idea of what exists. It reads the two
    pools the mission already maintains, so faction, DLC and map restrictions
    that CustomArsenal and VehicleArrays already apply are inherited for free:

      gear      the BIS virtual cargo on missionNamespace, which
                CustomArsenal_Arsenal fills during ITW_Start
      vehicles  the va_p*Classes arrays from VehicleArrays.sqf, the same pool
                the base garage draws on

    Built once per side and cached. Call ITW_CLASH_Store_fnc_InvalidateCatalog
    if the mission ever changes those pools mid-session.
*/

#include "defines.hpp"

if (isNil "ITW_CLASH_StoreCatalogCache") then {
    ITW_CLASH_StoreCatalogCache = createHashMap;
};

ITW_CLASH_Store_fnc_InvalidateCatalog = {
    ITW_CLASH_StoreCatalogCache = createHashMap;
    diag_log "CLASH STORE | CATALOG | cache-invalidated";
    true
};

/* ------------------------------------------------------ categorisation -- */

ITW_CLASH_Store_fnc_CategoryForVehicle = {
    params ["_className"];

    private _cfg = configFile >> "CfgVehicles" >> _className;
    if !(isClass _cfg) exitWith { "" };
    if ((getNumber (_cfg >> "scope")) < 1) exitWith { "" };
    if ((getNumber (_cfg >> "isBackpack")) isEqualTo 1) exitWith { "backpacks" };
    if (_className isKindOf "CAManBase") exitWith { "" };
    if (_className isKindOf "StaticWeapon") exitWith { "static" };
    if (_className isKindOf "Tank") exitWith { "armor" };
    if (_className isKindOf "Car") exitWith { "cars" };
    if (_className isKindOf "Helicopter") exitWith { "helis" };
    if (_className isKindOf "Plane") exitWith { "planes" };
    if (_className isKindOf "Ship") exitWith { "naval" };
    if (_className isKindOf "AllVehicles") exitWith { "other" };

    ""
};

ITW_CLASH_Store_fnc_CategoryForWeapon = {
    params ["_className"];

    private _cfg = configFile >> "CfgWeapons" >> _className;
    if !(isClass _cfg) exitWith { "" };

    /*  CfgWeapons >> type is a bitmask: 1 primary, 2 handgun, 4 launcher. */
    private _weaponType = getNumber (_cfg >> "type");
    if (((floor (_weaponType / 1)) mod 2) > 0) exitWith { "primary" };
    if (((floor (_weaponType / 2)) mod 2) > 0) exitWith { "handgun" };
    if (((floor (_weaponType / 4)) mod 2) > 0) exitWith { "secondary" };

    private _itemType = _className call BIS_fnc_itemType;
    _itemType params ["_group", "_kind"];

    if (_kind isEqualTo "Uniform") exitWith { "uniforms" };
    if (_kind isEqualTo "Vest") exitWith { "vests" };
    if (_kind isEqualTo "Headgear") exitWith { "headgear" };
    if (_kind in ["AccessoryMuzzle", "AccessoryPointer", "AccessorySights", "AccessoryBipod"]) exitWith { "attachments" };
    if (_kind in ["Binocular", "LaserDesignator"]) exitWith { "misc" };
    if (_group in ["Item", "Equipment", "Mine", "Magazine"]) exitWith { "misc" };

    ""
};

ITW_CLASH_Store_fnc_CategoryForMagazine = {
    params ["_className"];

    private _cfg = configFile >> "CfgMagazines" >> _className;
    if !(isClass _cfg) exitWith { "" };

    /*  A magazine that places an object -- mine, satchel, claymore -- belongs
        with the mines rather than buried among rifle ammunition. */
    private _mine = false;
    private _ammo = getText (_cfg >> "ammo");

    if (_ammo isNotEqualTo "") then {
        private _ammoCfg = configFile >> "CfgAmmo" >> _ammo;
        if (isClass _ammoCfg) then {
            _mine =
                (getNumber (_ammoCfg >> "isMine") isEqualTo 1) ||
                { _ammo isKindOf ["MineBase", configFile >> "CfgAmmo"] } ||
                { _ammo isKindOf ["TimeBombCore", configFile >> "CfgAmmo"] } ||
                { _ammo isKindOf ["PipeBombCore", configFile >> "CfgAmmo"] };
        };
    };

    if (_mine) then { "mines" } else { "ammo" }
};

/*  Resolve any gear classname to a store category without knowing in advance
    which config root it lives in. Used to price a saved loadout, whose entries
    are bare classnames. Returns "" for something unrecognised. */
ITW_CLASH_Store_fnc_CategoryForClass = {
    params ["_className"];

    if !(_className isEqualType "") exitWith { "" };
    if (_className isEqualTo "") exitWith { "" };

    if (isClass (configFile >> "CfgGlasses" >> _className)) exitWith { "facewear" };

    if (isClass (configFile >> "CfgVehicles" >> _className)) exitWith {
        if ((getNumber (configFile >> "CfgVehicles" >> _className >> "isBackpack")) isEqualTo 1) then {
            "backpacks"
        } else {
            [_className] call ITW_CLASH_Store_fnc_CategoryForVehicle
        }
    };

    if (isClass (configFile >> "CfgWeapons" >> _className)) exitWith {
        [_className] call ITW_CLASH_Store_fnc_CategoryForWeapon
    };

    if (isClass (configFile >> "CfgMagazines" >> _className)) exitWith {
        [_className] call ITW_CLASH_Store_fnc_CategoryForMagazine
    };

    ""
};

/* --------------------------------------------------------- attachments -- */

/*  Attachments a weapon ships with in its config, offered as a checklist when
    the weapon is added to the cart. */
ITW_CLASH_Store_fnc_WeaponAttachments = {
    params ["_className"];

    private _weaponCfg = configFile >> "CfgWeapons" >> _className;
    if !(isClass _weaponCfg) exitWith { [] };

    private _linkedCfg = _weaponCfg >> "LinkedItems";
    if !(isClass _linkedCfg) exitWith { [] };

    private _slotLabels = createHashMapFromArray [
        ["MuzzleSlot", "Muzzle"],
        ["CowsSlot", "Optic"],
        ["PointerSlot", "Pointer"],
        ["UnderBarrelSlot", "Underbarrel"]
    ];

    private _attachments = [];

    {
        private _attachmentClass = getText (_x >> "item");
        if (_attachmentClass isEqualTo "") then { continue };
        if !(isClass (configFile >> "CfgWeapons" >> _attachmentClass)) then { continue };

        private _attachmentCfg = configFile >> "CfgWeapons" >> _attachmentClass;
        private _slot = getText (_x >> "slot");
        private _name = getText (_attachmentCfg >> "displayName");
        if (_name isEqualTo "") then { _name = _attachmentClass };

        _attachments pushBack createHashMapFromArray [
            ["className", _attachmentClass],
            ["name", _name],
            ["slot", _slot],
            ["slotName", _slotLabels getOrDefault [_slot, "Attachment"]],
            ["image", getText (_attachmentCfg >> "picture")],
            ["priceValue", [_attachmentClass, "attachments", "gear"] call ITW_CLASH_Store_fnc_PriceOf]
        ];
    } forEach ("true" configClasses _linkedCfg);

    _attachments
};

/* --------------------------------------------------------------- entries -- */

ITW_CLASH_Store_fnc_BuildCatalogItem = {
    params ["_className", "_entryKind", "_category"];

    private _cfg = switch (true) do {
        case (_entryKind isEqualTo "vehicle"): { configFile >> "CfgVehicles" >> _className };
        case (_category isEqualTo "backpacks"): { configFile >> "CfgVehicles" >> _className };
        case (_category isEqualTo "facewear"): { configFile >> "CfgGlasses" >> _className };
        case (_category in ["ammo", "mines"]): { configFile >> "CfgMagazines" >> _className };
        case (
            _category isEqualTo "misc" &&
            { isClass (configFile >> "CfgMagazines" >> _className) } &&
            { !(isClass (configFile >> "CfgWeapons" >> _className)) }
        ): { configFile >> "CfgMagazines" >> _className };
        default { configFile >> "CfgWeapons" >> _className };
    };

    private _name = getText (_cfg >> "displayName");
    if (_name isEqualTo "") then { _name = _className };

    private _image = getText (_cfg >> "picture");
    if (_image isEqualTo "") then { _image = getText (_cfg >> "editorPreview") };

    private _attachments = [];
    if ((_entryKind isEqualTo "gear") && { _category in ["primary", "handgun", "secondary"] }) then {
        _attachments = [_className] call ITW_CLASH_Store_fnc_WeaponAttachments;
    };

    createHashMapFromArray [
        ["className", _className],
        ["name", _name],
        ["category", _category],
        ["entryKind", _entryKind],
        ["includedAttachments", _attachments],
        ["priceValue", [_className, _category, _entryKind] call ITW_CLASH_Store_fnc_PriceOf],
        ["image", _image],
        ["locked", false],
        ["lockReason", ""]
    ]
};

ITW_CLASH_Store_fnc_AppendCatalogItem = {
    params ["_itemsByCategory", "_seen", "_className", "_entryKind", "_category"];

    if !(_className isEqualType "") exitWith {};
    if (_className isEqualTo "") exitWith {};
    if (_category isEqualTo "") exitWith {};
    if !(_category in _itemsByCategory) exitWith {};

    private _key = format ["%1:%2", _entryKind, toLowerANSI _className];
    if (_key in _seen) exitWith {};

    private _valid = switch (_entryKind) do {
        case "vehicle": { isClass (configFile >> "CfgVehicles" >> _className) };
        default {
            switch (_category) do {
                case "ammo";
                case "mines": { isClass (configFile >> "CfgMagazines" >> _className) };
                case "backpacks": { isClass (configFile >> "CfgVehicles" >> _className) };
                case "facewear": { isClass (configFile >> "CfgGlasses" >> _className) };
                case "misc": {
                    (isClass (configFile >> "CfgWeapons" >> _className)) ||
                    { isClass (configFile >> "CfgMagazines" >> _className) }
                };
                default { isClass (configFile >> "CfgWeapons" >> _className) };
            }
        };
    };

    if (!_valid) exitWith {};

    (_itemsByCategory get _category) pushBack (
        [_className, _entryKind, _category] call ITW_CLASH_Store_fnc_BuildCatalogItem
    );
    _seen set [_key, true];
};

/* --------------------------------------------------------------- catalog -- */

ITW_CLASH_Store_fnc_BuildCatalog = {
    params ["_sideKey"];

    if (!isServer) exitWith {
        diag_log "CLASH STORE | CATALOG | REJECTED | build-off-server";
        createHashMap
    };

    if (_sideKey in ITW_CLASH_StoreCatalogCache) exitWith {
        ITW_CLASH_StoreCatalogCache get _sideKey
    };

    private _itemsByCategory = createHashMap;
    {
        _itemsByCategory set [_x select 0, []];
    } forEach ITW_CLASH_StoreCatalogCategories;

    private _seen = createHashMap;

    /* ---- gear, from the virtual arsenal pool the mission already built --- */

    private _weapons = [missionNamespace, true] call BIS_fnc_getVirtualWeaponCargo;
    private _magazines = [missionNamespace, true] call BIS_fnc_getVirtualMagazineCargo;
    private _items = [missionNamespace, true] call BIS_fnc_getVirtualItemCargo;
    private _backpacks = [missionNamespace, true] call BIS_fnc_getVirtualBackpackCargo;

    {
        private _category = [_x] call ITW_CLASH_Store_fnc_CategoryForWeapon;
        [_itemsByCategory, _seen, _x, "gear", _category] call ITW_CLASH_Store_fnc_AppendCatalogItem;
    } forEach _weapons;

    {
        private _category = [_x] call ITW_CLASH_Store_fnc_CategoryForMagazine;
        [_itemsByCategory, _seen, _x, "gear", _category] call ITW_CLASH_Store_fnc_AppendCatalogItem;
    } forEach _magazines;

    {
        private _category = "";
        if (isClass (configFile >> "CfgGlasses" >> _x)) then {
            _category = "facewear";
        } else {
            _category = [_x] call ITW_CLASH_Store_fnc_CategoryForWeapon;
            if (_category isEqualTo "" && { isClass (configFile >> "CfgMagazines" >> _x) }) then {
                _category = "misc";
            };
        };
        [_itemsByCategory, _seen, _x, "gear", _category] call ITW_CLASH_Store_fnc_AppendCatalogItem;
    } forEach _items;

    {
        [_itemsByCategory, _seen, _x, "gear", "backpacks"] call ITW_CLASH_Store_fnc_AppendCatalogItem;
    } forEach _backpacks;

    /* ---- vehicles, from the same pool the base garage uses --------------

        Impasse is PvE: every player is on ITW_PlayerSide and va_pAllVehicles
        is the players' pool, assembled in VehicleArrays.sqf specifically for
        the garage. There is no second player faction to branch on, so the
        enemy arrays (va_e*) are deliberately never read here. */

    private _vehiclePool = [];
    if (!isNil "va_pAllVehicles" && { va_pAllVehicles isEqualType [] }) then {
        _vehiclePool = va_pAllVehicles;
    };

    {
        if (_x isEqualType "") then {
            private _category = [_x] call ITW_CLASH_Store_fnc_CategoryForVehicle;
            if (_category isNotEqualTo "backpacks") then {
                [_itemsByCategory, _seen, _x, "vehicle", _category] call ITW_CLASH_Store_fnc_AppendCatalogItem;
            };
        };
    } forEach _vehiclePool;

    /* ---- stable ordering ------------------------------------------------ */

    {
        private _category = _x select 0;
        _itemsByCategory set [
            _category,
            [_itemsByCategory get _category, [], { _x get "name" }, "ASCEND"] call BIS_fnc_sortBy
        ];
    } forEach ITW_CLASH_StoreCatalogCategories;

    private _catalog = createHashMapFromArray [
        ["sideKey", _sideKey],
        ["itemsByCategory", _itemsByCategory],
        ["createdAt", diag_tickTime]
    ];

    ITW_CLASH_StoreCatalogCache set [_sideKey, _catalog];

    diag_log format [
        "CLASH STORE | CATALOG | built | side=%1 | entries=%2 | vehiclePool=%3",
        _sideKey,
        count _seen,
        count _vehiclePool
    ];

    _catalog
};

/*  Look one entry up without handing the whole catalog to the caller. Used by
    checkout to confirm a client is asking for something that exists. */
ITW_CLASH_Store_fnc_FindCatalogItem = {
    params ["_sideKey", "_className", "_entryKind", "_category"];

    private _catalog = [_sideKey] call ITW_CLASH_Store_fnc_BuildCatalog;
    private _itemsByCategory = _catalog getOrDefault ["itemsByCategory", createHashMap];
    if !(_category in _itemsByCategory) exitWith { createHashMap };

    private _wanted = toLowerANSI _className;
    private _found = createHashMap;

    {
        if (
            (toLowerANSI (_x get "className")) isEqualTo _wanted &&
            { (_x get "entryKind") isEqualTo _entryKind }
        ) exitWith { _found = _x; };
    } forEach (_itemsByCategory get _category);

    _found
};
