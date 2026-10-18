/*
    C.L.A.S.H. Air Threat Overlay v1 - READ ONLY.

    Server: converts HAL's known ground-AA contacts into side-scoped, sanitized
    [position, radius, age, label] reports. No new enemy acquisition, no
    positions taken from a live hostile's getPosATL, and no HAL task mutations.

    Client: ACE self interaction toggles local map markers. Neither the server
    nor any other client ever creates the player's markers.
*/
if (!isServer && {!hasInterface}) exitWith {true};

if (hasInterface && {
    !(missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayClientStarted",false])
}) then {
    ITW_CLASH_AirThreatOverlayClientStarted = true;
    ITW_CLASH_AirThreatOverlayShown = false;
    ITW_CLASH_AirThreatOverlayRows = [];
    ITW_CLASH_AirThreatOverlaySide = "";
    ITW_CLASH_AirThreatOverlayMarkerCount = 0;

    ITW_CLASH_AirThreatOverlay_fnc_Clear = {
        private _count = missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayMarkerCount",0];
        for "_i" from 0 to (_count - 1) do {
            deleteMarkerLocal format ["CLASH_AA_ZONE_%1",_i];
            deleteMarkerLocal format ["CLASH_AA_LABEL_%1",_i];
        };
        ITW_CLASH_AirThreatOverlayMarkerCount = 0;
    };

    ITW_CLASH_AirThreatOverlay_fnc_Render = {
        [] call ITW_CLASH_AirThreatOverlay_fnc_Clear;
        if (!ITW_CLASH_AirThreatOverlayShown) exitWith {false};
        if (isNull player) exitWith {false};
        if (ITW_CLASH_AirThreatOverlaySide != (toUpperANSI str (side group player))) exitWith {false};
        {
            _x params ["_pos","_radius","_age","_label"];
            if (count _pos < 2 || {_radius <= 0}) then {continue};
            private _id = ITW_CLASH_AirThreatOverlayMarkerCount;
            private _zone = createMarkerLocal [format ["CLASH_AA_ZONE_%1",_id],_pos];
            _zone setMarkerShapeLocal "ELLIPSE";
            _zone setMarkerBrushLocal (if (_age > 120) then {"FDiagonal"} else {"Solid"});
            _zone setMarkerColorLocal "ColorRed";
            _zone setMarkerAlphaLocal (if (_age > 120) then {0.22} else {0.17});
            _zone setMarkerSizeLocal [_radius,_radius];

            private _labelMarker = createMarkerLocal [format ["CLASH_AA_LABEL_%1",_id],_pos];
            _labelMarker setMarkerShapeLocal "ICON";
            _labelMarker setMarkerTypeLocal "mil_warning";
            _labelMarker setMarkerColorLocal "ColorRed";
            _labelMarker setMarkerSizeLocal [0.65,0.65];
            _labelMarker setMarkerTextLocal format [
                "%1 | ~%2 km%3",_label,
                (round (_radius / 100)) / 10,
                if (_age > 120) then {" | LAST KNOWN"} else {""}
            ];
            ITW_CLASH_AirThreatOverlayMarkerCount = _id + 1;
        } forEach ITW_CLASH_AirThreatOverlayRows;
        true
    };

    // Invoked ONLY by server; the payload has coordinates and labels, not
    // object references or enemy positions that a client can query later.
    ITW_CLASH_AirThreatOverlay_fnc_Receive = {
        params ["_sideKey","_rows"];
        if (!hasInterface) exitWith {false};
        if (!isServer && {remoteExecutedOwner != 2}) exitWith {false};
        if (isNull player || {_sideKey != (toUpperANSI str (side group player))}) exitWith {
            ITW_CLASH_AirThreatOverlayRows = [];
            ITW_CLASH_AirThreatOverlaySide = "";
            [] call ITW_CLASH_AirThreatOverlay_fnc_Clear;
            false
        };
        ITW_CLASH_AirThreatOverlaySide = _sideKey;
        ITW_CLASH_AirThreatOverlayRows = _rows;
        if (ITW_CLASH_AirThreatOverlayShown) then {
            [] call ITW_CLASH_AirThreatOverlay_fnc_Render;
        };
        true
    };

    ITW_CLASH_AirThreatOverlay_fnc_Toggle = {
        ITW_CLASH_AirThreatOverlayShown = !ITW_CLASH_AirThreatOverlayShown;
        [] call ITW_CLASH_AirThreatOverlay_fnc_Render;
        systemChat format [
            "C.L.A.S.H. | Air threats %1 (advisory estimates)",
            if (ITW_CLASH_AirThreatOverlayShown) then {"ON"} else {"OFF"}
        ];
    };

    [] spawn {
        scriptName "ITW_CLASH_AirThreatOverlayClient";
        private _installedFor = objNull;
        while {true} do {
            if (isNull player) then {
                [] call ITW_CLASH_AirThreatOverlay_fnc_Clear;
                _installedFor = objNull;
            } else {
                if (ITW_CLASH_AirThreatOverlaySide != (toUpperANSI str (side group player))) then {
                    [] call ITW_CLASH_AirThreatOverlay_fnc_Clear;
                };
                if (player != _installedFor && {
                    !isNil "ace_interact_menu_fnc_createAction"
                    && {!isNil "ace_interact_menu_fnc_addActionToObject"}
                }) then {
                    private _action = [
                        "ITW_CLASH_AirThreatToggle",
                        "Show AirThreats",
                        "",
                        {[] call ITW_CLASH_AirThreatOverlay_fnc_Toggle},
                        {true},
                        {},[],{[0,0,0]},2,[false,false,false,false,false],
                        {
                            params ["_target","_player","_params","_actionData"];
                            _actionData set [
                                1,if (ITW_CLASH_AirThreatOverlayShown) then {
                                    "Hide AirThreats"
                                } else {
                                    "Show AirThreats"
                                }
                            ];
                        }
                    ] call ace_interact_menu_fnc_createAction;
                    [player,1,["ACE_SelfActions"],_action] call ace_interact_menu_fnc_addActionToObject;
                    _installedFor = player;
                };
            };
            uiSleep 1;
        };
    };
    diag_log "CLASH BOOT | air-threat-overlay-client-ready | ace=true localMarkers=true";
};

if (isServer && {
    !(missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayServerStarted",false])
}) then {
    if (isNil "ITW_CLASH_AirPicture_fnc_Observers" ||
        {isNil "ITW_CLASH_fnc_GetCommanderForSide"}) exitWith {
        diag_log "CLASH BOOT | WARNING | air-threat-overlay-prereq-missing | overlay disabled; HAL unchanged";
        false
    };
    ITW_CLASH_AirThreatOverlayServerStarted = true;
    ITW_CLASH_AirThreatOverlayMemory = createHashMap;
    ITW_CLASH_AirThreatOverlayPoll = missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayPoll",15];
    ITW_CLASH_AirThreatOverlayMobileMemory = missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayMobileMemory",600];
    ITW_CLASH_AirThreatOverlayStaticMemory = missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayStaticMemory",1200];
    ITW_CLASH_AirThreatOverlayMargin = missionNamespace getVariable ["ITW_CLASH_AirThreatOverlayMargin",1.25];

    // Derive the longest credible AA engagement range from loaded ammo and
    // matching weapon modes. No arbitrary "SPAA=3.5km" ceiling. Flight speed
    // times TTL is NOT treated as a reliable engagement range.
    ITW_CLASH_AirThreatOverlay_fnc_Range = {
        params ["_veh",["_knownAA",false]];
        if (isNull _veh || {_veh isKindOf "Air"}) exitWith {0};

        private _profile = [_veh] call ITW_CLASH_AirPicture_fnc_WeaponProfile;
        private _radar = _profile getOrDefault ["radar",false];
        private _loaded = [];
        {
            if ((_x#2) > 0) then {_loaded pushBackUnique (_x#0)};
        } forEach (magazinesAllTurrets _veh);
        if (_veh isKindOf "CAManBase") then {
            {_loaded pushBackUnique _x} forEach magazines _veh;
        };
        private _weapons = +weapons _veh;
        private _turrets = allTurrets [_veh,true];
        _turrets pushBack [];
        {_weapons append (weaponsTurret [_veh,_x])} forEach _turrets;
        _weapons = _weapons arrayIntersect _weapons;

        private _best = 0;
        {
            private _mag = _x;
            private _ammoName = getText (configFile >> "CfgMagazines" >> _mag >> "ammo");
            if (_ammoName == "") then {continue};
            private _ammo = configFile >> "CfgAmmo" >> _ammoName;
            // Some sensor-driven SAM mods omit legacy airLock. HAL\'s own
            // AA threat bucket is independent corroboration for their role.
            if (getNumber (_ammo >> "airLock") <= 1 && {!_knownAA}) then {continue};
            private _guided = [_ammoName] call ITW_CLASH_AirPicture_fnc_AmmoIsGuided;
            private _range = getNumber (_ammo >> "maxRange");
            _range = _range max getNumber (_ammo >> "missileLockMaxDistance");
            if (_guided) then {
                _range = _range max getNumber (_ammo >> "maxControlRange");
            };
            {
                private _cfg = configFile >> "CfgWeapons" >> _x;
                // A weapon may support many magazines; ignore unrelated guns.
                if !(_mag in getArray (_cfg >> "magazines")) then {continue};
                _range = _range max getNumber (_cfg >> "maxRange");
                {
                    _range = _range max getNumber (_cfg >> _x >> "maxRange");
                } forEach getArray (_cfg >> "modes");
            } forEach _weapons;
            // Modded missiles sometimes omit range properties or inherit a
            // nonsensical few hundred metres from a generic CfgAmmo class.
            if (_guided && {_range < 2000}) then {
                _range = if (_radar) then {12000} else {8000};
            };
            if (!_guided && {_range < 300}) then {_range = 2500};
            _best = _best max _range;
        } forEach _loaded;
        // A range of zero means we have no evidence of AA armament.
        if (_best <= 0 && {_knownAA}) then {
            // An identified AA system with unreadable mod ammunition must
            // not be depicted as safe at 2 km. This is a coarse warning.
            _best = if (_radar) then {12000} else {8000};
        };
        if (_best <= 0) exitWith {0};
        (_best * ITW_CLASH_AirThreatOverlayMargin) max 1000 min 60000
    };

    // Use an observer's engine-maintained perceived position, NEVER getPosATL
    // on a hostile object. A stale HAL object reference is not fresh sighting.
    // Returns [knownPosition, lastSeenTime, errorRadius].
    ITW_CLASH_AirThreatOverlay_fnc_Perceived = {
        params ["_target","_observers"];
        private _best = [];
        private _newest = -1;
        {
            if (isNull _x || {!alive _x}) then {continue};
            if ((_x knowsAbout _target) < 0.05) then {continue};
            private _intel = _x targetKnowledge _target;
            if (count _intel < 7) then {continue};
            _intel params ["_knownGroup","_knownUnit","_lastSeen","","","_error","_pos"];
            if (!_knownGroup && {!_knownUnit}) then {continue};
            if (_lastSeen <= 0 || {_lastSeen < time - 180}) then {continue};
            if (count _pos < 2 || {_pos#0 <= 0 && {_pos#1 <= 0}}) then {continue};
            if (_lastSeen > _newest) then {
                _newest = _lastSeen;
                _best = [+_pos,_lastSeen,_error max 0];
            };
        } forEach _observers;
        _best
    };

    ITW_CLASH_AirThreatOverlay_fnc_Snapshot = {
        params ["_side"];
        private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
        if (isNull _hq) exitWith {[]};
        private _key = toUpperANSI str _side;
        private _memory = ITW_CLASH_AirThreatOverlayMemory getOrDefault [_key,createHashMap];
        ITW_CLASH_AirThreatOverlayMemory set [_key,_memory];
        private _observers = [_hq] call ITW_CLASH_AirPicture_fnc_Observers;
        private _aaGroups = _hq getVariable ["RydHQ_AAthreat",[]];
        private _candidates = +(_hq getVariable ["RydHQ_KnEnemies",[]]);
        // Existing denial memory supplies known identities, NOT true positions.
        {
            _candidates pushBackUnique (_y get "vehicle");
        } forEach ([_hq] call ITW_CLASH_AirPicture_fnc_Denials);

        private _processed = [];
        {
            private _unit = _x;
            if (isNull _unit) then {continue};
            private _veh = vehicle _unit;
            if (isNull _veh || {_veh isKindOf "Air"} || {!alive _veh}) then {continue};
            private _id = [_veh] call ITW_CLASH_AirPicture_fnc_ContactKey;
            if (_id in _processed) then {continue};
            _processed pushBack _id;

            private _crewGroup = group effectiveCommander _veh;
            private _knownAA = _crewGroup in _aaGroups || {group _unit in _aaGroups};
            private _range = [_veh,_knownAA] call ITW_CLASH_AirThreatOverlay_fnc_Range;
            if (_range <= 0) then {continue};
            private _intel = [_veh,_observers] call ITW_CLASH_AirThreatOverlay_fnc_Perceived;
            if (_intel isEqualTo [] && {_unit != _veh}) then {
                _intel = [_unit,_observers] call ITW_CLASH_AirThreatOverlay_fnc_Perceived;
            };
            if (_intel isEqualTo []) then {continue};
            _intel params ["_position","_seenAt","_error"];
            private _stored = _memory getOrDefault [_id,[]];
            if (_stored isEqualTo [] || {_seenAt >= (_stored#2)}) then {
                // Error margin widens the warning, never contracts it.
                private _radius = (_range + _error) min 60000;
                private _category = if (_veh isKindOf "CAManBase") then {
                    "AA infantry"
                } else {
                    if (_veh isKindOf "StaticWeapon") then {"AA emplacement"} else {"AA vehicle"}
                };
                _memory set [_id,[_position,_radius,_seenAt,_category,
                    if (_veh isKindOf "StaticWeapon") then {
                        ITW_CLASH_AirThreatOverlayStaticMemory
                    } else {
                        ITW_CLASH_AirThreatOverlayMobileMemory
                    },_veh]];
            };
        } forEach _candidates;

        private _rows = [];
        private _ids = keys _memory;
        _ids sort true;
        {
            private _entry = _memory get _x;
            _entry params ["_pos","_radius","_seenAt","_category","_ttl","_veh"];
            if (isNull _veh || {!alive _veh} || {(time - _seenAt) > _ttl}) then {
                _memory deleteAt _x;
                continue
            };
            _rows pushBack [+_pos,_radius,(time - _seenAt) max 0,_category];
        } forEach _ids;
        _rows
    };

    [] spawn {
        scriptName "ITW_CLASH_AirThreatOverlayServer";
        while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                private _side = _x;
                private _rows = [_side] call ITW_CLASH_AirThreatOverlay_fnc_Snapshot;
                private _key = toUpperANSI str _side;
                {
                    if (side group _x == _side) then {
                        [_key,_rows] remoteExecCall ["ITW_CLASH_AirThreatOverlay_fnc_Receive",_x];
                    };
                } forEach allPlayers;
            } forEach _sides;
            sleep ITW_CLASH_AirThreatOverlayPoll;
        };
    };
    diag_log "CLASH BOOT | air-threat-overlay-server-ready | readonly=true source=HAL range=config sideScoped=true";
};
true
