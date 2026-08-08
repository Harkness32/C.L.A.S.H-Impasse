#include "defines.inc"

/*
	Calculates time for danger event accumulation based on closest player distance.
*/

private _playerDistances = allPlayers apply {_x distance _this}; 
_playerDistances sort true;

((_playerDistances param [0,500]) * REACTION_DELAY_PER_METER) max 1 min 5 