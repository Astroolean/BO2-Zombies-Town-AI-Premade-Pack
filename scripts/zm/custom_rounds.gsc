// Black Ops 2 Zombies: Cold War-like Zombie Spawn Algorithm (Improved Version)
// This script modifies the default zombie spawning behavior in Black Ops 2
// to mimic the zombie count progression found in Call of Duty: Cold War Zombies.
//
// Original algorithm by Guilherme_INFR, with pseudo-code insights by GerardS0406.
// This improved version aims for closer replication of Cold War's early game
// and provides more detailed comments for clarity.

// --- Include necessary game scripts ---
// These are standard includes for Zombies modding in Black Ops 2.
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

// --- Main entry point for the GSC script ---
// This function is automatically called when the map loads.
main()
{
    // Override the default round spawn function with our custom Cold War-like logic.
    level.round_spawn_func = ::cold_war_spawn;
}

// --- Custom Cold War-like Zombie Spawn Function ---
// This function is responsible for calculating and managing the total number of
// zombies that will spawn in the current round, based on Cold War's progression.
cold_war_spawn()
{
    // Set up endons to terminate this thread when certain game events occur.
    level endon( "intermission" );
    level endon( "end_of_round" );
    level endon( "restart_round" );
    /# // Debugging/development specific endon, typically commented out in release.
    level endon( "kill_round" );
    #/

    // If the game is in an intermission (between rounds), do not spawn zombies.
    if ( level.intermission )
        return;

    /# // Debugging/cheat related check, typically commented out.
    if ( getdvarint( #"zombie_cheat" ) == 2 || getdvarint( #"zombie_cheat" ) >= 4 )
        return;
    #/

    // Check if there are any active zombie spawn locations. If not, return to prevent errors.
    if ( level.zombie_spawn_locations.size < 1 )
    {
    /# // Assert message for development, typically commented out.
        assertmsg( "No active spawners in the map. Check to see if the zone is active and if it's pointing to spawners." );
    #/
        return;
    }

    // Call the game's default function to calculate zombie health for the current round.
    ai_calculate_health( level.round_number );
    
    // Initialize a counter for spawned zombies (used in the original script's loop).
    count = 0;
    
    // Get all active players in the game.
    players = get_players();

    // Reset zombification time for all players (related to last stand/revive mechanics).
    for ( i = 0; i < players.size; i++ )
        players[i].zombification_time = 0;

    // --- Cold War-like Zombie Count Logic Starts Here ---

    // Get the current number of players to scale zombie spawns appropriately.
    player_num = get_players().size;

    // This variable will store the final calculated maximum number of zombies for the current round.
    calculated_max_zombies = 0;

    // Step 1: Handle hardcoded zombie counts for early rounds (1-5).
    // Cold War has specific, fixed zombie counts for these initial rounds,
    // which are handled by the `default_max_zombie_func`.
    if (level.round_number >= 1 && level.round_number <= 5) {
        calculated_max_zombies = default_max_zombie_func(0, level.round_number, player_num);
        // Note: We pass 0 as the first argument to default_max_zombie_func because for these rounds,
        // it completely overrides any prior calculation.
    } else {
        // Step 2: Calculate zombies for mid-rounds (Rounds 6 up to the dynamic cap thresholds).
        // This section uses a multiplier-based logic that smoothly transitions into the high-round caps.
        // It reflects Cold War's scaling before its distinct fixed-increment patterns begin.

        // Get the base maximum AI capacity (e.g., 24 active zombies without player/round scaling).
        // GerardS0406 suggested this is typically 24 in Cold War.
        calculated_max_zombies = level.zombie_vars["zombie_max_ai"];

        // Get the "zombies per player" base value (e.g., 6 additional zombies per player).
        // GerardS0406 suggested this is typically 6 in Cold War.
        zombie_ai_per_player_base = level.zombie_vars["zombie_ai_per_player"];

        // Calculate a base multiplier that increases with the round number.
        // This is derived from Cold War's pseudo-code logic (n_round / 5).
        current_round_base_multiplier = level.round_number / 5;
        if (current_round_base_multiplier < 1) {
            current_round_base_multiplier = 1; // Ensure the multiplier is at least 1.
        }

        // Apply an additional exponential multiplier for rounds 10 and beyond.
        // GerardS0406 indicated a value of 0.15 for this, based on BO4's equivalent logic.
        if (level.round_number >= 10) {
            current_round_base_multiplier *= (level.round_number * 0.15);
        }

        // Add player-specific zombies based on the calculated multiplier.
        // This applies to rounds before the hard dynamic caps (Round 20/29) kick in.
        if (player_num == 1) {
            // For solo, original mod uses 0.5 for this part of the calculation.
            calculated_max_zombies += int(0.5 * zombie_ai_per_player_base * current_round_base_multiplier);
        } else {
            // For 2, 3, or 4 players, (player_num - 1) is used for scaling.
            calculated_max_zombies += int((player_num - 1) * zombie_ai_per_player_base * current_round_base_multiplier);
        }

        // Step 3: Apply the distinct dynamic caps for higher rounds (Round 20 or 29 onwards).
        // These are the specific, fixed-increment patterns Guilherme_INFR reverse-engineered.
        // These calculations *override* the previous multiplier-based calculation for `calculated_max_zombies`.
        solo_duo_cap_round = 29; // Threshold for 1-2 players
        trio_quad_cap_round = 20; // Threshold for 3-4 players

        if (player_num == 1 && level.round_number >= solo_duo_cap_round) {
            // Logic for 1 player from Round 29 onwards
            base_zombies = 97; // Starting total zombies for Round 29
            added_zombies = 0;
            // Loop from Round 29 up to the current round to accumulate added zombies.
            for (i = 0; i < (level.round_number - solo_duo_cap_round); i++) {
                if ((solo_duo_cap_round + i) % 2 == 1) { // If the specific round (29 + i) is odd, add 2 zombies
                    added_zombies += 2;
                } else { // If the specific round (29 + i) is even, add 3 zombies
                    added_zombies += 3;
                }
            }
            calculated_max_zombies = base_zombies + added_zombies;
        } else if (player_num == 2 && level.round_number >= solo_duo_cap_round) {
            // Logic for 2 players from Round 29 onwards
            base_zombies = 180; // Starting total zombies for Round 29
            added_zombies = 0;
            // Loop from Round 29 up to the current round.
            for (i = 0; i < (level.round_number - solo_duo_cap_round); i++) {
                if ((solo_duo_cap_round + i) % 2 == 1) { // If the specific round (29 + i) is odd, add 5 zombies
                    added_zombies += 5;
                } else { // If the specific round (29 + i) is even, add 6 zombies
                    added_zombies += 6;
                }
            }
            calculated_max_zombies = base_zombies + added_zombies;
        } else if (player_num == 3 && level.round_number >= trio_quad_cap_round) {
            // Logic for 3 players from Round 20 onwards
            base_zombies = 168; // Starting total zombies for Round 20
            added_zombies = 0;
            // Loop from Round 20 up to the current round.
            for (i = 0; i < (level.round_number - trio_quad_cap_round); i++) {
                if ((trio_quad_cap_round + i) % 5 == 0) { // If the specific round (20 + i) is a multiple of 5, add 8 zombies
                    added_zombies += 8;
                } else { // For other rounds, add 7 zombies
                    added_zombies += 7;
                }
            }
            calculated_max_zombies = base_zombies + added_zombies;
        } else if (player_num == 4 && level.round_number >= trio_quad_cap_round) {
            // Logic for 4 players from Round 20 onwards
            base_zombies = 204; // Starting total zombies for Round 20
            // Simply add 9 zombies per round for every round past Round 20.
            calculated_max_zombies = base_zombies + ((level.round_number - trio_quad_cap_round) * 9);
        }
    }

    // Ensure that the calculated maximum zombies is at least 1 to prevent unexpected behavior (e.g., zero zombies spawning).
    if (calculated_max_zombies <= 0) {
        calculated_max_zombies = 1;
    }

    // --- End of Cold War-like Zombie Count Logic ---


    // --- Standard BO2 Zombie Spawning and Management Logic ---
    // This section largely remains as per the original BO2 implementation,
    // now using our `calculated_max_zombies` for the total zombies this round.

    // If the game's default max zombie function is not defined, set it.
    // (In a mod, our `cold_war_spawn` directly manages the total, but this ensures compatibility).
    if ( !isdefined( level.max_zombie_func ) )
        level.max_zombie_func = ::default_max_zombie_func; // This will point to the game's built-in `default_max_zombie_func`

    // If the total zombies for the round haven't been set yet (or are 0), set them
    // using our calculated value.
    if ( !( isdefined( level.kill_counter_hud ) && level.zombie_total > 0 ) )
    {
        // Use the game's `level.max_zombie_func` to officially set `level.zombie_total`.
        // We pass our `calculated_max_zombies` to it.
        level.zombie_total = [[ level.max_zombie_func ]]( calculated_max_zombies );
        level notify( "zombie_total_set" ); // Notify the game that the zombie total has been set.
    }

    // If a custom function for setting zombie total is defined, run it.
    if ( isdefined( level.zombie_total_set_func ) )
        level thread [[ level.zombie_total_set_func ]]();

    // Trigger zombie speed-up logic for early rounds or if speed changes are active.
    if ( level.round_number < 10 || level.speed_change_max > 0 )
        level thread zombie_speed_up();

    // Variables for managing random spawn points to avoid immediate re-use.
    mixed_spawns = 0; // Related to mixed enemy spawns like dogs.
    old_spawn = undefined;

    // Main loop for spawning individual zombies during the round.
    while ( true )
    {
        // Wait until current active zombies are below the limit and total zombies for the round remain.
        while ( get_current_zombie_count() >= level.zombie_ai_limit || level.zombie_total <= 0 )
            wait 0.1;

        // If the total actor count (including corpses) is too high, clear corpses to make room.
        while ( get_current_actor_count() >= level.zombie_actor_limit )
        {
            clear_all_corpses();
            wait 0.1;
        }

        // Wait for the "spawn_zombies" flag to be set (signaling it's time to spawn).
        flag_wait( "spawn_zombies" );

        // Ensure there are active spawn locations before attempting to spawn.
        while ( level.zombie_spawn_locations.size <= 0 )
            wait 0.1;

        // Run any custom AI spawn checks (defined elsewhere in the game's scripts).
        run_custom_ai_spawn_checks();
        
        // Select a random spawn point.
        spawn_point = level.zombie_spawn_locations[randomint( level.zombie_spawn_locations.size )];

        // Logic to try and avoid spawning two zombies from the exact same point consecutively.
        if ( !isdefined( old_spawn ) )
            old_spawn = spawn_point;
        else if ( spawn_point == old_spawn )
            spawn_point = level.zombie_spawn_locations[randomint( level.zombie_spawn_locations.size )];
        old_spawn = spawn_point;

        // --- Mixed Spawns Logic (e.g., Hellhounds) ---
        // This section is kept as is from the original provided script.
        if ( isdefined( level.mixed_rounds_enabled ) && level.mixed_rounds_enabled == 1 )
        {
            spawn_dog = 0;

            // Chances for dog spawns increase with higher rounds.
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
                                // Spawn a special dog and decrement the total zombie count.
                                maps\mp\zombies\_zm_ai_dogs::special_dog_spawn( undefined, 1 );
                                level.zombie_total--;
                                wait_network_frame(); // Wait a frame to prevent too many spawns at once.
                            }
                        }
                    }
                }
            }
        }

        // Attempt to spawn a zombie at the chosen spawn point.
        ai = undefined; // Initialize ai variable
        if ( isdefined( level.zombie_spawners ) )
        {
            spawner = undefined;
            // Logic to select the specific spawner based on zone or group.
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
                else if ( isdefined( level.spawner_int ) && ( isdefined( level.zombie_spawn[level.spawner_int].size ) && level.zombie_spawn[level.spawner_int].size ) )
                    spawner = random( level.zombie_spawn[level.spawner_int] );
                else
                    spawner = random( level.zombie_spawners );
            }
            else
                spawner = random( level.zombie_spawners );

            // Call the game's function to spawn a zombie.
            ai = spawn_zombie( spawner, spawner.targetname, spawn_point );
        }

        // If a zombie was successfully spawned, decrement the total for the round.
        if ( isdefined( ai ) )
        {
            level.zombie_total--;
            ai thread round_spawn_failsafe(); // Ensure the spawned AI has a failsafe if it gets stuck.
            count++; // Increment count of zombies spawned this loop.
        }

        // Wait for a short delay before attempting to spawn the next zombie.
        wait( level.zombie_vars["zombie_spawn_delay"] );
        wait_network_frame(); // Wait a network frame for synchronization.
    }
}

// --- default_max_zombie_func (Helper Function for Early Rounds) ---
// This function determines the exact number of zombies for rounds 1-5, based on player count.
// It uses hardcoded arrays, as found in Cold War's pseudo-code, ensuring early rounds match CW's behavior.
// Parameters:
//   - max_num: This parameter is used as a fallback if the player count is out of expected range.
//              In `cold_war_spawn`, we pass 0 for rounds 1-5 as this function fully determines the count.
//   - n_round: The current round number.
//   - n_players: The current number of players in the game.
default_max_zombie_func(max_num, n_round, n_players)
{
    // Arrays storing specific zombie counts for rounds 1-5 based on player count.
    // Index mapping: 0 = 1 player, 1 = 2 players, 2 = 3 players, 3 = 4 players.
    // The fifth value (index 4) in these arrays (e.g., '17' for round1Counts)
    // is likely for a hypothetical 5th player or leftover development data.
    // We explicitly handle player counts 1-4 for standard gameplay.
    round1Counts = array(6, 8, 11, 14, 17);
    round2Counts = array(9, 11, 14, 18, 21);
    round3Counts = array(13, 15, 20, 25, 31);
    round4Counts = array(18, 20, 25, 33, 40);
    round5Counts = array(24, 25, 32, 42, 48);

    // Ensure n_players is within the expected range (1 to 4) to prevent out-of-bounds array access.
    if (n_players < 1 || n_players > 4) {
        // If player count is outside 1-4, return the `max_num` passed in (which would be 0 or a fallback),
        // or a default sensible value like `level.zombie_vars["zombie_max_ai"]` if this were truly a standalone fallback.
        // For our usage in `cold_war_spawn`, this means the hardcoded part won't apply if player count is weird.
        return max_num;
    }

    // Use a switch statement to apply the hardcoded counts for rounds 1-5.
    switch (n_round) {
        case 1:
            max_num = round1Counts[n_players - 1];
            break;
        case 2:
            max_num = round2Counts[n_players - 1];
            break;
        case 3:
            max_num = round3Counts[n_players - 1];
            break;
        case 4:
            max_num = round4Counts[n_players - 1];
            break;
        case 5:
            max_num = round5Counts[n_players - 1];
            break;
        default:
            // For rounds beyond 5, this function doesn't modify `max_num`.
            // The main `cold_war_spawn` function's dynamic logic (Step 2 & 3) handles these rounds.
            break;
    }
    return max_num;
}
