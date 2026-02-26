// ╔══════════════════════════════════════════════════════════════════╗
// ║                        LAVA PROTECTION                           ║
// ║                    Black Ops II Zombies (T6)                     ║
// ║                       Plutonium Client Mod                       ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ Created by: Astroolean                                           ║
// ║ File:       custom_lava.gsc                                      ║
// ║ Purpose:    Prevents lava/fire damage + visuals on Transit maps  ║
// ║             (Town / Farm / Bus Depot / TranZit).                 ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ What this does (high level):                                     ║
// ║   This script uses a two-layer approach to keep lava from        ║
// ║   killing you or applying the annoying burn overlay/sounds.      ║
// ║                                                                  ║
// ║   Layer 1 — Preemptive:                                          ║
// ║     When you're low enough (origin Z below a max height) and     ║
// ║     grounded, we force the player's is_burning flag ON. On       ║
// ║     Transit maps, this prevents the engine's lava damage handler ║
// ║     (player_lava_damage) from firing in the first place.         ║
// ║                                                                  ║
// ║   Layer 2 — Reactive cleanup:                                    ║
// ║     If the engine still manages to set burn state (jumping into  ║
// ║     lava, height mismatches, edge cases), we:                    ║
// ║       - Restore small tick damage (typical lava tick size)       ║
// ║       - Strip burn FX/overlay/looping fire sound                 ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ Controls:                                                        ║
// ║   Toggle ON/OFF: D-pad Right  ( +actionslot 4 )                  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ Configuration (DVARs):                                           ║
// ║   lava_protection   0/1   (default: 1)                           ║
// ║     1 = protection enabled, 0 = disabled                         ║
// ║                                                                  ║
// ║   lava_max_height   float (default: 50)                          ║
// ║     Any player with origin[2] < lava_max_height AND grounded     ║
// ║     gets flagged as burning (preemptive layer).                  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║ Notes / Safety:                                                  ║
// ║   - Map-gated: only runs when mapname == "zm_transit"            ║
// ║   - Code behavior is unchanged; this file is just organized and  ║
// ║     heavily documented for long-term maintenance.                ║
// ║   - Damage restore is intentionally conservative (small ticks).  ║
// ╚══════════════════════════════════════════════════════════════════╝

#include common_scripts\utility;
#include maps\mp\_utility;

// ==================================================================
// SCRIPT ENTRYPOINT
// ==================================================================

// ------------------------------------------------------------------
// init()
//
// Engine entrypoint. This runs once when the script loads.
// We do three things here:
//   1) Hard-gate to Transit family maps (mapname == "zm_transit")
//   2) Apply default DVAR values if the user hasn't set them
//   3) Start the player connect loop that attaches per-player threads
// ------------------------------------------------------------------
init()
{
    // Only run on Transit-family maps (Town/Farm/Bus Depot/TranZit)
    if (getDvar("mapname") != "zm_transit")
        return;

    // Default enabled unless user explicitly sets lava_protection
    if (getDvar("lava_protection") == "")
        setDvar("lava_protection", "1");

    // Default height gate (tweak if your map/build uses different Z)
    if (getDvar("lava_max_height") == "")
        setDvar("lava_max_height", "50");

    // Start the connection watcher (attaches per-player threads)
    level thread onPlayerConnect();
}


// ------------------------------------------------------------------
// onPlayerConnect()
//
// Infinite loop that waits for each player to start connecting,
// then attaches the protection monitor + toggle listener.
//
// NOTE:
//   Using "connecting" makes sure threads are attached as early as
//   possible in the connection flow (this file is already working
//   with your setup, so we keep it as-is).
// ------------------------------------------------------------------
onPlayerConnect()
{
    for (;;)
    {
        // Grab the player entity as they connect, then attach threads
        level waittill("connecting", player);
        // Main protection loop (damage/FX prevention)
        player thread lavaProtectionMonitor();
        // Toggle listener (D-pad Right)
        player thread lavaProtectionToggle();
    }
}


// ------------------------------------------------------------------
// lavaProtectionMonitor()
//
// Per-player protection loop.
// Runs frequently (every 0.05 seconds) and does:
//   A) Preemptive flagging (Layer 1)
//   B) Reactive health restore + FX cleanup (Layer 2)
//
// This thread is safe to leave running forever; it ends on disconnect.
// ------------------------------------------------------------------
lavaProtectionMonitor()
{
    // Always cleanly stop when the player leaves
    self endon("disconnect");

    // Baseline used to detect tiny lava tick damage
    lastHealth = self.health;

    for (;;)
    {
        // 20Hz loop: fast enough to catch lava ticks without being heavy
        wait 0.05;

        // If disabled, just keep the baseline synced and do nothing
        if (getDvar("lava_protection") != "1")
        {
            // Keep baseline synced so tick math stays sane when re-enabled
            lastHealth = self.health;
            continue;
        }

        // -----------------------------
        // Layer 1 (Preemptive)
        // -----------------------------
        // If the player is below the configured height AND grounded,
        // force is_burning ON. On Transit maps, this blocks the
        // engine lava handler from starting (no overlay/FX/sound).
        maxZ = getDvarFloat("lava_max_height");
        if (self.origin[2] < maxZ && self IsOnGround())
            self.is_burning = 1;

        // Track small "tick" damage between frames
        currentHealth = self.health;
        damageTaken = lastHealth - currentHealth;

        // -----------------------------
        // Layer 2 (Reactive)
        // -----------------------------
        // If burn state is active for any reason, undo the usual lava
        // tick damage and strip any visuals/audio that slipped through.
        if (isDefined(self.is_burning) && self.is_burning)
        {
            // Only undo small ticks (typical lava damage). We keep
            // this conservative on purpose so we do not hide other
            // legitimate damage sources.
            if (damageTaken > 0 && damageTaken <= 30)
                self.health = lastHealth;

            // Cleanup is done once per burn-state window.
            if (!isDefined(self._lp_cleaned))
            {
                self cleanBurnEffects();
                self._lp_cleaned = true;
            }
        }
        else
        {
            // When not burning, allow cleanup to run again next time
            self._lp_cleaned = undefined;
        }

        lastHealth = self.health;
    }
}


// ------------------------------------------------------------------
// cleanBurnEffects()
//
// Strips burn visuals/audio that the engine may have applied.
// This is called once per "burn state" to avoid spamming cleanup.
// ------------------------------------------------------------------
cleanBurnEffects()
{
    // Removes the burn/heat overlay effect if present
    self stopShellshock();

    // If the engine set the fire flag, clear it and stop any loop audio
    if (isDefined(self.is_on_fire) && self.is_on_fire)
    {
        self.is_on_fire = undefined;
        // Stops any flame-damage logic still running on the player
        self notify("stop_flame_damage");
        // Stops the looping burn sound
        self stopLoopSound();
    }
}


// ------------------------------------------------------------------
// lavaProtectionToggle()
//
// Binds D-pad Right (actionslot 4) to toggle the protection DVAR.
// This is per-player (so everyone can flip it), but it writes to a
// global DVAR, so the state is shared for the match.
// ------------------------------------------------------------------
lavaProtectionToggle()
{
    // Stop cleanly when the player disconnects
    self endon("disconnect");

    // Bind D-pad Right (actionslot 4) -> "toggle_lava_prot" notify
    self notifyOnPlayerCommand("toggle_lava_prot", "+actionslot 4");

    for (;;)
    {
        // Wait for the bound keypress
        self waittill("toggle_lava_prot");

        // Flip the global DVAR and print current state
        current = getDvarInt("lava_protection");
        if (current)
        {
            setDvar("lava_protection", "0");
            self iprintln("Lava Protection: ^1OFF");
        }
        else
        {
            setDvar("lava_protection", "1");
            self iprintln("Lava Protection: ^2ON");
        }
    }
}
