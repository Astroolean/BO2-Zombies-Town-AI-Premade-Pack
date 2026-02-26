// =================================================================================================
//  CUSTOM_SNOW.GSC (Origins / zm_tomb)
//  Created by: Astroolean
//
//  Purpose
//  - Forces the map into the "snow" weather state immediately (including Round 1).
//  - Keeps the snow weather flag ON so Origins snow-dependent gameplay stays available.
//  - Optionally enables client FX so you also SEE falling snow particles (visual layer).
//
//  Important Notes
//  - This script targets ONLY Origins (mapname: zm_tomb). It returns instantly on other maps.
//  - This file is written to be drop-in safe: it only sets weather-related DVARs and a few
//    level variables/notifications used by weather listeners. No perk/weapon/AI logic here.
//  - If you have more than one snow/weather script active, they'll fight each other. Use ONE.
//
//  Install Path (Plutonium T6)
//    %localappdata%\Plutonium\storage\t6\scripts\zm\zm_tomb\custom_snow.gsc
//
//  Required Cleanup (so the new script actually compiles/loads)
//    Delete: %localappdata%\Plutonium\storage\t6\scripts\compiled\
//
//  DVAR Configuration (optional)
//    set perma_snow 1
//      - Master toggle. 1 = enabled (default). 0 = disabled (script stays loaded, does nothing).
//
//    set perma_snow_rate 250
//      - Watchdog interval in milliseconds (clamped 50..2000).
//      - Lower = more aggressive re-apply, higher = lighter touch.
//
//    set perma_snow_particles 1
//      - 1 = forces client FX drawing so falling snow is visible.
//      - 0 = only forces the REAL snow state (gameplay flag), no particle forcing.
//
//  File Layout
//    1) main()  : earliest hook, sets defaults and forces snow once ASAP
//    2) init()  : one-time boot, starts threads
//    3) Threads : startup hammer, watchdog loop, player spawn hook
//    4) Helper  : ops_force_real_snow() (the only place that actually sets weather state)
// =================================================================================================

// ============================================================
// ORIGINS (zm_tomb) - CUSTOM_SNOW (FIXED) - SNOW FROM ROUND 1
// ============================================================
// This file is meant to REPLACE your broken:
//   scripts\zm\zm_tomb\custom_snow.gsc
// That broken file starts with a literal "" at line 1, which causes:
//   invalid token ('\') at 1:1
//
// What this does:
// - Forces REAL snow state (Ice Staff dig logic) using force_weather_snow.
// - Forces falling snow particles by enabling FX client-side.
// - Tries to push snow into ROUND 1 via a short "startup hammer".
//
// Install (single file):
//   %localappdata%\Plutonium\storage\t6\scripts\zm\zm_tomb\custom_snow.gsc
//
// Cleanup (MANDATORY):
// - Delete cache folder: %localappdata%\Plutonium\storage\t6\scripts\compiled\
// - Make sure you do NOT have other snow scripts in scripts\zm\ or raw\scripts\zm\
//
// Dvars (optional):
//   set perma_snow 1                 (default 1)
//   set perma_snow 0
//   set perma_snow_rate 250          (ms, steady tick; 50-2000)
//   set perma_snow_particles 1       (default 1)
//   set perma_snow_particles 0
// ============================================================

// -------------------------------------------------------------------------------------------------
// main()
// Runs extremely early during script load. We use this to:
// - Ensure we are on Origins (zm_tomb).
// - Seed default DVARs if the user did not set them in console/config.
// - Force snow once as early as possible (before init() threads start).
// -------------------------------------------------------------------------------------------------
main()
{
    if (getDvar("mapname") != "zm_tomb")
        return;

    if (getDvar("perma_snow") == "") setDvar("perma_snow", "1");
    if (getDvar("perma_snow_rate") == "") setDvar("perma_snow_rate", "250");
    if (getDvar("perma_snow_particles") == "") setDvar("perma_snow_particles", "1");

    // Earliest possible forcing (before init)
    if (getDvarInt("perma_snow"))
        ops_force_real_snow();
}

// -------------------------------------------------------------------------------------------------
// init()
// Runs after main() in the map script lifecycle. We use this to:
// - Guard against duplicate loads (some setups can include the file twice).
// - Start the worker threads that keep snow stable and apply client FX on spawn.
// -------------------------------------------------------------------------------------------------
init()
{
    if (getDvar("mapname") != "zm_tomb")
        return;

    if (isDefined(level.custom_snow_loaded) && level.custom_snow_loaded)
        return;
    level.custom_snow_loaded = 1;

    level thread ops_startup_hammer();
    level thread ops_watchdog();
    level thread ops_hook_players();
}

// -------------------------------------------------------------------------------------------------
// ops_hook_players()
// Waits for players to connect and attaches our per-player spawn handler.
// This is how we safely set client DVARs (visual FX) without spamming when no player exists.
// -------------------------------------------------------------------------------------------------
ops_hook_players()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread ops_on_spawn();
    }
}

// -------------------------------------------------------------------------------------------------
// ops_on_spawn()
// Per-player loop. On each "spawned_player":
// - If snow is enabled, we hint the client weather state and ensure FX is allowed to render.
// - Client DVARs are used because particle visibility is a client-side rendering concern.
// -------------------------------------------------------------------------------------------------
ops_on_spawn()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");

        if (!getDvarInt("perma_snow"))
            continue;

        // Weather hints (harmless if ignored)
        self setClientDvar("weather", "snow");
        self setClientDvar("weather_state", "snow");

        // Ensure falling snow FX can render
        if (getDvarInt("perma_snow_particles"))
        {
            self setClientDvar("fx_enable", "1");
            self setClientDvar("fx_draw", "1");
            self setClientDvar("fx_drawClouds", "1");
            self setClientDvar("fx_freeze", "0");
        }
    }
}

// -------------------------------------------------------------------------------------------------
// ops_startup_hammer()
// Short, aggressive forcing window (~12s) aimed at Round 1 startup.
// Some maps/scripts set or reset weather during early initialization; this "hammer" helps win
// that race by re-applying the snow state repeatedly while the map finishes booting.
// -------------------------------------------------------------------------------------------------
ops_startup_hammer()
{
    level endon("end_game");
    level endon("game_ended");

    // Hammer for ~12 seconds to push snow into round 1
    start = getTime();
    while ((getTime() - start) < 12000)
    {
        if (getDvarInt("perma_snow"))
            ops_force_real_snow();

        wait 0.05;
    }
}

// -------------------------------------------------------------------------------------------------
// ops_watchdog()
// Long-running maintenance loop.
// - If enabled, it periodically re-applies the snow weather DVARs and notifies listeners.
// - Also re-applies client FX toggles to all current players (if particles are enabled).
// -------------------------------------------------------------------------------------------------
ops_watchdog()
{
    level endon("end_game");
    level endon("game_ended");

    wait 0.1;

    for (;;)
    {
        if (!getDvarInt("perma_snow"))
        {
            wait 1;
            continue;
        }

        rate_ms = getDvarInt("perma_snow_rate");
        if (rate_ms < 50) rate_ms = 50;
        if (rate_ms > 2000) rate_ms = 2000;

        ops_force_real_snow();

        // Re-apply FX to everyone periodically
        if (getDvarInt("perma_snow_particles") && isDefined(level.players))
        {
            for (i = 0; i < level.players.size; i++)
            {
                p = level.players[i];
                if (!isDefined(p)) continue;

                p setClientDvar("fx_enable", "1");
                p setClientDvar("fx_draw", "1");
                p setClientDvar("fx_drawClouds", "1");
                p setClientDvar("fx_freeze", "0");
            }
        }

        wait (rate_ms / 1000.0);
    }
}

// -------------------------------------------------------------------------------------------------
// ops_force_real_snow()
// The ONLY function that changes the actual weather state.
// This sets the Origins snow DVAR (force_weather_snow) and disables conflicting force modes.
// It also updates a couple best-effort level fields and emits weather-related notifications
// in case any scripts are listening for them.
// -------------------------------------------------------------------------------------------------
ops_force_real_snow()
{
    // REAL snow state (used by Origins internally)
    setDvar("force_weather_snow", "on");

    // Stop other forced weather modes fighting it
    setDvar("force_weather_rain", "off");
    setDvar("force_weather_none", "off");

    // Best-effort extras
    level.weather_cycle_enabled = 0;
    level.weather_state = "snow";

    setDvar("weather", "snow");
    setDvar("weather_state", "snow");

    // Kick any listeners
    level notify("weather_snow");
    level notify("start_snow");
    level notify("snow_on");
    level notify("snow");
}
