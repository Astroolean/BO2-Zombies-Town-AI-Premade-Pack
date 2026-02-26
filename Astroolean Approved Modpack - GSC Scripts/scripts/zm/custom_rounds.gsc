// ╔════════════════════════════════════════════════════════════════════════════════╗
// ║  Cold War-Style Round Spawn Counts                                             ║
// ║  Black Ops II Zombies (Plutonium T6)                                           ║
// ║                                                                                ║
// ║  Created by: Astroolean                                                        ║
// ║                                                                                ║
// ║  What this script does                                                         ║
// ║   - Overrides the round spawn handler so each round's TOTAL zombie spawns      ║
// ║     follow a Cold War-like progression curve instead of the stock BO2 curve.   ║
// ║   - Rounds 1–5: uses fixed, hand-tuned totals per player count (1–4 players).  ║
// ║   - Round 6+: scales using zombie_ai_per_player plus a round-based multiplier, ║
// ║     then applies high-round caps so totals don't explode.                      ║
// ║   - Optional mixed spawns: can inject Hellhounds (very low odds) on high rounds║
// ║     when mixed rounds are enabled.                                             ║
// ║                                                                                ║
// ║  How it works (high level)                                                     ║
// ║   1) main() assigns level.round_spawn_func to cold_war_spawn().                ║
// ║   2) cold_war_spawn() runs every round and sets level.zombie_total to the      ║
// ║      computed number of remaining spawns for the round.                        ║
// ║   3) The main while-loop keeps spawning until zombie_total hits 0, while       ║
// ║      respecting actor limits, zone flags, and vanilla spawn checks.            ║
// ║                                                                                ║
// ║  Credits / notes                                                               ║
// ║   - Original concept/algorithm notes: Guilherme_INFR                           ║
// ║   - Pseudo-code insights: GerardS0406                                          ║
// ║   - Adaptation + implementation + tuning: Astroolean                           ║
// ║                                                                                ║
// ║  Important                                                                     ║
// ║   - This file is written to be "logic-safe": comments/formatting are here      ║
// ║     for maintainability, but the gameplay logic is kept intact.                ║
// ╚════════════════════════════════════════════════════════════════════════════════╝
//
// NOTE: This script is intentionally include-heavy because it plugs into the
// vanilla Zombies round/spawn pipeline. Do NOT delete includes unless you know
// exactly which symbols your map/mod needs at compile-time.
//
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_ffotd;
#include maps\mp\zombies\_zm;
#include maps\mp\_visionset_mgr;
#include maps\mp\zombies\_zm_devgui;
#include maps\mp\zombies\_zm_zonemgr;
#include maps\mp\zombies\_zm_unitrigger;
#include maps\mp\zombies\_zm_audio;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_bot;
#include maps\mp\zombies\_zm_clone;
#include maps\mp\zombies\_zm_buildables;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_magicbox;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm_playerhealth;
#include maps\mp\zombies\_zm_power;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_spawner;
#include maps\mp\zombies\_zm_gump;
#include maps\mp\zombies\_zm_timer;
#include maps\mp\zombies\_zm_traps;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_tombstone;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_pers_upgrades;
#include maps\mp\gametypes_zm\_zm_gametype;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include maps\mp\_demo;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_melee_weapon;
#include maps\mp\zombies\_zm_ai_dogs;
#include maps\mp\zombies\_zm_pers_upgrades_system;
#include maps\mp\gametypes_zm\_weapons;
#include maps\mp\zombies\_zm_ai_basic;
#include maps\mp\zombies\_zm_game_module;

main()
{
    // Entry point.
    // BO2/Plutonium loads this script and calls main() once on init.

    // Hook the per-round spawn function pointer.
    // The Zombies framework calls level.round_spawn_func() at the start of each round.
    level.round_spawn_func = ::cold_war_spawn;
}

cold_war_spawn()
{
    // Round handler.
    // This runs once per round and is responsible for:
    //  - computing the TOTAL number of spawns this round (level.zombie_total)
    //  - spawning zombies until the total reaches 0
    //  - respecting stock limits (ai/actor caps), zones, and spawn checks

    // Kill this thread cleanly if the game transitions to any of these states.
    level endon( "intermission" );
    level endon( "end_of_round" );
    level endon( "restart_round" );
    /# 
    level endon( "kill_round" );
    #/

    // If we're already in intermission, do nothing.
    if ( level.intermission )
        return;

    /# 
    if ( getdvarint( #"zombie_cheat" ) == 2 || getdvarint( #"zombie_cheat" ) >= 4 )
        return;
    #/

    // Safety: if no spawn locations are currently active, we can't spawn anything.
    // This can happen if zones aren't active or your map's spawner setup is broken.
    if ( level.zombie_spawn_locations.size < 1 )
    {
    /# 
        assertmsg( "No active spawners in the map. Check to see if the zone is active and if it's pointing to spawners." );
    #/
        return;
    }

    // Update per-round AI health scaling (vanilla call).
    ai_calculate_health( level.round_number );

    // count = how many AIs we successfully spawned this round thread (debug/telemetry).
    count = 0;

    // Snapshot current players.
    players = get_players();

    // Reset any per-player timers used by certain maps/modes.
    // (Keeps behavior consistent with the base round spawn flow.)
    for ( i = 0; i < players.size; i++ )
        players[i].zombification_time = 0;

    // Player count is used to scale totals.
    // NOTE: get_players().size is the safest count for live players in Zombies.
    player_num = get_players().size;

    // This is the round TOTAL we want to spawn.
    calculated_max_zombies = 0;

    // Rounds 1–5 are intentionally hardcoded.
    // Cold War's early game is very specific per player-count; using fixed totals
    // avoids weirdness from multiplier math on low rounds.
    if (level.round_number >= 1 && level.round_number <= 5)
    {
        calculated_max_zombies = cold_war_early_round_count(level.round_number, player_num);
    }
    else
    {
        // Round 6+ scaling.
        // We start from the map's base max AI and add an amount based on:
        //  - zombie_ai_per_player (vanilla tuning var)
        //  - a multiplier derived from the current round
        // This keeps scaling smooth but still controlled.
        calculated_max_zombies = level.zombie_vars["zombie_max_ai"];
        zombie_ai_per_player_base = level.zombie_vars["zombie_ai_per_player"];

        current_round_base_multiplier = level.round_number / 5;
        if (current_round_base_multiplier < 1)
            current_round_base_multiplier = 1;

        if (level.round_number >= 10)
            current_round_base_multiplier *= (level.round_number * 0.15);

        if (player_num == 1)
            calculated_max_zombies += int(0.5 * zombie_ai_per_player_base * current_round_base_multiplier);
        else
            calculated_max_zombies += int((player_num - 1) * zombie_ai_per_player_base * current_round_base_multiplier);

        // High-round caps (these override the multiplier result).
        // These values are tuned to keep late rounds closer to Cold War pacing.
        solo_duo_cap_round = 29;
        trio_quad_cap_round = 20;

        // SOLO cap behavior (Round 29+): alternate +2/+3 additions each round.
        if (player_num == 1 && level.round_number >= solo_duo_cap_round)
        {
            base_zombies = 97;
            added_zombies = 0;
            for (i = 0; i < (level.round_number - solo_duo_cap_round); i++)
            {
                if ((solo_duo_cap_round + i) % 2 == 1)
                    added_zombies += 2;
                else
                    added_zombies += 3;
            }
            calculated_max_zombies = base_zombies + added_zombies;
        }
        // DUO cap behavior (Round 29+): alternate +5/+6 additions each round.
        else if (player_num == 2 && level.round_number >= solo_duo_cap_round)
        {
            base_zombies = 180;
            added_zombies = 0;
            for (i = 0; i < (level.round_number - solo_duo_cap_round); i++)
            {
                if ((solo_duo_cap_round + i) % 2 == 1)
                    added_zombies += 5;
                else
                    added_zombies += 6;
            }
            calculated_max_zombies = base_zombies + added_zombies;
        }
        // TRIO cap behavior (Round 20+): mostly +7, with +8 every 5th round.
        else if (player_num == 3 && level.round_number >= trio_quad_cap_round)
        {
            base_zombies = 168;
            added_zombies = 0;
            for (i = 0; i < (level.round_number - trio_quad_cap_round); i++)
            {
                if ((trio_quad_cap_round + i) % 5 == 0)
                    added_zombies += 8;
                else
                    added_zombies += 7;
            }
            calculated_max_zombies = base_zombies + added_zombies;
        }
        // QUADS cap behavior (Round 20+): steady +9 per round.
        else if (player_num == 4 && level.round_number >= trio_quad_cap_round)
        {
            base_zombies = 204;
            calculated_max_zombies = base_zombies + ((level.round_number - trio_quad_cap_round) * 9);
        }
    }

    if (calculated_max_zombies <= 0)
        calculated_max_zombies = 1;

    // Apply the total to the live round counter.
    // We set level.zombie_total directly instead of using level.max_zombie_func.
    // Reason: some custom max_zombie helpers are written with different argument
    // counts than what the engine calls (engine usually calls with 1 arg).
    // A mismatch can crash scripts at runtime.
    if ( !( isdefined( level.kill_counter_hud ) && level.zombie_total > 0 ) )
    {
        level.zombie_total = calculated_max_zombies;
        level notify( "zombie_total_set" );
    }

    if ( isdefined( level.zombie_total_set_func ) )
        level thread [[ level.zombie_total_set_func ]]();

    // Vanilla behavior: optionally ramp zombie speed as rounds progress.
    // Keeping this preserves the expected feel on maps that rely on it.
    if ( level.round_number < 10 || level.speed_change_max > 0 )
        level thread zombie_speed_up();

    mixed_spawns = 0;
    old_spawn = undefined;

    while ( true )
    {
        // Respect AI limit and the remaining round total.
        // - zombie_ai_limit controls how many live zombies can exist at once.
        // - zombie_total is how many we still need to spawn this round.
        while ( get_current_zombie_count() >= level.zombie_ai_limit || level.zombie_total <= 0 )
            wait 0.1;

        // Respect actor limit (engine-level entity cap).
        // If we hit the limit, we clear corpses to free actors and try again.
        while ( get_current_actor_count() >= level.zombie_actor_limit )
        {
            clear_all_corpses();
            wait 0.1;
        }

        // The core framework controls when spawns are allowed via this flag.
        // This blocks until the round logic says we can spawn.
        flag_wait( "spawn_zombies" );

        while ( level.zombie_spawn_locations.size <= 0 )
            wait 0.1;

        // Stock + custom spawn checks (power, doors, zone state, etc.).
        run_custom_ai_spawn_checks();

        // Pick a random spawn point from the currently active pool.
        spawn_point = level.zombie_spawn_locations[randomint( level.zombie_spawn_locations.size )];

        // Small anti-repeat: avoid picking the exact same spawn point twice in a row.
        if ( !isdefined( old_spawn ) )
            old_spawn = spawn_point;
        else if ( spawn_point == old_spawn )
            spawn_point = level.zombie_spawn_locations[randomint( level.zombie_spawn_locations.size )];
        old_spawn = spawn_point;

        // Mixed spawns (Hellhounds).
        // This is OPTIONAL and only runs when mixed rounds are enabled.
        // The odds are intentionally tiny; the goal is occasional variety, not constant dogs.
        if ( isdefined( level.mixed_rounds_enabled ) && level.mixed_rounds_enabled == 1 )
        {
            spawn_dog = 0;

            if ( level.round_number > 30 )
            {
                if ( randomint( 100 ) < 3 )
                    spawn_dog = 1;
            }
            else if ( level.round_number > 25 && mixed_spawns < 3 )
            {
                if ( randomint( 100 ) < 2 )
                    spawn_dog = 1;
            }
            else if ( level.round_number > 20 && mixed_spawns < 2 )
            {
                if ( randomint( 100 ) < 2 )
                    spawn_dog = 1;
            }
            else if ( level.round_number > 15 && mixed_spawns < 1 )
            {
                if ( randomint( 100 ) < 1 )
                    spawn_dog = 1;
            }

            if ( spawn_dog )
            {
                keys = getarraykeys( level.zones );

                for ( i = 0; i < keys.size; i++ )
                {
                    if ( level.zones[keys[i]].is_occupied )
                    {
                        akeys = getarraykeys( level.zones[keys[i]].adjacent_zones );

                        for ( k = 0; k < akeys.size; k++ )
                        {
                            if ( level.zones[akeys[k]].is_active && !level.zones[akeys[k]].is_occupied && level.zones[akeys[k]].dog_locations.size > 0 )
                            {
                                maps\mp\zombies\_zm_ai_dogs::special_dog_spawn( undefined, 1 );
                                level.zombie_total--;
                                mixed_spawns++;
                                wait_network_frame();
                            }
                        }
                    }
                }
            }
        }

        ai = undefined;

        // Choose a spawner entity to use, then spawn.
        // This respects maps that use grouped spawners (multiple spawn sets by zone/script_int).
        if ( isdefined( level.zombie_spawners ) )
        {
            spawner = undefined;
            if ( isdefined( level.use_multiple_spawns ) && level.use_multiple_spawns )
            {
                if ( isdefined( spawn_point.script_int ) )
                {
                    if ( isdefined( level.zombie_spawn[spawn_point.script_int] ) && level.zombie_spawn[spawn_point.script_int].size )
                        spawner = random( level.zombie_spawn[spawn_point.script_int] );
                    else
                    {
                    /#
                        assertmsg( "Wanting to spawn from zombie group " + spawn_point.script_int + "but it doesn't exist" );
                    #/
                    }
                }
                else if ( isdefined( level.zones[spawn_point.zone_name].script_int ) && level.zones[spawn_point.zone_name].script_int )
                    spawner = random( level.zombie_spawn[level.zones[spawn_point.zone_name].script_int] );
                else if ( isdefined( level.spawner_int ) && ( isdefined( level.zombie_spawn[level.spawner_int] ) && level.zombie_spawn[level.spawner_int].size ) )
                    spawner = random( level.zombie_spawn[level.spawner_int] );
                else
                    spawner = random( level.zombie_spawners );
            }
            else
                spawner = random( level.zombie_spawners );

            // Spawn the zombie.
            // Params:
            //  - spawner:      the spawner entity chosen above
            //  - targetname:   used by spawn routines / telemetry
            //  - spawn_point:  location/zone pick
            ai = spawn_zombie( spawner, spawner.targetname, spawn_point );
        }

        if ( isdefined( ai ) )
        {
            // We successfully spawned an AI; consume one from this round's remaining total.
            level.zombie_total--;

            // Safety thread used by the base framework to prevent stuck spawns.
            ai thread round_spawn_failsafe();

            count++;
        }

        // Delay between spawn attempts (map-tuned) + network frame sync.
        wait( level.zombie_vars["zombie_spawn_delay"] );
        wait_network_frame();
    }
}

// Helper: fixed early-round totals (Rounds 1–5)
// Cold War's early progression is more rigid than BO2's; these totals are
// intentionally locked per player count.
//
// n_round:   1..5
// n_players: 1..4 (clamped)
// returns:   integer total zombies to spawn this round
cold_war_early_round_count(n_round, n_players)
{
    // Clamp player count to valid range
    if (!isdefined(n_players) || n_players < 1)
        n_players = 1;
    if (n_players > 4)
        n_players = 4;

    // Round 1-5 counts: [1p, 2p, 3p, 4p]
    if (n_round == 1)
    {
        counts = array(6, 8, 11, 14);
        return counts[n_players - 1];
    }
    else if (n_round == 2)
    {
        counts = array(9, 11, 14, 18);
        return counts[n_players - 1];
    }
    else if (n_round == 3)
    {
        counts = array(13, 15, 20, 25);
        return counts[n_players - 1];
    }
    else if (n_round == 4)
    {
        counts = array(18, 20, 25, 33);
        return counts[n_players - 1];
    }
    else if (n_round == 5)
    {
        counts = array(24, 25, 32, 42);
        return counts[n_players - 1];
    }

    return 6;
}
