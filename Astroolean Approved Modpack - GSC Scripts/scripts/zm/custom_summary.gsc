// ============================================================================
// ROUND COMPLETION SUMMARY (ORIGINS / zm_tomb) — CUSTOM SCRIPT
// Created by: Astroolean
//
// What this script does:
// - Shows a clean "Round Complete" summary when a new round starts (Round 2+).
// - Displays four separate on-screen lines (no overlap) with:
//     1) Round complete title
//     2) Eliminations and round time for the round you just finished
//     3) Your personal best time and personal best eliminations for that round
//     4) Status line telling you if you set any new personal bests
// - Personal best values are saved using "seta" so they persist across restarts.
//
// Where to install (single file):
//   %localappdata%\Plutonium\storage\t6\scripts\zm\custom_summary.gsc
//
// Important cleanup (this is how you remove older popups from older versions):
// 1) Delete every other copy of custom_summary.gsc in these folders (if they exist):
//    %localappdata%\Plutonium\storage\t6\scripts\zm\zm_tomb\
//    %localappdata%\Plutonium\storage\t6\raw\scripts\zm\
//    %localappdata%\Plutonium\storage\t6\raw\scripts\zm\zm_tomb\
// 2) Delete compiled script cache folder:
//    %localappdata%\Plutonium\storage\t6\scripts\compiled\
// 3) Fully restart Plutonium (close and reopen), then launch Origins.
//
// Dvars (console / config):
//   set cs_enabled 1          // 1 = enabled, 0 = disabled
//   set cs_x 0                // Horizontal offset from center
//   set cs_y -60              // Vertical offset from center
//   set cs_seconds 10         // How long the summary stays visible (seconds)
//   set cs_cooldown_ms 2500   // Minimum time between summaries (milliseconds)
//
// Notes:
// - This script only runs on Origins (mapname "zm_tomb") by design.
// - "Heads-Up Display" is abbreviated as HUD inside variable names in this file.
// ============================================================================
//
#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_utility;


// ---------------------------------------------------------------------------
// main()
// Entry point used by some loaders.
// Calls cs_boot() to initialize the script once the file is loaded.
// ---------------------------------------------------------------------------
main()
{
    cs_boot();
}


// ---------------------------------------------------------------------------
// init()
// Standard Treyarch init() entry point.
// Calls cs_boot() so the script works whether it is executed via init() or main().
// ---------------------------------------------------------------------------
init()
{
    cs_boot();
}


// ---------------------------------------------------------------------------
// cs_boot()
// One-time initialization and map gating.
// Only enables on Origins (zm_tomb).
// Sets safe defaults for dvars if they are missing.
// Starts the connection listener thread.
// ---------------------------------------------------------------------------
cs_boot()
{
    if (getDvar("mapname") != "zm_tomb")
        return;

    // One instance only
    if (isDefined(level.cs_loaded) && level.cs_loaded)
        return;
    level.cs_loaded = 1;

    // Try to disable the older "CRS" script if it was installed before
    // (these were the old dvars from the previous versions I sent you)
    setDvar("ct_round_summary", "0");
    setDvar("ct_rs_show_session_best", "0");
    setDvar("ct_rs_show_round_pb", "0");

    // Defaults
    if (getDvar("cs_enabled") == "") setDvar("cs_enabled", "1");
    if (getDvar("cs_x") == "") setDvar("cs_x", "0");
    if (getDvar("cs_y") == "") setDvar("cs_y", "-60");
    if (getDvar("cs_seconds") == "") setDvar("cs_seconds", "10");
    if (getDvar("cs_cooldown_ms") == "") setDvar("cs_cooldown_ms", "2500");

    level thread cs_on_connect();
}


// ---------------------------------------------------------------------------
// cs_on_connect()
// Waits for each player to connect, then sets them up.
// Also sends 'kill' notifications that older versions of scripts might be listening for,
// and attempts to destroy legacy HUD elements so you do not see duplicate popups.
// ---------------------------------------------------------------------------
cs_on_connect()
{
    for (;;)
    {
        level waittill("connected", player);

        // Best-effort: tell older scripts to stop their popup threads
        player notify("crs_summary_kill");
        player notify("cs_popup_kill");
        player notify("cs_popup_kill2");

        // Best-effort: destroy any old HUD elements the older scripts created
        player thread cs_kill_legacy_hud();

        player thread cs_player_thread();
    }
}


// ---------------------------------------------------------------------------
// cs_kill_legacy_hud()
// Best-effort cleanup for legacy HUD elements created by older summary scripts.
// Runs a short loop to catch items that are mid-fade or created slightly late.
// ---------------------------------------------------------------------------
cs_kill_legacy_hud()
{
    self endon("disconnect");

    // Run a few times in case the old popup was mid-fade
    for (i = 0; i < 10; i++)
    {
        if (isDefined(self.crs_title)) self.crs_title destroy();
        if (isDefined(self.crs_line2)) self.crs_line2 destroy();
        if (isDefined(self.crs_line3)) self.crs_line3 destroy();
        if (isDefined(self.crs_line4)) self.crs_line4 destroy();

        if (isDefined(self.cs_title_old)) self.cs_title_old destroy();
        if (isDefined(self.cs_line2_old)) self.cs_line2_old destroy();
        if (isDefined(self.cs_line3_old)) self.cs_line3_old destroy();
        if (isDefined(self.cs_line4_old)) self.cs_line4_old destroy();

        if (isDefined(self.crs_summary)) self.crs_summary destroy();

        wait 0.1;
    }
}


// ---------------------------------------------------------------------------
// cs_player_thread()
// Per-player main loop.
// Waits until the game is fully in-progress, captures round start baselines,
// and watches for round transitions to trigger cs_on_round_change().
// ---------------------------------------------------------------------------
cs_player_thread()
{
    self endon("disconnect");

    if (isDefined(self.cs_running) && self.cs_running)
        return;
    self.cs_running = 1;

    flag_wait("initial_blackscreen_passed");

    while (!isDefined(level.round_number))
        wait 0.1;

    self.cs_last_round = level.round_number;
    self.cs_round_start_time = getTime();
    self.cs_kills_start = cs_get_kills();

    // Prevent instant spam during early init
    self.cs_last_popup_time = getTime();

    cs_hud_create();

    for (;;)
    {
        if (!getDvarInt("cs_enabled"))
        {
            wait 0.5;
            continue;
        }

        r = level.round_number;

        if (r != self.cs_last_round && r > 1)
            cs_on_round_change(r);

        wait 0.2;
    }
}


// ---------------------------------------------------------------------------
// cs_on_round_change()
// Called when the round number changes (meaning the previous round completed).
// Calculates round time and eliminations for the completed round.
// Updates per-round personal bests and persists them with 'seta'.
// Applies a cooldown so the popup cannot rapidly flicker or double-trigger.
// ---------------------------------------------------------------------------
cs_on_round_change(new_round)
{
    kills_now = cs_get_kills();

    completed_round = self.cs_last_round;

    round_time = int((getTime() - self.cs_round_start_time) / 1000);
    if (round_time < 0) round_time = 0;

    round_kills = kills_now - self.cs_kills_start;
    if (round_kills < 0) round_kills = 0;

    // Personal best per round (persist via seta)
    pb_time_key = "cs_personal_best_time_round_" + completed_round;
    pb_kills_key = "cs_personal_best_kills_round_" + completed_round;

    old_pb_time = getDvarInt(pb_time_key);
    old_pb_kills = getDvarInt(pb_kills_key);

    new_pb_time = 0;
    new_pb_kills = 0;

    if (round_time > 0 && (old_pb_time <= 0 || round_time < old_pb_time))
    {
        old_pb_time = round_time;
        setDvar(pb_time_key, round_time);
        cmdexec("seta " + pb_time_key + " " + round_time + "\n");
        new_pb_time = 1;
    }

    if (round_kills > old_pb_kills)
    {
        old_pb_kills = round_kills;
        setDvar(pb_kills_key, round_kills);
        cmdexec("seta " + pb_kills_key + " " + round_kills + "\n");
        new_pb_kills = 1;
    }

    // Cooldown to stop rapid re-trigger / flicker
    cooldown = getDvarInt("cs_cooldown_ms");
    if (cooldown < 500) cooldown = 500;
    if (cooldown > 10000) cooldown = 10000;

    now = getTime();
    if (isDefined(self.cs_last_popup_time) && (now - self.cs_last_popup_time) < cooldown)
    {
        self.cs_last_round = new_round;
        self.cs_round_start_time = getTime();
        self.cs_kills_start = kills_now;
        return;
    }
    self.cs_last_popup_time = now;

    self notify("cs_popup_kill3");
    self thread cs_popup(completed_round, round_time, round_kills, old_pb_time, old_pb_kills, new_pb_time, new_pb_kills);

    self.cs_last_round = new_round;
    self.cs_round_start_time = getTime();
    self.cs_kills_start = kills_now;
}


// ---------------------------------------------------------------------------
// cs_popup()
// Builds and displays the four-line summary popup.
// Positions the HUD elements using cs_x and cs_y, then fades in, waits, and fades out.
// ---------------------------------------------------------------------------
cs_popup(round_num, round_time, round_kills, pb_time, pb_kills, new_pb_time, new_pb_kills)
{
    self endon("disconnect");
    self endon("cs_popup_kill3");

    cs_hud_create();

    x = cs_clamp(getDvarInt("cs_x"), -300, 300);
    y = cs_clamp(getDvarInt("cs_y"), -220, 160);

    // Big spacing so it never mashes
    self.cs_title setPoint("CENTER", "CENTER", x, y - 58);
    self.cs_line2 setPoint("CENTER", "CENTER", x, y - 30);
    self.cs_line3 setPoint("CENTER", "CENTER", x, y - 4);
    self.cs_line4 setPoint("CENTER", "CENTER", x, y + 22);

    time_str = cs_time(round_time);

    pb_time_str = "Not Set";
    if (pb_time > 0) pb_time_str = cs_time(pb_time);

    status_str = cs_status(new_pb_time, new_pb_kills);

    self.cs_title setText("^5ROUND " + round_num + " COMPLETE");
    self.cs_line2 setText("^7Eliminations: ^5" + round_kills + " ^7| Round Time: ^5" + time_str);
    self.cs_line3 setText("^7Personal Best Time: ^3" + pb_time_str + " ^7| Personal Best Eliminations: ^3" + pb_kills);
    self.cs_line4 setText("^7Status: " + status_str);

    // Hard reset alpha
    self.cs_title.alpha = 0;
    self.cs_line2.alpha = 0;
    self.cs_line3.alpha = 0;
    self.cs_line4.alpha = 0;

    // Fade in
    self.cs_title fadeOverTime(0.18); self.cs_title.alpha = 0.95;
    self.cs_line2 fadeOverTime(0.18); self.cs_line2.alpha = 0.95;
    self.cs_line3 fadeOverTime(0.18); self.cs_line3.alpha = 0.95;
    self.cs_line4 fadeOverTime(0.18); self.cs_line4.alpha = 0.95;

    show_for = cs_clamp(getDvarInt("cs_seconds"), 3, 30);
    wait show_for;

    // Fade out
    self.cs_title fadeOverTime(0.28); self.cs_title.alpha = 0;
    self.cs_line2 fadeOverTime(0.28); self.cs_line2.alpha = 0;
    self.cs_line3 fadeOverTime(0.28); self.cs_line3.alpha = 0;
    self.cs_line4 fadeOverTime(0.28); self.cs_line4.alpha = 0;

    wait 0.28;
}


// ---------------------------------------------------------------------------
// cs_hud_create()
// Creates the four HUD font strings (title + three lines) if they do not already exist.
// If they exist but are partially missing, it destroys and recreates them cleanly.
// ---------------------------------------------------------------------------
cs_hud_create()
{
    if (isDefined(self.cs_title) && isDefined(self.cs_line4))
        return;

    if (isDefined(self.cs_title)) self.cs_title destroy();
    if (isDefined(self.cs_line2)) self.cs_line2 destroy();
    if (isDefined(self.cs_line3)) self.cs_line3 destroy();
    if (isDefined(self.cs_line4)) self.cs_line4 destroy();

    self.cs_title = self createFontString("default", 1.55);
    self.cs_title.sort = 25;
    self.cs_title.alpha = 0;
    self.cs_title.hideWhenInMenu = 1;

    self.cs_line2 = self createFontString("default", 1.25);
    self.cs_line2.sort = 25;
    self.cs_line2.alpha = 0;
    self.cs_line2.hideWhenInMenu = 1;

    self.cs_line3 = self createFontString("default", 1.12);
    self.cs_line3.sort = 25;
    self.cs_line3.alpha = 0;
    self.cs_line3.hideWhenInMenu = 1;

    self.cs_line4 = self createFontString("default", 1.12);
    self.cs_line4.sort = 25;
    self.cs_line4.alpha = 0;
    self.cs_line4.hideWhenInMenu = 1;
}


// ---------------------------------------------------------------------------
// cs_get_kills()
// Returns the player's kill count in a compatibility-friendly way.
// Tries self.kills first, then self.pers['kills'], then falls back to 0.
// ---------------------------------------------------------------------------
cs_get_kills()
{
    if (isDefined(self.kills))
        return self.kills;

    if (isDefined(self.pers) && isDefined(self.pers["kills"]))
        return self.pers["kills"];

    return 0;
}


// ---------------------------------------------------------------------------
// cs_time()
// Formats an integer number of seconds as M:SS.
// ---------------------------------------------------------------------------
cs_time(total)
{
    if (total < 0) total = 0;

    m = int(total / 60);
    s = int(total % 60);

    if (s < 10)
        return "" + m + ":0" + s;

    return "" + m + ":" + s;
}


// ---------------------------------------------------------------------------
// cs_status()
// Builds the status line text based on whether the player achieved any new personal bests.
// ---------------------------------------------------------------------------
cs_status(new_time, new_kills)
{
    if (new_time && new_kills)
        return "^2New Personal Best Time and New Personal Best Eliminations";
    if (new_time)
        return "^2New Personal Best Time";
    if (new_kills)
        return "^2New Personal Best Eliminations";

    return "^7No New Personal Best";
}


// ---------------------------------------------------------------------------
// cs_clamp()
// Clamps a value between a minimum and maximum.
// ---------------------------------------------------------------------------
cs_clamp(v, mn, mx)
{
    if (v < mn) return mn;
    if (v > mx) return mx;
    return v;
}
