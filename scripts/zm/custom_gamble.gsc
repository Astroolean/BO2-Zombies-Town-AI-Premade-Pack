#include common_scripts\utility;
#include maps\mp\gametypes\_hud_message;

main()
{
    level._gamble_totem_active = true;
    level thread setup_gamble_totem();
    level thread player_connect_monitor();
}

player_connect_monitor()
{
    for (;;) {
        level waittill("connected", player);
        println("Player connected: " + player.name);
        player thread player_gamble_hud_setup();
    }
}

player_gamble_hud_setup()
{
    self endon("disconnect");
    self endon("death");

    self.gamble_hud = newHudElem();
    self.gamble_hud.horzAlign = "center";
    self.gamble_hud.vertAlign = "middle";
    self.gamble_hud.x = 0;
    self.gamble_hud.y = -100;
    self.gamble_hud.font = "objectivefont";
    self.gamble_hud.fontscale = 2.0;
    self.gamble_hud.alpha = 0;
    self.gamble_hud.color = (1, 1, 1);
    self.gamble_hud.sort = 1;
}

setup_gamble_totem()
{
    level endon("game_ended");

    gamble_totem_origin = (2100, 175, -10);
    gamble_totem_angles = (0, -15.5017, 0);
    
    precachemodel("zombie_teddybear");

    level._gamble_totem_object = Spawn("script_model", gamble_totem_origin);
    level._gamble_totem_object SetModel("zombie_teddybear");
    level._gamble_totem_object.angles = gamble_totem_angles;

    gamble_trigger = Spawn("trigger_radius", gamble_totem_origin, 0, 32, 64);

    println("Gambler Totem spawned at: " + gamble_trigger.origin);

    gamble_trigger._last_gamble_time = 0;
    gamble_trigger._cooldown_duration_ms = 2000;

    gamble_trigger thread monitor_trigger_loop(gamble_trigger);
}

monitor_trigger_loop(trigger)
{
    trigger endon("death");
    level endon("game_ended");

    while (true)
    {
        trigger waittill("trigger", player);

        if (isdefined(player))
        {
            player thread handle_gamble_zone(trigger);
        }
    }
}

handle_gamble_zone(trigger)
{
    self endon("disconnect");
    self endon("death");

    if (isdefined(self.in_gamble_zone) && self.in_gamble_zone)
        return;

    self.in_gamble_zone = true;

    button_icon = newHudElem();
    button_icon.horzAlign = "center";
    button_icon.vertAlign = "bottom";
    button_icon.x = -60;
    button_icon.y = -100;
    button_icon.alpha = 1;
    button_icon setShader("button_use", 32, 32);

    hint_text = newHudElem();
    hint_text.horzAlign = "center";
    hint_text.vertAlign = "bottom";
    hint_text.x = -100;
    hint_text.y = -100;
    hint_text.fontScale = 1.5;
    hint_text.alpha = 1;
    hint_text.color = (1,1,1);
    hint_text setText("^5Gamble your points away! (500 per spin)");

    while (self IsTouching(trigger))
    {
        if (self UseButtonPressed())
        {
            self thread handle_gamble_attempt(trigger);
            break;
        }
        wait 0.05;
    }

    button_icon destroy();
    hint_text destroy();
    self.in_gamble_zone = false;
}

handle_gamble_attempt(trigger)
{
    self endon("disconnect");
    self endon("death");

    current_time = gettime();

    if (current_time - trigger._last_gamble_time >= trigger._cooldown_duration_ms) {
        trigger._last_gamble_time = current_time;

        gamble_cost = 500;

        if (self.score >= gamble_cost) {
            self.score -= gamble_cost;
            self iprintlnbold("Gambling...");

            wait 5;

            roll_for_points_reward(self);
        }
        else if (self.score < 0) {
            self thread show_gamble_message("You're in debt! No gambling!", (1, 0.2, 0.2), -30, -75);   
            self iprintlnbold("You owe money! Pay your debts first!");
        }
        else {
            self iprintlnbold("Need " + gamble_cost + " Points to Gamble!");
            self thread show_gamble_message("Not enough points!", (1, 0, 0), -30, -75);
        }
    }
}

roll_for_points_reward(player)
{
    player endon("disconnect");
    player endon("death");

    roll = randomfloat(100);
    reward = 0;

    if (roll < 30) {
        reward = randomint(5001) * -1;  // -5000 to 0
    }
    else if (roll < 60) {
        reward = randomint(2001) * -1;  // -2000 to 0
    }
    else if (roll < 85) {
        reward = randomint(3001);       // 0 to +3000
    }
    else if (roll < 97.5) {
        reward = randomint(5001);       // 0 to +5000
    }
    else if (roll < 99.5) {
        reward = randomint(10001);      // 0 to +10,000
    }
    else {
        reward = randomint(10001) * -1; // -10,000
    }

    player.score += reward;

    if (reward >= 10000) {
        player iprintlnbold("^2JACKPOT! +10000 POINTS!");
        player thread flashing_gamble_message("+10000!", (0,1,0), -30, -75);
    }
    else if (reward <= -10000) {
        player iprintlnbold("^1BANKRUPT! -10000 POINTS!");
        player thread flashing_gamble_message("-10000!", (1,0,0), -30, -75);
    }
    else {
        color = (1,1,1);
        if (reward > 0)
            color = (0,1,0);
        else if (reward < 0)
            color = (1,0,0);

        player iprintlnbold("Result: " + reward + " Points");
        player thread show_gamble_message(reward >= 0 ? ("+" + reward) : ("" + reward), color, -30, -75);
    }
}

show_gamble_message(message, color, x_offset, y_offset)
{
    self.gamble_hud.x = x_offset;
    self.gamble_hud.y = y_offset;
    self.gamble_hud.color = color;
    self.gamble_hud settext(message);
    self.gamble_hud fadeovertime(0.5);
    self.gamble_hud.alpha = 1;

    wait 3;

    self.gamble_hud fadeovertime(1);
    self.gamble_hud.alpha = 0;
    wait 1;
    self.gamble_hud settext("");
}

flashing_gamble_message(message, color, x_offset, y_offset)
{
    self.gamble_hud.x = x_offset;
    self.gamble_hud.y = y_offset;

    flashes = 15;
    for (i = 0; i < flashes; i++)
    {
        self.gamble_hud settext(message);
        self.gamble_hud.color = color;
        self.gamble_hud.alpha = 1;
        wait 0.5;

        self.gamble_hud.alpha = 0;
        wait 0.5;
    }
    self.gamble_hud settext("");
}
