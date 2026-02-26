/* ===========================================================================================
    CUSTOM SELF-REVIVE (SYRETTE)  |  Black Ops II Zombies (Plutonium T6)
    Created by: Astroolean

    What this does
    - Adds a charge-based self-revive system.
    - When a lethal hit would down you, the script cancels that lethal damage, heals you instantly,
      plays a quick "syrette" animation, and grants a short invulnerability window.
    - Includes safeguards to prevent double-consumption, spam triggers, and stuck states.
    - Includes a simple HUD line showing remaining charges, plus a short "used" notification.

    Install / usage
    - Place this file in your mod's scripts folder and ensure its init() is executed for the map.
    - You can tune the behavior with DVARs (set these BEFORE starting the match):

        set sr_charges    "3"     // starting charges per player (clamped 0..99)
        set sr_invuln_ms  "700"   // invulnerability after revive, in ms (clamped 100..5000)

    Compatibility notes
    - Mob of the Dead: this file detects Afterlife and does not interfere with it.
    - This is a "damage-cancel" revive (it prevents the down by passing 0 damage to the engine).
      If another script, mod, or map logic is also manipulating downs/bleedout/game-over,
      timing conflicts can still happen. (If you ever see "revive starts but the match ends",
      the next step is to gate/block the death/game-over path the moment self-revive triggers.)

    File layout
    - Includes / init
    - Hooking the player damage callback
    - Player lifecycle (connect/spawn) + state reset
    - Self-revive core (damage handler + revive flow)
    - Timers / failsafes
    - HUD

   =========================================================================================== */

#include maps\mp\_utility;
#include common_scripts\utility;

/* ===========================================================================================
    INIT / SETUP
   =========================================================================================== */

init()
{
    // One-time init guard (prevents double-hooking if init() is called twice).
    if (isDefined(level.sr_init))
        return;

    level.sr_init = 1;

    // Default configuration if the server/admin didn't set these already.
    // (Keeping the setDvar calls here makes the mod "plug-and-play".)
    if (getDvar("sr_charges") == "")
        setDvar("sr_charges", "3");

    if (getDvar("sr_invuln_ms") == "")
        setDvar("sr_invuln_ms", "700");

    // Hook the engine player-damage callback when it becomes available.
    level thread sr_hook_damage();

    // Track connecting players and attach spawn logic.
    level thread sr_on_connect();
}

/* ===========================================================================================
    HOOK: LEVEL.CALLBACKPLAYERDAMAGE
    BO2 Zombies routes player damage through level.callbackplayerdamage.
    We replace it with our wrapper, and forward to the original callback whenever needed.
   =========================================================================================== */

sr_hook_damage()
{
    level endon("game_ended");

    for (;;)
    {
        // Wait until the game sets the callback pointer. (Different maps/scripts can set it later.)
        if (isDefined(level.callbackplayerdamage))
        {
            // Keep a reference to the original so we can call it safely.
            level.sr_orig_damage = level.callbackplayerdamage;

            // Replace with our wrapper function (sr_damage).
            level.callbackplayerdamage = ::sr_damage;

            return;
        }

        wait 0.05;
    }
}

/* ===========================================================================================
    PLAYER LIFECYCLE
   =========================================================================================== */

sr_on_connect()
{
    for (;;)
    {
        level waittill("connected", player);

        // Attach spawn handler to each connecting player.
        player thread sr_on_spawn();
    }
}

sr_on_spawn()
{
    self endon("disconnect");
    level endon("game_ended");

    for (;;)
    {
        self waittill("spawned_player");

        // One-time per-player initialization (HUD + charge count).
        if (!isDefined(self.sr_init_done))
        {
            self.sr_init_done = 1;

            // Read charges from DVAR and clamp to a safe range.
            self.sr_charges = getDvarInt("sr_charges");
            if (self.sr_charges < 0)  self.sr_charges = 0;
            if (self.sr_charges > 99) self.sr_charges = 99;

            // Build HUD elements once.
            self thread sr_hud_init();
        }

        // Reset per-life flags.
        self.sr_invuln     = 0;  // true while invulnerability window is active
        self.sr_busy       = 0;  // true while the syrette animation is playing
        self.sr_lock       = 0;  // hard lock to prevent re-entry / charge spam
        self.sr_triggering = 0;  // set during the exact lethal-hit revive trigger

        // "Prime gate" (first hit protection)
        // A charge can NEVER be used on the very first damage event after spawn.
        // This prevents the classic bug where the script consumes a charge instantly on the first hit.
        self.sr_armed = 0;

        // Update HUD immediately on each spawn.
        sr_hud_update_once();
    }
}

/* ===========================================================================================
    CORE: DAMAGE WRAPPER
    This function replaces level.callbackplayerdamage.
    It decides whether to:
      - forward damage normally,
      - ignore damage (invuln/lock),
      - or intercept a lethal hit and trigger the self-revive.
   =========================================================================================== */

sr_damage(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex)
{
    // If we somehow got called before we saved the original callback, do nothing.
    if (!isDefined(level.sr_orig_damage))
        return;

    // Mob of the Dead Afterlife: do not interfere at all.
    if (isDefined(self.afterlife) && self.afterlife)
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Hard block while reviving/injecting (prevents burning multiple charges during animations).
    if ((isDefined(self.sr_lock) && self.sr_lock) || (isDefined(self.sr_busy) && self.sr_busy))
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, 0, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Invulnerability window after revive: pass 0 damage.
    if (isDefined(self.sr_invuln) && self.sr_invuln)
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, 0, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Defensive checks: if anything looks off, forward damage normally.
    if (!isDefined(self) || !isDefined(iDamage) || iDamage <= 0 || !isDefined(self.sr_charges) || self.sr_charges <= 0 || !isDefined(self.health))
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Ensure flags always exist (avoids "undefined" checks later).
    if (!isDefined(self.sr_armed))
        self.sr_armed = 0;

    if (!isDefined(self.sr_triggering))
        self.sr_triggering = 0;

    // Skip falling damage (common edge-case where revive behavior can feel wrong).
    if (sMeansOfDeath == "MOD_FALLING")
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Non-lethal damage: arm the system for this life and forward normally.
    if ((self.health - iDamage) > 0)
    {
        self.sr_armed = 1;

        self [[level.sr_orig_damage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Lethal hit BEFORE arming: treat it like a normal hit and do not consume a charge.
    // This specifically fixes "syrette on first hit" behavior.
    if (!self.sr_armed)
    {
        self.sr_armed = 1;

        self [[level.sr_orig_damage]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // Re-entry guard: if we're already triggering a revive this frame, ignore extra damage.
    if (self.sr_triggering)
    {
        self [[level.sr_orig_damage]](eInflictor, eAttacker, 0, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);
        return;
    }

    // ===========================
    // LETHAL HIT -> TRIGGER REVIVE
    // ===========================

    self.sr_triggering = 1;

    // Lock immediately so hits during the effect can't burn extra charges.
    self.sr_lock   = 1;
    self.sr_invuln = 1;

    // Start/refresh invulnerability timer.
    self thread sr_invuln_timer();

    // Critical solo safety:
    // Heal immediately THIS FRAME, then forward 0 damage.
    // The goal is to prevent the engine from committing a solo down/game-over state first.
    if (isDefined(self.maxhealth) && self.maxhealth > 0)
        self.health = self.maxhealth;
    else
        self.health = 100;

    // Forward 0 damage so the lethal hit does not down the player.
    self [[level.sr_orig_damage]](eInflictor, eAttacker, 0, iDFlags, sMeansOfDeath, sWeapon, vPoint, vDir, sHitLoc, timeOffset, boneIndex);

    // Consume exactly one charge.
    self.sr_charges--;
    if (self.sr_charges < 0)
        self.sr_charges = 0;

    // HUD + flow continuation (kept threaded so we don't stall the damage callback).
    self thread sr_hud_notify_used();
    self thread sr_after_save();
}

/* ===========================================================================================
    POST-TRIGGER FLOW
    Runs right after the lethal-hit intercept.
    - waittillframeend lets the engine finish the current damage event cleanly.
    - then we re-assert health, play the syrette animation, and update HUD.
   =========================================================================================== */

sr_after_save()
{
    self endon("disconnect");
    level endon("game_ended");

    // Let the engine finish its bookkeeping for the damage event first.
    waittillframeend;

    // Re-assert health after frame end (belt-and-suspenders).
    if (isDefined(self.maxhealth) && self.maxhealth > 0)
        self.health = self.maxhealth;
    else
        self.health = 100;

    // If not already busy, play the injection animation sequence.
    if (!isDefined(self.sr_busy) || !self.sr_busy)
        self thread sr_syrette();

    // Absolute failsafe: unlock if anything gets stuck.
    self thread sr_lock_failsafe();

    // HUD should never lag behind the real charge count.
    sr_hud_update_once();
}

/* ===========================================================================================
    INVULNERABILITY TIMER
    Refreshable timer:
    - We notify("sr_invuln_end") to cancel any prior timer threads,
      then start a new window using the current DVAR.
   =========================================================================================== */

sr_invuln_timer()
{
    // Kill any previous invuln timer thread.
    self notify("sr_invuln_end");
    self endon("sr_invuln_end");

    self endon("disconnect");
    level endon("game_ended");

    self.sr_invuln = 1;

    ms = getDvarInt("sr_invuln_ms");
    if (ms < 100)  ms = 100;
    if (ms > 5000) ms = 5000;

    wait (ms / 1000.0);

    self.sr_invuln = 0;
}

/* ===========================================================================================
    SYRETTE ANIMATION SEQUENCE
    This is intentionally simple:
    - temporarily give the syrette weapon
    - switch to it, wait, then restore the previous weapon
    Notes:
    - The revive itself is NOT tied to this animation; the revive already happened by canceling
      lethal damage + instant heal. This is strictly visual/feedback.
   =========================================================================================== */

sr_syrette()
{
    self endon("disconnect");
    level endon("game_ended");

    // Already playing? Don't restart it.
    if (isDefined(self.sr_busy) && self.sr_busy)
        return;

    self.sr_busy = 1;
    self.sr_lock = 1;

    // If the engine thinks we're dead, abort cleanly and unlock.
    if (!isAlive(self))
    {
        self.sr_busy       = 0;
        self.sr_lock       = 0;
        self.sr_triggering = 0;
        return;
    }

    // Remember the current weapon so we can restore it.
    prev = self getCurrentWeapon();

    // Give + equip syrette.
    self giveWeapon("syrette_zm");
    waittillframeend;

    if (isAlive(self))
        self switchToWeapon("syrette_zm");

    // Let the syrette play long enough to be noticeable.
    wait 2;

    // Restore weapon state.
    if (isAlive(self))
    {
        self takeWeapon("syrette_zm");

        if (isDefined(prev) && prev != "" && prev != "none")
            self switchToWeapon(prev);
    }

    // Unlock and clear flags so we can trigger again later.
    self.sr_busy       = 0;
    self.sr_lock       = 0;
    self.sr_triggering = 0;

    // Require at least one normal hit again before another charge can be spent.
    self.sr_armed = 0;
}

/* ===========================================================================================
    FAILSAFE: NEVER LET LOCKS GET STUCK
    If something interrupts the syrette flow (disconnect, unusual engine state, etc),
    this thread ensures we clear any stuck flags after a short delay.
   =========================================================================================== */

sr_lock_failsafe()
{
    self endon("disconnect");
    level endon("game_ended");

    // Small delay that covers the whole injection sequence.
    wait 2.60;

    if (isDefined(self.sr_lock) && self.sr_lock)
        self.sr_lock = 0;

    if (isDefined(self.sr_busy) && self.sr_busy)
        self.sr_busy = 0;

    if (isDefined(self.sr_triggering) && self.sr_triggering)
        self.sr_triggering = 0;
}

/* ===========================================================================================
    HUD (BO2-compatible)
    - A main counter line (always visible in-game)
    - A short "used" popup line
   =========================================================================================== */

sr_hud_init()
{
    self endon("disconnect");
    level endon("game_ended");

    // Destroy existing elements if this is re-run for any reason.
    if (isDefined(self.sr_hud_main))
    {
        self.sr_hud_main destroy();
        self.sr_hud_main = undefined;
    }

    if (isDefined(self.sr_hud_note))
    {
        self.sr_hud_note destroy();
        self.sr_hud_note = undefined;
    }

    // Main counter line (top-center).
    self.sr_hud_main = NewClientHudElem(self);
    self.sr_hud_main.horzAlign     = "center";
    self.sr_hud_main.vertAlign     = "top";
    self.sr_hud_main.alignX        = "center";
    self.sr_hud_main.alignY        = "top";
    self.sr_hud_main.x             = 0;
    self.sr_hud_main.y             = 18;
    self.sr_hud_main.fontScale     = 1.55;
    self.sr_hud_main.archived      = 0;
    self.sr_hud_main.hidewheninmenu= 1;
    self.sr_hud_main.foreground    = 1;
    self.sr_hud_main.alpha         = 0.90;
    self.sr_hud_main.sort          = 1000;

    // Notification line (appears briefly after a charge is used).
    self.sr_hud_note = NewClientHudElem(self);
    self.sr_hud_note.horzAlign      = "center";
    self.sr_hud_note.vertAlign      = "top";
    self.sr_hud_note.alignX         = "center";
    self.sr_hud_note.alignY         = "top";
    self.sr_hud_note.x              = 0;
    self.sr_hud_note.y              = 42;
    self.sr_hud_note.fontScale      = 1.20;
    self.sr_hud_note.archived       = 0;
    self.sr_hud_note.hidewheninmenu = 1;
    self.sr_hud_note.foreground     = 1;
    self.sr_hud_note.alpha          = 0;
    self.sr_hud_note.sort           = 1000;

    // Initial HUD draw.
    sr_hud_update_once();
}

sr_hud_update_once()
{
    if (!isDefined(self.sr_hud_main))
        return;

    charges = 0;
    if (isDefined(self.sr_charges))
        charges = self.sr_charges;

    // Green when charges remain, red when empty.
    if (charges > 0)
        self.sr_hud_main setText("^7SELF REVIVES: ^2" + charges);
    else
        self.sr_hud_main setText("^7SELF REVIVES: ^1" + charges);
}

sr_hud_notify_used()
{
    if (!isDefined(self.sr_hud_note))
        return;

    charges = 0;
    if (isDefined(self.sr_charges))
        charges = self.sr_charges;

    // Update main counter immediately so it never lags behind.
    sr_hud_update_once();

    self.sr_hud_note setText("^2SELF REVIVE USED ^7| ^2" + charges + "^7 REMAINING");
    self.sr_hud_note fadeOverTime(0.12);
    self.sr_hud_note.alpha = 1;

    wait 1.25;

    self.sr_hud_note fadeOverTime(0.55);
    self.sr_hud_note.alpha = 0;
}
