#include scripts\zm\custom_welcome;

init()
{
    level thread onPlayerSpawnedHandler();
}

onPlayerSpawnedHandler()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("connected", player);
        player thread onPlayerSpawned();
    }
}