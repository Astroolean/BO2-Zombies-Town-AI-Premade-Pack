// ╔════════════════════════════════════════════════════════════════════════════╗
// ║  PERK POP-UP ICON ANIMATION                                                ║
// ║  Call of Duty: Black Ops II Zombies (Plutonium T6)                         ║
// ║  Created by Astroolean                                                     ║
// ║                                                                            ║
// ║  What this script does                                                     ║
// ║  - Hooks the stock give_perk() function using replaceFunc().               ║
// ║  - Whenever a perk is granted (usually via buying a perk), it shows a      ║
// ║    centered perk icon (HUD element) that scales/fades in, waits, then      ║
// ║    fades out and cleans itself up.                                         ║
// ║  - The original perk logic remains intact; this adds only the on-screen    ║
// ║    perk animation at the very end of the perk-give flow.                   ║
// ║                                                                            ║
// ║  Notes                                                                     ║
// ║  - HUD = Heads-Up Display. Shaders are the perk icon materials.            ║
// ║  - To support additional perks:                                            ║
// ║      1) Add a case in perkHUD() mapping perk name -> shader.               ║
// ║      2) (Optional) Add a friendly name in getPerkShader().                 ║
// ╚════════════════════════════════════════════════════════════════════════════╝

// ────────────────────────────────────────────────────────────────────────────
// Includes
// ────────────────────────────────────────────────────────────────────────────
#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_perks;

// ────────────────────────────────────────────────────────────────────────────
// Core startup / player lifecycle
// ────────────────────────────────────────────────────────────────────────────
/**
 * init()
 * Entry point called by the game when the script loads.
 * Starts the player connect listener and swaps give_perk() to our override.
 * Important: replaceFunc() must run early so future perk grants go through this file.
 */
init()
{
    level thread onPlayerConnect();
    replaceFunc(::give_perk, ::give_perk_override);
}

/**
 * onPlayerConnect()
 * Loops forever waiting for players to connect, then starts per-player threads.
 * This keeps per-player logic safely scoped to each player entity.
 */
onPlayerConnect()
{
    for(;;)
    {
        level waittill("connected", player);
        player thread onPlayerSpawned();
    }
}

/**
 * onPlayerSpawned()
 * Waits for the player spawn event and keeps the thread alive across respawns.
 * This script does not currently run extra logic on spawn; the loop exists so you
 * can add spawn-time behavior later without rewriting your connection flow.
 */
onPlayerSpawned()
{
    self endon("disconnect");
	level endon("game_ended");
    for(;;)
    {
        self waittill("spawned_player");
    }
}

// ────────────────────────────────────────────────────────────────────────────
// HUD pop-up animation
// ────────────────────────────────────────────────────────────────────────────
/**
 * perkHUD(perk)
 * Shows a perk icon pop-up on the player's HUD when they receive a perk.
 * perk: the perk id string (example: specialty_armorvest).
 * Visual only: does not grant perks or modify gameplay.
 */
perkHUD(perk)
{
    // Map the perk id to the correct perk icon shader, then animate it on the HUD.
	level endon("end_game");
	self endon( "disconnect" );



    // Convert the perk id into the correct perk icon shader material.
    // If you add custom perks, add a new case here.
    switch( perk ) {
    	case "specialty_armorvest":
        	shader = "specialty_juggernaut_zombies";
        	break;
    	case "specialty_quickrevive":
        	shader = "specialty_quickrevive_zombies";
        	break;
    	case "specialty_fastreload":
        	shader = "specialty_fastreload_zombies";
        	break;
    	case "specialty_rof":
        	shader = "specialty_doubletap_zombies";
        	break;  
    	case "specialty_longersprint":
        	shader = "specialty_marathon_zombies";
        	break; 
    	case "specialty_flakjacket":
        	shader = "specialty_divetonuke_zombies";
        	break;  
    	case "specialty_deadshot":
        	shader = "specialty_ads_zombies";
        	break;
    	case "specialty_additionalprimaryweapon":
        	shader = "specialty_additionalprimaryweapon_zombies";
        	break; 
		case "specialty_scavenger": 
			shader = "specialty_tombstone_zombies";
        	break; 
    	case "specialty_finalstand":
			shader = "specialty_chugabud_zombies";
        	break; 
    	case "specialty_nomotionsensor":
			shader = "specialty_vulture_zombies";
        	break; 
    	case "specialty_grenadepulldeath":
			shader = "specialty_electric_cherry_zombie";
        	break; 
    	default:
        	shader = "";
        	break;
    }



    // Create a client HUD element for THIS player. We will animate and then destroy it.
	perk_hud = newClientHudElem(self);
    // Positioning: centered horizontally, near the top-middle of the screen.
	perk_hud.alignx = "center";
	perk_hud.aligny = "middle";
	perk_hud.horzalign = "user_center";
	perk_hud.vertalign = "user_top";
	perk_hud.x += 0;
	perk_hud.y += 120;
	perk_hud.fontscale = 2;
	perk_hud.alpha = 1;
	perk_hud.color = ( 1, 1, 1 );
	perk_hud.hidewheninmenu = 1;
	perk_hud.foreground = 1;
    // Set the icon material and initial size.
	perk_hud setShader(shader, 128, 128);
	
	

    // Animation IN: quick scale-down + fade-in so it pops onto the screen.
	perk_hud moveOvertime( 0.25 );
    perk_hud fadeovertime( 0.25 );
    perk_hud scaleovertime( 0.25, 64, 64);
    perk_hud.alpha = 1;
    perk_hud.setscale = 2;
    // Hold the icon on-screen for a moment.
    wait 3.25;

    // Animation IN: quick scale-down + fade-in so it pops onto the screen.

    // Animation OUT: fade out + scale up, then clean up.
    perk_hud moveOvertime( 1 );
    perk_hud fadeovertime( 1 );
    perk_hud.alpha = 0;
    perk_hud.setscale = 5;
    perk_hud scaleovertime( 1, 128, 128);
    wait 1;
    // Notify 'death' so any dependent threads can end cleanly (standard HUD elem pattern).
    perk_hud notify( "death" );

    // Safety: only destroy if it still exists.
    if ( isdefined( perk_hud ) )
        perk_hud destroy();
}


/**
 * getPerkShader(perk)
 * Returns a readable perk name for logging or future HUD text, based on the perk id.
 * If a perk is not handled here, the function returns undefined (left as-is).
 */
getPerkShader(perk)
{
	if(perk == "specialty_armorvest") //Juggernog
		return "Juggernog";
	if(perk == "specialty_rof") //Doubletap
		return "Double Tap";
	if(perk == "specialty_longersprint") //Stamin Up
		return "Stamin-Up";
	if(perk == "specialty_fastreload") //Speedcola
		return "Speed Cola";
	if(perk == "specialty_additionalprimaryweapon") //Mule Kick
		return "Mule Kick";
	if(perk == "specialty_quickrevive") //Quick Revive
		return "Quick Revive";
	if(perk == "specialty_finalstand") //Whos Who
		return "Who's Who";
	if(perk == "specialty_grenadepulldeath") //Electric Cherry
		return "Electric Cherry";
	if(perk == "specialty_flakjacket") //PHD Flopper
		return "PHD Flopper";
	if(perk == "specialty_deadshot") //Deadshot
		return "Deadshot Daiquiri";
	if(perk == "specialty_scavenger") //Tombstone
		return "Tombstone";
	if(perk == "specialty_nomotionsensor") //Vulture
		return "Vulture Aid";
}

// ────────────────────────────────────────────────────────────────────────────
// Perk hook (give_perk override)
// ────────────────────────────────────────────────────────────────────────────
/**
 * give_perk_override(perk, bought)
 * Override for the stock give_perk() function.
 * perk: the perk id string being granted.
 * bought: if defined and true, the perk was purchased (plays VO/blur and notifies perk_bought).
 * This function preserves the original logic and adds ONE line at the end:
 *     self perkHUD(perk);
 * so the pop-up icon appears after the perk is successfully applied.
 */
give_perk_override( perk, bought )
{
    // Apply the perk exactly like the stock function, then trigger the perk pop-up icon.
    // Grant the perk to the player.
    self setperk( perk );
    // Track total perk count (used by perk limit logic elsewhere).
    self.num_perks++;


    // If this perk was purchased (not granted for free), play the usual audio/VO and effects.
    if ( isdefined( bought ) && bought )
    {
        // Small 'burp' sound effect after drinking a perk.
        self maps\mp\zombies\_zm_audio::playerexert( "burp" );

        // Perk voice-over callout (immediate or delayed depending on map/game settings).
        if ( isdefined( level.remove_perk_vo_delay ) && level.remove_perk_vo_delay )
            self maps\mp\zombies\_zm_audio::perk_vox( perk );
        else
            self delay_thread( 1.5, maps\mp\zombies\_zm_audio::perk_vox, perk );

        // Brief blur pulse for perk feedback.
        self setblur( 4, 0.1 );
        wait 0.1;
        // Brief blur pulse for perk feedback.
        self setblur( 0, 0.1 );
        self notify( "perk_bought", perk );
    }


    // If this perk affects max health (Juggernog), apply the correct max health logic.
    self perk_set_max_health_if_jugg( perk, 1, 0 );


    // Deadshot uses a clientfield so the client can apply aim/ADS behavior.
    if ( !( isdefined( level.disable_deadshot_clientfield ) && level.disable_deadshot_clientfield ) )
    {
        if ( perk == "specialty_deadshot" )
            self setclientfieldtoplayer( "deadshot_perk", 1 );
        else if ( perk == "specialty_deadshot_upgrade" )
            self setclientfieldtoplayer( "deadshot_perk", 1 );
    }


    // Tombstone flag used by other scripts to enable/disable tombstone behavior.
    if ( perk == "specialty_scavenger" )
        self.hasperkspecialtytombstone = 1;


    // Pull current player list (kept from base function).
    players = get_players();


    // Solo Quick Revive: tracks extra lives and sets the 'solo_revive' flag after 3 uses.
    if ( use_solo_revive() && perk == "specialty_quickrevive" )
    {
        // Give the player a life token for the solo revive system.
        self.lives = 1;

        if ( !isdefined( level.solo_lives_given ) )
            level.solo_lives_given = 0;

        if ( isdefined( level.solo_game_free_player_quickrevive ) )
            level.solo_game_free_player_quickrevive = undefined;
        else
            level.solo_lives_given++;

        if ( level.solo_lives_given >= 3 )
            flag_set( "solo_revive" );

        self thread solo_revive_buy_trigger_move( perk );
    }


    // Who's Who / Chugabud-style behavior: grants an extra life and sets its activation flag.
    if ( perk == "specialty_finalstand" )
    {
        // Give the player a life token for the solo revive system.
        self.lives = 1;
        self.hasperkspecialtychugabud = 1;
        self notify( "perk_chugabud_activated" );
    }


    // Support for custom perk definitions: run any perk-specific give thread if provided.
    if ( isdefined( level._custom_perks[perk] ) && isdefined( level._custom_perks[perk].player_thread_give ) )
        self thread [[ level._custom_perks[perk].player_thread_give ]]();


    // Set the perk clientfield so the HUD/perk machine scripts can reflect ownership.
    self set_perk_clientfield( perk, 1 );
    // Demo bookmark for playback/debugging.
    maps\mp\_demo::bookmark( "zm_player_perk", gettime(), self );
    // Update stats counters (client + player).
    self maps\mp\zombies\_zm_stats::increment_client_stat( "perks_drank" );
    // Update stats counters (client + player).
    self maps\mp\zombies\_zm_stats::increment_client_stat( perk + "_drank" );
    self maps\mp\zombies\_zm_stats::increment_player_stat( perk + "_drank" );
    self maps\mp\zombies\_zm_stats::increment_player_stat( "perks_drank" );


    // Maintain a history list of perks acquired (used by other scripts / UI).
    if ( !isdefined( self.perk_history ) )
        self.perk_history = [];

    self.perk_history = add_to_array( self.perk_history, perk, 0 );


    // Maintain an active perks list, then notify scripts that a perk was acquired.
    if ( !isdefined( self.perks_active ) )
        self.perks_active = [];

    self.perks_active[self.perks_active.size] = perk;
    self notify( "perk_acquired" );
    // Start any perk-specific think loop.
    self thread perk_think( perk );
    // Finally: show the perk icon pop-up animation for this perk.
    self perkHUD(perk);
}
