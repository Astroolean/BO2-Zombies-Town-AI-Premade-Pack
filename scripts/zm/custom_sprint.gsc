// =================================================================================================
// File:    custom_sprint.gsc
// Purpose: Handles player connection, spawning, and initial ability/perk application for Zombies.
// Note:    This is a conceptual adaptation. Specific Cold War function names and ability IDs may vary.
// =================================================================================================

// Main initialization function for the script.
// This function is typically called once when the map loads.
init()
{
    // Start a persistent thread to listen for new player connections.
    // 'level thread' ensures this thread runs globally for the entire game level.
    level thread onPlayerConnect();

    // You might add other global setup or event listeners here for the level.
    // For example, setting up game rules, custom objectives, or UI elements.
    // level thread onGameStart();
}

// Function to handle player connection events.
// This function runs in a loop, waiting for players to join.
onPlayerConnect()
{
    // The 'for(;;)' loop makes this a continuous listener.
    for(;;)
    {
        // Wait until a player connects.
        // The connected player entity is passed as an argument 'player'.
        level waittill("connected", player);

        // Once a player connects, start a dedicated thread for that player.
        // This ensures each player's events are handled independently.
        player thread onPlayerJoined();
    }
}

// Function to handle events specific to a player after they have joined the game.
// This function runs on the 'player' entity.
onPlayerJoined()
{
    // Ensure this player's thread terminates if the game ends or if the player disconnects.
    level endon("end_game");
    self endon("disconnect"); // Common event triggered when player leaves the game

    // Initialize a flag to prevent applying unlimited sprint multiple times if spawned_player
    // is triggered without a full disconnect/reconnect cycle.
    self.has_unlimited_sprint_ability = false;

    // Continuously listen for player-specific events, like spawning.
    for(;;)
    {
        // Wait until the player spawns into the game.
        // "spawned_player" is a common event, but verify Cold War's specific spawn event.
        self waittill("spawned_player");

        // Apply initial abilities and setup if not already done for this spawn cycle.
        if ( !self.has_unlimited_sprint_ability )
        {
            // Call a custom function to grant the unlimited sprint ability.
            // This encapsulates the specific logic for Cold War's sprint system.
            self _custom_give_player_unlimited_sprint();

            // Set the flag to true so it's not applied again on subsequent 'spawned_player' events
            // until the player disconnects and reconnects.
            self.has_unlimited_sprint_ability = true;
        }

        // Add other initial setup for the player after spawning here:
        // Example: Giving an initial weapon (ensure weapon names are Cold War compatible)
        // self giveWeapon("t8_weapon_pistol_colt", 0); // Placeholder weapon name
        // Example: Setting initial ammo for all weapons
        // self setPlayerAmmoCount("all", 99999);
        // Example: Setting initial points
        // self addPlayerScore(500); // Give initial score
    }
}

// =================================================================================================
// Custom Function: _custom_give_player_unlimited_sprint
// Purpose: Applies the unlimited sprint ability to the player.
// Note: This is a conceptual implementation. Actual Cold War functions may vary.
// =================================================================================================
_custom_give_player_unlimited_sprint()
{
    // In Cold War, unlimited sprint might be handled by:
    // 1. A specific perk.
    // 2. A field upgrade or operator skill.
    // 3. A direct player flag/modifier.

    // Using 'setperk' as a conceptual placeholder based on the original request.
    // You'd need to find the Cold War equivalent for actual implementation.
    self setperk("specialty_unlimitedsprint"); // Placeholder: Use actual CW perk/ability ID

    // Optional: Notify the player that unlimited sprint has been granted.
    // This uses the client-side text overlay.
    self iprintlnbold("Unlimited Sprint Activated!");

    // Another way to handle unlimited sprint in a custom way could involve:
    // looping a function that constantly resets stamina or sets a high stamina value,
    // or by overriding default sprint behavior via specific GSC functions.
    // Example (conceptual, requires finding correct CW functions):
    // self setStaminaEnabled(false); // Disable stamina drain
    // self setSprintSpeedMultiplier(1.0); // Ensure normal sprint speed
}

// =================================================================================================
// Example of how to trigger 'end_game' (e.g., when the game over condition is met)
// =================================================================================================
/*
// This would be in another part of your script that determines game state.
onGameOver()
{
    // ... game over logic ...
    level notify("end_game"); // Notifies all threads waiting on "end_game" to terminate.
}
*/

// =================================================================================================
// Note on Cold War Ability System:
// Cold War's system for player abilities and perks is more nuanced than BO2's.
// 'specialty_unlimitedsprint' is from older titles. For Cold War, you'd investigate
// functions related to player abilities, field upgrades, or specific perk granting
// mechanisms to achieve unlimited sprint, which might even be a default setting
// in some custom game modes.
// =================================================================================================
