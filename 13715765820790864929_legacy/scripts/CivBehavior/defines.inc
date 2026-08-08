
#define DEBUG_VISUAL     false
#define DEBUG_LOG(x,y)   //diag_log['CivBeh: '+x,y]

#define MODE_SAFE						0
#define MODE_IDLE						1

#define REACTION_DELAY_PER_METER			0.01				//reaction delay seconds per meter (0.01 = AI 100m away from player will react 1x per second)
#define THREAT_DECAY_PER_METER				0.005				//absolute threat degradation per meter (0.01 = treat drops by 1 for each 100m)
#define THREAT_DECAY_PER_SECOND				0.005				//absolute threat degradation per second (0.01 = treat drops by 1 for each 100secs)

#define GET_THREAT_BY_DISTANCE(threatValue,threatPos,unitPos)	((threatValue - ((unitPos distance threatPos) * THREAT_DECAY_PER_METER)) max 0)

#define ICON_SAFESPOT						"\A3\Modules_F_Tacops\Data\CivilianPresenceSafeSpot\icon32_ca.paa"
#define ICON_SAFESPOT_TERMINAL				"\A3\Modules_F_Tacops\Data\CivilianPresenceSafeSpot\debugIsTerminal_ca.paa"
#define ICON_UNIT							"\A3\Modules_F_Tacops\Data\CivilianPresenceUnit\debugUnit_ca.paa"
#define ICON_DESTINATION					"\A3\Ui_f\data\IGUI\Cfg\simpleTasks\types\default_ca.paa"

#define ROUND_DECIMALS(input,accuracy)		(round((1/accuracy)*(input))*accuracy)