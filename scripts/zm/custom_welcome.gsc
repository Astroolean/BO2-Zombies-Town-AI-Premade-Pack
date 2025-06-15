onPlayerSpawned()
{
    self endon("disconnect");
    level endon("game_ended");

    self waittill("spawned_player");

    wait 5;
    self thread showWelcomeHud();
}

showWelcomeHud()
{
    self endon("disconnect");

    hud = NewClientHudElem(self);
    hud.alignX = "center";
    hud.alignY = "top";
    hud.horzAlign = "center";
    hud.vertAlign = "top";
    hud.x = 0;
    hud.y = 50;
    hud.fontScale = 2.4;
    hud.alpha = 0; // Start completely transparent
    hud.color = (0.4, 0.8, 1.0);
    hud.glowColor = (0.0, 0.1, 0.4);
    hud.glowAlpha = 1;
    hud.foreground = true;
    hud.font = "objective";
    hud.sort = 1;
    hud.hidewheninmenu = false;

    // Message 1: Fade in, display, then fade out
    hud setText("I did a coding thing...");
    hud fadeOverTime(2); // Fade in over 2 seconds
    hud.alpha = 1;
    wait 10; // Display for 10 seconds
    hud fadeOverTime(2); // Fade out over 2 seconds
    hud.alpha = 0;
    wait 2; // Wait for fade out to complete

    // Message 2: Fade in, display, then fade out
    hud setText("Welcome back to your nostalgic past...");
    hud fadeOverTime(2);
    hud.alpha = 1;
    wait 10;
    hud fadeOverTime(2);
    hud.alpha = 0;
    wait 2;

    hud destroy();
}
