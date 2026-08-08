// BoundaryLines
// 
// draw or update boundary lines on the map marking boundary between territory owned by different factions
//
// see SKL_BL_Test for an example usage
//
// [_pos] call _checkSideFn will return a side (west,east,independent,civilian,sideEmpty,...)

SKL_BL_Markers = [];

// this hashmap maps cells around cell to what to draw:
// key:  [upper==current,upperRight==current,right==current]
// data: array of numbers 0 to 7:   0 - 3 straight lines, 4 - 7 diagonal lines 
//                                    1                                        
//                                    1                      4 5               
//                                    1                     4   5              
//                                 000 222                 4     5             
//                                    3                    7     6                
//                                    3                     7   6                 
//                                    3                      7 6                  
SKL_BL_Table = createHashMapFromArray [
    [[false,false,false],[7]],
    [[false,false,true ],[0,2]],
    [[false,true ,false],[0,1,2,3]],
    [[false,true ,true ],[4]],
    [[true ,false,false],[1,3]],
    [[true ,false,true ],[5]],
    [[true ,true ,false],[6]],
    [[true ,true ,true ],[]]
];

SKL_BoundaryLines = {
    params ["_checkSideFn","_cellSize",["_lineWidth",-1],["_brush","SolidFull"],["_alpha",1],["_aoLowerLeft",[0,0]],["_aoUpperRight",[worldSize,worldSize]]];
    private _debug = false;
    
    // do some math just once
    private _cellSize2 = _cellSize/2;
    private _cellSize4 = _cellSize/4;
    private _cellSize3 = _cellSize2 + _cellSize4;
    private _cellSize4Sqr2 = 1.4142 * _cellSize4;
    if (_lineWidth < 0) then {_lineWidth = _cellSize/50};
    private _lineWidth2  = _lineWidth / 2;
    private _lineOffset = _lineWidth;
    
    // setup matrix of who owns each zone
    private _zoneOwners = [];
    private _upperX = _aoUpperRight#0 - _cellSize2;
    private _upperY = _aoUpperRight#1 - _cellSize2;
    private _lowerX = _aoLowerLeft#0 + _cellSize2;
    private _lowerY = _aoLowerLeft#1 + _cellSize2;
    for "_j" from _lowerY to _upperY step _cellSize do {
        private _rowOwners = [];
        for "_i" from _lowerX to _upperX step _cellSize do {
            private _pos = [_i,_j];        
            private _owner = [_pos] call _checkSideFn;
            _rowOwners pushBack _owner;
        };
        _zoneOwners pushBack _rowOwners;
    };
    private _zoneW = count _zoneOwners - 2;
    private _zoneH = count (_zoneOwners#0) - 2;
    
    // draw lines at zone boundaries
    private _mrkIndex = 0;
    for "_j" from 0 to _zoneH do {
        private _ptY = _lowerY + (_cellSize * _j);
        for "_i" from 0 to _zoneW do {
            private _ptX = _lowerX + (_cellSize * _i);
            private _ptOwner = _zoneOwners#_j#_i;
            private _upperOwner = _zoneOwners#(_j+1)#_i;
            private _rightOwner = _zoneOwners#_j#(_i+1);
            private _upperRtOwner = _zoneOwners#(_j+1)#(_i+1);
            private _key = [_upperOwner==_ptOwner,_upperRtOwner==_ptOwner,_rightOwner==_ptOwner];
            private _lines = SKL_BL_Table getOrDefault [_key,[]];
            // may need to add lines 1 & 2 between non _ptOwner sides
            if (_upperOwner != _upperRtOwner && {_upperOwner != _ptOwner && {_upperRtOwner != _ptOwner}}) then {
                _lines = +_lines;
                _lines pushBack 1;
                if (7 in _lines) then {
                    _lines = _lines - [7];
                    _lines pushBack 0;
                    _lines pushBack 3;
                };
            };
            if (_rightOwner != _upperRtOwner && {_rightOwner != _ptOwner && {_upperRtOwner != _ptOwner}}) then {
                _lines = +_lines;
                _lines pushBack 2;
                if (7 in _lines) then {
                    _lines = _lines - [7];
                    _lines pushBack 0;
                    _lines pushBack 3;
                };
            };          
            {        
                private ["_pt","_dir","_size","_offsetX","_offsetY","_side0","_side1"];
                switch (_x) do {
                    case 0: {
                        _pt = [_ptX + _cellSize4,_ptY + _cellSize2];
                        _dir = 90;
                        _size = _cellSize4;
                        _offsetX = 0;
                        _offsetY = 1;
                        _side0 = _ptOwner;
                        _side1 = _upperOwner;
                    };
                    case 1: {
                        _pt = [_ptX + _cellSize2,_ptY + _cellSize3];
                        _dir = 0;
                        _size = _cellSize4;
                        _offsetX = 1;
                        _offsetY = 0;
                        _side0 = _upperOwner;
                        _side1 = _upperRtOwner;
                    };
                    case 2: {
                        _pt = [_ptX + _cellSize3,_ptY + _cellSize2];
                        _dir = 90;
                        _size = _cellSize4;
                        _offsetX = 0;
                        _offsetY = 1;
                        _side0 = _rightOwner;
                        _side1 = _upperRtOwner;
                    };
                    case 3: {
                        _pt = [_ptX + _cellSize2,_ptY + _cellSize4];
                        _dir = 0;
                        _size = _cellSize4;
                        _offsetX = 1;
                        _offsetY = 0;
                        _side0 = _ptOwner;
                        _side1 = _rightOwner;
                    };
                    case 4: {
                        _pt = [_ptX + _cellSize4,_ptY + _cellSize3];
                        _dir = 45;
                        _size = _cellSize4Sqr2 + _lineWidth2;
                        _offsetX = -0.707;
                        _offsetY = 0.707;
                        _side0 = _ptOwner;
                        _side1 = _upperOwner;
                    };
                    case 5: {
                        _pt = [_ptX + _cellSize3,_ptY + _cellSize3];
                        _dir = -45;
                        _size = _cellSize4Sqr2 + _lineWidth2;
                        _offsetX = 0.707;
                        _offsetY = 0.707;
                        _side0 = _ptOwner;
                        _side1 = _upperRtOwner;
                    };
                    case 6: {
                        _pt = [_ptX + _cellSize3,_ptY + _cellSize4];
                        _dir = 45;
                        _size = _cellSize4Sqr2 + _lineWidth2;
                        _offsetX = 0.707;
                        _offsetY = -0.707;
                        _side0 = _ptOwner;
                        _side1 = _rightOwner;
                    };
                    case 7: {
                        _pt = [_ptX + _cellSize4,_ptY + _cellSize4];
                        _dir = -45;
                        _size = _cellSize4Sqr2 + _lineWidth2;
                        _offsetX = 0.707;
                        _offsetY = 0.707;
                        _side0 = _ptOwner;
                        _side1 = _rightOwner;
                    };
                };
                if !(isNil "_pt") then {
                    private _deltaX = _lineOffset * _offsetX;
                    private _deltaY = _lineOffset * _offsetY;
                    
                    private _mrkName = "SKLBL_" + str _mrkIndex;
                    _mrkIndex = _mrkIndex + 1;
                    private _mrkr = if (markerColor _mrkName == "") then {createMarkerLocal [_mrkName,[0,0]]} else {_mrkName};
                    _mrkr setMarkerPosLocal (_pt vectorAdd [-_deltaX,-_deltaY]);
                    _mrkr setMarkerBrushLocal _brush;
                    _mrkr setMarkerColorLocal ([_side0,true] call BIS_fnc_sideColor);
                    _mrkr setMarkerDirLocal _dir;
                    _mrkr setMarkerShapeLocal "RECTANGLE";
                    _mrkr setMarkerSizeLocal [_lineWidth,_size];
                    _mrkr setMarkerAlpha _alpha;
                    
                    _mrkName = "SKLBL_" + str _mrkIndex;
                    _mrkIndex = _mrkIndex + 1;
                    _mrkr = if (markerColor _mrkName == "") then {createMarkerLocal [_mrkName,[0,0]]} else {_mrkName};
                    _mrkr setMarkerPosLocal (_pt vectorAdd [_deltaX,_deltaY]);
                    _mrkr setMarkerBrushLocal _brush;
                    _mrkr setMarkerColorLocal ([_side1, true] call BIS_fnc_sideColor);
                    _mrkr setMarkerDirLocal _dir;
                    _mrkr setMarkerShapeLocal "RECTANGLE";
                    _mrkr setMarkerSizeLocal [_lineWidth,_size];
                    _mrkr setMarkerAlpha _alpha;
                };
            } forEach _lines;
            if (_debug) then {     
                private _mrkName = "SKLBL_" + str _mrkIndex;
                _mrkIndex = _mrkIndex + 1;
                private _mrkr = if (markerColor _mrkName == "") then {createMarkerLocal [_mrkName,[0,0]]} else {_mrkName};
                _mrkr setMarkerPosLocal [_ptX,_ptY];
                _mrkr setMarkerTypeLocal "b_unknown";
                _mrkr setMarkerColorLocal ([_ptOwner,true] call BIS_fnc_sideColor);
                _mrkr setMarkerDirLocal 0;
                _mrkr setMarkerShapeLocal "ICON";
                _mrkr setMarkerSizeLocal [1,1];
                _mrkr setMarkerAlpha 1;
            };
        };
        if (_debug) then {diag_log ((_zoneOwners#_j) apply {private _s = if (_x == sideEmpty) then {sideUnknown} else {_x};str _s select [0,1]})};
    };
    
    private _erasing = true;
    while {_erasing} do {
        _mrkName = "SKLBL_" + str _mrkIndex;
        _mrkIndex = _mrkIndex + 1;
        if (markerColor _mrkName == "") then {_erasing = false} else {_mrkName setMarkerAlpha 0};
    };
};

SKL_BoundaryLinesErase = {
    private _erasing = true;
    private _mrkIndex = 0;
    while {_erasing} do {
        _mrkName = "SKLBL_" + str _mrkIndex;
        _mrkIndex = _mrkIndex + 1;
        if (markerColor _mrkName == "") then {_erasing = false} else {_mrkName setMarkerAlpha 0};
    };
};

SKL_BL_Test = {
    private _step = 1000;
    #define SKL_BL_TEST_SIZE 10000
    private _testFn = {
        params ["_pos"];
        _pos params ["_i","_j"];
        private _borderSize = 1000;
        private _width2 = SKL_BL_TEST_SIZE/2;
        private _height2 = SKL_BL_TEST_SIZE/2;
        private _side = sideUnknown;
        _result = switch (true) do {
            case (_j < (_width2 - _borderSize)): {west};
            case (_j > (_width2 + _borderSize) && {_i < (_height2 - _borderSize)}): {east};
            case (_j > (_width2 + _borderSize) && {_i > (_height2 + _borderSize)}): {independent};
            case (_i < (_height2 - _borderSize)): {selectRandom [east,west]};
            case (_i > (_height2 + _borderSize)): {selectRandom [independent,west]};
            case (_j > (_width2 + _borderSize)): {selectRandom [east,independent]};
            default {sideEmpty};
        };
        _result
    };
    [_testFn,_step,_step/50,[0,0],[SKL_BL_TEST_SIZE,SKL_BL_TEST_SIZE]] spawn SKL_BoundaryLines;
};

if (isNil "SKL_fnc_CompileFinal") exitWith {};
["SKL_BoundaryLines"] call SKL_fnc_CompileFinal;
["SKL_BoundaryLinesErase"] call SKL_fnc_CompileFinal;
["SKL_BL_Test"] call SKL_fnc_CompileFinal;