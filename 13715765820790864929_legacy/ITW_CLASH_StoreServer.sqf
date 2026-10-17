/*
    C.L.A.S.H. base store -- server authority.

    The client sends intent and nothing else. Every catalog, price, balance and
    delivery decision is made here, and every inbound request is checked
    against remoteExecutedOwner so one client cannot shop as another.

    Orders arrive in pieces. The page->SQF channel truncates at 10240
    characters, so a cart is sent as numbered chunks followed by a commit. An
    order whose chunks do not all arrive is refused rather than part-filled.
*/

#include "defines.hpp"

/*  Orders mid-flight, keyed by owner id. One slot per client: a new sequence
    replaces whatever that client had pending. */
if (isNil "ITW_CLASH_StorePendingOrders") then {
    ITW_CLASH_StorePendingOrders = createHashMap;
};

ITW_CLASH_StoreOrderTimeout = 60;

/* -------------------------------------------------------------- responses -- */

/*  Encode here and send JSON text, so what crosses the network is a string
    rather than a HashMap whose wire support varies by Arma build. The client
    hands the text straight to the page without re-parsing it. */
ITW_CLASH_Store_fnc_SendResponse = {
    params ["_owner", "_event", "_payload"];

    if (!isServer) exitWith {};

    private _json = toJSON _payload;

    if (_owner <= 0) exitWith {
        /*  Hosted listen server: the shopper is this machine. */
        if (hasInterface) then {
            [_event, _json] call ITW_CLASH_Store_fnc_ReceiveResponse;
        };
    };

    [_event, _json] remoteExecCall ["ITW_CLASH_Store_fnc_ReceiveResponse", _owner];
};

ITW_CLASH_Store_fnc_Deny = {
    params ["_owner", "_event", "_message"];

    [
        _owner,
        _event,
        createHashMapFromArray [
            ["success", false],
            ["message", _message]
        ]
    ] call ITW_CLASH_Store_fnc_SendResponse;
};

/* --------------------------------------------------------------- access -- */

/*  Confirm this player may use the store at this base right now. Returns a
    HashMap whose "success" key decides everything downstream. */
ITW_CLASH_Store_fnc_ValidateAccess = {
    params ["_player", "_baseIndex"];

    private _owner = if (isNull _player) then { 0 } else { owner _player };
    private _payload = createHashMapFromArray [
        ["success", false],
        ["message", ""],
        ["owner", _owner]
    ];

    if (!isServer) exitWith { _payload };

    if (isNull _player) exitWith {
        _payload set ["message", "Invalid store player."];
        _payload
    };

    /*  Ownership: a client may only act for itself. remoteExecutedOwner is 0
        for a server-local call and 2 for the server itself. */
    if (remoteExecutedOwner > 2 && { remoteExecutedOwner isNotEqualTo _owner }) exitWith {
        diag_log format [
            "CLASH STORE | ACCESS | REJECTED | owner-mismatch | caller=%1 | player=%2",
            remoteExecutedOwner,
            _owner
        ];
        _payload set ["message", "Store request ownership is invalid."];
        _payload
    };

    if (!alive _player) exitWith {
        _payload set ["message", "The store is unavailable while you are down."];
        _payload
    };

    if !(_baseIndex isEqualType 0) exitWith {
        _payload set ["message", "Invalid store base."];
        _payload
    };

    private _index = floor _baseIndex;
    if (isNil "ITW_Bases" || { _index < 0 } || { _index >= count ITW_Bases }) exitWith {
        _payload set ["message", "That base no longer exists."];
        _payload
    };

    private _baseInfo = ITW_Bases select _index;
    if !(_baseInfo isEqualType []) exitWith {
        _payload set ["message", "That base no longer exists."];
        _payload
    };

    if !(_baseInfo select ITW_BASE_SPAWNED) exitWith {
        _payload set ["message", "That base has not been established yet."];
        _payload
    };

    private _basePos = _baseInfo select ITW_BASE_POS;
    if ((_player distance2D _basePos) > ITW_CLASH_StoreAccessRange) exitWith {
        _payload set ["message", "Move closer to the base store."];
        _payload
    };

    private _side = side group _player;
    if (!isNil "ITW_PlayerSide" && { _side isNotEqualTo ITW_PlayerSide }) exitWith {
        _payload set ["message", "The store serves the player faction only."];
        _payload
    };

    private _sideKey = [_side] call ITW_CLASH_Store_fnc_SideKey;

    _payload set ["success", true];
    _payload set ["side", _side];
    _payload set ["sideKey", _sideKey];
    _payload set ["sideName", str _side];
    _payload set ["baseIndex", _index];
    _payload set ["baseInfo", _baseInfo];
    _payload set ["basePos", _basePos];
    _payload
};

/* -------------------------------------------------------------- payloads -- */

ITW_CLASH_Store_fnc_BuildHydratePayload = {
    params ["_access"];

    private _sideKey = _access get "sideKey";
    private _catalog = [_sideKey] call ITW_CLASH_Store_fnc_BuildCatalog;
    private _itemsByCategory = _catalog getOrDefault ["itemsByCategory", createHashMap];

    private _categories = [];
    private _firstCategory = "";

    {
        _x params ["_id", "_label", "_icon"];
        private _count = count (_itemsByCategory getOrDefault [_id, []]);

        _categories pushBack createHashMapFromArray [
            ["id", _id],
            ["label", _label],
            ["icon", _icon],
            ["count", _count]
        ];

        if ((_firstCategory isEqualTo "") && { _count > 0 }) then {
            _firstCategory = _id;
        };
    } forEach ITW_CLASH_StoreCategories;

    createHashMapFromArray [
        ["success", true],
        ["message", ""],
        ["sideKey", _sideKey],
        ["sideName", _access get "sideName"],
        ["baseIndex", _access get "baseIndex"],
        ["economyEnabled", ITW_CLASH_StoreEconomyEnabled],
        ["balance", [_sideKey] call ITW_CLASH_Store_fnc_WalletBalance],
        ["categories", _categories],
        ["firstCategory", _firstCategory]
    ]
};

ITW_CLASH_Store_fnc_BuildCategoryPayload = {
    params ["_access", "_category"];

    private _known = false;
    {
        if ((_x select 0) isEqualTo _category) exitWith { _known = true; };
    } forEach ITW_CLASH_StoreCategories;

    if (!_known) exitWith {
        createHashMapFromArray [
            ["success", false],
            ["message", format ["Unknown store category: %1", _category]],
            ["category", _category],
            ["items", []]
        ]
    };

    private _sideKey = _access get "sideKey";
    private _catalog = [_sideKey] call ITW_CLASH_Store_fnc_BuildCatalog;
    private _itemsByCategory = _catalog getOrDefault ["itemsByCategory", createHashMap];

    createHashMapFromArray [
        ["success", true],
        ["message", ""],
        ["category", _category],
        ["label", [_category] call ITW_CLASH_Store_fnc_CategoryLabel],
        ["items", _itemsByCategory getOrDefault [_category, []]],
        ["economyEnabled", ITW_CLASH_StoreEconomyEnabled],
        ["balance", [_sideKey] call ITW_CLASH_Store_fnc_WalletBalance]
    ]
};

/* -------------------------------------------------------------- requests -- */

ITW_CLASH_Store_fnc_RequestHydrate = {
    params ["_player", "_baseIndex"];

    if (!isServer) exitWith {};

    private _access = [_player, _baseIndex] call ITW_CLASH_Store_fnc_ValidateAccess;
    private _owner = _access get "owner";

    if !(_access get "success") exitWith {
        [_owner, "hydrate", _access get "message"] call ITW_CLASH_Store_fnc_Deny;
    };

    [
        _owner,
        "hydrate",
        [_access] call ITW_CLASH_Store_fnc_BuildHydratePayload
    ] call ITW_CLASH_Store_fnc_SendResponse;
};

ITW_CLASH_Store_fnc_RequestCategory = {
    params ["_player", "_baseIndex", "_category"];

    if (!isServer) exitWith {};
    if !(_category isEqualType "") exitWith {};

    private _access = [_player, _baseIndex] call ITW_CLASH_Store_fnc_ValidateAccess;
    private _owner = _access get "owner";

    if !(_access get "success") exitWith {
        [_owner, "category", _access get "message"] call ITW_CLASH_Store_fnc_Deny;
    };

    [
        _owner,
        "category",
        [_access, _category] call ITW_CLASH_Store_fnc_BuildCategoryPayload
    ] call ITW_CLASH_Store_fnc_SendResponse;
};

/*  One chunk of a cart. Held until the matching commit arrives. */
ITW_CLASH_Store_fnc_RequestCartChunk = {
    params ["_player", "_sequence", "_index", "_total", "_items"];

    if (!isServer) exitWith {};
    if (isNull _player) exitWith {};

    private _owner = owner _player;
    if (remoteExecutedOwner > 2 && { remoteExecutedOwner isNotEqualTo _owner }) exitWith {
        diag_log format [
            "CLASH STORE | ORDER | REJECTED | chunk-owner-mismatch | caller=%1 | player=%2",
            remoteExecutedOwner,
            _owner
        ];
    };

    if !(
        _sequence isEqualType 0 && { _index isEqualType 0 } &&
        { _total isEqualType 0 } && { _items isEqualType [] }
    ) exitWith {};

    if (_total < 1 || { _total > 40 } || { _index < 0 } || { _index >= _total }) exitWith {};

    private _key = str _owner;
    private _pending = ITW_CLASH_StorePendingOrders getOrDefault [_key, createHashMap];

    /*  A new sequence discards the previous half-sent order. */
    if ((_pending getOrDefault ["sequence", -1]) isNotEqualTo _sequence) then {
        _pending = createHashMapFromArray [
            ["sequence", _sequence],
            ["total", _total],
            ["chunks", createHashMap],
            ["startedAt", diag_tickTime]
        ];
    };

    (_pending get "chunks") set [str _index, _items];
    _pending set ["total", _total];
    ITW_CLASH_StorePendingOrders set [_key, _pending];
};

ITW_CLASH_Store_fnc_RequestCheckout = {
    params ["_player", "_baseIndex", "_sequence", "_total"];

    if (!isServer) exitWith {};

    private _access = [_player, _baseIndex] call ITW_CLASH_Store_fnc_ValidateAccess;
    private _owner = _access get "owner";

    if !(_access get "success") exitWith {
        [_owner, "checkout", _access get "message"] call ITW_CLASH_Store_fnc_Deny;
    };

    private _key = str _owner;
    private _pending = ITW_CLASH_StorePendingOrders getOrDefault [_key, createHashMap];
    ITW_CLASH_StorePendingOrders deleteAt _key;

    if ((_pending getOrDefault ["sequence", -1]) isNotEqualTo _sequence) exitWith {
        [_owner, "checkout", "That order expired. Try again."] call ITW_CLASH_Store_fnc_Deny;
    };

    if ((diag_tickTime - (_pending getOrDefault ["startedAt", 0])) > ITW_CLASH_StoreOrderTimeout) exitWith {
        [_owner, "checkout", "That order expired. Try again."] call ITW_CLASH_Store_fnc_Deny;
    };

    private _chunks = _pending getOrDefault ["chunks", createHashMap];
    private _expected = _pending getOrDefault ["total", 0];

    if (_total isEqualType 0 && { _total isNotEqualTo _expected }) exitWith {
        [_owner, "checkout", "That order did not arrive intact. Try again."] call ITW_CLASH_Store_fnc_Deny;
    };

    /*  Every chunk, or nothing. A missing piece means the channel truncated
        and buying the remainder would be buying something nobody chose. */
    private _lines = [];
    private _missing = false;
    for "_i" from 0 to (_expected - 1) do {
        private _chunk = _chunks getOrDefault [str _i, nil];
        if (isNil "_chunk") then {
            _missing = true;
        } else {
            _lines append _chunk;
        };
    };

    if (_missing) exitWith {
        diag_log format [
            "CLASH STORE | ORDER | REJECTED | incomplete | owner=%1 | expected=%2 | got=%3",
            _owner,
            _expected,
            count _chunks
        ];
        [_owner, "checkout", "That order did not arrive intact. Try again."] call ITW_CLASH_Store_fnc_Deny;
    };

    [_access, _lines] call ITW_CLASH_Store_fnc_Checkout;
};

/* -------------------------------------------------------------- checkout -- */

/*  Validate the whole order, charge once, then deliver. Nothing is delivered
    before the charge succeeds and nothing is charged for a line the catalog
    does not contain. */
ITW_CLASH_Store_fnc_Checkout = {
    params ["_access", "_lines"];

    if (!isServer) exitWith {};

    private _owner = _access get "owner";
    private _sideKey = _access get "sideKey";

    if ((count _lines) > ITW_CLASH_StoreMaxCartLines) exitWith {
        [_owner, "checkout", "That order has too many lines."] call ITW_CLASH_Store_fnc_Deny;
    };

    private _gearLines = [];
    private _vehicleLines = [];
    private _total = 0;
    private _rejected = "";
    private _vehicleCount = 0;

    {
        /*  Lines arrive as plain positional arrays from the client:
            [className, entryKind, category, container, quantity, attachments] */
        if !(_x isEqualType [] && { (count _x) >= 6 }) then { continue };

        _x params [
            "_className", "_entryKind", "_category",
            "_container", "_quantity", "_attachments"
        ];

        if !(_className isEqualType "" && { _className isNotEqualTo "" }) then { continue };
        if !(_entryKind isEqualType "") then { continue };
        if !(_category isEqualType "") then { continue };
        if !(_container isEqualType "") then { continue };
        if !(_quantity isEqualType 0) then { continue };

        _quantity = floor _quantity;
        if (_quantity < 1) then { continue };
        if (_quantity > ITW_CLASH_StoreMaxLineQuantity) then {
            _quantity = ITW_CLASH_StoreMaxLineQuantity;
        };

        if !(_container in ITW_CLASH_StoreContainers) then { _container = "auto" };
        if !(_attachments isEqualType []) then { _attachments = [] };

        /*  The catalog is the allowlist. A class the client made up, or one
            from a category it does not belong to, never reaches delivery. */
        private _item = [_sideKey, _className, _entryKind, _category] call ITW_CLASH_Store_fnc_FindCatalogItem;
        if ((keys _item) isEqualTo []) then {
            _rejected = format ["%1 is not sold here.", _className];
            continue;
        };

        if (_item getOrDefault ["locked", false]) then {
            _rejected = format ["%1 is unavailable here.", _item getOrDefault ["name", _className]];
            continue;
        };

        _total = _total + (_quantity * (_item getOrDefault ["priceValue", 0]));

        /*  Only attachments the weapon actually ships with are chargeable and
            installable, so the client cannot smuggle in arbitrary items. */
        private _allowed = (_item getOrDefault ["includedAttachments", []]) apply {
            toLowerANSI (_x get "className")
        };
        private _resolvedAttachments = [];
        {
            if (_x isEqualType "" && { (toLowerANSI _x) in _allowed }) then {
                _resolvedAttachments pushBackUnique _x;
                _total = _total + (_quantity * ([_x, "attachments", "gear"] call ITW_CLASH_Store_fnc_PriceOf));
            };
        } forEach _attachments;

        /*  Resolved lines stay plain positional arrays, matching
            ITW_CLASH_STORE_LINE_* so they cross the network to the shopper's
            machine without depending on HashMap wire support. */
        private _resolved = [
            _className,
            _item getOrDefault ["name", _className],
            _entryKind,
            _category,
            _container,
            _quantity,
            _resolvedAttachments
        ];

        if ([_category] call ITW_CLASH_Store_fnc_IsVehicleCategory) then {
            _vehicleCount = _vehicleCount + _quantity;
            _vehicleLines pushBack _resolved;
        } else {
            _gearLines pushBack _resolved;
        };
    } forEach _lines;

    if (_gearLines isEqualTo [] && { _vehicleLines isEqualTo [] }) exitWith {
        [
            _owner,
            "checkout",
            if (_rejected isEqualTo "") then { "Nothing in that order could be filled." } else { _rejected }
        ] call ITW_CLASH_Store_fnc_Deny;
    };

    if (_vehicleCount > ITW_CLASH_StoreMaxVehiclesPerOrder) exitWith {
        [
            _owner,
            "checkout",
            format ["At most %1 vehicles per order.", ITW_CLASH_StoreMaxVehiclesPerOrder]
        ] call ITW_CLASH_Store_fnc_Deny;
    };

    if !([_sideKey, _total] call ITW_CLASH_Store_fnc_WalletCharge) exitWith {
        [_owner, "checkout", "Insufficient funds."] call ITW_CLASH_Store_fnc_Deny;
    };

    /* ---- delivery ------------------------------------------------------- */

    private _spawned = 0;
    {
        if ([_access, _x] call ITW_CLASH_Store_fnc_SpawnVehicle) then {
            _spawned = _spawned + 1;
        };
    } forEach _vehicleLines;

    if !(_gearLines isEqualTo []) then {
        /*  Gear is applied where the unit lives, which is the shopper's own
            machine. The client re-checks the sender before it applies. */
        if (_owner <= 0) then {
            if (hasInterface) then {
                [_gearLines] call ITW_CLASH_Store_fnc_ApplyGear;
            };
        } else {
            [_gearLines] remoteExecCall ["ITW_CLASH_Store_fnc_ApplyGear", _owner];
        };
    };

    private _message = "Purchase complete.";
    if (_spawned > 0) then {
        _message = format ["Purchase complete. %1 vehicle(s) delivered to the garage.", _spawned];
    };
    if (_rejected isNotEqualTo "") then {
        _message = _message + " Some lines were skipped: " + _rejected;
    };

    diag_log format [
        "CLASH STORE | ORDER | filled | owner=%1 | side=%2 | gearLines=%3 | vehicles=%4 | cost=%5",
        _owner,
        _sideKey,
        count _gearLines,
        _spawned,
        _total
    ];

    [
        _owner,
        "checkout",
        createHashMapFromArray [
            ["success", true],
            ["message", _message],
            ["economyEnabled", ITW_CLASH_StoreEconomyEnabled],
            ["balance", [_sideKey] call ITW_CLASH_Store_fnc_WalletBalance]
        ]
    ] call ITW_CLASH_Store_fnc_SendResponse;
};

/* -------------------------------------------------------- saved loadouts -- */

/*  A saved loadout is priced and charged exactly like a cart, so turning the
    economy on does not open a free-gear route. The loadout itself stays on the
    client -- only its class list travels, and only the verdict comes back.

    Classes the catalog does not sell are charged nothing and reported, rather
    than failing the whole request: a loadout saved before a pool changed
    should still be wearable. */
ITW_CLASH_Store_fnc_RequestLoadoutApply = {
    params ["_player", "_baseIndex", "_id", "_classList"];

    if (!isServer) exitWith {};

    private _access = [_player, _baseIndex] call ITW_CLASH_Store_fnc_ValidateAccess;
    private _owner = _access get "owner";

    if !(_access get "success") exitWith {
        [_owner, "loadouts", _access get "message"] call ITW_CLASH_Store_fnc_Deny;
    };

    if !(_id isEqualType "" && { _classList isEqualType [] }) exitWith {
        [_owner, "loadouts", "That loadout could not be read."] call ITW_CLASH_Store_fnc_Deny;
    };

    if ((count _classList) > ITW_CLASH_StoreMaxCartLines) exitWith {
        [_owner, "loadouts", "That loadout has too many distinct items."] call ITW_CLASH_Store_fnc_Deny;
    };

    private _sideKey = _access get "sideKey";
    private _total = 0;
    private _unknown = 0;

    {
        if !(_x isEqualType [] && { (count _x) >= 2 }) then { continue };

        private _className = _x select 0;
        private _count = _x select 1;

        if !(_className isEqualType "" && { _count isEqualType 0 }) then { continue };

        _count = floor _count;
        if (_count < 1) then { continue };
        if (_count > ITW_CLASH_StoreMaxLineQuantity) then {
            _count = ITW_CLASH_StoreMaxLineQuantity;
        };

        private _category = [_className] call ITW_CLASH_Store_fnc_CategoryForClass;
        if (_category isEqualTo "") then {
            _unknown = _unknown + 1;
            continue;
        };

        private _item = [_sideKey, _className, "gear", _category] call ITW_CLASH_Store_fnc_FindCatalogItem;
        if ((keys _item) isEqualTo []) then {
            _unknown = _unknown + 1;
            continue;
        };

        _total = _total + (_count * (_item getOrDefault ["priceValue", 0]));
    } forEach _classList;

    if !([_sideKey, _total] call ITW_CLASH_Store_fnc_WalletCharge) exitWith {
        [_owner, "loadouts", "Insufficient funds for that loadout."] call ITW_CLASH_Store_fnc_Deny;
    };

    diag_log format [
        "CLASH STORE | LOADOUT | approved | owner=%1 | cost=%2 | unpriced=%3",
        _owner,
        _total,
        _unknown
    ];

    if (_owner <= 0) then {
        if (hasInterface) then {
            [_id] call ITW_CLASH_Store_fnc_LoadoutApprove;
        };
    } else {
        [_id] remoteExecCall ["ITW_CLASH_Store_fnc_LoadoutApprove", _owner];
    };

    /*  Refresh the client's balance after the charge. */
    [
        _owner,
        "hydrate",
        [_access] call ITW_CLASH_Store_fnc_BuildHydratePayload
    ] call ITW_CLASH_Store_fnc_SendResponse;
};

/* ------------------------------------------------------- vehicle delivery -- */

/*  Purchased vehicles appear at the base garage pad, which is where players
    already expect to collect them. This is the one seam to change if you would
    rather route purchases through ITW_Garage. */
ITW_CLASH_Store_fnc_SpawnVehicle = {
    params ["_access", "_line"];

    if (!isServer) exitWith { false };

    private _baseInfo = _access get "baseInfo";
    private _className = _line select ITW_CLASH_STORE_LINE_CLASS;
    private _quantity = _line select ITW_CLASH_STORE_LINE_QUANTITY;

    private _pad = _baseInfo select ITW_BASE_GARAGE_POS;
    if !(_pad isEqualType [] && { (count _pad) >= 2 }) then {
        _pad = _baseInfo select ITW_BASE_POS;
    };

    /*  A pad of [-1000,-1000,0] is the "no garage here" sentinel. */
    if ((_pad select 0) < -900) then {
        _pad = _baseInfo select ITW_BASE_POS;
    };

    private _created = 0;
    for "_i" from 1 to _quantity do {
        private _spot = _pad findEmptyPosition [6, 60, _className];
        if (_spot isEqualTo []) then { _spot = _pad getPos [8 + (_i * 6), random 360] };

        private _vehicle = createVehicle [_className, _spot, [], 0, "NONE"];
        if (isNull _vehicle) then { continue };

        _vehicle setDir ((_baseInfo select ITW_BASE_DIR) + 90);
        _vehicle setVectorUp surfaceNormal (getPosATL _vehicle);
        if (!isNil "ITW_PlayerSide") then {
            _vehicle setVariable ["ITW_CLASH_StorePurchased", true, true];
        };

        /*  Register with the mission's own vehicle bookkeeping so cleanup and
            persistence treat it like any other player vehicle. */
        if (!isNil "ITW_PlayerVehiclesList") then {
            ITW_PlayerVehiclesList pushBack [_vehicle];
        };

        _created = _created + 1;
    };

    if (_created > 0) then {
        diag_log format [
            "CLASH STORE | DELIVERY | vehicle | class=%1 | count=%2 | base=%3",
            _className,
            _created,
            _access get "baseIndex"
        ];
    };

    _created > 0
};
