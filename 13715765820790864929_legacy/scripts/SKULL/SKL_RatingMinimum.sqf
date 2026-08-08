// SKL_RatingMinimum.sqf
//
// Will keep players from becoming enemy due to rating
//
// place in init.sqf:    execVM "scripts\SKULL\SKL_RatingMinimum.sqf";
//
// Version 1.0  2-13-14
// 1.0: initial release
// 2.0: change to event handler 9-4-23

if (hasInterface) then {
    player addEventHandler ["HandleRating", {
        params ["_unit", "_rating"];
        private _newRating = rating _unit + _rating;
        #define RATING_LIMIT -1900
        if (_newRating < RATING_LIMIT) then { 
            private _msgTime = player getVariable ["SKL_MinRatingTime",-60];
            if (time - _msgTime > 10) then {
                [format [localize "STR_SKL_RM_HasBeenDemotedFMT",name player]] remoteExec ["systemChat",0];
                player setVariable ["SKL_MinRatingTime",time];
            };
            _rating = RATING_LIMIT - (rating _unit);
        };
        _rating
    }];
};

