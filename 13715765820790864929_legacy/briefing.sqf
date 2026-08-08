// Briefing

waitUntil {!isNull player};

// Get current location
_aoText = "";
try {
    private _locTypes = [];
    private _locs = "true" configClasses (configFile >> "CfgLocationTypes");
    {_locTypes pushBack (configName _x)} forEach _locs;

    // SOG Prairie Fire has a couple of location types that throw a ton of warnings, so remove them
    _locTypes = _locTypes - ["HandDrawnPoint","NameCityCapitalFormer"];
    _locations = nearestLocations [getPosATL player, _locTypes, 1000];
    {
        _aoText = text _x;
        if (count _aoText > 0) exitWith {};
    } forEach _locations;
} catch { diag_log format ["Error in briefing getting current location.\n%1",_exception]};

if (count _aoText == 0) then {_aoText = "countryside"};

player createDiarySubject ["ITW","Impasse Total War"];
player createDiaryRecord ["ITW", ["Credits", 
format [" Mission: %1<br/>",getText (missionconfigfile >> "onLoadName")]+
" Type: Solo/Co-op<br/>"+
format [" Players: %1-%2<br/>",getNumber (missionconfigfile >> "Header" >> "minPlayers"),getNumber (missionconfigfile >> "Header" >> "maxPlayers")]+
format [" Author: %1<br/><br/>",getText (missionconfigfile >> "author")] +
"<br/>Check out my other missions in the steam workshop at https://steamcommunity.com/sharedfiles/filedetails/?id=2773765491<br/>"
]];

player createDiaryRecord ["ITW", ["Copying to other maps", 
"How to copy my multi-map missions to a new map:<br/>
<br/>
<font color='#FFAAAA'>Simple Method:</font><br/>
1. get the zip file of all my missions (link in the mission description of any of my missions)<br/>
2. copy the file  ImpasseTW.altis.pbo and put it in your Arma MPMissions directory.  It's usually something like <font color='#FFD68A'>C:\Program Files (x86)\Steam\steamapps\common\Arma 3\MPMissions</font>.<br/>
3. Rename the file for the map you want:  Madrigal:  ImpasseTW.OPTRE_Madrigal.pbo<br/>
<br/>
Finding the Arma internal map name takes a little work.  If you have CBA_A3 mod, then start up Arma to where you choose the map and hover the cursor over the map name.  It will show the name that Arma uses internally.<br/>
<br/>
If you don't have CBA_A3, then choose the map you want on the left, select <<New - 3D Editor>> on the right, and click 'play'.  Once the editor loads, click 'Play Scenario' in the lower right.  Now open a windows explorer window and navigate to where your missions are stored.<br/>
For me it is: <font color='#FFD68A'>C:\Users\MY-NAME\Documents\Arma 3 - Other Profiles\MY-ARMA-PROFILE\MPMissions</font>.<br/>
In there you will see a new directory called  tempMissionMP.XXXXX  where the XXXXX is the map name you want.  Use that when renaming the ImpasseTW.Altis.pbo file in step 3 above.<br/>
<br/>
Each time I update the mission, you need to update these copies if you want the changes. <br/> 
<br/>
<br/>
<font color='#FFAAAA'>Complex Method:</font><br/>
1. Subscribe to <font color='#FFD68A'>Impasse Total War - Altis</font> using the steam workshop.<br/>
2. Create a symbolic link from the steam workshop file into your Arma MPMissions folder (path shown above)<br/>
The steam workshop file will be something like:
<font color='#FFD68A'>C:\Program Files (x86)\Steam\steamapps\workshop\content\107410\3444387114\13781306754930211082_legacy.bin</font><br/>
<br/>
So the shell command should look something like this, and may require admin privileges:<br/>
<font color='#FFD68A'>mklink &quot;C:\Program Files (x86)\Steam\steamapps\common\Arma 3\MPMissions\ImpasseTW.XXXX.pbo&quot; &quot;C:\Program Files (x86)\Steam\steamapps\workshop\content\107410\3444387114\13781306754930211082_legacy.bin&quot;</font><br/>
Replace the XXXX with the map name (see simple description above for how to get this).<br/>
Using this method will automatically update whenever the mission is updated.
"]];

player createDiaryRecord ["ITW", ["Parameters - Miscellaneous",
"
<font color='#FFAAAA'>Fast Travel</font color> This options adjusts what kind of fast travel is allowed.<br/>
<font color='#FFD68A'>Bases only</font color> Players can fast travel from base to base by talking to the officer.  They can also fast travel from a captured flag to a base by interacting with the flag.<br/>
<font color='#FFD68A'>Bases and Captured Flags</font color> The same as 'base only' above, except players can fast travel to captured flags not just from them.<br/>
<font color='#FFD68A'>Bases and Flags</font color> Players can fast travel between bases and captured flag, but can also parachute into un-captured bases.<br/>
<br/>
<font color='#FFAAAA'>Objective status UI</font color> By default the flag levels are shown as bars on the hud.  This can be disabled, or switched between the right or left side of the screen.<br/>
<br/>
<font color='#FFAAAA'>Red screen</font color> The mission turns the player's screen red when they are in enemy held territory.  This option allows adjusting how quickly this red appears.<br/>
<br/>
<font color='#FFAAAA'>Civilian Presence</font color> This parameter determines how many civilians are present in objectives.<br/>
<br/>
<font color='#FFAAAA'>Virtual Arsenal</font color> This parameter allows for adjusting what is available in the arsenal.<br/>
<br/>
<font color='#FFAAAA'>Use ACE Arsenal</font color> If the ACE arsenal is available, should it be used or not.  Default is to use it.  If the ACE mod is not loaded, this option has no effect.<br/>
<br/>
<font color='#FFAAAA'>Virtual Garage</font color> You can use this option to disable the virtual garage, or limit which vehicles the players have access to in the virtual garage.<br/>
<br/>
<font color='#FFAAAA'>Headless client</font color> The mission supports headless clients when this parameter is enabled.  This option allows for disabling it to improve performance when no headless clients are in use.<br/>
<br/>
<font color='#FFAAAA'>Player Identity</font color> This option can be used to force the players face/voice to use the one chosen by the player's profile, or to choose one that matches the faction being played.<br/>
<br/>
<font color='#FFAAAA'>Volume of squad mate radio chatter</font color> This parameter determines the volume of the radio chatter of your squad mates calling out targets and such.<br/>
<br/>
<font color='#FFAAAA'>Dead unit cleanup</font color> This allows adjusting how aggressive the mission will clean up dead units.  Making it more aggressive can improve performance.<br/>
<font color='#FFAAAA'>Enable NVGs even on maps that don't support them</font color> This parameter enables Night Vision Goggles in the arsenal and on players even if set to only allow DLC specific items and the DLC doesn't have NVGs.<br/>
<br/>
<font color='#FFAAAA'>Time of Day</font color> This parameter sets the time of day.<br/>
<br/>
<font color='#FFAAAA'>Weather</font color> This parameter sets the weather.<br/>
<br/>
<font color='#FFAAAA'>Time Multiplier</font color> Choose how fast time passes.  Faster times will speed up the day/night cycle.<br/>
<br/>
<font color='#FFAAAA'>View Distance</font color> This parameter sets the view distance.  Larger values allow seeing and engaging enemy vehicles further away, but is more taxing on your computer hardware.<br/>
<br/>
<font color='#FFAAAA'>Stamina</font color>
This parameter can be turned on to erase any saved game on this map.  Saved games are automatically created whenever a zone is captured/lost.  The save game is erased once the game is won/lost.  This will always be reset back to 'NO' when you restart Arma.
"]];

player createDiaryRecord ["ITW", ["Parameters - Enemy",
"<font color='#FFAAAA'>Enemy Difficulty</font color> This parameter sets skill level of the enemy units.<br/>
<br/>
<font color='#FFAAAA'>Show enemy on the map</font color> This mission has the ability to toggle on showing friendly groups/vehicles on the map (radio 0-8-2).  This option determines if known about enemy groups/vehicles are shown on the map when the friendlies are being shown.  Only enemy known about by the allies are shown, and only the vehicles or groups are shown, not all units.<br/>
"]];

player createDiaryRecord ["ITW", ["Parameters - Friendly",
"<font color='#FFAAAA'>Number of friendly soldiers compared to enemy</font color> This will adjust how many friendly vs enemy ai are in the war.  You can use this to adjust the balance of soldiers in the game.  It will make it easier or harder on the players.<br/>
<br/>
<font color='#FFAAAA'>Skill of friendly AI squads</font color> Sets the skill of the friendly ai squads and teammates.<br/>
<br/>
<font color='#FFAAAA'>Friendly squad size</font color> This option can be used to limit the number of AI allowed in the player's squad.  Limiting it can be useful on servers where rogue players may spam too many units.<br/>
<br/>
<font color='#FFAAAA'>Friendly Revive Available</font color> This option can be used to disable the AI's ability to revive players, and teammates ability to be revived.  Turn this off if you use another mod that provides this functionality.<br/>
<br/>
<font color='#FFAAAA'>Friendlies wait at base</font color> When enabled, this will cause a couple of squads of friendly infantry to remain at base awaiting transport by the players.  This option is for those players who enjoy having some support role delivering units to the front lines.<br/>
<br/>
<font color='#FFAAAA'>Player artillery</font color> The mission allows players to call in artillery.  This option is used to limit how frequently, if at all, artillery can be called.<br/>
<br/>
<font color='#FFAAAA'>Player close air support</font color> The mission allows players to call in CAS vehicles.  This option is used to limit how frequently, if at all, CAS can be called.<br/>
"]];

player createDiaryRecord ["ITW", ["Parameters - Vehicles",
"<font color='#FFAAAA'>Vehicle used by AI</font color> This option chooses where the vehicles are chosen by.  This is ignored if the 'vehicle chooser' (see below) is enabled.  It can be:
* All vehicles in Arma<br/>
* All vehicles on the faction's side (blue/red/green)<br/>
* All vehicles on the faction's side from the chosen DLCs<br/>
* All vehicles belonging to the selected faction<br/>
<br/>
<font color='#FFAAAA'>Vehicle Chooser</font color> This options allows the players to select the specific vehicles that will be used in the mission.  The garage interface in Arma is used to pick the vehicles for the friendlies, enemies, or both.  By default, vehicles are chosen based on the parameter above.<br/>
<br/>
<font color='#FFAAAA'>Vehicle escalation</font color> This option changes which vehicles are available to the AI at the start/end of the game.  It does not limit the vehicles players can use.<br/>
<font color='#FFD68A'>Vehicles unlock as missions progresses</font color> Easiest. In the first zone, the ai will only get unarmored vehicles and transport helicopters, as more zones are captured, APCs, tanks, and attack aircraft are added.  All vehicles are available by the 3rd or 4th zone.  This makes the game start off a bit easier and get a little harder over the first couple of zones since the players have access to those more powerful vehicles from the start.<br/>
<font color='#FFD68A'>Vehicles unlock depending on territory owned</font color> Hardest. This options is similar to the one above except that it's dependent on how many zones are owned.  So the friendly ai start at a disadvantage of only getting unarmored vehicles while the enemy has access to all their vehicles.  At the end of the game when the enemy only own a couple of zones, the are limited to less advanced vehicles.<br/>
<font color='#FFD68A'>All vehicles are unlocked</font color> In this mode, ai get access to all vehicles the whole game.<br/>
<br/>
<font color='#FFAAAA'>Number of friendly vehicles compared to enemy</font color> This will adjust how many friendly vs enemy ai vehicles are in the war.  You can use this to adjust the balance of vehicles in the game.  It will make it easier or harder on the players.  Use this (and it's parallel 'friendly vs enemy unit' parameter) to make the game a little easier or harder if it seems off balance.  Both of these parameters can be adjusted in game as well by the squad leader speaking with the officer at a base.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of vehicles</font color> This options changes the 'ticket rate' for the ai vehicles which can speed up or slow down the spawning of more powerful vehicles by the ai on both sides.  This will adjust the difficulty and the pacing of the game.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of PLANES</font color> This options changes the 'ticket rate' for the attack jets which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above.  This can also be used to disable all attack planes, or all attack/transport planes.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of HELICOPTERS</font color> This options changes the 'ticket rate' for the attack helicopters which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above. This can also be used to disable all attack helicopters, or all attack/transport helicopters.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of TANKS</font color> This options changes the 'ticket rate' for the attack tanks which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above. This can also be used to disable all attack tanks, or all attack/transport tanks.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of APCS</font color> This options changes the 'ticket rate' for the attack APCs which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above. This can also be used to disable all attack APCs, or all attack/transport APCs.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of TRUCKS/CARS</font color> This options changes the 'ticket rate' for the attack trucks/cars which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above. This can also be used to disable all attack trucks, or all attack/transport trucks.<br/>
<br/>
<font color='#FFAAAA'>Adjust amount of SHIPS</font color> This options changes the 'ticket rate' for the attack ships which can speed up or slow down the spawning of these powerful vehicles by the ai on both sides.  This is combined with the 'amount of vehicles' parameter above. This can also be used to disable all attack ships, or all attack/transport ships.<br/>
<br/>
<font color='#FFAAAA'>Air drop vehicles</font color> The mission will air drop land vehicles (cars,trucks,apcs,tanks) if no land route is available.  With this option you can enable/disable this feature<br/>
<br/>
<font color='#FFAAAA'>AI planes without airfields</font color> The mission doesn't allow the AI to use planes/jets unless that side has captured and airfield.  With this option you can enable/disable this feature<br/>
<br/>
<font color='#FFAAAA'>AI transport despawn</font color> The mission will have ai transport vehicles return to their base after unloading infantry.  To improve performance, you can disable this feature which will just delete the transport vehicle as soon as the infantry has unloaded.<br/>
"]];

player createDiaryRecord ["ITW", ["Parameters - Objectives",
"<font color='#FFAAAA'>Objectives Count</font color> How many objective points there are in the game.  This parameter has the option to <font color='#FFD68A'>Let me choose my own locations</font> which, on starting a new game, will allow you to choose all the objective locations on the map.<br/>
<br/>
<font color='#FFAAAA'>Objective per zone</font color> How many objectives there are in each zone.  All these objectives must be captured to advance to the next zone.<br/>
<br/>
<font color='#FFAAAA'>Objective Size</font color> Size of objectives (ranges from 200n to 500m diameter)<br/>
<br/>
<font color='#FFAAAA'>Objective Capture Speed</font color> How fast the objectives are captured.  Each setting is a little less than double the previous level.<br/>
<br/>
<font color='#FFAAAA'>Objectives visible in 3D</font color> Determines if the 'attack task' symbol should show on the players hud or not.  The currently contested objective tasks will always show on the map.<br/>
<br/>
<font color='#FFAAAA'>Extra Buildings</font color> This options will cause extra buildings to be added to the zones if needed.  Only a few will be added if requested, and only if there are not a few buildings already there.  This adds a bit of cover in zones that were found that don't have quite enough.<br/>
<br/>
<font color='#FFAAAA'>Approximate number of infantry on each side</font color> This will determine how many ai are on the map at once.  If the game starts to lag or your fps drops too much, lower this number.<br/>
<br/>
<font color='#FFAAAA'>AI missile launchers</font color> This options adjusts how many of the ai on both sides carry missile launchers.  This will change the difficulty when players are using vehicles.<br/>
<br/>
<font color='#FFAAAA'>Minefields</font color> This options allows there to be minefields around the contested objectives.<br/>
<br/>
<font color='#FFAAAA'>AI Artillery</font color> This option controls whether AI will drop artillery shells into the battle.  When enabled, each side will have artillery that recharges at the chosen rate (give or take 50%).  When fired, it will target enemy that side knows about.  It will not with perfect accuracy and will have a delay before arriving.<br/>
<br/>
<font color='#FFAAAA'>Statics</font color> This options allows there to be static weapons around the contested objectives.<br/>
<br/>
<font color='#FFAAAA'>Garrison</font color> This options allows the AI infantry to garrison into buildings in the contested objectives.  AI is not as good at clearing buildings so the players may need to flush out the garrisoned units.<br/>
"]];

player createDiaryRecord ["ITW", ["Parameters - New Game",
"<font color='#FFAAAA'>Force a new game</font color> This parameter you to discard the save game and start a new one.<br/> 
<br/>
* Saved games are specific to each map.  So you can have a game going on Altis, and start a new game on Malden without losing your Altis game.<br/>
* Game is automatically saved whenever the players advance to the next zone.<br/>
* Game is automatically saved every 10 minutes<br/>
* Game can be manually saved at the officer in any base<br/>
* Saved game is erased once the game is won.<br/>
* Save game includes:<br/>
** factions and selected DLC (if appropriate)<br/>
** objective information: locations, objective captured, state of contested objectives (blue or red)<br/>
** player deployed airfield location<br/>
** teammates on players squad<br/>
** time of day<br/>
** vehicle chooser/ garage selected vehicles<br/>
<br/>
Many parameters are not part of a save and can be adjusted when loading a new save, but some are only set at time of a new game.
<br/>
"]];

_diaryResources = player createDiaryRecord ["ITW", ["Features",
"<font color='#FFAAAA'>Save Game:</font color>  The game is automatically saved after each zone is captured.  The save includes where objectives are located, which zones have been captured, which contested objectives are owned by the players, and the player loadouts.  Winning (capturing the whole island) will remove the saved game.  You can also force a new game in the parameters.  You can also save partial progress (which objectives are blue) at any time at the officer at any base.<br/>
<br/>
<font color='#FFAAAA'>Allies:</font color> You have squads of allied AI.  They will spawn at your captured zones and head to the contested objectives utilizing vehicles as are available.  You can adjust which objectives they prioritize and land routes they use by using the radio (0-8-5).  If you get knocked unconscious while allies are nearby, they should come revive you.<br/>
<br/>
<font color='#FFAAAA'>Teammates:</font color> Additional teammates can join your squad (option available at the officer at any of your bases).  These teammates will revive any player or other teammate nearby.  They will follow the squad leader and are controllable as normal in Arma.  They have an additional feature in that they can follow a specific player if requested (use the action menu on the AI).<br/>
<br/>
Following will cause the AI to keep a couple dozen meters behind the player.  The AI will enter/exit vehicles that the player gets in/out of.  The AI will copy the player's stance as well.  This allows players to split off from the group (to do recon or sniping for instance) and still have a teammate to help revive them.  The squad leader can recall the following AI by issuing a 'regroup' command.<br/>
<br/>
<font color='#FFAAAA'>Supports:</font color> A few supports are available from the supports menu. (0-8 on the keys above the keyboard, not the number pad.)  Supports include<br/>
* Supply drop - air drop a virtual arsenal<br/>
* Flares drop - drop flares for about 10 minutes within 80m of the designated location<br/>
* Artillery<br/>
* CAS bomber or heli<br/>
* Heli extract<br/>
* Ground Vehicle (extract and/or deliver AI teammates)<br/>
* Air drop vehicle<br/>
* Scan the zone for life signs<br/>
* Show or Hide group icons on the map<br/>
<br/>
<font color='#FFAAAA'>Leadership Options</font color> You have a few leadership options available at the officer at any of your bases. These include <br/>
* request/relinquish leadership                                                             <br/>
* recruit squad mates                                                                       <br/>
* split/join player groups                                                                  <br/>
* adjust number of friendly vs enemy units and vehicles                                     <br/>
* recall ai squads (deletes them and allows them to be respawned at better location)        <br/>
* skip time                                                                                 <br/>
* clean up dead units                                                                       <br/>
* save game, the game saves every 10 minutes and whenever the players advanced to a new zone<br/>
<br/>
<font color='#FFAAAA'>Pausing</font color> If playing the game solo, with only one player who is hosting, there will be a <font color='#FFD68A'>pause game</font color> option added to the players action menu (mouse wheel) when not in a vehicle.   A useful feature for bathroom breaks or answering phone calls.<br/>
<br/>
<font color='#FFAAAA'>Airfield</font color> You can place a player garage at an airfield.  Talk to the mechanic (near the repair point) to get an airfield crate, get it to an airfield, and deploy it.  You'll get a fast travel point, and a garage to spawn planes that the players can fly.<br/>
<br/>
<font color='#FFAAAA'>AI Airfields</font color> AI can launch jets if they have captured and airfield.  Airfields will be marked with who owns them.  Unmarked airfields are in the contested area.  Sometime jets can spawn even when AI don't own the airfield.  This can happen when jets are being used as a substitute for helicopters if the faction doesn't have any helicopters of the variety needed.  There is a parameter to allow ai to use aircraft even if they don't own an airfield<br/>"]];

player createDiaryRecord ["ITW", ["Mission Overview",
"<font color='#FFAAAA'>Impasse Total War</font color> is a randomly generated persistent capture the island mission broken up into zones that are fought over sequentially.  Vehicles play a big part in the warfare.<br/>
<br/>
<font color='#FFAAAA'>Features:</font color><br/>
* solo or coop team play<br/>
* ai engage each other using infantry, land vehicles, aircraft, ships<br/>
* virtual garage is available to the players<br/>
* choose any factions<br/>
* save game feature<br/>
* virtual arsenal<br/>
* friendly AI squad and teammates that can revive the players and each other<br/>
* many adjustable parameters to suit the game to your liking<br/>
* the mission can be instantly moved to any map just by changing the pbo filename<br/>
<br/>
Having more friendlies in the area than enemy will capture the flag.  It will go faster the larger the difference.
"]];

player createDiarySubject ["Map Legend","Map Legend"];
player createDiaryRecord ["Map Legend",
"<img image='\A3\ui_f\data\map\markers\nato\b_inf.paa'      width='64' height='64'/><br/>Infantry<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_motor_inf.paa' width='64' height='64'/><br/>Motorized Infantry (lightly armored vehicle)<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_mech_inf.paa'  width='64' height='64'/><br/>Mechanized Infantry (armored vehicle)<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_armor.paa'     width='64' height='64'/><br/>Armor (tank)<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_air.paa'       width='64' height='64'/><br/>Helicopter<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_plane.paa'     width='64' height='64'/><br/>Plane<br/><br/>
<img image='\A3\ui_f\data\map\markers\nato\b_naval.paa'      width='64' height='64'/><br/>Ship
"];

player createDiaryRecord ["Diary", ["Mission brief",
format [" Country:  %1<br/>",worldName]+
format [" Location:  %1<br/>",_aoText]+
format [" Enemy:  %1<br/>",ITW_AIEnemyName]+
"<br/>We've gotten a foothold on the island.  It's your job to push them completely off the island.<br/>
<br/>
The plan is for you to capture the island in zones.  Once captured, we can hold the zone leaving you to focus on capturing the next zone.<br/>
<br/>
Good luck.<br/>"
]];