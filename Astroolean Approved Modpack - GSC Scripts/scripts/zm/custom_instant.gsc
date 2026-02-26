/*
    Instant Pack-a-Punch (BO2 Zombies / Plutonium T6)
    Created by: Astroolean

    SUMMARY
    - Adds a custom Pack-a-Punch interaction that upgrades the weapon in your hands instantly when you hold the Use key.
    - Uses a configurable price DVAR: pap_price (defaults to 5000).
    - Places a new trigger_radius at the Pack-a-Punch machine and disables the default upgrade trigger.

    WHAT THIS SCRIPT DOES (HIGH LEVEL)
    1) Waits for Pack-a-Punch to become available ("Pack_A_Punch_on").
    2) Finds the Pack-a-Punch machine entity (targetname: vending_packapunch).
    3) Disables the original weapon upgrade trigger (script_noteworthy: specialty_weapupgrade).
    4) Spawns a new radius trigger around the machine with a custom hint string showing the cost.
    5) When a player uses the trigger:
       - Validates the held weapon (not riot shield, not equipment/mines, not revive tool, not already upgraded, etc.).
       - Charges points (pap_price).
       - Swaps the weapon to its Pack-a-Punch upgraded version immediately.

    CONFIGURATION
    - DVAR: pap_price
      Default: 5000
      Change at runtime (example): set pap_price 3000

    NOTES / INTENTIONAL BEHAVIOR
    - This file is organized for maintainability: includes, init hooks, player hooks, Pack-a-Punch logic, helpers.
    - Code logic is unchanged; edits are comments + layout only.
*/

#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_magicbox;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_power;
#include maps\mp\zombies\_zm_pers_upgrades_functions;
#include maps\mp\zombies\_zm_audio;
#include maps\mp\_demo;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_chugabud;
#include maps\mp\_visionset_mgr;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm;


// ============================================================================ 
// init (function)
// ============================================================================ 

/**
 * init()
 *
 * Entry point for the script.
 * - Starts the player connection handler.
 * - Starts the Pack-a-Punch trigger thread (runs on level).
 * - Initializes the pap_price DVAR (only sets it if it doesn't exist yet).
 */
init()
{
        level thread onPlayerConnect();
        level.custom_pap_validation = thread new_pap_trigger();
        create_dvar("pap_price", 5000);
}


// ============================================================================ 
// onPlayerConnect (function)
// ============================================================================ 

/**
 * onPlayerConnect()
 *
 * Runs forever and fires when each player connects.
 * - Threads onPlayerSpawned() for each new player so they get the HUD print on spawn.
 */
onPlayerConnect()
{
        for (;;)
        {
                level waittill("connected", player);
                player thread onPlayerSpawned();
        }
}


// ============================================================================ 
// onPlayerSpawned (function)
// ============================================================================ 

/**
 * onPlayerSpawned()
 *
 * Per-player loop that runs every time the player spawns.
 * - Prints a single line so the player knows the mod is active.
 *
 * NOTE: This is informational only; it does not change gameplay behavior.
 */
onPlayerSpawned()
{
        self endon("disconnect");
        level endon("game_ended");

        for (;;)
        {
                self waittill("spawned_player");
                self iPrintLn("^5Instant Pack-a-Punch ^7Active");
        }
}


// ============================================================================ 
// new_pap_trigger (function)
// ============================================================================ 

/**
 * new_pap_trigger()
 *
 * Main Pack-a-Punch replacement logic.
 *
 * Flow:
 * - Wait for the game to enable Pack-a-Punch.
 * - Locate the machine entity and disable the stock upgrade trigger.
 * - Spawn a new trigger_radius around the machine with a cost hint.
 * - When a player triggers it and holds Use:
 *     - Validate weapon + player state.
 *     - Charge points.
 *     - Give the upgraded weapon immediately and switch to it.
 */
new_pap_trigger()
{
        level waittill("Pack_A_Punch_on");
        wait 2;

        if (getDvar("mapname") == "zm_transit" && getDvar("g_gametype") == "zstandard")
        {
        }
        else
        {
                level notify("Pack_A_Punch_off");
                level thread pap_off();
        }

        if (getDvar("mapname") == "zm_nuked")
        {
                level waittill("Pack_A_Punch_on");
        }

        perk_machine = getEnt("vending_packapunch", "targetname");
        weapon_upgrade_trigger = getEntArray("specialty_weapupgrade", "script_noteworthy");
        weapon_upgrade_trigger[0] trigger_off();

        if (getDvar("mapname") == "zm_transit" && getDvar("g_gametype") == "zclassic")
        {
                if (!level.buildables_built["pap"])
                {
                        level waittill("pap_built");
                }
        }

        wait 1;
        self.perk_machine = perk_machine;
        perk_machine_sound = getEntArray("perksacola", "targetname");
        packa_rollers = spawn("script_origin", perk_machine.origin);
        packa_timer = spawn("script_origin", perk_machine.origin);
        packa_rollers linkTo(perk_machine);
        packa_timer linkTo(perk_machine);

        if (getDvar("mapname") == "zm_highrise")
        {
                trigger = spawn("trigger_radius", perk_machine.origin, 1, 60, 80);
                trigger enableLinkTo();
                trigger linkTo(self.perk_machine);
        }
        else
        {
                trigger = spawn("trigger_radius", perk_machine.origin, 1, 35, 80);
        }

        trigger setCursorHint("HINT_NOICON");
        trigger setHintString("Hold ^3&&1^7 for Pack-a-Punch [Cost: " + getDvarInt("pap_price") + "]");
        trigger useTriggerRequireLookAt();
        perk_machine thread maps\mp\zombies\_zm_perks::activate_packapunch();

        for (;;)
        {
                trigger waittill("trigger", player);
                current_weapon = player getCurrentWeapon();


                // --------------------------------------------------------------------
                // Purchase / validation gate
                // --------------------------------------------------------------------
                // Requirements (must ALL be true):
                // - Player is holding Use.
                // - Player has enough points (pap_price).
                // - Weapon is valid for Pack-a-Punch (not riot shield, not equipment/mines, etc.).
                // - Player is allowed to buy right now (can_buy_weapon) and isn't in another action (drinking).
                // - Weapon is not already upgraded.
                //
                // If any check fails, nothing happens (no points taken).

                if (player useButtonPressed() && player.score >= getDvarInt("pap_price") && current_weapon != "riotshield_zm" && player can_buy_weapon() && !player.is_drinking && !is_placeable_mine(current_weapon) && !is_equipment(current_weapon) && level.revive_tool != current_weapon && current_weapon != "none" && !is_weapon_upgraded(current_weapon))
                {
                        player.score -= getDvarInt("pap_price");
                        player thread maps\mp\zombies\_zm_audio::play_jingle_or_stinger("mus_perks_packa_sting");
                        trigger setInvisibleToAll();

                        upgrade_as_attachment = will_upgrade_weapon_as_attachment(current_weapon);


                        // Cache ammo values before the weapon swap.
                        // NOTE: These fields are stored on the player for potential later use.
                        // This script captures them exactly as the original did.

                        player.restore_ammo = undefined;
                        player.restore_clip = undefined;
                        player.restore_stock = undefined;
                        player.restore_clip_size = undefined;
                        player.restore_max = undefined;

                        player.restore_clip = player getWeaponAmmoClip(current_weapon);
                        player.restore_clip_size = weaponClipSize(current_weapon);
                        player.restore_stock = player getWeaponAmmoStock(current_weapon);
                        player.restore_max = weaponMaxAmmo(current_weapon);


                        // Perform the instant upgrade:
                        // - Remove current weapon
                        // - Resolve any alternate weapon form (e.g., underbarrel/alt mode)
                        // - Compute upgraded weapon name
                        // - Give upgraded weapon + switch to it

                        player takeWeapon(current_weapon);
                        current_weapon = player maps\mp\zombies\_zm_weapons::switch_from_alt_weapon(current_weapon);
                        self.current_weapon = current_weapon;
                        upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(current_weapon, upgrade_as_attachment);

                        player giveWeapon(upgrade_name, 0, player maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options(upgrade_name));
                        player switchToWeapon(upgrade_name);

                        player playSound("zmb_perks_packa_ready");
                        player playSound("zmb_cha_ching");

                        if (isDefined(player))
                        {
                                trigger setInvisibleToAll();
                                trigger setVisibleToPlayer(player);
                        }

                        self.current_weapon = "";
                        trigger setInvisibleToPlayer(player);
                        wait 0.5;
                        trigger setVisibleToAll();
                        self.pack_player = undefined;
                        flag_clear("pack_machine_in_use");
                }

                trigger setHintString("Hold ^3&&1^7 for Pack-a-Punch [Cost: " + getDvarInt("pap_price") + "]");
                wait 0.1;
        }
}


// ============================================================================ 
// pap_off (function)
// ============================================================================ 

/**
 * pap_off()
 *
 * Utility thread used on maps where you want to immediately suppress/undo the
 * "Pack_A_Punch_on" state by notifying "Pack_A_Punch_off" whenever it turns on.
 *
 * This is a compatibility behavior used by the original script; it is preserved.
 */
pap_off()
{
        wait 5;
        for (;;)
        {
                level waittill("Pack_A_Punch_on");
                wait 1;
                level notify("Pack_A_Punch_off");
        }
}


// ============================================================================ 
// create_dvar(dvar, set) (function)
// ============================================================================ 

/**
 * create_dvar(dvar, set)
 *
 * Safe helper: only sets a DVAR if it doesn't already exist / is empty.
 * This avoids overwriting server configs or user-set values.
 */
create_dvar(dvar, set)
{
        if (getDvar(dvar) == "")
                setDvar(dvar, set);
}