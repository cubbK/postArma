/*
Title:  Sarogahtyps Simple Loot Spawner - SSLS V-1.0
Author: Sarogahtyp

Description:
Spawns weapons, items and bags in buildings near to alive players maybe inside a trigger area or marker area.
Deletes stuff if players are not close enough anymore.
The script doesnt care about any trigger preferences except the trigger area.
Main while loop runs every 8-12 seconds.
Soft delayed item spawning to prevent performance impact.

How to adjust/use the script: 
_trigger_array   ["string1", "string2", ...] or []
                 -> contains the names of triggers/markers in which area loot should spawn.
                 -> if empty then loot will spawn everywhere near players

_spawn_chance   number (0-100)
                ->  The chance to spawn loot inside of a specific house.
				-> value gets split into chance to spawn in a house and chance to spawn multiple items in it
				-> 100 means an average of 75% (50-100) for spawning in a house and
                   an average of 25% (0-50) for spawning on more than one spot in this house
				-> 40 would mean average 30% for spawning in a house and average 10% for spawning multiple
                -> the splitted values are randomized on each new loop run
				
_launcher_chance   number (0-100)
                   -> chance to spawn a launcher as weapon instead of rifle, pistol or machine gun
                   -> if this is set to e.g. 20 and items/bags to 0 then you ll get 80% guns and 20% launchers

_item_chance   number (0-100)
               -> chance to spawn an item instead of a launcher
               -> if launcher chance is 50 and item chance is 50 and bag chance is 0 then you will get
                  50% guns, 25% launchers, 25% items and 0% backpacks

_bag_chance   number (0-100)
              -> chance to spawn a bag/backpack instead of a item
              -> if launcher chance is 100 and item chance is 50 and bag chance is 50 then you will get
              -> 0% guns, 50% launchers, 25% items and 25% backpacks

_max_magazines   number (0-x)
                 -> the maximum number of magazines spawned for a gun

_max_magazines_launcher   number (0-x)
                          -> the maximum number of magazines spawned for a launcher

_max_magazines_gl   number (0-x)
                    -> the maximum number of magazines spawned for a grenade launcher

_house_distance   number (0-x)
                  -> houses inside of this radius of a player will spawn loot

_player_exclude_distance   number (0-x)
                           -> if 2 players or more are closer together than this then only 1 player is considered
                           -> loot will get deleted if the specific house is farther away than _house_distance + _player_exclude_distance

_exclude_loot   ["string1", "string2", ...] or []
                -> you can add classnames there and those stuff will never spawn

_exclusive_loot   ["string1", "string2", ...] or []
                  -> add classnames here and nothing else will be spawned

_use_bohemia_classes   boolean (true or false)
                       -> if true then vanilla stuff will get spawned.

_use_mod_classes   boolean (true or false)
                   -> if true then stuff of your mods will get spawned.

_debug   boolean (true or false)
         -> if true then u get hints about places were stuff was spawned or deleted and how many spawn places are active
*/

//***** EDIT BELOW TO ADJUST MAIN BEHAVIOR
// (L) means lower values are better for performance - (H) means the opposite

SSLS_script_switch_off = false;  //if you want to stop spawning loot then set this to true at any time in your mission

_trigger_array = [];  // contains the names of triggers/markers in which area loot should spawn.
_spawn_chance = 100; // (L) The chance to spawn loot inside of a specific house.
_launcher_chance = 30;  // chance to spawn a launcher as weapon instead of rifle, pistol or machine gun
_item_chance = 70;   // chance to spawn an item instead of a weapon
_bag_chance = 50; // chance to spawn a backpack instead of an item
_max_magazines = 7;    // the maximum number of magazines spawned for a gun
_max_magazines_launcher = 3; // maximum number of ammo to spawn for rocket launchers
_max_magazines_gl = 5; // maximum number of ammo to spawn for grenade launchers
_house_distance = 25;  // (L) houses with that distance to players will spawn loot
_player_exclude_distance = 15; //if 2 players or more are closer together than this then only 1 player is considered
_exclude_loot = []; //classnames of items which should never spawn (blacklist)
_exclusive_loot = []; //add classnames here and nothing else will be spawned (whitelist)
_use_bohemia_classes = true; // for spawning bohemia created stuff set this to true
_use_mod_classes = true; //// for spawning stuff from loaded mods set this to true
_debug = false;  //information about number of places where items were spawned or deleted

// if you have performance issues then consider introducing spawning areas (_trigger_array) before changing following values!
_spawn_interval = 1.5; // (H) desired runtime for the main loop. time which is not needed will be used for soft spawning or a break.

//***** EDIT ABOVE TO ADJUST MAIN BEHAVIOR


//***** init variables

_weapons_mags_array = [];
_launchers_mags_array = [];
_items_array = [];
_bags_array = [];
_exclusive_loot_bool = if ((count _exclusive_loot) > 0) then {true} else {false};

_use_bohemia_classes = if (_use_bohemia_classes || (!_use_bohemia_classes && !_use_mod_classes)) then {true} else {false};
_use_all_classes = if (_use_bohemia_classes && _use_mod_classes) then {true} else {false};

_box_classname = "WeaponHolderSimulated_Scripted";
_spawn_interval_rnd = _spawn_interval / 10;

_player_exclude_distance_sqr = _player_exclude_distance ^ 2;
_delete_distance_sqr = (_house_distance + _player_exclude_distance) ^ 2;
_house_distance = _house_distance + _player_exclude_distance;

if (_spawn_chance isEqualTo 0) exitWith {true};

//***** get weapon and magazine classnames from config file
_cfgWeapons = ("true" configClasses (configFile >> "cfgWeapons")) select
{
 _parents = [_x,true] call BIS_fnc_returnParents;
 _name = configName _x;

 (("Rifle" in _parents) or ("MGun" in _parents) or ("Pistol" in _parents)) and 
 {!(_name in _exclude_loot) and (getNumber (_x >> 'scope') > 1) and (!_exclusive_loot_bool or (_name in _exclusive_loot)) and 
 {(_use_bohemia_classes and ((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or (_use_mod_classes and !((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or _use_all_classes}}
}; 

{
 _weaponString = configName (_x);
 _muzzle_class = (getArray (configFile >> "CfgWeapons" >> _weaponString >> "muzzles")) select 1;
 _muzzle_magazines = [];
  
 if !(isNil {_muzzle_class}) then
 {	
  _muzzle_magazines = getArray (configFile >> "CfgWeapons" >> _weaponString >> _muzzle_class >> "magazines")
 };

 _d = _weapons_mags_array pushBack [_weaponString, (getArray (configFile >> "CfgWeapons" >> _weaponString >> "magazines")), _muzzle_magazines];
  
} count _cfgWeapons;


//***** get launchers and rocket/grenade classnames from config file
if (_launcher_chance > 0) then
{
 // filter for valid launcher configs
 _cfgLaunchers = ("true" configClasses (configFile >> "cfgWeapons")) select
 {
  _parents = [_x,true] call BIS_fnc_returnParents; 
  _name = configName _x;
  ("Launcher" in _parents) and {!(_name in _exclude_loot) and (getNumber (_x >> 'scope') > 1) and (!_exclusive_loot_bool or (_name in _exclusive_loot)) and 
  {(_use_bohemia_classes and ((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or (_use_mod_classes and !((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or _use_all_classes}}
 }; 

 // build classname array of launchers together with its magazines
 {
  _launcherString = configName (_x);
  _d = _launchers_mags_array pushBack [_launcherString, (getArray (configFile >> "CfgWeapons" >> _launcherString >> "magazines"))];
 } count _cfgLaunchers;
};

//*****get items classnames from config file
if (_item_chance > 0) then
{
 _cfgItems = ("true" configClasses (configFile >> "cfgWeapons")) 
 select
 {
  _parents = [_x,true] call BIS_fnc_returnParents;
  _name = configName _x;
  ("ItemCore" in _parents) and {!(_name in _exclude_loot) and (getNumber (_x >> 'scope') > 1) and (!_exclusive_loot_bool or (_name in _exclusive_loot)) and 
  {(_use_bohemia_classes and ((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or (_use_mod_classes and !((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or _use_all_classes}}
 } apply {configName _x};
  
 _items_array = _cfgItems;
};

//*****get bag classnames from config file
if (_bag_chance > 0) then
{
 _cfgBags = ("true" configClasses (configFile >> "cfgVehicles")) select
 {
  _parents = [_x,true] call BIS_fnc_returnParents;
  _name = configName _x;
  ("Bag_Base" in _parents) and {!(_name in _exclude_loot) and (getNumber (_x >> 'scope') > 1) and (!_exclusive_loot_bool or (_name in _exclusive_loot)) and 
  {(_use_bohemia_classes and ((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or (_use_mod_classes and !((getText (_x >> 'author')) isEqualTo "Bohemia Interactive")) or _use_all_classes}}
 } apply {configName _x}; 

 _bags_array = _cfgBags;
};

[_trigger_array, _house_distance, _debug, _box_classname, _item_chance, 
 _launcher_chance, _weapons_mags_array, _max_magazines, _launchers_mags_array, _max_magazines_launcher, 
 _bag_chance, _items_array, _bags_array, _spawn_interval, _spawn_interval_rnd, _max_magazines_gl, 
 _spawn_chance, _player_exclude_distance_sqr, _delete_distance_sqr] spawn
{
 params ["_trigger_array", "_house_distance", "_debug", "_box_classname",
		 "_item_chance", "_launcher_chance", "_weapons_mags_array", "_max_magazines", "_launchers_mags_array",
         "_max_magazines_launcher", "_bag_chance", "_items_array", "_bags_array", "_spawn_interval",
		 "_spawn_interval_rnd", "_max_magazines_gl", "_spawn_chance", "_player_exclude_distance_sqr",
		 "_delete_distance_sqr"];
 

 _houses_delete = [];
 _last_houses_in_area = [];
 _houses_spawned = [];
 _houses_now_in_area = [];
 _houses_spawn_new = [];
  
 _timefull = 0;
 _sol_1_time = 0;
 _last_time = diag_tickTime;
 _time_before = _last_time;
 
 while {!SSLS_script_switch_off} do
 {
  // split spawn chance into spawning and multiple spawning chance
  _rnd_house = random (_spawn_chance * 0.5);
  _spawn_chance_rnd = _spawn_chance * 0.5 + _rnd_house;
  _house_multiple_chance = _spawn_chance - _spawn_chance_rnd;
  
  _houses_now_in_area = [];
  _houses_spawn_new = [];
  
  _loot_players = [];
  _justPlayers = (allPlayers - entities "HeadlessClient_F") select {alive _x && isNull objectParent _x};
//  _justPlayers append allUnits;  // can be used to test script with AI
  _justPlayers2 = [];
  
  //***** get desired spawn positions for loot in the buildings close to players
  //***** which are inside of a loot trigger area
  if(count _trigger_array > 0) then
  {
   {
    _d =
    {
     _d = _loot_players pushBack _x;
    } count (_justPlayers inAreaArray _x);
   } count _trigger_array;
  }
  else
  {
   _loot_players = _justPlayers;
  };
 
  _sol_1_start = diag_tickTime;
 
  {
   _plyr = _x;
   if ( _justPlayers2 findIf {(_x distanceSqr _plyr) < _player_exclude_distance_sqr} < 0) then
   {
    _d = _justPlayers2 pushBack _plyr;
   };
  } count _loot_players;

  _loot_players = _justPlayers2;
 
  _active_houses = [];

  { _d =
   {
     if ((random 100) < _spawn_chance_rnd && {!(_x in _last_houses_in_area)}) then
	 {
      _d = _houses_spawn_new pushBackUnique _x;         // houses where new items will spawned
	  _d = _houses_spawned pushBackUnique _x;      // houses with already (and newly) spawned items
	 };
	 _d = _houses_now_in_area pushBackUnique _x;     // houses which are in area now but were not before
   } count nearestObjects [_x, ["house"], _house_distance];
  }count _loot_players;
  
  _last_houses_in_area = _houses_now_in_area;  // remember actual houses for next while run

  _houses_delete = (_houses_spawned - _houses_now_in_area) select  // delete inside of all houses which are not in area anymore
  {
   _house = _x; 
   _loot_players findIf {_house distanceSqr _x < _delete_distance_sqr} < 0
  };

  _houses_spawned = _houses_spawned - _houses_delete; // deleted houses have no spawned stuff anymore

  [_houses_delete, _box_classname] spawn
  {
   params ["_houses_delete", "_box_classname"];
 // delete all stuff inside of all houses marked for deletion
  { _d =
   { _d=
    {
     deleteVehicle _x;
    } count (nearestObjects [_x, [_box_classname], 2]);
   } count (_x buildingPos -1);
  } count _houses_delete;
  };
  //***** try to spawn loot within specified time (delay to prevent performance impact)

  _new_house_num = count _houses_spawn_new;
  _sol_1_time = diag_tickTime - _sol_1_start;
  
  // debug things
  if(_debug) then
  {
   _spawned_num = count _houses_spawned;
   _in_area_num = count _houses_now_in_area;
   _del_house_num = count _houses_delete;

   _time_act = diag_tickTime;
   _runtime = _time_act - _time_before;
   _time_before = _time_act;
   
   hint parseText format ["houses where new loot is spawned<br />houses where all loot got deleted<br />new h.: %1, del h.: %2<br /><br />
   houses where stuff is inside<br />houses which are in range of a player<br />spawned h.: %3, h. in area: %4<br /><br />
   players on server<br />players which are used for spawning<br />players: %5, watched pl.: %6<br /><br />
   runtime of the code which does not spawn<br />full runtime<br />sol1: %7, runtime: %8<br /><br />
   chance to spawn in a house<br />chance to spawn on multiple spots in a house<br />h.chance = %9%%, mult. ch. = %10%%",
   _new_house_num, _del_house_num, _spawned_num, _in_area_num, (count _justPlayers), (count _loot_players), _sol_1_time, _runtime, _spawn_chance_rnd, _house_multiple_chance];
  };

   _curr_time = diag_tickTime;
   _timefull = _curr_time - _last_time;
   _break_time = _spawn_interval + (random _spawn_interval_rnd) - _timefull;
   _break_time = if (_break_time > 0) then {_break_time} else {0};

  if (_new_house_num > 0) then
  {
   _sleep_delay = _break_time / (_new_house_num + _house_multiple_chance * _new_house_num * 0.01);
   {
    _pos_array = _x buildingPos -1;
    _pos_num = count _pos_array;
	
    while {_pos_num > 0} do
    {
     _pos = selectRandom _pos_array;
     _pos_array = _pos_array - _pos;
     _pos_num = _pos_num - 1;

     _position = _pos vectorAdd [0, 0, 0.2];
	
     _itembox = createVehicle [_box_classname, _position, [], 0.2, "NONE"];
   
     if (random 100 > _item_chance) then
     {
      if(random 100 > _launcher_chance) then
      {
       _weapon_mag = selectRandom _weapons_mags_array;
       _itembox addItemCargoGlobal [(_weapon_mag select 0), 1];
    
       for "_i" from 1 to (ceil random _max_magazines) do 
       {
        _itembox addItemCargoGlobal [(selectRandom (_weapon_mag select 1)), 1];
       };
	 
	   if (count (_weapon_mag select 2) > 0) then
	   {
	    for "_i" from 1 to (ceil random _max_magazines_gl) do 
        {
         _itembox addItemCargoGlobal [(selectRandom (_weapon_mag select 2)), 1];
        };
	   };
      }
      else
      {
       _launcher_mag = selectRandom _launchers_mags_array;
       _itembox addItemCargoGlobal [(_launcher_mag select 0), 1];
    
       for "_i" from 1 to (ceil random _max_magazines_launcher) do 
       {
        _itembox addItemCargoGlobal [(selectRandom (_launcher_mag select 1)), 1];
       };
      };
     }
     else
     {
      if(random 100 > _bag_chance) then
      {
       _item = selectRandom _items_array;
       _itembox addItemCargoGlobal [_item, 1];
      }
      else
      {
       _backpack = selectRandom _bags_array;
       _itembox addBackpackCargoGlobal [_backpack, 1];
      };
     };

     if( random 100 >= _house_multiple_chance) then
     {
      _pos_num = 0;
     };

     sleep _sleep_delay;
    };
   } count _houses_spawn_new;
  }
  else
  {
   sleep _break_time;
  };
  _last_time = diag_tickTime;
 };
 
 _houses_delete append _houses_spawned;
 _houses_delete append _houses_now_in_area;
 _houses_delete append _houses_spawn_new;
  
 { _d=
  { _d=
   {
    deleteVehicle _x;
   } count (nearestObjects [_x, [_box_classname], 3]);
  } count (_x buildingPos -1);
 } count _houses_delete;
};