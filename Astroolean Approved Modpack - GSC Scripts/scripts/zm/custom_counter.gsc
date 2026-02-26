#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_utility;

// ╔══════════════════════════════════════════════════════════════════╗
// ║        CUSTOM COUNTER & RANK TRACKER v4.2                        ║
// ║  Kills/Downs · Headshots · Round Pace · Career Totals            ║
// ║  Shotguns Progress (Estimate) · Black Ops II Zombies             ║
// ║  Plutonium T6 Client                                             ║
// ║                                                                  ║
// ║  Created by Astroolean                                           ║
// ║  Reverse-Engineered research reference: Dobby                    ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  What this script does                                           ║
// ║    • Adds a clean text Heads-Up Display above the health bar.    ║
// ║    • Tracks live match stats and rolling career totals.          ║
// ║    • Shows a Shotguns progress bar using an estimated model.     ║
// ║                                                                  ║
// ║  What this script does NOT do                                    ║
// ║    • Does not change damage, health, perks, weapons, or drops.   ║
// ║    • Does not unlock anything automatically; it only tracks.     ║
// ║                                                                  ║
// ║  Configuration dvars (set once; defaults are created if missing) ║
// ║    ct_hud              1   Enable/disable HUD (0 or 1)           ║
// ║    ct_round_summary    1   Enable/disable round summary popup    ║
// ║    ct_re_mode          1   Use Reverse-Engineered estimate lines ║
// ║    ct_re_sg_ratio10    1800 Target ratio scaled x10 (1800 = 180.0║
// ║    ct_re_sg_playsec    0   Optional time gate in seconds (0 = off║
// ║                                                                  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  Saved career dvars (auto-updated)                               ║
// ║    ct_career_kills         Total career zombie kills             ║
// ║    ct_career_downs         Total career downs                    ║
// ║    ct_career_headshots     Total career headshot kills           ║
// ║    ct_career_rounds        Highest round ever reached            ║
// ║    ct_career_games         Total games played                    ║
// ║                                                                  ║
// ║  Reverse-Engineered tracker dvars (auto-updated; scaled values)  ║
// ║    ct_re_career_pos        Positive weighted round score (x100)  ║
// ║    ct_re_career_neg        Negative weighted down score (x100)   ║
// ║    ct_re_career_exits      Game-end penalty count                ║
// ║    ct_re_career_playsec    Tracked playtime seconds              ║
// ║                                                                  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  Reset note                                                      ║
// ║    Plutonium may mirror these dvars in multiple config files.    ║
// ║    If you reset, do it with the game closed in BOTH files:       ║
// ║      • config.cfg                                                ║
// ║      • plutonium_zm.cfg                                          ║
// ║                                                                  ║
// ║  Accuracy note                                                   ║
// ║    The rank/progress portion is an estimate based on community   ║
// ║    findings; it is not confirmed to be identical to Treyarch logi║
// ║                                                                  ║
// ║  File layout (for quick navigation)                              ║
// ║    Initialization → Player hooks → Stats engine → Main loop      ║
// ║    Career saving → HUD build → Mapvote hide → RE helpers         ║
// ║    Player stat helpers → Formatting helpers                      ║
// ╚══════════════════════════════════════════════════════════════════╝


// ============================================================
//  INITIALIZATION
// ============================================================

// -----------------------------------------------------------------------------
// init()
//
// Entry point (runs when the script loads).
// Creates default dvars (only when missing) and starts player connect hooks.
//
// Safe to edit: comments/spacing only. Changing logic will affect stats tracking.
// -----------------------------------------------------------------------------

init()
{
        initCounterDvars();
        level thread onPlayerConnect();
}

// -----------------------------------------------------------------------------
// initCounterDvars()
//
// Ensures every configuration and career dvar used by this script exists.
// Plutonium stores dvars as strings; missing dvars typically read as an empty string.
// We only set defaults when a dvar is missing, so user changes persist across sessions.
// -----------------------------------------------------------------------------

initCounterDvars()
{
        if (getDvar("ct_hud") == "")
                setDvar("ct_hud", "1");
        if (getDvar("ct_round_summary") == "")
                setDvar("ct_round_summary", "1");
        if (getDvar("ct_career_kills") == "")
                setDvar("ct_career_kills", "0");
        if (getDvar("ct_career_downs") == "")
                setDvar("ct_career_downs", "0");
        if (getDvar("ct_career_headshots") == "")
                setDvar("ct_career_headshots", "0");
        if (getDvar("ct_career_rounds") == "")
                setDvar("ct_career_rounds", "0");
        if (getDvar("ct_career_games") == "")
                setDvar("ct_career_games", "0");

        // Community reverse-engineered (weighted rounds/downs) tracker dvars
        if (getDvar("ct_re_mode") == "")
                setDvar("ct_re_mode", "1");
        if (getDvar("ct_re_career_pos") == "")
                setDvar("ct_re_career_pos", "0");      // scaled x100
        if (getDvar("ct_re_career_neg") == "")
                setDvar("ct_re_career_neg", "0");      // scaled x100
        if (getDvar("ct_re_career_exits") == "")
                setDvar("ct_re_career_exits", "0");
        if (getDvar("ct_re_career_playsec") == "")
                setDvar("ct_re_career_playsec", "0");

        // Estimated RE shotguns progress target (progress bar uses this when ct_re_mode = 1)
        // ct_re_sg_ratio10 is scaled x10 (1800 = 180.0 weighted R/D target)
        // ct_re_sg_playsec optional playtime gate in seconds (0 disables playtime gate)
        if (getDvar("ct_re_sg_ratio10") == "")
                setDvar("ct_re_sg_ratio10", "1800");
        if (getDvar("ct_re_sg_playsec") == "")
                setDvar("ct_re_sg_playsec", "0");
}

// -----------------------------------------------------------------------------
// onPlayerConnect()
//
// Waits for players to connect and attaches the per-player spawn/stats threads.
// Uses the 'connecting' event so each player is initialized as early as possible.
// -----------------------------------------------------------------------------

onPlayerConnect()
{
        for (;;)
        {
                level waittill("connecting", player);
                player thread onPlayerSpawned();
        }
}

// -----------------------------------------------------------------------------
// onPlayerSpawned()
//
// Runs per player.
// Starts the stats engine thread once, then waits for subsequent spawns.
// Ends cleanly on disconnect.
// -----------------------------------------------------------------------------

onPlayerSpawned()
{
        self endon("disconnect");
        self thread statsEngine();

        for (;;)
        {
                self waittill("spawned_player");
        }
}


// ============================================================
//  STATS ENGINE
// ============================================================

// -----------------------------------------------------------------------------
// statsEngine()
//
// Main per-player initializer after the map finishes loading.
// Captures baseline career values from dvars so this match can add deltas on top.
// Builds the Heads-Up Display (if enabled) and starts the main update loops.
// Also starts integration watchers (mapvote hide + end-of-game penalty handling).
//
// This thread waits for 'initial_blackscreen_passed' to avoid creating HUD too early.
// -----------------------------------------------------------------------------

statsEngine()
{
        level endon("game_ended");
        self endon("disconnect");


                // Wait until the map has finished its initial fade-in / blackscreen.
                // Creating HUD elements too early can fail or display incorrectly on some maps.

        flag_wait("initial_blackscreen_passed");

        // ------------------------------------------------------------
        // Session-local baseline snapshot
        //
        // These fields live on the player entity (self) and track only
        // the current match. Career totals are read from dvars once and
        // then we add live deltas on top during HUD updates/saves.
        // ------------------------------------------------------------
        self.ct_session_start = getTime();
        self.ct_round_start = getTime();
        self.ct_last_round = level.round_number;
        self.ct_round_kills_start = getPlayerKills();
        self.ct_best_round_kills = 0;
        self.ct_best_round_time = 999999;
        self.ct_tick = 0;

        self.ct_session_headshots = 0;
        self.ct_prev_headshots = getPlayerHeadshots();

        self.ct_base_kills = getDvarInt("ct_career_kills");
        self.ct_base_downs = getDvarInt("ct_career_downs");
        self.ct_base_headshots = getDvarInt("ct_career_headshots");

        // Community reverse-engineered weighted tracker (estimate)
        self.ct_re_base_pos = getDvarInt("ct_re_career_pos");
        self.ct_re_base_neg = getDvarInt("ct_re_career_neg");
        self.ct_re_base_exits = getDvarInt("ct_re_career_exits");
        self.ct_re_base_playsec = getDvarInt("ct_re_career_playsec");
        self.ct_re_session_pos = 0;
        self.ct_re_session_neg = 0;
        self.ct_re_session_exits = 0;
        self.ct_re_last_downs = getPlayerDowns();
        self.ct_re_start_round_abs = level.round_number;
        self.ct_re_exit_penalty_applied = false;

        // Count this match as a new 'game played' immediately after loading.
        // This increments even if you end early; it matches how most trackers behave.
        careerGames = getDvarInt("ct_career_games") + 1;
        setDvar("ct_career_games", careerGames);
        cmdexec("seta ct_career_games " + careerGames + "\n");

        if (getDvarInt("ct_hud"))
                self initCounterHUD();

        self thread mainLoop();
        self thread careerSaveLoop();
        self thread mapvoteHideWatcher();
        self thread reGameEndWatcher();
}


// ============================================================
//  MAIN UPDATE LOOP
// ============================================================

// -----------------------------------------------------------------------------
// mainLoop()
//
// Runs every 0.25 seconds while the match is active.
// Collects live session stats (kills, downs, headshots, time, zombies remaining).
// Calculates both career totals and session-only metrics used for rank/progress.
// Updates HUD text lines and the progress bar fill/colour.
// Detects round changes to trigger per-round summary and weighting logic.
// -----------------------------------------------------------------------------

mainLoop()
{
        level endon("game_ended");
        self endon("disconnect");

        for (;;)
        {
                // ------------------------------------------------------------
                // Round state + zombies remaining
                //
                // level.zombie_total may not exist on every map/script variant,
                // so we guard it with isDefined(). We combine it with the engine
                // helper get_current_zombie_count() to estimate remaining.
                // ------------------------------------------------------------
                zombieTotal = 0;
                if (isDefined(level.zombie_total))
                        zombieTotal = level.zombie_total;
                remaining = zombieTotal + get_current_zombie_count();
                if (remaining < 0)
                        remaining = 0;
                round = level.round_number;

                // Throttle the heavy calculations to a predictable tick cadence.
                // This keeps HUD updates smooth without doing expensive work every frame.
                self.ct_tick++;
                if (self.ct_tick >= 1)
                {
                        self.ct_tick = 0;

                        // Pull live per-match counters from the player entity.
                        sessKills = getPlayerKills();
                        sessDowns = getPlayerDowns();

                        // ------------------------------------------------------------
                        // Reverse-Engineered estimate: down weighting
                        //
                        // Each time the player goes down, we add a negative weight. Early
                        // downs in your run hurt more than late downs, based on played-round.
                        // All weights are stored scaled x100 for stable integer math.
                        // ------------------------------------------------------------
                        // Detect new downs and apply weighted penalty by played-round index (community RE estimate)
                        if (sessDowns > self.ct_re_last_downs)
                        {
                                downDiff = sessDowns - self.ct_re_last_downs;
                                while (downDiff > 0)
                                {
                                        relNow = getRelativePlayedRound(round);
                                        self.ct_re_session_neg = self.ct_re_session_neg + getDownPenaltyScaled(relNow);
                                        downDiff--;
                                }
                                self.ct_re_last_downs = sessDowns;
                        }
                        else if (sessDowns < self.ct_re_last_downs)
                        {
                                self.ct_re_last_downs = sessDowns;
                        }

                        // Session time since start (seconds) and a formatted HUD string.
                        elapsed = (getTime() - self.ct_session_start) / 1000;
                        timeStr = formatTime(int(elapsed));

                        // Headshots: BO2 stores a running total, so we track deltas each tick.
                        // This avoids missing headshots when other scripts update the stat.
                        newHS = getPlayerHeadshots();
                        if (newHS > self.ct_prev_headshots)
                        {
                                self.ct_session_headshots = self.ct_session_headshots + (newHS - self.ct_prev_headshots);
                                self.ct_prev_headshots = newHS;
                        }

                        // Career totals = baseline (saved) + this match's live deltas.
                        careerKills = self.ct_base_kills + sessKills;
                        careerDowns = self.ct_base_downs + sessDowns;
                        careerHS = self.ct_base_headshots + self.ct_session_headshots;

                        // Kills/Downs ratios: clamp downs to at least 1 to avoid divide-by-zero.
                        // Ratios are stored scaled x10 so we can show one decimal without floats.
                        effDowns = careerDowns;
                        if (effDowns < 1)
                                effDowns = 1;
                        kd10 = int((careerKills * 10) / effDowns);
                        kdWhole = int(kd10 / 10);
                        kdDec = int(kd10 % 10);

                        sessEffDowns = sessDowns;
                        if (sessEffDowns < 1)
                                sessEffDowns = 1;
                        sessKD10 = int((sessKills * 10) / sessEffDowns);

                        // Headshot percentage across career totals (includes this match).
                        hsPct = 0;
                        if (careerKills > 0)
                                hsPct = int((careerHS * 100) / careerKills);

                        // Session-based target (performance-per-run) so Rank starts at BONES each game
                        // ------------------------------------------------------------
                        // Rank target + progress metric
                        //
                        // Two modes:
                        //   1) Default: session Kills/Downs ratio compared to a session target.
                        //   2) Reverse-Engineered mode: weighted ratio compared to ct_re_sg_ratio10.
                        //
                        // The rank display uses session-only performance so it starts fresh each run,
                        // while the career lines show lifetime totals.
                        // ------------------------------------------------------------
                        targetKD = getShotgunTarget(sessKills);
                        targetKD10 = targetKD * 10;

                        // RE rank uses session-only weighted ratio (starts at 0.0 each run)
                        reTarget10 = getREShotgunTargetRatio10();

                        rankMetric10 = sessKD10;
                        rankTarget10 = targetKD10;

                        if (getDvarInt("ct_re_mode"))
{
                                rePosSess = self.ct_re_session_pos;
                                reNegSess = self.ct_re_session_neg;
                                reNegForRatioSess = reNegSess;
                                if (reNegForRatioSess < 100)
                                reNegForRatioSess = 100;
                                rankMetric10 = int((rePosSess * 10) / reNegForRatioSess);
                                rankTarget10 = reTarget10;
}

                        // Convert the numeric metric into a named rank + percent progress for the bar.
                        rankName = getRankName(rankMetric10, rankTarget10);
                        progressPct = getRankProgress(rankMetric10, rankTarget10);

                        rankWhole = int(rankMetric10 / 10);
                        rankDec = int(rankMetric10 % 10);

                        // Community RE weighted ratio (positive weighted rounds / weighted negatives)
                        rePos = self.ct_re_base_pos + self.ct_re_session_pos;
                        reNegRaw = self.ct_re_base_neg + self.ct_re_session_neg;
                        reNegForRatio = reNegRaw;
                        if (reNegForRatio < 100)
                                reNegForRatio = 100;
                        reRatio10 = int((rePos * 10) / reNegForRatio);
                        reWhole = int(reRatio10 / 10);
                        reDec = int(reRatio10 % 10);
                        reExits = self.ct_re_base_exits + self.ct_re_session_exits;
                        totalPlaySec = self.ct_re_base_playsec + int(elapsed);
                        reProgressPct = getREShotgunProgressPct(reRatio10, totalPlaySec);
                        reTargetWhole = int(reTarget10 / 10);
                        reTargetDec = int(reTarget10 % 10);
                        rePlayTargetSec = getDvarInt("ct_re_sg_playsec");
                        rePlayPct = 0;
                        if (rePlayTargetSec > 0)
                                rePlayPct = getSimpleProgressPct(totalPlaySec, rePlayTargetSec);

                        // Performance tag uses the same metric as Rank (session Kills/Downs or session RE ratio)
                        // Performance status tag: quick indicator for how close you are to target.
                        if (rankMetric10 >= rankTarget10)
                        statusTag = "^3MAX";
                        else if (rankMetric10 >= int(rankTarget10 * 0.7))
                        statusTag = "^5CLOSE";
                        else
                        statusTag = "^1BEHIND";

                        minutes = elapsed / 60;
                        kpm = 0;
                        if (minutes >= 0.5)
                                kpm = sessKills / minutes;

                        killsNeeded = getKillsNeeded(careerKills, careerDowns, targetKD);

                        if (remaining == 0)
                                line1 = "^2ROUND CLEAR ^7|  Round " + round + "  |  ^5" + timeStr;
                        else
                                line1 = "^5" + remaining + " Zombies Left ^7|  Round " + round + "  |  ^5" + timeStr;

                        targetWhole = int(targetKD);
                        targetDec = int((targetKD * 10) % 10);

                        line2 = "^5Career: ^7" + careerKills + " Kills  " + careerDowns + " Downs  ^5Kills/Downs ^7" + kdWhole + "." + kdDec;
                        line3 = "^5Rank: ^7" + rankName + "  ^5|  This Game: ^7" + sessKills + " Kills  " + sessDowns + " Downs";
                        line6 = "";
                        line7 = "";

                        if (rankMetric10 >= rankTarget10)
{
                                if (getDvarInt("ct_re_mode"))
                                line4 = "^2SHOTGUNS RANK ACHIEVED!  ^7RE: " + rankWhole + "." + rankDec;
                                else
                                line4 = "^2SHOTGUNS RANK ACHIEVED!  ^7Kills/Downs: " + rankWhole + "." + rankDec;

                                line5 = "";
                                line6 = "";
                                line7 = "";
}
                        else
                        {
                                line4 = "^5Next Rank: ^7" + targetWhole + "." + targetDec + " Kills/Downs  ^5Need: ^7" + killsNeeded + " Kills  (" + progressPct + "%)";
                                if (statusTag == "^3MAX")
                                        statusText = "^3Max Rank";
                                else if (statusTag == "^2ON TRACK")
                                        statusText = "^2On Track";
                                else if (statusTag == "^5CLOSE")
                                        statusText = "^5Almost There";
                                else
                                        statusText = "^1Falling Behind";
                        }

                        if (getDvarInt("ct_re_mode"))
                        {
                                // RE display uses community-known behavior: weighted round value, early-down penalties, +exit penalty
                                line4 = "^5Shotguns Progress (Reverse-Engineered Estimate): ^7" + reWhole + "." + reDec + " / " + reTargetWhole + "." + reTargetDec + "  ^5(" + reProgressPct + "%)";
                                if (kd10 < targetKD10)
                                        line4 = line4 + "  ^5|  " + statusText;

                                line5 = "^5Reverse-Engineered Tracker: ^7Weighted Rounds to Downs Ratio: ^7" + reWhole + "." + reDec;
                                line6 = "^5Positive Weighted Rounds: ^7" + int(rePos / 100) + "  ^5Negative Weighted Downs: ^7" + formatScaled100(reNegRaw);
                                line7 = "^5Game End Penalties: ^7" + reExits + "  ^5Playtime: ^7" + formatPlaytimeSpelledOut(totalPlaySec);
                                if (rePlayTargetSec > 0)
                                        line7 = line7 + "  ^5|  Playtime Goal: ^7" + formatPlaytimeSpelledOut(rePlayTargetSec) + " ^5(" + rePlayPct + "%)";
                        }
                        else
                        {
                                if (kd10 >= targetKD10)
                                {
                                        line5 = "";
                                        line6 = "";
                                        line7 = "";
                                }
                                else
                                {
                                        line5 = "^5Status: " + statusText;
                                        line6 = "";
                                        line7 = "";
                                }
                        }

                        if (isDefined(self.ct_line1))
                                self.ct_line1 setText(line1);
                        if (isDefined(self.ct_line2))
                                self.ct_line2 setText(line2);
                        if (isDefined(self.ct_line3))
                                self.ct_line3 setText(line3);
                        if (isDefined(self.ct_line4))
                                self.ct_line4 setText(line4);
                        if (isDefined(self.ct_line5))
                                self.ct_line5 setText(line5);
                        if (isDefined(self.ct_line6))
                                self.ct_line6 setText(line6);
                        if (isDefined(self.ct_line7))
                                self.ct_line7 setText(line7);

                        barProgress = progressPct;
                        if (getDvarInt("ct_re_mode"))
                                barProgress = reProgressPct;

                        if (barProgress > 100) barProgress = 100;
                        if (barProgress < 0) barProgress = 0;
                        barWidth = int((barProgress * 148) / 100);
                        if (barWidth < 2) barWidth = 2;

                        if (isDefined(self.ct_bar_fill))
                        {
                                self.ct_bar_fill setShader("white", barWidth, 6);

                                if (getDvarInt("ct_re_mode"))
                                {
                                        if (reProgressPct >= 100)
                                                self.ct_bar_fill.color = (0.2, 1, 0.4);
                                        else if (reProgressPct >= 75)
                                                self.ct_bar_fill.color = (0.3, 0.8, 0.4);
                                        else
                                                self.ct_bar_fill.color = (0.3, 0.55, 1.0);
                                }
                                else
                                {
                                        if (kd10 >= targetKD10)
                                                self.ct_bar_fill.color = (0.2, 1, 0.4);
                                        else if (sessKD10 >= targetKD10)
                                                self.ct_bar_fill.color = (0.3, 0.8, 0.4);
                                        else
                                                self.ct_bar_fill.color = (0.3, 0.55, 1.0);
                                }
                        }

                        if (round != self.ct_last_round && round > 1)
                                self thread onRoundChange(round, sessKills);
                }

                if (isDefined(self.ct_hud_hidden) && self.ct_hud_hidden)
                {
                        wait 0.5;
                        continue;
                }

                inAfterlife = (isDefined(self.afterlife) && self.afterlife);
                if (inAfterlife)
                        setHudAlpha(0.15);
                else
                        setHudAlpha(0.85);

                wait 0.25;
        }
}


// ============================================================
//  CAREER SAVE — PERIODIC DVAR UPDATES
// ============================================================

// -----------------------------------------------------------------------------
// careerSaveLoop()
//
// Periodic autosave thread.
// Every 10 seconds, writes current totals back into dvars and persists to config.
// -----------------------------------------------------------------------------

careerSaveLoop()
{
        level endon("game_ended");
        self endon("disconnect");

        for (;;)
        {
                wait 10;
                saveCareerStats();
        }
}

// -----------------------------------------------------------------------------
// saveCareerStats()
//
// Writes the current career totals into dvars and persists them to disk.
// Uses both setDvar() (runtime) and cmdexec('seta ...') (config persistence).
// Calls writeconfig so values survive quitting the game.
// -----------------------------------------------------------------------------

saveCareerStats()
{
        kills = self.ct_base_kills + getPlayerKills();
        downs = self.ct_base_downs + getPlayerDowns();
        headshots = self.ct_base_headshots + self.ct_session_headshots;

        // Best round: keep the maximum across all matches.
        // We compare the saved career best vs the current match round.
        bestRound = getDvarInt("ct_career_rounds");
        curRound = 0;
        if (isDefined(level.round_number))
                curRound = level.round_number;
        if (curRound > bestRound)
                bestRound = curRound;

        games = getDvarInt("ct_career_games");

        rePos = self.ct_re_base_pos + self.ct_re_session_pos;
        reNeg = self.ct_re_base_neg + self.ct_re_session_neg;
        reExits = self.ct_re_base_exits + self.ct_re_session_exits;
        rePlaySec = self.ct_re_base_playsec + int((getTime() - self.ct_session_start) / 1000);

        // Update runtime dvars (these are what getDvarInt reads during play).
        // These are stored as strings, so we keep values numeric but pass them as ints/strings.
        setDvar("ct_career_kills", kills);
        setDvar("ct_career_downs", downs);
        setDvar("ct_career_headshots", headshots);
        setDvar("ct_career_rounds", bestRound);

        setDvar("ct_re_career_pos", rePos);
        setDvar("ct_re_career_neg", reNeg);
        setDvar("ct_re_career_exits", reExits);
        setDvar("ct_re_career_playsec", rePlaySec);

        // Persist to config with 'seta' so the values survive a full restart.
        // writeconfig writes the current dvar table to disk (config.cfg).
        cmdexec("seta ct_career_kills " + kills + "\n");
        cmdexec("seta ct_career_downs " + downs + "\n");
        cmdexec("seta ct_career_headshots " + headshots + "\n");
        cmdexec("seta ct_career_rounds " + bestRound + "\n");
        cmdexec("seta ct_career_games " + games + "\n");

        cmdexec("seta ct_re_career_pos " + rePos + "\n");
        cmdexec("seta ct_re_career_neg " + reNeg + "\n");
        cmdexec("seta ct_re_career_exits " + reExits + "\n");
        cmdexec("seta ct_re_career_playsec " + rePlaySec + "\n");

        cmdexec("writeconfig config.cfg\n");
}


// ============================================================
//  HUD ALPHA
// ============================================================

// -----------------------------------------------------------------------------
// setHudAlpha(a)
//
// Utility to fade the entire HUD as a unit.
// Used to dim the display during Afterlife (Mob of the Dead) without hiding it.
// -----------------------------------------------------------------------------

setHudAlpha(a)
{
        if (isDefined(self.ct_line1))  self.ct_line1.alpha = a;
        if (isDefined(self.ct_line2))  self.ct_line2.alpha = a * 0.85;
        if (isDefined(self.ct_line3))  self.ct_line3.alpha = a;
        if (isDefined(self.ct_line4))  self.ct_line4.alpha = a * 0.75;
        if (isDefined(self.ct_line5))  self.ct_line5.alpha = a * 0.75;
        if (isDefined(self.ct_line6))  self.ct_line6.alpha = a * 0.75;
        if (isDefined(self.ct_line7))  self.ct_line7.alpha = a * 0.75;
        if (isDefined(self.ct_bar_bg))  self.ct_bar_bg.alpha = a * 0.6;
        if (isDefined(self.ct_bar_fill))  self.ct_bar_fill.alpha = a;
}


// ============================================================
//  RANK DISPLAY — THRESHOLDS USED BY THIS TRACKER
// ============================================================

// -----------------------------------------------------------------------------
// getShotgunTarget(totalKills)
//
// Returns the target Kills/Downs ratio threshold for the Shotguns rank bar.
// This is a scaling target based on total kills (so expectations rise over time).
// -----------------------------------------------------------------------------

getShotgunTarget(totalKills)
{
        if (totalKills < 10000)
                return 120;
        if (totalKills < 20000)
                return 140;
        if (totalKills < 30000)
                return 160;
        if (totalKills < 40000)
                return 180;
        if (totalKills < 50000)
                return 200;
        return 220;
}

// -----------------------------------------------------------------------------
// getRankName(kd10, targetKD10)
//
// Converts a ratio (scaled x10) into a human-readable rank label.
// The returned string includes BO2 colour codes (e.g., ^5) for HUD display.
// -----------------------------------------------------------------------------

getRankName(kd10, targetKD10)
{
        if (kd10 >= targetKD10)
                return "^3SHOTGUNS";
        if (kd10 >= 1100)
                return "^7SKULL AND KNIFE";
        if (kd10 >= 600)
                return "^7SKULL";
        if (kd10 >= 200)
                return "^6CROSSED BONES";
        return "^8BONES";
}

// -----------------------------------------------------------------------------
// getRankProgress(kd10, targetKD10)
//
// Returns percentage progress toward the target (0–100).
// Inputs are scaled x10 to keep integer math stable in GSC.
// -----------------------------------------------------------------------------

getRankProgress(kd10, targetKD10)
{
        if (targetKD10 <= 0)
                return 100;
        pct = int((kd10 * 100) / targetKD10);
        if (pct > 100)
                pct = 100;
        if (pct < 0)
                pct = 0;
        return pct;
}

// -----------------------------------------------------------------------------
// getREShotgunTargetRatio10()
//
// Reads ct_re_sg_ratio10 (scaled x10) from dvars and returns a safe default if needed.
// Example: 1800 means a target ratio of 180.0 in the weighted model.
// -----------------------------------------------------------------------------

getREShotgunTargetRatio10()
{
        target10 = getDvarInt("ct_re_sg_ratio10");
        if (target10 <= 0)
                target10 = 1800; // 180.0 weighted R/D target (estimated default)
        return target10;
}

// -----------------------------------------------------------------------------
// getSimpleProgressPct(value, target)
//
// Generic helper: converts value/target into a clamped 0–100 percentage.
// -----------------------------------------------------------------------------

getSimpleProgressPct(value, target)
{
        if (target <= 0)
                return 100;

        pct = int((value * 100) / target);
        if (pct > 100)
                pct = 100;
        if (pct < 0)
                pct = 0;
        return pct;
}

// -----------------------------------------------------------------------------
// getREShotgunProgressPct(reRatio10, totalPlaySec)
//
// Computes progress for the Reverse-Engineered estimate mode.
// Primary gate: weighted ratio target (ct_re_sg_ratio10).
// Optional second gate: minimum playtime (ct_re_sg_playsec).
// If playtime gate is enabled, the progress bar shows the limiting factor.
// -----------------------------------------------------------------------------

getREShotgunProgressPct(reRatio10, totalPlaySec)
{
        ratioPct = getSimpleProgressPct(reRatio10, getREShotgunTargetRatio10());

        // Optional playtime gate. When enabled, progress bar shows the limiting factor toward shotguns.
        playTarget = getDvarInt("ct_re_sg_playsec");
        if (playTarget > 0)
        {
                timePct = getSimpleProgressPct(totalPlaySec, playTarget);
                if (timePct < ratioPct)
                        return timePct;
        }

        return ratioPct;
}

// -----------------------------------------------------------------------------
// getKillsNeeded(totalKills, totalDowns, targetKD)
//
// Returns how many additional kills are required to hit the target Kills/Downs ratio.
// Output is returned as a string so it can contain formatting or caps (e.g., 99999+).
// -----------------------------------------------------------------------------

getKillsNeeded(totalKills, totalDowns, targetKD)
{
        needed = (targetKD * totalDowns) - totalKills;
        if (totalDowns < 1)
                needed = targetKD - totalKills;
        if (needed <= 0)
                return "^20";
        if (needed > 99999)
                return "99999+";
        return "" + needed;
}

// ============================================================
//  ROUND TRANSITIONS
// ============================================================

// -----------------------------------------------------------------------------
// onRoundChange(round, kills)
//
// Handles round transitions.
// Updates best-round stats for the session (fastest round, most kills in a round).
// Optionally shows the round summary popup.
// Applies the weighted-round positive contribution for the Reverse-Engineered model.
// Updates best round reached in career dvars and forces a save.
// -----------------------------------------------------------------------------

onRoundChange(round, kills)
{
        self endon("disconnect");

        roundTime = (getTime() - self.ct_round_start) / 1000;
        roundKills = kills - self.ct_round_kills_start;

        if (roundKills > self.ct_best_round_kills)
                self.ct_best_round_kills = roundKills;
        if (roundTime < self.ct_best_round_time && roundTime > 0)
                self.ct_best_round_time = int(roundTime);

        if (getDvarInt("ct_round_summary"))
                self thread roundSummary(self.ct_last_round, int(roundTime), roundKills);

        // Community RE estimate: rounds only begin contributing positive value after first 4 played rounds
        completedAbsRound = self.ct_last_round;
        completedRelRound = getRelativePlayedRound(completedAbsRound);
        if (completedRelRound >= 5)
                self.ct_re_session_pos = self.ct_re_session_pos + (completedAbsRound * 100);

        bestRound = getDvarInt("ct_career_rounds");
        if (round > bestRound)
        {
                setDvar("ct_career_rounds", round);
                cmdexec("seta ct_career_rounds " + round + "\n");
        }

        saveCareerStats();

        self.ct_round_start = getTime();
        self.ct_round_kills_start = kills;
        self.ct_last_round = round;
}

// -----------------------------------------------------------------------------
// roundSummary(roundNum, roundTime, roundKills)
//
// Builds and animates a center-screen summary popup for the last round.
// Auto-destroys after a short delay to avoid HUD clutter.
// -----------------------------------------------------------------------------

roundSummary(roundNum, roundTime, roundKills)
{
        self endon("disconnect");

        if (isDefined(self.ct_summary))
                self.ct_summary destroy();

        timeStr = formatTime(roundTime);
        bestStr = "";
        if (self.ct_best_round_time < 999999)
                bestStr = "\n^7Best: ^3" + formatTime(self.ct_best_round_time) + " ^7(" + self.ct_best_round_kills + " Kills)";

        self.ct_summary = self createFontString("default", 1.6);
        self.ct_summary setPoint("CENTER", "CENTER", 0, -50);
        self.ct_summary.sort = 20;
        self.ct_summary.alpha = 0;
        self.ct_summary.hideWhenInMenu = 1;
        self.ct_summary.glowColor = (0.3, 0.55, 1.0);
        self.ct_summary.glowAlpha = 0.3;
        self.ct_summary setText("^5== ROUND " + roundNum + " ==\n^7Kills: ^5" + roundKills + "  ^7|  Time: ^5" + timeStr + bestStr);

        self.ct_summary fadeOverTime(0.3);
        self.ct_summary.alpha = 0.85;
        wait 3.5;
        self.ct_summary fadeOverTime(0.5);
        self.ct_summary.alpha = 0;
        wait 0.5;
        if (isDefined(self.ct_summary))
                self.ct_summary destroy();
}

// -----------------------------------------------------------------------------
// pbNotify(label, value)
//
// Placeholder hook for personal-best notifications.
// Currently disabled (early return) to avoid spam while keeping the structure ready.
// -----------------------------------------------------------------------------

pbNotify(label, value)
{
        self endon("disconnect");

        return;
}


// ============================================================
//  HUD — CLEAN TEXT LINES ABOVE HEALTH BAR
// ============================================================

// -----------------------------------------------------------------------------
// initCounterHUD()
//
// Creates the HUD elements (7 text lines + progress bar) and positions them.
// Destroys existing elements first so re-initializing does not duplicate HUD pieces.
// All elements are client HUD elems and are hidden while menus are open.
// -----------------------------------------------------------------------------

initCounterHUD()
{
        if (isDefined(self.ct_line1))  self.ct_line1 destroy();
        if (isDefined(self.ct_line2))  self.ct_line2 destroy();
        if (isDefined(self.ct_line3))  self.ct_line3 destroy();
        if (isDefined(self.ct_line4))  self.ct_line4 destroy();
        if (isDefined(self.ct_line5))  self.ct_line5 destroy();
        if (isDefined(self.ct_line6))  self.ct_line6 destroy();
        if (isDefined(self.ct_line7))  self.ct_line7 destroy();
        if (isDefined(self.ct_bar_bg))  self.ct_bar_bg destroy();
        if (isDefined(self.ct_bar_fill))  self.ct_bar_fill destroy();

        // Layout tuning:
        //   lineH  = vertical spacing between text lines (pixels).
        //   baseY  = distance up from the bottom of the screen (pixels).
        //   fSize  = font scale for readability without overlapping the health bar.

        lineH = 14;
        baseY = 82;
        fSize = 1.0;

        // Progress bar background (a dark rectangle).
        self.ct_bar_bg = newClientHudElem(self);
        self.ct_bar_bg.x = 5;
        self.ct_bar_bg.y = -(baseY);
        self.ct_bar_bg.alignX = "left";
        self.ct_bar_bg.alignY = "bottom";
        self.ct_bar_bg.horzAlign = "left";
        self.ct_bar_bg.vertAlign = "bottom";
        self.ct_bar_bg setShader("black", 152, 10);
        self.ct_bar_bg.color = (0.12, 0.12, 0.15);
        self.ct_bar_bg.alpha = 0;
        self.ct_bar_bg.sort = 3;
        self.ct_bar_bg.hideWhenInMenu = 1;

        // Progress bar fill (a coloured rectangle whose width changes with progress).
        self.ct_bar_fill = newClientHudElem(self);
        self.ct_bar_fill.x = 7;
        self.ct_bar_fill.y = -(baseY + 2);
        self.ct_bar_fill.alignX = "left";
        self.ct_bar_fill.alignY = "bottom";
        self.ct_bar_fill.horzAlign = "left";
        self.ct_bar_fill.vertAlign = "bottom";
        self.ct_bar_fill setShader("white", 2, 6);
        self.ct_bar_fill.color = (0.3, 0.55, 1.0);
        self.ct_bar_fill.alpha = 0;
        self.ct_bar_fill.sort = 4;
        self.ct_bar_fill.hideWhenInMenu = 1;

        self.ct_line7 = self createFontString("default", fSize);
        self.ct_line7 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12));
        self.ct_line7.sort = 3;
        self.ct_line7.alpha = 0;
        self.ct_line7.hideWhenInMenu = 1;

        self.ct_line6 = self createFontString("default", fSize);
        self.ct_line6 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH));
        self.ct_line6.sort = 3;
        self.ct_line6.alpha = 0;
        self.ct_line6.hideWhenInMenu = 1;

        self.ct_line5 = self createFontString("default", fSize);
        self.ct_line5 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH * 2));
        self.ct_line5.sort = 3;
        self.ct_line5.alpha = 0;
        self.ct_line5.hideWhenInMenu = 1;

        self.ct_line4 = self createFontString("default", fSize);
        self.ct_line4 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH * 3));
        self.ct_line4.sort = 3;
        self.ct_line4.alpha = 0;
        self.ct_line4.hideWhenInMenu = 1;

        self.ct_line3 = self createFontString("default", fSize);
        self.ct_line3 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH * 4));
        self.ct_line3.sort = 3;
        self.ct_line3.alpha = 0;
        self.ct_line3.hideWhenInMenu = 1;

        self.ct_line2 = self createFontString("default", fSize);
        self.ct_line2 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH * 5));
        self.ct_line2.sort = 3;
        self.ct_line2.alpha = 0;
        self.ct_line2.hideWhenInMenu = 1;

        self.ct_line1 = self createFontString("default", fSize);
        self.ct_line1 setPoint("BOTTOM_LEFT", "BOTTOM_LEFT", 5, -(baseY + 12 + lineH * 6));
        self.ct_line1.sort = 3;
        self.ct_line1.alpha = 0;
        self.ct_line1.hideWhenInMenu = 1;
}


// ============================================================
//  MAPVOTE INTEGRATION — HIDE DURING VOTING
// ============================================================

// -----------------------------------------------------------------------------
// mapvoteHideWatcher()
//
// Integration hook for mapvote scripts.
// Waits for the 'mapvote_start' level event, then fades the HUD out so the vote UI is clean.
// -----------------------------------------------------------------------------

mapvoteHideWatcher()
{
        self endon("disconnect");

        // Block until a mapvote system signals the start of voting.
        // If you do not use a mapvote script, this thread simply waits forever (safe).
        level waittill("mapvote_start");

        if (isDefined(self.ct_line1))
        {
                self.ct_line1 fadeOverTime(0.4);
                self.ct_line1.alpha = 0;
        }
        if (isDefined(self.ct_line2))
        {
                self.ct_line2 fadeOverTime(0.4);
                self.ct_line2.alpha = 0;
        }
        if (isDefined(self.ct_line3))
        {
                self.ct_line3 fadeOverTime(0.4);
                self.ct_line3.alpha = 0;
        }
        if (isDefined(self.ct_line4))
        {
                self.ct_line4 fadeOverTime(0.4);
                self.ct_line4.alpha = 0;
        }
        if (isDefined(self.ct_line5))
        {
                self.ct_line5 fadeOverTime(0.4);
                self.ct_line5.alpha = 0;
        }
        if (isDefined(self.ct_line6))
        {
                self.ct_line6 fadeOverTime(0.4);
                self.ct_line6.alpha = 0;
        }
        if (isDefined(self.ct_line7))
        {
                self.ct_line7 fadeOverTime(0.4);
                self.ct_line7.alpha = 0;
        }
        if (isDefined(self.ct_bar_bg))
        {
                self.ct_bar_bg fadeOverTime(0.4);
                self.ct_bar_bg.alpha = 0;
        }
        if (isDefined(self.ct_bar_fill))
        {
                self.ct_bar_fill fadeOverTime(0.4);
                self.ct_bar_fill.alpha = 0;
        }

        self.ct_hud_hidden = true;
}


// ============================================================
//  COMMUNITY RE TRACKER HELPERS (WEIGHTED ESTIMATE)
// ============================================================

// -----------------------------------------------------------------------------
// reGameEndWatcher()
//
// Reverse-Engineered estimate helper.
// On game end, applies a one-time exit penalty (community-observed behaviour).
// Saves immediately so leaving/ending still records the penalty + playtime.
// -----------------------------------------------------------------------------

reGameEndWatcher()
{
        self endon("disconnect");

        // Wait for the engine to end the match (deathout, host end, quit, etc.).
        level waittill("game_ended");

        if (!isDefined(self.ct_re_exit_penalty_applied) || !self.ct_re_exit_penalty_applied)
        {
                // Community finding: ending/leaving a game appears to add an additional negative hit
                self.ct_re_session_neg = self.ct_re_session_neg + 100;
                self.ct_re_session_exits++;
                self.ct_re_exit_penalty_applied = true;
                saveCareerStats();
        }
}

// -----------------------------------------------------------------------------
// getRelativePlayedRound(absRound)
//
// Converts the absolute round number into a 'played-round index' for this match.
// Example: if you join on round 10, your played-round 1 is still 10.
// Used so early downs in *your* run are weighted more heavily than late downs.
// -----------------------------------------------------------------------------

getRelativePlayedRound(absRound)
{
        if (!isDefined(self.ct_re_start_round_abs))
                return absRound;

        // Example: start round 10 → absRound 10 becomes relRound 1.
        rel = (absRound - self.ct_re_start_round_abs) + 1;
        if (rel < 1)
                rel = 1;
        return rel;
}

// -----------------------------------------------------------------------------
// getDownPenaltyScaled(relRound)
//
// Returns the negative weight for a down based on played-round index.
// Values are scaled x100 so we can use integer math while preserving decimals.
// -----------------------------------------------------------------------------

getDownPenaltyScaled(relRound)
{
        // Scaled x100. Community RE-style weighting by played-round index.
        if (relRound <= 5)
                return 100; // 1.00
        if (relRound <= 10)
                return 50;  // 0.50
        if (relRound <= 15)
                return 33;  // 0.33
        if (relRound <= 20)
                return 25;  // 0.25
        if (relRound <= 25)
                return 20;  // 0.20
        return 10;          // 0.10 (late-round downs still hurt, but less)
}


// ============================================================
//  PLAYER STAT HELPERS
// ============================================================

// -----------------------------------------------------------------------------
// getPlayerKills()
//
// Safe accessor for the player's kill count.
// Tries self.kills first, then self.pers['kills'], then falls back to 0.
// -----------------------------------------------------------------------------

getPlayerKills()
{
        if (isDefined(self.kills))
                return self.kills;
        if (isDefined(self.pers) && isDefined(self.pers["kills"]))
                return self.pers["kills"];
        return 0;
}

// -----------------------------------------------------------------------------
// getPlayerDowns()
//
// Safe accessor for the player's down count.
// Tries self.downs first, then self.pers['downs'], then falls back to 0.
// -----------------------------------------------------------------------------

getPlayerDowns()
{
        if (isDefined(self.downs))
                return self.downs;
        if (isDefined(self.pers) && isDefined(self.pers["downs"]))
                return self.pers["downs"];
        return 0;
}

// -----------------------------------------------------------------------------
// getPlayerRevives()
//
// Safe accessor for the player's revive count.
// Included for future HUD expansion; currently not displayed by default.
// -----------------------------------------------------------------------------

getPlayerRevives()
{
        if (isDefined(self.revives))
                return self.revives;
        if (isDefined(self.pers) && isDefined(self.pers["revives"]))
                return self.pers["revives"];
        return 0;
}

// -----------------------------------------------------------------------------
// getPlayerHeadshots()
//
// Safe accessor for the player's headshot count.
// Used to compute headshot percentage across career + this session.
// -----------------------------------------------------------------------------

getPlayerHeadshots()
{
        if (isDefined(self.headshots))
                return self.headshots;
        if (isDefined(self.pers) && isDefined(self.pers["headshots"]))
                return self.pers["headshots"];
        return 0;
}


// ============================================================
//  FORMATTING UTILITIES
// ============================================================

// -----------------------------------------------------------------------------
// formatTime(totalSeconds)
//
// Formats seconds as M:SS or H:MM:SS for HUD display.
// -----------------------------------------------------------------------------

formatTime(totalSeconds)
{
        hours = int(totalSeconds / 3600);
        minutes = int((totalSeconds % 3600) / 60);
        seconds = int(totalSeconds % 60);

        if (hours > 0)
                return "" + hours + ":" + padZero(minutes) + ":" + padZero(seconds);
        return "" + minutes + ":" + padZero(seconds);
}

// -----------------------------------------------------------------------------
// padZero(num)
//
// Formats a 0–9 integer as a zero-padded two-character string (e.g., 7 → '07').
// -----------------------------------------------------------------------------

padZero(num)
{
        if (num < 10)
                return "0" + num;
        return "" + num;
}

// -----------------------------------------------------------------------------
// formatScaled100(v)
//
// Formats a value scaled x100 into a single-decimal string.
// Example: 250 → '2.5'. Used for weighted down totals on HUD.
// -----------------------------------------------------------------------------

formatScaled100(v)
{
        if (v < 0)
                v = 0;

        whole = int(v / 100);
        dec = int((v % 100) / 10);
        return "" + whole + "." + dec;
}

// -----------------------------------------------------------------------------
// formatPlaytimeSpelledOut(totalSeconds)
//
// Formats playtime as 'X Hours Y Minutes' or 'Y Minutes' for readability.
// -----------------------------------------------------------------------------

formatPlaytimeSpelledOut(totalSeconds)
{
        h = int(totalSeconds / 3600);
        m = int((totalSeconds % 3600) / 60);

        if (h > 0)
        {
                hourWord = "Hours";
                if (h == 1)
                        hourWord = "Hour";

                minuteWord = "Minutes";
                if (m == 1)
                        minuteWord = "Minute";

                return "" + h + " " + hourWord + " " + m + " " + minuteWord;
        }

        minuteWord = "Minutes";
        if (m == 1)
                minuteWord = "Minute";

        return "" + m + " " + minuteWord;
}

// -----------------------------------------------------------------------------
// formatKPM(kpm)
//
// Formats kills-per-minute with one decimal place for HUD display.
// -----------------------------------------------------------------------------

formatKPM(kpm)
{
        // Note: GSC float math can be a little loose; we only display 1 decimal.
        // kpm here is computed as kills / minutes in mainLoop.
        whole = int(kpm);
        decimal = int((kpm - whole) * 10);
        return "^7" + whole + "." + decimal;
}
