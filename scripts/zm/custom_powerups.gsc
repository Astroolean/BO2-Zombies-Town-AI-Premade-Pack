//Decompiled with love
#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_powerups;

// Entry point for the script. Initializes the powerups and sets up player connection handling.
init()
{
    // Start a thread to listen for new player connections.
    level thread onplayerconnect();

    // Unlimited Ammo Powerup
    include_zombie_powerup( "unlimited_ammo" );
    level.unlimited_ammo_duration = 60;
    add_zombie_powerup( "unlimited_ammo", "zombie_teddybear", &"ZOMBIE_POWERUP_UNLIMITED_AMMO", ::func_should_always_drop, 0, 0, 0 );
    powerup_set_can_pick_up_in_last_stand( "unlimited_ammo", 1 );

    // Blood Money Powerup
    include_zombie_powerup( "blood_money" );
    level.blood_money_duration = 60;
    add_zombie_powerup( "blood_money", "zombie_teddybear", &"ZOMBIE_POWERUP_BLOOD_MONEY", ::func_should_always_drop, 0, 0, 0 );
    powerup_set_can_pick_up_in_last_stand( "blood_money", 1 ); // Corrected: Removed extra "in"

    // Fire Sale Powerup
    include_zombie_powerup( "fire_sale" );
    level.fire_sale_duration = 60;
    add_zombie_powerup( "fire_sale", "zombie_teddybear", &"ZOMBIE_POWERUP_FIRE_SALE", ::func_should_always_drop, 0, 0, 0 );
    powerup_set_can_pick_up_in_last_stand( "fire_sale", 1 );

    // --- NEW POWERUP: Round Skip ---
    include_zombie_powerup( "round_skip" );
    // Round Skip doesn't have a duration, as it's an instant effect.
    add_zombie_powerup( "round_skip", "zombie_teddybear", &"ZOMBIE_POWERUP_ROUND_SKIP", ::func_should_always_drop, 0, 0, 0 );
    powerup_set_can_pick_up_in_last_stand( "round_skip", 1 );

    // --- NEW POWERUP: Pay Taxes ---
    include_zombie_powerup( "pay_taxes" );
    // Pay Taxes doesn't have a duration, as it's an instant effect.
    add_zombie_powerup( "pay_taxes", "zombie_teddybear", &"ZOMBIE_POWERUP_PAY_TAXES", ::func_should_always_drop, 0, 0, 0 );
    powerup_set_can_pick_up_in_last_stand( "pay_taxes", 1 );
}

// Thread that continuously listens for players connecting to the game.
onplayerconnect()
{
    for(;;) // Infinite loop
    {
        // Wait until a player connects.
        level waittill( "connected", player );
        // When a player connects, start a new thread for that player to handle their spawning.
        player thread onplayerspawned();
    }
}

// Thread for each player, activated upon connection, to handle their spawn events.
onplayerspawned()
{
    // End this thread if the player disconnects.
    self endon( "disconnect" );
    // End this thread if the game ends.
    level endon( "game_ended" );

    for(;;) // Infinite loop
    {
        // Wait until the player spawns.
        self waittill( "spawned_player" );

        // This block ensures that the custom powerup grab function is only set once per game.
        // It checks if 'level.custom_powerup_first_spawn' is NOT defined.
        if( !(IsDefined( level.custom_powerup_first_spawn )) )
        {
            wait 2; // Small delay.

            // If the original powerup grab function is defined, store it.
            if( IsDefined( level._zombiemode_powerup_grab ) )
            {
                level.original_zombiemode_powerup_grab = level._zombiemode_powerup_grab;
            }
            // Override the default powerup grab function with our custom one.
            level._zombiemode_powerup_grab = ::custom_powerup_grab;

            wait 2; // Another small delay.

            // Inform the player that the custom powerup is loaded.
            self iprintlnbold( "^7Custom Powerups Loaded!" );
            // Start a thread to allow the player to test the powerup.
            //self thread test_the_powerup();
            // Set a flag to indicate that the first spawn initialization has occurred.
            level.custom_powerup_first_spawn = "init_complete";
        }
    }
}

// Allows the player to test dropping the Blood Money powerup for a limited time.
// This is set to Blood Money as per your last provided code.
//test_the_powerup()
//{
//    self endon( "death" ); // End if the player dies.
//    self endon( "disconnected" ); // End if the player disconnects.
//    self endon( "testing_chance_ended" ); // End when the testing duration times out.
//    level endon( "game_ended" ); // End if the game ends.

//    wait 3; // Initial delay.

    // Instruct the player on how to test the powerup.
//    self iprintlnbold( "^7Press ^1[{+smoke}] ^7to test the Blood Money powerup, you have ^160 seconds^7." );
    // Start a timer for the testing duration.
//    self thread testing_duration_timeout();

//    for(;;) // Infinite loop for input detection.
//    {
        // Check if the player presses the secondary offhand button (usually grenade/smoke).
//        if( self secondaryoffhandbuttonpressed() )
//        {
            // Drop the "blood_money" powerup in front of the player.
//            level specific_powerup_drop( "round_skip", self.origin + ( anglestoforward( self.angles ) * 70 ) );
//        }
//        wait 0.05; // Small delay to prevent excessive loop iterations.
//    }
//}

// Timer for the testing phase of the powerup.
//testing_duration_timeout()
//{
//    self endon( "death" ); // End if the player dies.
//    self endon( "disconnected" ); // End if the player disconnects.

//    wait 60; // Wait for 60 seconds.
    // Notify to end the testing chance.
//    self notify( "testing_chance_ended" );
//}

// Custom function to handle powerup grabs, overriding the default behavior.
// s_powerup: The powerup entity that was grabbed.
// e_player: The player who grabbed the powerup.
custom_powerup_grab( s_powerup, e_player )
{
    // Check if the grabbed powerup is "unlimited_ammo".
    if( s_powerup.powerup_name == "unlimited_ammo" )
    {
        // If it is, activate the unlimited ammo powerup effect.
        level thread unlimited_ammo_powerup();
    }
    // Check if the grabbed powerup is "blood_money".
    else if( s_powerup.powerup_name == "blood_money" )
    {
        // If it is, activate the blood money powerup effect.
        level thread blood_money_powerup();
    }
    // Fire Sale Powerup Grab Handling
    else if( s_powerup.powerup_name == "fire_sale" )
    {
        level thread fire_sale_powerup();
    }
    // --- NEW: Round Skip Powerup Grab Handling ---
    else if( s_powerup.powerup_name == "round_skip" )
    {
        level thread round_skip_powerup();
    }
    // --- NEW: Pay Taxes Powerup Grab Handling ---
    else if( s_powerup.powerup_name == "pay_taxes" )
    {
        level thread pay_taxes_powerup();
    }
    else
    {
        // If it's not our custom powerup, and the original powerup grab function was stored,
        // call the original function to handle other powerups.
        if( IsDefined( level.original_zombiemode_powerup_grab ) )
        {
            level thread [[ level.original_zombiemode_powerup_grab ]]( s_powerup, e_player );
        }
    }
}

// Activates the unlimited ammo effect for all players.
unlimited_ammo_powerup()
{
    // Notify all players to end any existing unlimited ammo effects (to reset or restart the timer).
    foreach( player in level.players )
    {
        player notify( "end_unlimited_ammo" );
    }

    // Play the announcer sound globally for Unlimited Ammo, just once.
    level playsound( "vox_zm_powerup_insta_kill" ); // Global announcer voice for Insta-Kill (assuming this is the correct global alias)

    // Now, loop through players to apply their individual effects and sounds.
    foreach( player in level.players )
    {
        player playsound( "zmb_insta_kill" ); // Player-specific sound for Insta-Kill (from your notify_unlimited_ammo_end function)
        player thread turn_on_unlimited_ammo(); // Start the actual unlimited ammo effect.
        player thread unlimited_ammo_on_hud(); // Display the unlimited ammo status on HUD.
        player thread notify_unlimited_ammo_end(); // Set a timer to end the effect.
    }
}

// Manages the "Unlimited Ammo!" HUD string.
unlimited_ammo_on_hud()
{
    self endon( "disconnect" ); // End if the player disconnects.

    // Create a new client-side HUD element for the text.
    unlimited_ammo_hud_string = newclienthudelem( self );
    unlimited_ammo_hud_string.elemtype = "font";
    unlimited_ammo_hud_string.font = "objective";
    unlimited_ammo_hud_string.fontscale = 2;
    unlimited_ammo_hud_string.x = 0;
    unlimited_ammo_hud_string.y = 0;
    unlimited_ammo_hud_string.width = 0;
    unlimited_ammo_hud_string.height = int( level.fontheight * 2 );
    unlimited_ammo_hud_string.xoffset = 0;
    unlimited_ammo_hud_string.yoffset = 0;
    unlimited_ammo_hud_string.children = []; // Initialize children array (if any child elements are attached later).
    unlimited_ammo_hud_string setparent( level.uiparent ); // Set parent to the main UI parent.
    unlimited_ammo_hud_string.hidden = 0; // Make it visible.
    // Position the HUD element.
    unlimited_ammo_hud_string setpoint( "TOP", undefined, 0, level.zombie_vars[ "zombie_timer_offset"] - level.zombie_vars[ "zombie_timer_offset_interval"] * 2 );
    unlimited_ammo_hud_string.sort = 0.5; // Z-order for drawing.
    unlimited_ammo_hud_string.alpha = 0; // Start invisible for fading in.

    unlimited_ammo_hud_string fadeovertime( 0.5 ); // Fade in over 0.5 seconds.
    unlimited_ammo_hud_string.alpha = 1; // Set target alpha to fully visible.
    unlimited_ammo_hud_string settext( "Unlimited Ammo!" ); // Set the text.
    unlimited_ammo_hud_string thread unlimited_ammo_hud_string_move(); // Start thread to move/destroy the string.

    // Create a new client-side HUD element for the icon.
    unlimited_ammo_hud_icon = newclienthudelem( self );
    unlimited_ammo_hud_icon.horzalign = "center";
    unlimited_ammo_hud_icon.vertalign = "bottom";
    unlimited_ammo_hud_icon.x = -75;
    unlimited_ammo_hud_icon.y = 0;
    unlimited_ammo_hud_icon.alpha = 1; // Start fully visible.
    unlimited_ammo_hud_icon.hidewheninmenu = 1; // Hide when in menu.
    unlimited_ammo_hud_icon setshader( "hud_icon_minigun", 40, 40 );

    self thread unlimited_ammo_hud_icon_blink( unlimited_ammo_hud_icon ); // Start thread to make the icon blink.
    self thread destroy_unlimited_ammo_icon_hud( unlimited_ammo_hud_icon ); // Start thread to destroy the icon.
}

// Animates the "Unlimited Ammo!" HUD string by moving and fading it.
unlimited_ammo_hud_string_move()
{
    wait 0.5; // Initial delay.
    self fadeovertime( 1.5 ); // Start fading out.
    self moveovertime( 1.5 ); // Start moving.
    self.y = 270; // Move to y-coordinate 270.
    self.alpha = 0; // Fade to fully transparent.
    wait 1.5; // Wait for the animation to complete.
    self destroy(); // Destroy the HUD element.
}

// Makes the unlimited ammo HUD icon blink based on remaining time.
unlimited_ammo_hud_icon_blink( elem )
{
    level endon( "disconnect" ); // End if the level disconnects (game ends).
    self endon( "disconnect" ); // End if the player disconnects.
    self endon( "end_unlimited_ammo" ); // End if the unlimited ammo effect ends.

    time_left = level.unlimited_ammo_duration; // Initialize time remaining.
    for(;;) // Infinite loop for blinking.
    {
        // Determine blink speed based on time remaining.
        time = 0.5; // Default blink speed.
        if( time_left <= 5 )
        {
            time = 0.1; // Faster blink for the last 5 seconds.
        }
        else if( time_left <= 10 )
        {
            time = 0.2; // Medium blink speed for 5-10 seconds remaining.
        }

        // Blinking animation: fade out, wait, fade in, wait.
        elem fadeovertime( time );
        elem.alpha = 0;
        wait time;
        elem fadeovertime( time );
        elem.alpha = 1;
        wait time;

        // Update remaining time by subtracting two 'time' intervals (for fade out and fade in).
        time_left = time_left - (time * 2);

        if (time_left <= 0) {
            break;
        }
    }
}

// Destroys the unlimited ammo HUD icon after the duration or on specific events.
destroy_unlimited_ammo_icon_hud( elem )
{
    level endon( "game_ended" ); // End if the game ends.
    // Wait until the powerup duration passes or player disconnects/effect ends.
    self waittill_any_timeout( level.unlimited_ammo_duration + 1, "disconnect", "end_unlimited_ammo" );
    elem destroy(); // Destroy the HUD element.
}

// Grants the player "unlimited ammo" by constantly replenishing their current weapon's clip.
turn_on_unlimited_ammo()
{
    level endon( "game_ended" ); // End if the game ends.
    self endon( "disconnect" ); // End if the player disconnects.
    self endon( "end_unlimited_ammo" ); // End if the unlimited ammo effect is manually ended.

    for(;;) // Infinite loop while unlimited ammo is active.
    {
        // Set the current weapon's clip ammo to 150 (a high value that effectively acts as unlimited).
        self setweaponammoclip( self getcurrentweapon(), 150 );
        wait 0.05; // Small delay to constantly replenish.
    }
}

// Notifies the player when the unlimited ammo effect ends.
notify_unlimited_ammo_end()
{
    level endon( "game_ended" ); // End if the game ends.
    self endon( "disconnect" ); // End if the player disconnects.
    self endon( "end_unlimited_ammo" ); // End if the unlimited ammo effect is manually ended (prevents double notification).

    wait level.unlimited_ammo_duration; // Wait for the specified duration.

    self playsound( "zmb_insta_kill" ); // Play a sound effect to indicate the end.
    self notify( "end_unlimited_ammo" ); // Notify other threads that the effect has ended.
}

// Activates the blood money effect for all players.
blood_money_powerup()
{
    // Notify all players to end any existing Blood Money effects.
    foreach( player in level.players )
    {
        player notify( "end_blood_money" );
    }

    // Play the announcer sound globally for Blood Money, just once.
    level playsound( "zmb_bloodmoney_announcer_voice" ); // Global announcer sound

    // Now, loop through players to apply their individual effects and sounds.
    foreach( player in level.players )
    {
        player playsound( "zmb_bldmoney_chant" ); // Player-specific sound
        player thread turn_on_blood_money();
        player thread blood_money_on_hud();
        player thread notify_blood_money_end();
    }
}

// Manages the "Blood Money!" HUD string.
blood_money_on_hud()
{
    self endon( "disconnect" );

    blood_money_hud_string = newclienthudelem( self );
    blood_money_hud_string.elemtype = "font";
    blood_money_hud_string.font = "objective";
    blood_money_hud_string.fontscale = 2;
    blood_money_hud_string.x = 0;
    blood_money_hud_string.y = 0;
    blood_money_hud_string.width = 0;
    blood_money_hud_string.height = int( level.fontheight * 2 );
    blood_money_hud_string.xoffset = 0;
    blood_money_hud_string.yoffset = 0;
    blood_money_hud_string.children = [];
    blood_money_hud_string setparent( level.uiparent );
    blood_money_hud_string.hidden = 0;
    blood_money_hud_string setpoint( "TOP", undefined, 0, level.zombie_vars[ "zombie_timer_offset"] - level.zombie_vars[ "zombie_timer_offset_interval"] * 2 );
    blood_money_hud_string.sort = 0.5;
    blood_money_hud_string.alpha = 0;

    blood_money_hud_string fadeovertime( 0.5 );
    blood_money_hud_string.alpha = 1;
    blood_money_hud_string settext( "Blood Money!" );
    blood_money_hud_string thread blood_money_hud_string_move();

    blood_money_hud_icon = newclienthudelem( self );
    blood_money_hud_icon.horzalign = "center";
    blood_money_hud_icon.vertalign = "bottom";
    blood_money_hud_icon.x = -75;
    blood_money_hud_icon.y = 0;
    blood_money_hud_icon.alpha = 1;
    blood_money_hud_icon.hidewheninmenu = 1;
    blood_money_hud_icon setshader( "hud_icon_minigun", 40, 40 );

    self thread blood_money_hud_icon_blink( blood_money_hud_icon );
    self thread destroy_blood_money_icon_hud( blood_money_hud_icon );
}

// Animates the "Blood Money!" HUD string.
blood_money_hud_string_move()
{
    wait 0.5;
    self fadeovertime( 1.5 );
    self moveovertime( 1.5 );
    self.y = 270;
    self.alpha = 0;
    wait 1.5;
    self destroy();
}

// Makes the blood money HUD icon blink based on remaining time.
blood_money_hud_icon_blink( elem )
{
    level endon( "disconnect" );
    self endon( "disconnect" );
    self endon( "end_blood_money" );

    time_left = level.blood_money_duration;
    for(;;)
    {
        time = 0.5;
        if( time_left <= 5 )
        {
            time = 0.1;
        }
        else if( time_left <= 10 )
        {
            time = 0.2;
        }

        elem fadeovertime( time );
        elem.alpha = 0;
        wait time;
        elem fadeovertime( time );
        elem.alpha = 1;
        wait time;

        time_left = time_left - (time * 2);

        if (time_left <= 0) {
            break;
        }
    }
}

// Destroys the blood money HUD icon.
destroy_blood_money_icon_hud( elem )
{
    level endon( "game_ended" );
    self waittill_any_timeout( level.blood_money_duration + 1, "disconnect", "end_blood_money" );
    elem destroy();
}

// Grants the player "blood money" effect.
turn_on_blood_money()
{
    self endon( "death" ); // Add this to end the thread if the player dies
    self endon( "disconnected" ); // Add this to end if the player disconnects
    self endon( "end_blood_money" );
    level endon( "game_ended" );

    // Calculate a random reward between 500 and 2500
    // randomintrange(min, max) is exclusive for the max value, so (500, 2501) gives 500-2500
    reward = randomintrange( 500, 2501 );

    // Add the reward to the player's score
    self.score += reward;

    // Notify the player about the points they received
    self iprintlnbold( "^5Blood Money Activated! ^7+" + reward + " Points!" );
    self playsound( "zmb_bloodmoney_announcer_voice" ); // Play sound directly for the player
}

// Notifies the player when the blood money effect ends.
notify_blood_money_end()
{
    level endon( "game_ended" );
    self endon( "disconnect" );
    self endon( "end_blood_money" );

    wait level.blood_money_duration;

    self playsound( "zmb_bloodmoney_off_announcer" ); // You might want a different sound here
    self notify( "end_blood_money" );
}

// --- Fire Sale Powerup Functions ---

// Activates the Fire Sale effect for all players.
fire_sale_powerup()
{
    // Notify all players to end any existing Fire Sale effects (to reset or restart the timer).
    foreach( player in level.players )
    {
        player notify( "end_fire_sale" );
    }

    // Store the original box price. This assumes 'level.zombie_vars["box_price"]' is where the base box price is stored.
    if (!IsDefined(level.original_box_price)) {
        level.original_box_price = level.zombie_vars["box_cost"];
    }

    // Set the box price to 10 points.
    level.zombie_vars["box_cost"] = 10;
    level playsound( "zmb_firesale_announcer_voice" ); // Global announcer sound for Fire Sale

    foreach( player in level.players )
    {
        player playsound( "zmb_firesale_plr" ); // Player-specific sound
        player thread fire_sale_on_hud(); // Display the Fire Sale status on HUD.
        player thread notify_fire_sale_end(); // Set a timer to end the effect.
    }
}

// Manages the "Fire Sale!" HUD string.
fire_sale_on_hud()
{
    self endon( "disconnect" );

    fire_sale_hud_string = newclienthudelem( self );
    fire_sale_hud_string.elemtype = "font";
    fire_sale_hud_string.font = "objective";
    fire_sale_hud_string.fontscale = 2;
    fire_sale_hud_string.x = 0;
    fire_sale_hud_string.y = 0;
    fire_sale_hud_string.width = 0;
    fire_sale_hud_string.height = int( level.fontheight * 2 );
    fire_sale_hud_string.xoffset = 0;
    fire_sale_hud_string.yoffset = 0;
    fire_sale_hud_string.children = [];
    fire_sale_hud_string setparent( level.uiparent );
    fire_sale_hud_string.hidden = 0;
    fire_sale_hud_string setpoint( "TOP", undefined, 0, level.zombie_vars[ "zombie_timer_offset"] - level.zombie_vars[ "zombie_timer_offset_interval"] * 2 );
    fire_sale_hud_string.sort = 0.5;
    fire_sale_hud_string.alpha = 0;

    fire_sale_hud_string fadeovertime( 0.5 );
    fire_sale_hud_string.alpha = 1;
    fire_sale_hud_string settext( "Fire Sale!" );
    fire_sale_hud_string thread fire_sale_hud_string_move();

    fire_sale_hud_icon = newclienthudelem( self );
    fire_sale_hud_icon.horzalign = "center";
    fire_sale_hud_icon.vertalign = "bottom";
    fire_sale_hud_icon.x = -75;
    fire_sale_hud_icon.y = 0;
    fire_sale_hud_icon.alpha = 1;
    fire_sale_hud_icon.hidewheninmenu = 1;
    fire_sale_hud_icon setshader( "hud_icon_minigun", 40, 40 );

    self thread fire_sale_hud_icon_blink( fire_sale_hud_icon );
    self thread destroy_fire_sale_icon_hud( fire_sale_hud_icon );
}

// Animates the "Fire Sale!" HUD string.
fire_sale_hud_string_move()
{
    wait 0.5;
    self fadeovertime( 1.5 );
    self moveovertime( 1.5 );
    self.y = 270;
    self.alpha = 0;
    wait 1.5;
    self destroy();
}

// Makes the Fire Sale HUD icon blink based on remaining time.
fire_sale_hud_icon_blink( elem )
{
    level endon( "disconnect" );
    self endon( "disconnect" );
    self endon( "end_fire_sale" );

    time_left = level.fire_sale_duration;
    for(;;)
    {
        time = 0.5;
        if( time_left <= 5 )
        {
            time = 0.1;
        }
        else if( time_left <= 10 )
        {
            time = 0.2;
        }

        elem fadeovertime( time );
        elem.alpha = 0;
        wait time;
        elem fadeovertime( time );
        elem.alpha = 1;
        wait time;

        time_left = time_left - (time * 2);

        if (time_left <= 0) {
            break;
        }
    }
}

// Destroys the Fire Sale HUD icon.
destroy_fire_sale_icon_hud( elem )
{
    level endon( "game_ended" );
    self waittill_any_timeout( level.fire_sale_duration + 1, "disconnect", "end_fire_sale" );
    elem destroy();
}

// Notifies when the Fire Sale effect ends and restores original box price.
notify_fire_sale_end()
{
    level endon( "game_ended" );
    self endon( "disconnect" );
    self endon( "end_fire_sale" );

    wait level.fire_sale_duration;

    // Restore the original box price for all mystery box entities.
    if (IsDefined(level.original_box_price)) {
        level.zombie_vars["box_cost"] = level.original_box_price;
    } else {
        // Fallback to a default price if original wasn't stored (e.g., 950 points)
        level.zombie_vars["box_cost"] = 950; // Common default for mystery box
    }

    self playsound( "zmb_firesale_off_announcer" ); // Announcer sound for Fire Sale ending
    self notify( "end_fire_sale" );
}

round_skip_powerup()
{
    level endon("game_ended");

    // Play announcer sound to all players
    level playsound("zmb_spawn"); // Change this to a valid alias if you have a custom one

    foreach (player in level.players)
    {
        player iprintlnbold("^3Round Skipped!");
        player playsound("zmb_cha_ching"); // Replace with custom if working
    }

    wait 1; // Optional delay to let sound play before chaos starts

    // Prefer official round skip method
    if (IsDefined(level.zombie_round_go_to_next_round))
    {
        level thread [[level.zombie_round_go_to_next_round]]();
    }
    else
    {
        level thread kill_all_zombies_and_advance();
    }
}

kill_all_zombies_and_advance()
{
    level endon("game_ended");

    a_zombies = GetAIArray();
    for (i = 0; i < a_zombies.size; i++)
    {
        if (IsDefined(a_zombies[i]) && IsAlive(a_zombies[i]) && a_zombies[i].archetype == "zombie")
        {
            a_zombies[i] dodamage(a_zombies[i].health + 1000, a_zombies[i].origin);
        }
    }

    wait 0.5; // Give time for zombies to die
    level notify("end_of_round");
}

// Activates the Pay Taxes effect.
pay_taxes_powerup()
{
    level endon( "game_ended" );

    // Announce the powerup to all players
    level playsound( "zmb_pay_taxes_announcer" ); // You'll need to define this sound alias
    foreach( player in level.players )
    {
        player iprintlnbold( "^1PAYING TAXES!" );
        player playsound( "zmb_powerup_pay_taxes_plr" ); // Player-specific sound for pay taxes
    }

    // Apply the tax to each player
    foreach( player in level.players )
    {
        if ( IsDefined( player ) && IsPlayer( player ) )
        {
            current_score = player.score;
            tax_amount = int( current_score * 0.50 ); // Calculate 50% of current score
            player.score -= tax_amount; // Remove the points

            player iprintlnbold( "^1-" + tax_amount + " Points! ^7(Taxes Paid)" );
        }
    }
}