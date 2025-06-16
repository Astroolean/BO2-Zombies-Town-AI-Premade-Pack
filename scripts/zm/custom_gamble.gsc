#include common_scripts\utility;
#include maps\mp\gametypes\_hud_message;

/*
================================================================================================
Enhanced Gambling Totem Script (v2 - Mode Selector)

Features:
- Primary Gambling: A standard points-based gambling system.
- Debt System: Going into negative points puts you in debt, triggering unique, escalating consequences.
- High-Roller Mode: A toggleable mode for high-risk, high-reward gambling.
- Custom Sounds: Sound triggers for jackpot, bankruptcy, wins, and losses.
- Player-Specific HUD: Each player has their own HUD elements for messages.
================================================================================================
*/

main()
{
    // Initialize the gambling system
    level._gamble_totem_active = true;
    level thread setup_gamble_totem();
    level thread player_connect_monitor();

    // --- Sound Setup ---
    // NOTE FOR GSC: These are sound aliases. For them to work, you must define them
    // in a .csv file (e.g., sound/my_custom_sounds.csv) and include it in your Zone Source.
    // This is a standard GSC practice and does not require a "full mod".
    // Example CSV line: gamble_jackpot,sound/path/to/your/jackpot.wav
    level.sounds["gamble_jackpot"] = "gamble_jackpot";
    level.sounds["gamble_bankrupt"] = "gamble_bankrupt";
    level.sounds["gamble_win"] = "gamble_win";
    level.sounds["gamble_lose"] = "gamble_lose";
    level.sounds["gamble_debt_reward"] = "gamble_debt_reward";
}

// Monitors for new players connecting to the server
player_connect_monitor()
{
    for (;;) {
        level waittill("connected", player);
        player thread on_player_connect();
    }
}

// Sets up initial variables and HUD for a connecting player
on_player_connect()
{
    self endon("disconnect");

    // --- Player State ---
    if (!isdefined(self.player_debt_level)) {
        self.player_debt_level = 0;
    }
    // Set default gambling mode for the player
    self.gamble_mode = "standard";
}

// Spawns the physical totem and its interaction trigger
setup_gamble_totem()
{
    level endon("game_ended");

    // --- Totem Object ---
    gamble_totem_origin = (2100, 175, -10);
    gamble_totem_angles = (0, -15.5017, 0);

    precachemodel("zombie_teddybear");

    level._gamble_totem_object = Spawn("script_model", gamble_totem_origin);
    level._gamble_totem_object SetModel("zombie_teddybear");
    level._gamble_totem_object.angles = gamble_totem_angles;

    // --- Interaction Trigger ---
    gamble_trigger = Spawn("trigger_radius", gamble_totem_origin, 0, 64, 80);

    println("Gambler Totem spawned at: " + gamble_trigger.origin);

    gamble_trigger._last_gamble_time = 0;
    gamble_trigger._cooldown_duration_ms = 2000;

    gamble_trigger thread monitor_trigger_loop();
}

// Waits for a player to enter the trigger
monitor_trigger_loop()
{
    self endon("death");
    level endon("game_ended");

    while (true)
    {
        self waittill("trigger", player);
        if (isdefined(player))
        {
            player thread handle_gamble_zone(self);
        }
    }
}

// Manages the interaction prompts and mode switching
handle_gamble_zone(trigger)
{
    self endon("disconnect");
    self endon("death");

    if (isdefined(self.in_gamble_zone) && self.in_gamble_zone)
        return;

    self.in_gamble_zone = true;

    // --- Hint Message Setup ---
    hint_text = newHudElem();
    // Setting both horizontal alignment to center and x to 0 will center the text.
    hint_text.horzAlign = "center";
    hint_text.vertAlign = "bottom";
    hint_text.x = -125; // Centered
    hint_text.y = -120;
    hint_text.fontScale = 1.8;
    hint_text.alpha = 1;
    hint_text.color = (1,1,1);

    // --- Main Interaction Loop ---
    while (self IsTouching(trigger))
    {
        // --- Update Hint Text based on current mode ---
        // Changed "{+use}" to "{+gostand}" to display the Square button icon.
        // The "{+speed_throw}" typically maps to L2/LT.
        if (self.gamble_mode == "standard") {
            hint_text setText("^5Press ^7[{+gostand}]^5 for Standard Gamble ^7(500)\n^5Press ^7[{+speed_throw}]^5 to switch mode");
        } else {
            hint_text setText("^5Press ^7[{+gostand}]^5 for High-Roller Gamble ^7(2500)\n^5Press ^7[{+speed_throw}]^5 to switch mode");
        }

        // --- Check for Mode Switch (Ads Button) ---
        // Using AdsButtonPressed for mode switch. Consider if a different keybind
        // like 'alt_grenade_button' might be less intrusive during gameplay.
        if (self AdsButtonPressed()) {
            if (self.gamble_mode == "standard") {
                self.gamble_mode = "high_roller";
            } else {
                self.gamble_mode = "standard";
            }
            self playsound("ui_mp_class_change"); // A simple feedback sound
            wait 0.2; // Debounce to prevent rapid switching
        }

        // --- Check for Gamble Attempt (Use Button) ---
        // UseButtonPressed typically maps to the 'use' action which is often the Square button.
        // We are only changing the displayed icon, not the actual button binding.
        if (self UseButtonPressed())
        {
            self thread handle_gamble_attempt(trigger);
            break; // Exit loop after an attempt
        }
        wait 0.05;
    }

    // --- Cleanup ---
    hint_text destroy();
    self.in_gamble_zone = false;
}

// Processes a player's attempt to gamble based on their selected mode
handle_gamble_attempt(trigger)
{
    self endon("disconnect");
    self endon("death");

    // --- Determine cost and type from player's mode ---
    local_gamble_cost = 500;
    local_gamble_type = "standard";
    if (self.gamble_mode == "high_roller") {
        local_gamble_cost = 2500;
        local_gamble_type = "high_roller";
    }

    current_time = gettime();

    // Cooldown Check
    if (current_time - trigger._last_gamble_time < trigger._cooldown_duration_ms) {
        self iprintlnbold("^5Totem is recharging^7...");
        return;
    }

    // Debt Check
    if (self.score < 0) {
        self thread show_gamble_message("^5You're in debt^7!", (1, 0.2, 0.2));
        self iprintlnbold("^5You owe money^7! ^5No gambling until you pay your debts^7!");
        return;
    }

    // Points Check
    if (self.score < local_gamble_cost) {
        self iprintlnbold("^5Need ^7" + local_gamble_cost + " ^5points to gamble^7!");
        self thread show_gamble_message("^5Not enough points^7!", (1, 0, 0));
        return;
    }

    // Process Gamble
    trigger._last_gamble_time = current_time;
    self.score -= local_gamble_cost;
    self iprintlnbold("^5Gambling^7...");

    wait 1.5;

    // Determine Outcome
    if (local_gamble_type == "high_roller") {
        self thread roll_for_high_roller_reward();
    } else {
        self thread roll_for_standard_reward();
    }
}

// Calculates the result of a standard gamble
roll_for_standard_reward()
{
    self endon("disconnect");
    self endon("death");

    roll = randomfloat(100);
    reward = 0;
    message = "";
    color = (1, 1, 1);
    sound_alias = "";

    if (roll < 35) {
        reward = randomintrange(-2000, -1);
        message = "" + reward;
        color = (1, 0.2, 0.2);
        sound_alias = level.sounds["gamble_lose"];
    } else if (roll < 85) {
        reward = randomintrange(1, 3000);
        message = "+" + reward;
        color = (0.5, 1, 0.5);
        sound_alias = level.sounds["gamble_win"];
    } else if (roll < 98) {
        reward = randomintrange(3001, 7500);
        message = "+" + reward;
        color = (0.2, 1, 0.2);
        sound_alias = level.sounds["gamble_win"];
    } else {
        reward = 10000;
        message = "JACKPOT!";
        color = (1, 0.8, 0);
        sound_alias = level.sounds["gamble_jackpot"];
        self thread flashing_gamble_message("+" + reward, color);
    }

    self.score += reward;
    self iprintlnbold("^5Result^7: " + message + " ^5Points");
    if(reward != 10000) self thread show_gamble_message(message, color); // Jackpot has its own flashy message
    self playsound(sound_alias);

    self thread check_debt_status();
}

// Calculates the result of a high-roller gamble
roll_for_high_roller_reward()
{
    self endon("disconnect");
    self endon("death");

    roll = randomfloat(100);
    reward = 0;
    message = "";
    color = (1, 1, 1);
    sound_alias = "";

    if (roll < 50) {
        reward = -15000;
        message = "BANKRUPT!";
        color = (1, 0, 0);
        sound_alias = level.sounds["gamble_bankrupt"];
        self thread flashing_gamble_message(message + "!", color);
    } else if (roll < 95) {
        reward = randomintrange(10000, 20000);
        message = "+" + reward;
        color = (0.2, 1, 0.2);
        sound_alias = level.sounds["gamble_win"];
    } else {
        reward = 50000;
        message = "MEGA JACKPOT!";
        color = (1, 0.8, 0);
        sound_alias = level.sounds["gamble_jackpot"];
        self thread flashing_gamble_message("+" + reward, color);
    }

    self.score += reward;
    self iprintlnbold("^5High-Roller Result^7: " + message + " ^5Points");
    if(reward > 0) self thread show_gamble_message(message, color); // Bankrupt/Jackpot has its own flashy message
    self playsound(sound_alias);

    self thread check_debt_status();
}


// --- Debt System ---
check_debt_status()
{
    self endon("disconnect");
    self endon("death");

    if (self.score >= 0) {
        self.player_debt_level = 0;
        return;
    }

    debt = abs(self.score);
    new_debt_level = 0;

    if (debt > 50000) new_debt_level = 4;
    else if (debt > 20000) new_debt_level = 3;
    else if (debt > 5000) new_debt_level = 2;
    else if (debt > 0) new_debt_level = 1;

    if (new_debt_level > self.player_debt_level) {
        self.player_debt_level = new_debt_level;
        self thread trigger_debt_consequence(self.player_debt_level);
    }
}

// Helper function to reset color map after a delay
reset_color_map_after_delay()
{
    self endon("disconnect");
    self endon("death");
    wait 10; // Duration of the curse
    if (isdefined(self)) {
        self setclientdvar( "r_colorMap", "0" ); // Reset to default color map
    }
}

trigger_debt_consequence(debt_level)
{
    self endon("disconnect");
    self endon("death");

    self playsound(level.sounds["gamble_debt_reward"]);

    switch(debt_level)
    {
        case 1:
            self iprintlnbold("^5Your hands feel heavy^7... ^5you are in debt^7...");
            self setmovespeedscale(0.8);
            wait 30;
            if(isdefined(self)) self setmovespeedscale(1.0);
            if(isdefined(self)) self iprintlnbold("^5Your debt burden feels lighter^7...");
            break;

        case 2:
            self iprintlnbold("^5The totem mocks you^7, ^5swapping your weapons^7...");

            non_pap_weapons = [];
            
            // --- SNIPERS ---
            non_pap_weapons[non_pap_weapons.size] = "dsr50_zm";
            non_pap_weapons[non_pap_weapons.size] = "barretm82_zm";
            non_pap_weapons[non_pap_weapons.size] = "svu_zm";
            non_pap_weapons[non_pap_weapons.size] = "ballista_zm";

            // --- SMGs ---
            non_pap_weapons[non_pap_weapons.size] = "ak74u_zm";
            non_pap_weapons[non_pap_weapons.size] = "mp5k_zm";
            non_pap_weapons[non_pap_weapons.size] = "pdw57_zm";
            non_pap_weapons[non_pap_weapons.size] = "qcw05_zm";
            non_pap_weapons[non_pap_weapons.size] = "thompson_zm";
            non_pap_weapons[non_pap_weapons.size] = "uzi_zm";
            non_pap_weapons[non_pap_weapons.size] = "evoskorpion_zm";
            non_pap_weapons[non_pap_weapons.size] = "ak74u_extclip_zm";

            // --- ASSAULT RIFLES ---
            non_pap_weapons[non_pap_weapons.size] = "fnfal_zm";
            non_pap_weapons[non_pap_weapons.size] = "m14_zm";
            non_pap_weapons[non_pap_weapons.size] = "saritch_zm";
            non_pap_weapons[non_pap_weapons.size] = "m16_zm";
            non_pap_weapons[non_pap_weapons.size] = "tar21_zm";
            non_pap_weapons[non_pap_weapons.size] = "gl_tar21_zm";
            non_pap_weapons[non_pap_weapons.size] = "galil_zm";
            non_pap_weapons[non_pap_weapons.size] = "an94_zm";
            non_pap_weapons[non_pap_weapons.size] = "type95_zm";
            non_pap_weapons[non_pap_weapons.size] = "xm8_zm";
            non_pap_weapons[non_pap_weapons.size] = "ak47_zm";
            non_pap_weapons[non_pap_weapons.size] = "scar_zm";
            non_pap_weapons[non_pap_weapons.size] = "hk416_zm";
            non_pap_weapons[non_pap_weapons.size] = "mp44_zm";

            // --- SHOTGUNS ---
            non_pap_weapons[non_pap_weapons.size] = "870mcs_zm";
            non_pap_weapons[non_pap_weapons.size] = "rottweil72_zm";
            non_pap_weapons[non_pap_weapons.size] = "saiga12_zm";
            non_pap_weapons[non_pap_weapons.size] = "srm1216_zm";
            non_pap_weapons[non_pap_weapons.size] = "ksg_zm";

            // --- LMGS ---
            non_pap_weapons[non_pap_weapons.size] = "lsat_zm";
            non_pap_weapons[non_pap_weapons.size] = "hamr_zm";
            non_pap_weapons[non_pap_weapons.size] = "rpd_zm";
            non_pap_weapons[non_pap_weapons.size] = "mg08_zm";

            // --- PISTOLS ---
            non_pap_weapons[non_pap_weapons.size] = "m1911_zm";
            non_pap_weapons[non_pap_weapons.size] = "rnma_zm";
            non_pap_weapons[non_pap_weapons.size] = "judge_zm";
            non_pap_weapons[non_pap_weapons.size] = "kard_zm";
            non_pap_weapons[non_pap_weapons.size] = "fiveseven_zm";
            non_pap_weapons[non_pap_weapons.size] = "fivesevendw_zm";
            non_pap_weapons[non_pap_weapons.size] = "beretta93r_zm";
            non_pap_weapons[non_pap_weapons.size] = "python_zm";
            non_pap_weapons[non_pap_weapons.size] = "c96_zm";
            non_pap_weapons[non_pap_weapons.size] = "beretta93r_extclip_zm";

            // --- LAUNCHERS ---
            non_pap_weapons[non_pap_weapons.size] = "usrpg_zm";
            non_pap_weapons[non_pap_weapons.size] = "m32_zm";

            // --- SPECIALS ---
            non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_zm";
            non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_bowie_zm";
            non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_no_melee_zm";

            // --- WONDER WEAPONS ---
            non_pap_weapons[non_pap_weapons.size] = "ray_gun_zm";
            non_pap_weapons[non_pap_weapons.size] = "raygun_mark2_zm";

            // Remove all current weapons and give a random one
            self TakeAllWeapons();
            randIndex = randomint(non_pap_weapons.size);
            randGun = non_pap_weapons[randIndex];
            self GiveWeapon(randGun);
            self SwitchToWeaponImmediate(randGun);
            break;

        case 3:
            self iprintlnbold("^5DEBT GHOSTS^7... ^5They hunger for your soul^7...");
            for(i = 0; i < 3; i++) {
                ghost = spawn("script_model", self.origin + (randomintrange(-100, 100), randomintrange(-100, 100), 20));
                ghost setmodel("zombie_cymbal_monkey");
                wait 0.5;
            }
            break;

        case 4:
            self iprintlnbold("^5THE TOTEM HAS CURSED YOU^7...");
            self shellshock("explosion", 5);
            self setclientdvar("r_colorMap", "2");
            self thread reset_color_map_after_delay();
            break;
    }
}

// --- HUD Message Functions ---
show_gamble_message(message, color)
{
    self.gamble_hud.color = color;
    self.gamble_hud settext(message);
    self.gamble_hud.alpha = 0;
    self.gamble_hud fadeovertime(0.5);
    self.gamble_hud.alpha = 1;

    wait 3;

    self.gamble_hud fadeovertime(1);
    self.gamble_hud.alpha = 0;
}

flashing_gamble_message(message, color)
{
    flashes = 10;
    flash_duration = 0.2;
    for (i = 0; i < flashes; i++)
    {
        self.gamble_hud settext(message);
        self.gamble_hud.color = color;
        self.gamble_hud.alpha = 1;
        wait flash_duration;

        self.gamble_hud.alpha = 0;
        wait flash_duration;
    }
    self.gamble_hud settext("");
}
