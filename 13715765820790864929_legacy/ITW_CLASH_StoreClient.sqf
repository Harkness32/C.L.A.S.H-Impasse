/*
    C.L.A.S.H. base store -- client.

    Owns the dialog, the browser event routing, gear application on the local
    unit, saved loadouts, and the local 3D preview scene.

    The preview is not drawn by the page. The browser control is transparent and
    the page leaves a hole where #previewViewport sits; a real camera, mannequin
    and light are created locally behind it and framed to that hole. The page
    reports the hole's rectangle whenever it moves or the window resizes.

    Nothing here decides a price or a balance. The server does that.
*/

#include "defines.hpp"
#include "defines_gui.hpp"

if (!hasInterface) exitWith {};

ITW_CLASH_StoreActiveBaseIndex = -1;

/* ------------------------------------------------------------- base pick -- */

/*  Nearest established base of the player's own side within store range, or -1.
    ITW_Bases is public, so this needs no server round trip. */
ITW_CLASH_Store_fnc_NearestBaseIndex = {
    params [["_unit", player]];

    if (isNil "ITW_Bases") exitWith { -1 };

    private _best = -1;
    private _bestDistance = ITW_CLASH_StoreAccessRange + 1;

    {
        if (_x isEqualType [] && { (count _x) > ITW_BASE_SPAWNED } && { _x select ITW_BASE_SPAWNED }) then {
            private _distance = _unit distance2D (_x select ITW_BASE_POS);
            if (_distance < _bestDistance) then {
                _bestDistance = _distance;
                _best = _forEachIndex;
            };
        };
    } forEach ITW_Bases;

    _best
};

ITW_CLASH_Store_fnc_CanUseStore = {
    ([] call ITW_CLASH_Store_fnc_NearestBaseIndex) >= 0
};

/* ---------------------------------------------------------------- preview -- */

ITW_CLASH_Store_fnc_PreviewOpen = {
    params ["_display"];

    if (isNull _display) exitWith { false };

    /*  Far outside the playable area so nothing in the world is disturbed and
        nothing in the world is visible behind the backdrop. */
    private _position = [worldSize + 1000, worldSize + 1000, 1000];

    private _man = (typeOf player) createVehicleLocal _position;
    if (isNull _man) exitWith {
        diag_log "CLASH STORE | PREVIEW | FAILED | mannequin-not-created";
        false
    };

    _man setPosASL _position;
    _man enableSimulation false;
    _man allowDamage false;
    _man disableAI "ALL";
    _man setUnitLoadout (getUnitLoadout player);
    _man setFace (face player);
    _man setDir 0;
    _man switchMove "AmovPercMstpSnonWnonDnon";

    /*  The editor sphere gives a neutral floor and backdrop for free. */
    private _backdrop = createSimpleObject ["Sphere_3DEN", _position, true];

    private _camera = "camera" camCreate _position;
    _camera cameraEffect ["Internal", "Back"];
    showCinemaBorder false;
    _camera camSetFov 0.7;

    private _light = "#lightpoint" createVehicleLocal _position;
    _light setLightDayLight true;
    _light setLightAmbient [0.6, 0.65, 0.72];
    _light setLightColor [1, 0.95, 0.9];
    _light setLightBrightness 3;

    _display setVariable ["ITW_CLASH_StorePreview", createHashMapFromArray [
        ["camera", _camera],
        ["man", _man],
        ["model", objNull],
        ["light", _light],
        ["backdrop", _backdrop],
        ["position", _position],
        ["baseline", getUnitLoadout player],
        ["subject", _man],
        ["angle", 135],
        ["pitch", 8],
        ["zoom", 1],
        ["mode", "character"],
        ["selection", createHashMap],
        ["viewport", [0.42, 0.18, 0.32, 0.5]]
    ]];

    [_display] call ITW_CLASH_Store_fnc_PreviewUpdateCamera;
    true
};

ITW_CLASH_Store_fnc_PreviewClose = {
    params ["_display"];

    if (isNull _display) exitWith {};
    /*  An unload can follow a failed display creation, before the preview was
        ever built. */
    if (isNil { _display getVariable "ITW_CLASH_StorePreview" }) exitWith {};

    private _state = _display getVariable "ITW_CLASH_StorePreview";
    private _camera = _state get "camera";

    _camera cameraEffect ["Terminate", "Back"];
    camDestroy _camera;
    deleteVehicle (_state get "man");
    deleteVehicle (_state get "model");
    deleteVehicle (_state get "light");
    deleteVehicle (_state get "backdrop");

    _display setVariable ["ITW_CLASH_StorePreview", nil];
};

/*  Frame the subject inside the transparent gap in the page. */
ITW_CLASH_Store_fnc_PreviewUpdateCamera = {
    params ["_display"];

    if (isNull _display) exitWith {};
    if (isNil { _display getVariable "ITW_CLASH_StorePreview" }) exitWith {};

    private _state = _display getVariable "ITW_CLASH_StorePreview";
    private _subject = _state get "subject";
    if (isNull _subject) exitWith {};

    /*  Geometry bounds first: general bounds include firing and memory proxies
        far larger than the item itself, which would frame it tiny. */
    private _bounds = boundingBoxReal [_subject, "Geometry"];
    if ((_bounds select 0) isEqualTo (_bounds select 1)) then {
        _bounds = 0 boundingBoxReal _subject;
    };

    private _center = ((_bounds select 0) vectorAdd (_bounds select 1)) vectorMultiply 0.5;
    private _size = (_bounds select 1) vectorDiff (_bounds select 0);
    private _radius = ((vectorMagnitude _size) * 0.5) max 0.15;

    if (_subject isEqualTo (_state get "man")) then {
        _center = [0, 0, 0.95];
        _radius = 1.05;
    };

    private _target = _subject modelToWorldVisualWorld _center;

    (_state get "viewport") params ["_vx", "_vy", "_vw", "_vh"];
    private _resolution = getResolution;
    private _aspect = (_resolution select 0) / (_resolution select 1);

    private _distance = _radius / ((_vw min (_vh / _aspect)) * 0.62) * (_state get "zoom");
    private _angle = _state get "angle";
    private _pitch = _state get "pitch";

    private _forward = [sin _angle * cos _pitch, cos _angle * cos _pitch, -sin _pitch];
    private _right = [cos _angle, -sin _angle, 0];
    private _up = _right vectorCrossProduct _forward;

    /*  Slide the camera sideways and up so the subject lands in the page's gap
        rather than in the middle of the screen. */
    private _shift = (_right vectorMultiply ((0.5 - (_vx + _vw / 2)) * _distance * 1.4)) vectorAdd
        (_up vectorMultiply (((_vy + _vh / 2) - 0.5) * _distance * 1.4 / _aspect));

    private _camera = _state get "camera";
    _camera camSetPos (ASLToAGL ((_target vectorDiff (_forward vectorMultiply _distance)) vectorAdd _shift));
    _camera camSetTarget (ASLToAGL (_target vectorAdd _shift));
    _camera camCommit 0;

    (_state get "light") setPosASL ((_target vectorDiff (_forward vectorMultiply (_radius * 3))) vectorAdd [0, 0, _radius]);
};

/*  Put one item on the mannequin against the player's real loadout. */
ITW_CLASH_Store_fnc_PreviewEquip = {
    params ["_man", "_baseline", "_class", "_category"];

    _man setUnitLoadout _baseline;

    switch (_category) do {
        case "uniforms": { removeUniform _man; _man forceAddUniform _class };
        case "vests": { removeVest _man; _man addVest _class };
        case "backpacks": { removeBackpack _man; _man addBackpack _class };
        case "headgear": { removeHeadgear _man; _man addHeadgear _class };
        case "facewear": { removeGoggles _man; _man addGoggles _class };
        case "primary";
        case "handgun";
        case "secondary": {
            private _old = switch (_category) do {
                case "primary": { primaryWeapon _man };
                case "handgun": { handgunWeapon _man };
                default { secondaryWeapon _man };
            };
            _man removeWeapon _old;
            _man addWeapon _class;
            _man selectWeapon _class;
        };
        case "attachments": {
            if (_class in (compatibleItems (primaryWeapon _man))) then {
                _man addPrimaryWeaponItem _class;
            };
        };
        case "misc": {
            if (((_class call BIS_fnc_itemType) select 1) in ["NVGoggles", "GPS", "Map", "Compass", "Watch", "Radio", "Terminal"]) then {
                _man linkItem _class;
            };
        };
    };

    _man switchMove (switch (_category) do {
        case "handgun": { "AmovPercMstpSrasWpstDnon" };
        case "secondary": { "AmovPercMstpSrasWlnrDnon" };
        case "primary";
        case "attachments": { "AmovPercMstpSlowWrflDnon" };
        default { "AmovPercMstpSnonWnonDnon" };
    });
};

ITW_CLASH_Store_fnc_PreviewSelect = {
    params ["_display", "_selection"];

    if (isNull _display) exitWith { false };
    if (isNil { _display getVariable "ITW_CLASH_StorePreview" }) exitWith { false };

    private _state = _display getVariable "ITW_CLASH_StorePreview";
    private _class = _selection getOrDefault ["className", ""];
    private _category = _selection getOrDefault ["category", ""];
    private _kind = _selection getOrDefault ["entryKind", ""];

    if !(_class isEqualType "" && { _category isEqualType "" } && { _kind isEqualType "" }) exitWith { false };

    private _man = _state get "man";
    deleteVehicle (_state get "model");
    _state set ["model", objNull];
    _state set ["subject", _man];
    _state set ["selection", _selection];
    _man hideObject false;
    _man setUnitLoadout (_state get "baseline");

    private _status = "";

    if (_class isNotEqualTo "" && { _kind in ["gear", "vehicle"] }) then {
        private _root = switch (true) do {
            case (_kind isEqualTo "vehicle" || { _category isEqualTo "backpacks" }): { "CfgVehicles" };
            case (_category isEqualTo "facewear"): { "CfgGlasses" };
            case (
                _category in ["ammo", "mines"] ||
                { _category isEqualTo "misc" && { !(isClass (configFile >> "CfgWeapons" >> _class)) } }
            ): { "CfgMagazines" };
            default { "CfgWeapons" };
        };

        private _cfg = configFile >> _root >> _class;

        if (isClass _cfg) then {
            private _wearable = _kind isEqualTo "gear" &&
                { _category in ["uniforms", "vests", "backpacks", "headgear", "facewear", "primary", "handgun", "secondary", "attachments", "misc"] };

            if ((((_state get "mode") isEqualTo "character") || { _category isEqualTo "uniforms" }) && { _wearable }) then {
                [_man, _state get "baseline", _class, _category] call ITW_CLASH_Store_fnc_PreviewEquip;
                if (_category isEqualTo "attachments" && { !(_class in (primaryWeaponItems _man)) }) then {
                    _status = "Does not fit your current primary weapon. Use Equipment to inspect it.";
                };
            } else {
                private _path = getText (_cfg >> "model");
                if (_category in ["vests", "headgear"]) then {
                    _path = getText (_cfg >> "ItemInfo" >> "uniformModel");
                };
                if (_path isNotEqualTo "" && { (toLowerANSI (_path select [(count _path - 4) max 0])) isNotEqualTo ".p3d" }) then {
                    _path = _path + ".p3d";
                };

                if (_path isNotEqualTo "" && { fileExists _path }) then {
                    private _model = createSimpleObject [
                        [_path, _class] select (_root isEqualTo "CfgVehicles"),
                        _state get "position",
                        true
                    ];

                    /*  A raw weapon model still carries its muzzle-flash
                        proxies; without simulation nothing hides them. */
                    private _flash = toLowerANSI getText (_cfg >> "selectionFireAnim");
                    {
                        private _name = toLowerANSI _x;
                        if (
                            _name isEqualTo _flash ||
                            { (_name find "zasleh") >= 0 } ||
                            { (_name find "muzzle_flash") >= 0 }
                        ) then {
                            _model hideSelection [_x, true];
                        };
                    } forEach (selectionNames _model);

                    _model setDir 180;
                    _state set ["model", _model];
                    _state set ["subject", _model];
                    _man hideObject true;
                } else {
                    _status = "This item has no standalone preview model. Character view is available for wearable gear.";
                };
            };
        } else {
            _status = "No preview model available for this entry.";
        };
    };

    [_display] call ITW_CLASH_Store_fnc_PreviewUpdateCamera;

    private _browser = _display displayCtrl ITW_CLASH_STORE_BROWSER_IDC;
    [_browser, "previewStatus", _status] call ITW_CLASH_Store_fnc_Push;
    true
};

ITW_CLASH_Store_fnc_PreviewControl = {
    params ["_display", "_data"];

    if (isNull _display) exitWith { false };
    if (isNil { _display getVariable "ITW_CLASH_StorePreview" }) exitWith { false };

    private _state = _display getVariable "ITW_CLASH_StorePreview";

    switch (_data getOrDefault ["action", ""]) do {
        case "orbit": {
            private _dx = _data getOrDefault ["x", 0];
            private _dy = _data getOrDefault ["y", 0];
            if (_dx isEqualType 0 && { _dy isEqualType 0 } && { finite _dx } && { finite _dy }) then {
                _state set ["angle", ((_state get "angle") + (-90 max _dx min 90)) mod 360];
                _state set ["pitch", -30 max ((_state get "pitch") + (-30 max _dy min 30)) min 60];
            };
        };
        case "zoom": {
            private _delta = _data getOrDefault ["value", 0];
            if (_delta isEqualType 0 && { finite _delta }) then {
                _state set ["zoom", 0.45 max ((_state get "zoom") + (-0.3 max _delta min 0.3)) min 2];
            };
        };
        case "reset": {
            _state set ["angle", 135];
            _state set ["pitch", 8];
            _state set ["zoom", 1];
        };
        case "mode": {
            private _mode = _data getOrDefault ["value", ""];
            if (_mode in ["character", "equipment"]) then {
                _state set ["mode", _mode];
                [_display, _state get "selection"] call ITW_CLASH_Store_fnc_PreviewSelect;
            };
        };
        case "viewport": {
            private _rect = _data getOrDefault ["rect", []];
            if (
                _rect isEqualType [] && { (count _rect) isEqualTo 4 } &&
                { (_rect findIf { !(_x isEqualType 0) || { !finite _x } || { _x < 0 } || { _x > 1 } }) isEqualTo -1 } &&
                { (_rect select 2) > 0.05 } && { (_rect select 3) > 0.05 }
            ) then {
                _state set ["viewport", _rect];
            };
        };
    };

    [_display] call ITW_CLASH_Store_fnc_PreviewUpdateCamera;
    true
};

/* ----------------------------------------------------- gear application -- */

ITW_CLASH_Store_fnc_AddInventoryItem = {
    params ["_unit", "_className", "_container"];

    private _added = false;

    switch (_container) do {
        case "uniform": {
            if ((uniform _unit) isEqualTo "") then {
                if (_unit canAdd _className) then { _unit addItem _className; _added = true };
            } else {
                if (_unit canAddItemToUniform _className) then { _unit addItemToUniform _className; _added = true };
            };
        };
        case "vest": {
            if ((vest _unit) isEqualTo "") then {
                if (_unit canAdd _className) then { _unit addItem _className; _added = true };
            } else {
                if (_unit canAddItemToVest _className) then { _unit addItemToVest _className; _added = true };
            };
        };
        case "backpack": {
            if ((backpack _unit) isEqualTo "") then {
                if (_unit canAdd _className) then { _unit addItem _className; _added = true };
            } else {
                if (_unit canAddItemToBackpack _className) then { _unit addItemToBackpack _className; _added = true };
            };
        };
        default {
            if (_unit canAdd _className) then { _unit addItem _className; _added = true };
        };
    };

    _added
};

ITW_CLASH_Store_fnc_ClearCargo = {
    params ["_container"];
    if (isNull _container) exitWith {};
    clearItemCargoGlobal _container;
    clearMagazineCargoGlobal _container;
    clearWeaponCargoGlobal _container;
};

/*  Apply purchased gear to the local unit. Equipment slots are filled first so
    containers exist before anything is packed into them; whatever will not fit
    comes back as an overflow list and is dropped at the player's feet. */
ITW_CLASH_Store_fnc_ApplyGear = {
    params ["_lines"];

    if (!hasInterface) exitWith {};

    /*  Only the server may hand out gear. */
    if (isMultiplayer && { remoteExecutedOwner isNotEqualTo 2 } && { remoteExecutedOwner isNotEqualTo 0 }) exitWith {
        diag_log format [
            "CLASH STORE | GEAR | REJECTED | unexpected-sender | owner=%1",
            remoteExecutedOwner
        ];
    };

    if !(_lines isEqualType []) exitWith {};

    private _unit = player;
    private _overflow = [];
    private _filled = createHashMap;
    private _equipment = [];
    private _cargo = [];

    /*  Lines are positional arrays built by the server; see
        ITW_CLASH_STORE_LINE_* in defines.hpp. */
    {
        if (_x isEqualType [] && { (count _x) >= ITW_CLASH_STORE_LINE_SIZE }) then {
            if ((_x select ITW_CLASH_STORE_LINE_CONTAINER) isEqualTo "auto") then {
                _equipment pushBack _x;
            } else {
                _cargo pushBack _x;
            };
        };
    } forEach _lines;

    /*  Fixed slot order: a vest cannot be packed before it is worn. */
    {
        private _targetCategory = _x;
        {
            if ((_x select ITW_CLASH_STORE_LINE_CATEGORY) isNotEqualTo _targetCategory) then { continue };

            private _className = _x select ITW_CLASH_STORE_LINE_CLASS;
            private _quantity = _x select ITW_CLASH_STORE_LINE_QUANTITY;
            private _attachments = _x select ITW_CLASH_STORE_LINE_ATTACHMENTS;
            private _equipped = false;

            if !(_targetCategory in _filled) then {
                switch (_targetCategory) do {
                    case "uniforms": {
                        removeUniform _unit;
                        _unit forceAddUniform _className;
                        _equipped = (uniform _unit) isEqualTo _className;
                        if (_equipped) then { [uniformContainer _unit] call ITW_CLASH_Store_fnc_ClearCargo };
                    };
                    case "vests": {
                        removeVest _unit;
                        _unit addVest _className;
                        _equipped = (vest _unit) isEqualTo _className;
                        if (_equipped) then { [vestContainer _unit] call ITW_CLASH_Store_fnc_ClearCargo };
                    };
                    case "backpacks": {
                        removeBackpack _unit;
                        _unit addBackpack _className;
                        _equipped = (backpack _unit) isEqualTo _className;
                        if (_equipped) then { [backpackContainer _unit] call ITW_CLASH_Store_fnc_ClearCargo };
                    };
                    case "headgear": {
                        removeHeadgear _unit;
                        _unit addHeadgear _className;
                        _equipped = (headgear _unit) isEqualTo _className;
                    };
                    case "facewear": {
                        removeGoggles _unit;
                        _unit addGoggles _className;
                        _equipped = (goggles _unit) isEqualTo _className;
                    };
                    case "primary";
                    case "handgun";
                    case "secondary": {
                        private _old = switch (_targetCategory) do {
                            case "primary": { primaryWeapon _unit };
                            case "handgun": { handgunWeapon _unit };
                            default { secondaryWeapon _unit };
                        };
                        if (_old isNotEqualTo "") then { _unit removeWeapon _old };
                        _unit addWeapon _className;
                        _equipped = _className in (weapons _unit);

                        if (_equipped) then {
                            /*  Config attachments the buyer kept. */
                            {
                                switch (_targetCategory) do {
                                    case "primary": { _unit addPrimaryWeaponItem _x };
                                    case "handgun": { _unit addHandgunItem _x };
                                    default { _unit addSecondaryWeaponItem _x };
                                };
                            } forEach _attachments;

                            /*  One magazine so the weapon is usable. */
                            private _magazines = getArray (configFile >> "CfgWeapons" >> _className >> "magazines");
                            if ((count _magazines) > 0) then {
                                private _magazine = _magazines select 0;
                                if (_magazine isEqualType "") then {
                                    _unit addMagazine _magazine;
                                };
                            };
                        };
                    };
                    case "misc": {
                        private _kind = (_className call BIS_fnc_itemType) select 1;
                        if (_kind in ["Binocular", "LaserDesignator"]) then {
                            if ((binocular _unit) isNotEqualTo "") then { _unit removeWeapon (binocular _unit) };
                            _unit addWeapon _className;
                            _equipped = (binocular _unit) isEqualTo _className;
                        } else {
                            if (_kind in ["NVGoggles", "GPS", "Map", "Compass", "Watch", "Radio", "Terminal"]) then {
                                _unit linkItem _className;
                                _equipped = _className in (assignedItems _unit);
                            };
                        };
                    };
                };
            };

            if (_equipped) then {
                _filled set [_targetCategory, true];
                _quantity = _quantity - 1;
            };

            /*  Anything beyond the one worn copy goes into inventory. */
            for "_i" from 1 to _quantity do {
                if !([_unit, _className, "auto"] call ITW_CLASH_Store_fnc_AddInventoryItem) then {
                    _overflow pushBack _className;
                };
            };
        } forEach _equipment;
    } forEach [
        "uniforms", "vests", "backpacks", "headgear", "facewear",
        "primary", "handgun", "secondary", "attachments", "misc", "ammo", "mines"
    ];

    {
        private _className = _x select ITW_CLASH_STORE_LINE_CLASS;
        private _container = _x select ITW_CLASH_STORE_LINE_CONTAINER;
        for "_i" from 1 to (_x select ITW_CLASH_STORE_LINE_QUANTITY) do {
            if !([_unit, _className, _container] call ITW_CLASH_Store_fnc_AddInventoryItem) then {
                _overflow pushBack _className;
            };
        };
    } forEach _cargo;

    if !(_overflow isEqualTo []) then {
        private _ground = createVehicle ["GroundWeaponHolder", getPosATL _unit, [], 0, "CAN_COLLIDE"];
        {
            if (isClass (configFile >> "CfgMagazines" >> _x)) then {
                _ground addMagazineCargoGlobal [_x, 1];
            } else {
                if (isClass (configFile >> "CfgWeapons" >> _x)) then {
                    _ground addItemCargoGlobal [_x, 1];
                };
            };
        } forEach _overflow;

        hint format ["Purchase applied. %1 item(s) would not fit and were dropped at your feet.", count _overflow];
    } else {
        hint "Purchase applied.";
    };

    diag_log format [
        "CLASH STORE | GEAR | applied | lines=%1 | overflow=%2",
        count _lines,
        count _overflow
    ];
};

/* -------------------------------------------------------- saved loadouts -- */

/*  Loadouts are whole getUnitLoadout arrays in the player's own Arma profile,
    so they are per-computer and never travel over the network. */

ITW_CLASH_Store_fnc_LoadoutsLoad = {
    private _stored = profileNamespace getVariable ["ITW_CLASH_StoreLoadouts", []];
    if !(_stored isEqualType []) exitWith { [] };

    private _valid = [];
    {
        if (
            _x isEqualType [] && { (count _x) >= 3 } &&
            { (_x select 0) isEqualType "" } && { (_x select 1) isEqualType "" } &&
            { (_x select 2) isEqualType [] }
        ) then {
            _valid pushBack _x;
        };
    } forEach _stored;

    _valid
};

ITW_CLASH_Store_fnc_LoadoutsPersist = {
    params ["_loadouts"];
    profileNamespace setVariable ["ITW_CLASH_StoreLoadouts", _loadouts];
    saveProfileNamespace;
    true
};

/*  [id, name, loadoutArray] -> the payload the page renders. */
ITW_CLASH_Store_fnc_LoadoutsPayload = {
    params [["_message", ""], ["_success", true]];

    private _kits = ([] call ITW_CLASH_Store_fnc_LoadoutsLoad) apply {
        createHashMapFromArray [
            ["id", _x select 0],
            ["name", _x select 1],
            ["lineCount", count ([_x select 2] call ITW_CLASH_Store_fnc_LoadoutClassList)]
        ]
    };

    createHashMapFromArray [
        ["success", _success],
        ["message", _message],
        ["kits", _kits]
    ]
};

/*  Flatten a getUnitLoadout array into [[className, count], ...]. Used to
    price a saved loadout and to show how many lines it holds. */
ITW_CLASH_Store_fnc_LoadoutClassList = {
    params ["_loadout"];

    if !(_loadout isEqualType []) exitWith { [] };

    private _counts = createHashMap;

    private _tally = {
        params ["_class", ["_count", 1]];
        if !(_class isEqualType "") exitWith {};
        if (_class isEqualTo "") exitWith {};
        private _key = _class;
        _counts set [_key, (_counts getOrDefault [_key, 0]) + _count];
    };

    /*  Weapon slots: [weapon, muzzle, pointer, optic, [mag,n], [glMag,n], bipod] */
    private _readWeapon = {
        params ["_slot"];
        if !(_slot isEqualType []) exitWith {};
        {
            private _entry = _x;
            if (_entry isEqualType "") then {
                [_entry] call _tally;
            } else {
                if (_entry isEqualType [] && { (count _entry) >= 2 } && { (_entry select 0) isEqualType "" }) then {
                    [_entry select 0, _entry select 1] call _tally;
                };
            };
        } forEach _slot;
    };

    /*  Container slots: [containerClass, [[item, count], ...]] */
    private _readContainer = {
        params ["_slot"];
        if !(_slot isEqualType []) exitWith {};
        if ((count _slot) < 1) exitWith {};
        if ((_slot select 0) isEqualType "") then { [_slot select 0] call _tally };
        if ((count _slot) >= 2 && { (_slot select 1) isEqualType [] }) then {
            {
                if (_x isEqualType [] && { (count _x) >= 2 }) then {
                    [_x select 0, _x select 1] call _tally;
                };
            } forEach (_slot select 1);
        };
    };

    if ((count _loadout) >= 3) then {
        [_loadout select 0] call _readWeapon;
        [_loadout select 1] call _readWeapon;
        [_loadout select 2] call _readWeapon;
    };
    if ((count _loadout) >= 6) then {
        [_loadout select 3] call _readContainer;
        [_loadout select 4] call _readContainer;
        [_loadout select 5] call _readContainer;
    };
    if ((count _loadout) >= 8) then {
        [_loadout select 6] call _tally;
        [_loadout select 7] call _tally;
    };
    if ((count _loadout) >= 9) then {
        [_loadout select 8] call _readWeapon;
    };
    if ((count _loadout) >= 10 && { (_loadout select 9) isEqualType [] }) then {
        { [_x] call _tally } forEach (_loadout select 9);
    };

    (keys _counts) apply { [_x, _counts get _x] }
};

ITW_CLASH_Store_fnc_LoadoutSave = {
    params ["_name"];

    if !(_name isEqualType "") exitWith {
        ["Invalid loadout name.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    _name = _name regexReplace ["^\s+|\s+$", ""];
    if (_name isEqualTo "") exitWith {
        ["Name the loadout first.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };
    if ((count _name) > 40) then { _name = _name select [0, 40] };

    private _loadout = getUnitLoadout player;
    if (([_loadout] call ITW_CLASH_Store_fnc_LoadoutClassList) isEqualTo []) exitWith {
        ["You are not carrying anything to save.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    private _existing = [] call ITW_CLASH_Store_fnc_LoadoutsLoad;
    private _nameLower = toLowerANSI _name;
    private _id = "";
    private _next = [];

    {
        if ((toLowerANSI (_x select 1)) isEqualTo _nameLower) then {
            _id = _x select 0;
        } else {
            _next pushBack _x;
        };
    } forEach _existing;

    if ((count _next) >= 20) exitWith {
        ["You already have 20 saved loadouts. Delete one first.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    if (_id isEqualTo "") then {
        _id = format ["kit_%1_%2", getPlayerUID player, floor (diag_tickTime * 1000)];
    };

    _next pushBack [_id, _name, _loadout];
    [_next] call ITW_CLASH_Store_fnc_LoadoutsPersist;

    [format ["Saved loadout: %1.", _name], true] call ITW_CLASH_Store_fnc_LoadoutsPayload
};

ITW_CLASH_Store_fnc_LoadoutDelete = {
    params ["_id"];

    if !(_id isEqualType "" && { _id isNotEqualTo "" }) exitWith {
        ["Invalid loadout.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    private _next = [];
    private _found = false;
    {
        if ((_x select 0) isEqualTo _id) then { _found = true } else { _next pushBack _x };
    } forEach ([] call ITW_CLASH_Store_fnc_LoadoutsLoad);

    if (!_found) exitWith {
        ["That loadout no longer exists.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    [_next] call ITW_CLASH_Store_fnc_LoadoutsPersist;
    ["Deleted loadout.", true] call ITW_CLASH_Store_fnc_LoadoutsPayload
};

ITW_CLASH_Store_fnc_LoadoutFind = {
    params ["_id"];

    private _match = [];
    {
        if ((_x select 0) isEqualTo _id) exitWith { _match = _x; };
    } forEach ([] call ITW_CLASH_Store_fnc_LoadoutsLoad);
    _match
};

/*  Loading goes through the server so a saved loadout is priced and charged
    exactly like a cart. With the economy off the charge is zero and the round
    trip is the only cost. */
ITW_CLASH_Store_fnc_LoadoutRequestApply = {
    params ["_id"];

    private _record = [_id] call ITW_CLASH_Store_fnc_LoadoutFind;
    if (_record isEqualTo []) exitWith {
        ["That loadout no longer exists.", false] call ITW_CLASH_Store_fnc_LoadoutsPayload
    };

    [
        player,
        ITW_CLASH_StoreActiveBaseIndex,
        _id,
        [_record select 2] call ITW_CLASH_Store_fnc_LoadoutClassList
    ] remoteExecCall ["ITW_CLASH_Store_fnc_RequestLoadoutApply", 2];

    ["Checking loadout…", true] call ITW_CLASH_Store_fnc_LoadoutsPayload
};

/*  Server said the loadout is paid for; put it on. */
ITW_CLASH_Store_fnc_LoadoutApprove = {
    params ["_id"];

    if (!hasInterface) exitWith {};
    if (isMultiplayer && { remoteExecutedOwner isNotEqualTo 2 } && { remoteExecutedOwner isNotEqualTo 0 }) exitWith {
        diag_log format [
            "CLASH STORE | LOADOUT | REJECTED | unexpected-sender | owner=%1",
            remoteExecutedOwner
        ];
    };

    private _record = [_id] call ITW_CLASH_Store_fnc_LoadoutFind;
    if (_record isEqualTo []) exitWith {};

    player setUnitLoadout (_record select 2);
    hint format ["Loadout applied: %1.", _record select 1];

    private _control = uiNamespace getVariable ["ITW_CLASH_StoreControl", controlNull];
    if (!isNull _control) then {
        [
            _control,
            "loadouts",
            [format ["Loadout applied: %1.", _record select 1], true] call ITW_CLASH_Store_fnc_LoadoutsPayload
        ] call ITW_CLASH_Store_fnc_Push;
    };
};

/* --------------------------------------------------------- event routing -- */

/*  The JSDialog handler. MUST return a boolean: the engine is blocking the
    browser until it gets one, and a frozen store is the symptom of forgetting.
*/
ITW_CLASH_Store_fnc_HandleUiEvent = {
    params ["_control", "_isConfirmDialog", "_message"];

    /*  Receiving anything proves the page is alive, so release any queued
        ExecJS now rather than waiting for PageLoaded, which races. */
    [_control] call ITW_CLASH_Store_fnc_BridgeMarkReady;

    ([_message] call ITW_CLASH_Store_fnc_BridgeDecode) params ["_event", "_data"];
    if (_event isEqualTo "") exitWith { true };

    private _display = ctrlParent _control;

    switch (_event) do {
        case "store::ready": {
            uiNamespace setVariable ["ITW_CLASH_StoreControl", _control];
            [player, ITW_CLASH_StoreActiveBaseIndex] remoteExecCall ["ITW_CLASH_Store_fnc_RequestHydrate", 2];
        };
        case "store::refresh": {
            [player, ITW_CLASH_StoreActiveBaseIndex] remoteExecCall ["ITW_CLASH_Store_fnc_RequestHydrate", 2];
        };
        case "store::category": {
            [player, ITW_CLASH_StoreActiveBaseIndex, _data getOrDefault ["category", ""]]
                remoteExecCall ["ITW_CLASH_Store_fnc_RequestCategory", 2];
        };
        case "store::preview": {
            [_display, _data] call ITW_CLASH_Store_fnc_PreviewSelect;
        };
        case "store::previewControl": {
            [_display, _data] call ITW_CLASH_Store_fnc_PreviewControl;
        };
        case "store::cartChunk": {
            /*  Flatten each decoded line into a plain positional array before
                it crosses the network. Only arrays, numbers and strings go
                over the wire, so nothing depends on how this Arma build
                serialises a HashMap. The server reads the same positions. */
            private _items = _data getOrDefault ["items", []];
            if !(_items isEqualType []) then { _items = [] };

            private _flat = [];
            {
                if (_x isEqualType createHashMap) then {
                    private _attachments = _x getOrDefault ["attachments", []];
                    if !(_attachments isEqualType []) then { _attachments = [] };

                    _flat pushBack [
                        _x getOrDefault ["className", ""],
                        _x getOrDefault ["entryKind", "gear"],
                        _x getOrDefault ["category", ""],
                        _x getOrDefault ["container", "auto"],
                        _x getOrDefault ["quantity", 0],
                        _attachments select { _x isEqualType "" }
                    ];
                };
            } forEach _items;

            [
                player,
                _data getOrDefault ["seq", -1],
                _data getOrDefault ["index", -1],
                _data getOrDefault ["total", 0],
                _flat
            ] remoteExecCall ["ITW_CLASH_Store_fnc_RequestCartChunk", 2];
        };
        case "store::checkout": {
            [
                player,
                ITW_CLASH_StoreActiveBaseIndex,
                _data getOrDefault ["seq", -1],
                _data getOrDefault ["total", 0]
            ] remoteExecCall ["ITW_CLASH_Store_fnc_RequestCheckout", 2];
        };
        case "store::loadoutsOpen": {
            [_control, "loadouts", [] call ITW_CLASH_Store_fnc_LoadoutsPayload] call ITW_CLASH_Store_fnc_Push;
        };
        case "store::loadoutSave": {
            [
                _control,
                "loadouts",
                [_data getOrDefault ["name", ""]] call ITW_CLASH_Store_fnc_LoadoutSave
            ] call ITW_CLASH_Store_fnc_Push;
        };
        case "store::loadoutDelete": {
            [
                _control,
                "loadouts",
                [_data getOrDefault ["id", ""]] call ITW_CLASH_Store_fnc_LoadoutDelete
            ] call ITW_CLASH_Store_fnc_Push;
        };
        case "store::loadoutApply": {
            [
                _control,
                "loadouts",
                [_data getOrDefault ["id", ""]] call ITW_CLASH_Store_fnc_LoadoutRequestApply
            ] call ITW_CLASH_Store_fnc_Push;
        };
        case "store::close": {
            closeDialog 0;
        };
        default {
            diag_log format ["CLASH STORE | UI | unhandled-event | %1", _event];
        };
    };

    true
};

/*  Server responses arrive as JSON text already encoded by the server and are
    handed to the page unchanged. */
ITW_CLASH_Store_fnc_ReceiveResponse = {
    params ["_event", "_json"];

    if (!hasInterface) exitWith {};

    if (isMultiplayer && { remoteExecutedOwner isNotEqualTo 2 } && { remoteExecutedOwner isNotEqualTo 0 }) exitWith {
        diag_log format [
            "CLASH STORE | RESPONSE | REJECTED | unexpected-sender | owner=%1",
            remoteExecutedOwner
        ];
    };

    if !(_event isEqualType "" && { _json isEqualType "" }) exitWith {};

    private _control = uiNamespace getVariable ["ITW_CLASH_StoreControl", controlNull];
    if (isNull _control) exitWith {};

    [_control, _event, _json] call ITW_CLASH_Store_fnc_PushJson;
};

/* ---------------------------------------------------------------- dialog -- */

ITW_CLASH_Store_fnc_OnDialogLoad = {
    params ["_display"];

    if (isNull _display) exitWith {};

    private _control = _display displayCtrl ITW_CLASH_STORE_BROWSER_IDC;
    if (isNull _control) exitWith {
        closeDialog 0;
        hint "The store browser control is unavailable. This mission needs Arma 3 2.20 or newer.";
    };

    [_control] call ITW_CLASH_Store_fnc_BridgeReset;
    uiNamespace setVariable ["ITW_CLASH_StoreControl", _control];

    /*  Local scene objects are created after the display is constructed. */
    [_display] call ITW_CLASH_Store_fnc_PreviewOpen;

    /*  Both readiness signals are wired: PageLoaded is the documented one and
        the page's own first message is the one that usually arrives first. */
    _control ctrlAddEventHandler ["PageLoaded", {
        params ["_control"];
        [_control] call ITW_CLASH_Store_fnc_BridgeMarkReady;
    }];
    _control ctrlAddEventHandler ["JSDialog", ITW_CLASH_Store_fnc_HandleUiEvent];
};

ITW_CLASH_Store_fnc_OnDialogUnload = {
    params ["_display"];

    if (isNull _display) exitWith {};

    [_display] call ITW_CLASH_Store_fnc_PreviewClose;

    private _control = _display displayCtrl ITW_CLASH_STORE_BROWSER_IDC;
    if (!isNull _control) then {
        [_control] call ITW_CLASH_Store_fnc_BridgeReset;
    };

    uiNamespace setVariable ["ITW_CLASH_StoreControl", controlNull];
    ITW_CLASH_StoreActiveBaseIndex = -1;
};

ITW_CLASH_Store_fnc_OpenDialog = {
    if (!hasInterface) exitWith { false };

    private _baseIndex = [] call ITW_CLASH_Store_fnc_NearestBaseIndex;
    if (_baseIndex < 0) exitWith {
        hint "You must be at a base to use the store.";
        false
    };

    ITW_CLASH_StoreActiveBaseIndex = _baseIndex;

    if (!isNull (findDisplay ITW_CLASH_STORE_IDD)) exitWith {
        [player, _baseIndex] remoteExecCall ["ITW_CLASH_Store_fnc_RequestHydrate", 2];
        true
    };

    createDialog "ITW_CLASH_StoreDialog";

    if (isNull (findDisplay ITW_CLASH_STORE_IDD)) exitWith {
        hint "The store could not be opened.";
        false
    };

    true
};

/* ----------------------------------------------------------- entry points -- */

[] spawn {
    scriptName "ITW_CLASH_StoreEntryPoints";

    waitUntil { sleep 1; !isNil "ITW_Bases" && { alive player } };

    /*  Self scroll action, shown only at a base. */
    player addAction [
        "<t color='#8bd1ef'>Base Store</t>",
        { [] call ITW_CLASH_Store_fnc_OpenDialog },
        nil,
        6,
        false,
        true,
        "",
        "_this == _target && {[] call ITW_CLASH_Store_fnc_CanUseStore}"
    ];

    /*  Communication menu, matching how the employment menu is reached. */
    if (!isNil "BIS_fnc_addCommMenuItem") then {
        ITW_CLASH_StoreCommMenuId = [
            "ITW_CLASH_StoreCommMenu",
            ["Base Store", { [] call ITW_CLASH_Store_fnc_OpenDialog }]
        ] call BIS_fnc_addCommMenuItem;
    };

    /*  ACE self-interaction, when ACE is loaded. */
    if (!isNil "ace_interact_menu_fnc_addActionToObject") then {
        private _action = [
            "ITW_CLASH_StoreAce",
            "Base Store",
            "",
            { [] call ITW_CLASH_Store_fnc_OpenDialog },
            { [] call ITW_CLASH_Store_fnc_CanUseStore }
        ] call ace_interact_menu_fnc_createAction;

        [player, 1, ["ACE_SelfActions"], _action] call ace_interact_menu_fnc_addActionToObject;
    };

    diag_log "CLASH STORE | CLIENT | entry-points-registered";
};
