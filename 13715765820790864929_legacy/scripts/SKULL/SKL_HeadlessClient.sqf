// execVM from init.sqf of mission
//
// Add headless clients to the mission and call them HC1 through HC5
// place them far enough off the map to not cause issues as they are in allPlayers
// Groups can be excluded from being passed off to headless client with: _group setVariable ["noHeadless",true];
/* This code modified from:
	Title: Assign AI to Headless Clients
	Author: mtatoglu00 (Gandalf)
    URL: https://github.com/mtatoglu00/AItoHC
*/

HeadlessClients = []; // variable can be used by mission, it is publicVariabled
                      // allPlayers - HeadlessClients                           (0.5us) 
                      // allPlayers select {!(_x isKindOf "HeadlessClient_F")}  (1.1us)
                      // allPlayers - entities "HeadlessClient_F"               (3.9us)

DebugHC = compileFinal '
    if (!isServer) exitWith {[] remoteExec ["DebugHC",2];"sending DebugHC command to server"};
    private _aiUnits = allUnits select {!isPlayer _x && side _x != civilian};
    private _serverUnits = _aiUnits select {groupOwner (group _x) == 2};
    private _serverUnitsCount = count _serverUnits;
    private _hcMsg = "";
    {   
        private _hc = _x;
        _count = {groupOwner (group _x) == owner _hc} count _aiUnits;
        _hcMsg = _hcMsg + format ["| %1: %2 ",name _hc,_count];
    } forEach (allPlayers select {_x isKindOf "HeadlessClient_F"});
    private _totalAI = count _aiUnits;
    private _message = format [
        "Total AI Units: %1 | Server: %2 %3",
        _totalAI,
        _serverUnitsCount,
        _hcMsg
    ];
    [_message] remoteExec ["systemChat", -2]; // Broadcast to all clients
    diag_log _message;
    if (_serverUnitsCount > 0) then {
        {
            diag_log format ["Server-controlled unit: %1, Group: %2, Side: %3, Type: %4", _x, group _x, side _x, typeOf _x];
        } forEach _serverUnits;
    };
    _message; // Return only the summary for debug console output
';

if (isServer) then {
    diag_log "HC: 'call DebugHC' on the server to view headless client usage";
    while {true} do {
        // Wait for at least one HC to connect
        diag_log "HC: Waiting for headless client to connect";
        private _delay = 1;
        waitUntil {
            sleep _delay;
            if (time > 30) then {_delay = 10};
            !(allPlayers select {_x isKindOf "HeadlessClient_F"} isEqualTo [])
        };
        diag_log "HC: Headless client connected";
        
        // Start the loop to assign AI to HCs
        while {true} do {
            // Get headless clients
            private _hcArray = allPlayers select {_x isKindOf "HeadlessClient_F"};

            if !(HeadlessClients isEqualTo _hcArray) then {HeadlessClients = _hcArray; publicVariable "HeadlessClients"};
            
            // Exit if no HCs are available
            if (count _hcArray == 0) exitWith {diag_log "HC: All headless clients disconnected"};

            // Select HC with fewest units
            private _selectedHC = _hcArray select 0;
            if (count _hcArray > 1) then {
                private _hcCounts = [];
                {
                    private _hcOwner = owner _x;
                    private _unitCount = count (allUnits select {groupOwner (group _x) == _hcOwner});
                    _hcCounts pushBack [_unitCount, _x];
                } forEach _hcArray;
                _hcCounts sort true; // Sort by unit count (ascending)
                _selectedHC = (_hcCounts select 0) select 1; // HC with fewest units
            };

            // Find all AI units and assign to HC
            {
                private _grp = _x;
                if (local _x && {side _x != civilian && {{isPlayer _x} count units _grp == 0 && {!(_grp getVariable ["noHeadless",false])}}}) then {
                    _grp setGroupOwner (owner _selectedHC);
                };
            } forEach allGroups;
            sleep 10;
        };
    };
};