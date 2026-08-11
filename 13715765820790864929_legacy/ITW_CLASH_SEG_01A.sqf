#include "defines.hpp"

ITW_CLASH_Version = 6;
ITW_CLASH_Mode = 0;
ITW_CLASH_ObserverEnabled = false;
ITW_CLASH_ObserverStarted = false;
ITW_CLASH_LiveEnabled = false;
ITW_CLASH_LiveStarted = false;
ITW_CLASH_HALReady = false;
ITW_CLASH_PilotFailed = false;
ITW_CLASH_CommanderWatchdogStarted = false;
ITW_CLASH_Transitioning = false;
ITW_CLASH_RegistrationFrozenUntil = 0;
ITW_CLASH_MaxManagedGroups = 12;
ITW_CLASH_MaxManagedPerObjective = 4;
ITW_CLASH_HALLeader = objNull;
ITW_CLASH_HALHQ = grpNull;
ITW_CLASH_HALObjectives = [];
ITW_CLASH_LastMirroredZone = -1;
ITW_CLASH_LastHeldObjectives = [];
ITW_CLASH_LastObjectiveSignature = "";
ITW_CLASH_LastDoctrineSignature = "";
ITW_CLASH_LastAllocationSignature = "";
ITW_CLASH_LastAnchorSignature = "";
ITW_CLASH_AllocationDriftMargin = 150;
ITW_CLASH_AllocationDriftCooldown = 60;
ITW_CLASH_MinAnchorSoldiers = 6;
ITW_CLASH_AnchorAuditGrace = 75;
ITW_CLASH_AnchorOrderCooldown = 60;
ITW_CLASH_AnchorRefillGrace = 120;
ITW_CLASH_AnchorAuditReadyAt = 1e10;
ITW_CLASH_ReserveRatio = 0.20;
ITW_CLASH_CommanderObjective = -1;
ITW_CLASH_ManagedGroups = [];
ITW_CLASH_AnchorGroups = createHashMap;
ITW_CLASH_AnchorRefills = createHashMap;
ITW_CLASH_ExhaustionConfirmGrace = 20;
ITW_CLASH_WithdrawalArrivalRadius = 125;
ITW_CLASH_WithdrawalOrderCooldown = 30;
ITW_CLASH_Withdrawals = createHashMap;
ITW_CLASH_LastWithdrawalSignature = "";
ITW_CLASH_ObserverNextId = 0;
ITW_CLASH_ObserverGroups = createHashMap;
ITW_CLASH_ObserverWriterLast = createHashMap;

ITW_CLASH_fnc_Log = {
    params ["_event",["_payload",[]]];
    if (!isServer || {!ITW_CLASH_ObserverEnabled}) exitWith {};
    diag_log format ["CLASH OBS | %1 | %2",_event,_payload];
};

ITW_CLASH_fnc_GroupId = {
    params ["_group"];
    if (isNull _group) exitWith {"<null>"};

    private _id = _group getVariable ["ITW_CLASH_ObserverId",""];
    if (_id isEqualTo "") then {
        ITW_CLASH_ObserverNextId = ITW_CLASH_ObserverNextId + 1;
        _id = format ["G%1",ITW_CLASH_ObserverNextId];
        _group setVariable ["ITW_CLASH_ObserverId",_id];
    };
    _id
};

ITW_CLASH_fnc_IsCommanderGroup = {
    params ["_group"];
    !isNull _group && {
        _group isEqualTo ITW_CLASH_HALHQ || {
            _group getVariable ["ITW_CLASH_Commander",false]
        }
    }
};
