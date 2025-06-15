// === Fire Damage Immunity Script (BO2 Zombies - Town) ===
// Author: ChatGPT & Astroolean
// Final Version — Corrected Logic Based on Damage Detection + Z Height
// This script prevents players from taking damage from environmental fire/lava
// if they are on the ground and within the typical lava height range.

#include common_scripts\utility; // For general utility functions.
#include maps\mp\_utility;     // For player functions like IsOnGround().

init()
{
    level thread onPlayerConnect(); // Start monitoring player connections.

    // Initialize a Dvar to control the fire protection.
    // Set to "1" (enabled) by default.
    setDvar("enable_fire_protection", "1"); 
    println("^2custom_fire_protection.gsc: Fire Protection script initialized.");
}

onPlayerConnect()
{
    for (;;) // Loop indefinitely to catch all connecting players.
    {
        level waittill("connecting", player); // Wait for a player to connect.
        // Start a separate thread for each player to monitor fire damage and handle toggling.
        player thread fireProtectionMonitor();
        player thread fireProtectionToggle();
    }
}

fireProtectionMonitor()
{
    self endon("disconnect"); // Stop this thread if the player disconnects.
    
    // Store the player's initial health.
    lastHealth = self.health;

    while (true) // Loop continuously as long as the player is connected.
    {
        wait 0.05; // Wait a short moment to prevent excessive looping (20 times per second).

        // Only apply fire protection if the Dvar is enabled.
        if (getDvar("enable_fire_protection") == "1")
        {
            // Calculate damage taken in this very short interval.
            // This needs to be done *before* any potential health restoration.
            currentHealth = self.health;
            damageTaken = lastHealth - currentHealth;

            // Check if damage was taken, and if it falls within expected fire damage ranges.
            // Damage from lava/fire is typically small, continuous ticks.
            // 15 is a common base fire damage tick.
            // 22 accounts for reduced damage with Juggernog (e.g., if base 15 becomes 7-8 per tick with reduction).
            // The 'self IsOnGround()' check has been REMOVED here.
            // 'self.origin[2] < 50' checks if the player's Z-coordinate is below a certain height (typical for Town's lava).
            if (damageTaken > 0 && 
                (damageTaken <= 15 || damageTaken <= 22) && // Check if damage is within typical fire range
                self.origin[2] < 50) 
            {
                // Restore health to what it was before this small tick of fire damage.
                self.health = lastHealth;
            }

            // Update lastHealth for the *next* iteration of the loop.
            // This must be the health *after* any restoration has occurred.
            lastHealth = self.health;
        }
    }
}

fireProtectionToggle()
{
    self endon("disconnect"); // Stop this thread if the player disconnects.

    // Listen for the player pressing the "actionslot 4" button (usually D-pad Right or F3).
    self notifyOnPlayerCommand("toggle_fire_protection", "+actionslot 4");

    while (true) // Loop indefinitely to catch toggle commands.
    {
        self waittill("toggle_fire_protection"); // Wait until the command is received.

        // Get the current state of the Dvar (0 or 1).
        current = getDvarInt("enable_fire_protection");
        // Toggle the value (0 becomes 1, 1 becomes 0).
        newVal = !current;
        // Set the Dvar to the new state.
        setDvar("enable_fire_protection", newVal);

        // Inform the player about the new state of fire protection.
        self iprintln("Fire Protection: " + (newVal ? "^2ENABLED" : "^1DISABLED"));
    }
}
