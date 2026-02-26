// ╔════════════════════════════════════════════════════════════════════════════╗
// ║  CUSTOM PERMAPERKS / PERSONAL UPGRADES FORCER                              ║
// ║  Black Ops II Zombies (Plutonium T6)                                       ║
// ║                                                                            ║
// ║  Created by: Astroolean                                                    ║
// ║                                                                            ║
// ║  What this does                                                            ║
// ║  • Forces the personal-upgrades (a.k.a. “permaperks”) system to be active. ║
// ║  • Registers all supported personal upgrades up front.                     ║
// ║  • When a player spawns, it sets the required client stats to the exact    ║
// ║    threshold values so each upgrade is immediately considered earned.      ║
// ║  • Triggers a forced test pass so the game awards the upgrades right away. ║
// ║                                                                            ║
// ║  Notes                                                                     ║
// ║  • This script intentionally overwrites personal-upgrade stat values using ║
// ║    set_client_stat(). That is the whole point: it forces awards.           ║
// ║  • Debug print lines are left enabled (iprintlnbold). If you want them off ║
// ║    later, we can add a simple toggle, but they are harmless as-is.         ║
// ║                                                                            ║
// ║  Install                                                                   ║
// ║  • Load this file the same way you load your other custom GSC mods.        ║
// ║  • Do NOT rename stock include paths unless you know exactly what you're   ║
// ║    doing; these are required for the pers-upgrades functions used below.   ║
// ╚════════════════════════════════════════════════════════════════════════════╝

#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_pers_upgrades_system;
#include maps\mp\zombies\_zm_pers_upgrades;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include common_scripts\utility;
#include maps\mp\_utility;

// ─────────────────────────────────────────────────────────────────────────────
// init()
// • Runs once when the level script system initializes.
// • Prepares arrays used by the personal-upgrades system, forces it on,
//   registers every upgrade we want, then enables the feature flags.
// ─────────────────────────────────────────────────────────────────────────────
init()
{
    // Setup monitoring system containers used by the pers-upgrades system.
    // (These arrays store the definitions/keys for upgrades.)
    level.pers_upgrades = [];
    level.pers_upgrades_keys = [];

    // Force the personal-upgrades system to always be active.
    // Some maps/modes may gate this system; this bypasses that.
    level.force_pers_system_active = true;

    // ─────────────────────────────────────────────────────────────────────────
    // Register all permaperks (personal upgrades)
    //
    // pers_register_upgrade( <name>, <active_check_fn>, <stat_key>, <required>, <flag> )
    // - <name>             : Internal identifier for the upgrade.
    // - <active_check_fn>  : Function pointer the game uses to check if active.
    // - <stat_key>         : The client-stat key used to track progress.
    // - <required>         : Threshold needed to earn the upgrade.
    // - <flag>             : Stock system flag (varies by upgrade).
    //
    // We register first, then later (on spawn) we write the stats to thresholds.
    // ─────────────────────────────────────────────────────────────────────────
    pers_register_upgrade("board",               ::pers_upgrade_boards_active,           "pers_boarding",              74, 0);
    pers_register_upgrade("revive",              ::pers_upgrade_revive_active,           "pers_revivenoperk",          17, 1);
    pers_register_upgrade("multikill_headshots", ::pers_upgrade_headshot_active,         "pers_multikill_headshots",    5, 0);
    pers_register_upgrade("cash_back",           ::pers_upgrade_cash_back_active,        "pers_cash_back_bought",      50, 0);
    pers_register_upgrade("insta_kill",          ::pers_upgrade_insta_kill_active,       "pers_insta_kill",             2, 0);
    pers_register_upgrade("jugg",                ::pers_upgrade_jugg_active,             "pers_jugg",                   3, 0);
    pers_register_upgrade("carpenter",           ::pers_upgrade_carpenter_active,        "pers_carpenter",              1, 0);
    pers_register_upgrade("flopper",             ::pers_upgrade_flopper_active,          "pers_flopper_counter",        1, 0);
    pers_register_upgrade("perk_lose",           ::pers_upgrade_perk_lose_active,        "pers_perk_lose_counter",      3, 0);
    pers_register_upgrade("pistol_points",       ::pers_upgrade_pistol_points_active,    "pers_pistol_points_counter",  1, 0);
    pers_register_upgrade("double_points",       ::pers_upgrade_double_points_active,    "pers_double_points_counter",  1, 0);
    pers_register_upgrade("sniper",              ::pers_upgrade_sniper_active,           "pers_sniper_counter",         1, 0);
    pers_register_upgrade("box_weapon",          ::pers_upgrade_box_weapon_active,       "pers_box_weapon_counter",     5, 0);
    pers_register_upgrade("nube",                ::pers_upgrade_nube_active,             "pers_nube_counter",           1, 0);

    // ─────────────────────────────────────────────────────────────────────────
    // Default values for level variables (only set if the map/mod didn't define)
    //
    // These control the “required” thresholds and various upgrade behaviors.
    // They are set up here so your mod is consistent across maps.
    // ─────────────────────────────────────────────────────────────────────────
    if(!isdefined(level.pers_boarding_number_of_boards_required))
        level.pers_boarding_number_of_boards_required = 74;

    if(!isdefined(level.pers_revivenoperk_number_of_revives_required))
        level.pers_revivenoperk_number_of_revives_required = 17;

    if(!isdefined(level.pers_multikill_headshots_required))
        level.pers_multikill_headshots_required = 5;

    if(!isdefined(level.pers_cash_back_num_perks_required))
        level.pers_cash_back_num_perks_required = 50;

    if(!isdefined(level.pers_insta_kill_num_required))
        level.pers_insta_kill_num_required = 2;

    // How long the insta-kill personal upgrade remains “active” (seconds).
    if(!isdefined(level.pers_insta_kill_upgrade_active_time))
        level.pers_insta_kill_upgrade_active_time = 18;

    // Juggernog personal-upgrade health bonus (engine-specific usage).
    if(!isdefined(level.pers_jugg_upgrade_health_bonus))
        level.pers_jugg_upgrade_health_bonus = 90;

    if(!isdefined(level.pers_carpenter_zombie_kills))
        level.pers_carpenter_zombie_kills = 1;

    if(!isdefined(level.pers_flopper_counter))
        level.pers_flopper_counter = 1;

    if(!isdefined(level.pers_perk_lose_counter))
        level.pers_perk_lose_counter = 3;

    if(!isdefined(level.pers_pistol_points_counter))
        level.pers_pistol_points_counter = 1;

    if(!isdefined(level.pers_double_points_counter))
        level.pers_double_points_counter = 1;

    if(!isdefined(level.pers_sniper_counter))
        level.pers_sniper_counter = 1;

    if(!isdefined(level.pers_box_weapon_counter))
        level.pers_box_weapon_counter = 5;

    if(!isdefined(level.pers_nube_counter))
        level.pers_nube_counter = 1;

    // ─────────────────────────────────────────────────────────────────────────
    // Enable all permaperk systems (feature flags)
    //
    // These flags are what the stock scripts check to decide whether each
    // personal upgrade is allowed to run.
    // ─────────────────────────────────────────────────────────────────────────
    level.pers_upgrade_boards              = 1;
    level.pers_upgrade_revive              = 1;
    level.pers_upgrade_multi_kill_headshots= 1;
    level.pers_upgrade_cash_back           = 1;
    level.pers_upgrade_insta_kill          = 1;
    level.pers_upgrade_jugg                = 1;
    level.pers_upgrade_carpenter           = 1;
    level.pers_upgrade_flopper             = 1;
    level.pers_upgrade_perk_lose           = 1;
    level.pers_upgrade_pistol_points       = 1;
    level.pers_upgrade_double_points       = 1;
    level.pers_upgrade_sniper              = 1;
    level.pers_upgrade_box_weapon          = 1;
    level.pers_upgrade_nube                = 1;

    // Start listening for players so we can force-apply upgrades on spawn.
    level thread on_player_connect();
}

// ─────────────────────────────────────────────────────────────────────────────
// on_player_connect()
// • Loop forever and attach a spawn handler to each joining player.
// • Uses the level "connecting" notify to catch players early.
// ─────────────────────────────────────────────────────────────────────────────
on_player_connect()
{
    for(;;)
    {
        level waittill("connecting", player);
        player thread on_player_spawned();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// on_player_spawned()
// • Runs for each player entity.
// • Waits for the player to fully spawn.
// • Initializes required pers-upgrades globals/structures.
// • Writes all personal-upgrade stats to “earned” thresholds.
// • Forces the system to evaluate and award upgrades immediately.
// ─────────────────────────────────────────────────────────────────────────────
on_player_spawned()
{
    self endon("disconnect");

    // Wait for player to fully connect/spawn into the game.
    self waittill("spawned");

    // Short delay after spawning so the engine has finished initial setup.
    wait 0.5;

    // Debug log (safe; purely visual).
    self iprintlnbold("Force activating permaperks for player: " + self.name);

    // Initialize globals used by the personal-upgrades system on the player.
    self pers_abilities_init_globals();

    // Ensure required structures exist to avoid undefined errors in stock calls.
    if(!isDefined(self.pers_upgrades_awarded))
        self.pers_upgrades_awarded = [];

    if(!isDefined(self.stats_this_frame))
        self.stats_this_frame = [];

    // ─────────────────────────────────────────────────────────────────────────
    // 1) Set all required stats to the “earned” values
    //
    // This is the core of the forcer: each stat is set to the requirement.
    // The stock system will see these and treat each upgrade as completed.
    // ─────────────────────────────────────────────────────────────────────────
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_boarding",              level.pers_boarding_number_of_boards_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_revivenoperk",          level.pers_revivenoperk_number_of_revives_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_multikill_headshots",   level.pers_multikill_headshots_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_cash_back_bought",      level.pers_cash_back_num_perks_required);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_insta_kill",            level.pers_insta_kill_num_required);

    // NOTE:
    // The original script uses level.pers_jugg_hit_and_die_total here.
    // That value is defined/maintained by the stock system on many maps.
    // We do NOT touch that logic — we only document it.
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_jugg",                  level.pers_jugg_hit_and_die_total);

    self maps\mp\zombies\_zm_stats::set_client_stat("pers_carpenter",             level.pers_carpenter_zombie_kills);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_flopper_counter",       level.pers_flopper_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_perk_lose_counter",     level.pers_perk_lose_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_pistol_points_counter", level.pers_pistol_points_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_double_points_counter", level.pers_double_points_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_sniper_counter",        level.pers_sniper_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_box_weapon_counter",    level.pers_box_weapon_counter);
    self maps\mp\zombies\_zm_stats::set_client_stat("pers_nube_counter",          level.pers_nube_counter);

    // ─────────────────────────────────────────────────────────────────────────
    // 2) Force the system to re-check stats
    //
    // Some stock logic only evaluates upgrades at specific times. This flag
    // forces a test pass so the awards happen immediately.
    // ─────────────────────────────────────────────────────────────────────────
    self.pers_upgrade_force_test = 1;

    // Brief wait to allow the internal upgrade evaluation to run.
    wait 0.1;

    // Debug log (safe; purely visual).
    self iprintlnbold("All permaperks forcefully activated for " + self.name);
}
