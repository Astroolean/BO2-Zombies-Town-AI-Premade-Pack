// ╔════════════════════════════════════════════════════════════════════════════╗
// ║  CUSTOM POWERUP DROP REBALANCE + POWERUP REWORKS (BO2 ZOMBIES / T6)        ║
// ║  Created by: Astroolean                                                    ║
// ║                                                                            ║
// ║  What this file does (high level):                                         ║
// ║   1) Rebuilds the powerup drop cycle each round using weighted rules.      ║
// ║      - This controls WHAT powerup is next when a drop happens.             ║
// ║      - It does NOT force drops; the game still uses its normal RNG.        ║
// ║   2) Adjusts drop pacing (how often drops can occur, and per-round caps).  ║
// ║   3) Adds “late-round” tweaks so certain drops stay useful:                ║
// ║      - Carpenter: bonus points on higher rounds.                           ║
// ║      - Nuke: percentage-based damage on higher rounds + a small bonus.     ║
// ║   4) Prevents a bad overlap: Double Points sitting in the “next slot”      ║
// ║      while Insta-Kill is already active (swaps the slot forward).          ║
// ║                                                                            ║
// ║  Install path (Plutonium):                                                 ║
// ║   %localappdata%\Plutonium\storage\t6\scripts\zm\                          ║
// ║                                                                            ║
// ║  Safety promise: only comments/organization/whitespace were changed here.  ║
// ║  Gameplay logic is intentionally left as-is.                               ║
// ╚════════════════════════════════════════════════════════════════════════════╝

// ----------------------------------------------------------------------------
// Dependencies
// ----------------------------------------------------------------------------
// common_scripts\utility / maps\mp\_utility provide basic helpers like:
//  - array_randomize(), gettime(), isdefined(), get_players(), etc.
// _zm_powerups exposes the powerup system arrays/index used by the engine.
// _zm_score is used for adding points (Carpenter/Nuke reworks).
// ----------------------------------------------------------------------------
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm;


// ----------------------------------------------------------------------------
// main()
// ----------------------------------------------------------------------------
// Script entry point.
// - Sets a marker flag on level so other scripts can detect this mod is active.
// - Starts the player connect loop (so each player gets ammo tracking).
// - Starts the global rebalance initializer (waits for blackscreen).
// ----------------------------------------------------------------------------
main()
{
    // Simple marker flag (debug / other scripts can check if this mod is running).
    level.custom_powerup_rebalance = 1;

    // Start: waits for players to connect, then spawns per-player ammo tracking.
    level thread on_player_connect();
    // Start: waits for game init, then configures drop pacing and cycle logic.
    level thread powerup_rebalance_init();
}


// ----------------------------------------------------------------------------
// on_player_connect()
// ----------------------------------------------------------------------------
// Waits for players to connect, then starts their per-player ammo watcher.
// The ammo watcher only sets a lightweight boolean (player.low_ammo) used by
// the weighted Max Ammo logic later.
// ----------------------------------------------------------------------------
on_player_connect()
{
    level endon( "end_game" );

    for (;;)
    {
        // Engine event: fired when a player entity is fully connected.
        level waittill( "connected", player );

        if ( !isdefined( player ) )
            continue;

        player.low_ammo = 0;
        // Player thread: keeps player.low_ammo updated for Max Ammo weighting.
        player thread track_player_ammo_state();
    }
}


// ----------------------------------------------------------------------------
// track_player_ammo_state()
// ----------------------------------------------------------------------------
// Runs on each player.
// - Every few seconds, checks the player’s currently-held weapon ammo.
// - Calculates total ammo percentage (stock + clip) vs (max stock + max clip).
// - Sets self.low_ammo = 1 when below 25% total ammo, else 0.
// Notes:
// - This is intentionally simple and fast; it doesn’t try to be “perfect” for
//   every weapon type — it’s just a “Max Ammo should be more likely” hint.
// ----------------------------------------------------------------------------
track_player_ammo_state()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    self.low_ammo = 0;

    for (;;)
    {
        wait 5;

        if ( !isdefined( self ) || !isalive( self ) )
            continue;

        // Current weapon only (this is fast and good enough for “low ammo” hinting).
        weapon = self getcurrentweapon();
        if ( !isdefined( weapon ) || weapon == "none" || weapon == "" )
            continue;

        // Max reserve ammo for this weapon (not including current clip).
        max_stock = weaponmaxammo( weapon );
        if ( !isdefined( max_stock ) || max_stock <= 0 )
        {
            self.low_ammo = 0;
            continue;
        }

        // Current reserve ammo (stock) and current clip ammo.
        stock = self getweaponammostock( weapon );
        clip = self getweaponammoclip( weapon );
        clip_max = weaponclipsize( weapon );

        if ( !isdefined( stock ) )
            stock = 0;
        if ( !isdefined( clip ) )
            clip = 0;
        if ( !isdefined( clip_max ) )
            clip_max = 0;

        // Total max ammo we compare against = max reserve + max clip.
        total_max = max_stock + clip_max;

        if ( total_max <= 0 )
        {
            self.low_ammo = 0;
            continue;
        }

        // Percent of total ammo remaining (reserve + clip).
        ammo_pct = ((stock + clip) * 100) / total_max;

        if ( ammo_pct < 25 )
            self.low_ammo = 1;
        else
            self.low_ammo = 0;
    }
}


// ----------------------------------------------------------------------------
// powerup_rebalance_init()
// ----------------------------------------------------------------------------
// Global initializer for the rebalance system.
// - Waits until "initial_blackscreen_passed" so zombie globals are ready.
// - Sets baseline drop pacing values in level.zombie_vars:
//     zombie_powerup_drop_increment       (points threshold between drops)
//     zombie_powerup_drop_max_per_round   (hard cap per round)
// - Initializes lightweight timers for active powerups (IK / Double Points).
// - Starts all global monitoring threads:
//     monitor_round_change()     -> updates drop caps/threshold by round
//     weighted_powerup_cycle()   -> rebuilds drop cycle each round
//     monitor_powerup_grabs()    -> tracks powerup grabs + late-round reworks
//     smart_overlap_guard()      -> prevents IK+DP “next slot” overlap
// ----------------------------------------------------------------------------
powerup_rebalance_init()
{
    level endon( "end_game" );

    // Wait until core zombie systems are initialized (safe time to touch zombie_vars).
    flag_wait( "initial_blackscreen_passed" );
    wait 1;

    if ( !isdefined( level.zombie_vars ) )
        return;

    // Score threshold between allowed drops (lower = more frequent drops).
    level.zombie_vars["zombie_powerup_drop_increment"] = 1500;
    // Hard cap of powerups that can spawn per round.
    level.zombie_vars["zombie_powerup_drop_max_per_round"] = 4;

    // Timers (ms) updated on pickup; used by overlap rules / weighting.
    level.custom_insta_kill_active_until = 0;
    level.custom_double_points_active_until = 0;

    level thread monitor_round_change();
    level thread weighted_powerup_cycle();
    level thread monitor_powerup_grabs();
    level thread smart_overlap_guard();
}

// ============================================================
// ROUND CHANGE MONITOR
// ============================================================

// ----------------------------------------------------------------------------
// monitor_round_change()
// ----------------------------------------------------------------------------
// Runs once per round transition.
// - Uses the "between_round_over" event as the “new round is live” moment.
// - Scales how many drops are allowed per round (more rounds -> more cap).
// - Lowers the score threshold between drops on higher rounds so drops still
//   show up at a useful pace when zombie health is higher and rounds are long.
// ----------------------------------------------------------------------------
monitor_round_change()
{
    level endon( "end_game" );

    for (;;)
    {
        // Engine event: fired when the between-round period ends (new round begins).
        level waittill( "between_round_over" );

        if ( !isdefined( level.round_number ) )
            continue;

        if ( !isdefined( level.zombie_vars ) )
            continue;

        // Early rounds: keep it close to vanilla.
        if ( level.round_number <= 10 )
            level.zombie_vars["zombie_powerup_drop_max_per_round"] = 4;
        // Mid rounds: slight increase in allowed drops.
        else if ( level.round_number <= 20 )
            level.zombie_vars["zombie_powerup_drop_max_per_round"] = 5;
        // Later rounds: allow more drops as zombie count/health climbs.
        else if ( level.round_number <= 35 )
            level.zombie_vars["zombie_powerup_drop_max_per_round"] = 6;
        // High rounds: highest cap.
        else
            level.zombie_vars["zombie_powerup_drop_max_per_round"] = 7;

        // Drop threshold scaling: later rounds lower the threshold so drops still happen.
        if ( level.round_number <= 15 )
            level.zombie_vars["zombie_powerup_drop_increment"] = 1500;
        // Mid-high rounds: a bit more frequent.
        else if ( level.round_number <= 30 )
            level.zombie_vars["zombie_powerup_drop_increment"] = 1200;
        // High rounds: lowest threshold (most frequent drops).
        else
            level.zombie_vars["zombie_powerup_drop_increment"] = 1000;
    }
}

// ============================================================
// WEIGHTED POWERUP CYCLE
// ============================================================

// ----------------------------------------------------------------------------
// weighted_powerup_cycle()
// ----------------------------------------------------------------------------
// Keeps level.zombie_powerup_array refreshed.
// - Waits a few seconds after match start, then applies a fresh weighted cycle.
// - Re-applies after every round transition ("between_round_over").
// Important:
// - The engine consumes level.zombie_powerup_array like a queue using
//   level.zombie_powerup_index. Resetting index to 0 makes the new cycle active.
// ----------------------------------------------------------------------------
weighted_powerup_cycle()
{
    level endon( "end_game" );

    wait 5;

    apply_weighted_cycle_now();

    for (;;)
    {
        // Engine event: fired when the between-round period ends (new round begins).
        level waittill( "between_round_over" );
        wait 0.5;
        apply_weighted_cycle_now();
    }
}


// ----------------------------------------------------------------------------
// apply_weighted_cycle_now()
// ----------------------------------------------------------------------------
// Builds a new weighted pool and replaces the engine’s powerup cycle array.
// This is the “commit” step that actually changes upcoming drops.
// ----------------------------------------------------------------------------
apply_weighted_cycle_now()
{
    if ( !isdefined( level.zombie_powerup_array ) )
        return;

    if ( !isdefined( level.round_number ) )
        return;

    // Build a brand-new weighted cycle based on round + player ammo state.
    new_array = build_weighted_cycle();

    if ( isdefined( new_array ) && new_array.size > 0 )
    {
        level.zombie_powerup_array = new_array;
        level.zombie_powerup_index = 0;
    }
}


// ----------------------------------------------------------------------------
// build_weighted_cycle()
// ----------------------------------------------------------------------------
// Creates a weighted list (“pool”) of powerup names.
// The more times a name appears in the pool, the more likely it becomes in the
// randomized result.
// Weighting rules used here:
// - Max Ammo ("full_ammo") increases if players are low on ammo and on later rounds.
// - Insta-Kill weight increases on later rounds (helps with tanky zombies).
// - Double Points weight reduces on later rounds and is reduced while IK is active.
// - Nuke weight increases mid rounds.
// - Carpenter reduces after round 15 (because it’s reworked into point bonus).
// - Fire Sale becomes more common after round 10/20.
// Anti-repeat:
// - After randomize, a pass attempts to swap away any immediate back-to-back duplicates.
// ----------------------------------------------------------------------------
build_weighted_cycle()
{
    // "pool" is a weighted list. More copies of a name => more likely in final cycle.
    pool = [];

    // -------------------------------
    // Max Ammo weighting
    // -------------------------------
    // Baseline count + boosts:
    // - +1 per player currently flagged low_ammo
    // - +1 extra on later rounds (25+)
    // Capped to prevent the cycle becoming “all ammo”.
    max_ammo_count = 3;
    players = get_players();
    if ( isdefined( players ) )
    {
        for ( i = 0; i < players.size; i++ )
        {
            if ( isdefined( players[i] ) && isdefined( players[i].low_ammo ) && players[i].low_ammo )
                max_ammo_count++;
        }
    }
    if ( isdefined( level.round_number ) && level.round_number >= 25 )
        max_ammo_count++;
    if ( max_ammo_count > 8 )
        max_ammo_count = 8;
    for ( i = 0; i < max_ammo_count; i++ )
        pool[pool.size] = "full_ammo";


    // -------------------------------
    // Insta-Kill weighting
    // -------------------------------
    // Higher rounds => heavier weighting to help with tanky zombies.
    ik_count = 2;
    if ( isdefined( level.round_number ) )
    {
        if ( level.round_number >= 15 )
            ik_count = 3;
        if ( level.round_number >= 30 )
            ik_count = 4;
    }
    for ( i = 0; i < ik_count; i++ )
        pool[pool.size] = "insta_kill";


    // -------------------------------
    // Double Points weighting
    // -------------------------------
    // Reduced later, and reduced while Insta-Kill is active (overlap protection).
    dp_count = 2;
    if ( isdefined( level.round_number ) && level.round_number >= 30 )
        dp_count = 1;

    if ( is_custom_powerup_active( "insta_kill" ) && dp_count > 0 )
        dp_count--;
    for ( i = 0; i < dp_count; i++ )
        pool[pool.size] = "double_points";


    // -------------------------------
    // Nuke weighting
    // -------------------------------
    // Slightly boosted after round 20 (and nuke is reworked on 15+).
    nuke_count = 2;
    if ( isdefined( level.round_number ) && level.round_number >= 20 )
        nuke_count = 3;
    for ( i = 0; i < nuke_count; i++ )
        pool[pool.size] = "nuke";


    // -------------------------------
    // Carpenter weighting
    // -------------------------------
    // De-weighted after round 15 because it becomes a points-bonus drop.
    carp_count = 2;
    if ( isdefined( level.round_number ) && level.round_number >= 15 )
        carp_count = 1;
    for ( i = 0; i < carp_count; i++ )
        pool[pool.size] = "carpenter";


    // -------------------------------
    // Fire Sale weighting
    // -------------------------------
    // Becomes more common after round 10, and again after round 20.
    fs_count = 1;
    if ( isdefined( level.round_number ) )
    {
        if ( level.round_number >= 10 )
            fs_count = 2;
        if ( level.round_number >= 20 )
            fs_count = 3;
    }
    for ( i = 0; i < fs_count; i++ )
        pool[pool.size] = "fire_sale";

    if ( pool.size <= 0 )
        return pool;


    // Randomize the weighted pool into a cycle order.
    pool = array_randomize( pool );

    if ( pool.size > 1 )
    {
        for ( i = 1; i < pool.size; i++ )
        {
            // Anti-repeat pass: avoid immediate back-to-back duplicates where possible.
            if ( pool[i] == pool[i - 1] )
            {
                swapped = 0;
                for ( j = i + 1; j < pool.size; j++ )
                {
                    if ( pool[j] != pool[i] )
                    {
                        temp = pool[i];
                        pool[i] = pool[j];
                        pool[j] = temp;
                        swapped = 1;
                        break;
                    }
                }
                if ( !swapped )
                    break;
            }
        }
    }

    return pool;
}


// ----------------------------------------------------------------------------
// is_custom_powerup_active( powerup_name )
// ----------------------------------------------------------------------------
// Lightweight “active window” tracker for specific powerups.
// We update these timers when a powerup is grabbed (see monitor_powerup_grabs()).
// This is used for overlap rules (ex: don’t line up Double Points while IK is active).
// Timers use gettime() (milliseconds).
// ----------------------------------------------------------------------------
is_custom_powerup_active( powerup_name )
{
    // gettime() returns time in milliseconds.
    now = gettime();

    if ( powerup_name == "insta_kill" )
    {
        if ( isdefined( level.custom_insta_kill_active_until ) && level.custom_insta_kill_active_until > now )
            return 1;
        return 0;
    }

    if ( powerup_name == "double_points" )
    {
        if ( isdefined( level.custom_double_points_active_until ) && level.custom_double_points_active_until > now )
            return 1;
        return 0;
    }

    return 0;
}


// ----------------------------------------------------------------------------
// smart_overlap_guard()
// ----------------------------------------------------------------------------
// Prevents a wasteful combo: Double Points sitting in the NEXT drop slot while
// Insta-Kill is already active.
// If IK is active and the current “next slot” is Double Points, we search forward
// for the next non-Double-Points entry and swap it into the next slot.
// This does NOT remove Double Points — it just delays it to a better moment.
// ----------------------------------------------------------------------------
smart_overlap_guard()
{
    level endon( "end_game" );

    for (;;)
    {
        wait 0.25;

        // Only do overlap work while Insta-Kill is active.
        if ( !is_custom_powerup_active( "insta_kill" ) )
            continue;

        if ( !isdefined( level.zombie_powerup_array ) )
            continue;

        if ( !isdefined( level.zombie_powerup_index ) )
            continue;

        if ( level.zombie_powerup_array.size <= 0 )
            continue;

        idx = level.zombie_powerup_index;
        if ( idx < 0 || idx >= level.zombie_powerup_array.size )
            continue;

        if ( !isdefined( level.zombie_powerup_array[idx] ) )
            continue;

        // If the next slot isn’t Double Points, there’s nothing to fix.
        if ( level.zombie_powerup_array[idx] != "double_points" )
            continue;

        // Search forward for the next non-Double-Points entry to swap into the next slot.
        swap_idx = -1;

        for ( i = idx + 1; i < level.zombie_powerup_array.size; i++ )
        {
            if ( !isdefined( level.zombie_powerup_array[i] ) )
                continue;

            if ( level.zombie_powerup_array[i] == "double_points" )
                continue;

            swap_idx = i;
            break;
        }

        if ( swap_idx < 0 )
            continue;

        temp = level.zombie_powerup_array[idx];
        level.zombie_powerup_array[idx] = level.zombie_powerup_array[swap_idx];
        level.zombie_powerup_array[swap_idx] = temp;
    }
}

// ============================================================
// POWERUP GRAB MONITOR
// ============================================================

// ----------------------------------------------------------------------------
// monitor_powerup_grabs()
// ----------------------------------------------------------------------------
// Listens to the "powerup_grabbed" event and reacts to certain powerups.
// - Records active windows for Insta-Kill and Double Points (35 seconds).
// - Triggers late-round reworks:
//     Carpenter (round 15+) -> bonus points to alive players
//     Nuke (round 15+)      -> percentage-based damage to all zombies + bonus
// ----------------------------------------------------------------------------
monitor_powerup_grabs()
{
    level endon( "end_game" );

    for (;;)
    {
        // Engine event: a player picked up a powerup drop.
        level waittill( "powerup_grabbed", powerup_ent, player );

        if ( !isdefined( powerup_ent ) )
            continue;

        if ( !isdefined( player ) )
            continue;

        if ( !isalive( player ) )
            continue;

        // Powerup entities store a string name in powerup_ent.powerup_name.
        powerup_name = undefined;
        if ( isdefined( powerup_ent.powerup_name ) )
            powerup_name = powerup_ent.powerup_name;

        if ( !isdefined( powerup_name ) || powerup_name == "" )
            continue;

        if ( !isdefined( level.round_number ) )
            continue;

        // Track active window (35 seconds).
        if ( powerup_name == "insta_kill" )
            // 35000ms = 35 seconds.
            level.custom_insta_kill_active_until = gettime() + 35000;

        if ( powerup_name == "double_points" )
            // 35000ms = 35 seconds.
            level.custom_double_points_active_until = gettime() + 35000;

        // Late-round rework (round 15+).
        if ( powerup_name == "carpenter" && level.round_number >= 15 )
            level thread carpenter_bonus( player );

        if ( powerup_name == "nuke" && level.round_number >= 15 )
            level thread nuke_scaling_damage( player );
    }
}

// ============================================================
// CARPENTER REWORK
// ============================================================

// ----------------------------------------------------------------------------
// carpenter_bonus( grabber )
// ----------------------------------------------------------------------------
// Late-round Carpenter rework.
// - Computes a bonus based on round number, capped to avoid crazy values.
// - Awards the bonus to every alive player.
// Note: grabber is passed in for potential future use; current logic awards all.
// ----------------------------------------------------------------------------
carpenter_bonus( grabber )
{
    level endon( "end_game" );

    if ( !isdefined( level.round_number ) )
        return;

    // Bonus scales by round, capped below.
    bonus = 1000 + (level.round_number * 50);
    if ( bonus > 5000 )
        bonus = 5000;

    players = get_players();
    if ( !isdefined( players ) )
        return;

    for ( i = 0; i < players.size; i++ )
    {
        if ( !isdefined( players[i] ) )
            continue;

        if ( !isalive( players[i] ) )
            continue;

        players[i] maps\mp\zombies\_zm_score::add_to_player_score( bonus );
        players[i] iprintln( "Carpenter Bonus: +" + bonus );
    }
}

// ============================================================
// NUKE SCALING
// ============================================================

// ----------------------------------------------------------------------------
// nuke_scaling_damage( attacker )
// ----------------------------------------------------------------------------
// Late-round Nuke rework.
// - After a tiny delay (lets normal nuke effects start), we apply extra damage:
//     damage = current_zombie_health * pct (40/50/60%), with a minimum of 150.
// - Counts kills caused by this extra damage, then gives the attacker a small
//   points bonus based on kills (capped).
// Performance notes:
// - Waits every 5 zombies to avoid a single-frame spike on large hordes.
// ----------------------------------------------------------------------------
nuke_scaling_damage( attacker )
{
    level endon( "end_game" );

    // Small delay so the stock nuke effect begins before we apply extra logic.
    wait 0.2;

    if ( !isdefined( attacker ) || !isalive( attacker ) )
        return;

    if ( !isdefined( level.round_number ) )
        return;

    // Zombies are typically on "axis" in BO2 zombies scripts.
    zombies = getaiarray( "axis" );

    if ( !isdefined( zombies ) || zombies.size == 0 )
        return;

    // Damage percentage scales up at very high rounds.
    damage_pct = 40;
    if ( level.round_number >= 30 )
        damage_pct = 50;
    if ( level.round_number >= 50 )
        damage_pct = 60;

    killed = 0;

    for ( i = 0; i < zombies.size; i++ )
    {
        if ( !isdefined( zombies[i] ) )
            continue;

        if ( !isalive( zombies[i] ) )
            continue;

        if ( !isdefined( zombies[i].health ) )
            continue;

        if ( !isdefined( zombies[i].origin ) )
            continue;

        // Use current zombie health so this stays relevant across rounds.
        damage = int( (zombies[i].health * damage_pct) / 100 );
        if ( damage < 150 )
            damage = 150;

        if ( !isdefined( attacker ) || !isalive( attacker ) )
            break;

        zombies[i] dodamage( damage, zombies[i].origin, attacker );

        if ( isdefined( zombies[i] ) && !isalive( zombies[i] ) )
            killed++;

        // Throttle slightly to avoid a single-frame hitch when many zombies are alive.
        if ( i % 5 == 0 )
            wait 0.05;
    }

    if ( killed > 0 && isdefined( attacker ) && isalive( attacker ) )
    {
        score_bonus = killed * 50;
        if ( score_bonus > 5000 )
            score_bonus = 5000;
        // Small bonus so using the nuke still “feels” rewarding on high rounds.
        attacker maps\mp\zombies\_zm_score::add_to_player_score( score_bonus );
        attacker iprintln( "Nuke Bonus: " + killed + " kills" );
    }
}
