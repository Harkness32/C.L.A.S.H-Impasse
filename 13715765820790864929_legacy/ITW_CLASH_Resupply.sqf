#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ResupplyStarted",false]) exitWith {
    missionNamespace getVariable ["ITW_CLASH_ResupplyReady",false]
};

ITW_CLASH_ResupplyStarted = true;
ITW_CLASH_ResupplyReady = false;
ITW_CLASH_ResupplyVersion = 1;

/*
    One owner for "HAL let this unit run dry and nothing is coming".
    Native HAL resupply always gets the first chance. A group is only claimed
    after staying in need past a patience window with no native delivery in
    flight; it is then held with HAL's own Busy lock (taken only after HAL's
    Break unwinds the running order), withdrawn to a clear rally, served by
    HAL's own Go*Supp delivery scripts or an ACE-magic crate, and released.

    Known unsolved: ground delivery is a physical service vehicle covering only
    its own kind, while an air-dropped crate covers all three. A unit needing
    two kinds with no air available gets them one truck at a time.
*/

{
    missionNamespace setVariable [_x#0,missionNamespace getVariable [_x#0,_x#1]];
} forEach [
    ["ITW_CLASH_ResupplyTick",5],
    ["ITW_CLASH_ResupplyPatience",120],
    ["ITW_CLASH_ResupplyNativeGrace",45],
    ["ITW_CLASH_ResupplyClaimTimeout",900],
    ["ITW_CLASH_ResupplyMaxRetries",2],
    ["ITW_CLASH_ResupplyMaxClaimsPerHQ",4],
    ["ITW_CLASH_ResupplyMaxDeliveriesPerHQ",3],
    ["ITW_CLASH_ResupplyArrivalRadius",75],
    ["ITW_CLASH_ResupplyServiceRadius",40],
    ["ITW_CLASH_ResupplyShareRadius",1500],
    ["ITW_CLASH_ResupplyGroundMaxRoad",5000],
    ["ITW_CLASH_ResupplyCrateUses",3],
    ["ITW_CLASH_ResupplyCrateIdleLife",1200],
    ["ITW_CLASH_ResupplyInfantryHollowShare",0.5],
    ["ITW_CLASH_ResupplyFuelThreshold",0.1],
    ["ITW_CLASH_ResupplyRepairThreshold",0.5],
    ["ITW_CLASH_ResupplyRetryCooldown",300],
    ["ITW_CLASH_ResupplyBuyCooldown",90],
    ["ITW_CLASH_ResupplyInFlightStale",900],
    ["ITW_CLASH_ResupplyFloorRadius",500],
    ["ITW_CLASH_ResupplyHeavyRadius",1500],
    ["ITW_CLASH_ResupplyStepDistance",250],
    ["ITW_CLASH_ResupplyMaxSearch",3000],
    ["ITW_CLASH_ResupplyPrimaryMags",6],
    ["ITW_CLASH_ResupplyHandgunMags",2]
];
ITW_CLASH_ResupplySweepOffsets = [0,-45,45,-90,90];

ITW_CLASH_ResupplyClaims = createHashMap;
ITW_CLASH_ResupplyCrates = createHashMap;
ITW_CLASH_ResupplyMagCache = createHashMap;

ITW_CLASH_Resupply_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_fnc_Log") then {
        ["resupply-" + _event,_payload] call ITW_CLASH_fnc_Log;
    } else {
        diag_log format ["CLASH RESUPPLY | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_Resupply_fnc_Say = {
    params ["_text"];
    diag_log ("CLASH RESUPPLY | " + _text);
};

ITW_CLASH_Resupply_fnc_Id = {
    params ["_group"];
    if (!isNil "ITW_CLASH_fnc_GroupId") exitWith {[_group] call ITW_CLASH_fnc_GroupId};
    groupId _group
};

ITW_CLASH_Resupply_fnc_Describe = {
    params ["_group"];
    private _id = [_group] call ITW_CLASH_Resupply_fnc_Id;
    private _veh = vehicle leader _group;
    if (_veh != leader _group) exitWith {
        format ["%1 (%2)",_id,getText (configOf _veh >> "displayName")]
    };
    format ["%1 (%2 infantry)",_id,{alive _x} count units _group]
};

ITW_CLASH_Resupply_fnc_HQs = {
    private _result = [];
    {
        if (_x != sideUnknown) then {
            private _hq = [_x] call ITW_CLASH_fnc_GetCommanderForSide;
            if (!isNull _hq) then {_result pushBackUnique _hq};
        };
    } forEach [
        missionNamespace getVariable ["ITW_PlayerSide",sideUnknown],
        missionNamespace getVariable ["ITW_EnemySide",sideUnknown]
    ];
    _result
};

ITW_CLASH_Resupply_fnc_TargetGroup = {
    params ["_target"];
    if (isNull _target) exitWith {grpNull};
    if (_target isKindOf "Man") exitWith {group _target};
    private _commander = effectiveCommander _target;
    if (isNull _commander) then {_commander = driver _target};
    if (isNull _commander) exitWith {grpNull};
    group _commander
};

ITW_CLASH_Resupply_fnc_Stamp = {
    params ["_group","_delta"];
    if (isNull _group) exitWith {};
    private _count = ((_group getVariable ["ITW_CLASH_ResupplyInFlight",0]) + _delta) max 0;
    _group setVariable ["ITW_CLASH_ResupplyInFlight",_count];
    _group setVariable ["ITW_CLASH_ResupplyInFlightAt",time];
};

ITW_CLASH_Resupply_fnc_InFlight = {
    params ["_group"];
    if (isNull _group) exitWith {false};
    if (
        (_group getVariable ["ITW_CLASH_ResupplyInFlight",0]) > 0
        && {time - (_group getVariable ["ITW_CLASH_ResupplyInFlightAt",-1e6]) < ITW_CLASH_ResupplyInFlightStale}
    ) exitWith {true};
    if ((_group getVariable ["ITW_CLASH_NativeAmmoExecution",""]) isNotEqualTo "") exitWith {true};

    private _thunder = false;
    if (!isNil "ITW_CLASH_ThunderRuns") then {
        {
            private _state = ITW_CLASH_ThunderRuns getOrDefault [_x,createHashMap];
            if (
                count _state > 0
                && {!(_state getOrDefault ["finalized",false])}
                && {([_state getOrDefault ["target",objNull]] call ITW_CLASH_Resupply_fnc_TargetGroup) isEqualTo _group}
            ) exitWith {_thunder = true};
        } forEach (keys ITW_CLASH_ThunderRuns);
    };
    _thunder
};

// Only vehicles this group commands: infantry riding in another group's
// transport must not inherit that transport's fuel or damage.
ITW_CLASH_Resupply_fnc_GroundVehicles = {
    params ["_group"];
    private _result = [];
    {
        private _unit = _x;
        if (!alive _unit) then {continue};
        {
            if (
                !isNull _x
                && {alive _x}
                && {_x isKindOf "LandVehicle"}
                && {!(_x isKindOf "StaticWeapon")}
                && {
                    ([_x] call ITW_CLASH_Resupply_fnc_TargetGroup) isEqualTo _group
                    || {_x isEqualTo (assignedVehicle _unit) && {((crew _x) select {alive _x}) isEqualTo []}}
                }
            ) then {_result pushBackUnique _x};
        } forEach [vehicle _unit,assignedVehicle _unit];
    } forEach units _group;
    _result
};

// HAL's own non-combat vehicle list first, so an empty truck never reads as dry.
ITW_CLASH_Resupply_fnc_IsArmed = {
    params ["_veh","_hq"];
    if ((toLowerANSI typeOf _veh) in (_hq getVariable ["RydHQ_NCVeh",[]])) exitWith {false};
    ([[-1]] + (allTurrets [_veh,true])) findIf {
        (_veh weaponsTurret _x) findIf {
            private _weapon = toLowerANSI _x;
            (_weapon find "horn") < 0
            && {(_weapon find "smoke") < 0}
            && {(_weapon find "cmflare") < 0}
        } >= 0
    } >= 0
};

ITW_CLASH_Resupply_fnc_WeaponMags = {
    params ["_weapon"];
    if (_weapon isEqualTo "") exitWith {[]};
    private _key = toLowerANSI _weapon;
    private _cached = ITW_CLASH_ResupplyMagCache getOrDefault [_key,[]];
    if (_cached isNotEqualTo []) exitWith {_cached};
    private _mags = ([_weapon] call BIS_fnc_compatibleMagazines) apply {toLowerANSI _x};
    ITW_CLASH_ResupplyMagCache set [_key,_mags];
    _mags
};

ITW_CLASH_Resupply_fnc_CountMags = {
    params ["_unit","_weapon"];
    private _compatible = [_weapon] call ITW_CLASH_Resupply_fnc_WeaponMags;
    if (_compatible isEqualTo []) exitWith {99};
    {(toLowerANSI _x) in _compatible} count (magazines _unit)
};

// AMMO_INF is kept separate from vehicle AMMO: only an air crate can serve it.
ITW_CLASH_Resupply_fnc_Needs = {
    params ["_group","_hq"];
    private _needs = [];
    {
        if (!someAmmo _x && {[_x,_hq] call ITW_CLASH_Resupply_fnc_IsArmed}) then {_needs pushBackUnique "AMMO"};
        if (fuel _x <= ITW_CLASH_ResupplyFuelThreshold) then {_needs pushBackUnique "FUEL"};
        if (damage _x >= ITW_CLASH_ResupplyRepairThreshold || {!canMove _x}) then {_needs pushBackUnique "REPAIR"};
    } forEach ([_group] call ITW_CLASH_Resupply_fnc_GroundVehicles);

    private _dismounted = (units _group) select {alive _x && {vehicle _x == _x}};
    if (_dismounted isNotEqualTo []) then {
        private _hollow = {([_x,primaryWeapon _x] call ITW_CLASH_Resupply_fnc_CountMags) < 2} count _dismounted;
        if ((_hollow / (count _dismounted)) >= ITW_CLASH_ResupplyInfantryHollowShare) then {
            _needs pushBackUnique "AMMO_INF";
        };
    };
    _needs
};

ITW_CLASH_Resupply_fnc_MagicFor = {
    params ["_kind"];
    switch (_kind) do {
        case "AMMO";
        case "AMMO_INF": {missionNamespace getVariable ["RydxHQ_MagicRearm",false]};
        case "FUEL": {missionNamespace getVariable ["RydxHQ_MagicRefuel",false]};
        case "REPAIR": {missionNamespace getVariable ["RydxHQ_MagicRepair",false]};
        default {false};
    }
};

ITW_CLASH_Resupply_fnc_Eligible = {
    params ["_group","_hq"];
    if (isNull _group || {({alive _x} count units _group) == 0}) exitWith {false};
    if !(_group in (_hq getVariable ["RydHQ_Friends",[]])) exitWith {false};
    if ((units _group findIf {isPlayer _x}) >= 0) exitWith {false};
    if (time < (_group getVariable ["ITW_CLASH_ResupplyRetryAt",0])) exitWith {false};

    private _var = str _group;
    if (
        _group getVariable ["ITW_CLASH_GTFO",false]
        || {_group getVariable ["ITW_CLASH_Withdrawing",false]}
        || {_group getVariable ["ITW_CLASH_ThunderRunActive",false]}
        || {_group getVariable ["Resting" + _var,false]}
        || {_group getVariable ["ITW_CLASH_ServiceAsset",false]}
        || {_group getVariable ["ITW_CLASH_CheckbookAsset",false]}
        || {(_group getVariable ["ITW_CLASH_CASEVAC_State",""]) isNotEqualTo ""}
        || {(_group getVariable ["ITW_CLASH_GroundMEDEVAC_State",""]) isNotEqualTo ""}
    ) exitWith {false};

    private _providers = (_hq getVariable ["RydHQ_AmmoSupportG",[]])
        + (_hq getVariable ["RydHQ_FuelSupportG",[]])
        + (_hq getVariable ["RydHQ_RepSupportG",[]])
        + (_hq getVariable ["RydHQ_AmmoDrop",[]]);
    if (_group in _providers) exitWith {false};

    private _veh = vehicle leader _group;
    !(_veh isKindOf "Air") && {!(_veh isKindOf "Ship")}
};

ITW_CLASH_Resupply_fnc_CountClaims = {
    params ["_hq",["_states",[]]];
    {
        private _claim = ITW_CLASH_ResupplyClaims getOrDefault [_x,createHashMap];
        count _claim > 0
        && {(_claim get "hq") isEqualTo _hq}
        && {_states isEqualTo [] || {(_claim get "state") in _states}}
    } count (keys ITW_CLASH_ResupplyClaims)
};

// [pos, hq] -> [clear, nearestDist, nearestGroup]. Long-reach threats (armor,
// AT, artillery) get a wider radius than the general known-enemy floor.
ITW_CLASH_Resupply_fnc_Clearance = {
    params ["_pos","_hq"];
    private _known = _hq getVariable ["RydHQ_KnEnemiesG",[]];
    private _heavy = (_hq getVariable ["RydHQ_EnHArmor",[]])
        + (_hq getVariable ["RydHQ_EnLArmorAT",[]])
        + (_hq getVariable ["RydHQ_EnArt",[]]);

    private _floorCheck = [_pos,_known,ITW_CLASH_ResupplyFloorRadius] call RYD_CloseEnemyB;
    private _heavyCheck = [_pos,_heavy,ITW_CLASH_ResupplyHeavyRadius] call RYD_CloseEnemyB;

    private _clear = !(_floorCheck#0) && {!(_heavyCheck#0)};
    private _nearestDist = (_floorCheck#1) min (_heavyCheck#1);
    private _nearestGroup = if ((_floorCheck#1) <= (_heavyCheck#1)) then {_floorCheck#2} else {_heavyCheck#2};
    [_clear,_nearestDist,_nearestGroup]
};

ITW_CLASH_Resupply_fnc_SnapToRoad = {
    params ["_pos",["_searchRadius",150]];
    private _roads = _pos nearRoads _searchRadius;
    if (_roads isEqualTo []) exitWith {_pos};
    private _nearest = _roads select 0;
    private _nearestDist = _pos distance2D _nearest;
    {
        private _d = _pos distance2D _x;
        if (_d < _nearestDist) then {_nearest = _x; _nearestDist = _d};
    } forEach _roads;
    getPosATL _nearest
};

ITW_CLASH_Resupply_fnc_ScreenCount = {
    params ["_candidate","_threatPos","_hq"];
    private _count = 0;
    {
        private _fv = vehicle (leader _x);
        if (
            (_fv distance _threatPos) < (_candidate distance _threatPos)
            && {(_fv distance _candidate) < (_candidate distance _threatPos)}
        ) then {
            _count = _count + 1;
        };
    } forEach (_hq getVariable ["RydHQ_Friends",[]]);
    _count
};

// Walk away from the nearest known threat until a candidate clears; the FOB
// only wins if it is closer AND independently clears the same check.
ITW_CLASH_Resupply_fnc_ResolveRally = {
    params ["_group","_hq","_origin","_isVehicle"];

    private _nearest = [_origin,(_hq getVariable ["RydHQ_KnEnemiesG",[]]),1000000] call RYD_CloseEnemyB;
    private _threatPos = _origin;
    private _baseBearing = 0;
    if (!isNull (_nearest#2)) then {
        _threatPos = getPosATL (leader (_nearest#2));
        _baseBearing = _threatPos getDir _origin;
    };

    private _best = [];
    private _bestScreen = -1;
    private _bestDist = 1e10;
    {
        private _bearing = _baseBearing + _x;
        private _found = false;
        private _dist = ITW_CLASH_ResupplyStepDistance;
        while {_dist <= ITW_CLASH_ResupplyMaxSearch && {!_found}} do {
            private _candidate = _origin getPos [_dist,_bearing];
            if (_isVehicle) then {
                _candidate = [_candidate] call ITW_CLASH_Resupply_fnc_SnapToRoad;
            };
            if (!(surfaceIsWater _candidate) && {([_candidate,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0}) then {
                _found = true;
                private _screen = [_candidate,_threatPos,_hq] call ITW_CLASH_Resupply_fnc_ScreenCount;
                if (_screen > _bestScreen) then {
                    _bestScreen = _screen;
                    _bestDist = _dist;
                    _best = [_candidate,"rendezvous"];
                };
            };
            _dist = _dist + ITW_CLASH_ResupplyStepDistance;
        };
        if (_found && {_x == 0}) exitWith {};
    } forEach ITW_CLASH_ResupplySweepOffsets;

    if (
        !isNil "ITW_CLASH_VehicleEchelon_fnc_Objective"
        && {!isNil "ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn"}
    ) then {
        private _objective = [_group,vehicle leader _group] call ITW_CLASH_VehicleEchelon_fnc_Objective;
        private _forward = [_objective,side _group] call ITW_CLASH_Reconstitution_fnc_ResolveForwardSpawn;
        if (_forward isNotEqualTo []) then {
            private _fobPos = _forward#0;
            private _fobDistance = _origin distance _fobPos;
            if (
                _fobDistance <= _bestDist
                && {([_fobPos,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0}
            ) then {
                _best = [_fobPos,"fob"];
            };
        };
    };
    _best
};

ITW_CLASH_Resupply_fnc_CrateKey = {
    params ["_crate"];
    private _key = netId _crate;
    if (_key isEqualTo "" || {_key isEqualTo "0:0"}) then {_key = str _crate};
    _key
};

ITW_CLASH_Resupply_fnc_CrateCovers = {
    params ["_needs"];
    _needs findIf {[_x] call ITW_CLASH_Resupply_fnc_MagicFor} >= 0
};

ITW_CLASH_Resupply_fnc_CrateNear = {
    params ["_pos","_radius","_side","_needs"];
    if !([_needs] call ITW_CLASH_Resupply_fnc_CrateCovers) exitWith {objNull};
    private _best = objNull;
    private _bestDist = _radius;
    {
        (ITW_CLASH_ResupplyCrates get _x) params ["_crate","_uses","","","_crateSide"];
        if (isNull _crate || {_uses <= 0} || {(_crateSide getFriend _side) < 0.6}) then {continue};
        private _d = _pos distance2D _crate;
        if (_d <= _bestDist) then {_best = _crate; _bestDist = _d};
    } forEach (keys ITW_CLASH_ResupplyCrates);
    _best
};

// A live crate is the best meeting ground; failing that, another claim's
// rally, so one delivery can serve both groups.
ITW_CLASH_Resupply_fnc_FindSharedRally = {
    params ["_claim","_origin"];
    private _group = _claim get "group";
    private _hq = _claim get "hq";

    private _crate = [_origin,ITW_CLASH_ResupplyShareRadius,side _group,_claim get "needs"] call ITW_CLASH_Resupply_fnc_CrateNear;
    if (!isNull _crate && {([getPosATL _crate,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0}) exitWith {
        [getPosATL _crate,"crate"]
    };

    private _best = [];
    private _bestDist = ITW_CLASH_ResupplyShareRadius;
    {
        if (_x == (_claim get "id")) then {continue};
        private _other = ITW_CLASH_ResupplyClaims get _x;
        if ((_other get "hq") isNotEqualTo _hq) then {continue};
        private _pos = _other get "rally";
        if (_pos isEqualTo []) then {continue};
        private _d = _origin distance2D _pos;
        if (_d < _bestDist && {([_pos,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0}) then {
            _best = [_pos,"shared-rally"];
            _bestDist = _d;
        };
    } forEach (keys ITW_CLASH_ResupplyClaims);
    _best
};

ITW_CLASH_Resupply_fnc_ClearHALRoles = {
    params ["_group","_hq"];
    if (isNull _hq) exitWith {};
    {
        private _members = +(_hq getVariable [_x,[]]);
        if (_group in _members) then {_hq setVariable [_x,_members - [_group]]};
    } forEach ["RydHQ_Garrison","RydHQ_DefSpot","RydHQ_Def","RydHQ_DefRes","RydHQ_RecDefSpot"];
    if (_group getVariable ["Defending",false]) then {_group setVariable ["Defending",false]};
};

ITW_CLASH_Resupply_fnc_OrderMove = {
    params ["_group","_pos"];
    [_group] call RYD_WPdel;
    private _wp = _group addWaypoint [_pos,0];
    _wp setWaypointType "MOVE";
    _wp setWaypointBehaviour "AWARE";
    _wp setWaypointCombatMode "YELLOW";
    _wp setWaypointSpeed "FULL";
    _wp setWaypointCompletionRadius 25;
    _group setCurrentWaypoint _wp;
};

// Break is HAL's own cancellation surface: the order that owns Busy unwinds
// and releases it itself. Busy is only taken once that has happened.
ITW_CLASH_Resupply_fnc_Claim = {
    params ["_group","_hq","_needs"];
    private _id = [_group] call ITW_CLASH_Resupply_fnc_Id;
    private _claim = createHashMapFromArray [
        ["id",_id],["group",_group],["hq",_hq],["state","BREAKING"],
        ["needs",_needs],["claimedAt",time],["busyOwned",false],
        ["rally",[]],["rallySource",""],["inPlace",false],["arrivedAt",-1],
        ["relocations",0],["lastRallyCheck",time],["lastMoveOrder",-1],
        ["deliveryAt",-1],["deliveryMode",""],["retries",0],["lastDispatchTry",-1]
    ];
    ITW_CLASH_ResupplyClaims set [_id,_claim];
    _group setVariable ["ITW_CLASH_ResupplyClaimed",true];

    ["claim",[_id,_needs,side _group]] call ITW_CLASH_Resupply_fnc_Log;
    [format [
        "%1 has needed %2 for %3s with nothing inbound - taking it from HAL for resupply",
        [_group] call ITW_CLASH_Resupply_fnc_Describe,
        _needs joinString "+",
        round ITW_CLASH_ResupplyPatience
    ]] call ITW_CLASH_Resupply_fnc_Say;

    [_claim] spawn {
        params ["_claim"];
        private _group = _claim get "group";
        private _var = str _group;
        private _breakSet = false;
        if (
            _group getVariable ["Busy" + _var,false]
            || {_group getVariable ["Resting" + _var,false]}
        ) then {
            _group setVariable ["Break",true];
            _breakSet = true;
        };

        private _deadline = time + 45;
        waitUntil {
            sleep 1;
            isNull _group
            || {time >= _deadline}
            || {
                !(_group getVariable ["Busy" + _var,false])
                && {!(_group getVariable ["Resting" + _var,false])}
                && {!(_group getVariable ["Break",false])}
            }
        };
        if (isNull _group) exitWith {};
        if !(_group getVariable ["ITW_CLASH_ResupplyClaimed",false]) exitWith {};

        if (
            _group getVariable ["Busy" + _var,false]
            || {_group getVariable ["Resting" + _var,false]}
        ) exitWith {
            if (_breakSet) then {_group setVariable ["Break",false]};
            _claim set ["abortReason","hal-order-did-not-unwind"];
            _claim set ["state","ABORT"];
        };

        _group setVariable ["Busy" + _var,true];
        _claim set ["busyOwned",true];
        [_group,_claim get "hq"] call ITW_CLASH_Resupply_fnc_ClearHALRoles;
        _claim set ["state","RESOLVE"];
    };
    true
};

ITW_CLASH_Resupply_fnc_Release = {
    params ["_id","_reason"];
    private _claim = ITW_CLASH_ResupplyClaims getOrDefault [_id,createHashMap];
    ITW_CLASH_ResupplyClaims deleteAt _id;
    if (count _claim == 0) exitWith {false};

    private _group = _claim get "group";
    if (!isNull _group) then {
        if (_claim get "busyOwned") then {
            [_group] call RYD_WPdel;
            _group setVariable ["Busy" + str _group,false];
        };
        _group setVariable ["ITW_CLASH_ResupplyClaimed",nil];
        _group setVariable ["ITW_CLASH_ResupplyNeedSince",nil];
        if (_reason != "serviced") then {
            _group setVariable ["ITW_CLASH_ResupplyRetryAt",time + ITW_CLASH_ResupplyRetryCooldown];
        };
    };

    ["release",[_id,_reason,time - (_claim get "claimedAt")]] call ITW_CLASH_Resupply_fnc_Log;
    [format [
        "%1 handed back to HAL (%2) after %3s",
        if (isNull _group) then {_id} else {[_group] call ITW_CLASH_Resupply_fnc_Describe},
        _reason,
        round (time - (_claim get "claimedAt"))
    ]] call ITW_CLASH_Resupply_fnc_Say;
    true
};

ITW_CLASH_Resupply_fnc_Detect = {
    params ["_hq"];
    private _groups = [];
    {
        private _g = [_x] call ITW_CLASH_Resupply_fnc_TargetGroup;
        if (!isNull _g) then {_groups pushBackUnique _g};
    } forEach (
        (_hq getVariable ["RydHQ_Hollow",[]])
        + (_hq getVariable ["RydHQ_Dried",[]])
        + (_hq getVariable ["RydHQ_damaged",[]])
    );

    {
        private _group = _x;
        if (_group getVariable ["ITW_CLASH_ResupplyClaimed",false]) then {continue};
        if !([_group,_hq] call ITW_CLASH_Resupply_fnc_Eligible) then {continue};

        private _needs = [_group,_hq] call ITW_CLASH_Resupply_fnc_Needs;
        if (_needs isEqualTo []) then {
            _group setVariable ["ITW_CLASH_ResupplyNeedSince",nil];
            continue
        };

        // Patience restarts whenever native HAL is actually delivering.
        private _seen = _group getVariable ["ITW_CLASH_ResupplyNeedSince",[]];
        if (
            _seen isEqualTo []
            || {time - (_seen#1) > (ITW_CLASH_ResupplyTick * 6)}
            || {[_group] call ITW_CLASH_Resupply_fnc_InFlight}
        ) then {
            _group setVariable ["ITW_CLASH_ResupplyNeedSince",[time,time]];
            continue
        };
        _group setVariable ["ITW_CLASH_ResupplyNeedSince",[_seen#0,time]];
        if (time - (_seen#0) < ITW_CLASH_ResupplyPatience) then {continue};
        if (([_hq] call ITW_CLASH_Resupply_fnc_CountClaims) >= ITW_CLASH_ResupplyMaxClaimsPerHQ) exitWith {};

        [_group,_hq,_needs] call ITW_CLASH_Resupply_fnc_Claim;
    } forEach _groups;
};

ITW_CLASH_Resupply_fnc_StepResolve = {
    params ["_claim"];
    private _group = _claim get "group";
    private _hq = _claim get "hq";
    private _origin = getPosATL vehicle leader _group;
    private _vehicles = [_group] call ITW_CLASH_Resupply_fnc_GroundVehicles;

    // A vehicle out of fuel or immobilized cannot withdraw: resupply comes to it.
    if (_vehicles findIf {fuel _x <= 0 || {!canMove _x}} >= 0) exitWith {
        _claim set ["rally",_origin];
        _claim set ["rallySource","immobile"];
        _claim set ["inPlace",true];
        _claim set ["state","AT_RALLY"];
        _claim set ["arrivedAt",time];
        [format [
            "%1 can't move - holding at %2, resupply comes to it",
            [_group] call ITW_CLASH_Resupply_fnc_Describe,
            mapGridPosition _origin
        ]] call ITW_CLASH_Resupply_fnc_Say;
    };

    private _rally = [_claim,_origin] call ITW_CLASH_Resupply_fnc_FindSharedRally;
    if (_rally isEqualTo [] && {([_origin,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0}) then {
        _rally = [_origin,"already-clear"];
    };
    if (_rally isEqualTo []) then {
        _rally = [_group,_hq,_origin,_vehicles isNotEqualTo []] call ITW_CLASH_Resupply_fnc_ResolveRally;
    };
    if (_rally isEqualTo []) exitWith {
        [_claim get "id","no-clear-rally"] call ITW_CLASH_Resupply_fnc_Release;
    };

    _rally params ["_pos","_source"];
    _claim set ["rally",_pos];
    _claim set ["rallySource",_source];
    _claim set ["lastRallyCheck",time];

    if (_source == "already-clear") exitWith {
        _claim set ["inPlace",true];
        _claim set ["state","AT_RALLY"];
        _claim set ["arrivedAt",time];
        [format [
            "%1 is already clear of threats - holding at %2 for resupply",
            [_group] call ITW_CLASH_Resupply_fnc_Describe,
            mapGridPosition _pos
        ]] call ITW_CLASH_Resupply_fnc_Say;
    };

    [_group,_pos] call ITW_CLASH_Resupply_fnc_OrderMove;
    _claim set ["lastMoveOrder",time];
    _claim set ["state","MOVING"];
    [format [
        "%1 withdrawing %2m to %3 (%4)",
        [_group] call ITW_CLASH_Resupply_fnc_Describe,
        round (_origin distance2D _pos),
        mapGridPosition _pos,
        _source
    ]] call ITW_CLASH_Resupply_fnc_Say;
};

ITW_CLASH_Resupply_fnc_StepMoving = {
    params ["_claim"];
    private _group = _claim get "group";
    private _hq = _claim get "hq";
    private _rally = _claim get "rally";

    if (((vehicle leader _group) distance2D _rally) <= ITW_CLASH_ResupplyArrivalRadius) exitWith {
        _claim set ["state","AT_RALLY"];
        _claim set ["arrivedAt",time];
        [format [
            "%1 reached rally %2",
            [_group] call ITW_CLASH_Resupply_fnc_Describe,
            mapGridPosition _rally
        ]] call ITW_CLASH_Resupply_fnc_Say;
    };

    private _relocate = false;
    if (time - (_claim get "lastRallyCheck") >= 60) then {
        _claim set ["lastRallyCheck",time];
        _relocate = !(([_rally,_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0)
            && {(_claim get "relocations") < 2};
    };
    if (_relocate) exitWith {
        _claim set ["relocations",(_claim get "relocations") + 1];
        _claim set ["state","RESOLVE"];
        [format [
            "%1's rally at %2 went hot - picking a new one",
            [_group] call ITW_CLASH_Resupply_fnc_Describe,
            mapGridPosition _rally
        ]] call ITW_CLASH_Resupply_fnc_Say;
    };

    private _last = _claim get "lastMoveOrder";
    private _wpDone = (currentWaypoint _group) >= (count waypoints _group);
    if ((_wpDone && {time - _last > 15}) || {time - _last > 120}) then {
        [_group,_rally] call ITW_CLASH_Resupply_fnc_OrderMove;
        _claim set ["lastMoveOrder",time];
    };
};

ITW_CLASH_Resupply_fnc_GoToCrate = {
    params ["_claim"];
    private _group = _claim get "group";
    private _immobile = (_claim get "rallySource") == "immobile";
    private _radius = if (_immobile) then {ITW_CLASH_ResupplyServiceRadius * 2} else {300};
    private _crate = [
        getPosATL vehicle leader _group,_radius,side _group,_claim get "needs"
    ] call ITW_CLASH_Resupply_fnc_CrateNear;
    if (isNull _crate) exitWith {false};

    if (
        !_immobile
        && {((vehicle leader _group) distance2D _crate) > (ITW_CLASH_ResupplyServiceRadius * 0.75)}
        && {time - (_claim get "lastMoveOrder") > 20}
    ) then {
        [_group,getPosATL _crate] call ITW_CLASH_Resupply_fnc_OrderMove;
        _claim set ["lastMoveOrder",time];
    };
    true
};

ITW_CLASH_Resupply_fnc_PeerDeliveryPending = {
    params ["_claim"];
    private _rally = _claim get "rally";
    private _needs = _claim get "needs";
    private _pending = false;
    {
        if (_x == (_claim get "id")) then {continue};
        private _other = ITW_CLASH_ResupplyClaims get _x;
        if ((_other get "hq") isNotEqualTo (_claim get "hq")) then {continue};
        if ((_other get "state") != "AWAIT_DELIVERY") then {continue};
        private _pos = _other get "rally";
        if (_pos isEqualTo [] || {(_pos distance2D _rally) > 150}) then {continue};
        private _mode = _other get "deliveryMode";
        if (_mode == "AIR" || {(_mode select [7]) in _needs}) exitWith {_pending = true};
    } forEach (keys ITW_CLASH_ResupplyClaims);
    _pending
};

ITW_CLASH_Resupply_fnc_TargetFor = {
    params ["_group","_hq","_kind"];
    private _vehicles = [_group] call ITW_CLASH_Resupply_fnc_GroundVehicles;
    private _pick = switch (_kind) do {
        case "AMMO": {_vehicles select {!someAmmo _x && {[_x,_hq] call ITW_CLASH_Resupply_fnc_IsArmed}}};
        case "FUEL": {_vehicles select {fuel _x <= ITW_CLASH_ResupplyFuelThreshold}};
        case "REPAIR": {_vehicles select {damage _x >= ITW_CLASH_ResupplyRepairThreshold || {!canMove _x}}};
        default {[]};
    };
    if (_pick isNotEqualTo []) exitWith {_pick#0};
    if (_vehicles isNotEqualTo []) exitWith {_vehicles#0};
    leader _group
};

ITW_CLASH_Resupply_fnc_ProviderVehicle = {
    params ["_providerGroup"];
    if (!isNil "ITW_CLASH_HALLogistics_fnc_ProviderVehicle") exitWith {
        [_providerGroup] call ITW_CLASH_HALLogistics_fnc_ProviderVehicle
    };
    assignedVehicle leader _providerGroup
};

// Air uses HAL's own drop path, exactly like the Thunder Run vehicle bridge,
// so the existing sling/package/Thunder Run routing all still applies.
ITW_CLASH_Resupply_fnc_DispatchAir = {
    params ["_claim"];
    private _group = _claim get "group";
    private _hq = _claim get "hq";
    private _rally = _claim get "rally";
    private _target = [_group,_hq,""] call ITW_CLASH_Resupply_fnc_TargetFor;
    if (isNull _target) exitWith {""};

    private _boxes = (_hq getVariable ["RydHQ_AmmoBoxes",[]]) select {
        !isNull _x && {alive _x} && {isNull (_x getVariable ["ITW_CLASH_PreloadedSlingCarrier",objNull])}
    };
    if (_boxes isEqualTo []) exitWith {""};

    private _best = [];
    private _bestDist = 1e10;
    {
        private _providerGroup = _x;
        if (
            isNull _providerGroup
            || {({alive _x} count units _providerGroup) == 0}
            || {_providerGroup getVariable ["Busy" + str _providerGroup,false]}
            || {_providerGroup getVariable ["Unable",false]}
            || {(units _providerGroup findIf {isPlayer _x}) >= 0}
        ) then {continue};

        private _heli = [_providerGroup] call ITW_CLASH_Resupply_fnc_ProviderVehicle;
        if (
            isNull _heli
            || {!alive _heli}
            || {!canMove _heli}
            || {fuel _heli <= 0.2}
            || {!(_heli isKindOf "Helicopter")}
            || {!isNull getSlingLoad _heli}
            || {_heli getVariable ["ITW_CLASH_ThunderRunActive",false]}
        ) then {continue};

        private _boxIndex = _boxes findIf {_heli canSlingLoad _x};
        if (_boxIndex < 0) then {continue};

        if (!isNil "ITW_CLASH_ThunderRun_fnc_Classify") then {
            private _classification = [_heli,_target,_hq] call ITW_CLASH_ThunderRun_fnc_Classify;
            if ((_classification getOrDefault ["state","NORMAL"]) == "AIR_DENIED") then {continue};
        };

        private _d = _heli distance2D _rally;
        if (_d < _bestDist) then {
            _bestDist = _d;
            _best = [_heli,_boxes#_boxIndex];
        };
    } forEach (_hq getVariable ["RydHQ_AmmoDrop",[]]);
    if (_best isEqualTo []) exitWith {""};

    _best params ["_heli","_box"];
    private _targetGroup = [_target] call ITW_CLASH_Resupply_fnc_TargetGroup;
    private _supported = +(_hq getVariable ["RydHQ_ASupportedG",[]]);
    _supported pushBackUnique _targetGroup;
    _hq setVariable ["RydHQ_ASupportedG",_supported];
    _hq setVariable ["RydHQ_AmmoBoxes",(_hq getVariable ["RydHQ_AmmoBoxes",[]]) - [_box]];

    [[
        _heli,_target,[],[],true,_box,_hq,false,
        ["CLASH_RESUPPLY_AIR",true,true]
    ],HAL_GoAmmoSupp] call RYD_Spawn;

    ["dispatch-air",[_claim get "id",typeOf _heli,typeOf _box,round _bestDist]] call ITW_CLASH_Resupply_fnc_Log;
    [format [
        "Request approved for %1: %2 dropping a crate at %3 (%4m out)",
        [_group] call ITW_CLASH_Resupply_fnc_Describe,
        getText (configOf _heli >> "displayName"),
        mapGridPosition _rally,
        round _bestDist
    ]] call ITW_CLASH_Resupply_fnc_Say;
    "AIR"
};

// Ground providers are ranked by honest road distance. -1 (no road link or
// search budget exhausted) never counts as near; it is a last resort only.
ITW_CLASH_Resupply_fnc_DispatchGround = {
    params ["_claim","_vehNeeds","_lastResort"];
    private _group = _claim get "group";
    private _hq = _claim get "hq";
    private _rally = _claim get "rally";
    private _vehicles = [_group] call ITW_CLASH_Resupply_fnc_GroundVehicles;

    private _priority = [];
    if ("REPAIR" in _vehNeeds && {_vehicles findIf {!canMove _x} >= 0}) then {_priority pushBack "REPAIR"};
    if ("FUEL" in _vehNeeds && {_vehicles findIf {fuel _x <= 0} >= 0}) then {_priority pushBackUnique "FUEL"};
    {_priority pushBackUnique _x} forEach (["AMMO","FUEL","REPAIR"] select {_x in _vehNeeds});

    private _mode = "";
    {
        private _kind = _x;
        private _pool = switch (_kind) do {
            case "AMMO": {(_hq getVariable ["RydHQ_AmmoSupportG",[]]) - (_hq getVariable ["RydHQ_AmmoDrop",[]])};
            case "FUEL": {+(_hq getVariable ["RydHQ_FuelSupportG",[]])};
            case "REPAIR": {+(_hq getVariable ["RydHQ_RepSupportG",[]])};
            default {[]};
        };
        if (!isNil "ITW_CLASH_HALLogistics_fnc_UsableGroups") then {
            _pool = [_pool] call ITW_CLASH_HALLogistics_fnc_UsableGroups;
        };

        private _truck = objNull;
        private _bestCost = 1e10;
        {
            private _providerGroup = _x;
            if ((units _providerGroup findIf {isPlayer _x}) >= 0) then {continue};
            private _candidate = [_providerGroup] call ITW_CLASH_Resupply_fnc_ProviderVehicle;
            if (isNull _candidate || {!(_candidate isKindOf "LandVehicle")}) then {continue};

            private _cost = -1;
            if (!isNil "ITW_CLASH_RoadDistance_fnc_Calculate") then {
                _cost = [getPosATL _candidate,_rally] call ITW_CLASH_RoadDistance_fnc_Calculate;
            };
            if (_cost < 0 || {_cost > ITW_CLASH_ResupplyGroundMaxRoad}) then {
                if (!_lastResort) then {continue};
                _cost = 1e6 + (_candidate distance2D _rally);
            };
            if (_cost < _bestCost) then {_bestCost = _cost; _truck = _candidate};
        } forEach _pool;
        if (isNull _truck) then {continue};

        private _target = [_group,_hq,_kind] call ITW_CLASH_Resupply_fnc_TargetFor;
        private _supportedKey = switch (_kind) do {
            case "AMMO": {"RydHQ_ASupportedG"};
            case "FUEL": {"RydHQ_FSupportedG"};
            default {"RydHQ_RSupportedG"};
        };
        private _supported = +(_hq getVariable [_supportedKey,[]]);
        _supported pushBackUnique _group;
        _hq setVariable [_supportedKey,_supported];

        switch (_kind) do {
            case "AMMO": {
                [[
                    _truck,_target,[],[],false,objNull,_hq,false,
                    ["CLASH_RESUPPLY_GROUND",false,true]
                ],HAL_GoAmmoSupp] call RYD_Spawn;
            };
            case "FUEL": {
                [[_truck,_target,+(_hq getVariable ["RydHQ_Dried",[]]),_hq],HAL_GoFuelSupp] call RYD_Spawn;
            };
            case "REPAIR": {
                [[_truck,_target,+(_hq getVariable ["RydHQ_damaged",[]]),_hq],HAL_GoRepSupp] call RYD_Spawn;
            };
        };

        _mode = "GROUND:" + _kind;
        ["dispatch-ground",[_claim get "id",_kind,typeOf _truck,round _bestCost,_lastResort]] call ITW_CLASH_Resupply_fnc_Log;
        [format [
            "Request approved for %1: %2 truck %3 driving to %4%5",
            [_group] call ITW_CLASH_Resupply_fnc_Describe,
            toLowerANSI _kind,
            getText (configOf _truck >> "displayName"),
            mapGridPosition _rally,
            if (_bestCost >= 1e6) then {" (no road route found - straight-line fallback)"} else {format [" (%1m by road)",round _bestCost]}
        ]] call ITW_CLASH_Resupply_fnc_Say;
        if (true) exitWith {};
    } forEach _priority;
    _mode
};

ITW_CLASH_Resupply_fnc_Dispatch = {
    params ["_claim"];
    private _needs = _claim get "needs";
    private _hq = _claim get "hq";
    private _hasInfantry = "AMMO_INF" in _needs;
    private _vehNeeds = _needs - ["AMMO_INF"];
    private _airUseful = [_needs] call ITW_CLASH_Resupply_fnc_CrateCovers;
    private _rallyClear = ([_claim get "rally",_hq] call ITW_CLASH_Resupply_fnc_Clearance)#0;
    private _preferAir = _hasInfantry || {count _vehNeeds >= 2} || {!_rallyClear};

    private _mode = "";
    {
        if (_x == "AIR" && {_airUseful}) then {
            _mode = [_claim] call ITW_CLASH_Resupply_fnc_DispatchAir;
        };
        if (_x == "GROUND" && {_vehNeeds isNotEqualTo []}) then {
            _mode = [_claim,_vehNeeds,false] call ITW_CLASH_Resupply_fnc_DispatchGround;
        };
        if (_mode != "") exitWith {};
    } forEach (if (_preferAir) then {["AIR","GROUND"]} else {["GROUND","AIR"]});

    if (_mode == "" && {_vehNeeds isNotEqualTo []}) then {
        _mode = [_claim,_vehNeeds,true] call ITW_CLASH_Resupply_fnc_DispatchGround;
    };
    _mode
};

// Checkbook is for capability that is missing, not capability that is busy.
ITW_CLASH_Resupply_fnc_RequestCapacity = {
    params ["_claim"];
    if (isNil "ITW_CLASH_HALLogistics_fnc_Request") exitWith {false};
    private _hq = _claim get "hq";
    private _needs = _claim get "needs";
    private _alive = {
        params ["_groups"];
        _groups select {!isNull _x && {({alive _x} count units _x) > 0}}
    };

    private _asks = [];
    if (([_needs] call ITW_CLASH_Resupply_fnc_CrateCovers) && {"AMMO_INF" in _needs || {count (_needs - ["AMMO_INF"]) >= 2}}) then {
        if (([_hq getVariable ["RydHQ_AmmoDrop",[]]] call _alive) isEqualTo []) then {
            _asks pushBack ["LOGISTICS_AMMO","AIR"];
        };
        if (((_hq getVariable ["RydHQ_AmmoBoxes",[]]) select {!isNull _x && {alive _x}}) isEqualTo []) then {
            _asks pushBack ["LOGISTICS_PACKAGE_AMMO","AIR"];
        };
    };
    {
        private _poolKey = switch (_x) do {
            case "AMMO": {"RydHQ_AmmoSupportG"};
            case "FUEL": {"RydHQ_FuelSupportG"};
            default {"RydHQ_RepSupportG"};
        };
        if (([_hq getVariable [_poolKey,[]]] call _alive) isEqualTo []) then {
            _asks pushBack ["LOGISTICS_" + _x,"GROUND"];
        };
    } forEach ((_needs - ["AMMO_INF"]) select {_x in ["AMMO","FUEL","REPAIR"]});

    {
        _x params ["_capability","_mode"];
        private _key = "ITW_CLASH_ResupplyBuyAt_" + _capability + "_" + _mode;
        if (time < (_hq getVariable [_key,0])) then {continue};
        _hq setVariable [_key,time + ITW_CLASH_ResupplyBuyCooldown];
        [_hq,_capability,_mode] call ITW_CLASH_HALLogistics_fnc_Request;
        [format [
            "%1 needs %2 but HAL has no %3 %4 at all - asking Checkbook",
            [_claim get "group"] call ITW_CLASH_Resupply_fnc_Describe,
            _needs joinString "+",
            toLowerANSI _mode,
            _capability
        ]] call ITW_CLASH_Resupply_fnc_Say;
    } forEach _asks;
    _asks isNotEqualTo []
};

ITW_CLASH_Resupply_fnc_StepAtRally = {
    params ["_claim"];
    if ([_claim] call ITW_CLASH_Resupply_fnc_GoToCrate) exitWith {};
    if ([_claim get "group"] call ITW_CLASH_Resupply_fnc_InFlight) exitWith {};
    if (time - (_claim get "arrivedAt") < ITW_CLASH_ResupplyNativeGrace) exitWith {};
    if ([_claim] call ITW_CLASH_Resupply_fnc_PeerDeliveryPending) exitWith {};
    if (([_claim get "hq",["AWAIT_DELIVERY"]] call ITW_CLASH_Resupply_fnc_CountClaims) >= ITW_CLASH_ResupplyMaxDeliveriesPerHQ) exitWith {};
    if (time - (_claim get "lastDispatchTry") < 20) exitWith {};
    _claim set ["lastDispatchTry",time];

    private _mode = [_claim] call ITW_CLASH_Resupply_fnc_Dispatch;
    if (_mode == "") exitWith {
        [_claim] call ITW_CLASH_Resupply_fnc_RequestCapacity;
    };
    _claim set ["deliveryMode",_mode];
    _claim set ["deliveryAt",time];
    _claim set ["state","AWAIT_DELIVERY"];
};

ITW_CLASH_Resupply_fnc_StepAwait = {
    params ["_claim"];
    if ([_claim] call ITW_CLASH_Resupply_fnc_GoToCrate) exitWith {};
    if ([_claim get "group"] call ITW_CLASH_Resupply_fnc_InFlight) exitWith {};
    if (time - (_claim get "deliveryAt") < 60) exitWith {};

    // The delivery script has finished (or never started) and the group is
    // still in need: retry a bounded number of times, then give it back.
    private _retries = (_claim get "retries") + 1;
    _claim set ["retries",_retries];
    if (_retries > ITW_CLASH_ResupplyMaxRetries) exitWith {
        [_claim get "id","delivery-failed"] call ITW_CLASH_Resupply_fnc_Release;
    };
    _claim set ["state","AT_RALLY"];
    _claim set ["arrivedAt",time - ITW_CLASH_ResupplyNativeGrace];
    [format [
        "%1's %2 delivery ended but it still needs %3 - retry %4",
        [_claim get "group"] call ITW_CLASH_Resupply_fnc_Describe,
        _claim get "deliveryMode",
        (_claim get "needs") joinString "+",
        _retries
    ]] call ITW_CLASH_Resupply_fnc_Say;
};

ITW_CLASH_Resupply_fnc_TickClaims = {
    {
        private _id = _x;
        private _claim = ITW_CLASH_ResupplyClaims getOrDefault [_id,createHashMap];
        if (count _claim == 0) then {continue};
        private _group = _claim get "group";
        private _state = _claim get "state";

        if (isNull _group || {({alive _x} count units _group) == 0}) then {
            [_id,"group-lost"] call ITW_CLASH_Resupply_fnc_Release;
            continue
        };
        if (_state == "ABORT") then {
            [_id,_claim getOrDefault ["abortReason","aborted"]] call ITW_CLASH_Resupply_fnc_Release;
            continue
        };
        if (time - (_claim get "claimedAt") > ITW_CLASH_ResupplyClaimTimeout) then {
            [_id,"timeout"] call ITW_CLASH_Resupply_fnc_Release;
            continue
        };
        if (_state == "BREAKING") then {continue};
        if ((units _group findIf {isPlayer _x}) >= 0) then {
            [_id,"player-took-command"] call ITW_CLASH_Resupply_fnc_Release;
            continue
        };

        private _needs = [_group,_claim get "hq"] call ITW_CLASH_Resupply_fnc_Needs;
        if (_needs isEqualTo []) then {
            [_id,"serviced"] call ITW_CLASH_Resupply_fnc_Release;
            continue
        };
        _claim set ["needs",_needs];

        private _var = str _group;
        if ((_claim get "busyOwned") && {!(_group getVariable ["Busy" + _var,false])}) then {
            _group setVariable ["Busy" + _var,true];
            _claim set ["lastMoveOrder",-1];
            ["busy-reasserted",[_id,_state]] call ITW_CLASH_Resupply_fnc_Log;
        };

        switch (_state) do {
            case "RESOLVE": {[_claim] call ITW_CLASH_Resupply_fnc_StepResolve};
            case "MOVING": {[_claim] call ITW_CLASH_Resupply_fnc_StepMoving};
            case "AT_RALLY": {[_claim] call ITW_CLASH_Resupply_fnc_StepAtRally};
            case "AWAIT_DELIVERY": {[_claim] call ITW_CLASH_Resupply_fnc_StepAwait};
        };
    } forEach +(keys ITW_CLASH_ResupplyClaims);
};

ITW_CLASH_Resupply_fnc_RegisterCrate = {
    params ["_crate","_side"];
    if (isNull _crate || {!alive _crate}) exitWith {false};
    private _key = [_crate] call ITW_CLASH_Resupply_fnc_CrateKey;
    if (_key in ITW_CLASH_ResupplyCrates) exitWith {false};
    if (
        isObjectHidden _crate
        || {((getPosATL _crate)#2) > 3}
        || {!isNull (attachedTo _crate)}
        || {!isNull (ropeAttachedTo _crate)}
        || {(_crate getVariable ["ITW_CLASH_LogisticsPackageState",""]) in ["AVAILABLE_AT_REAR","RESERVED","IN_TRANSIT"]}
        || {(call ITW_CLASH_Resupply_fnc_HQs) findIf {_crate in (_x getVariable ["RydHQ_AmmoBoxes",[]])} >= 0}
    ) exitWith {false};

    ITW_CLASH_ResupplyCrates set [_key,[_crate,ITW_CLASH_ResupplyCrateUses,time,time,_side]];
    _crate setVariable ["ITW_CLASH_ResupplyCrateUses",ITW_CLASH_ResupplyCrateUses,true];
    ["crate-registered",[_key,typeOf _crate,getPosATL _crate,_side]] call ITW_CLASH_Resupply_fnc_Log;
    true
};

// isBoxed must be cleared before deletion: HAL reads getPosATL of the stored
// crate, and a deleted crate would send the group toward the map origin.
ITW_CLASH_Resupply_fnc_DeleteCrate = {
    params ["_key","_reason"];
    private _entry = ITW_CLASH_ResupplyCrates getOrDefault [_key,[]];
    ITW_CLASH_ResupplyCrates deleteAt _key;
    if (_entry isEqualTo []) exitWith {false};
    private _crate = _entry#0;
    if (isNull _crate) exitWith {false};

    private _boxedGroups = allGroups select {(_x getVariable ["isBoxed",objNull]) isEqualTo _crate};
    {_x setVariable ["isBoxed",nil]} forEach _boxedGroups;
    {
        private _hq = _x;
        _hq setVariable ["RydHQ_OrdnanceDrops",(_hq getVariable ["RydHQ_OrdnanceDrops",[]]) - [_crate]];
        _hq setVariable ["RydHQ_AmmoBoxes",(_hq getVariable ["RydHQ_AmmoBoxes",[]]) - [_crate]];
        _hq setVariable ["RydHQ_Boxed",(_hq getVariable ["RydHQ_Boxed",[]]) - _boxedGroups];
    } forEach (call ITW_CLASH_Resupply_fnc_HQs);

    [format ["crate at %1 removed (%2)",mapGridPosition _crate,_reason]] call ITW_CLASH_Resupply_fnc_Say;
    deleteVehicle _crate;
    true
};

ITW_CLASH_Resupply_fnc_RefillMan = {
    params ["_unit"];
    {
        _x params ["_weapon","_loaded","_target"];
        if (_weapon isEqualTo "") then {continue};
        private _mag = if (_loaded isNotEqualTo []) then {_loaded#0} else {
            ([_weapon] call ITW_CLASH_Resupply_fnc_WeaponMags) param [0,""]
        };
        if (_mag isEqualTo "") then {continue};
        private _add = (_target - ([_unit,_weapon] call ITW_CLASH_Resupply_fnc_CountMags)) max 0;
        if (_add > 0) then {[_unit,[_mag,_add]] remoteExec ["addMagazines",_unit]};
    } forEach [
        [primaryWeapon _unit,primaryWeaponMagazine _unit,ITW_CLASH_ResupplyPrimaryMags],
        [handgunWeapon _unit,handgunMagazine _unit,ITW_CLASH_ResupplyHandgunMags]
    ];
};

// Same ACE-magic service HAL applies when a support truck arrives, gated on
// the same RydxHQ_Magic* flags. One use = one group, fully topped up.
ITW_CLASH_Resupply_fnc_ApplyService = {
    params ["_group","_crate","_usesLeft"];
    private _range = ITW_CLASH_ResupplyServiceRadius * 2;
    private _rearm = missionNamespace getVariable ["RydxHQ_MagicRearm",false];
    private _refuel = missionNamespace getVariable ["RydxHQ_MagicRefuel",false];
    private _repair = missionNamespace getVariable ["RydxHQ_MagicRepair",false];

    {
        if ((_x distance2D _crate) > _range) then {continue};
        if (_rearm) then {[_x,1] remoteExec ["setVehicleAmmo",_x]};
        if (_refuel) then {[_x,1] remoteExec ["setFuel",_x]};
        if (_repair) then {_x setDamage 0};
    } forEach ([_group] call ITW_CLASH_Resupply_fnc_GroundVehicles);

    if (_rearm) then {
        {
            if (vehicle _x == _x && {(_x distance2D _crate) <= _range}) then {
                [_x] call ITW_CLASH_Resupply_fnc_RefillMan;
            };
        } forEach ((units _group) select {alive _x});
    };

    {
        if (isPlayer _x) then {
            (format ["Resupplied from crate (%1 uses left)",_usesLeft]) remoteExec ["hint",_x];
        };
    } forEach units _group;
};

ITW_CLASH_Resupply_fnc_ServiceAtCrate = {
    params ["_key"];
    private _entry = ITW_CLASH_ResupplyCrates get _key;
    _entry params ["_crate","_uses","","","_side"];
    private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;

    private _groups = [];
    {
        private _g = [_x] call ITW_CLASH_Resupply_fnc_TargetGroup;
        if (!isNull _g && {((side _g) getFriend _side) >= 0.6}) then {_groups pushBackUnique _g};
    } forEach (_crate nearEntities [["Man","LandVehicle"],ITW_CLASH_ResupplyServiceRadius]);

    private _served = false;
    {
        if (_uses <= 0) exitWith {};
        private _g = _x;
        if (time < ((_g getVariable ["ITW_CLASH_ResupplyServedAt",-1e6]) + 30)) then {continue};
        private _needs = ([_g,_hq] call ITW_CLASH_Resupply_fnc_Needs) select {[_x] call ITW_CLASH_Resupply_fnc_MagicFor};
        if (_needs isEqualTo []) then {continue};

        _uses = _uses - 1;
        [_g,_crate,_uses] call ITW_CLASH_Resupply_fnc_ApplyService;
        _g setVariable ["ITW_CLASH_ResupplyServedAt",time];
        _served = true;
        ["crate-service",[_key,[_g] call ITW_CLASH_Resupply_fnc_Id,_needs,_uses]] call ITW_CLASH_Resupply_fnc_Log;
        [format [
            "%1 resupplied (%2) from crate at %3 - %4 uses left",
            [_g] call ITW_CLASH_Resupply_fnc_Describe,
            _needs joinString "+",
            mapGridPosition _crate,
            _uses
        ]] call ITW_CLASH_Resupply_fnc_Say;
    } forEach _groups;

    if (_served) then {
        _entry set [1,_uses];
        _entry set [3,time];
        _crate setVariable ["ITW_CLASH_ResupplyCrateUses",_uses,true];
    };
    if (_uses <= 0) then {[_key,"used up"] call ITW_CLASH_Resupply_fnc_DeleteCrate};
};

ITW_CLASH_Resupply_fnc_TickCrates = {
    {
        private _hq = _x;
        {[_x,side _hq] call ITW_CLASH_Resupply_fnc_RegisterCrate} forEach (_hq getVariable ["RydHQ_OrdnanceDrops",[]]);
    } forEach (call ITW_CLASH_Resupply_fnc_HQs);
    {
        private _claim = ITW_CLASH_ResupplyClaims get _x;
        private _g = _claim get "group";
        if (!isNull _g) then {
            private _boxed = _g getVariable ["isBoxed",objNull];
            if (!isNull _boxed) then {[_boxed,side _g] call ITW_CLASH_Resupply_fnc_RegisterCrate};
        };
    } forEach (keys ITW_CLASH_ResupplyClaims);

    private _anyMagic = ["AMMO","FUEL","REPAIR"] findIf {[_x] call ITW_CLASH_Resupply_fnc_MagicFor} >= 0;
    {
        private _key = _x;
        (ITW_CLASH_ResupplyCrates get _key) params ["_crate","_uses","","_lastUsed"];
        if (isNull _crate || {!alive _crate}) then {
            ITW_CLASH_ResupplyCrates deleteAt _key;
            continue
        };
        if (_uses <= 0) then {
            [_key,"used up"] call ITW_CLASH_Resupply_fnc_DeleteCrate;
            continue
        };
        if (ITW_CLASH_ResupplyCrateIdleLife > 0 && {time - _lastUsed > ITW_CLASH_ResupplyCrateIdleLife}) then {
            [_key,"unused too long"] call ITW_CLASH_Resupply_fnc_DeleteCrate;
            continue
        };
        if (_anyMagic) then {[_key] call ITW_CLASH_Resupply_fnc_ServiceAtCrate};
    } forEach +(keys ITW_CLASH_ResupplyCrates);
};

// Stamp the target group while a native delivery script is actually running,
// so "nothing inbound" is judged by real execution, not HAL's bookkeeping.
[] spawn {
    scriptName "ITW_CLASH_ResupplyNativeStamps";
    private _deadline = diag_tickTime + 600;
    waitUntil {
        sleep 1;
        diag_tickTime >= _deadline || {
            !isNil "HAL_GoAmmoSupp"
            && {!isNil "HAL_GoFuelSupp"}
            && {!isNil "HAL_GoRepSupp"}
        }
    };
    if (diag_tickTime >= _deadline) exitWith {
        ["stamp-bind-timeout",[]] call ITW_CLASH_Resupply_fnc_Log;
    };

    // Bind outermost, after the PlayerDemand interceptor has wrapped
    // HAL_GoAmmoSupp, so the two binders never race on the same global.
    private _interceptorDeadline = diag_tickTime + 180;
    waitUntil {
        sleep 1;
        diag_tickTime >= _interceptorDeadline
        || {missionNamespace getVariable ["ITW_CLASH_PlayerDemandNativeInterceptorsReady",false]}
    };

    ITW_CLASH_Resupply_fnc_GoAmmoSuppBase = HAL_GoAmmoSupp;
    HAL_GoAmmoSupp = {
        private _group = [_this param [1,objNull]] call ITW_CLASH_Resupply_fnc_TargetGroup;
        [_group,1] call ITW_CLASH_Resupply_fnc_Stamp;
        private _result = _this call ITW_CLASH_Resupply_fnc_GoAmmoSuppBase;
        [_group,-1] call ITW_CLASH_Resupply_fnc_Stamp;
        if (isNil "_result") exitWith {};
        _result
    };

    ITW_CLASH_Resupply_fnc_GoFuelSuppBase = HAL_GoFuelSupp;
    HAL_GoFuelSupp = {
        private _group = [_this param [1,objNull]] call ITW_CLASH_Resupply_fnc_TargetGroup;
        [_group,1] call ITW_CLASH_Resupply_fnc_Stamp;
        private _result = _this call ITW_CLASH_Resupply_fnc_GoFuelSuppBase;
        [_group,-1] call ITW_CLASH_Resupply_fnc_Stamp;
        if (isNil "_result") exitWith {};
        _result
    };

    ITW_CLASH_Resupply_fnc_GoRepSuppBase = HAL_GoRepSupp;
    HAL_GoRepSupp = {
        private _group = [_this param [1,objNull]] call ITW_CLASH_Resupply_fnc_TargetGroup;
        [_group,1] call ITW_CLASH_Resupply_fnc_Stamp;
        private _result = _this call ITW_CLASH_Resupply_fnc_GoRepSuppBase;
        [_group,-1] call ITW_CLASH_Resupply_fnc_Stamp;
        if (isNil "_result") exitWith {};
        _result
    };

    ITW_CLASH_ResupplyStampsReady = true;
};

[] spawn {
    scriptName "ITW_CLASH_Resupply";
    waitUntil {
        sleep 1;
        missionNamespace getVariable ["ITW_CLASH_HALLogisticsReady",false]
        && {missionNamespace getVariable ["ITW_CLASH_ResupplyStampsReady",false]}
        && {!isNil "ITW_CLASH_fnc_GetCommanderForSide"}
        && {!isNil "RYD_CloseEnemyB"}
        && {!isNil "RYD_Spawn"}
        && {!isNil "RYD_WPdel"}
    };

    ITW_CLASH_ResupplyReady = true;
    diag_log format [
        "CLASH BOOT | resupply-ready | version=%1 patience=%2 nativeGrace=%3 maxClaims=%4 maxDeliveries=%5 crateUses=%6 crateIdleLife=%7 magic=%8/%9/%10",
        ITW_CLASH_ResupplyVersion,
        ITW_CLASH_ResupplyPatience,
        ITW_CLASH_ResupplyNativeGrace,
        ITW_CLASH_ResupplyMaxClaimsPerHQ,
        ITW_CLASH_ResupplyMaxDeliveriesPerHQ,
        ITW_CLASH_ResupplyCrateUses,
        ITW_CLASH_ResupplyCrateIdleLife,
        missionNamespace getVariable ["RydxHQ_MagicRearm",false],
        missionNamespace getVariable ["RydxHQ_MagicRefuel",false],
        missionNamespace getVariable ["RydxHQ_MagicRepair",false]
    ];

    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        {[_x] call ITW_CLASH_Resupply_fnc_Detect} forEach (call ITW_CLASH_Resupply_fnc_HQs);
        call ITW_CLASH_Resupply_fnc_TickClaims;
        call ITW_CLASH_Resupply_fnc_TickCrates;
        sleep ITW_CLASH_ResupplyTick;
    };
};

true
