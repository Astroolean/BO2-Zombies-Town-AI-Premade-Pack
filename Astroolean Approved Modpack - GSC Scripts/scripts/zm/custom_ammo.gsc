// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  MULTI-PACK-A-PUNCH + ALTERNATE AMMO TYPES (AAT) + HUD                    ║
// ║  Black Ops II Zombies (Plutonium T6)                                      ║
// ║                                                                           ║
// ║  Created by: Astroolean                                                   ║
// ║                                                                           ║
// ║  What this file does                                                      ║
// ║   - Replaces the default Pack-a-Punch trigger with a custom trigger that  ║
// ║     supports upgrading weapons multiple times and adjusts the cost based  ║
// ║     on Bonfire Sale and whether the current weapon is already upgraded.   ║
// ║   - Preserves ammo/clip after upgrading so you don't get ammo wiped.      ║
// ║   - Adds Alternate Ammo Types (AAT) to upgraded weapons and routes zombie ║
// ║     damage through an AAT callback that randomly triggers effects:        ║
// ║       Thunder Wall · Fireworks · Turned · Cluster · Headcutter · Explosive║
// ║       Blast Furnace                                                       ║
// ║   - Shows the current weapon's AAT on the player's HUD.                   ║
// ║                                                                           ║
// ║  Compatibility / notes                                                    ║
// ║   - Mob of the Dead (zm_prison): player damage callback is skipped to     ║
// ║     avoid Afterlife conflicts.                                            ║
// ║   - AAT damage skips Turned allies and certain boss/special AIs.          ║
// ║   - This version is comment/structure focused; gameplay logic is intact.  ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

// ========================================================================== 
//  FILE LAYOUT (reading order)
//   1) Imports / includes
//   2) Entry points: main(), init()
//   3) Pack-a-Punch override + ammo restore
//   4) AAT router (zombie damage callback) + cooldowns
//   5) AAT implementations (Thunder Wall, Fireworks, Turned, etc.)
//   6) AAT assignment + HUD + safety filters
// ========================================================================== 
// --------------------------------------------------------------------------
// Imports / includes
// NOTE: This file intentionally keeps a broad include list for cross-map
//       compatibility. Removing includes can cause 'undefined function' errors
//       on certain maps/gametypes depending on what gets referenced at runtime.
// --------------------------------------------------------------------------
#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\gametypes_zm\_spawnlogic;
#include maps\mp\animscripts\traverse\shared;
#include maps\mp\animscripts\utility;
#include maps\mp\zombies\_load;
#include maps\mp\_createfx;
#include maps\mp\_music;
#include maps\mp\_busing;
#include maps\mp\_script_gen;
#include maps\mp\gametypes_zm\_globallogic_audio;
#include maps\mp\gametypes_zm\_tweakables;
#include maps\mp\_challenges;
#include maps\mp\gametypes_zm\_weapons;
#include maps\mp\_demo;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\gametypes_zm\_spawning;
#include maps\mp\gametypes_zm\_globallogic_utils;
#include maps\mp\gametypes_zm\_spectating;
#include maps\mp\gametypes_zm\_globallogic_spawn;
#include maps\mp\gametypes_zm\_globallogic_ui;
#include maps\mp\gametypes_zm\_hostmigration;
#include maps\mp\gametypes_zm\_globallogic_score;
#include maps\mp\gametypes_zm\_globallogic;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_ai_faller;
#include maps\mp\zombies\_zm_spawner;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include maps\mp\zombies\_zm_pers_upgrades;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\animscripts\zm_run;
#include maps\mp\animscripts\zm_death;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\animscripts\zm_shared;
#include maps\mp\animscripts\zm_utility;
#include maps\mp\zombies\_zm_ai_basic;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_net;
#include maps\mp\zombies\_zm_audio;
#include maps\mp\gametypes_zm\_zm_gametype;
#include maps\mp\_visionset_mgr;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_power;
#include maps\mp\zombies\_zm_server_throttle;
#include maps\mp\gametypes\_hud_util;
#include maps\mp\zombies\_zm_unitrigger;
#include maps\mp\zombies\_zm_zonemgr;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm_melee_weapon;
#include maps\mp\zombies\_zm_audio_announcer;
#include maps\mp\zombies\_zm_magicbox;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_ai_dogs;
#include maps\mp\zombies\_zm_game_module;
#include maps\mp\zombies\_zm_buildables;
#include codescripts\character;

// Specific weapon and map includes
#include maps\mp\zombies\_zm_weap_riotshield;
#include maps\mp\zombies\_zm_weap_riotshield_tomb;
#include maps\mp\zombies\_zm_weap_riotshield_prison;

#include maps\mp\zm_transit_bus;
#include maps\mp\zm_transit_utility;
#include maps\mp\zombies\_zm_equip_turret;
#include maps\mp\zombies\_zm_mgturret;
#include maps\mp\zombies\_zm_weap_jetgun;

#include maps\mp\zombies\_zm_ai_sloth;
#include maps\mp\zombies\_zm_ai_sloth_ffotd;
#include maps\mp\zombies\_zm_ai_sloth_utility;
#include maps\mp\zombies\_zm_ai_sloth_magicbox;
#include maps\mp\zombies\_zm_ai_sloth_crawler;
#include maps\mp\zombies\_zm_ai_sloth_buildables;

#include maps\mp\zombies\_zm_tombstone;
#include maps\mp\zombies\_zm_chugabud;

#include maps\mp\zm_nuked_perks;

// ========================================================================== 
//  SECTION: ENTRY POINTS
// ========================================================================== 

// --------------------------------------------------------------------------
// main()
// Script entry point (runs when this file is loaded).
// Registers the callback hooks that power the AAT system:
//  - Player damage callback (filters out damage caused by our spawned AAT entities).
//  - Zombie damage callback (randomly triggers AAT effects on eligible hits).
// Special-case: skips the player damage callback on Mob of the Dead (zm_prison) due to Afterlife.
// --------------------------------------------------------------------------
main()
{   
    // Hotfix: Disable player AAT damage response in "zm_prison" due to Afterlife incompatibility.
    // Moved to main from init for better loading in "Origins" map.
    if(getdvar("mapname") != "zm_prison")
        register_player_damage_callback( ::player_aat_damage_respond );

    // Register a callback for zombie damage to handle Alternate Ammo Types (AATs)
    maps\mp\zombies\_zm_spawner::register_zombie_damage_callback( ::aat_zombie_damage_response );
}

// --------------------------------------------------------------------------
// init()
// Game init (runs at match start).
//  - Hooks per-player startup via onplayerconnect_callback().
//  - Starts the custom Pack-a-Punch trigger thread.
//  - Overrides the point-of-interest function used for Turned zombies.
// --------------------------------------------------------------------------
init()
{
    // Register a callback to watch for weapon changes for each player
    onplayerconnect_callback( ::watch_weapon_changes ); 
    
    // Start the Pack-a-Punch trigger logic
    thread new_pap_trigger();
    // Override point of interest for turned zombies
    level._poi_override = ::turned_zombie;
}

// ========================================================================== 
//  SECTION: DAMAGE FILTERING / BASIC HELPERS
// ========================================================================== 

// --------------------------------------------------------------------------
// player_aat_damage_respond()
// Player damage callback used to prevent unintended damage/feedback loops from AAT helpers.
// Returns 0 to cancel damage when the attacker entity is one of our spawned AAT objects
// (cluster grenades / firework weapon model). Otherwise returns the original damage value.
// Params match the engine's register_player_damage_callback signature.
// --------------------------------------------------------------------------
player_aat_damage_respond( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, psoffsettime )
{
    players = get_players();
    for(i=0;i<players.size;i++)
    {
        if( isdefined(players[i].cluster_grenades) )
        {
            for(j=0;j<players[i].cluster_grenades.size;j++)
            {
                if( isdefined(players[i].cluster_grenades[j]) && eattacker == players[i].cluster_grenades[j] )
                    return 0;
            }
        }
        
        if( isdefined(players[i].firework_weapon) && eattacker == players[i].firework_weapon )
            return 0;
    }
    return idamage;
}

// --------------------------------------------------------------------------
// vector_scal()
// Small math helper: scales a 3D vector by a scalar (float).
// Used for long-distance traces (e.g., explosive bullet aim).
// --------------------------------------------------------------------------
vector_scal( vec, scale )
{
    vec = ( vec[ 0] * scale, vec[ 1] * scale, vec[ 2] * scale );
    return vec;
}

// ========================================================================== 
//  SECTION: PACK-A-PUNCH OVERRIDE
// ========================================================================== 

// --------------------------------------------------------------------------
// vending_weapon_upgrade_cost()
// Tracks the Bonfire Sale powerup state.
// Sets level._bonfire_sale while active so the PaP hint + cost can update on the fly.
// --------------------------------------------------------------------------
vending_weapon_upgrade_cost()
{
    level endon("end_game"); // End this thread if the game ends
    for( ;; ) // Loop indefinitely
    {
        level waittill( "powerup bonfire sale" ); // Wait for Bonfire Sale to start
        level._bonfire_sale = 1; // Activate Bonfire Sale flag
        level waittill( "bonfire_sale_off" ); // Wait for Bonfire Sale to end
        level._bonfire_sale = 0; // Deactivate Bonfire Sale flag
    }
}

// --------------------------------------------------------------------------
// pap_off()
// Maintains Pack-a-Punch on/off state notifications for maps/gametypes that expect it.
// This helps keep upstream PaP logic in sync while our custom trigger is active.
// --------------------------------------------------------------------------
pap_off()
{
    level endon("end_game"); // End this thread if the game ends
    wait 5; // Initial small delay
    for(;;) // Loop indefinitely
    {
        level waittill("Pack_A_Punch_on"); // Wait for PAP to be activated
        wait 1; // Small delay
        level notify("Pack_A_Punch_off"); // Notify that PAP is off (to prevent continuous use)
    }
}

// --------------------------------------------------------------------------
// new_pap_trigger()
// Replaces the map's default Pack-a-Punch trigger with a custom trigger_radius.
// Core responsibilities:
//  - Deletes the default PaP trigger entity so players interact with this one.
//  - Handles map-specific cases (Transit classic buildable, Nuketown timing, etc.).
//  - Validates weapon eligibility, charges points, runs the upgrade animation,
//    and then waits for the player to pick up the upgraded weapon.
//  - Restores ammo/clip to preserve the player's previous ammo state after the swap.
//  - Adjusts cost based on Bonfire Sale and whether the weapon is already upgraded.
// --------------------------------------------------------------------------
new_pap_trigger()
{
    level endon("end_game"); // End this thread if the game ends
    thread vending_weapon_upgrade_cost(); // Start thread to manage Bonfire Sale cost
    level waittill("Pack_A_Punch_on"); // Wait for PAP power to be on
    wait 2; // Short delay after PAP is on
    
    // If not Transit map or not standard zombie gametype, manage PAP power state
    if(getdvar( "mapname" ) != "zm_transit" && getdvar ( "g_gametype") != "zstandard")
    {
        level notify("Pack_A_Punch_off");
        level thread pap_off();
    }

    // Specific logic for Nuketown Zombies (zm_nuked)
    if( getdvar( "mapname" ) == "zm_nuked" )
        level waittill( "Pack_A_Punch_on" ); // Wait for PAP to be on again (might be redundant depending on setup)
    
    // Get the Pack-a-Punch machine entity and its default triggers
    perk_machine = getent( "vending_packapunch", "targetname" );
    if (!isdefined(perk_machine))
        return;

    pap_triggers = getentarray( "specialty_weapupgrade", "script_noteworthy" );
    if (isdefined(pap_triggers) && pap_triggers.size > 0)
        pap_triggers[0] delete(); // Delete the default Pack-a-Punch trigger

    // If Transit Classic, wait for PAP buildable to be constructed
    if( getdvar( "mapname" ) == "zm_transit" && getdvar ( "g_gametype")  == "zclassic" )
    {
        if(!level.buildables_built[ "pap" ])
            level waittill("pap_built");
    }
    wait 1; // Small delay

    // Assign perk_machine to self (which is the trigger entity in this context)
    self.perk_machine = perk_machine;
    perk_machine_sound = getentarray( "perksacola", "targetname" ); // Not used, can be removed or used for sound

    // Create origins for visual effects or timing related to the PAP machine
    packa_rollers = spawn( "script_origin", perk_machine.origin );
    packa_timer = spawn( "script_origin", perk_machine.origin );
    packa_rollers linkto( perk_machine );
    packa_timer linkto( perk_machine );

    // Determine trigger size based on map
    if( getdvar( "mapname" ) == "zm_highrise" )
    {
        Trigger = spawn( "trigger_radius", perk_machine.origin, 1, 60, 80 );
        Trigger enableLinkTo();
        Trigger linkto(self.perk_machine);
    }
    else
        Trigger = spawn( "trigger_radius", perk_machine.origin, 1, 35, 80 );
    
    // Set cursor hint for the trigger
    Trigger SetCursorHint( "HINT_NOICON" );
    Trigger sethintstring( "             Hold ^3&&1^7 for Pack-a-Punch [Cost: 5000] \n Weapons can be pack a punched multiple times" );
    
    cost = 5000; // Default Pack-a-Punch cost

    Trigger usetriggerrequirelookat(); // Player must be looking at the trigger to use it
    for(;;) // Loop indefinitely for player interaction
    {
        Trigger waittill("trigger", player); // Wait for a player to activate the trigger
        current_weapon = player getcurrentweapon();

        // Check for weapons that cannot be upgraded
        if(current_weapon == "saritch_upgraded_zm+dualoptic" || current_weapon == "dualoptic_saritch_upgraded_zm+dualoptic" || current_weapon == "slowgun_upgraded_zm" || current_weapon == "staff_air_zm" || current_weapon == "staff_lightning_zm" || current_weapon == "staff_fire_zm" || current_weapon == "staff_water_zm" )
        {
            Trigger sethintstring( "^1This weapon can not be upgraded." );
            wait .05;
            continue; // Skip to next iteration if weapon cannot be upgraded
        }
        
        // Check if player can afford and use Pack-a-Punch
        if(player UseButtonPressed() && player.score >= cost && current_weapon != "riotshield_zm" && player can_buy_weapon() && !player.is_drinking && !is_placeable_mine( current_weapon ) && !is_equipment( current_weapon ) && level.revive_tool != current_weapon && current_weapon != "none" )
        {
            player.score -= cost; // Deduct cost from player's score
            player thread maps\mp\zombies\_zm_audio::play_jingle_or_stinger( "mus_perks_packa_sting" ); // Play Pack-a-Punch jingle
            trigger setinvisibletoall(); // Hide the trigger during the upgrade process

            upgrade_as_attachment = will_upgrade_weapon_as_attachment( current_weapon ); // Determine upgrade type
            
            // Store current ammo and clip data for restoration
            player.restore_ammo = undefined; // Flag to indicate if ammo needs restoration
            player.restore_clip = undefined;
            player.restore_stock = undefined;
            player.restore_clip_size = undefined;
            player.restore_max = undefined;
            
            player.restore_clip = player getweaponammoclip( current_weapon );
            player.restore_clip_size = weaponclipsize( current_weapon );
            player.restore_stock = player getweaponammostock( current_weapon );
            player.restore_max = weaponmaxammo( current_weapon );
            
            player thread maps\mp\zombies\_zm_perks::do_knuckle_crack(); // Play knuckle crack animation
            wait .1; // Small delay
            player takeWeapon(current_weapon); // Take current weapon from player
            current_weapon = player maps\mp\zombies\_zm_weapons::switch_from_alt_weapon( current_weapon ); // Handle alternate weapon forms
            
            self.current_weapon = current_weapon; // Store weapon on the trigger (for timeout logic)
            upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon( current_weapon, upgrade_as_attachment ); // Get upgraded weapon name
            
            // Perform third-person weapon upgrade animation
            player third_person_weapon_upgrade( current_weapon, upgrade_name, packa_rollers, perk_machine, self );
            
            trigger sethintstring( &"ZOMBIE_GET_UPGRADED" ); // Update hint string
            // Start waiting for the player to pick up the upgraded weapon
            trigger thread wait_for_pick(player, current_weapon, upgrade_name);

            if ( isDefined( player ) ) // Ensure player is still defined
            {
                Trigger setinvisibletoall(); // Hide for all except the interacting player
                Trigger setvisibletoplayer( player );
            }
            // Start timeout for picking up the weapon
            self thread wait_for_timeout( current_weapon, packa_timer, player );
            // Wait until weapon is taken, times out, or player disconnects
            self waittill_any( "pap_timeout", "pap_taken", "pap_player_disconnected" );
            self.current_weapon = ""; // Clear weapon reference

            // Clean up world models if they exist
            if ( isDefined( self.worldgun ) && isDefined( self.worldgun.worldgundw ) )
                self.worldgun.worldgundw delete();
            
            if ( isDefined( self.worldgun ) )
                self.worldgun delete();
            
            Trigger setinvisibletoplayer( player ); // Hide trigger from the player
            wait 1.5; // Short delay
            Trigger setvisibletoall(); // Make trigger visible again to all players
                
            self.current_weapon = ""; // Clear weapon reference again
            self.pack_player = undefined; // Clear player reference
            flag_clear( "pack_machine_in_use" ); // Clear machine in use flag
        }
        // Update cost hint based on Bonfire Sale or if weapon is already upgraded
        weapon = player getcurrentweapon();
        if(isdefined(level._bonfire_sale) && level._bonfire_sale)
        {
            Trigger sethintstring( "             Hold ^3&&1^7 for Pack-a-Punch [Cost: 1000] \n Weapons can be pack a punched multiple times" );
            cost = 1000;
        }
        else if(is_weapon_upgraded(weapon))
        {
            Trigger sethintstring( "             Hold ^3&&1^7 for Pack-a-Punch [Cost: 2500] \n Weapons can be pack a punched multiple times" );
            cost = 2500;
        }
        else
        {
            Trigger sethintstring( "             Hold ^3&&1^7 for Pack-a-Punch [Cost: 5000] \n Weapons can be pack a punched multiple times" );
            cost = 5000;
        }
        wait .1; // Small delay before next loop iteration
    }
}

// --------------------------------------------------------------------------
// wait_for_pick()
// Pickup handler for the custom PaP process.
// Waits for the same player to press Use again, then:
//  - Gives the upgraded weapon (or re-gives special upgraded bases).
//  - Optionally assigns an AAT (when re-upgrading an already-upgraded weapon).
//  - Restores clip/stock ammo based on the saved values from new_pap_trigger().
//  - Notifies 'pap_taken' so the PaP machine can reset/clean up.
// --------------------------------------------------------------------------
wait_for_pick(player, original_weapon, upgrade_weapon)
{
    level endon( "pap_timeout" );
    level endon("end_game");
    for (;;) // Loop indefinitely until weapon is picked
    {
        self playloopsound( "zmb_perks_packa_ticktock" ); // Play ticking sound
        self waittill( "trigger", user ); // Wait for a player to trigger
        if(user UseButtonPressed() && player == user) // If the same player presses use button
        {   
            self stoploopsound( 0.05 ); // Stop ticking sound
            player thread do_player_general_vox( "general", "pap_arm2", 15, 100 ); // Play player voice line

            base = get_base_name(original_weapon);
            // Special handling for specific upgraded weapons that get AAT immediately
            if( base == "galil_upgraded_zm" || base == "fnfal_upgraded_zm" || base == "ak74u_upgraded_zm" )
            {
                player.restore_ammo = 1; // Flag for ammo restoration
                player thread give_aat(original_weapon); // Give AAT to the original weapon (already upgraded)
                player giveweapon( original_weapon, 0, player maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options( original_weapon ));
                player switchToWeapon( original_weapon );
                x = original_weapon; // Set 'x' to the weapon for ammo restoration
            }
            else // For all other weapons
            {
                if(is_weapon_upgraded( original_weapon )) // If the weapon was already upgraded once
                {
                    player.restore_ammo = 1; // Flag for ammo restoration
                    player thread give_aat(upgrade_weapon); // Give AAT to the newly upgraded weapon
                }
                weapon_limit = get_player_weapon_limit( player );
                player maps\mp\zombies\_zm_weapons::take_fallback_weapon(); // Take fallback weapon if needed
                primaries = player getweaponslistprimaries();
                
                // Give the upgraded weapon to the player
                if ( isDefined( primaries ) && primaries.size >= weapon_limit )
                    player maps\mp\zombies\_zm_weapons::weapon_give( upgrade_weapon );
                else
                    player giveweapon( upgrade_weapon, 0, player maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options( upgrade_weapon ));

                player switchToWeapon( upgrade_weapon ); // Switch to the new weapon
                x = upgrade_weapon; // Set 'x' to the weapon for ammo restoration
            }

            // Restore ammo and clip based on previous state
            if ( isDefined( player.restore_ammo ) && player.restore_ammo )
            {
                new_clip = player.restore_clip + ( weaponclipsize( x ) - player.restore_clip_size );
                new_stock = player.restore_stock + ( weaponmaxammo( x ) - player.restore_max );
                player setweaponammostock( x, new_stock );
                player setweaponammoclip( x, new_clip );
            }
            level notify( "pap_taken" ); // Notify that PAP weapon was taken
            player notify( "pap_taken" ); // Notify player specifically
            break; // Exit the loop
        }
        wait .1; // Small delay before next loop iteration
    }
}

// ========================================================================== 
//  SECTION: AAT ROUTER + COOLDOWNS
// ========================================================================== 

// --------------------------------------------------------------------------
// aat_zombie_damage_response()
// Zombie damage callback (runs on the zombie AI being hit).
// Routes eligible hits through the attacker's per-weapon AAT assignment and,
// if off cooldown, randomly triggers one of the AAT effects.
// Returns 1 when an AAT effect is applied; otherwise returns 0.
// --------------------------------------------------------------------------
aat_zombie_damage_response( mod, hit_location, hit_origin, attacker, amount )
{
    if(!can_aat_damage(self))
        return 0;

    if(!isdefined(attacker) || !isplayer(attacker))
        return 0;

    if(!isDefined(attacker.aat_cooldown))
        attacker.aat_cooldown = 0;

    if(!isdefined(attacker.aat))
        return 0;
    
    if(isdefined( self.damageweapon ))
    {
        if(!attacker.aat_cooldown && isdefined(attacker.aat[self.damageweapon]))
        {
            zombies = getaiarray( level.zombie_team ); // Get all zombies on the zombie team

            // Turned AAT - ~25% chance to trigger
            if(randomint(100) >= 75 && self turned_zombie_validation() && !attacker.active_turned && attacker.aat[self.damageweapon] == "Turned")
            {
                attacker thread Cooldown("Turned"); // Start cooldown for "Turned" AAT
                self thread turned( attacker ); // Turn the zombie
                return 1; // Indicate AAT applied
            }
            // Cluster AAT - ~20% chance to trigger
            if(randomint(100) >= 80 && attacker.aat[self.damageweapon] == "Cluster")
            {
                attacker thread Cooldown("Cluster"); // Start cooldown for "Cluster" AAT
                self thread cluster( attacker ); // Spawn cluster grenades
                return 1; // Indicate AAT applied
            }
            // Headcutter AAT - ~30% chance to trigger
            if(randomint(100) >= 70 && attacker.aat[self.damageweapon] == "Headcutter")
            {
                attacker thread Cooldown("Headcutter"); // Start cooldown for "Headcutter" AAT
                // Affects zombies within 250 units (increased from 200)
                for( i=0; i < zombies.size; i++ )
                {
                    if(distance(self.origin, zombies[i].origin) <= 250) // Check proximity
                    {
                        if((!isdefined(zombies[i].done) || !zombies[i].done) && can_aat_damage(zombies[i])) // Ensure zombie hasn't been processed and can be damaged
                        {
                            zombies[i].done = 1; // Mark as processed for this AAT trigger
                            zombies[i] thread headcutter_wrapper(attacker); // Apply Headcutter effect
                        }
                    }
                }
                return 1; // Indicate AAT applied
            }
            // Thunder Wall AAT - ~20% chance to trigger
            if(randomint(100) >= 80 && attacker.aat[self.damageweapon] == "Thunder Wall")
            {
                attacker setclientdvar( "ragdoll_enable", 1); // Enable ragdoll (client-side)
                self thread thunderwall(attacker); // Apply Thunder Wall effect
                attacker thread Cooldown("Thunder Wall"); // Start cooldown
                return 1;              
            }
            // Blast Furnace AAT - ~25% chance to trigger
            if(randomint(100) >= 75 && attacker.aat[self.damageweapon] == "Blast Furnace")
            {
                attacker thread Cooldown("Blast Furnace"); // Start cooldown
                PlayFXOnTag(level._effect[ "character_fire_death_torso" ], self, "j_spinelower"); // Play fire effects
                PlayFXOnTag(level._effect[ "character_fire_death_sm" ], self, "j_spineupper");
                // Affects zombies within 250 units (increased from 220)
                for( i = 0; i < zombies.size; i++ )
                {
                    if(distance(self.origin, zombies[i].origin) <= 250 && can_aat_damage(zombies[i])) // Check proximity and if damageable
                        zombies[i] thread flames_fx(attacker); // Apply flames effect
                }
                return 1; // Indicate AAT applied
            }
            // Fireworks AAT - ~20% chance to trigger
            if(randomint(100) >= 80 && attacker.aat[self.damageweapon] == "Fireworks")
            {
                attacker thread Cooldown("Fireworks"); // Start cooldown
                self thread spawn_weapon( attacker ); // Spawn a weapon for the fireworks
                self thread fireworks(); // Play fireworks effects
                return 1; // Indicate AAT applied
            }
            // Explosive AAT (no trigger chance here, as it's handled by weapon_fired event)
        }
    }
    return 0; // No AAT applied
}

// --------------------------------------------------------------------------
// Cooldown()
// Per-player AAT cooldown gate.
// Sets self.aat_cooldown for a randomized duration depending on the AAT type,
// preventing multiple procs back-to-back.
// --------------------------------------------------------------------------
Cooldown(aat)
{
    self endon("disconnect");
    cooldown_time = 0;

    self.aat_cooldown = 1;

    // Set specific cooldown times based on AAT type (adjusted for balance)
    if( aat == "Thunder Wall" )
        cooldown_time = randomintrange(10, 18); // Slightly tighter cooldown
    else if( aat == "Fireworks" )
        cooldown_time = randomintrange(10, 15); // Slightly tighter cooldown
    else if( aat == "Turned" )
        cooldown_time = randomintrange(12, 20); // Similar range
    else if( aat == "Cluster" )
        cooldown_time = randomintrange(10, 20); // Tighter top end
    else if( aat == "Headcutter" )
        cooldown_time = randomintrange(12, 20); // Similar range
    else if( aat == "Explosive" )
        cooldown_time = randomintrange(4, 12); // Slightly tighter cooldown, as it's single target burst
    else if( aat == "Blast Furnace" )
        cooldown_time = randomintrange(10, 18); // Slightly tighter cooldown
    
    wait cooldown_time; // Wait for the cooldown duration

    self.aat_cooldown = 0; // Reset cooldown flag to inactive
}

// ========================================================================== 
//  SECTION: AAT IMPLEMENTATIONS
// ========================================================================== 

// --------------------------------------------------------------------------
// explosive_bullet()
// AAT implementation: Explosive.
// Listens for the player's 'weapon_fired' event. When the current weapon has
// Explosive assigned and the player is off cooldown, it performs a bullettrace
// to find the impact point and applies an explosion + radius damage there.
// Note: brief invulnerability is toggled to avoid the player self-killing from the proc.
// --------------------------------------------------------------------------
explosive_bullet()
{
    level endon("end_game"); // End if game ends
    self endon("disconnect"); // End if player disconnects
    for( ;; ) // Loop indefinitely
    {
        self waittill( "weapon_fired", weapon ); // Wait for the player to fire a weapon

        // Determine explosion effect based on map
        if(getdvar("mapname") == "zm_tomb" || getdvar("mapname") == "zm_buried")
            fx = level._effect[ "divetonuke_groundhit" ];
        else
            fx = level._effect[ "def_explosion" ];

        // Check if AAT is "Explosive" and not on cooldown
        if(!self.aat_cooldown && isdefined(self.aat) && isdefined(self.aat[weapon]) && self.aat[weapon] == "Explosive")
        {
            self thread Cooldown("Explosive");
            
            // Calculate bullet trace for explosion origin
            forward = self gettagorigin( "tag_weapon_right" );
            aim_dir = anglestoforward( self getplayerangles() );
            end = forward + vector_scal( aim_dir, 1000000 );
            trace = bullettrace( forward, end, true, self );
            crosshair_entity = trace["entity"];
            crosshair = trace["position"];
            
            magicbullet( self getcurrentweapon(), self gettagorigin( "j_shouldertwist_le" ), crosshair, self );
            self enableInvulnerability();
            
            // Calculate dynamic damage based on round number
            explosive_damage = 2000 + (level.round_number * 300);
            if (explosive_damage > 20000) explosive_damage = 20000; 

            // Apply explosion effects and damage
            if(isdefined(crosshair_entity))
            {
                crosshair_entity playsound( "zmb_phdflop_explo" );
                playfx(fx, crosshair_entity.origin, anglestoforward( ( 0, 45, 55  ) ) );
                radiusdamage( crosshair_entity.origin, 350, explosive_damage, 1000, self );
            }
            else
            {
                // Use temp entity for sound since playsound requires an entity
                snd = spawn( "script_origin", crosshair );
                snd playsound( "zmb_phdflop_explo" );
                playfx(fx, crosshair, anglestoforward( ( 0, 45, 55  ) ) );
                radiusdamage( crosshair, 350, explosive_damage, 1000, self );
                wait 0.1;
                snd delete();
            }
            wait .3;
            self disableInvulnerability();
        }
        wait .1; // Small delay before next loop iteration
    }
}

// --------------------------------------------------------------------------
// flames_fx()
// AAT implementation: Blast Furnace damage-over-time.
// Plays fire FX on the zombie and applies scaled damage ticks over a short duration.
// --------------------------------------------------------------------------
flames_fx(attacker)
{
    self endon("death");
    for(i = 0; i < 5; i++)
    {
        if(!isdefined(self) || !isalive(self))
            return;

        PlayFXOnTag(level._effect[ "character_fire_death_sm" ], self, "j_spineupper");

        fire_damage = int(self.maxhealth * 0.08) + (level.round_number * 80);
        self dodamage(fire_damage, (0,0,0));
        
        if(isdefined(attacker) && isplayer(attacker))
        {
            if(i < 3)
                attacker.score += 15;
            else
                attacker.score += 60;
        }
        wait 1;
    }
}

// --------------------------------------------------------------------------
// fireworks()
// AAT implementation: Fireworks visuals.
// Spawns temporary script_models around the zombie and plays map-specific FX.
// This is purely visual; the damage component is handled in spawn_weapon().
// --------------------------------------------------------------------------
fireworks()
{
    level endon("end_game");
    self endon("death");
    origin = self.origin;

    // Map-specific fireworks effects (logic remains similar, but now called from spawn_weapon for actual effect)
    if(getdvar("mapname") == "zm_buried")
    {
        for(i=0;i<10;i++)
        {
            x = randomintrange(-40, 40);
            y = randomintrange(-40, 40);

            up_in_air = origin + (0,0,65);
            up_in_air2 = origin + (x,y,randomintrange(45, 66));
            up_in_air3 = origin + (x,y,randomintrange(45, 66));

            // Create script models for fireworks
            firework = Spawn( "script_model", origin );
            firework SetModel( "tag_origin" );

            firework2 = Spawn( "script_model", origin );
            firework2 SetModel( "tag_origin" );

            firework3 = Spawn( "script_model", origin );
            firework3 SetModel( "tag_origin" );
    
            // Play specific FX on the fireworks models
            fx = PlayFxOnTag( level._effect[ "fx_wisp_m" ], firework, "tag_origin");
            fx2 = PlayFxOnTag( level._effect[ "fx_wisp_m" ], firework2, "tag_origin");
            fx3 = PlayFxOnTag( level._effect[ "fx_wisp_m" ], firework3, "tag_origin");
            
            // Move fireworks models upwards
            firework moveto(up_in_air, 1);
            firework2 moveto(up_in_air2, randomfloatrange(0.4, 1.1));
            firework3 moveto(up_in_air3, randomfloatrange(0.4, 1.1));

            wait .5; // Wait briefly
            // Delete models and FX
            firework delete();
            firework2 delete();
            firework3 delete();
            fx delete();
            fx2 delete();
            fx3 delete();
        }
    }

    else if(getdvar("mapname") == "zm_highrise")
    {
        for(i=0;i<22;i++)
        {
            firework = Spawn( "script_model", origin );
            firework SetModel( "tag_origin" );
            firework.angles = (0,0,0);
            fx = PlayFxOnTag( level._effect[ "sidequest_dragon_spark_max" ], firework, "tag_origin");
            wait .25;
            firework delete();
            fx delete();
        }
    }

    else if(getdvar("mapname") == "zm_tomb")
    {
        for(i=0;i<20;i++)
        {
            firework = Spawn( "script_model", origin );
            firework SetModel( "tag_origin" );
            firework.angles = (-90,0,0);
            fx = PlayFxOnTag( level._effect[ "fire_muzzle" ], firework, "tag_origin");
            wait .25;
            firework delete();
            fx delete();
        }
    }
    else if(getdvar("mapname") == "zm_transit" && getdvar ( "g_gametype")  == "zclassic" )
    {
        for(i=0;i<5;i++)
        {
            up_in_air = origin + (0,0,65);
            firework = Spawn( "script_model", origin );
            firework SetModel( "tag_origin" );
            fx = PlayFxOnTag( level._effect[ "richtofen_sparks" ], firework, "tag_origin");
            firework moveto(up_in_air, 1);
            wait 1;
            firework delete();
            fx delete();
        }
    }
    else
    {
        // Generic fallback for all other maps (zm_prison, zm_nuked, etc.)
        for(i=0;i<10;i++)
        {
            firework = Spawn( "script_model", origin );
            firework SetModel( "tag_origin" );
            firework.angles = (0,0,0);
            fx = PlayFxOnTag( level._effect[ "def_explosion" ], firework, "tag_origin");
            wait .35;
            firework delete();
            fx delete();
        }
    }
}

// --------------------------------------------------------------------------
// spawn_weapon()
// AAT implementation: Fireworks damage.
// Spawns a floating weapon model at the hit zombie, aims it at nearby zombies,
// fires magic bullets, and applies small radius damage at the impact point.
// Also tags attacker.firework_weapon so player damage callback can ignore it.
// --------------------------------------------------------------------------
spawn_weapon(attacker)
{
    level endon("end_game");
    attacker endon("disconnect");

    origin = self.origin;
    weapon = attacker getCurrentWeapon();

    attacker.firework_weapon = spawn( "script_model", origin );
    attacker.firework_weapon.angles = (0,0,0);
    attacker.firework_weapon setmodel( GetWeaponModel( weapon ) ); // Set model to attacker's weapon
    attacker.firework_weapon useweaponhidetags( weapon ); // Apply weapon hide tags

    // Animate the weapon model moving slightly up and then back down
    attacker.firework_weapon MoveTo( origin + (0, 0, 45), 0.5, 0.25, 0.25 );
    attacker.firework_weapon waittill( "movedone" );

    // Fire a set number of projectiles with splash damage
    num_projectiles = 5 + int(level.round_number / 10); // More projectiles late game, max 15
    if (num_projectiles > 15) num_projectiles = 15;

    for(i=0;i<num_projectiles;i++) 
    {
        // Find the closest zombies
        zombies = get_array_of_closest( attacker.firework_weapon.origin, getaiarray( level.zombie_team ), undefined, undefined, 300  );
        forward = attacker.firework_weapon.origin;
        
        // If there's a valid zombie target, fire a magic bullet at it
        if( isdefined( zombies[ 0 ] ) && can_aat_damage( zombies[ 0 ] ) )
        {
            end = zombies[ 0 ] gettagorigin( "j_spineupper" ); // Aim at spine
            crosshair = bullettrace( forward, end, 0, self )[ "position" ]; // Get hit position
            attacker.firework_weapon.angles = VectorToAngles( end - attacker.firework_weapon.origin ); // Orient weapon
            
            // Fire bullet if target is within range
            if( distance(zombies[ 0 ].origin, attacker.firework_weapon.origin) <= 300)
            {
                magicbullet( weapon, attacker.firework_weapon.origin, crosshair, attacker.firework_weapon );
                // Add radius damage on impact
                fireworks_damage = 1000 + (level.round_number * 100); // Scaled damage
                if (fireworks_damage > 8000) fireworks_damage = 8000;
                radiusdamage( crosshair, 200, fireworks_damage, 500, attacker ); // Smaller radius, fixed damage
            }
        }
        wait .1; // Small delay between shots
    }
    // Move weapon back and delete
    if (isdefined(attacker.firework_weapon))
    {
        attacker.firework_weapon MoveTo( origin, 0.5, 0.25, 0.25 );
        attacker.firework_weapon waittill( "movedone" );
        attacker.firework_weapon delete();
        attacker.firework_weapon = undefined;
    }
}

// --------------------------------------------------------------------------
// thunderwall()
// AAT implementation: Thunder Wall.
// Applies a blast centered on the hit zombie: finds nearby zombies, flings them,
// and deals scaled damage in an area.
// --------------------------------------------------------------------------
thunderwall( attacker ) 
{
    thunder_wall_blast_pos = self.origin; // Origin of the blast (the hit zombie)
    // Get zombies closest to the blast origin
    ai_zombies = get_array_of_closest( thunder_wall_blast_pos, getaiarray( level.zombie_team ), undefined, undefined, 300  ); // Increased radius
    
    if ( !isDefined( ai_zombies ) || ai_zombies.size == 0 ) // Return if no zombies found
        return;
    
    flung_zombies = 0;
    max_zombies = randomIntRange(8, 15); // More predictable range of affected zombies
    for ( i = 0; i < ai_zombies.size; i++ )
    {
        if( isdefined(ai_zombies[i]) && can_aat_damage(ai_zombies[i]) ) // Added isdefined check
        {
            n_random_x = RandomFloatRange( -3, 3 );
            n_random_y = RandomFloatRange( -3, 3 );
            ai_zombies[i] StartRagdoll(); // Force ragdoll
            ai_zombies[i] LaunchRagdoll( (n_random_x, n_random_y, 200) ); // Increased launch height

            // Play map-specific smoke/wind effects
            if(getdvar("mapname") == "zm_transit")
                playfxontag( level._effect[ "jetgun_smoke_cloud"], ai_zombies[i], "J_SpineUpper" );
            else if(getdvar("mapname") == "zm_tomb")
                playfxontag( level._effect[ "air_puzzle_smoke" ], ai_zombies[i], "J_SpineUpper" );
            else if(getdvar("mapname") == "zm_buried")
                playfxontag( level._effect[ "rise_billow_foliage" ], ai_zombies[i], "J_SpineUpper" );
            
            // Calculate dynamic damage
            thunder_damage = 2500 + (level.round_number * 200); // Scaled damage
            if (thunder_damage > 15000) thunder_damage = 15000;

            ai_zombies[i] DoDamage( thunder_damage, ai_zombies[i].origin, attacker, attacker, "none", "MOD_IMPACT" );
            flung_zombies++;
            attacker.score += 35; // Increased score
            if ( flung_zombies >= max_zombies ) // Stop if max zombies affected
                break;
        }
    }
}

// --------------------------------------------------------------------------
// headcutter_wrapper()
// Helper wrapper for Headcutter so each zombie can independently run the effect.
// Primarily used to avoid double-processing the same zombie within one proc.
// --------------------------------------------------------------------------
headcutter_wrapper(attacker)
{
    self thread Headcutter(attacker);
    self waittill("death");
    self.done = 0; // Reset done flag so zombie can be affected again on respawn
}

// --------------------------------------------------------------------------
// Headcutter()
// AAT implementation: Headcutter (instant-kill style proc).
// Handles the actual kill/FX behavior applied to a single zombie.
// --------------------------------------------------------------------------
Headcutter(attacker)
{
    self endon("death"); // End this thread if the zombie dies
    self maps\mp\zombies\_zm_spawner::zombie_head_gib(); // Force head gib
    
    // Immediate area damage upon head gib
    headcutter_initial_damage = 1000 + (level.round_number * 150);
    if (headcutter_initial_damage > 10000) headcutter_initial_damage = 10000;
    radiusdamage( self.origin, 150, headcutter_initial_damage, 500, attacker ); // Small radius, burst damage
    
    for(i=0; i < 5; i++) // Apply damage over 5 seconds
    {   
        wait 1; // Wait 1 second
        // Damage is a combination of fixed and scaled with round number
        headcutter_dot_damage = 100 + (level.round_number * 50); 
        self dodamage( headcutter_dot_damage, self.origin, attacker, attacker, "none", "MOD_IMPACT" ); // Deal damage
        attacker.score += 20; // Award score per tick
    }
}

// --------------------------------------------------------------------------
// cluster()
// AAT implementation: Cluster.
// Spawns a set of grenade-like projectiles around the hit zombie that detonate
// to damage surrounding zombies. Tracks spawned entities on the attacker so
// player damage filtering can ignore them.
// --------------------------------------------------------------------------
cluster( attacker )
{
    amount = 3 + int(level.round_number / 8);
    if (amount > 10) amount = 10;
    
    origin = self.origin;
    base_damage = 500 + (level.round_number * 50);
    radius = 128;

    for(i = 0; i < amount; i++)
    {
        random_x = RandomFloatRange( -80, 80 );
        random_y = RandomFloatRange( -80, 80 );
        explosion_origin = origin + (random_x, random_y, 10);
        RadiusDamage( explosion_origin, radius, base_damage, base_damage * 0.5, attacker );
        if ( isdefined( level._effect["def_explosion"] ) )
            PlayFX( level._effect["def_explosion"], explosion_origin );
        wait 0.15;
    }
}

// --------------------------------------------------------------------------
// turned()
// AAT implementation: Turned.
// Converts the hit zombie into an allied 'Turned' zombie for a short duration,
// and sets flags so AAT damage routing ignores the turned ally.
// --------------------------------------------------------------------------
turned( attacker )
{
    self.is_turned = 1; // Flag the zombie as turned
    self.actor_damage_func = ::turned_damage_respond; // Custom damage response for turned zombies
    self.health = int(self.maxhealth * 5); // Make turned zombie tanky but not truly immortal (5x health)

    attacker.active_turned = 1; // Flag attacker has an active turned zombie
    self.turned_zombie_kills = 0; // Initialize kill counter for this turned zombie
    self.max_kills = randomIntRange(8, 15); // Adjusted max kills (shorter lifespan for more frequent triggers)

    self thread set_zombie_run_cycle( "sprint" ); // Make turned zombie sprint
    self.custom_goalradius_override = 1000000; // Increase goal radius for chasing enemies

    // Play map-specific turned FX on the zombie's head
    if(getdvar("mapname") == "zm_tomb")
        turned_fx = playfxontag(level._effect[ "staff_soul" ], self, "j_head");
    else
        turned_fx = playfxontag(level._effect["powerup_on_solo"], self, "j_head");

    enemyoverride = []; // Array to store enemy override target
    self.team = level.players; // Change zombie's team to players' team
    self.ignore_enemy_count = 1; // Ignore enemy count (doesn't count towards spawn limit)

    // Determine attack animation based on map and if zombie has legs
    if(getdvar("mapname") == "zm_tomb")
        attackanim = "zm_generator_melee";
    else
        attackanim = "zm_riotshield_melee";
    
    if ( !self.has_legs )
        attackanim += "_crawl"; // Use crawl animation if no legs
    
    while(isAlive(self)) // Loop while the turned zombie is alive
    {
        // Get closest zombies to target
        ai_zombies = get_array_of_closest( self.origin, getaiarray( level.zombie_team ), undefined, undefined, undefined  );
        
        // Find a valid target (prioritize zombies[1] then zombies[0])
        if(isdefined(ai_zombies[1]) && can_aat_damage(ai_zombies[1]))
        {
            enemyoverride[0] = ai_zombies[1].origin;
            enemyoverride[1] = ai_zombies[1];
        }
        else if(isdefined(ai_zombies[0]) && can_aat_damage(ai_zombies[0]))
        {
            enemyoverride[0] = ai_zombies[0].origin;
            enemyoverride[1] = ai_zombies[0];
        }
        else
        {
            // If no valid target found, break the loop to prevent errors or infinite spinning
            break; 
        }
        self.enemyoverride = enemyoverride; // Set the turned zombie's target
        
        // If target is close enough, perform melee attack
        if(isdefined(ai_zombies[1]) && distance(self.origin, ai_zombies[1].origin) < 40 && isalive(ai_zombies[1]) )
        {
            angles = VectorToAngles( ai_zombies[1].origin - self.origin );
            self animscripted( self.origin, angles, attackanim ); // Play attack animation
            
            // Turned zombie attack damage (scaled with rounds)
            turned_attack_damage = int(ai_zombies[1].maxhealth * 0.5) + (level.round_number * 100); // 50% target max health + scaled flat damage
            if (turned_attack_damage > 10000) turned_attack_damage = 10000; // Cap damage
            ai_zombies[1] dodamage(turned_attack_damage, ai_zombies[1].origin); // Deal heavy damage
            
            self.turned_zombie_kills++; // Increment kill counter
            
            if(isdefined(attacker) && isplayer(attacker))
            {
                attacker.score += 75;
                attacker.pers["score"] = attacker.score;
            }

            // If max kills reached, kill the turned zombie
            if(self.turned_zombie_kills > self.max_kills)
            {
                if (isdefined(turned_fx)) turned_fx delete(); // Delete turned FX
                self.is_turned = 0; // Unflag as turned
                wait .1; // Small delay
                self dodamage(self.health + 666, self.origin); // Kill the turned zombie
                break; // Exit loop after death
            }

            wait 1; // Wait before next attack
        }
        else
            self stopanimscripted(); // Stop animation if not attacking

        wait .05; // Small delay
    }
    if(isdefined(attacker) && isplayer(attacker))
        attacker.active_turned = 0;
    self.is_turned = 0;

    if(isdefined(turned_fx)) // Clean up turned FX if it exists
        turned_fx delete();
}

// --------------------------------------------------------------------------
// turned_damage_respond()
// Damage callback for Turned zombies to prevent friendly-fire conflicts and to
// control what can and cannot damage the turned ally.
// --------------------------------------------------------------------------
turned_damage_respond( einflictor, eattacker, idamage, idflags, smeansofdeath, sweapon, vpoint, vdir, shitloc, psoffsettime, boneindex )
{
    if(isdefined(self.is_turned) && self.is_turned) // If the zombie is turned
        return 0; // Return 0 damage
    return idamage; // Return original damage if not turned
}

// --------------------------------------------------------------------------
// turned_zombie()
// Point-of-interest override function used by the game to evaluate turned zombies.
// Assigned to level._poi_override in init().
// --------------------------------------------------------------------------
turned_zombie()
{
    if(isdefined(self.is_turned) && self.is_turned)
    {
        return undefined;
    }

    zombie_poi = self get_zombie_point_of_interest( self.origin ); // Normal zombie POI logic
    return zombie_poi;
}

// --------------------------------------------------------------------------
// turned_zombie_validation()
// Validation gate used before proccing Turned.
// Ensures the target zombie is eligible to be turned (not special/boss/invalid).
// --------------------------------------------------------------------------
turned_zombie_validation()
{   
    // Cannot turn zombies that are entering barricades, traversing, not fully spawned, leaping, or inert
    if( IS_TRUE( self.barricade_enter ) )
        return false;
    
    if ( IS_TRUE( self.is_traversing ) )
        return false;
    
    if ( !IS_TRUE( self.completed_emerging_into_playable_area ) )
        return false;
    
    if ( IS_TRUE( self.is_leaping ) )
        return false;
    
    if ( IS_TRUE( self.is_inert ) )
        return false;
    
    return true; // If all checks pass, the zombie can be turned
}

// --------------------------------------------------------------------------
// is_true()
// Small helper: normalizes an arbitrary value to a strict boolean-ish 0/1 result.
// Useful when mixing undefined / int / bool-like flags in older scripts.
// --------------------------------------------------------------------------
is_true(check)
{
    return(IsDefined(check) && check);
}

// ========================================================================== 
//  SECTION: AAT ASSIGNMENT + HUD
// ========================================================================== 

// --------------------------------------------------------------------------
// give_aat()
// Assigns a random Alternate Ammo Type to a specific weapon for this player.
// Uses self.old_aat to avoid rolling the same AAT twice in a row.
// Stores assignments in self.aat[weapon] so the zombie damage callback can route procs.
// --------------------------------------------------------------------------
give_aat(weapon)
{       
    if(!isDefined(self.aat)) // Initialize AAT array if not present
        self.aat = [];

    // Store the old AAT as a number for comparison
    if(isdefined(self.old_aat))
    {
        if(self.old_aat == "Thunder Wall")
            self.old_aat = 0;
        else if(self.old_aat == "Fireworks")
            self.old_aat = 1;
        else if(self.old_aat == "Turned")
            self.old_aat = 2;
        else if(self.old_aat == "Cluster")
            self.old_aat = 3;
        else if(self.old_aat == "Headcutter")
            self.old_aat = 4;
        else if(self.old_aat == "Explosive")
            self.old_aat = 5;
        else if(self.old_aat == "Blast Furnace")
            self.old_aat = 6;
    }

    name = undefined; // Initialize AAT name

    number = randomint(7); // Get a random number (0-6)
    
    // Reroll if the new AAT is the same as the old one (ensures variety)
    while(isdefined(self.old_aat) && number == self.old_aat)
    {
        number = randomint(7);
        wait .05; // Small delay to prevent tight loop
    }
    
    // Map the random number to an AAT name
    if(number == 0)
        name = "Thunder Wall";
    else if(number == 1)
        name = "Fireworks";
    else if(number == 2)
        name = "Turned";
    else if(number == 3)
        name = "Cluster";
    else if(number == 4)
        name = "Headcutter";
    else if(number == 5)
        name = "Explosive";
    else if(number == 6)
        name = "Blast Furnace";

    self.aat[weapon] = name; // Assign the AAT to the specific weapon
    self.old_aat = name; // Store the current AAT as the old one for next time
}

// --------------------------------------------------------------------------
// tombstone_timeout()
// Handles the Tombstone (Scavenger) revive window timing.
// After a delay, notifies the weapon/HUD system so it can refresh state if the
// player timed out and returned without the usual revive path.
// --------------------------------------------------------------------------
tombstone_timeout()
{
    level endon("end_game"); // End if game ends
    self endon("dance_on_my_grave"); // End if player revives with Tombstone
    self endon("disconnect"); // End if player disconnects
    self endon("revived_player"); // End if player is revived normally

    self waittill("spawned_player"); // Wait for player to spawn
    wait 60; // Wait 60 seconds
    self notify("tombstone_timedout"); // Notify that Tombstone timed out
    wait 1; // Small delay
    weapon = self getCurrentWeapon(); // Get current weapon
    self notify("weapon_change", weapon); // Notify weapon change (to update HUD)
}

// --------------------------------------------------------------------------
// watch_weapon_changes()
// Per-player loop that keeps AAT state and HUD accurate.
//  - Creates self.aat and related state containers.
//  - Starts Explosive AAT listener thread (weapon_fired).
//  - Updates HUD on weapon_change and cleans up stale AAT entries for weapons the
//    player no longer has.
// Includes special handling for downed states, Tombstone, and Afterlife (zm_prison).
// --------------------------------------------------------------------------
watch_weapon_changes()
{
    level endon( "end_game" ); // End if game ends
    self endon( "disconnect" ); // End if player disconnects
    self waittill("spawned_player"); // Wait for player to spawn
    flag_wait("initial_blackscreen_passed"); // Wait for initial blackscreen to pass

    // Prevent immediate weapon change trigger when spawning in Mob of the Dead
    if(getdvar("mapname") == "zm_prison")
        level waittill("start_of_round");

    self.aat = [];
    self.aat_cooldown = 0;
    self.active_turned = 0;
    self thread explosive_bullet();

    while( isdefined( self ) )
    {
        result = self waittill_any_return( "weapon_change", "fake_death", "player_downed" );
        weapon = self getCurrentWeapon();

        // If player is downed or fake death triggered (e.g., Last Stand, PHD Flopper)
        if(result == "player_downed" || result == "fake_death")
        {
            // If player has Scavenger (Tombstone) or Final Stand perk
            if(self hasperk("specialty_scavenger") || self hasperk("specialty_finalstand"))
            {
                if(self hasperk("specialty_scavenger"))
                    self thread tombstone_timeout(); // Start Tombstone perk timeout

                // Wait for player to be revived or specific bleedout events
                self waittill_any("player_revived", "dance_on_my_grave", "tombstone_timedout", "chugabud_bleedout", "chugabud_effects_cleanup");
            }
        }

        // If player is in afterlife (Mob of the Dead), wait for them to spawn back
        if(isdefined(self.afterlife) && self.afterlife)
            self waittill("spawned_player");

        name = undefined;

        if( isdefined(self.aat) && IsDefined( self.aat[weapon] ) )
            name = self.aat[weapon];

        self aat_hud(name);

        if( IsDefined( self.aat ) )
        {
            keys = GetArrayKeys( self.aat );
            foreach( aat in keys )
            {
                if(IsDefined( self.aat[aat] ) && isdefined( aat ) && !self hasweapon( aat ))
                    self.aat[aat] = undefined;
            }
        }
    }
}

// --------------------------------------------------------------------------
// aat_hud()
// Creates/updates the on-screen AAT label for the player's current weapon.
// Destroys the prior element (if any) and rebuilds with a name + color per AAT.
// Position is map-tuned to avoid overlapping default HUD elements.
// --------------------------------------------------------------------------
aat_hud(name)
{
    self endon("disconnect"); // End if player disconnects

    if(isdefined(self.aat_hud)) // If HUD element already exists
        self.aat_hud destroy(); // Destroy it before recreating

    if(isDefined(name)) // If a name for the AAT is provided
    {
        // Define label and color for each AAT
        if(name == "Thunder Wall")
        {
            label = &"Thunder Wall";
            color = (0,1,1);
        }
        else if(name == "Fireworks")
        {
            label = &"Fireworks";
            color = (0,1,0);
        }
        else if(name == "Turned")
        {
            label = &"Turned";
            color = (1,0.5,0.5);
        }
        else if(name == "Cluster")
        {
            label = &"Cluster";
            color = (0.4,0.4,0.2);
        }
        else if(name == "Headcutter")
        {
            label = &"Headcutter";
            color = (1,0,1);
        }
        else if(name == "Explosive")
        {
            label = &"Explosive";
            color = (0,0,1);
        }
        else if(name == "Blast Furnace")
        {
            label = &"Blast Furnace";
            color = (1,0,0);
        }

        // Create a new client HUD element
        self.aat_hud = newClientHudElem(self);
        self.aat_hud.alignx = "right";
        self.aat_hud.aligny = "bottom";
        self.aat_hud.horzalign = "user_right";
        self.aat_hud.vertalign = "user_bottom";
        
        // Set position based on map
        if( getdvar( "mapname" ) == "zm_transit" || getdvar( "mapname" ) == "zm_highrise" || getdvar( "mapname" ) == "zm_nuked")
        {
            self.aat_hud.x = -85;
            self.aat_hud.y = -22;
        }
        else if( getdvar( "mapname" ) == "zm_tomb" )
        {
            self.aat_hud.x = -110;
            self.aat_hud.y = -80;
        }
        else
        {
            self.aat_hud.x = -95;
            self.aat_hud.y = -80;
        }
        
        // Set other HUD element properties
        self.aat_hud.archived = 1; // Persists across game states
        self.aat_hud.fontscale = 1;
        self.aat_hud.alpha = 1;
        self.aat_hud.color = color;
        self.aat_hud.hidewheninmenu = 1; // Hide when in menu
        self.aat_hud.label = label; // Set the AAT name as the label
    }
}

// ========================================================================== 
//  SECTION: SAFETY FILTERS
// ========================================================================== 

// --------------------------------------------------------------------------
// can_aat_damage()
// Safety filter: returns 1 only if the target AI should be affected by AAT damage.
// Blocks Turned allies and several known special/boss AIs (Avogadro, Brutus, Mechz, etc.).
// --------------------------------------------------------------------------
can_aat_damage(ai_zombies)
{
    // Cannot damage if zombie is "turned" (allied)
    if(isdefined(ai_zombies.is_turned) && ai_zombies.is_turned)
        return 0;

    // Cannot damage if it's the Sloth boss (specific to some maps)
    if(isdefined(level.sloth) && ai_zombies == level.sloth)
        return 0;

    // Cannot damage if it's a special boss type
    if(isDefined(ai_zombies.is_avogadro) && ai_zombies.is_avogadro || isDefined(ai_zombies.is_brutus) && ai_zombies.is_brutus || isDefined(ai_zombies.is_mechz) && ai_zombies.is_mechz )
        return 0;

    return 1; // Otherwise, it can be damaged
}
