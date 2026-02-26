#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_perks;

// ╔════════════════════════════════════════════════════════════════════╗
// ║  CUSTOM DEADSHOT DAIQUIRI+ v2.0                                    ║
// ║  Enhanced Deadshot bonuses · Black Ops II Zombies (Plutonium T6)   ║
// ║                                                                    ║
// ║  Created by: Astroolean                                            ║
// ║                                                                    ║
// ║  WHAT THIS SCRIPT DOES                                             ║
// ║    • Watches for perk gained/lost events and toggles "Deadshot+"   ║
// ║      automatically when the player has Deadshot Daiquiri.          ║
// ║    • While active, grants helper perks for faster ADS / reduced    ║
// ║      sway / better bullet accuracy (engine perks, not custom math).║
// ║    • Adds a headshot reward loop:                                  ║
// ║        - Bonus points per headshot event                           ║
// ║        - Small heal per headshot event (clamped to maxhealth)      ║
// ║        - Headshot streak tracker with milestone callouts           ║
// ║    • Cleans everything up when the perk is lost, on death, or      ║
// ║      when the player disconnects.                                  ║
// ║                                                                    ║
// ║  CONFIGURATION (DVARs)                                             ║
// ║    ds_hs_damage  (default "1.35")  Reserved (not used in this file)║
// ║    ds_hs_points  (default "50")    Bonus score per headshot event  ║
// ║    ds_hs_heal    (default "15")    Health restored per headshot    ║
// ║    ds_hud        (default "1")     Enables iPrintLn notifications  ║
// ║                                                                    ║
// ║  HEADSHOT STREAK MILESTONES                                        ║
// ║    5x  Sharpshooter   10x Marksman   25x Deadeye                   ║
// ║    50x Skull Collector               100x HEAD HUNTER              ║
// ║                                                                    ║
// ║  FILE LAYOUT                                                       ║
// ║    1) init / player connect / spawn hooks                          ║
// ║    2) perk monitor + cleanup on death                              ║
// ║    3) activate / deactivate (grant & remove helper perks)          ║
// ║    4) headshot reward loop + streak milestones                     ║
// ║    5) notification helpers                                         ║
// ╚════════════════════════════════════════════════════════════════════╝



// ============================================================
//  1) INITIALIZATION / PLAYER HOOKS
// ============================================================

/*
    init()
    ------
    Entry point. Sets default DVAR values only when they are missing,
    then registers the player connection handler.

    IMPORTANT:
    - DVAR defaults are strings in BO2 GSC, so these are set as "50", "15", etc.
    - If a server config or another script already set these DVARs, we do NOT overwrite.
*/
init()
{
	// Set defaults only if the DVAR doesn't exist yet.
	if (getDvar("ds_hs_damage") == "")
		setDvar("ds_hs_damage", "1.35"); // Reserved (kept for compatibility / future use)

	if (getDvar("ds_hs_points") == "")
		setDvar("ds_hs_points", "50");

	if (getDvar("ds_hs_heal") == "")
		setDvar("ds_hs_heal", "15");

	if (getDvar("ds_hud") == "")
		setDvar("ds_hud", "1");

	// Start listening for player connections.
	level thread onPlayerConnect();
}

/*
    onPlayerConnect()
    -----------------
    Runs forever. Each time a player connects, we start the per-player
    spawn handler thread.
*/
onPlayerConnect()
{
	for (;;)
	{
		level waittill("connected", player);
		player thread onPlayerSpawned();
	}
}

/*
    onPlayerSpawned()
    -----------------
    Runs per-player, forever across respawns.

    Every time this player spawns, we:
    - reset runtime state
    - start the perk monitor thread
    - start a death watcher thread (to guarantee cleanup)
*/
onPlayerSpawned()
{
	self endon("disconnect");

	for (;;)
	{
		self waittill("spawned_player");

		// Runtime flags / counters reset on each spawn.
		self.ds_active = false;   // Are Deadshot+ bonuses currently applied?
		self.ds_hs_streak = 0;    // Current headshot streak (resets on spawn in this script)
		self.ds_hs_total = 0;     // Total headshots tracked (lifetime for this life)

		// Start the monitor that turns Deadshot+ on/off based on perk state.
		self thread monitorDeadshot();

		// Ensure we always clean up if the player dies (perk monitor ends-on-death too,
		// but this makes cleanup explicit and safe).
		self thread watchDeath();
	}
}



// ============================================================
//  2) CORE ENGINE — PERK STATE MONITORING
// ============================================================

/*
    monitorDeadshot()
    -----------------
    Event-driven loop that listens for perk changes.

    Waits for either:
    - "perk_acquired"
    - "perk_lost"

    Then checks if the player currently has Deadshot Daiquiri.
    If yes and not already active -> activate.
    If no and currently active -> deactivate.
*/
monitorDeadshot()
{
	self endon("disconnect");
	self endon("death");

	for (;;)
	{
		// Efficient: only wakes up when a perk changes.
		self waittill_any("perk_acquired", "perk_lost");

		hasDeadshot = self hasPerk("specialty_deadshot");

		if (hasDeadshot && !self.ds_active)
		{
			self thread activateDeadshotPlus();
		}
		else if (!hasDeadshot && self.ds_active)
		{
			self thread deactivateDeadshotPlus();
		}
	}
}

/*
    watchDeath()
    ------------
    One-shot cleanup on death.

    This does not modify the death flow; it only ensures Deadshot+ is removed
    so no helper perks leak across states.
*/
watchDeath()
{
	self endon("disconnect");

	self waittill("death");

	if (self.ds_active)
		self thread deactivateDeadshotPlus();
}



// ============================================================
//  3) ACTIVATION / DEACTIVATION — APPLY & REMOVE BONUSES
// ============================================================

/*
    activateDeadshotPlus()
    ----------------------
    Applies helper perks and starts the headshot reward loop.

    Notes:
    - These are built-in engine perks (fast ADS / reduced sway / accuracy).
    - We only set them if missing, so we don't fight other mods.
*/
activateDeadshotPlus()
{
	self endon("disconnect");

	self.ds_active = true;

	// Faster aim-down-sight speed.
	if (!self hasPerk("specialty_fastads"))
		self setPerk("specialty_fastads");

	// Reduced weapon idle sway.
	if (!self hasPerk("specialty_reducedsway"))
		self setPerk("specialty_reducedsway");

	// Improved bullet accuracy / spread handling.
	if (!self hasPerk("specialty_bulletaccuracy"))
		self setPerk("specialty_bulletaccuracy");

	// Start the headshot reward loop. It self-terminates on death/deactivate.
	self thread headshotBonusLoop();

	// Optional: show activation message.
	if (getDvarInt("ds_hud"))
		self thread activateNotify();
}

/*
    deactivateDeadshotPlus()
    ------------------------
    Removes helper perks and signals the headshot loop to stop.

    The notify("ds_deactivate") is the clean shutdown signal for the bonus loop,
    so we never leave a running thread behind after losing the perk.
*/
deactivateDeadshotPlus()
{
	self endon("disconnect");

	self.ds_active = false;

	// Signal any running bonus loop(s) to stop.
	self notify("ds_deactivate");

	// Remove helper perks, but only if we are the reason they exist.
	// (If another mod sets these perks later, it can re-set them.)
	if (self hasPerk("specialty_fastads"))
		self unsetPerk("specialty_fastads");

	if (self hasPerk("specialty_reducedsway"))
		self unsetPerk("specialty_reducedsway");

	if (self hasPerk("specialty_bulletaccuracy"))
		self unsetPerk("specialty_bulletaccuracy");

	// Optional: show loss message.
	if (getDvarInt("ds_hud"))
		self iPrintLn("^1Deadshot+ ^7Lost");
}



// ============================================================
//  4) HEADSHOT BONUS LOOP — POINTS / HEAL / STREAK
// ============================================================

/*
    headshotBonusLoop()
    -------------------
    Waits for "headshot" events and applies rewards while Deadshot+ is active.

    Rewards:
    - Adds ds_hs_points to self.score
    - Heals ds_hs_heal HP (clamped to maxhealth; default fallback max is 100)
    - Tracks streak and total, then checks for milestone callouts

    Thread lifetime:
    - Ends on disconnect, death, or "ds_deactivate".
*/
headshotBonusLoop()
{
	self endon("disconnect");
	self endon("death");
	self endon("ds_deactivate");

	// Pull once per thread start (cheap). Change DVARs mid-game requires reacquire/deactivate.
	bonusPoints = getDvarInt("ds_hs_points");
	healAmount = getDvarInt("ds_hs_heal");

	for (;;)
	{
		// "headshot" is fired by the game/mod framework when a headshot kill event occurs.
		// Some frameworks pass the killed zombie as the 2nd param; we accept it either way.
		self waittill("headshot", zombie);

		// Extra safety: if something triggers this while inactive, ignore.
		if (!self.ds_active)
			continue;

		// Update streak counters.
		self.ds_hs_streak++;
		self.ds_hs_total++;

		// Bonus points: direct score modification.
		if (bonusPoints > 0)
			self.score += bonusPoints;

		// Heal: clamp to maxhealth (or 100 if maxhealth is not defined).
		if (healAmount > 0)
		{
			newHp = self.health + healAmount;

			maxHp = self.maxhealth;
			if (!isDefined(maxHp))
				maxHp = 100;

			if (newHp > maxHp)
				newHp = maxHp;

			self.health = newHp;
		}

		// Milestone callouts.
		self thread checkStreakMilestone(self.ds_hs_streak);
	}
}



// ============================================================
//  5) STREAK MILESTONES + NOTIFICATION HELPERS
// ============================================================

/*
    checkStreakMilestone(streak)
    ----------------------------
    Prints milestone messages at specific streak counts.
*/
checkStreakMilestone(streak)
{
	self endon("disconnect");

	// Respect HUD toggle.
	showHud = getDvarInt("ds_hud");
	if (!showHud)
		return;

	// Only react on the milestones we care about.
	if (streak != 5 && streak != 10 && streak != 25 && streak != 50 && streak != 100)
		return;

	switch (streak)
	{
	case 5:
		self iPrintLn("^5HS x5 ^7Sharpshooter");
		break;

	case 10:
		self iPrintLn("^5HS x10 ^7Marksman");
		break;

	case 25:
		self iPrintLn("^3HS x25 ^7Deadeye");
		break;

	case 50:
		self iPrintLn("^6HS x50 ^7Skull Collector");
		break;

	case 100:
		self iPrintLn("^1HS x100 ^7HEAD HUNTER");
		break;
	}
}

/*
    activateNotify()
    ----------------
    Small helper to print an activation notification.
*/
activateNotify()
{
	self endon("disconnect");

	self iPrintLn("^5Deadshot+ ^7Active");
}
