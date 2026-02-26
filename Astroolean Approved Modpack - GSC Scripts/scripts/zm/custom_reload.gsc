#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;

// ╔════════════════════════════════════════════════════════════════════╗
// ║                     CUSTOM RELOAD SYSTEM v2.0                      ║
// ║                Black Ops II Zombies · Plutonium T6                 ║
// ║                                                                    ║
// ║  Created by: Astroolean                                            ║
// ║                                                                    ║
// ║  What this does                                                    ║
// ║    - While you are reloading, your move speed is adjusted based    ║
// ║      on weapon weight (light/medium/heavy).                        ║
// ║    - Tactical reload detection: if you started reloading with      ║
// ║      ammo still in the magazine, you get an extra bonus.           ║
// ║    - Tactical streak: chaining tactical reloads stacks a small     ║
// ║      bonus up to a configurable cap.                               ║
// ║    - Mastery ranks: your total tactical reloads determine a rank   ║
// ║      (Novice → Skilled → Expert → Elite → Master) with a small     ║
// ║      permanent bonus for the rest of the match.                    ║
// ║    - Speed Cola synergy: bonuses can be multiplied if you have     ║
// ║      specialty_fastreload (Speed Cola).                            ║
// ║    - Optional HUD helpers are included (animated reload bar),      ║
// ║      but are only used if you call the HUD functions.              ║
// ║                                                                    ║
// ║  Configuration (DVARs)                                             ║
// ║    rl_speed_light      1.40    Move speed while reloading (light)  ║
// ║    rl_speed_medium     1.25    Move speed while reloading (med)    ║
// ║    rl_speed_heavy      1.10    Move speed while reloading (heavy)  ║
// ║    rl_tactical_bonus   0.15    Flat bonus if tactical reload       ║
// ║    rl_streak_max       10      Max streak level used in bonus      ║
// ║    rl_streak_step      0.02    Bonus per streak level              ║
// ║    rl_cola_mult        1.20    Multiplier when Speed Cola is owned ║
// ║    rl_burst_speed      1.12    Post-reload burst speed             ║
// ║    rl_burst_time       0.6     Post-reload burst duration (sec)    ║
// ║    rl_hud              1       Enable HUD code path (0/1)          ║
// ║                                                                    ║
// ║  Safety                                                            ║
// ║    Speed is capped at 1.80 to avoid animation / timing desync.     ║
// ╚════════════════════════════════════════════════════════════════════╝


// ============================================================
//  INITIALIZATION
// ============================================================


// init()
// Entry point called when this script is loaded.
// - Sets default DVAR values (only if they are not already set).
// - Starts the player connect listener so every player gets the reload thread.
// Notes:
// - This script only changes movement speed via setMoveSpeedScale().

init()
{
        initReloadDvars();
        level thread onPlayerConnect();
}


// initReloadDvars()
// Defines safe defaults for every rl_* DVAR used by this script.
// Important:
// - If a DVAR is already set (server cfg / console), this does NOT overwrite it.

initReloadDvars()
{
        if (getDvar("rl_speed_light") == "")
                setDvar("rl_speed_light", "1.40");
        if (getDvar("rl_speed_medium") == "")
                setDvar("rl_speed_medium", "1.25");
        if (getDvar("rl_speed_heavy") == "")
                setDvar("rl_speed_heavy", "1.10");
        if (getDvar("rl_tactical_bonus") == "")
                setDvar("rl_tactical_bonus", "0.15");
        if (getDvar("rl_streak_max") == "")
                setDvar("rl_streak_max", "10");
        if (getDvar("rl_streak_step") == "")
                setDvar("rl_streak_step", "0.02");
        if (getDvar("rl_cola_mult") == "")
                setDvar("rl_cola_mult", "1.20");
        if (getDvar("rl_burst_speed") == "")
                setDvar("rl_burst_speed", "1.12");
        if (getDvar("rl_burst_time") == "")
                setDvar("rl_burst_time", "0.6");
        if (getDvar("rl_hud") == "")
                setDvar("rl_hud", "1");
}


// onPlayerConnect()
// Waits for players to connect, then starts per-player spawn hooks.

onPlayerConnect()
{
        for (;;)
        {
                level waittill("connected", player);
                player thread onPlayerSpawned();
        }
}


// onPlayerSpawned()
// Runs on each player.
// - Re-initializes per-life counters/trackers on each spawn.
// - Starts the core reload monitor thread (reloadCore).
// Threads and end conditions:
// - This loop ends on disconnect; reloadCore ends on death/disconnect.

onPlayerSpawned()
{
        self endon("disconnect");

        for (;;)
        {
                self waittill("spawned_player");

                self.rl_streak = 0;
                self.rl_best_streak = 0;
                self.rl_total_reloads = 0;
                self.rl_tactical_count = 0;
                self.rl_rank = 0;
                self.rl_prev_rank = 0;

                self thread reloadCore();
        }
}


// ============================================================
//  CORE RELOAD ENGINE
// ============================================================


// reloadCore()
// Main state machine that detects reload start/end and applies movement speed.
// How it works:
// - Detects reload edge: (isReloading false → true) = reload start.
// - Detects reload edge: (isReloading true → false) = reload end.
// On reload start:
// - Captures weapon, ammo-in-clip before reload, and weight class.
// - Determines if it's a tactical reload (clipBefore > 0).
// - Calculates speed multiplier and applies it immediately.
// On reload end:
// - Checks if the reload actually completed (ammo increased for same weapon).
// - Updates tactical count / streak / best streak and rank.
// - If completed, fires a short post-reload burst animation; otherwise resets speed.
// Notifies used:
// - Sends "rl_burst_stop" to cancel any active burst when a new reload starts.

reloadCore()
{
        self endon("disconnect");
        self endon("death");

        // State tracked across frames so we can detect the exact start/end of a reload.
        // wasReloading: last frame's reload state (edge detection).
        // weapon/clipBefore: snapshot of weapon + ammo BEFORE reload starts (used to detect completion).
        // isTactical: true if the magazine was not empty when reload began.
        // weight: simplified weapon weight class used for speed scaling.
        wasReloading = false;
        weapon = "";
        clipBefore = 0;
        isTactical = false;
        weight = "medium";

        for (;;)
        {
                // Poll the engine reload flag. We use it like a simple state machine.
                isNow = self isReloading();


                // ── Reload START (false → true) ─────────────────────────────────────────
                if (isNow && !wasReloading)
                {
                        weapon = self getCurrentWeapon();
                        weight = getWeaponWeight(weapon);
                        clipBefore = self getWeaponAmmoClip(weapon);
                        isTactical = (clipBefore > 0);

                        speed = calcReloadSpeed(weight, isTactical, self.rl_streak, self.rl_rank, self hasPerk("specialty_fastreload"));
                        self setMoveSpeedScale(speed);

                        self notify("rl_burst_stop");
                }


                // ── Reload END (true → false) ──────────────────────────────────────────
                // Determine whether the reload actually completed, then update streak/rank.
                if (!isNow && wasReloading)
                {
                        sameWeapon = (self getCurrentWeapon() == weapon);
                        clipAfter = 0;
                        if (sameWeapon && isDefined(weapon) && weapon != "")
                                clipAfter = self getWeaponAmmoClip(weapon);
                        // Completed means: player stayed on the same weapon AND ammo-in-clip increased.
                        completed = (sameWeapon && clipAfter > clipBefore);

                        // Tactical completion = reload finished AND we started with ammo left in mag.
                        // Tactical reloads increase the mastery counter and can build a streak.
                        if (completed && isTactical)
                        {
                                self.rl_tactical_count++;
                                self.rl_streak++;
                                if (self.rl_streak > self.rl_best_streak)
                                        self.rl_best_streak = self.rl_streak;
                        }
                        else
                        {
                                self.rl_streak = 0;
                        }

                        self.rl_total_reloads++;


                        // Recompute mastery rank from total tactical reloads.
                        // Tip: If you want rank-up messages, you would compare rl_prev_rank vs rl_rank here
                        // and call rankUpNotify(self.rl_rank) when it increases. (Comments only; no calls here.)
                        self.rl_prev_rank = self.rl_rank;
                        self.rl_rank = calcRank(self.rl_tactical_count);

                        if (completed)
                                self thread postReloadBurst();
                        else
                                self setMoveSpeedScale(1.0);
                }

                wasReloading = isNow;
                wait 0.05;
        }
}


// ============================================================
//  SPEED CALCULATIONS
// ============================================================


// calcReloadSpeed(weight, isTactical, streak, rank, hasCola)
// Returns the movement speed multiplier to use DURING the reload animation.
// Inputs:
// - weight: "light" | "medium" | "heavy" (see getWeaponWeight).
// - isTactical: true if player began reload with ammo left in mag.
// - streak: current tactical reload streak (clamped by rl_streak_max).
// - rank: mastery rank index (0-4) based on total tactical reloads.
// - hasCola: true if player has Speed Cola perk (specialty_fastreload).
// Safety:
// - Clamps final value to 1.80 to reduce timing/animation issues.

calcReloadSpeed(weight, isTactical, streak, rank, hasCola)
{
        switch (weight)
        {
        case "light":
                base = getDvarFloat("rl_speed_light");
                break;
        case "heavy":
                base = getDvarFloat("rl_speed_heavy");
                break;
        default:
                base = getDvarFloat("rl_speed_medium");
                break;
        }

        if (isTactical)
                base += getDvarFloat("rl_tactical_bonus");

        maxStreak = getDvarInt("rl_streak_max");
        streakLevel = streak;
        if (streakLevel > maxStreak)
                streakLevel = maxStreak;
        base += streakLevel * getDvarFloat("rl_streak_step");

        base += getRankBonus(rank);

        if (hasCola)
                base *= getDvarFloat("rl_cola_mult");

        if (base > 1.80)
                base = 1.80;

        return base;
}


// getWeaponWeight(weapon)
// Maps a weapon to a simple weight class used for speed scaling.
// Fallback:
// - If weapon is undefined/empty/none, returns "medium".
// Implementation:
// - Uses weaponClass() to map pistols/SMGs to light, MG/sniper/rocket to heavy.

getWeaponWeight(weapon)
{
        if (!isDefined(weapon) || weapon == "" || weapon == "none")
                return "medium";

        wClass = weaponClass(weapon);

        switch (wClass)
        {
        case "pistol":
        case "smg":
                return "light";
        case "mg":
        case "sniper":
        case "rocketlauncher":
                return "heavy";
        default:
                return "medium";
        }
}


// postReloadBurst()
// Short movement 'burst' AFTER a successful reload completes.
// Design:
// - Applies burst speed briefly, then eases down in steps back to 1.0.
// End conditions:
// - Stops on disconnect, death, or "rl_burst_stop" notify.

postReloadBurst()
{
        self endon("disconnect");
        self endon("death");
        self endon("rl_burst_stop");

        burstSpeed = getDvarFloat("rl_burst_speed");
        burstTime = getDvarFloat("rl_burst_time");
        diff = burstSpeed - 1.0;

        self setMoveSpeedScale(burstSpeed);
        wait (burstTime * 0.5);

        self setMoveSpeedScale(1.0 + diff * 0.6);
        wait (burstTime * 0.2);

        self setMoveSpeedScale(1.0 + diff * 0.3);
        wait (burstTime * 0.2);

        self setMoveSpeedScale(1.0 + diff * 0.1);
        wait (burstTime * 0.1);

        self setMoveSpeedScale(1.0);
}


// ============================================================
//  MASTERY RANK SYSTEM
// ============================================================


// calcRank(tacticalCount)
// Returns mastery rank index (0-4) based on total tactical reloads performed.
// Ranks:
// 0 Novice  (<10) | 1 Skilled (10+) | 2 Expert (25+) | 3 Elite (50+) | 4 Master (100+)

calcRank(tacticalCount)
{
        if (tacticalCount >= 100) return 4;
        if (tacticalCount >= 50)  return 3;
        if (tacticalCount >= 25)  return 2;
        if (tacticalCount >= 10)  return 1;
        return 0;
}


// getRankName(rank)
// Returns a color-coded label string for HUD/messages based on rank index.

getRankName(rank)
{
        switch (rank)
        {
        case 1:  return "^2SKILLED";
        case 2:  return "^5EXPERT";
        case 3:  return "^6ELITE";
        case 4:  return "^3MASTER";
        default: return "^7NOVICE";
        }
}


// getRankBonus(rank)
// Returns the flat speed bonus (0.00 - 0.08) granted by mastery rank.
// Applied inside calcReloadSpeed() so it affects reload movement speed.

getRankBonus(rank)
{
        switch (rank)
        {
        case 1:  return 0.02;
        case 2:  return 0.04;
        case 3:  return 0.06;
        case 4:  return 0.08;
        default: return 0.0;
        }
}


// rankUpNotify(rank)
// Prints a simple on-screen message when a player reaches a new mastery rank.
// Note:
// - This function is defined for convenience but is NOT called by default in this file.
//   If you want rank-up callouts, you would call it when rl_rank changes.

rankUpNotify(rank)
{
        self endon("disconnect");

        name = getRankName(rank);
        bonus = int(getRankBonus(rank) * 100);

        self iPrintLn("^5Reload " + name + " ^7+" + bonus + "% Speed");
}


// ============================================================
//  STREAK MILESTONES
// ============================================================


// streakMilestone(streak)
// Prints milestone callouts at specific streak values (3, 5, 10).
// Note:
// - This function is defined for convenience but is NOT called by default in this file.
//   If you want streak callouts, you would call it when rl_streak increases.

streakMilestone(streak)
{
        self endon("disconnect");

        if (streak != 3 && streak != 5 && streak != 10)
                return;

        switch (streak)
        {
        case 3:
                self iPrintLn("^5Tactical x3");
                break;
        case 5:
                self iPrintLn("^3Tactical x5");
                break;
        case 10:
                self iPrintLn("^6Tactical x10");
                break;
        }
}


// ============================================================
//  advanced HUD — ANIMATED RELOAD BAR
// ============================================================


// initReloadHUD()
// Builds/refreshes HUD elements for the animated reload bar.
// Elements created:
// - rl_hud_bg: background plate
// - rl_hud_fill: animated fill bar
// - rl_hud_glow: subtle glow plate behind the bar
// - rl_hud_status: text (RELOADING / TACTICAL)
// - rl_hud_streak: text (streak + rank after completion)
// Safety:
// - Destroys old elems first to avoid duplicates on respawn.

initReloadHUD()
{
        if (isDefined(self.rl_hud_bg))
                self.rl_hud_bg destroy();
        if (isDefined(self.rl_hud_fill))
                self.rl_hud_fill destroy();
        if (isDefined(self.rl_hud_glow))
                self.rl_hud_glow destroy();
        if (isDefined(self.rl_hud_status))
                self.rl_hud_status destroy();
        if (isDefined(self.rl_hud_streak))
                self.rl_hud_streak destroy();

        barW = 80;
        barH = 3;
        xPos = 85;
        yPos = -42;

        self.rl_hud_bg = newClientHudElem(self);
        self.rl_hud_bg.x = xPos;
        self.rl_hud_bg.y = yPos;
        self.rl_hud_bg.alignX = "center";
        self.rl_hud_bg.alignY = "middle";
        self.rl_hud_bg.horzAlign = "left";
        self.rl_hud_bg.vertAlign = "bottom";
        self.rl_hud_bg.sort = 10;
        self.rl_hud_bg.alpha = 0;
        self.rl_hud_bg.color = (0.06, 0.07, 0.09);
        self.rl_hud_bg setShader("white", barW + 4, barH + 4);

        self.rl_hud_fill = newClientHudElem(self);
        self.rl_hud_fill.x = xPos - (barW / 2);
        self.rl_hud_fill.y = yPos;
        self.rl_hud_fill.alignX = "left";
        self.rl_hud_fill.alignY = "middle";
        self.rl_hud_fill.horzAlign = "left";
        self.rl_hud_fill.vertAlign = "bottom";
        self.rl_hud_fill.sort = 11;
        self.rl_hud_fill.alpha = 0;
        self.rl_hud_fill.color = (0.25, 0.5, 0.85);
        self.rl_hud_fill setShader("white", 1, barH);

        self.rl_hud_glow = newClientHudElem(self);
        self.rl_hud_glow.x = xPos;
        self.rl_hud_glow.y = yPos;
        self.rl_hud_glow.alignX = "center";
        self.rl_hud_glow.alignY = "middle";
        self.rl_hud_glow.horzAlign = "left";
        self.rl_hud_glow.vertAlign = "bottom";
        self.rl_hud_glow.sort = 9;
        self.rl_hud_glow.alpha = 0;
        self.rl_hud_glow.color = (0.3, 0.55, 1.0);
        self.rl_hud_glow setShader("white", barW + 8, barH + 8);

        self.rl_hud_status = self createFontString("default", 1.0);
        self.rl_hud_status setPoint("LEFT", "BOTTOM_LEFT", xPos - (barW / 2), yPos - 8);
        self.rl_hud_status.alpha = 0;
        self.rl_hud_status.sort = 12;

        self.rl_hud_streak = self createFontString("default", 1.0);
        self.rl_hud_streak setPoint("LEFT", "BOTTOM_LEFT", xPos - (barW / 2), yPos + 8);
        self.rl_hud_streak.alpha = 0;
        self.rl_hud_streak.sort = 12;
}


// showReloadBar(weight, isTactical)
// Shows and animates the reload progress bar for the estimated reload time.
// Notes:
// - This is an estimate (getReloadEstimate) and not tied to exact weapon timings.
// - Ends on "rl_hud_stop" notify if you choose to send it from your own code.

showReloadBar(weight, isTactical)
{
        self endon("disconnect");
        self endon("death");
        self endon("rl_hud_stop");

        if (!isDefined(self.rl_hud_bg))
                return;

        barW = 80;
        barH = 3;

        estTime = getReloadEstimate(weight, self hasPerk("specialty_fastreload"));

        if (isTactical)
        {
                self.rl_hud_fill.color = (0.85, 0.7, 0.2);
                self.rl_hud_glow.color = (0.85, 0.7, 0.2);
                self.rl_hud_status setText("^3TACTICAL");
        }
        else
        {
                self.rl_hud_fill.color = (0.25, 0.5, 0.85);
                self.rl_hud_glow.color = (0.3, 0.55, 1.0);
                self.rl_hud_status setText("^5RELOADING");
        }

        if (self.rl_rank >= 4)
        {
                self.rl_hud_fill.color = (1.0, 0.85, 0.3);
                self.rl_hud_glow.color = (1.0, 0.85, 0.3);
        }

        self.rl_hud_bg.alpha = 0.6;
        self.rl_hud_fill.alpha = 0.85;
        self.rl_hud_glow.alpha = 0.1;
        self.rl_hud_status.alpha = 0.65;

        self.rl_hud_fill setShader("white", 1, barH);
        self.rl_hud_fill scaleOverTime(estTime, barW, barH);
}


// hideReloadBar(completed, wasTactical, streak)
// Fades out the reload HUD. If the reload completed, briefly flashes the bar and
// optionally shows a streak/rank line for tactical reload streaks.
// Notes:
// - Ends on "rl_hud_stop" notify if you choose to send it from your own code.

hideReloadBar(completed, wasTactical, streak)
{
        self endon("disconnect");
        self endon("death");
        self endon("rl_hud_stop");

        if (!isDefined(self.rl_hud_bg))
                return;

        barW = 80;
        barH = 3;

        if (completed)
        {
                self.rl_hud_fill.color = (0.3, 0.9, 1.0);
                self.rl_hud_fill setShader("white", barW, barH);
                self.rl_hud_glow.alpha = 0.3;
                self.rl_hud_glow.color = (0.3, 0.9, 1.0);

                if (wasTactical && streak > 0)
                {
                        rankName = getRankName(self.rl_rank);
                        self.rl_hud_streak setText("^5" + streak + "x ^7STREAK  ^5|  " + rankName);
                        self.rl_hud_streak.alpha = 0.55;
                }

                wait 0.25;
        }

        self.rl_hud_bg fadeOverTime(0.35);
        self.rl_hud_bg.alpha = 0;
        self.rl_hud_fill fadeOverTime(0.35);
        self.rl_hud_fill.alpha = 0;
        self.rl_hud_glow fadeOverTime(0.35);
        self.rl_hud_glow.alpha = 0;
        self.rl_hud_status fadeOverTime(0.35);
        self.rl_hud_status.alpha = 0;

        if (completed && streak > 0)
        {
                wait 1.2;
                if (isDefined(self.rl_hud_streak))
                {
                        self.rl_hud_streak fadeOverTime(0.4);
                        self.rl_hud_streak.alpha = 0;
                }
        }
        else if (isDefined(self.rl_hud_streak))
        {
                self.rl_hud_streak.alpha = 0;
        }
}


// ============================================================
//  RELOAD TIME ESTIMATION (for HUD progress bar)
// ============================================================


// getReloadEstimate(weight, hasCola)
// Returns a rough reload duration used ONLY for the HUD animation.
// Values are tuned by weight class and halved if Speed Cola is owned.

getReloadEstimate(weight, hasCola)
{
        switch (weight)
        {
        case "light":
                base = 1.8;
                break;
        case "heavy":
                base = 3.5;
                break;
        default:
                base = 2.5;
                break;
        }

        if (hasCola)
                base *= 0.5;

        return base;
}
