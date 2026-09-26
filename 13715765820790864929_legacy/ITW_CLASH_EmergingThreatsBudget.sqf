#include "defines.hpp"

if (!isServer) exitWith {false};
if (missionNamespace getVariable ["ITW_CLASH_ETBStarted",false]) exitWith {true};

ITW_CLASH_ETBStarted = true;
ITW_CLASH_ETBVersion = 1;
ITW_CLASH_ETBReady = false;

/*
    The Emerging Threats Budget.

    CLASH's checkbook shares Impasse's per-row tickets with Impasse's own
    vehicle spawner, and the spawner always goes first and spends every
    affordable ticket (ITW_Attack.sqf: spawn at 1210, sleep, add tickets at
    1348-1384, straight back to spawn). A row becomes affordable and is emptied
    moments later, while HAL only evaluates threats every 45-90 seconds - so in
    the 81-minute peer run of 2026-09-25, 4 of 117 threat purchases went
    through and HAL's decisions did not change what got built.

    The ETB is a second, separate wallet per commander, on top of Impasse and
    never inside it. Impasse's economy is untouched: no ticket is taken,
    reserved, borrowed or edited here, and ETB vehicles never carry ITW_VehDef,
    so they never count against Impasse's caps.

    This file owns money and nothing else: balances, income, prices, reserve,
    row and safety limits, reservations, escrow, the living-asset registry,
    write-offs, authorization and its log. It never decides that a commander
    should own something (HAL creates the demand, through ThreatCoverage), never
    chooses a class or a spawn point (Force Generation), and never employs
    anything (HAL).

    The ceiling is what keeps it a strategic reserve rather than a money
    printer: cash plus the purchase value of every living ETB asset must stay
    under the capacity, and income stops while the reserve is full. A loss frees
    room without refunding money, so survival is rewarded and kills stick.

    ITW_VehDef readers, audited so an ETB asset is not quietly skipped:
      - ITW_CLASH_LogisticsGuard.sqf:280 is the only positive identity test. It
        prunes the RTB/overshoot waypoint pair Impasse gives a completed land
        transport, so skipping a vehicle without a def is right and an ETB
        combat asset must stay out of it: HAL owns its waypoints.
      - ServiceAuthority:133, ServiceLifecycle:149 and :185, ServiceStability:72
        all store or fall back on an empty def and keep working without one.
      - VehicleEchelonPolicy:32 reads the def's type first and falls back to the
        vehicle's own class and editor subcategory, so an ETB tank still
        classifies as armored.
      - DualHALCheckbook:863 and :925 are Impasse's own field-handoff and
        migration paths, reached only by vehicles Impasse spawned.
    ITW_CLASH_Generation_fnc_RegisterAsset stamps ITW_VehDef
    (ITW_CLASH_ForceGeneration.sqf:368), so the ETB needs its own registration
    path rather than that one.

    Nothing here is written to profileNamespace: Impasse saves to the profile
    but field vehicles do not persist (ITW_Save.sqf:161-205), so a saved balance
    could refill or wipe a reserve whose assets no longer exist. The decided
    rule is to reset to the starting reserve on load, which is what an
    unsaved ledger does by construction.
*/

ITW_CLASH_ETBEnabled = missionNamespace getVariable ["ITW_CLASH_ETBEnabled",true];
// Ships the ledger, the economy and every decision, but stops short of
// spawning: each authorization logs what it would have bought. Phase 3 of the
// build order runs in this mode until an RPT says the numbers are right.
ITW_CLASH_ETBDryRun = missionNamespace getVariable ["ITW_CLASH_ETBDryRun",false];
ITW_CLASH_ETBIncomeScale = missionNamespace getVariable ["ITW_CLASH_ETBIncomeScale",1];
ITW_CLASH_ETBStartingReserve = missionNamespace getVariable ["ITW_CLASH_ETBStartingReserve",40];
ITW_CLASH_ETBCapacity = missionNamespace getVariable ["ITW_CLASH_ETBCapacity",80];
ITW_CLASH_ETBRowLimitScale = missionNamespace getVariable ["ITW_CLASH_ETBRowLimitScale",1];
// Only for odd modded factions with a cheap, high-cap combat row. Logged
// whenever it bites, because it means the row limits did not do their job.
ITW_CLASH_ETBSafetyLimit = missionNamespace getVariable ["ITW_CLASH_ETBSafetyLimit",6];
ITW_CLASH_ETBGroundInterval = missionNamespace getVariable ["ITW_CLASH_ETBGroundInterval",90];
ITW_CLASH_ETBAccrualInterval = missionNamespace getVariable ["ITW_CLASH_ETBAccrualInterval",5];
ITW_CLASH_ETBAuditInterval = missionNamespace getVariable ["ITW_CLASH_ETBAuditInterval",15];
// An asset HAL will not employ releases its reserve room, with no cash back. It
// still counts against row and safety limits and is still re-offered first.
ITW_CLASH_ETBIdleRelease = missionNamespace getVariable ["ITW_CLASH_ETBIdleRelease",480];
// Write-offs. A crewless, stuck or abandoned vehicle stays "alive" forever
// otherwise, holding reserve room: Impasse only cleans these up when its own
// cleanup setting is on and no player is near (ITW_Attack.sqf:3958-3980).
ITW_CLASH_ETBCrewWriteOff = missionNamespace getVariable ["ITW_CLASH_ETBCrewWriteOff",300];
ITW_CLASH_ETBImmobileWriteOff = missionNamespace getVariable ["ITW_CLASH_ETBImmobileWriteOff",600];
ITW_CLASH_ETBImmobileTolerance = missionNamespace getVariable ["ITW_CLASH_ETBImmobileTolerance",15];
ITW_CLASH_ETBReservationTimeout = missionNamespace getVariable ["ITW_CLASH_ETBReservationTimeout",120];

// The only two needs the ETB answers. Everything else - infantry, cars,
// statics, artillery, cargo - stays the baseline army's job.
ITW_CLASH_ETBNeeds = ["ANTI_ARMOR","COUNTER_AIR"];
// Canonical capability names, one per provider.
ITW_CLASH_ETBCapabilities = ["GROUND_ANTI_ARMOR","ANTI_ARMOR_CAS","CAP_AIRCRAFT","SPAA"];
/*
    Every reason a request can come back with. One vocabulary, so a run can be
    read end to end from the RPT: the ETB owns the money reasons and Force
    Generation and ThreatCoverage own the rest.
*/
ITW_CLASH_ETBDenialReasons = [
    "NO_CANDIDATE","PROGRESSION_LOCKED","AIRPORT_REQUIRED","COST_EXCEEDS_CAPACITY",
    "INSUFFICIENT_ETB","ETB_ROW_CAP","ETB_RESERVE_CAP","SAFETY_LIMIT","PACING",
    "ACTIVE_RESPONDER","IDLE_RESPONDER_REOFFERED","THREAT_GONE","SPAWN_FAILED",
    "HAL_REGISTRATION_FAILED"
];

ITW_CLASH_ETBLedgers = createHashMap;
ITW_CLASH_ETBSerial = 0;

ITW_CLASH_ETB_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isNil "ITW_CLASH_DualHAL_fnc_Log") then {
        ["etb-" + _event,_payload] call ITW_CLASH_DualHAL_fnc_Log;
    } else {
        diag_log format ["CLASH ETB EVENT | %1 | %2",_event,_payload];
    };
};

ITW_CLASH_ETB_fnc_SideKey = {
    params ["_side"];
    toUpperANSI str _side
};

ITW_CLASH_ETB_fnc_CodeSign = {
    params ["_side"];
    if (isNil "ITW_CLASH_fnc_GetCommanderForSide") exitWith {str _side};
    private _hq = [_side] call ITW_CLASH_fnc_GetCommanderForSide;
    if (isNull _hq) exitWith {str _side};
    _hq getVariable ["RydHQ_CodeSign",str _side]
};

ITW_CLASH_ETB_fnc_Ledger = {
    params ["_side"];
    private _key = [_side] call ITW_CLASH_ETB_fnc_SideKey;
    private _ledger = ITW_CLASH_ETBLedgers getOrDefault [_key,createHashMap];
    if (count _ledger == 0) then {
        _ledger = createHashMapFromArray [
            ["side",_side],
            ["cash",ITW_CLASH_ETBStartingReserve],
            ["accruedAt",time],
            ["assets",[]],
            ["reservations",createHashMap],
            ["bypassed",createHashMap],
            ["escrow",""],
            ["pacedUntil",0],
            ["statusAt",0]
        ];
        ITW_CLASH_ETBLedgers set [_key,_ledger];
        ["ledger-opened",[
            [_side] call ITW_CLASH_ETB_fnc_CodeSign,
            ITW_CLASH_ETBStartingReserve,ITW_CLASH_ETBCapacity
        ]] call ITW_CLASH_ETB_fnc_Log;
    };
    _ledger
};

// A load starts over at the starting reserve: the ledger is never persisted,
// and the assets a saved balance would have been earned against are gone.
ITW_CLASH_ETB_fnc_Reset = {
    params [["_reason","load"]];
    ITW_CLASH_ETBLedgers = createHashMap;
    ["ledger-reset",[_reason,ITW_CLASH_ETBStartingReserve]] call ITW_CLASH_ETB_fnc_Log;
    true
};

/*
    Income: Impasse's neutral base rate, times the ETB income scale. It
    deliberately ignores Impasse's side adjustment (0.7), the side-ops bonus,
    territory scaling, the defend-phase boost and the zone-start bonus - those
    are Impasse's macro balance, and the ETB is an equal commander reserve. Both
    commanders earn it at the same rate by default.
*/
ITW_CLASH_ETB_fnc_IncomeRate = {
    private _adjustment = missionNamespace getVariable ["ITW_ParamVehicleSpawnAdjustment",1];
    private _aiCount = missionNamespace getVariable ["ITW_ParamEnemyAiCnt",30];
    TICKETS_PER_MIN * _adjustment * ((_aiCount + 70) / 100) * ITW_CLASH_ETBIncomeScale
};

// Purchase value of every living asset that still holds reserve room. A living
// asset keeps its full purchase value until it is lost - or until HAL has left
// it idle long enough to release the room.
ITW_CLASH_ETB_fnc_LivingValue = {
    params ["_side"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _value = 0;
    {
        if (_x get "holdsReserve") then {_value = _value + (_x get "cost")};
    } forEach (_ledger get "assets");
    // Money already committed to a purchase in flight is spent, not free.
    {
        _value = _value + (_y get "cost");
    } forEach (_ledger get "reservations");
    _value
};

ITW_CLASH_ETB_fnc_Cash = {
    params ["_side"];
    ([_side] call ITW_CLASH_ETB_fnc_Ledger) get "cash"
};

ITW_CLASH_ETB_fnc_Reserve = {
    params ["_side"];
    ([_side] call ITW_CLASH_ETB_fnc_Cash) + ([_side] call ITW_CLASH_ETB_fnc_LivingValue)
};

// Income stops while the reserve is full: unspent money plus living value is
// capped, so the ETB can never accumulate an army's worth of cash.
ITW_CLASH_ETB_fnc_Accrue = {
    params ["_side"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _elapsed = time - (_ledger get "accruedAt");
    if (_elapsed <= 0) exitWith {false};
    _ledger set ["accruedAt",time];

    private _headroom = ITW_CLASH_ETBCapacity - ([_side] call ITW_CLASH_ETB_fnc_Reserve);
    if (_headroom <= 0) exitWith {false};
    private _income = (call ITW_CLASH_ETB_fnc_IncomeRate) * (_elapsed / 60);
    _ledger set ["cash",(_ledger get "cash") + (_income min _headroom)];
    true
};

// Impasse's own attack spawn setting for this vehicle type. Dual rows use the
// attack settings, as Impasse does; the ETB only ever buys attack and dual rows.
ITW_CLASH_ETB_fnc_TypeSpawnAdjustment = {
    params ["_type"];
    switch (_type) do {
        case ITW_TYPE_VEH_AIRPLANE: {missionNamespace getVariable ["ITW_ParamAttackPlaneSpawnAdjustment",1]};
        case ITW_TYPE_VEH_HELI: {missionNamespace getVariable ["ITW_ParamAttackHeliSpawnAdjustment",1]};
        case ITW_TYPE_VEH_TANK: {missionNamespace getVariable ["ITW_ParamAttackTankSpawnAdjustment",1]};
        case ITW_TYPE_VEH_APC: {missionNamespace getVariable ["ITW_ParamAttackApcSpawnAdjustment",1]};
        case ITW_TYPE_VEH_CAR: {missionNamespace getVariable ["ITW_ParamAttackCarSpawnAdjustment",1]};
        case ITW_TYPE_VEH_SHIP: {missionNamespace getVariable ["ITW_ParamAttackShipSpawnAdjustment",1]};
        default {1};
    }
};

ITW_CLASH_ETB_fnc_Row = {
    params ["_rowIndex"];
    if (isNil "ITW_VehArrays" || {_rowIndex < 0} || {_rowIndex >= count ITW_VehArrays}) exitWith {[]};
    ITW_VehArrays#_rowIndex
};

ITW_CLASH_ETB_fnc_RowKey = {
    params ["_rowIndex"];
    private _row = [_rowIndex] call ITW_CLASH_ETB_fnc_Row;
    if (_row isEqualTo []) exitWith {"?/?"};
    private _type = switch (_row#ITW_VEH_TYPE) do {
        case ITW_TYPE_VEH_AIRPLANE: {"PLANE"};
        case ITW_TYPE_VEH_HELI: {"HELI"};
        case ITW_TYPE_VEH_TANK: {"TANK"};
        case ITW_TYPE_VEH_APC: {"APC"};
        case ITW_TYPE_VEH_CAR: {"CAR"};
        case ITW_TYPE_VEH_SHIP: {"SHIP"};
        default {"OTHER"};
    };
    private _role = switch (_row#ITW_VEH_ROLE) do {
        case ITW_VEH_ROLE_ATTACK: {"ATTACK"};
        case ITW_VEH_ROLE_TRANSPORT: {"TRANSPORT"};
        case ITW_VEH_ROLE_DUAL: {"DUAL"};
        default {"OTHER"};
    };
    format ["%1/%2",_type,_role]
};

/*
    Price: the Impasse row's ticket price divided by Impasse's attack spawn
    setting for that vehicle type. A host who makes attack helicopters half as
    common in Impasse makes them cost twice as much ETB, which keeps the ETB
    honest about the host's own scarcity without reading Impasse's tickets. A
    setting of 0 means the ETB cannot buy that type at all.
*/
ITW_CLASH_ETB_fnc_Price = {
    params ["_rowIndex"];
    private _row = [_rowIndex] call ITW_CLASH_ETB_fnc_Row;
    if (_row isEqualTo []) exitWith {-1};
    private _adjustment = [_row#ITW_VEH_TYPE] call ITW_CLASH_ETB_fnc_TypeSpawnAdjustment;
    if (_adjustment <= 0) exitWith {-1};
    (_row#ITW_VEH_REQD_TICKETS) / _adjustment
};

// At most as many living ETB assets per Impasse row as that row's own cap. Per
// row, not per class: the row is what carries the host's intent about how many
// of a thing should exist.
ITW_CLASH_ETB_fnc_RowLimit = {
    params ["_rowIndex"];
    private _row = [_rowIndex] call ITW_CLASH_ETB_fnc_Row;
    if (_row isEqualTo []) exitWith {0};
    floor ((_row#ITW_VEH_MAX) * ITW_CLASH_ETBRowLimitScale)
};

ITW_CLASH_ETB_fnc_RowLiving = {
    params ["_side","_rowIndex"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _count = 0;
    {
        if ((_x get "rowIndex") == _rowIndex) then {_count = _count + 1};
    } forEach (_ledger get "assets");
    {
        if ((_y get "rowIndex") == _rowIndex) then {_count = _count + 1};
    } forEach (_ledger get "reservations");
    _count
};

ITW_CLASH_ETB_fnc_LivingCount = {
    params ["_side"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    (count (_ledger get "assets")) + (count (_ledger get "reservations"))
};

// A demand is reachable when its counter could fit in the reserve at all once
// there is cash for it. An unreachable one waits without holding up anything
// else, so it can never freeze every other purchase forever.
ITW_CLASH_ETB_fnc_Reachable = {
    params ["_side","_price"];
    if (_price <= 0) exitWith {false};
    _price <= (ITW_CLASH_ETBCapacity - ([_side] call ITW_CLASH_ETB_fnc_LivingValue))
};

ITW_CLASH_ETB_fnc_Assets = {
    params ["_side",["_capability",""]];
    private _assets = ([_side] call ITW_CLASH_ETB_fnc_Ledger) get "assets";
    if (_capability isEqualTo "") exitWith {+_assets};
    _assets select {(_x get "capability") isEqualTo _capability}
};

/*
    Escrow, and only when starvation actually happens: if a younger demand
    spends money while an older one cannot afford its counter, the older demand
    is marked bypassed, and after one bypass the money is held for it. Holding
    from the start would stall the cheap, frequent answers for an expensive one
    that may never be wanted.
*/
ITW_CLASH_ETB_fnc_MarkBypassed = {
    params ["_side","_need","_price"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _bypassed = _ledger get "bypassed";
    private _count = (_bypassed getOrDefault [_need,0]) + 1;
    _bypassed set [_need,_count];
    if (_count >= 1 && {[_side,_price] call ITW_CLASH_ETB_fnc_Reachable}) then {
        _ledger set ["escrow",_need];
        ["escrow-held",[
            [_side] call ITW_CLASH_ETB_fnc_CodeSign,_need,round _price,_count
        ]] call ITW_CLASH_ETB_fnc_Log;
    };
    _count
};

ITW_CLASH_ETB_fnc_Escrow = {
    params ["_side"];
    ([_side] call ITW_CLASH_ETB_fnc_Ledger) get "escrow"
};

ITW_CLASH_ETB_fnc_ClearEscrow = {
    params ["_side",["_need",""]];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    if (_need isNotEqualTo "" && {(_ledger get "escrow") isNotEqualTo _need}) exitWith {false};
    _ledger set ["escrow",""];
    if (_need isNotEqualTo "") then {(_ledger get "bypassed") deleteAt _need};
    true
};

// One purchase per pacing interval per commander, then everything is
// re-evaluated: a shortfall of six means a shortage exists, not six purchases.
ITW_CLASH_ETB_fnc_Paced = {
    params ["_side"];
    time < (([_side] call ITW_CLASH_ETB_fnc_Ledger) get "pacedUntil")
};

ITW_CLASH_ETB_fnc_Status = {
    params ["_side",["_pending",""]];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _living = [_side] call ITW_CLASH_ETB_fnc_LivingValue;
    diag_log format [
        "CLASH ETB | %1 | cash=%2 living=%3 reserve=%4/%5 income=%6/min assets=%7 pending=%8",
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,
        round (_ledger get "cash"),
        round _living,
        round ((_ledger get "cash") + _living),
        ITW_CLASH_ETBCapacity,
        (round ((call ITW_CLASH_ETB_fnc_IncomeRate) * 100)) / 100,
        count (_ledger get "assets"),
        if (_pending isEqualTo "") then {"none"} else {_pending}
    ];
    _ledger set ["statusAt",time];
    true
};

ITW_CLASH_ETB_fnc_Deny = {
    params ["_side","_capability","_reason",["_detail",[]]];
    diag_log format [
        "CLASH ETB DENIED | %1 | %2 | %3 | %4",
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,_capability,_reason,_detail
    ];
    ["denied",[
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,_capability,_reason,_detail
    ]] call ITW_CLASH_ETB_fnc_Log;
    createHashMapFromArray [
        ["status","DENIED"],["reason",_reason],["capability",_capability],["reservation",""]
    ]
};

/*
    Authorize one purchase. Money and the row slot are taken here, before
    anything that can pause the script, so two demands in the same pass cannot
    both spend the same cash. Every path either returns a reservation or a
    reason from the one vocabulary.
*/
ITW_CLASH_ETB_fnc_Authorize = {
    params ["_side","_capability","_need","_rowIndex",["_class",""],["_threat",""]];
    if (!ITW_CLASH_ETBEnabled) exitWith {
        [_side,_capability,"NO_CANDIDATE",["etb-disabled"]] call ITW_CLASH_ETB_fnc_Deny
    };
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    [_side] call ITW_CLASH_ETB_fnc_Accrue;

    private _price = [_rowIndex] call ITW_CLASH_ETB_fnc_Price;
    if (_price <= 0) exitWith {
        [_side,_capability,"NO_CANDIDATE",[
            "row-unbuyable",_rowIndex,[_rowIndex] call ITW_CLASH_ETB_fnc_RowKey
        ]] call ITW_CLASH_ETB_fnc_Deny
    };
    // A normalized price can exceed the whole capacity (a 42-ticket helicopter
    // at a 0.5 setting costs 84), so it could never be bought: the caller is
    // expected to try a cheaper vehicle in the same capability first.
    if (_price > ITW_CLASH_ETBCapacity) exitWith {
        [_side,_capability,"COST_EXCEEDS_CAPACITY",[
            _class,round _price,ITW_CLASH_ETBCapacity
        ]] call ITW_CLASH_ETB_fnc_Deny
    };
    if (([_side] call ITW_CLASH_ETB_fnc_LivingCount) >= ITW_CLASH_ETBSafetyLimit) exitWith {
        [_side,_capability,"SAFETY_LIMIT",[
            ITW_CLASH_ETBSafetyLimit,[_rowIndex] call ITW_CLASH_ETB_fnc_RowKey,_class
        ]] call ITW_CLASH_ETB_fnc_Deny
    };
    private _rowLimit = [_rowIndex] call ITW_CLASH_ETB_fnc_RowLimit;
    if (([_side,_rowIndex] call ITW_CLASH_ETB_fnc_RowLiving) >= _rowLimit) exitWith {
        [_side,_capability,"ETB_ROW_CAP",[
            [_rowIndex] call ITW_CLASH_ETB_fnc_RowKey,_rowLimit
        ]] call ITW_CLASH_ETB_fnc_Deny
    };
    private _living = [_side] call ITW_CLASH_ETB_fnc_LivingValue;
    if ((_living + _price) > ITW_CLASH_ETBCapacity) exitWith {
        [_side,_capability,"ETB_RESERVE_CAP",[
            round _living,round _price,ITW_CLASH_ETBCapacity
        ]] call ITW_CLASH_ETB_fnc_Deny
    };

    private _cash = _ledger get "cash";
    if (_cash < _price) exitWith {
        private _rate = call ITW_CLASH_ETB_fnc_IncomeRate;
        private _eta = if (_rate > 0) then {(_price - _cash) / _rate} else {-1};
        [_side,_capability,"INSUFFICIENT_ETB",[
            (round (_cash * 10)) / 10,round _price,
            (round ((_price - _cash) * 10)) / 10,
            (round (_eta * 10)) / 10
        ]] call ITW_CLASH_ETB_fnc_Deny
    };
    // Money held for an older demand that was bypassed once already is not
    // available to a younger one.
    private _escrow = _ledger get "escrow";
    if (_escrow isNotEqualTo "" && {_escrow isNotEqualTo _need}) exitWith {
        [_side,_capability,"INSUFFICIENT_ETB",[
            "escrow-held",_escrow,_need,round _price
        ]] call ITW_CLASH_ETB_fnc_Deny
    };

    if (ITW_CLASH_ETBDryRun) exitWith {
        diag_log format [
            "CLASH ETB DRYRUN | %1 | %2 | %3 | row=%4 | cost=%5 | cash=%6 | threat=%7",
            [_side] call ITW_CLASH_ETB_fnc_CodeSign,_capability,_class,
            [_rowIndex] call ITW_CLASH_ETB_fnc_RowKey,round _price,round _cash,_threat
        ];
        createHashMapFromArray [
            ["status","DRY_RUN"],["reason","dry-run"],["capability",_capability],
            ["reservation",""],["price",_price]
        ]
    };

    ITW_CLASH_ETBSerial = ITW_CLASH_ETBSerial + 1;
    private _reservationId = format ["ETB-%1-%2",round (diag_tickTime * 1000),ITW_CLASH_ETBSerial];
    _ledger set ["cash",_cash - _price];
    (_ledger get "reservations") set [_reservationId,createHashMapFromArray [
        ["cost",_price],["rowIndex",_rowIndex],["capability",_capability],
        ["need",_need],["class",_class],["threat",_threat],["reservedAt",time],
        ["cashBefore",_cash]
    ]];
    _ledger set ["pacedUntil",time + ITW_CLASH_ETBGroundInterval];
    [_side,_need] call ITW_CLASH_ETB_fnc_ClearEscrow;

    ["reserved",[
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,_reservationId,_capability,_class,
        round _price,round (_cash - _price)
    ]] call ITW_CLASH_ETB_fnc_Log;
    createHashMapFromArray [
        ["status","APPROVED"],["reason","reserved"],["capability",_capability],
        ["reservation",_reservationId],["price",_price]
    ]
};

// Any failure after the reservation returns the money and the slot: the ETB
// never leaks a reservation, and it never falls back to Impasse tickets.
ITW_CLASH_ETB_fnc_Cancel = {
    params ["_side","_reservationId",["_reason","cancelled"]];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _reservations = _ledger get "reservations";
    private _reservation = _reservations getOrDefault [_reservationId,createHashMap];
    if (count _reservation == 0) exitWith {false};
    _reservations deleteAt _reservationId;
    _ledger set ["cash",(_ledger get "cash") + (_reservation get "cost")];
    // A cancelled purchase must not eat the pacing interval, or a string of
    // spawn failures would silently stop the commander buying anything.
    _ledger set ["pacedUntil",0];
    ["reservation-returned",[
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,_reservationId,_reason,
        round (_reservation get "cost"),round (_ledger get "cash")
    ]] call ITW_CLASH_ETB_fnc_Log;
    true
};

/*
    The reservation becomes a living asset. The vehicle is stamped as ETB
    property and never with ITW_VehDef: ETB assets are purely additive and must
    not count against Impasse's caps. Every reader of ITW_VehDef that skips
    vehicles without it has to accept these instead - see the ETB asset marks
    below, which LogisticsGuard and the service layers test for.
*/
ITW_CLASH_ETB_fnc_Commit = {
    params ["_side","_reservationId","_veh",["_group",grpNull],["_threat",""]];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _reservations = _ledger get "reservations";
    private _reservation = _reservations getOrDefault [_reservationId,createHashMap];
    if (count _reservation == 0) exitWith {false};
    if (isNull _veh) exitWith {
        [_side,_reservationId,"no-vehicle"] call ITW_CLASH_ETB_fnc_Cancel;
        false
    };
    _reservations deleteAt _reservationId;

    private _cost = _reservation get "cost";
    private _rowIndex = _reservation get "rowIndex";
    private _livingBefore = [_side] call ITW_CLASH_ETB_fnc_LivingValue;
    private _crew = (crew _veh) select {alive _x && {!isPlayer _x}};
    ITW_CLASH_ETBSerial = ITW_CLASH_ETBSerial + 1;
    private _asset = createHashMapFromArray [
        ["id",format ["ETBA-%1",ITW_CLASH_ETBSerial]],
        ["vehicle",_veh],
        ["group",if (isNull _group) then {group effectiveCommander _veh} else {_group}],
        ["class",typeOf _veh],
        ["cost",_cost],
        ["rowIndex",_rowIndex],
        ["capability",_reservation get "capability"],
        ["need",_reservation get "need"],
        ["threat",if (_threat isEqualTo "") then {_reservation get "threat"} else {_threat}],
        ["crew",_crew],
        ["purchasedAt",time],
        ["holdsReserve",true],
        ["idleSince",time],
        ["lastCrewAt",time],
        ["lastMovedAt",time],
        ["lastPosition",getPosATL _veh],
        ["side",_side]
    ];
    (_ledger get "assets") pushBack _asset;

    _veh setVariable ["ITW_CLASH_ETBAsset",true,true];
    _veh setVariable ["ITW_CLASH_ETBRow",_rowIndex,true];
    _veh setVariable ["ITW_CLASH_ETBCost",_cost,true];
    _veh setVariable ["ITW_CLASH_ETBCapability",_reservation get "capability",true];

    diag_log format [
        "CLASH ETB PURCHASE | %1 | %2 | %3 | row=%4 | cost=%5 | cash %6->%7 | living %8->%9 | threat=%10",
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,
        _reservation get "capability",
        typeOf _veh,
        [_rowIndex] call ITW_CLASH_ETB_fnc_RowKey,
        round _cost,
        round (_reservation get "cashBefore"),
        round (_ledger get "cash"),
        round (_livingBefore - _cost),
        round _livingBefore,
        _asset get "threat"
    ];
    true
};

// There is no refund when an ETB asset dies. Losing it frees reserve room, so
// the commander can buy again in time, but the money is gone: that is what
// makes destroying the enemy's counter worth real effort.
ITW_CLASH_ETB_fnc_Retire = {
    params ["_side","_asset",["_reason","lost"]];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    private _assets = _ledger get "assets";
    private _index = _assets findIf {(_x get "id") isEqualTo (_asset get "id")};
    if (_index < 0) exitWith {false};
    private _livingBefore = [_side] call ITW_CLASH_ETB_fnc_LivingValue;
    private _reserveBefore = (_ledger get "cash") + _livingBefore;
    _assets deleteAt _index;
    private _livingAfter = [_side] call ITW_CLASH_ETB_fnc_LivingValue;

    diag_log format [
        "CLASH ETB LOSS | %1 | %2 | cost=%3 | living %4->%5 | reserve %6->%7 | no refund | %8",
        [_side] call ITW_CLASH_ETB_fnc_CodeSign,
        _asset get "class",
        round (_asset get "cost"),
        round _livingBefore,
        round _livingAfter,
        round _reserveBefore,
        round ((_ledger get "cash") + _livingAfter),
        _reason
    ];
    true
};

// Is HAL employing this asset at all? Idle here means exactly what it means in
// native HAL: not on a mission, not resting, not being resupplied.
ITW_CLASH_ETB_fnc_AssetIsEmployed = {
    params ["_asset"];
    private _group = _asset get "group";
    if (isNull _group) exitWith {false};
    (_group getVariable ["Busy" + str _group,false])
    || {_group getVariable ["Resting" + str _group,false]}
    || {_group getVariable ["ITW_CLASH_ResupplyClaimed",false]}
    || {_group getVariable ["ITW_CLASH_SPAAOverwatch",false]}
};

/*
    One audit pass per commander. It answers four questions, in this order:
    is the asset still ours, is its crew still aboard, can it still move, and
    is HAL using it.
*/
ITW_CLASH_ETB_fnc_Audit = {
    params ["_side"];
    private _ledger = [_side] call ITW_CLASH_ETB_fnc_Ledger;
    {
        private _asset = _x;
        private _veh = _asset get "vehicle";
        private _retire = "";

        if (isNull _veh || {!alive _veh}) then {
            _retire = "destroyed";
        };
        // A crewed vehicle that has changed hands is no longer this
        // commander's asset. An empty one is left to the crew write-off below,
        // which is also what covers a player driving off in an abandoned tank.
        if (_retire isEqualTo "") then {
            private _commander = effectiveCommander _veh;
            if (!isNull _commander && {alive _commander} && {side (group _commander) != _side}) then {
                _retire = "side-changed";
            };
        };

        if (_retire isEqualTo "") then {
            private _crew = _asset get "crew";
            private _aboard = (crew _veh) select {alive _x && {_x in _crew}};
            if (_aboard isNotEqualTo []) then {
                _asset set ["lastCrewAt",time];
            } else {
                if ((time - (_asset get "lastCrewAt")) >= ITW_CLASH_ETBCrewWriteOff) then {
                    _retire = "crew-gone";
                };
            };
        };

        if (_retire isEqualTo "") then {
            private _position = getPosATL _veh;
            if (
                !(canMove _veh)
                || {(_position distance2D (_asset get "lastPosition")) < ITW_CLASH_ETBImmobileTolerance}
            ) then {
                if ((time - (_asset get "lastMovedAt")) >= ITW_CLASH_ETBImmobileWriteOff) then {
                    _retire = "immobile";
                };
            } else {
                _asset set ["lastMovedAt",time];
                _asset set ["lastPosition",_position];
            };
        };

        if (_retire isNotEqualTo "") then {
            [_side,_asset,_retire] call ITW_CLASH_ETB_fnc_Retire;
            continue;
        };

        if ([_asset] call ITW_CLASH_ETB_fnc_AssetIsEmployed) then {
            _asset set ["idleSince",time];
        } else {
            if (
                (_asset get "holdsReserve")
                && {(time - (_asset get "idleSince")) >= ITW_CLASH_ETBIdleRelease}
            ) then {
                // HAL will not employ it and the reserve should not stay frozen
                // for the rest of the war. The room comes back; the cash does
                // not, and the asset still counts against row and safety limits
                // and is still re-offered before any new purchase.
                _asset set ["holdsReserve",false];
                ["idle-release",[
                    [_side] call ITW_CLASH_ETB_fnc_CodeSign,
                    _asset get "class",round (_asset get "cost"),
                    round (time - (_asset get "idleSince"))
                ]] call ITW_CLASH_ETB_fnc_Log;
            };
        };
    } forEach (+(_ledger get "assets"));

    // A reservation whose purchase never completed would hold money forever.
    {
        if ((time - (_y get "reservedAt")) > ITW_CLASH_ETBReservationTimeout) then {
            [_side,_x,"reservation-timeout"] call ITW_CLASH_ETB_fnc_Cancel;
        };
    } forEach (+(_ledger get "reservations"));
    true
};

[] spawn {
    scriptName "ITW_CLASH_EmergingThreatsBudget";
    waitUntil {
        sleep 1;
        !isNil "ITW_CLASH_fnc_GetCommanderForSide" || {
            missionNamespace getVariable ["ITW_GameOver",false]
        }
    };

    private _auditAt = 0;
    private _statusAt = 0;
    while {isNil "ITW_GameOver" || {!ITW_GameOver}} do {
        if (ITW_CLASH_ETBEnabled) then {
            private _sides = [];
            if (!isNil "ITW_PlayerSide") then {_sides pushBackUnique ITW_PlayerSide};
            if (!isNil "ITW_EnemySide") then {_sides pushBackUnique ITW_EnemySide};
            {
                [_x] call ITW_CLASH_ETB_fnc_Accrue;
                if (time >= _auditAt) then {[_x] call ITW_CLASH_ETB_fnc_Audit};
                if (time >= _statusAt) then {[_x,""] call ITW_CLASH_ETB_fnc_Status};
            } forEach _sides;
            if (time >= _auditAt) then {_auditAt = time + ITW_CLASH_ETBAuditInterval};
            if (time >= _statusAt) then {_statusAt = time + 60};
        };
        sleep ITW_CLASH_ETBAccrualInterval;
    };
};

ITW_CLASH_ETBReady = true;
diag_log format [
    "CLASH BOOT | etb-ready | version=%1 dryRun=%2 start=%3 capacity=%4 incomeScale=%5 rate=%6/min rowScale=%7 safetyLimit=%8 pacing=%9 idleRelease=%10 impasseTicketsUntouched=true vehDefStamped=false",
    ITW_CLASH_ETBVersion,
    ITW_CLASH_ETBDryRun,
    ITW_CLASH_ETBStartingReserve,
    ITW_CLASH_ETBCapacity,
    ITW_CLASH_ETBIncomeScale,
    (round ((call ITW_CLASH_ETB_fnc_IncomeRate) * 100)) / 100,
    ITW_CLASH_ETBRowLimitScale,
    ITW_CLASH_ETBSafetyLimit,
    ITW_CLASH_ETBGroundInterval,
    ITW_CLASH_ETBIdleRelease
];
true
