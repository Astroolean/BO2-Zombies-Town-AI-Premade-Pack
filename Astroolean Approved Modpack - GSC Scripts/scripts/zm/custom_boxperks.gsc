#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_magicbox;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_unitrigger;
#include maps\mp\zombies\_zm_utility;

// ╔══════════════════════════════════════════════════════════════════╗
// ║                 CUSTOM BOX PERKS (MAGIC BOX)                     ║
// ║   Perk Bottles as Magic Box pulls + Safeguards + Clean Flow      ║
// ║   Black Ops II Zombies · Plutonium T6 Client                     ║
// ║                                                                  ║
// ║   Created by Astroolean                                          ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  What this script does                                           ║
// ║    • Forces/sets your box-perk DVARs every match.                ║
// ║    • Adds perk bottles into the Mystery Box roll pool (1-in-N).  ║
// ║    • Prevents duplicates, respects perk limits, avoids softlocks.║
// ║    • Uses “link-safe” helper stubs so it doesn’t crash on builds ║
// ║      missing some stock BO2 helper functions.                    ║
// ║                                                                  ║
// ║  What this script does NOT do                                    ║
// ║    • Does not change zombie damage, player health, or perk stats.║
// ║    • Does not give “free perks” without a box pull.              ║
// ║                                                                  ║
// ║  Configuration DVARs (auto-set in init() every match)            ║
// ║    perks_in_box            1   0=off  1=on                       ║
// ║    perk_limit              12  Per-player perk cap (safe 4–20)   ║
// ║    box_perk_roll_range     5   1-in-N chance to roll a perk      ║
// ║                                                                  ║
// ║  File layout (high level)                                        ║
// ║    1) Safe helpers / link-safety stubs                           ║
// ║    2) Perk-bottle string -> perk mapping                         ║
// ║    3) init() + chest discovery / monitoring                      ║
// ║    4) Box trigger prompts + chest think loop                     ║
// ║    5) Roll selection (weapons vs perk bottles)                   ║
// ║    6) Perk grant pipeline (bottle pickup -> setperk)             ║
// ║                                                                  ║
// ║  Notes                                                           ║
// ║    • This file is intentionally kept “behavior-identical” to the ║
// ║      working version you provided: organization + comments only. ║
// ║    • Any helper functions that may not exist on every client are ║
// ║      stubbed safely (no hard errors / no infinite waits).        ║
// ╚══════════════════════════════════════════════════════════════════╝

// Source note: Decompiled with SeriousHD-'s GSC Decompiler

// ============================================================================
// SECTION 1: Safe helpers + link-safety stubs
//   These exist so the mod can run on client builds that are missing certain
//   stock BO2 helper functions. They are designed to be safe no-ops where
//   appropriate (never throw, never hang).
// ============================================================================

// ----------------------------------------------------------------------------
// ensure_dvar_int( name, defaultValue )
//   Ensures a DVAR exists and has a value that can be read as an int.
//   Why: maps/scripts sometimes read these early; empty DVARs can act like 0.
//   Behavior: if missing/empty, sets it to defaultValue as a string.
// ----------------------------------------------------------------------------
ensure_dvar_int( name, defaultValue )
{
    if( !IsDefined( name ) ) return;
    v = getdvar( name );
    if( !IsDefined( v ) || v == "" )
        setdvar( name, defaultValue + "" );
}

// ----------------------------------------------------------------------------
// getdvarintdefault( name, defaultValue )
//   Safe integer DVAR read with a fallback when the DVAR is missing/empty.
//   Returns: int (defaultValue if unset).
// ----------------------------------------------------------------------------
getdvarintdefault( name, defaultValue )
{
    if( !IsDefined( name ) ) return defaultValue;
    v = getdvar( name );
    if( !IsDefined( v ) || v == "" )
        return defaultValue;
    return getdvarint( name );
}

// ----------------------------------------------------------------------------
// is_player_valid( player )
//   Lightweight sanity check for player entities (disconnect/transition-safe).
//   Used to avoid rare script errors when the game is ending or a client drops.
// ----------------------------------------------------------------------------
is_player_valid( player )
{
    if( !IsDefined( player ) ) return false;
    // basic sanity checks; avoids rare script errors during disconnect/transition
    if( !IsDefined( player.pers ) ) return false;
    if( IsDefined( player.sessionstate ) && player.sessionstate != "playing" ) return false;
    return true;
}


// ----------------------------------------------------------------------------
// player_is_in_laststand()
//   Best-effort “last stand” (downed) detection that never hard-errors.
//   Some Plutonium builds don’t expose the original helper, so we check common
//   fields that appear across mods / decompiles.
// ----------------------------------------------------------------------------
player_is_in_laststand()
{
    // Plutonium client builds don't always expose the original helper.
    // Make this a safe best-effort check that never hard-errors.
    if( !IsDefined( self ) ) return false;

    if( IsDefined( self.laststand ) && self.laststand ) return true;
    if( IsDefined( self.lastStand ) && self.lastStand ) return true;
    if( IsDefined( self.in_laststand ) && self.in_laststand ) return true;
    if( IsDefined( self.isinlaststand ) && self.isinlaststand ) return true;
    if( IsDefined( self.isInLastStand ) && self.isInLastStand ) return true;

    return false;
}

// ----------------------------------------------------------------------------
// is_true( v )
//   Small helper to normalize “defined + truthy” checks in decompiled branches.
// ----------------------------------------------------------------------------
is_true( v )
{
    if( !IsDefined( v ) ) return false;
    return v;
}

// Some decompiled code expects these as methods on the player.
// We provide safe versions so the script never fails to link.

// ----------------------------------------------------------------------------
// is_pers_double_points_active()
//   Link-safe stub: returns false on purpose.
//   Double Points should affect earning, not spending, and this script uses its
//   own point subtraction logic for box costs.
// ----------------------------------------------------------------------------
is_pers_double_points_active()
{
    // This script does NOT rely on double points for costs; keep false.
    // (Double Points affects earning, not spending.)
    return false;
}

// ----------------------------------------------------------------------------
// minus_to_player_score( amount )
//   Subtract points from the player in a build-safe way.
//   Prefers self.score when present; otherwise uses self.pers["score"].
//   Also notifies common listeners so HUD/score widgets refresh.
// ----------------------------------------------------------------------------
minus_to_player_score( amount )
{
    if( !IsDefined( amount ) ) return;
    if( amount <= 0 ) return;

    // Prefer engine score field if present.
    if( IsDefined( self.score ) )
    {
        self.score = self.score - amount;
        if( self.score < 0 ) self.score = 0;
    }
    else if( IsDefined( self.pers ) && IsDefined( self.pers["score"] ) )
    {
        self.pers["score"] = self.pers["score"] - amount;
        if( self.pers["score"] < 0 ) self.pers["score"] = 0;
    }

    // Nudge common score listeners (harmless if nobody is listening).
    self notify( "update_score" );
    self notify( "score_changed" );
}


// ----------------------------------------------------------------------------
// add_to_player_score( amount, flags )
//   Link-safe shim: no-op by design.
//   Some decompiled paths call this helper, but this mod already handles costs
//   with minus_to_player_score(). Keeping this as a no-op prevents “refund” bugs.
// ----------------------------------------------------------------------------
add_to_player_score( amount, flags )
{
    // Link-safe shim. Some client builds have this helper; many don't.
    // We DO NOT adjust score here, because this decompiled script already
    // handles cost via minus_to_player_score(). Keeping this a no-op prevents
    // accidental refunds/free-box behavior.
    if( IsDefined( self ) )
    {
        self notify( "update_score" );
        self notify( "score_changed" );
    }
    return;
}

// ----------------------------------------------------------------------------
// watch_for_lock()
//   Compatibility alias used by older scripts. Delegates to custom_watch_for_lock().
// ----------------------------------------------------------------------------
watch_for_lock()
{
    // Alias for older helper name. Delegate to our custom implementation.
    custom_watch_for_lock();
}

// ----------------------------------------------------------------------------
// has_perk_paused( perk )
//   Small state helper used by some perk scripts; stored on self._perk_paused[].
// ----------------------------------------------------------------------------
has_perk_paused( perk )
{
    if( !IsDefined( perk ) ) return false;
    if( IsDefined( self._perk_paused ) && IsDefined( self._perk_paused[perk] ) )
        return self._perk_paused[perk];
    return false;
}

// Equipment helpers used by some decompiled branches.
// Default to "not blocking" to avoid softlocks.
is_equipment( weaponName ) { return false; }
is_placeable_mine( weaponName ) { return false; }
is_equipment_that_blocks_purchase( weaponName ) { return false; }


// ----------------------------------------------------------------------------
// create_and_play_dialog( category, dialogAlias )
//   Link-safe stub for VO/dialog triggers some base scripts call.
//   This mod doesn’t require VO, so it’s a safe no-op.
// ----------------------------------------------------------------------------
create_and_play_dialog( category, dialogAlias )
{
    // Safe no-op. Some base scripts use this for VO like "no_money_box".
    // We intentionally do nothing to avoid unresolved externals on clients missing that helper.
    return;
}

// ----------------------------------------------------------------------------
// bookmark( tag, timestamp, player )
//   Link-safe stub. Some base scripts use “bookmark” events for replay/telemetry.
// ----------------------------------------------------------------------------
bookmark( tag, timestamp, player )
{
    // Safe no-op analytics hook.
    return;
}

// ----------------------------------------------------------------------------
// increment_client_stat( statName )
//   Link-safe stub. Some builds increment client stats here; this mod doesn’t.
// ----------------------------------------------------------------------------
increment_client_stat( statName )
{
    // Safe no-op; prevents unresolved externals in some client builds.
    return;
}

// ----------------------------------------------------------------------------
// increment_player_stat( statName )
//   Link-safe stub. Present for compatibility with decompiled branches.
// ----------------------------------------------------------------------------
increment_player_stat( statName )
{
    // Safe no-op; prevents unresolved externals in some client builds.
    return;
}

// ----------------------------------------------------------------------------
// in_revive_trigger()
//   Best-effort check for “revive interaction” triggers.
//   If we can’t detect it reliably on a build, we return false (non-blocking).
// ----------------------------------------------------------------------------
in_revive_trigger()
{
    // If we can't detect revive trigger reliably, assume not in revive.
    return false;
}

// Map perk-bottle weapon strings -> perk specialty names (self-contained; avoids unresolved externals).

// ============================================================================
// SECTION 2: Perk-bottle mapping
//   Converts the box “weapon_string” for perk bottles into actual perk names.
// ============================================================================

// ----------------------------------------------------------------------------
// get_perk_from_bottle( weapon )
//   Maps a perk-bottle weapon string (box pull) to the perk specialty name.
//   This keeps the perk pipeline self-contained and avoids relying on externals.

// ============================================================================
// SECTION 2: Perk-bottle mapping
//   Converts the box “weapon_string” for perk bottles into actual perk names.
// ============================================================================

// ----------------------------------------------------------------------------
get_perk_from_bottle( weapon )
{
    if( !IsDefined( weapon ) ) return undefined;

    switch( weapon )
    {
        case "zombie_perk_bottle_revive":                 return "specialty_quickrevive";
        case "zombie_perk_bottle_jugg":                   return "specialty_armorvest";
        case "zombie_perk_bottle_sleight":                return "specialty_fastreload";
        case "zombie_perk_bottle_doubletap":              return "specialty_rof";
        case "zombie_perk_bottle_marathon":               return "specialty_longersprint";
        case "zombie_perk_bottle_tombstone":              return "specialty_scavenger";
        case "zombie_perk_bottle_deadshot":               return "specialty_deadshot";
        case "zombie_perk_bottle_cherry":                 return "specialty_grenadepulldeath";
        // Many community scripts bind PhD/Flopper to flakjacket in BO2 ZM.
        case "zombie_perk_bottle_nuke":                   return "specialty_flakjacket";
        // Mule Kick
        case "zombie_perk_bottle_additionalprimaryweapon":return "specialty_additionalprimaryweapon";
        // Vulture Aid
        case "zombie_perk_bottle_vulture":                return "specialty_nomotionsensor";
        // Who’s Who
        case "zombie_perk_bottle_whoswho":                return "specialty_finalstand";
    }

    return undefined;
}

// Some decompiled scripts call this helper but not all client builds ship it.
// Keep it safe: never throw, never hang. Lock logic continues to work without it.

// ----------------------------------------------------------------------------
// clean_up_locked_box()
//   Link-safe stub used by locked-box flows on some maps/builds.
//   Uses only endons + a tiny wait so it never hangs or throws.
// ----------------------------------------------------------------------------
clean_up_locked_box()
{
    self endon( "box_locked" );
    self endon( "user_grabbed_weapon" );
    self endon( "chest_accessed" );
    wait 0.05;
    return;
}


// Additional link-safety stubs discovered on some client builds.

// ----------------------------------------------------------------------------
// clean_up_hacked_box()
//   Link-safe stub used when a hacker interaction ends on some builds.
//   Mirrors clean_up_locked_box() behavior.
// ----------------------------------------------------------------------------
clean_up_hacked_box()
{
    // Some builds call this when a hacker interaction ends.
    // Keep behavior identical to clean_up_locked_box, but without depending on other scripts.
    self endon( "box_locked" );
    self endon( "user_grabbed_weapon" );
    self endon( "chest_accessed" );
    wait 0.05;
    return;
}

// ----------------------------------------------------------------------------
// vector_scale( v, s )
//   Small math helper for builds missing vector_scale().
// ----------------------------------------------------------------------------
vector_scale( v, s )
{
    // Some builds don't ship vector_scale(); implement it safely.
    if( !IsDefined( v ) ) return ( 0, 0, 0 );
    if( !IsDefined( s ) ) s = 1;
    return ( v[0] * s, v[1] * s, v[2] * s );
}

// ----------------------------------------------------------------------------
// pers_treasure_chest_get_weapons_array()
//   Ensures level.pers_box_weapons exists (array of possible box pulls).
//   Falls back to an empty array if level.zombie_weapons isn’t available yet.
// ----------------------------------------------------------------------------
pers_treasure_chest_get_weapons_array()
{
    // Populate the persistent box weapon array if the base helper is missing.
    if( IsDefined( level.zombie_weapons ) )
    {
        level.pers_box_weapons = getarraykeys( level.zombie_weapons );
    }
    else
    {
        level.pers_box_weapons = [];
    }
    return;
}


// ============================================================================
// SECTION 3: Entry point + chest discovery/monitoring
//   Wires this mod into the map’s Mystery Box / Treasure Chest entities.
// ============================================================================

// ----------------------------------------------------------------------------
// init()
//   Entry point for the mod.
//   1) Forces the key DVARs each match (your requested defaults).
//   2) Hooks chest discovery depending on map flow (Origins vs others).
//   3) Applies a safe perk limit early, then re-applies after blackscreen in case
//      the map overwrote DVARs during init.

// ============================================================================
// SECTION 3: Entry point + chest discovery/monitoring
//   Wires this mod into the map’s Mystery Box / Treasure Chest entities.
// ============================================================================

// ----------------------------------------------------------------------------
init()
{
	// Forced defaults (auto every match).
	setdvar( "perks_in_box", "1" );
	setdvar( "perk_limit", "12" );
	setdvar( "box_perk_roll_range", "5" );

	// Keep original box logic.
	if( getdvar( "mapname" ) == "zm_tomb" )
	{
		thread monitor_boxes();
	}
	else
	{
		thread checkforcurrentbox();
	}

	level.shared_box = 0;
	add_zombie_hint( "default_shared_box", "Hold ^3&&1^7 for weapon" );

	// Perks-in-box toggle (forced on above).
	level.perks_in_box_enabled = getdvarintdefault( "perks_in_box", 1 );

	// Set a safe perk limit early (some scripts read this before blackscreen).
	limit = getdvarintdefault( "perk_limit", 12 );
	if( limit < 4 ) limit = 4;
	if( limit > 20 ) limit = 20;
	level.perk_purchase_limit = limit;

	flag_wait( "initial_blackscreen_passed" );

	// Re-apply after blackscreen in case the map overwrote it.
	limit = getdvarintdefault( "perk_limit", 12 );
	if( limit < 4 ) limit = 4;
	if( limit > 20 ) limit = 20;
	level.perk_purchase_limit = limit;
}


// ----------------------------------------------------------------------------
// monitor_boxes()
//   Map-specific chest monitor used on zm_tomb (Origins).
//   Keeps triggers/prompts updated while chests move/appear and players interact.
// ----------------------------------------------------------------------------
monitor_boxes()
{
	flag_wait( "initial_blackscreen_passed" );
	wait 0.05;

	// Safeguard: wait for chests to exist (prevents rare NPE/crash on load).
	t = 0;
	while( !IsDefined( level.chests ) && t < 200 )
	{
		wait 0.05;
		t++;
	}
	if( !IsDefined( level.chests ) )
	{
		return;
	}

	wait 10;

	i = 0;
	while( i < level.chests.size )
	{
		if( IsDefined( level.chests[ i] ) )
		{
			level.chests[ i] thread reset_box();
		}
		i++;
	}

	for(;;)
	{
		i = 0;
		while( i < level.chests.size )
		{
			if( IsDefined( level.chests[ i] ) && !(level.chests[ i].hidden) )
			{
				if( IsDefined( level.chests[ i].unitrigger_stub ) )
				{
					level.chests[ i].unitrigger_stub.prompt_and_visibility_func = ::boxtrigger_update_prompt;
				}
				if( IsDefined( level.chests[ i].zbarrier ) )
				{
					level.chests[ i].zbarrier waittill( "left" );
				}
			}
			i++;
		}
		wait 15;
	}
}


// ----------------------------------------------------------------------------
// setperklimit()
//   Legacy loop hook kept for older versions that expect it.
//   Continuously refreshes level.perk_purchase_limit from the perk_limit DVAR.
// ----------------------------------------------------------------------------
setperklimit()
{
	// Legacy hook (some older versions used this). Keep it safe.
	level endon( "end_game" );
	for(;;)
	{
		level.perk_purchase_limit = getdvarintdefault( "perk_limit", 12 );
		level waittill( "connected", player );
	}
}

// ----------------------------------------------------------------------------
// set_perk_limit( map )
//   Map-specific switch was removed/broken by decompile in some versions.
//   This implementation uses perk_limit DVAR consistently for all maps.
// ----------------------------------------------------------------------------
set_perk_limit( map )
{
	// Map-specific switch removed (decompiler broke it). Use a dvar instead.
	level.perk_purchase_limit = getdvarintdefault( "perk_limit", 12 );
	return level.perk_purchase_limit;
}

// ----------------------------------------------------------------------------
// checkforcurrentbox()
//   General chest discovery path for most maps.
//   Waits until initial_blackscreen_passed + chests exist, then wires triggers,
//   initializes hidden pieces where needed, and calls reset_box() per chest.
// ----------------------------------------------------------------------------
checkforcurrentbox()
{
	flag_wait( "initial_blackscreen_passed" );

	// Safeguard: wait for chests to exist (prevents rare NPE/crash on load).
	t = 0;
	while( !IsDefined( level.chests ) && t < 200 )
	{
		wait 0.05;
		t++;
	}
	if( !IsDefined( level.chests ) )
	{
		return;
	}

	if( getdvar( "mapname" ) == "zm_tomb" || getdvar( "mapname" ) == "zm_nuked" )
	{
		wait 10;
	}

	i = 0;
	while( i < level.chests.size )
	{
		if( IsDefined( level.chests[ i] ) )
		{
			level.chests[ i] thread reset_box();

			if( IsDefined( level.chests[ i].hidden ) && level.chests[ i].hidden )
			{
				level.chests[ i] get_chest_pieces();
			}

			if( IsDefined( level.chests[ i].hidden ) && !(level.chests[ i].hidden) )
			{
				if( IsDefined( level.chests[ i].unitrigger_stub ) )
				{
					level.chests[ i].unitrigger_stub.prompt_and_visibility_func = ::boxtrigger_update_prompt;
				}
			}
		}
		i++;
	}
}


// ----------------------------------------------------------------------------
// reset_box()
//   Resets chest state and re-registers the unitrigger think function if visible.
//   Also restarts the custom chest think loop (custom_treasure_chest_think()).
// ----------------------------------------------------------------------------
reset_box()
{
	self notify( "kill_chest_think" );
	wait 0.1;
	if( !(self.hidden) )
	{
		self.grab_weapon_hint = 0;
		self thread register_static_unitrigger( self.unitrigger_stub, ::magicbox_unitrigger_think );
		self.unitrigger_stub run_visibility_function_for_all_triggers();
	}
	self thread custom_treasure_chest_think();

}

// ----------------------------------------------------------------------------
// get_chest_pieces()
//   For hidden/assembled chests, caches the barrier + rubble entities used by
//   certain map flows (prevents null references during piece assembly).
// ----------------------------------------------------------------------------
get_chest_pieces()
{
	self.chest_box = getent( self.script_noteworthy + "_zbarrier", "script_noteworthy" );
	self.chest_rubble = [];
	rubble = getentarray( self.script_noteworthy + "_rubble", "script_noteworthy" );
	i = 0;
	while( i < rubble.size )
	{
		if( distancesquared( self.origin, rubble[ i].origin ) < 10000 )
		{
			self.chest_rubble[self.chest_rubble.size] = rubble[ i];
		}
		i++;
	}
	self.zbarrier = getent( self.script_noteworthy + "_zbarrier", "script_noteworthy" );
	if( IsDefined( self.zbarrier ) )
	{
		self.zbarrier zbarrierpieceuseboxriselogic( 3 );
		self.zbarrier zbarrierpieceuseboxriselogic( 4 );
	}
	self.unitrigger_stub = spawnstruct();
	self.unitrigger_stub.origin += anglestoright( self.angles ) * -22.5;
	self.unitrigger_stub.angles = self.angles;
	self.unitrigger_stub.script_unitrigger_type = "unitrigger_box_use";
	self.unitrigger_stub.script_width = 104;
	self.unitrigger_stub.script_height = 50;
	self.unitrigger_stub.script_length = 45;
	self.unitrigger_stub.trigger_target = self;
	unitrigger_force_per_player_triggers( self.unitrigger_stub, 1 );
	self.unitrigger_stub.prompt_and_visibility_func = ::boxtrigger_update_prompt;
	self.zbarrier.owner = self;

}

// ----------------------------------------------------------------------------
// boxtrigger_update_prompt( player )
//   Prompt/visibility callback for the unitrigger stub.
//   This is what makes the “Hold button to …” text correct based on state.
// ----------------------------------------------------------------------------
boxtrigger_update_prompt( player )
{
	can_use = self custom_boxstub_update_prompt( player );
	if( IsDefined( self.hint_string ) )
	{
		if( IsDefined( self.hint_parm1 ) )
		{
			self sethintstring( self.hint_string, self.hint_parm1 );
		}
		else
		{
			self sethintstring( self.hint_string );
		}
	}
	return can_use;

}

// ----------------------------------------------------------------------------
// custom_boxstub_update_prompt( player )
//   Secondary prompt updater used by certain decompiled branches / maps.
//   Kept separate so map scripts can swap callbacks safely.
// ----------------------------------------------------------------------------
custom_boxstub_update_prompt( player )
{
	self setcursorhint( "HINT_NOICON" );
	if( !(self trigger_visible_to_player( player )) )
	{
		if( level.shared_box )
		{
			self setvisibletoplayer( player );
			self.hint_string = get_hint_string( self, "default_shared_box" );
			return 1;
		}
		return 0;
	}
	self.hint_parm1 = undefined;
	if( self.stub.trigger_target.grab_weapon_hint && IsDefined( self.stub.trigger_target.grab_weapon_hint ) )
	{
		if( level.shared_box )
		{
			self.hint_string = get_hint_string( self, "default_shared_box" );
		}
		else
		{
			if( IsDefined( level.magic_box_check_equipment ) && [[ level.magic_box_check_equipment ]]( self.stub.trigger_target.grab_weapon_name ) )
			{
				self.hint_string = "Hold ^3&&1^7 for Equipment ^1or ^7Press ^3[{+melee}]^7 to let teammates pick it up";
			}
			else
			{
				self.hint_string = "Hold ^3&&1^7 for Weapon ^1or ^7Press ^3[{+melee}]^7 to let teammates pick it up";
			}
		}
	}
	else
	{
		if( self.stub.trigger_target.is_locked && IsDefined( self.stub.trigger_target.is_locked ) && level.using_locked_magicbox && IsDefined( level.using_locked_magicbox ) )
		{
			self.hint_string = get_hint_string( self, "locked_magic_box_cost" );
		}
		else
		{
			self.hint_parm1 = self.stub.trigger_target.zombie_cost;
			self.hint_string = get_hint_string( self, "default_treasure_chest" );
		}
	}
	return 1;

}

// ----------------------------------------------------------------------------
// custom_treasure_chest_think()
//   Main per-chest loop that drives the “open box / roll / grab” sequence.
//   Important responsibilities:
//     • Locks/unlocks the chest, handles timed-out rolls.
//     • Charges points once, prevents double-grabs, avoids softlocks.
//     • Integrates perk-bottle pulls: if the pull is a perk bottle, the pickup
//       calls give_perk_bottle() instead of giving a weapon.
// ----------------------------------------------------------------------------
custom_treasure_chest_think()
{
	if( !(IsDefined( level.perk_pick )) )
	{
		level.perk_pick = 0;
	}
	self endon( "kill_chest_think" );
	user = undefined;
	user_cost = undefined;
	self.box_rerespun = undefined;
	self.weapon_out = undefined;
	self thread unregister_unitrigger_on_kill_think();
	while( 1 )
	{
		if( !(IsDefined( self.forced_user )) )
		{
			self waittill( "trigger", user );
			if( user == level )
			{
				wait 0.1;
				continue;
			}
			break;
		}
		user = self.forced_user;
		if( user in_revive_trigger() )
		{
			wait 0.1;
			continue;
		}
		if( user.is_drinking > 0 )
		{
			wait 0.1;
			continue;
		}
		if( self.disabled && IsDefined( self.disabled ) )
		{
			wait 0.1;
			continue;
		}
		if( user getcurrentweapon() == "none" )
		{
			wait 0.1;
			continue;
		}
		reduced_cost = undefined;
		// No cost scaling here (keeps behavior consistent and avoids extra dependencies).
		if( self.is_locked && IsDefined( self.is_locked ) && level.using_locked_magicbox && IsDefined( level.using_locked_magicbox ) )
		{
			if( user.score >= level.locked_magic_box_cost )
			{
				user minus_to_player_score( level.locked_magic_box_cost );
				self.zbarrier set_magic_box_zbarrier_state( "unlocking" );
				self.unitrigger_stub run_visibility_function_for_all_triggers();
			}
			else
			{
				user create_and_play_dialog( "general", "no_money_box" );
			}
			wait 0.1;
			continue;
			break;
		}
		if( is_player_valid( user ) && IsDefined( self.auto_open ) )
		{
			if( !(IsDefined( self.no_charge )) )
			{
				user minus_to_player_score( self.zombie_cost );
				user_cost = self.zombie_cost;
			}
			else
			{
				user_cost = 0;
			}
			self.chest_user = user;
			break;
		}
		else
		{
			if( user.score >= self.zombie_cost && is_player_valid( user ) )
			{
				user minus_to_player_score( self.zombie_cost );
				user_cost = self.zombie_cost;
				self.chest_user = user;
				break;
			}
			else
			{
				if( user.score >= reduced_cost && IsDefined( reduced_cost ) )
				{
					user minus_to_player_score( reduced_cost );
					user_cost = reduced_cost;
					self.chest_user = user;
					break;
				}
				else
				{
					if( user.score < self.zombie_cost )
					{
						play_sound_at_pos( "no_purchase", self.origin );
						user create_and_play_dialog( "general", "no_money_box" );
						wait 0.1;
						continue;
					}
				}
			}
		}
		wait 0.05;
	}
	flag_set( "chest_has_been_used" );
	bookmark( "zm_player_use_magicbox", gettime(), user );
	user increment_client_stat( "use_magicbox" );
	user increment_player_stat( "use_magicbox" );
	if( IsDefined( level._magic_box_used_vo ) )
	{
		user thread [[ level._magic_box_used_vo ]]();
	}
	self thread watch_for_emp_close();
	if( level.using_locked_magicbox && IsDefined( level.using_locked_magicbox ) )
	{
		self thread watch_for_lock();
	}
	self._box_open = 1;
	level.box_open = 1;
	self._box_opened_by_fire_sale = 0;
	if( !IsDefined( self.auto_open ) && level.zombie_vars[ "zombie_powerup_fire_sale_on"] )
	{
		self._box_opened_by_fire_sale = 1;
	}
	if( IsDefined( self.chest_lid ) )
	{
		self.chest_lid thread treasure_chest_lid_open();
	}
	if( IsDefined( self.zbarrier ) )
	{
		play_sound_at_pos( "open_chest", self.origin );
		play_sound_at_pos( "music_chest", self.origin );
		self.zbarrier set_magic_box_zbarrier_state( "open" );
	}
	self.timedout = 0;
	self.weapon_out = 1;
	self.zbarrier thread treasure_chest_weapon_spawn( self, user );
	self.zbarrier thread treasure_chest_glowfx();
	thread unregister_unitrigger( self.unitrigger_stub );
	self.zbarrier waittill_any( "randomization_done", "box_hacked_respin" );
	if( IsDefined( user_cost ) && !self._box_opened_by_fire_sale )
	{
		user add_to_player_score( user_cost, 0 );
	}
	if( !self._box_opened_by_fire_sale && !(level.zombie_vars[ "zombie_powerup_fire_sale_on"]) )
	{
		self thread treasure_chest_move( self.chest_user );
	}
	else
	{
		self.grab_weapon_hint = 1;
		self.grab_weapon_name = self.zbarrier.weapon_string;
		self.chest_user = user;
		thread register_static_unitrigger( self.unitrigger_stub, ::magicbox_unitrigger_think );
		if( !is_true( self.zbarrier.closed_by_emp ) )
		{
			self thread treasure_chest_timeout();
		}
		timeout_time = 105;
		grabber = user;
		i = 0;
		while( i < 105 )
		{
			if( distance( self.origin, user.origin ) <= 100 && isplayer( user ) && user meleebuttonpressed() )
			{
				fx_obj = spawn( "script_model", self.origin + ( 0, 0, 35 ) );
				fx_obj setmodel( "tag_origin" );
				fx_box = loadfx( "maps/zombie/fx_zmb_race_trail_grief" );
				fx = playfxontag( fx_box, fx_obj, "TAG_ORIGIN" );
				level.magic_box_grab_by_anyone = 1;
				level.shared_box = 1;
				self.unitrigger_stub run_visibility_function_for_all_triggers();
				a = i;
				while( a < 105 )
				{
					foreach( player in level.players )
					{
						if( player usebuttonpressed() && !(player can_buy()) )
						{
							wait 0.1;
							break;
						}
						else
						{
							if( !player.is_drinking && IsDefined( player.is_drinking ) && distance( self.origin, player.origin ) <= 100 )
							{
								if( level.perk_pick == 1 && level.box_perks == 0 )
								{
									player playsound( "zmb_cha_ching" );
									self give_perk_bottle( player );
								}
								else
								{
									player thread treasure_chest_give_weapon( self.zbarrier.weapon_string );
								}
								a = 105;
								break;
							}
							else
							{
								continue;
							}
						}
					}
					wait 0.1;
					a++;
				}
				break;
				break;
			}
			else
			{
				if( grabber usebuttonpressed() && !(grabber can_buy()) )
				{
					wait 0.1;
					continue;
					break;
				}
				if( distance( self.origin, grabber.origin ) <= 100 && user == grabber && isplayer( grabber ) && grabber usebuttonpressed() )
				{
					if( level.perk_pick == 1 && level.box_perks == 0 )
					{
						grabber playsound( "zmb_cha_ching" );
						self give_perk_bottle( grabber );
					}
					else
					{
						grabber thread treasure_chest_give_weapon( self.zbarrier.weapon_string );
					}
					break;
				}
			}
			wait 0.1;
			i++;
		}
		fx_obj delete();
		fx delete();
		self.weapon_out = undefined;
		self notify( "user_grabbed_weapon" );
		user notify( "user_grabbed_weapon" );
		self.grab_weapon_hint = 0;
		self.zbarrier notify( "weapon_grabbed" );
		if( !self._box_opened_by_fire_sale )
		{
			level.chest_accessed = level.chest_accessed + 1;
		}
		if( IsDefined( level.pulls_since_last_ray_gun ) && level.chest_moves > 0 )
		{
			level.pulls_since_last_ray_gun = level.pulls_since_last_ray_gun + 1;
		}
		thread unregister_unitrigger( self.unitrigger_stub );
		if( IsDefined( self.chest_lid ) )
		{
			self.chest_lid thread treasure_chest_lid_close( self.timedout );
		}
		if( IsDefined( self.zbarrier ) )
		{
			self.zbarrier set_magic_box_zbarrier_state( "close" );
			play_sound_at_pos( "close_chest", self.origin );
			self.zbarrier waittill( "closed" );
			wait 1;
		}
		else
		{
			wait 3;
		}
		if( self == level.chests[ level.chest_index] || level.shared_box || (level.zombie_vars[ "zombie_powerup_fire_sale_on"] && IsDefined( level.zombie_vars[ "zombie_powerup_fire_sale_on"] )) )
		{
			thread register_static_unitrigger( self.unitrigger_stub, ::magicbox_unitrigger_think );
		}
	}
	level.perk_pick = 0;
	self._box_open = 0;
	level.box_open = 0;
	level.shared_box = 0;
	level.magic_box_grab_by_anyone = 0;
	self._box_opened_by_fire_sale = 0;
	self.chest_user = undefined;
	self notify( "chest_accessed" );
	self thread custom_treasure_chest_think();

}

// ============================================================================
// SECTION 5: Perk pickup + grant pipeline
//   Handles bottle pickup, validates state, then grants via setperk().
// ============================================================================

// ----------------------------------------------------------------------------
// give_perk_bottle( player )
//   Converts the rolled bottle weapon_string into a perk, then grants it safely.
//   Safeguards:
//     • Checks global toggle + perk cap.
//     • Blocks duplicates.
//     • Requires player can_buy() to avoid animation/weapon-state glitches.

// ============================================================================
// SECTION 5: Perk pickup + grant pipeline
//   Handles bottle pickup, validates state, then grants via setperk().
// ============================================================================

// ----------------------------------------------------------------------------
give_perk_bottle( player )
{
	if( !IsDefined( player ) ) return;

	// Global toggle safeguard.
	if( !IsDefined( level.perks_in_box_enabled ) || !level.perks_in_box_enabled )
	{
		return;
	}

	// Cap safeguard.
	if( IsDefined( level.perk_purchase_limit ) && player.num_perks >= level.perk_purchase_limit )
	{
		player iprintlnbold( "^3Perk limit reached." );
		return;
	}

	if( !IsDefined( self ) || !IsDefined( self.zbarrier ) || !IsDefined( self.zbarrier.weapon_string ) )
	{
		return;
	}

	perk = get_perk_from_bottle( self.zbarrier.weapon_string );
	if( !IsDefined( perk ) )
	{
		// Unknown bottle string (safe no-op).
		return;
	}

	// Already owned safeguard (prevents duplicates if something changes between roll and pickup).
	if( player hasperk( perk ) )
	{
		player iprintlnbold( "^3Already have that perk." );
		return;
	}

	// Purchase-state safeguard (prevents animation edge bugs).
	if( !player can_buy() )
	{
		player iprintlnbold( "^3Can’t take a perk right now." );
		return;
	}

	player thread dogiveperk( perk );
}


// ----------------------------------------------------------------------------
// custom_watch_for_lock()
//   Waits for the chest “box_locked” event, then re-registers triggers and
//   restarts the chest think loop. This prevents broken states after a lock.
// ----------------------------------------------------------------------------
custom_watch_for_lock()
{
	self endon( "user_grabbed_weapon" );
	self endon( "chest_accessed" );
	self waittill( "box_locked" );
	self notify( "kill_chest_think" );
	self.grab_weapon_hint = 0;
	wait 0.1;
	self thread register_static_unitrigger( self.unitrigger_stub, ::magicbox_unitrigger_think );
	self.unitrigger_stub run_visibility_function_for_all_triggers();
	self thread custom_treasure_chest_think();

}

// ----------------------------------------------------------------------------
// treasure_chest_weapon_spawn( chest, player, respin )
//   Performs the roll animation cycles and ultimately selects a weapon string.
//   This function is mostly decompiled stock flow; the mod keeps it intact and
//   relies on custom selection helpers so perk bottles can be selected too.
// ----------------------------------------------------------------------------
treasure_chest_weapon_spawn( chest, player, respin )
{
	if( level.using_locked_magicbox && IsDefined( level.using_locked_magicbox ) )
	{
		self.owner endon( "box_locked" );
		self thread clean_up_locked_box();
	}
	self endon( "box_hacked_respin" );
	self thread clean_up_hacked_box();
	self.weapon_string = undefined;
	modelname = undefined;
	rand = undefined;
	number_cycles = 40;
	if( IsDefined( chest.zbarrier ) )
	{
		if( IsDefined( level.custom_magic_box_do_weapon_rise ) )
		{
			chest.zbarrier thread [[ level.custom_magic_box_do_weapon_rise ]]();
		}
		else
		{
			chest.zbarrier thread magic_box_do_weapon_rise();
		}
	}
	i = 0;
	while( i < number_cycles )
	{
		if( i < 20 )
		{
			wait 0.05;
			i++;
			continue;
		}
		else
		{
			if( i < 30 )
			{
				wait 0.1;
				i++;
				continue;
			}
			else
			{
				if( i < 35 )
				{
					wait 0.2;
					i++;
					continue;
				}
				else
				{
					if( i < 38 )
					{
						wait 0.3;
					}
				}
			}
		}
		i++;
	}
	if( IsDefined( level.custom_magic_box_weapon_wait ) )
	{
		[[ level.custom_magic_box_weapon_wait ]]();
	}
	if( player.pers_upgrades_awarded[ "box_weapon"] && IsDefined( player.pers_upgrades_awarded[ "box_weapon"] ) )
	{
		rand = pers_treasure_chest_choosespecialweapon( player );
	}
	else
	{
		rand = custom_treasure_chest_chooseweightedrandomweapon( player );
	}
	if( rand == "zombie_perk_bottle_revive" )
	{
		rand = "zombie_perk_bottle_revive";
	}
	self.weapon_string = rand;
	wait 0.1;
	if( IsDefined( level.custom_magicbox_float_height ) )
	{
		v_float *= level.custom_magicbox_float_height;
	}
	else
	{
		v_float *= 40;
	}
	self.model_dw = undefined;
	self.weapon_model = spawn_weapon_model( rand, undefined, self.origin + v_float, self.angles + vector_scale( ( 0, 1, 0 ), 180 ) );
	if( weapon_is_dual_wield( rand ) )
	{
		self.weapon_model_dw = spawn_weapon_model( rand, get_left_hand_weapon_model_name( rand ), self.weapon_model.origin - vector_scale( ( 0, 1, 0 ), 3 ), self.weapon_model.angles );
	}
	if( level.zombie_vars[ "zombie_powerup_fire_sale_on"] && IsDefined( level.zombie_vars[ "zombie_powerup_fire_sale_on"] ) && !chest._box_opened_by_fire_sale )
	{
		random = randomint( 100 );
		if( !(IsDefined( level.chest_min_move_usage )) )
		{
			level.chest_min_move_usage = 4;
		}
		if( level.chest_accessed < level.chest_min_move_usage )
		{
			chance_of_joker = -1;
		}
		else
		{
			chance_of_joker += 20;
		}
		if( level.chest_accessed >= 8 && level.chest_moves == 0 )
		{
			chance_of_joker = 100;
		}
		if( level.chest_accessed < 8 && level.chest_accessed >= 4 )
		{
			if( random < 15 )
			{
				chance_of_joker = 100;
			}
			else
			{
				chance_of_joker = -1;
			}
		}
		if( level.chest_moves > 0 )
		{
			if( level.chest_accessed < 13 && level.chest_accessed >= 8 )
			{
				if( random < 30 )
				{
					chance_of_joker = 100;
				}
				else
				{
					chance_of_joker = -1;
				}
			}
			if( level.chest_accessed >= 13 )
			{
				if( random < 50 )
				{
					chance_of_joker = 100;
				}
				else
				{
					chance_of_joker = -1;
				}
			}
		}
		if( IsDefined( chest.no_fly_away ) )
		{
			chance_of_joker = -1;
		}
		if( IsDefined( level._zombiemode_chest_joker_chance_override_func ) )
		{
			chance_of_joker = [[ level._zombiemode_chest_joker_chance_override_func ]]( chance_of_joker );
		}
		if( chance_of_joker > random )
		{
			self.weapon_string = undefined;
			self.weapon_model setmodel( level.chest_joker_model );
			self.weapon_model.angles += vector_scale( ( 0, 1, 0 ), 90 );
			if( IsDefined( self.weapon_model_dw ) )
			{
				self.weapon_model_dw delete();
				self.weapon_model_dw = undefined;
			}
			self.chest_moving = 1;
			flag_set( "moving_chest_now" );
			level.chest_accessed = 0;
			level.chest_moves++;
		}
	}
	self notify( "randomization_done" );
	if( level.zombie_vars[ "zombie_powerup_fire_sale_on"] )
	{
		if( IsDefined( level.chest_joker_custom_movement ) )
		{
			self [[ level.chest_joker_custom_movement ]]();
		}
		else
		{
			wait 0.5;
			level notify( "weapon_fly_away_start" );
			wait 2;
			if( IsDefined( self.weapon_model ) )
			{
				v_fly_away += anglestoup( self.angles ) * 500;
				self.weapon_model moveto( v_fly_away, 4, 3 );
			}
			if( IsDefined( self.weapon_model_dw ) )
			{
				v_fly_away += anglestoup( self.angles ) * 500;
				self.weapon_model_dw moveto( v_fly_away, 4, 3 );
			}
			self.weapon_model waittill( "movedone" );
			self.weapon_model delete();
			if( IsDefined( self.weapon_model_dw ) )
			{
				self.weapon_model_dw delete();
				self.weapon_model_dw = undefined;
			}
			self notify( "box_moving" );
			level notify( "weapon_fly_away_end" );
		}
	}
	else
	{
		acquire_weapon_toggle( rand, player );
		if( rand == "ray_gun_zm" || rand == "tesla_gun_zm" )
		{
			if( rand == "ray_gun_zm" )
			{
				level.pulls_since_last_ray_gun = 0;
			}
			if( rand == "tesla_gun_zm" )
			{
				level.pulls_since_last_tesla_gun = 0;
				level.player_seen_tesla_gun = 1;
			}
		}
		if( !(IsDefined( respin )) )
		{
			if( IsDefined( chest.box_hacks[ "respin"] ) )
			{
				self [[ chest.box_hacks[ "respin"] ]]( chest, player );
			}
		}
		else
		{
			if( IsDefined( chest.box_hacks[ "respin_respin"] ) )
			{
				self [[ chest.box_hacks[ "respin_respin"] ]]( chest, player );
			}
		}
		if( IsDefined( level.custom_magic_box_timer_til_despawn ) )
		{
			self.weapon_model thread [[ level.custom_magic_box_timer_til_despawn ]]( self );
		}
		else
		{
			self.weapon_model thread timer_til_despawn( v_float );
		}
		if( IsDefined( self.weapon_model_dw ) )
		{
			if( IsDefined( level.custom_magic_box_timer_til_despawn ) )
			{
				self.weapon_model_dw thread [[ level.custom_magic_box_timer_til_despawn ]]( self );
			}
			else
			{
				self.weapon_model_dw thread timer_til_despawn( v_float );
			}
		}
		self waittill( "weapon_grabbed" );
		if( !(chest.timedout) )
		{
			if( IsDefined( self.weapon_model ) )
			{
				self.weapon_model delete();
			}
			if( IsDefined( self.weapon_model_dw ) )
			{
				self.weapon_model_dw delete();
			}
		}
	}
	self.weapon_string = undefined;
	self notify( "box_spin_done" );

}

// ----------------------------------------------------------------------------
// pers_treasure_chest_choosespecialweapon( player )
//   Chooses a special roll outcome (Wunder weapons, map specials, etc) when the
//   base scripts request it. Kept intact for map compatibility.
// ----------------------------------------------------------------------------
pers_treasure_chest_choosespecialweapon( player )
{
	rval = randomfloat( 1 );
	if( !(IsDefined( player.pers_magic_box_weapon_count )) )
	{
		player.pers_magic_box_weapon_count = 0;
	}
	if( rval < 0.6 && player.pers_magic_box_weapon_count == 0 || player.pers_magic_box_weapon_count < 2 )
	{
		player.pers_magic_box_weapon_count++;
		if( IsDefined( level.pers_treasure_chest_get_weapons_array_func ) )
		{
			[[ level.pers_treasure_chest_get_weapons_array_func ]]();
		}
		else
		{
			pers_treasure_chest_get_weapons_array();
		}
		keys = array_randomize( level.pers_box_weapons );
		pap_triggers = getentarray( "specialty_weapupgrade", "script_noteworthy" );
		i = 0;
		while( i < keys.size )
		{
			if( treasure_chest_canplayerreceiveweapon( player, keys[ i], pap_triggers ) )
			{
				return keys[ i];
			}
			i++;
		}
		return keys[ 0];
	}
	else
	{
		player.pers_magic_box_weapon_count = 0;
		weapon = custom_treasure_chest_chooseweightedrandomweapon( player );
		return weapon;
	}

}

// ============================================================================
// SECTION 4: Roll selection (weapons vs perk bottles)
//   Builds the eligible pool per player and chooses a result safely.
// ============================================================================

// ----------------------------------------------------------------------------
// custom_treasure_chest_chooseweightedrandomweapon( player )
//   Core selection logic for “what comes out of the box”.
//   - Rolls a 1-in-N chance to replace the weapon pool with perk bottles.
//   - Builds a perk-bottle list filtered by what the player does NOT own.
//   - Falls back to weapon keys if no perks are eligible.

// ============================================================================
// SECTION 4: Roll selection (weapons vs perk bottles)
//   Builds the eligible pool per player and chooses a result safely.
// ============================================================================

// ----------------------------------------------------------------------------
custom_treasure_chest_chooseweightedrandomweapon( player )
{
		// Always reset this each roll (prevents stale perk state).
	level.perk_pick = 0;

// 1-in-N perk roll (default N=5). Set box_perk_roll_range to control it.
	rollRange = getdvarintdefault( "box_perk_roll_range", 5 );
	if( rollRange < 2 )
	{
		rollRange = 2;
	}

	level.box_perks = randomintrange( 0, rollRange );
	zombie_perks = [];

	// Safeguard: ensure perk cap exists.
	if( !IsDefined( level.perk_purchase_limit ) )
	{
		level.perk_purchase_limit = getdvarintdefault( "perk_limit", 12 );
	}

	if( IsDefined( player ) && level.perks_in_box_enabled && player.num_perks < level.perk_purchase_limit && level.box_perks == 0 )
	{
		// Add every perk bottle (only if the player doesn't already have it).
		if( !(player hasperk( "specialty_quickrevive" )) )                 zombie_perks[zombie_perks.size] = "zombie_perk_bottle_revive";
		if( !(player hasperk( "specialty_armorvest" )) )                  zombie_perks[zombie_perks.size] = "zombie_perk_bottle_jugg";
		if( !(player hasperk( "specialty_fastreload" )) )                 zombie_perks[zombie_perks.size] = "zombie_perk_bottle_sleight";
		if( !(player hasperk( "specialty_rof" )) )                        zombie_perks[zombie_perks.size] = "zombie_perk_bottle_doubletap";
		if( !(player hasperk( "specialty_longersprint" )) )               zombie_perks[zombie_perks.size] = "zombie_perk_bottle_marathon";
		if( !(player hasperk( "specialty_scavenger" )) )                  zombie_perks[zombie_perks.size] = "zombie_perk_bottle_tombstone";
		if( !(player hasperk( "specialty_deadshot" )) )                   zombie_perks[zombie_perks.size] = "zombie_perk_bottle_deadshot";
		if( !(player hasperk( "specialty_grenadepulldeath" )) )           zombie_perks[zombie_perks.size] = "zombie_perk_bottle_cherry";
		if( !(player hasperk( "specialty_flakjacket" )) )                 zombie_perks[zombie_perks.size] = "zombie_perk_bottle_nuke";
		if( !(player hasperk( "specialty_additionalprimaryweapon" )) )    zombie_perks[zombie_perks.size] = "zombie_perk_bottle_additionalprimaryweapon";
		if( !(player hasperk( "specialty_nomotionsensor" )) )             zombie_perks[zombie_perks.size] = "zombie_perk_bottle_vulture";
		if( !(player hasperk( "specialty_finalstand" )) )                 zombie_perks[zombie_perks.size] = "zombie_perk_bottle_whoswho";
	}

	if( zombie_perks.size > 0 )
	{
		keys = array_randomize( zombie_perks );
	}
	else
	{
		if( IsDefined( level.zombie_weapons ) )
		{
			keys = array_randomize( getarraykeys( level.zombie_weapons ) );
		}
		else
		{
			keys = [];
		}
	}

	// Safeguard: never return an empty key list.
	if( !IsDefined( keys ) || keys.size <= 0 )
	{
		level.perk_pick = 0;
		return "m1911_zm";
	}

	if( IsDefined( level.customrandomweaponweights ) )
	{
		keys = player [[ level.customrandomweaponweights ]]( keys );
		if( !IsDefined( keys ) || keys.size <= 0 )
		{
			keys = array_randomize( getarraykeys( level.zombie_weapons ) );
		}
	}

	pap_triggers = getentarray( "specialty_weapupgrade", "script_noteworthy" );
	if( !IsDefined( pap_triggers ) )
	{
		pap_triggers = [];
	}

	i = 0;
	while( i < keys.size )
	{
		if( zombie_perks.size > 0 )
		{
			if( treasure_chest_canplayerreceiveperk( player, keys[ i] ) )
			{
				return keys[ i];
			}
		}
		else
		{
			if( treasure_chest_canplayerreceiveweapon( player, keys[ i], pap_triggers ) )
			{
				return keys[ i];
			}
		}
		i++;
	}

	return keys[ 0];
}


// ----------------------------------------------------------------------------
// treasure_chest_canplayerreceiveperk( player, weapon )
//   Validates whether the player can receive the perk represented by a bottle.
//   Sets level.perk_pick=1 when the bottle is eligible so later code knows the
//   box result is a perk and should be handled as a perk pickup.
// ----------------------------------------------------------------------------
treasure_chest_canplayerreceiveperk( player, weapon )
{
	if( !IsDefined( player ) ) return 0;
	if( !IsDefined( weapon ) ) return 0;

	perk = get_perk_from_bottle( weapon );
	if( !IsDefined( perk ) ) return 0;

	// Hard cap (prevents edge cases where the player hits the limit between roll and pickup).
	if( IsDefined( level.perk_purchase_limit ) && player.num_perks >= level.perk_purchase_limit )
	{
		return 0;
	}

	// Already owned safeguard.
	if( player hasperk( perk ) )
	{
		return 0;
	}

	level.perk_pick = 1;
	return 1;
}



// ----------------------------------------------------------------------------
// dogiveperk( perk )
//   The actual “grant perk” pipeline.
//   Handles the drink animation state safely, prevents concurrent perk grants,
//   respects perk cap, and finally calls setperk(perk).
//   Note: This is intentionally conservative to avoid map-specific edge bugs.
// ----------------------------------------------------------------------------
dogiveperk( perk )
{
	self endon( "disconnect" );
	self endon( "death" );
	level endon( "game_ended" );
	self endon( "perk_abort_drinking" );

	if( !IsDefined( perk ) ) return;
	if( perk == "" ) return;

	// Cap + duplicate safeguards.
	if( IsDefined( level.perk_purchase_limit ) && IsDefined( self.num_perks ) && self.num_perks >= level.perk_purchase_limit ) return;
	if( self hasperk( perk ) ) return;

	// Only allow one perk grant at a time (prevents thread pileups / hitching).
	if( IsDefined( self.__perk_give_in_progress ) && self.__perk_give_in_progress )
	{
		return;
	}
	self.__perk_give_in_progress = 1;

	// Don’t start if the player is in a bad state.
	if( !self can_buy() )
	{
		self.__perk_give_in_progress = 0;
		return;
	}

	// Mark drinking briefly so other purchase logic can’t collide.
	if( !IsDefined( self.is_drinking ) )
		self.is_drinking = 0;
	self.is_drinking = self.is_drinking + 1;

	// Tiny delay prevents rare race conditions right as the box is grabbed.
	wait 0.05;

	// Grant perk (no bottle weapon switching; safest for all maps).
	if( !(self hasperk( perk )) )
	{
		self setperk( perk );
	}

	// Cleanup.
	if( IsDefined( self.is_drinking ) && self.is_drinking > 0 )
		self.is_drinking = self.is_drinking - 1;

	self.__perk_give_in_progress = 0;
	self.__perk_give_token = undefined;
	self notify( "burp" );
}



// ============================================================================
// SECTION 6: Shared “can buy” gate
//   Centralized checks to block interactions during glitch-prone states.
// ============================================================================

// ----------------------------------------------------------------------------
// can_buy()
//   Shared “purchase allowed” gate used across this script.
//   Blocks perk pickup / box actions during states that commonly cause glitches:
//   drinking, weapon swap, grenade throw, last stand, revive triggers, hacking,
//   invalid player states, reloading, or having no weapon.

// ============================================================================
// SECTION 6: Shared “can buy” gate
//   Centralized checks to block interactions during glitch-prone states.
// ============================================================================

// ----------------------------------------------------------------------------
can_buy()
{
	if( IsDefined( self.is_drinking ) && self.is_drinking > 0 )
	{
		return 0;
	}
	if( self isswitchingweapons() )
	{
		return 0;
	}
	if( self isthrowinggrenade() )
	{
		return 0;
	}
	if( self player_is_in_laststand() )
	{
		return 0;
	}
	current_weapon = self getcurrentweapon();
	if( is_equipment( current_weapon ) || is_equipment_that_blocks_purchase( current_weapon ) || is_placeable_mine( current_weapon ) )
	{
		return 0;
	}
	if( level.revive_tool == current_weapon || self in_revive_trigger() )
	{
		return 0;
	}
	if( current_weapon == "none" )
	{
		return 0;
	}
	if( self hacker_active() )
	{
		return 0;
	}
	if( !(is_player_valid( self )) )
	{
		return 0;
	}
	if( self isreloading() )
	{
		return 0;
	}
	return 1;

}
