
if (isNil "ITW_Params_complete") then {
    // Convert all the params into ITW_<paramName> variables
    diag_log "ITW: Params:";
    
    private _list = [];
    private _randomParams = [];
    { 
        private _name = configName _x;
        if (_name select [0,6] != "Spacer") then { 
            call compile format [
                "ITW_Param%1 = %2;
                 if (isServer) then {profileNamespace setVariable ['ITW_Param%1',ITW_Param%1];};
                 _list pushBack 'ITW_Param%1';
                 if (ITW_Param%1 isEqualTo 777) then {_randomParams pushBack 'ITW_Param%1'};
                 "
                ,_name, [_name,nil] call BIS_fnc_getParamValue];
        };
    } forEach ("true" configClasses getMissionConfig "Params");
    
    
    // Handle random parameters
    if (isServer) then {
        private _randomMap = createHashMapFromArray [
            ["ITW_ParamObjectiveCount"               ,[1,2,4,6,10,16,18]],
            ["ITW_ParamObjectivesPerZone"            ,[1,2,3,4,5,6]],
            ["ITW_ParamObjectiveSize"                ,[50,100,150,200,250,400,500,750]],
            ["ITW_ParamObjectiveInTowns"             ,[40,15,5,0]],
            ["ITW_ParamObjectiveCaptureSpeed"        ,[1,2,3,5,8]],
            ["ITW_ParamExtraBuildings"               ,[0,1,2,3]],
            ["ITW_ParamEnemyAiCnt"                   ,[0,10,20,30,40,50,60,70,80,100,150]],
            ["ITW_ParamExtraLaunchers"               ,[0,1,2]],
            ["ITW_ParamMines"                        ,[0,1,2,3]],
            ["ITW_ParamArtillery"                    ,[0,3,5,10,15,20,25]],
            ["ITW_ParamStatics"                      ,[0,1,2,3,4,-1,-2,-3,-4]],
            ["ITW_ParamGarrison"                     ,[0,1,2]],
            ["ITW_ParamObjLockTime"                  ,[0,60,120,300,600]],
            ["ITW_ParamSpawnDelay"                   ,[60,120,180,240,300]],
            ["ITW_ParamSpawnDelayEnemy"              ,[60,120,180,240,300]],
            ["ITW_ParamTargets"                      ,[0,1,175,150,125,2,275,250,225]],
            ["ITW_ParamVehicles"                     ,[0, 1, 2, 3]],
            ["ITW_ParamVehicleEscalation"            ,[1,2,0]],
            ["ITW_ParamVehicleSideAdjustment"        ,[0,1,4,7,10,13,16,19]],
            ["ITW_ParamVehicleAirLandBalance"        ,[-2,-1,0,1,2]],
            ["ITW_ParamVehicleSpawnAdjustment"       ,[2,4,7,10,13,16]],
            ["ITW_ParamAttackPlaneSpawnAdjustment"   ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAttackHeliSpawnAdjustment"    ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAttackTankSpawnAdjustment"    ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAttackApcSpawnAdjustment"     ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAttackCarSpawnAdjustment"     ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAttackShipSpawnAdjustment"    ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportPlaneSpawnAdjustment",[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportHeliSpawnAdjustment" ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportTankSpawnAdjustment" ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportApcSpawnAdjustment"  ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportCarSpawnAdjustment"  ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamTransportShipSpawnAdjustment" ,[0,1,2,5,10,20,30,40,50]],
            ["ITW_ParamAirDropVehicles"              ,[0,1]],
            ["ITW_ParamAirplaneWithoutAirport"       ,[0,1]],
            ["ITW_ParamHelisUnload"                  ,[0,25,50,75,100]],
            ["ITW_ParamTransportUnloadDist"          ,[100,200,400,600,800,1000]],
            ["ITW_ParamFriendlyAiCntAdjustment"      ,[-10,-4,-3,-2,-1,0,1,2,3]],
            ["ITW_ParamFriendlyInvasionDelay"        ,[30,75,180,300,600,900]],
            ["ITW_ParamDefendPhaseIntensity"         ,[1,2,3,4,5,6,7,8,9,10]],
            ["ITW_ParamDefendPhaseDuration"          ,[450,600,750,900,1050,1200,1500,1800]],
            ["ITW_ParamCivilians"                    ,[0,0,0,1,2,3]],
            ["ITW_ParamVirtualArsenal"               ,[0,1,2]],
            ["ITW_ParamVirtualGarage"                ,[0,1,2]],
            ["ITW_ParamIdentity"                     ,[0,1,2]],
            ["ITW_ParamVehBoostZone"                 ,[0,1,2,3]],
            ["ITW_ParamDefendVehBoost"               ,[0,1,2,3]],
            ["ITW_ParamSdoIntensity"                 ,[0,1,2,3,4,5,6,7,8,9,10]],
            ["ITW_ParamSdoDuration"                  ,[300,600,900,1200,1500,1800]],
            ["ITW_ParamDamageBuildings"              ,[0,1]],
            ["ITW_ParamVehicleArmor"                 ,[0,0,1,2,3,4]],
            ["ITW_ParamVehicleArmorAmount"           ,[990,975,950,925,900,875,850,825,800,775,750,725,700]]
        ];
        
        private _savedChanged = false;
        private _savedRandoms = profileNamespace getVariable [format["ITW_RandomParams%1",worldName],createHashMap];
        {
            private _varName = _x;
            private _savedValue = _savedRandoms getOrDefault [_varName,[]];
            if (_savedValue isNotEqualTo []) then {
                call compile format ["%1 = %2",_varName,_savedValue];
                diag_log format [" %1 random, loaded from save %2",_varName,_savedValue];
            } else {
                private _values = _randomMap getOrDefault [_varName,[]];
                if (_values isNotEqualTo []) then {
                    private _value = selectRandom _values;
                    if (!isNil "_value") then {
                        call compile format ["%1 = %2",_varName,_value];
                        diag_log format [" %1 random, set to %2",_varName,_value];
                        _savedRandoms set [_varName,_value];
                        _savedChanged = true;
                    } else {
                        diag_log format ["Error Pos: ITW params.sqf: Invalid values array for parameter %1",_varName];
                    };
                } else {
                    diag_log format ["Error Pos: ITW params.sqf: Invalid random parameter %1 = 777",_varName]; 
                };
            };
        } forEach _randomParams;
        // some sanity checks on random
        if ("ITW_ParamStatics" in _randomParams) then {
            if (ITW_ParamObjectiveSize > 200) then {
                if (ITW_ParamStatics > 3) then {ITW_ParamStatics = 3};
                if (ITW_ParamStatics <-3) then {ITW_ParamStatics =-3};
            };
        };
        // now clear any saved randoms that were reset from being random
        private _savedKeys = keys _savedRandoms;
        {
            private _varName = _x;
            if (!(_varName in _randomParams) && {_varName in _savedKeys}) then {
                _savedRandoms deleteAt _varName; // remove old saved value
                diag_log format [" %1 saved random value removed",_varName];
            };
        } forEach _randomMap;
        if (_savedChanged) then {profileNamespace setVariable [format["ITW_RandomParams%1",worldName],_savedRandoms]};
        ITW_ParamsRandomSetting = _savedRandoms;
        publicVariable "ITW_ParamsRandomSetting";
    } else {
        waitUntil {!isNil "ITW_ParamsRandomSetting"};
        {
            private _varName = _x;
            private _value = _y;
            call compile format ["%1 = %2",_varName,_value];
            diag_log format [" %1 random, set to %2",_varName,_value];
        } forEach ITW_ParamsRandomSetting;
    };
    
    
    // Convert to fractional value
    if (ITW_ParamDifficulty == 0) then {
        ITW_ParamDifficulty = call ITW_FncGetServerAiDifficultySetting;
    } else {
        ITW_ParamDifficulty = ITW_ParamDifficulty/10; 
    };
    if (ITW_ParamFriendlySquadSkill == 0) then {
        ITW_ParamFriendlySquadSkill = call ITW_FncGetServerAiDifficultySetting;
    } else {
        ITW_ParamFriendlySquadSkill = ITW_ParamFriendlySquadSkill/10;
    };
    ITW_ParamForceNVGs = ITW_ParamForceNVGs == 1;
    ITW_ParamVehicleSideAdjustment = ITW_ParamVehicleSideAdjustment/10;
    ITW_ParamVehicleSpawnAdjustment = ITW_ParamVehicleSpawnAdjustment/10;
    ITW_ParamAttackPlaneSpawnAdjustment = ITW_ParamAttackPlaneSpawnAdjustment/10;
    ITW_ParamAttackHeliSpawnAdjustment  = ITW_ParamAttackHeliSpawnAdjustment /10;
    ITW_ParamAttackTankSpawnAdjustment  = ITW_ParamAttackTankSpawnAdjustment /10;
    ITW_ParamAttackApcSpawnAdjustment   = ITW_ParamAttackApcSpawnAdjustment  /10;
    ITW_ParamAttackCarSpawnAdjustment   = ITW_ParamAttackCarSpawnAdjustment  /10;
    ITW_ParamAttackShipSpawnAdjustment  = ITW_ParamAttackShipSpawnAdjustment /10;
    ITW_ParamTransportPlaneSpawnAdjustment = ITW_ParamTransportPlaneSpawnAdjustment/10;
    ITW_ParamTransportHeliSpawnAdjustment  = ITW_ParamTransportHeliSpawnAdjustment /10;
    ITW_ParamTransportTankSpawnAdjustment  = ITW_ParamTransportTankSpawnAdjustment /10;
    ITW_ParamTransportApcSpawnAdjustment   = ITW_ParamTransportApcSpawnAdjustment  /10;
    ITW_ParamTransportCarSpawnAdjustment   = ITW_ParamTransportCarSpawnAdjustment  /10;
    ITW_ParamTransportShipSpawnAdjustment  = ITW_ParamTransportShipSpawnAdjustment /10;
    ITW_ParamVehicleArmorAmount            = ITW_ParamVehicleArmorAmount /1000;
    ITW_ParamTransportsEnabled = {_x != 0} count [ITW_ParamTransportPlaneSpawnAdjustment,ITW_ParamTransportHeliSpawnAdjustment,ITW_ParamTransportTankSpawnAdjustment,
                                              ITW_ParamTransportApcSpawnAdjustment,ITW_ParamTransportCarSpawnAdjustment,ITW_ParamTransportShipSpawnAdjustment] > 0;
    
    {
        diag_log format ["  %1 = %2",_x,call compile _x];
    } forEach _list;
    ITW_AllParams = _list;
    ITW_Params_complete = true;
};