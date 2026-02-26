#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_perks;

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║                     CUSTOM SPEED COLA+ v2.0                              ║
// ║                    Black Ops II Zombies (Plutonium T6)                   ║
// ║                                                                          ║
// ║  Created by: Astroolean                                                  ║
// ║                                                                          ║
// ║  What this script does                                                   ║
// ║    - When the player has Speed Cola (specialty_fastreload), this script  ║
// ║      automatically grants extra weapon-handling perks:                   ║
// ║        • Fast ADS (specialty_fastads)                                    ║
// ║        • Fast Weapon Swap (specialty_fastweaponswitch)                   ║
// ║        • Fast Equipment Use (specialty_fastequipmentuse)                 ║
// ║        • Fast Melee Recovery (specialty_fastmeleerecovery)               ║
// ║      plus an optional movement speed multiplier.                         ║
// ║                                                                          ║
// ║    - When Speed Cola is lost (perk loss / down / death), it cleanly      ║
// ║      removes those bonuses and resets movement speed back to normal.     ║
// ║                                                                          ║
// ║  Configuration (DVARs)                                                   ║
// ║    sc_move_boost   1.08   Movement speed multiplier while active         ║
// ║    sc_hud          1      Activation text (0 = off, 1 = on)              ║
// ║                                                                          ║
// ║  Performance / safety notes                                              ║
// ║    - Event-driven: uses perk_acquired / perk_lost events (no polling).   ║
// ║    - Does not force perks: only reacts to Speed Cola being present.      ║
// ║    - Defensive: checks "hasPerk" before setting/unsetting.               ║
// ╚══════════════════════════════════════════════════════════════════════════╝

// --------------------------------------------------------------------------
// init()
//
// Bootstraps the script:
//   - Ensures default DVARs exist (movement boost + HUD toggle).
//   - Starts the global player connection listener.
// --------------------------------------------------------------------------
init()
{
        if (getDvar("sc_move_boost") == "")
                setDvar("sc_move_boost", "1.08");
        if (getDvar("sc_hud") == "")
                setDvar("sc_hud", "1");
        level thread onPlayerConnect();
}

// --------------------------------------------------------------------------
// onPlayerConnect()
//
// Runs forever on the level thread.
// Every time a player connects, we start per-player spawn handling.
// --------------------------------------------------------------------------
onPlayerConnect()
{
        for (;;)
        {
                level waittill("connected", player);
                player thread onPlayerSpawned();
        }
}

// --------------------------------------------------------------------------
// onPlayerSpawned()
//
// Runs for each connected player.
// On every spawn:
//   - Resets our internal active flag.
//   - Starts the perk event monitor (event-driven).
//   - Starts a death watcher to ensure cleanup if the player dies.
// --------------------------------------------------------------------------
onPlayerSpawned()
{
        self endon("disconnect");

        for (;;)
        {
                self waittill("spawned_player");
                self.sc_active = false;
                self thread monitorSpeedCola();
                self thread watchDeath();
        }
}


// ============================================================
//  CORE ENGINE — EVENT-DRIVEN PERK MONITOR
// ============================================================

// --------------------------------------------------------------------------
// monitorSpeedCola()
//
// Event-driven perk monitor.
// Waits for either:
//   - "perk_acquired"
//   - "perk_lost"
// Then checks if the player currently has Speed Cola (specialty_fastreload).
// If the state changed, it toggles the Speed Cola+ bonuses accordingly.
// --------------------------------------------------------------------------
monitorSpeedCola()
{
        self endon("disconnect");
        self endon("death");

        for (;;)
        {
                self waittill_any("perk_acquired", "perk_lost");

                // We only wake up when the engine tells us a perk changed;
                // then we compare current Speed Cola state vs our cached flag.

                hasCola = self hasPerk("specialty_fastreload");
                // Speed Cola perk internal name is specialty_fastreload.

                if (hasCola && !self.sc_active)
                {
                        self thread activateSpeedPlus();
                }
                else if (!hasCola && self.sc_active)
                {
                        self thread deactivateSpeedPlus();
                }
        }
}

// --------------------------------------------------------------------------
// watchDeath()
//
// Safety cleanup.
// If the player dies while Speed Cola+ is active, we remove all bonuses
// so nothing leaks into the next life or persists incorrectly.
// --------------------------------------------------------------------------
watchDeath()
{
        self endon("disconnect");

        self waittill("death");

        if (self.sc_active)
                self thread deactivateSpeedPlus();
}


// ============================================================
//  ACTIVATION — GRANT ALL BONUS PERKS
// ============================================================

// --------------------------------------------------------------------------
// activateSpeedPlus()
//
// Applies Speed Cola+ bonuses when Speed Cola is present.
// Important behaviors:
//   - Does NOT grant Speed Cola itself; it only reacts to it.
//   - Only sets bonus perks if missing (avoids reapplying/overwriting).
//   - Applies movement speed scale ONLY if sc_move_boost > 1.0.
//   - Optional HUD notification controlled by sc_hud (0/1).
// --------------------------------------------------------------------------
activateSpeedPlus()
{
        self endon("disconnect");

        self.sc_active = true;

        // Internal state flag so we do not double-apply or double-remove bonuses.

        if (!self hasPerk("specialty_fastads"))
                self setPerk("specialty_fastads");

        if (!self hasPerk("specialty_fastweaponswitch"))
                self setPerk("specialty_fastweaponswitch");

        if (!self hasPerk("specialty_fastequipmentuse"))
                self setPerk("specialty_fastequipmentuse");

        if (!self hasPerk("specialty_fastmeleerecovery"))
                self setPerk("specialty_fastmeleerecovery");

        moveBoost = getDvarFloat("sc_move_boost");
        // Optional movement boost while active. Keep it subtle to avoid feeling "floaty".
        if (moveBoost > 1.0)
                self setMoveSpeedScale(moveBoost);

        if (getDvarInt("sc_hud"))
                self thread activateNotify();
}


// ============================================================
//  DEACTIVATION — CLEAN REMOVAL OF ALL BONUSES
// ============================================================

// --------------------------------------------------------------------------
// deactivateSpeedPlus()
//
// Removes Speed Cola+ bonuses when Speed Cola is lost.
//   - Unsets bonus perks if present.
//   - Always resets movement speed scale back to 1.0.
//   - Optional HUD notification controlled by sc_hud (0/1).
// --------------------------------------------------------------------------
deactivateSpeedPlus()
{
        self endon("disconnect");

        self.sc_active = false;

        if (self hasPerk("specialty_fastads"))
                self unsetPerk("specialty_fastads");

        if (self hasPerk("specialty_fastweaponswitch"))
                self unsetPerk("specialty_fastweaponswitch");

        if (self hasPerk("specialty_fastequipmentuse"))
                self unsetPerk("specialty_fastequipmentuse");

        if (self hasPerk("specialty_fastmeleerecovery"))
                self unsetPerk("specialty_fastmeleerecovery");

        self setMoveSpeedScale(1.0);
        // Always hard-reset speed scale so no multiplier persists after perk loss.

        if (getDvarInt("sc_hud"))
                self thread deactivateNotify();
}


// ============================================================
//  COMPLETE HUD NOTIFICATIONS
// ============================================================

// --------------------------------------------------------------------------
// activateNotify()
//
// Simple HUD text when Speed Cola+ turns on (sc_hud must be enabled).
// --------------------------------------------------------------------------
activateNotify()
{
        self endon("disconnect");

        self iPrintLn("^5Speed Cola+ ^7Active");
        // Text-only notice; safe, fast, and doesn't depend on custom HUD assets.
}

// --------------------------------------------------------------------------
// deactivateNotify()
//
// Simple HUD text when Speed Cola+ turns off (sc_hud must be enabled).
// --------------------------------------------------------------------------
deactivateNotify()
{
        self endon("disconnect");

        self iPrintLn("^1Speed Cola+ ^7Lost");
        // Shown when bonuses are removed (perk lost, downed, death, etc.).
}
