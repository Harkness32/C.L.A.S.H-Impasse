#include "scripts\SKULL\SKL_Semaphore.hpp"

#define BASE_INDEX_NONE -999
#define ITW_SUITCASE "Land_Suitcase_F"

// ITW_Objective array indexes
#define ITW_OBJ_POS         0
#define ITW_OBJ_MARKER      1
#define ITW_OBJ_NAME        2
#define ITW_OBJ_FLAG        3
#define ITW_OBJ_TASKID      4
#define ITW_OBJ_ZONEID      5
#define ITW_OBJ_ATTACKS     6 // array of nearest base indexes this objective would be attacked from
#define ITW_OBJ_INDEX       7 // index into ITW_OBJECTIVES & ITW_Bases for this obj and it's associated base (-1 if not yet assigned)
#define ITW_OBJ_OWNER       8 // see ITW_OWNER_* defines below
#define ITW_OBJ_V_SPAWN     9 // vehicle spawn point (on a road), or [] if no reads nearby, or nil if not setup yet
#define ITW_OBJ_ATK_AVAIL  10 // array of [ATTACK_FRIENDLY land attack possible, ATTACK_ENEMY land attack possible, friendly sea attack possible, enemy sea attack possible]
#define ITW_OBJ_HIDDEN     11
#define ITW_OBJ_SIZE       12
#define ITW_OBJ_ARRAY_SIZE 13 // should be last enum

// ITW_ObjContestedState - this is updated over the network more frequently
#define ITW_CONT_OBJ_IDX         0 // obj index for this contested objective
#define ITW_CONT_PLAYER_OWNED    1 // true if players own the contested objective (blue flag, or red flag and enemy is still capturing it)
#define ITW_CONT_TARGET_COMPLETE 2 // number 0 to 1 (how complete: 0 = none, 1 = total complete) or -1 if not defined, -2 if none

// ITW_Objectives#_i#ITW_OBJ_ATTACKS array indexes (-1 if not available)
#define ITW_ATTACK_LAND_F  0 // nearest base for friendly to attack from by land
#define ITW_ATTACK_AIR_F   1 // friendly attack by air
#define ITW_ATTACK_LAND_E  2 // enemy attack by land
#define ITW_ATTACK_AIR_E   3 // enemy attack by air
#define ITW_ATTACK_SEA_F   4 // friendly attack by sea 
#define ITW_ATTACK_SEA_E   5 // enemy attack by sea

// ITW_Objectives#_i#ITW_OBJ_OWNER values
#define ITW_OWNER_UNDEFINDED -2  // value used during setup
#define ITW_OWNER_ENEMY      -1  // zone objectives owned by enemy
#define ITW_OWNER_CONTESTED   0  // these are the current zone objectives
#define ITW_OWNER_FRIENDLY    1  // zone objectives captured by players

#define EMPTY_OBJ_ATTACKS [-1,-1,-1,-1,-1,-1]
#define NO_OBJ_ATK_AVAIL  [false,false,false,false]
#define EMPTY_OBJECTIVE   [[0,0,0],"","Empty",objNull,"",0,EMPTY_OBJ_ATTACKS, 0,ITW_OWNER_ENEMY,[0,0,0],NO_OBJ_ATK_AVAIL, true,ITW_ParamObjectiveSize] 
#define INIT_OBJECTIVE    [[0,0,0],"","Empty",objNull,"",0,EMPTY_OBJ_ATTACKS,-1,ITW_OWNER_ENEMY,    nil,NO_OBJ_ATK_AVAIL,false,ITW_ParamObjectiveSize] 

// ITW_Bases array indexes
#define EMPTY_BASE         [[0,0,0],0,[0,0,0],[0,0,0],[-1000,-1000,0],[-1000,-1000,0],false]
#define ITW_BASE_POS        0
#define ITW_BASE_DIR        1
#define ITW_BASE_P_SPAWN    2   // player spawn point
#define ITW_BASE_A_SPAWN    3   // ai spawn point
#define ITW_BASE_GARAGE_POS 4
#define ITW_BASE_REPAIR_PT  5 
#define ITW_BASE_SPAWNED    6   // true if base has been placed

// ITW_Atk constants
#define AI_SQUAD_SIZE      6 // typical squad size for ai foot patrols
#define AI_SPAWN_TRIGGER   4 // how many ai die before we spawn the next wave
#define AI_SPAWN_RATE   0.25 // how many ai can spawn per cycle (% of max)
#define TICKETS_PER_MIN    1 // this value is scaled with number of enemy
#define MAX_AI_PER_SIDE   75 // max ai infantry per side (vehicles/crew not counted)
#define FLEE_TIMEOUT     120 //
#define UNIT_COURAGE     0.95 // unit's courage skill is set to 1, but this is used to limit fleeing
#define UNLOAD_DISTANCE  200 // distance that vehicles unload their cargo
#define TRANSPORT_DROP_MAX_DIST 800 // troops loaded into players vehicles will exit if within this close of an objective
#define MAX_CIV_UNITS     21 // max units in a 300m zone, levels will be 1/3, 2/3, or this amount depending on IM_ParamCivilians

#define FLAG_TYPE          "Flag_Blue_F"

// ITW_AtkManager Veh Array indexes (vehDef)
#define ITW_VEH_TYPE         0 
    #define ITW_TYPE_VEH_AIRPLANE   10
    #define ITW_TYPE_VEH_HELI       11 
    #define ITW_TYPE_VEH_AIR_MAX    ITW_TYPE_VEH_HELI // air vehicle below this value
    #define ITW_TYPE_VEH_TANK       12 
    #define ITW_TYPE_VEH_APC        13
    #define ITW_TYPE_VEH_CAR        14
    #define ITW_TYPE_VEH_LAND_MAX   ITW_TYPE_VEH_CAR // land vehicle below this value
    #define ITW_TYPE_VEH_INFANTRY   ITW_TYPE_VEH_LAND_MAX // infantry would act like land veh in some functions
    #define ITW_TYPE_VEH_SHIP       15
#define ITW_VEH_ROLE         1  // "attack","transport","dual"
    #define ITW_VEH_ROLE_ATTACK     20
    #define ITW_VEH_ROLE_TRANSPORT  21
    #define ITW_VEH_ROLE_DUAL       22
    #define ITW_VEH_ROLE_COMPLETE   23   // role of vehicle that needs to exit and despawn
#define ITW_VEH_ZONES_OWNED  2  // number of zones owned to allow this vehicle type (players 1st zone not counted, 0 to #zones-1)
#define ITW_VEH_REQD_TICKETS 3  // number of tickets required to spawn this vehicle
#define ITW_VEH_CURR_TICKETS 4  // current number of tickets
#define ITW_VEH_MAX          5  // max of how many of this veh type is in currently active in the battle
#define ITW_VEH_COUNT        6  // count of how many of this veh type is in currently active in the battle
#define ITW_VEH_CLASSES      7  // array of class names
#define ITW_VEH_IS_FRIENDLY  8  // true for player side, false for enemy side
#define ITW_VEH_IS_DUAL_AS_TRANSPORT 9 // true if a dual has been defined to be used as a transport, meaning the ammo needs to be removed

#define ITW_VEH_IS_AIR(VEHTYPE)  (VEHTYPE <= ITW_TYPE_VEH_AIR_MAX)
#define ITW_VEH_IS_LAND(VEHTYPE) (VEHTYPE <= ITW_TYPE_VEH_LAND_MAX && {VEHTYPE > ITW_TYPE_VEH_AIR_MAX})
#define ITW_VEH_IS_SEA(VEHTYPE)  (VEHTYPE == ITW_TYPE_VEH_SHIP)

// _vehInfo indexes 
#define VEHINFO_TYPE       0
#define VEHINFO_ROLE       1
#define VEHINFO_VEH        2
#define VEHINFO_CREW_GRP   3
#define VEHINFO_CARGO_GRPS 4 // array of groups or [] if no cargo units
#define VEHINFO_FROM_POS   5
#define VEHINFO_IS_DUAL_AS_TRANSPORT 6

// ITW_Atk* indexes
#define ATTACK_FRIENDLY      0
#define ATTACK_ENEMY         1
#define ATTACK_SEA_FRIENDLY  2
#define ATTACK_SEA_ENEMY     3
#define ATTACK_SIDE(ATTACK_GROUP)     if (side (ATTACK_GROUP) == west) then {0} else {1}
#define ATTACK_SIDE_SEA(ATTACK_GROUP) if (side (ATTACK_GROUP) == west) then {2} else {3}
#define GRP_IS_FRIENDLY(ATTACK_GROUP) (side (ATTACK_GROUP) == west)

// AttackVector types
#define AV_VEHICLE        0
#define AV_VEHICLE_ATTACK 1
#define AV_INFANTRY       2

// AssignedGroup type
#define AG_GROUPS 0
#define AG_COUNTS 1

// Attack Variables
#define VAR_SET_OBJ_IDX(GRP,OIDX)     (GRP setVariable ["VarAssignedObjIdx",OIDX]   )
#define VAR_GET_OBJ_IDX(GRP)          (GRP getVariable ["VarAssignedObjIdx",-1]     )
#define VAR_SET_WAIT_TRANSP(GRP,WAIT) (GRP setVariable ["VarWaitingTransport",WAIT] )
#define VAR_GET_WAIT_TRANSP(GRP)      (GRP getVariable ["VarWaitingTransport",false])

// Target indexes
#define TGT_FUNCTION    0
#define TGT_TITLE       1
#define TGT_DESCRIPTION 2

// Usefull Defines
#define GARAGE_MARKER_NAME(OBJECT)      "itwGpad"+ (netID (OBJECT))
#define ITW_BASE_PLACARD              "Land_Noticeboard_F"

#define ITW_TICKET_SEM_CHECK               while {ITW_VehArraysUpdating} do {sleep 0.1}; //_tm = time+1;while {time<_tm && ITW_VehArraysUpdating} do {sleep 0.1}; if (ITW_VehArraysUpdating) then {diag_log ["TICKET SEM TIMEOUT",__LINE__,__FILE_NAME__]};
#define ITW_TICKET_REDUCE(VEH_DEF)         (VEH_DEF) set [ITW_VEH_CURR_TICKETS,((VEH_DEF) select ITW_VEH_CURR_TICKETS) - ((VEH_DEF) select ITW_VEH_REQD_TICKETS)]            
#define ITW_VEH_COUNT_INCR(VEH_DEF)        (VEH_DEF) set [ITW_VEH_COUNT,((VEH_DEF) select ITW_VEH_COUNT)+1]

#define ITW_SETPOS_AGL(VEH,POSAGL) if (surfaceIsWater POSAGL) then {VEH setPosASL POSAGL} else {VEH setPosATL POSAGL}
#define ITW_ELEVATION_GT(VEH,ELEV) (getPosASL VEH select 2 > ELEV && {getPosATL VEH select 2 > ELEV})
#define ITW_ELEVATION_LT(VEH,ELEV) (getPosASL VEH select 2 < ELEV && {getPosATL VEH select 2 < ELEV})
#define ITW_ELEVATION(POSATL)      if (surfaceIsWater POSATL) then {(POSATL select 2)-(getTerrainHeightASL POSATL)} else {POSATL select 2}
#define ITW_DELETE_WAYPOINTS(GRP)  if (leader GRP == vehicle leader GRP) then {{_x doMove getPosATL _x} forEach units GRP};{deleteWaypoint _x} forEachReversed waypoints GRP;(GRP addWaypoint [getPos leader GRP,0]) setWaypointCompletionRadius 50000

#define GROUP_OWNER{GRP} if(units GRP isEqualTo []) then {objNull} else {{units GRP)#0}
#define YIELD_CPU   sleep 0.015

#define ITW_ALLOW_DAMAGE_DEBUG 0 // 1 enabled, 0 disabled
#if ITW_ALLOW_DAMAGE_DEBUG == 1
  #define ALLOW_DAMAGE(who,allowed) if (!isNull who) then {[who,allowed,__FILE_SHORT__,__LINE__] call ITW_FncAllowDamageDEBUG}
#else
  #define ALLOW_DAMAGE(who,allowed) if (!isNull who) then {if (local who) then {who allowDamage allowed} else {[who,allowed] remoteExec ["allowDamage",who]}}
#endif

#if __has_include("\z\ace\addons\main\script_component.hpp")
  #define ALIVE(unit) (lifeState (unit) in ["HEALTHY","INJURED"])
  #define CONSCIOUS(unit) (!((unit) getVariable ["ACE_isUnconscious", false]))
#else
  #define ALIVE(unit) (alive (unit))
  #define CONSCIOUS(unit) (lifeState (unit) in ["HEALTHY","INJURED"])
#endif
    
// uncomment this define to show all remoteExec calls in the log
//#define remoteExec select {if (!isServer) then {diag_log ["remoteExec",_x,__FILE_NAME__,__LINE__]};true} remoteExec
