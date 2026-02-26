/*
====================================================================================================
CUSTOM HEALTH BARS + HITMARKER FEEDBACK (BO2 ZOMBIES / PLUTONIUM T6)

Created by: Astroolean
File      : custom_healthbars.gsc

What this script does:
 - Shows a floating health bar for the last zombie you damaged (per-player, client HUD).
 - Optional zombie name + health text (bucketed percent or exact current/max via safe digit elements).
 - Uses text-throttling + digit HUD rendering to avoid configstring index overflow crashes.
 - Adds hitmarker HUD feedback and uses spawner callbacks to detect zombie damage/deaths cleanly.
 - Includes simple chat commands (prefix '#') to tweak bar color/size/name/shader and language.

How it works (high level):
 1) init() starts the player-connect listener and chat listener.
 2) on_player_connect_player() registers damage/death callbacks with the zombie spawner and
    sets up the hitmarker HUD elements for each connecting player.
 3) When a zombie is damaged/dead, do_hitmarker()/do_hitmarker_death() route to
    updatedamagefeedback(), which calls hud_show_zombie_health() for the current target.
 4) hud_show_zombie_health() creates the bar once, then updates width/color/text each time.

Safety notes:
 - GSC text strings can explode the configstring table if you spam unique strings every frame.
   This file limits text churn (bucketed % + throttled updates) and uses per-digit HUD for exact hp.
 - Cleanup is defensive: all HUD elements are faded/destroyed and threads are endon()-guarded.

Chat commands:
 - #barzm color <0-21>   : pick a color preset (or dynamic mode depending on list)
 - #barzm sizew <50-105> : bar width
 - #barzm sizeh <2-8>    : bar height
 - #barzm sizen <1-1.4>  : name font scale
 - #barzm name <0-1>     : toggle zombie name
 - #barzm shader <0-1>   : toggle the black shader backing/outline alpha
 - #help                : shows a small help overlay
 - #lang en|es          : switch message language

Editing rules (so you don’t accidentally break a working build):
 - Do NOT rename functions used as callbacks (do_hitmarker, do_hitmarker_death, etc.).
 - Prefer adjusting defaults in on_players_spawned() and the command ranges below.
 - If you add new text, keep it bucketed / throttled (avoid generating new strings every tick).
====================================================================================================
*/

#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\zombies\_zm_utility;
#include maps\mp_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm_hud_util;
#include maps\mp\zombies_zm;
#include maps\mp\zombies_zm_utility;
#include maps\mp\zombies_zm_weapons;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies_zm_stats;
#include maps\mp\gametypes_zm_hud_message;
#include maps\mp\zombies_zm_powerups;
#include maps\mp\zombies_zm_perks;
#include maps\mp\zombies_zm_audio;
#include maps\mp\zombies_zm_score;
#include maps\mp\gametypes_globallogic_spawn;
#include maps\mp\gametypes_spectating;
#include maps\mp_tacticalinsertion;
#include maps\mp_challenges;
#include maps\mp\gametypes_globallogic;
#include maps\mp\gametypes_globallogic_ui;
#include maps\mp\_utility;
#include maps\mp\gametypes_persistence;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\gametypes_zm\spawnlogic;
#include maps\mp\gametypes_zm\_hostmigration;


// ====================================================================================================
// ENTRY POINTS
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: init()
// Purpose : Entry point. Starts the player-connect handler and the chat command listener.
// Params  : none
// Returns : none
// Notes   :
//   - Runs on script load. Only lightweight threads should be started here.
// ----------------------------------------------------------------------------------------------------
init()
{
    level thread on_player_connect_player();
    level thread onPlayerSay();
}

// ---------------- HEALTHBAR SAFETY HELPERS (configstring overflow protection) ----------------
// text mode:
//   0 = name only (safest)
//   1 = name + bucketed percent (default, safe)
//   2 = exact hp/max (uses safe digit renderer) [stable anchors spacing fix]

// ====================================================================================================
// HEALTH BAR TEXT SAFETY HELPERS
//   These helpers exist to keep HUD text updates safe and stable on BO2.
//   The goal is to avoid generating lots of unique strings every frame (which can crash/freeze).
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: hb_safe_set_text(elem, txt)
// Purpose : Safely update a HUDelem's text only when it actually changes (reduces configstring churn).
// Params  : elem (HUDelem), txt (string)
// Returns : none
// Notes   :
//   - Prevents spamming setText() every update, which can contribute to configstring/index overflow issues.
// ----------------------------------------------------------------------------------------------------
hb_safe_set_text(elem, txt)
{
    if (!isdefined(elem))
        return;

    if (!isdefined(elem._hb_last_text) || elem._hb_last_text != txt)
    {
        elem._hb_last_text = txt;
        elem setText(txt);
    }
}


// ----------------------------------------------------------------------------------------------------
// Function: hb_digit_char(n)
// Purpose : Convert a single digit (0-9) into its string representation.
// Params  : n (int)
// Returns : string digit ('0'..'9')
// Notes   :
//   - Used by the exact-health digit renderer so we never build large unique strings per tick.
// ----------------------------------------------------------------------------------------------------
hb_digit_char(n)
{
    if (n == 0) return "0";
    if (n == 1) return "1";
    if (n == 2) return "2";
    if (n == 3) return "3";
    if (n == 4) return "4";
    if (n == 5) return "5";
    if (n == 6) return "6";
    if (n == 7) return "7";
    if (n == 8) return "8";
    if (n == 9) return "9";
    return "0";
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_hide_exact_health_text()
// Purpose : Hide the exact-health HUD elements (name/slash/digits) without destroying them.
// Params  : none (uses self.* fields)
// Returns : none
// Notes   :
//   - Exact-health mode keeps elements allocated and just toggles alpha for stability/performance.
// ----------------------------------------------------------------------------------------------------
hb_hide_exact_health_text()
{
    if (isdefined(self.hb_exact_name))
        self.hb_exact_name.alpha = 0;
    if (isdefined(self.hb_exact_slash))
        self.hb_exact_slash.alpha = 0;

    if (isdefined(self.hb_exact_cur_digits))
    {
        for (i = 0; i < self.hb_exact_cur_digits.size; i++)
        {
            if (isdefined(self.hb_exact_cur_digits[i]))
                self.hb_exact_cur_digits[i].alpha = 0;
        }
    }

    if (isdefined(self.hb_exact_max_digits))
    {
        for (i = 0; i < self.hb_exact_max_digits.size; i++)
        {
            if (isdefined(self.hb_exact_max_digits[i]))
                self.hb_exact_max_digits[i].alpha = 0;
        }
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_show_exact_health_text()
// Purpose : Show the fixed parts of exact-health mode (name and slash). Digits are shown by the updater.
// Params  : none
// Returns : none
// Notes   :
//   - Digits themselves are managed by hb_update_exact_health_text().
// ----------------------------------------------------------------------------------------------------
hb_show_exact_health_text()
{
    if (isdefined(self.hb_exact_name))
        self.hb_exact_name.alpha = 1;
    if (isdefined(self.hb_exact_slash))
        self.hb_exact_slash.alpha = 1;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_count_digits(value)
// Purpose : Count decimal digits for a non-negative integer (minimum 1).
// Params  : value (int)
// Returns : digit count (int)
// Notes   :
//   - Used for spacing/anchor layout in exact-health mode.
// ----------------------------------------------------------------------------------------------------
hb_count_digits(value)
{
    if (!isdefined(value) || value <= 0)
        return 1;

    count = 0;
    tmp = value;
    while (tmp > 0)
    {
        count++;
        tmp = int(tmp / 10);
    }
    return count;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_set_number_digits_right(digitElems, value)
// Purpose : Render an integer into an array of digit HUDelems, right-aligned (least significant digit on the right).
// Params  : digitElems (array<HUDelem>), value (int)
// Returns : digits used (int)
// Notes   :
//   - Clears/hides all digits first, then turns on only the digits needed.
//   - If the number exceeds the available digits, it saturates the display to all '9's as a safe fallback.
// ----------------------------------------------------------------------------------------------------
hb_set_number_digits_right(digitElems, value)
{
    if (!isdefined(digitElems))
        return 0;

    maxDigits = digitElems.size;

    for (i = 0; i < maxDigits; i++)
    {
        if (isdefined(digitElems[i]))
        {
            hb_safe_set_text(digitElems[i], "");
            digitElems[i].alpha = 0;
        }
    }

    if (!isdefined(value) || value < 0)
        value = 0;

    pos = maxDigits - 1;
    digitsUsed = 0;

    if (value == 0)
    {
        if (isdefined(digitElems[pos]))
        {
            hb_safe_set_text(digitElems[pos], "0");
            digitElems[pos].alpha = 1;
        }
        return 1;
    }

    tmp = value;
    while (tmp > 0 && pos >= 0)
    {
        digit = tmp % 10;
        if (isdefined(digitElems[pos]))
        {
            hb_safe_set_text(digitElems[pos], hb_digit_char(digit));
            digitElems[pos].alpha = 1;
        }
        tmp = int(tmp / 10);
        pos--;
        digitsUsed++;
    }

    if (tmp > 0)
    {
        for (i = 0; i < maxDigits; i++)
        {
            if (isdefined(digitElems[i]))
            {
                hb_safe_set_text(digitElems[i], "9");
                digitElems[i].alpha = 1;
            }
        }
        return maxDigits;
    }

    if (digitsUsed < 1)
        digitsUsed = 1;
    return digitsUsed;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_set_number_digits_left(digitElems, value)
// Purpose : Render an integer into an array of digit HUDelems, left-aligned (most significant digit on the left).
// Params  : digitElems (array<HUDelem>), value (int)
// Returns : digits used (int)
// Notes   :
//   - Same goal as hb_set_number_digits_right(), but useful when your anchor is the left edge.
// ----------------------------------------------------------------------------------------------------
hb_set_number_digits_left(digitElems, value)
{
    if (!isdefined(digitElems))
        return 0;

    maxDigits = digitElems.size;

    for (i = 0; i < maxDigits; i++)
    {
        if (isdefined(digitElems[i]))
        {
            hb_safe_set_text(digitElems[i], "");
            digitElems[i].alpha = 0;
        }
    }

    if (!isdefined(value) || value < 0)
        value = 0;

    if (value == 0)
    {
        if (isdefined(digitElems[0]))
        {
            hb_safe_set_text(digitElems[0], "0");
            digitElems[0].alpha = 1;
        }
        return 1;
    }

    strDigitsRev = [];
    tmp = value;
    count = 0;
    while (tmp > 0 && count < maxDigits)
    {
        strDigitsRev[count] = hb_digit_char(tmp % 10);
        tmp = int(tmp / 10);
        count++;
    }

    if (tmp > 0)
    {
        for (i = 0; i < maxDigits; i++)
        {
            if (isdefined(digitElems[i]))
            {
                hb_safe_set_text(digitElems[i], "9");
                digitElems[i].alpha = 1;
            }
        }
        return maxDigits;
    }

    // reverse into left-aligned display
    idx = 0;
    for (i = count - 1; i >= 0; i--)
    {
        if (isdefined(digitElems[idx]))
        {
            hb_safe_set_text(digitElems[idx], strDigitsRev[i]);
            digitElems[idx].alpha = 1;
        }
        idx++;
    }

    return count;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_layout_exact_health_text()
// Purpose : Position/space the exact-health elements (name, current digits, slash, max digits) so it reads cleanly.
// Params  : none
// Returns : none
// Notes   :
//   - This is the spacing “glue” that keeps the exact-health mode stable even as digit counts change.
// ----------------------------------------------------------------------------------------------------
hb_layout_exact_health_text()
{
    if (!isdefined(self.hb_exact_name))
        return;

    y = self.barY - 4;

    spacing = int(5 * self.sizeN);
    if (spacing < 4)
        spacing = 4;

    slashGap = int(5 * self.sizeN);
    if (slashGap < 4)
        slashGap = 4;

    // Add explicit visual spacing on BOTH sides of the slash so it reads like 125 / 150.
    slashPad = int(2 * self.sizeN);
    if (slashPad < 2)
        slashPad = 2;

    preSlashGap = slashGap + slashPad;
    postSlashGap = slashGap + slashPad;

    // Keep numeric group close together so it still looks like a normal single line.
    currentRightX = int(14 * self.sizeN);
    if (currentRightX < 10)
        currentRightX = 10;

    slashX = currentRightX + preSlashGap;
    maxLeftX = slashX + postSlashGap;

    // fixed name anchor so the name does not shift as current HP digit count changes
    reservedCurDigits = 5;
    nameRightX = currentRightX - ((reservedCurDigits - 1) * spacing) - int(3 * self.sizeN);

    self.hb_exact_name.horzalign = "center";
    self.hb_exact_name.vertalign = "middle";
    self.hb_exact_name.alignx = "right";
    self.hb_exact_name.aligny = "bottom";
    self.hb_exact_name.x = nameRightX;
    self.hb_exact_name.y = y;
    self.hb_exact_name.fontscale = self.sizeN;

    self.hb_exact_slash.horzalign = "center";
    self.hb_exact_slash.vertalign = "middle";
    self.hb_exact_slash.alignx = "center";
    self.hb_exact_slash.aligny = "bottom";
    self.hb_exact_slash.x = slashX;
    self.hb_exact_slash.y = y;
    self.hb_exact_slash.fontscale = self.sizeN;

    if (isdefined(self.hb_exact_cur_digits))
    {
        curSlots = self.hb_exact_cur_digits.size;
        for (i = 0; i < curSlots; i++)
        {
            if (!isdefined(self.hb_exact_cur_digits[i]))
                continue;
            self.hb_exact_cur_digits[i].horzalign = "center";
            self.hb_exact_cur_digits[i].vertalign = "middle";
            self.hb_exact_cur_digits[i].alignx = "center";
            self.hb_exact_cur_digits[i].aligny = "bottom";
            // right-aligned block packed against the slash
            self.hb_exact_cur_digits[i].x = currentRightX - ((curSlots - 1 - i) * spacing);
            self.hb_exact_cur_digits[i].y = y;
            self.hb_exact_cur_digits[i].fontscale = self.sizeN;
        }
    }

    if (isdefined(self.hb_exact_max_digits))
    {
        maxSlots = self.hb_exact_max_digits.size;
        for (i = 0; i < maxSlots; i++)
        {
            if (!isdefined(self.hb_exact_max_digits[i]))
                continue;
            self.hb_exact_max_digits[i].horzalign = "center";
            self.hb_exact_max_digits[i].vertalign = "middle";
            self.hb_exact_max_digits[i].alignx = "center";
            self.hb_exact_max_digits[i].aligny = "bottom";
            // left-aligned block packed against the slash
            self.hb_exact_max_digits[i].x = maxLeftX + (i * spacing);
            self.hb_exact_max_digits[i].y = y;
            self.hb_exact_max_digits[i].fontscale = self.sizeN;
        }
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_ensure_exact_health_text()
// Purpose : Create (once) the extra HUDelems needed for exact-health mode and cache them on the player.
// Params  : none
// Returns : none
// Notes   :
//   - Allocates the name element, slash element, and digit arrays for current/max health.
// ----------------------------------------------------------------------------------------------------
hb_ensure_exact_health_text()
{
    if (isdefined(self.hb_exact_name))
        return;

    self.hb_exact_name = newclienthudelem(self);
    self.hb_exact_name.sort = 4;
    self.hb_exact_name.hidewheninmenu = true;
    self.hb_exact_name.archived = false;
    self.hb_exact_name.foreground = true;
    self.hb_exact_name.font = "objective";
    self.hb_exact_name.alpha = 0;

    self.hb_exact_slash = newclienthudelem(self);
    self.hb_exact_slash.sort = 4;
    self.hb_exact_slash.hidewheninmenu = true;
    self.hb_exact_slash.archived = false;
    self.hb_exact_slash.foreground = true;
    self.hb_exact_slash.font = "objective";
    self.hb_exact_slash.alpha = 0;
    hb_safe_set_text(self.hb_exact_slash, "^7/");

    self.hb_exact_cur_digits = [];
    self.hb_exact_max_digits = [];

    for (i = 0; i < 7; i++)
    {
        self.hb_exact_cur_digits[i] = newclienthudelem(self);
        self.hb_exact_cur_digits[i].sort = 4;
        self.hb_exact_cur_digits[i].hidewheninmenu = true;
        self.hb_exact_cur_digits[i].archived = false;
        self.hb_exact_cur_digits[i].foreground = true;
        self.hb_exact_cur_digits[i].font = "objective";
        self.hb_exact_cur_digits[i].alpha = 0;
        hb_safe_set_text(self.hb_exact_cur_digits[i], "");

        self.hb_exact_max_digits[i] = newclienthudelem(self);
        self.hb_exact_max_digits[i].sort = 4;
        self.hb_exact_max_digits[i].hidewheninmenu = true;
        self.hb_exact_max_digits[i].archived = false;
        self.hb_exact_max_digits[i].foreground = true;
        self.hb_exact_max_digits[i].font = "objective";
        self.hb_exact_max_digits[i].alpha = 0;
        hb_safe_set_text(self.hb_exact_max_digits[i], "");
    }

    hb_layout_exact_health_text();
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_update_exact_health_text(currentName, currentHP, maxHP)
// Purpose : Update exact-health mode display: name + current HP + '/' + max HP using digit HUDelems.
// Params  : currentName (string), currentHP (int), maxHP (int)
// Returns : none
// Notes   :
//   - Uses per-digit HUDelems instead of building full '123/456' strings every update.
//   - Calls hb_layout_exact_health_text() to keep anchors consistent when digit counts change.
// ----------------------------------------------------------------------------------------------------
hb_update_exact_health_text(currentName, currentHP, maxHP)
{
    self hb_ensure_exact_health_text();

    if (!isdefined(self.hb_exact_cur_digits) || !isdefined(self.hb_exact_max_digits))
        return;

    // Update digit characters first (safe finite text set) and get visible digit counts.
    curDigitsShown = hb_set_number_digits_right(self.hb_exact_cur_digits, currentHP);
    maxDigitsShown = hb_set_number_digits_left(self.hb_exact_max_digits, maxHP);

    if (curDigitsShown < 1) curDigitsShown = 1;
    if (maxDigitsShown < 1) maxDigitsShown = 1;

    y = self.barY - 4;
    spacing = int(5 * self.sizeN);
    if (spacing < 4)
        spacing = 4;

    slashGap = int(5 * self.sizeN);
    if (slashGap < 4)
        slashGap = 4;

    // Match the static layout: visible space on BOTH sides of the slash (125 / 150)
    slashPad = int(2 * self.sizeN);
    if (slashPad < 2)
        slashPad = 2;

    preSlashGap = slashGap + slashPad;
    postSlashGap = slashGap + slashPad;

    currentRightX = int(14 * self.sizeN);
    if (currentRightX < 10)
        currentRightX = 10;

    slashX = currentRightX + preSlashGap;
    maxLeftX = slashX + postSlashGap;

    // Keep the name anchored in a fixed spot so it doesn't move when HP changes
    // (e.g. 158 -> 58). Reserve space for up to 5 current-HP digits.
    reservedCurDigits = 5;
    nameRightX = currentRightX - ((reservedCurDigits - 1) * spacing) - int(3 * self.sizeN);

    // Re-apply per-update positions with fixed anchors so the layout stays stable.
    if (isdefined(self.hb_exact_name))
    {
        self.hb_exact_name.horzalign = "center";
        self.hb_exact_name.vertalign = "middle";
        self.hb_exact_name.alignx = "right";
        self.hb_exact_name.aligny = "bottom";
        self.hb_exact_name.x = nameRightX;
        self.hb_exact_name.y = y;
        self.hb_exact_name.fontscale = self.sizeN;
    }

    if (isdefined(self.hb_exact_slash))
    {
        self.hb_exact_slash.horzalign = "center";
        self.hb_exact_slash.vertalign = "middle";
        self.hb_exact_slash.alignx = "center";
        self.hb_exact_slash.aligny = "bottom";
        self.hb_exact_slash.x = slashX;
        self.hb_exact_slash.y = y;
        self.hb_exact_slash.fontscale = self.sizeN;
    }

    if (isdefined(self.hb_exact_cur_digits))
    {
        curSlots = self.hb_exact_cur_digits.size;
        for (i = 0; i < curSlots; i++)
        {
            if (!isdefined(self.hb_exact_cur_digits[i]))
                continue;
            self.hb_exact_cur_digits[i].horzalign = "center";
            self.hb_exact_cur_digits[i].vertalign = "middle";
            self.hb_exact_cur_digits[i].alignx = "center";
            self.hb_exact_cur_digits[i].aligny = "bottom";
            self.hb_exact_cur_digits[i].x = currentRightX - ((curSlots - 1 - i) * spacing);
            self.hb_exact_cur_digits[i].y = y;
            self.hb_exact_cur_digits[i].fontscale = self.sizeN;
        }
    }

    if (isdefined(self.hb_exact_max_digits))
    {
        maxSlots = self.hb_exact_max_digits.size;
        for (i = 0; i < maxSlots; i++)
        {
            if (!isdefined(self.hb_exact_max_digits[i]))
                continue;
            self.hb_exact_max_digits[i].horzalign = "center";
            self.hb_exact_max_digits[i].vertalign = "middle";
            self.hb_exact_max_digits[i].alignx = "center";
            self.hb_exact_max_digits[i].aligny = "bottom";
            self.hb_exact_max_digits[i].x = maxLeftX + (i * spacing);
            self.hb_exact_max_digits[i].y = y;
            self.hb_exact_max_digits[i].fontscale = self.sizeN;
        }
    }

    if (self.zombieNAME == 1)
        hb_safe_set_text(self.hb_exact_name, currentName);
    else
        hb_safe_set_text(self.hb_exact_name, "");

    self hb_show_exact_health_text();
}

// ====================================================================================================
// ZOMBIE NAMING + LABEL BUILDERS
//   Name assignment is cached per-zombie so the same zombie keeps the same display name.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: hb_get_zombie_name(zombie)
// Purpose : Return a stable display name for a zombie entity (and cache it on the zombie).
// Params  : zombie (entity)
// Returns : string name
// Notes   :
//   - Name assignment is done once per zombie, then reused to avoid extra work and to keep names consistent.
// ----------------------------------------------------------------------------------------------------
hb_get_zombie_name(zombie)
{
    zombieNames = [];
    zombieNames[0] = "^1Alex";
    zombieNames[1] = "^2Bobby";
    zombieNames[2] = "^3Charlie";
    zombieNames[3] = "^4Daisy";
    zombieNames[4] = "^5Ella";
    zombieNames[5] = "^6Frank";
    zombieNames[6] = "^7Grace";
    zombieNames[7] = "^8Hank";
    zombieNames[8] = "^9Ivy";
    zombieNames[9] = "^1Jack";
    zombieNames[10] = "^2Kara";
    zombieNames[11] = "^3Liam";
    zombieNames[12] = "^4Mia";
    zombieNames[13] = "^5Nate";
    zombieNames[14] = "^6Olivia";
    zombieNames[15] = "^7Paul";
    zombieNames[16] = "^8Quinn";
    zombieNames[17] = "^9Riley";
    zombieNames[18] = "^1Sam";
    zombieNames[19] = "^2Tina";
    zombieNames[20] = "^3Ursula";
    zombieNames[21] = "^4Victor";
    zombieNames[22] = "^5Wendy";
    zombieNames[23] = "^6Xander";

    if (!isdefined(zombie._hb_name))
    {
        if (!isdefined(level._hb_next_name_index))
            level._hb_next_name_index = 0;

        idx = level._hb_next_name_index;
        if (idx < 0)
            idx = 0;

        if (idx >= zombieNames.size)
            idx = idx % zombieNames.size;

        zombie._hb_name = zombieNames[idx];
        level._hb_next_name_index = idx + 1;
        if (level._hb_next_name_index >= zombieNames.size)
            level._hb_next_name_index = 0;
    }

    return zombie._hb_name;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_bucket_percent(pct, bucketSize)
// Purpose : Clamp and bucket a percent value into steps (e.g., 0,10,20,...).
// Params  : pct (int), bucketSize (int)
// Returns : bucketed percent (int)
// Notes   :
//   - Bucketed percent greatly reduces the number of unique strings created over time.
// ----------------------------------------------------------------------------------------------------
hb_bucket_percent(pct, bucketSize)
{
    if (bucketSize <= 0)
        bucketSize = 10;

    if (pct < 0)
        pct = 0;
    if (pct > 100)
        pct = 100;

    bucket = int(pct / bucketSize) * bucketSize;
    if (bucket > 100)
        bucket = 100;
    if (bucket < 0)
        bucket = 0;

    return bucket;
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_build_zombie_text(player, zombie, currentName, totalHealth, isDead)
// Purpose : Build the zombie text label shown above the bar (name toggle + percent or other info).
// Params  : player, zombie, currentName, totalHealth, isDead
// Returns : string
// Notes   :
//   - Text output is designed to be low-entropy (bucketed) unless exact-health mode is enabled.
// ----------------------------------------------------------------------------------------------------
hb_build_zombie_text(player, zombie, currentName, totalHealth, isDead)
{
    if (isDead)
    {
        if(player.langLEN == 1)
            return currentName + " ^1DEAD";
        return currentName + " ^1MUERTO";
    }

    if (!isdefined(totalHealth) || totalHealth <= 0)
        totalHealth = zombie.maxhealth;

    if (totalHealth <= 0)
        totalHealth = 1;

    mode = 1;
    if (isdefined(player.hb_text_mode))
        mode = player.hb_text_mode;

    if (mode == 0)
        return currentName;

    if (mode == 2)
    {
        if(player.zombieNAME == 1)
            return currentName + " ^7" + zombie.health + "/" + totalHealth;
        return "^7" + zombie.health + "/" + totalHealth;
    }

    pct = int((zombie.health * 100) / totalHealth);
    bucketSize = 10;
    if (isdefined(player.hb_pct_bucket))
        bucketSize = player.hb_pct_bucket;

    pctBucket = hb_bucket_percent(pct, bucketSize);

    if(player.zombieNAME == 1)
        return currentName + " ^7" + pctBucket + "%";

    return "^7" + pctBucket + "%";
}

// ----------------------------------------------------------------------------------------------------
// Function: hb_start_destroy_healthbar_delayed(fadeTime)
// Purpose : Restart the fade/destroy timer for the zombie bar (prevents multiple destroy threads fighting).
// Params  : fadeTime (float seconds)
// Returns : none
// Notes   :
//   - Uses a notify-based reset so only the newest destroy thread is active.
// ----------------------------------------------------------------------------------------------------
hb_start_destroy_healthbar_delayed(fadeTime)
{
    self notify("hb_destroy_healthbar_reset");
    self thread destroyHealthBarDelayed(fadeTime);
}

// ====================================================================================================
// PLAYER LIFECYCLE + CALLBACK REGISTRATION
//   Connect/spawn hooks live here. This is also where hitmarker HUD elements are created.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: on_player_connect_player()
// Purpose : Global connect loop. Registers zombie damage/death callbacks and sets up per-player hitmarker HUD.
// Params  : none (waits for 'connected', player)
// Returns : none
// Notes   :
//   - Precaches shaders once, then loops forever waiting for players to connect.
//   - Also starts the per-player spawn loop for defaults and player bar monitoring.
// ----------------------------------------------------------------------------------------------------
on_player_connect_player()
{
    self endon( "end_game" );
    precacheshader( "damage_feedback" );
    precacheshader( "white" );
    self maps\mp\zombies\_zm_spawner::register_zombie_damage_callback(::do_hitmarker);
    self maps\mp\zombies\_zm_spawner::register_zombie_death_event_callback(::do_hitmarker_death);
    for (;;)
    {
        level waittill( "connected", player );
        player thread on_players_spawned();

        player.definido_comandos = 0;
        player.zombieDeathCounter = 0;

        player.hud_damagefeedback = newdamageindicatorhudelem( player );
        player.hud_damagefeedback.horzalign = "center";
        player.hud_damagefeedback.vertalign = "middle";
        player.hud_damagefeedback.x = -12;
        player.hud_damagefeedback.y = -12;
        player.hud_damagefeedback.alpha = 0;
        player.hud_damagefeedback.archived = 1;
        player.hud_damagefeedback.color = ( 1, 1, 1 );
        player.hud_damagefeedback setshader( "damage_feedback", 24, 48 );
        player.hud_damagefeedback_red = newdamageindicatorhudelem( player );
        player.hud_damagefeedback_red.horzalign = "center";
        player.hud_damagefeedback_red.vertalign = "middle";
        player.hud_damagefeedback_red.x = -12;
        player.hud_damagefeedback_red.y = -12;
        player.hud_damagefeedback_red.alpha = 0;
        player.hud_damagefeedback_red.archived = 1;
        player.hud_damagefeedback_red.color = ( 1, 0, 0 );
        player.hud_damagefeedback_red setshader( "damage_feedback", 24, 48 );
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: on_players_spawned()
// Purpose : Per-player spawn loop. Sets defaults (sizes, language, safe text mode) and starts monitors.
// Params  : none (runs on player via thread)
// Returns : none
// Notes   :
//   - Defaults live here so they reset cleanly each time the player spawns.
// ----------------------------------------------------------------------------------------------------
on_players_spawned()
{
    self endon( "disconnect" );
    for (;;)
    {
        self waittill( "spawned_player" );
        self.definido_comandos = 0;
        self.shaderON = 0.8;
        self.zombieNAME = 1;
        self.sizeW = 80;
        self.sizeH = 5;
        self.sizeN = 1;
        self.langLEN = 1;
        self.barY = -60;
        self.playerBarW = 140;
        self.playerBarH = 8;
        self.playerBarON = 1;

        // safer defaults to prevent SG_FindConfigstringIndex overflow from live hp text spam
        self.hb_text_mode = 2;      // 0=name only, 1=bucketed %, 2=exact hp/max (safe digits renderer default)
        self.hb_pct_bucket = 10;    // 10% steps = 11 possible values
        self.hb_text_min_interval = 0.08;
        self.hb_next_text_update_time = 0;

        self thread playerHealthBarMonitor();
    }
}

// ====================================================================================================
// HITMARKERS + EVENT ROUTING
//   Zombie damage/death callbacks route here to update HUD and bar state.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: updatedamagefeedback(mod, inflictor, death)
// Purpose : Core hit feedback handler. Plays sound, shows hitmarker HUD, and triggers zombie bar updates.
// Params  : mod, inflictor, death
// Returns : 0 (convention)
// Notes   :
//   - Death flag controls red hitmarker path and also triggers a final 'dead' bar update.
// ----------------------------------------------------------------------------------------------------
updatedamagefeedback( mod, inflictor, death )
{
    if( IsDefined( self.disable_hitmarkers ) || !(isplayer( self )) )
    {
        return;
    }

    if( mod != "MOD_HIT_BY_OBJECT" && mod != "MOD_GRENADE_SPLASH" && mod != "MOD_CRUSH" && IsDefined( mod ) )
    {
        if( IsDefined( inflictor ) )
        {
            self playlocalsound( "mpl_hit_alert" );
        }

        if( getdvarintdefault( "redhitmarkers", 1 ) && death )
        {
            self.hud_damagefeedback_red setshader( "damage_feedback", 24, 48 );
            self.hud_damagefeedback_red.alpha = 1;
            self.hud_damagefeedback_red fadeovertime( 1 );
            self.hud_damagefeedback_red.alpha = 0;
            self.zombieDeathCounter++;

            self hud_show_zombie_health(self.targetZombie, true);
        }
        else
        {
            self.hud_damagefeedback setshader( "damage_feedback", 24, 48 );
            self.hud_damagefeedback.alpha = 1;
            self.hud_damagefeedback fadeovertime( 1 );
            self.hud_damagefeedback.alpha = 0;
        }

        if (IsDefined(self.targetZombie) && isalive(self.targetZombie))
        {
            self hud_show_zombie_health(self.targetZombie, false);
        }
    }
    return 0;
}

// ----------------------------------------------------------------------------------------------------
// Function: do_hitmarker_death()
// Purpose : Zombie spawner callback for deaths. Routes the event to the attacker’s updatedamagefeedback().
// Params  : none (uses self fields like attacker, damagemod)
// Returns : 0
// Notes   :
//   - Registered via register_zombie_death_event_callback().
// ----------------------------------------------------------------------------------------------------
do_hitmarker_death()
{
    if( self.attacker != self && isplayer( self.attacker ) && IsDefined( self.attacker ) )
    {
        self.attacker thread updatedamagefeedback( self.damagemod, self.attacker, 1 );
    }
    return 0;
}

// ----------------------------------------------------------------------------------------------------
// Function: do_hitmarker(mod, hitloc, hitorig, player, damage)
// Purpose : Zombie spawner callback for damage. Stores targetZombie on the attacker and triggers feedback.
// Params  : mod, hitloc, hitorig, player, damage
// Returns : 0
// Notes   :
//   - Registered via register_zombie_damage_callback().
// ----------------------------------------------------------------------------------------------------
do_hitmarker( mod, hitloc, hitorig, player, damage )
{
    if( player != self && isplayer( player ) && IsDefined( player ) )
    {
        player.targetZombie = self;
        player thread updatedamagefeedback( mod, player, 0 );
    }
    return 0;
}

// ====================================================================================================
// ZOMBIE HEALTH BAR HUD
//   Creates the bar lazily, then updates width/color/text when you damage a zombie.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: hud_show_zombie_health(zombie, isDead)
// Purpose : Create/update the zombie health bar HUD (outline, bg, fg fill, and text).
// Params  : zombie (entity), isDead (bool)
// Returns : none
// Notes   :
//   - Creates HUD elements lazily (first call), then only updates sizing/color/text.
//   - Text updates are throttled and optionally rendered with safe digit elements for exact health.
// ----------------------------------------------------------------------------------------------------
hud_show_zombie_health(zombie, isDead)
{
    self endon("disconnect");
    level endon("end_game");
    // Zombie names are assigned once per zombie and can be edited in hb_get_zombie_name() above.

    if (!isdefined(zombie))
        return;

    halfW = int(self.sizeW / 2);
    barY = self.barY;

    if (!isdefined(self.hud_zombie_health_outline))
    {
        self.hud_zombie_health_outline = newclienthudelem(self);
        self.hud_zombie_health_outline.horzalign = "center";
        self.hud_zombie_health_outline.vertalign = "middle";
        self.hud_zombie_health_outline.x = -(halfW) - 1;
        self.hud_zombie_health_outline.y = barY - 1;
        self.hud_zombie_health_outline.alpha = self.shaderON;
        self.hud_zombie_health_outline.color = (0.6, 0.6, 0.6);
        self.hud_zombie_health_outline setshader("white", self.sizeW + 2, self.sizeH + 2);
        self.hud_zombie_health_outline.sort = 0;
        self.hud_zombie_health_outline.hidewheninmenu = true;
        self.hud_zombie_health_outline.archived = false;
        self.hud_zombie_health_outline.foreground = true;

        self.hud_zombie_health_bg = newclienthudelem(self);
        self.hud_zombie_health_bg.horzalign = "center";
        self.hud_zombie_health_bg.vertalign = "middle";
        self.hud_zombie_health_bg.x = -(halfW);
        self.hud_zombie_health_bg.y = barY;
        self.hud_zombie_health_bg.alpha = self.shaderON;
        self.hud_zombie_health_bg.color = (0.08, 0.08, 0.08);
        self.hud_zombie_health_bg setshader("white", self.sizeW, self.sizeH);
        self.hud_zombie_health_bg.sort = 1;
        self.hud_zombie_health_bg.hidewheninmenu = true;
        self.hud_zombie_health_bg.archived = false;
        self.hud_zombie_health_bg.foreground = true;

        self.hud_zombie_health_fg = newclienthudelem(self);
        self.hud_zombie_health_fg.horzalign = "center";
        self.hud_zombie_health_fg.vertalign = "middle";
        self.hud_zombie_health_fg.x = -(halfW);
        self.hud_zombie_health_fg.y = barY;
        self.hud_zombie_health_fg.alpha = 1;
        self.hud_zombie_health_fg.color = (0.1, 0.9, 0.1);
        self.hud_zombie_health_fg setshader("white", self.sizeW, self.sizeH);
        self.hud_zombie_health_fg.sort = 2;
        self.hud_zombie_health_fg.hidewheninmenu = true;
        self.hud_zombie_health_fg.archived = false;
        self.hud_zombie_health_fg.foreground = true;

        self.hud_zombie_health_text = newclienthudelem(self);
        self.hud_zombie_health_text.horzalign = "center";
        self.hud_zombie_health_text.vertalign = "middle";
        self.hud_zombie_health_text.alignx = "center";
        self.hud_zombie_health_text.aligny = "bottom";
        self.hud_zombie_health_text.x = 0;
        self.hud_zombie_health_text.y = barY - 4;
        self.hud_zombie_health_text.alpha = 1;
        self.hud_zombie_health_text.fontscale = self.sizeN;
        self.hud_zombie_health_text.sort = 3;
        self.hud_zombie_health_text.hidewheninmenu = true;
        self.hud_zombie_health_text.archived = false;
        self.hud_zombie_health_text.foreground = true;
        self.hud_zombie_health_text.font = "objective";

        self thread configbar();
        self hb_ensure_exact_health_text();
        self hb_hide_exact_health_text();
    }
    currentName = hb_get_zombie_name(zombie);

    if (isDead)
    {
        self.hud_zombie_health_fg setshader("white", 1, self.sizeH);
        self.hud_zombie_health_fg.color = (0.6, 0, 0);

        self hb_hide_exact_health_text();
        self.hud_zombie_health_text.alpha = 1;
        hb_safe_set_text(self.hud_zombie_health_text, hb_build_zombie_text(self, zombie, currentName, 1, true));

        hb_start_destroy_healthbar_delayed(2.0);
    }
    else
    {
        totalHealth = zombie.maxhealth;
        damageInflicted = totalHealth - zombie.health;
        healthFraction = zombie.health / totalHealth;
        barWidth = int(self.sizeW * healthFraction);
        if (barWidth < 1)
            barWidth = 1;

        self.hud_zombie_health_fg setshader("white", barWidth, self.sizeH);

        if (healthFraction > 0.65)
            self.hud_zombie_health_fg.color = (0.1, 0.9, 0.1);
        else if (healthFraction > 0.4)
            self.hud_zombie_health_fg.color = (0.9, 0.9, 0.1);
        else if (healthFraction > 0.2)
            self.hud_zombie_health_fg.color = (0.9, 0.5, 0.05);
        else
            self.hud_zombie_health_fg.color = (0.9, 0.1, 0.1);

        // Throttle and bucket text updates to avoid configstring overflow crashes.
        doTextUpdate = true;
        if (isdefined(self.hb_next_text_update_time))
        {
            if (getTime() < self.hb_next_text_update_time)
                doTextUpdate = false;
        }

        if (doTextUpdate)
        {
            if (!isdefined(self.hb_text_min_interval))
                self.hb_text_min_interval = 0.08;

            self.hb_next_text_update_time = getTime() + int(self.hb_text_min_interval * 1000);

            if (isdefined(self.hb_text_mode) && self.hb_text_mode == 2)
            {
                self.hud_zombie_health_text.alpha = 0;
                self hb_update_exact_health_text(currentName, zombie.health, totalHealth);
            }
            else
            {
                self hb_hide_exact_health_text();
                self.hud_zombie_health_text.alpha = 1;
                hb_safe_set_text(self.hud_zombie_health_text, hb_build_zombie_text(self, zombie, currentName, totalHealth, false));
            }
        }
    }

    if (!isDead && zombie.health == zombie.maxhealth)
    {
        hb_start_destroy_healthbar_delayed(1.5);
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: destroyHealthBarDelayed(fadeTime)
// Purpose : Fade out and destroy zombie health bar HUDelems after a delay.
// Params  : fadeTime (float seconds)
// Returns : none
// Notes   :
//   - Guarded by endon() and hb_destroy_healthbar_reset notify so it is safe to restart.
// ----------------------------------------------------------------------------------------------------
destroyHealthBarDelayed(fadeTime)
{
    self endon("disconnect");
    level endon("end_game");
    self endon("hb_destroy_healthbar_reset");

    if (isdefined(self.hud_zombie_health_outline))
    {
        self.hud_zombie_health_outline fadeovertime(fadeTime);
        self.hud_zombie_health_outline.alpha = 0;
    }
    if (isdefined(self.hud_zombie_health_bg))
    {
        self.hud_zombie_health_bg fadeovertime(fadeTime);
        self.hud_zombie_health_bg.alpha = 0;
    }
    if (isdefined(self.hud_zombie_health_fg))
    {
        self.hud_zombie_health_fg fadeovertime(fadeTime);
        self.hud_zombie_health_fg.alpha = 0;
    }
    if (isdefined(self.hud_zombie_health_text))
    {
        self.hud_zombie_health_text fadeovertime(fadeTime);
        self.hud_zombie_health_text.alpha = 0;
    }
    if (isdefined(self.hb_exact_name))
    {
        self.hb_exact_name fadeovertime(fadeTime);
        self.hb_exact_name.alpha = 0;
    }
    if (isdefined(self.hb_exact_slash))
    {
        self.hb_exact_slash fadeovertime(fadeTime);
        self.hb_exact_slash.alpha = 0;
    }
    if (isdefined(self.hb_exact_cur_digits))
    {
        for (i = 0; i < self.hb_exact_cur_digits.size; i++)
        {
            if (isdefined(self.hb_exact_cur_digits[i]))
            {
                self.hb_exact_cur_digits[i] fadeovertime(fadeTime);
                self.hb_exact_cur_digits[i].alpha = 0;
            }
        }
    }
    if (isdefined(self.hb_exact_max_digits))
    {
        for (i = 0; i < self.hb_exact_max_digits.size; i++)
        {
            if (isdefined(self.hb_exact_max_digits[i]))
            {
                self.hb_exact_max_digits[i] fadeovertime(fadeTime);
                self.hb_exact_max_digits[i].alpha = 0;
            }
        }
    }

    wait(fadeTime + 0.1);

    if (isdefined(self.hud_zombie_health_outline))
    {
        self.hud_zombie_health_outline destroy();
        self.hud_zombie_health_outline = undefined;
    }
    if (isdefined(self.hud_zombie_health_bg))
    {
        self.hud_zombie_health_bg destroy();
        self.hud_zombie_health_bg = undefined;
    }
    if (isdefined(self.hud_zombie_health_fg))
    {
        self.hud_zombie_health_fg destroy();
        self.hud_zombie_health_fg = undefined;
    }
    if (isdefined(self.hud_zombie_health_text))
    {
        self.hud_zombie_health_text destroy();
        self.hud_zombie_health_text = undefined;
    }
    if (isdefined(self.hb_exact_name))
    {
        self.hb_exact_name destroy();
        self.hb_exact_name = undefined;
    }
    if (isdefined(self.hb_exact_slash))
    {
        self.hb_exact_slash destroy();
        self.hb_exact_slash = undefined;
    }
    if (isdefined(self.hb_exact_cur_digits))
    {
        for (i = 0; i < self.hb_exact_cur_digits.size; i++)
        {
            if (isdefined(self.hb_exact_cur_digits[i]))
                self.hb_exact_cur_digits[i] destroy();
        }
        self.hb_exact_cur_digits = undefined;
    }
    if (isdefined(self.hb_exact_max_digits))
    {
        for (i = 0; i < self.hb_exact_max_digits.size; i++)
        {
            if (isdefined(self.hb_exact_max_digits[i]))
                self.hb_exact_max_digits[i] destroy();
        }
        self.hb_exact_max_digits = undefined;
    }
}

//__________________________________________________________________________________________[PLAYER HEALTH BAR]___________________________________________________________________________________________//

// ====================================================================================================
// PLAYER HEALTH BAR HUD
//   Separate from the zombie bar: shows your own health in a consistent spot if enabled.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: playerHealthBarMonitor()
// Purpose : Create/update a player health bar HUD (separate from zombie bar).
// Params  : none
// Returns : none
// Notes   :
//   - Runs in a loop; reacts to player health changes and calls pulse/cleanup as needed.
// ----------------------------------------------------------------------------------------------------
playerHealthBarMonitor()
{
    self endon("disconnect");
    level endon("end_game");

    if (self.playerBarON != 1)
        return;

    wait(0.5);

    pBarW = self.playerBarW;
    pBarH = self.playerBarH;
    pBarX = 12;
    pBarY = -42;

    self.phb_outline = newclienthudelem(self);
    self.phb_outline.horzalign = "left";
    self.phb_outline.vertalign = "bottom";
    self.phb_outline.x = pBarX - 1;
    self.phb_outline.y = pBarY - 1;
    self.phb_outline.alpha = 0;
    self.phb_outline.color = (0.6, 0.6, 0.6);
    self.phb_outline setshader("white", pBarW + 2, pBarH + 2);
    self.phb_outline.sort = 0;
    self.phb_outline.hidewheninmenu = true;
    self.phb_outline.archived = false;
    self.phb_outline.foreground = true;

    self.phb_bg = newclienthudelem(self);
    self.phb_bg.horzalign = "left";
    self.phb_bg.vertalign = "bottom";
    self.phb_bg.x = pBarX;
    self.phb_bg.y = pBarY;
    self.phb_bg.alpha = 0;
    self.phb_bg.color = (0.08, 0.08, 0.08);
    self.phb_bg setshader("white", pBarW, pBarH);
    self.phb_bg.sort = 1;
    self.phb_bg.hidewheninmenu = true;
    self.phb_bg.archived = false;
    self.phb_bg.foreground = true;

    self.phb_fg = newclienthudelem(self);
    self.phb_fg.horzalign = "left";
    self.phb_fg.vertalign = "bottom";
    self.phb_fg.x = pBarX;
    self.phb_fg.y = pBarY;
    self.phb_fg.alpha = 0;
    self.phb_fg.color = (0.1, 0.9, 0.1);
    self.phb_fg setshader("white", pBarW, pBarH);
    self.phb_fg.sort = 2;
    self.phb_fg.hidewheninmenu = true;
    self.phb_fg.archived = false;
    self.phb_fg.foreground = true;

    self.phb_text = newclienthudelem(self);
    self.phb_text.horzalign = "left";
    self.phb_text.vertalign = "bottom";
    self.phb_text.alignx = "left";
    self.phb_text.aligny = "bottom";
    self.phb_text.x = pBarX;
    self.phb_text.y = pBarY - pBarH - 2;
    self.phb_text.alpha = 0;
    self.phb_text.fontscale = 1;
    self.phb_text.sort = 3;
    self.phb_text.hidewheninmenu = true;
    self.phb_text.archived = false;
    self.phb_text.foreground = true;
    self.phb_text.font = "objective";

    // Right-side percent text removed by request (keep only left HP current/max text).
    self.phb_pct = undefined;

    self.phb_outline fadeovertime(0.5);
    self.phb_outline.alpha = 0.8;
    self.phb_bg fadeovertime(0.5);
    self.phb_bg.alpha = 0.8;
    self.phb_fg fadeovertime(0.5);
    self.phb_fg.alpha = 1;
    self.phb_text fadeovertime(0.5);
    self.phb_text.alpha = 1;
    // self.phb_pct removed

    lastHP = -1;
    lastMaxHP = -1;
    maxHP = self.maxhealth;
    pulseActive = false;

    while (isalive(self))
    {
        if (self.playerBarON != 1)
        {
            self thread destroyPlayerHealthBar();
            return;
        }

        currentHP = self.health;
        maxHP = self.maxhealth;

        if (currentHP != lastHP || maxHP != lastMaxHP)
        {
            lastHP = currentHP;
            lastMaxHP = maxHP;
            healthFraction = currentHP / maxHP;
            pctValue = int(healthFraction * 100);
            barWidth = int(self.playerBarW * healthFraction);
            if (barWidth < 1)
                barWidth = 1;

            if (isdefined(self.phb_fg))
            {
                self.phb_fg setshader("white", barWidth, self.playerBarH);

                if (healthFraction > 0.65)
                    self.phb_fg.color = (0.1, 0.9, 0.1);
                else if (healthFraction > 0.4)
                    self.phb_fg.color = (0.9, 0.9, 0.1);
                else if (healthFraction > 0.2)
                    self.phb_fg.color = (0.9, 0.5, 0.05);
                else
                    self.phb_fg.color = (0.9, 0.1, 0.1);
            }

            if (isdefined(self.phb_text))
                hb_safe_set_text(self.phb_text, "^7HP " + currentHP + "^7/" + maxHP);

            // Right-side percent text removed by request.

            if (healthFraction <= 0.2 && !pulseActive)
            {
                pulseActive = true;
                self thread playerHealthPulse();
            }
            else if (healthFraction > 0.2)
            {
                pulseActive = false;
                self notify("end_player_pulse");
                if (isdefined(self.phb_outline))
                    self.phb_outline.color = (0.6, 0.6, 0.6);
            }
        }

        wait 0.1;
    }

    self thread destroyPlayerHealthBar();
}

// ----------------------------------------------------------------------------------------------------
// Function: playerHealthPulse()
// Purpose : Small pulse animation for the player health bar to draw attention (e.g., on damage / low health).
// Params  : none
// Returns : none
// Notes   :
//   - Visual-only; should never affect gameplay.
// ----------------------------------------------------------------------------------------------------
playerHealthPulse()
{
    self endon("disconnect");
    level endon("end_game");
    self endon("end_player_pulse");

    while (true)
    {
        if (isdefined(self.phb_outline))
        {
            self.phb_outline.color = (0.9, 0.1, 0.1);
            self.phb_outline fadeovertime(0.4);
            self.phb_outline.alpha = 1;
        }
        wait(0.4);
        if (isdefined(self.phb_outline))
        {
            self.phb_outline fadeovertime(0.4);
            self.phb_outline.alpha = 0.3;
        }
        wait(0.4);
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: destroyPlayerHealthBar()
// Purpose : Destroy the player's own health bar HUDelems and clear cached references.
// Params  : none
// Returns : none
// Notes   :
//   - Called when disabling the player bar or when cleaning up on disconnect.
// ----------------------------------------------------------------------------------------------------
destroyPlayerHealthBar()
{
    self endon("disconnect");
    level endon("end_game");

    if (isdefined(self.phb_outline))
    {
        self.phb_outline fadeovertime(0.3);
        self.phb_outline.alpha = 0;
    }
    if (isdefined(self.phb_bg))
    {
        self.phb_bg fadeovertime(0.3);
        self.phb_bg.alpha = 0;
    }
    if (isdefined(self.phb_fg))
    {
        self.phb_fg fadeovertime(0.3);
        self.phb_fg.alpha = 0;
    }
    if (isdefined(self.phb_text))
    {
        self.phb_text fadeovertime(0.3);
        self.phb_text.alpha = 0;
    }
    if (isdefined(self.phb_pct))
    {
        self.phb_pct fadeovertime(0.3);
        self.phb_pct.alpha = 0;
    }

    wait(0.4);

    self notify("end_player_pulse");

    if (isdefined(self.phb_outline))
    {
        self.phb_outline destroy();
        self.phb_outline = undefined;
    }
    if (isdefined(self.phb_bg))
    {
        self.phb_bg destroy();
        self.phb_bg = undefined;
    }
    if (isdefined(self.phb_fg))
    {
        self.phb_fg destroy();
        self.phb_fg = undefined;
    }
    if (isdefined(self.phb_text))
    {
        self.phb_text destroy();
        self.phb_text = undefined;
    }
    if (isdefined(self.phb_pct))
    {
        self.phb_pct destroy();
        self.phb_pct = undefined;
    }
}

//________________________________________________________________________________________________________________________________________________________________________________________________________//

// ----------------------------------------------------------------------------------------------------
// Function: configbar()
// Purpose : Apply runtime config values to the active zombie health bar (shader alpha, sizes, font scale, etc.).
// Params  : none
// Returns : none
// Notes   :
//   - Designed to be called once after creating HUD elements, then updated via threads/commands.
// ----------------------------------------------------------------------------------------------------
configbar()
{
    self endon("disconnect");
    level endon("end_game");
    while(true)
    {
        halfW = int(self.sizeW / 2);
        barY = self.barY;

        if (isdefined(self.hud_zombie_health_outline))
        {
            self.hud_zombie_health_outline.x = -(halfW) - 1;
            self.hud_zombie_health_outline.y = barY - 1;
            self.hud_zombie_health_outline setshader("white", self.sizeW + 2, self.sizeH + 2);
            self.hud_zombie_health_outline.alpha = self.shaderON;
        }
        if (isdefined(self.hud_zombie_health_bg))
        {
            self.hud_zombie_health_bg.x = -(halfW);
            self.hud_zombie_health_bg.y = barY;
            self.hud_zombie_health_bg setshader("white", self.sizeW, self.sizeH);
            self.hud_zombie_health_bg.alpha = self.shaderON;
        }
        if (isdefined(self.hud_zombie_health_fg))
        {
            self.hud_zombie_health_fg.x = -(halfW);
            self.hud_zombie_health_fg.y = barY;
        }
        if (isdefined(self.hud_zombie_health_text))
        {
            self.hud_zombie_health_text.fontscale = self.sizeN;
            self.hud_zombie_health_text.y = barY - 4;
        }
        self hb_layout_exact_health_text();
        wait 0.5;
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: colorBAR(varN)
// Purpose : Continuously apply a chosen color preset (or cycling color list) to the bar foreground.
// Params  : varN (int preset index)
// Returns : none
// Notes   :
//   - Runs until 'end_colorBAR' notify is received.
// ----------------------------------------------------------------------------------------------------
colorBAR(varN)
{
    self endon("disconnect");
    level endon("end_game");
    self endon("end_colorBAR");

    colorbarlist = [];
    colorbarlist[0] = (1, 0, 0);
    colorbarlist[1] = (0, 1, 0);
    colorbarlist[2] = (0, 0, 1);
    colorbarlist[3] = (1, 1, 0);
    colorbarlist[4] = (1, 0, 1);
    colorbarlist[5] = (0, 1, 1);
    colorbarlist[6] = (1, 1, 1);
    colorbarlist[7] = (0, 0, 0);
    colorbarlist[8] = (0.5, 0, 0);
    colorbarlist[9] = (0, 0.5, 0);
    colorbarlist[10] = (0, 0, 0.5);
    colorbarlist[11] = (0.5, 0.5, 0);
    colorbarlist[12] = (0.5, 0, 0.5);
    colorbarlist[13] = (0, 0.5, 0.5);
    colorbarlist[14] = (0.75, 0.75, 0.75);
    colorbarlist[15] = (0.25, 0.25, 0.25);
    colorbarlist[16] = (1, 0.5, 0);
    colorbarlist[17] = (0.5, 0.25, 0);
    colorbarlist[18] = (1, 0.75, 0.8);
    colorbarlist[19] = (0.5, 0, 0.25);
    colorbarlist[20] = (0.5, 1, 0.5);

    while (true)
    {
        if (isDefined(self.hud_zombie_health_fg))
        {
            if (varN == 0)
            {
                randomIndex = randomint(colorbarlist.size);
                self.hud_zombie_health_fg.color = colorbarlist[randomIndex];
            }
            else if (varN >= 1 && varN <= 21)
            {
                self.hud_zombie_health_fg.color = colorbarlist[varN - 1];
            }
        }
        wait(0.5);
    }
}

// ====================================================================================================
// CHAT COMMANDS
//   Prefix is '#'. Commands are parsed case-insensitively by lowercasing the message.
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: onPlayerSay()
// Purpose : Chat listener. Parses messages beginning with '#' and executes supported commands.
// Params  : none
// Returns : none
// Notes   :
//   - Commands: #barzm, #help, #lang. All parsing is lowercased for consistency.
// ----------------------------------------------------------------------------------------------------
onPlayerSay()
{
    level endon("end_game");
    prefix = "#";
    for (;;)
    {
        level waittill("say", message, player);
        message = toLower(message);
        guild_name = player getGuid();
        if (!level.intermission && message[0] == prefix)
        {
            args = strtok(message, " ");
            command = getSubStr(args[0], 1);
            switch (command)
            {
            case "barzm":
                if (!isDefined(args[1]))
                {
                    player tell("^1ERROR: Command missing parameters.");
                    continue;
                }
                executeBarzmCommand(args, player);
                break;
            case "help":
                player thread helpcommand();
                break;
            case "lang":
                if (!isDefined(args[1]))
                {
                    player tell("^1ERROR: Command missing parameters.");
                    continue;
                }
                updateLanguage(args, player);
                break;
            default:
                player tell("^1ERROR: Unknown command.");
                break;
            }
        }
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: executeBarzmCommand(args, player)
// Purpose : Dispatcher for '#barzm' subcommands.
// Params  : args (array), player (entity)
// Returns : none
// Notes   :
//   - Routes to updateColor/updateNameZombie/updateSizeW/updateSizeH/updateSizeN/updateShader.
// ----------------------------------------------------------------------------------------------------
executeBarzmCommand(args, player)
{
    if (args[1] == "color")
    {
        updateColor(args, player);
    }
    else if (args[1] == "name")
    {
        updateNameZombie(args, player);
    }
    else if (args[1] == "sizew")
    {
        updateSizeW(args, player);
    }
    else if (args[1] == "sizeh")
    {
        updateSizeH(args, player);
    }
    else if (args[1] == "sizen")
    {
        updateSizeN(args, player);
    }
    else if (args[1] == "shader")
    {
        updateShader(args, player);
    }
    else
    {
        player tell("^1ERROR: Invalid barzm option.");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateNameZombie(args, player)
// Purpose : Toggle zombie-name display (0=off, 1=on) for the calling player.
// Params  : args, player
// Returns : none
// Notes   :
//   - Also prints a localized confirmation message.
// ----------------------------------------------------------------------------------------------------
updateNameZombie(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm name <value>");
        return;
    }
    varN = int(args[2]);
    if (varN >= 0 && varN <= 1)
    {
        player.zombieNAME = varN;
        if(player.langLEN == 0)
        {
            if(varN == 0)
                player tell("Zombie nombre off");
            else if(varN == 1)
                player tell("Zombie nombre on");
        }
        else if(player.langLEN == 1)
        {
            if(varN == 0)
                player tell("Zombie name off");
            else if(varN == 1)
                player tell("Zombie name on");
        }
    }
    else
    {
        player tell("^1ERROR VALUE -> 0 a 1");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateColor(args, player)
// Purpose : Set the bar color preset and restart the colorBAR thread.
// Params  : args, player
// Returns : none
// Notes   :
//   - Valid range is enforced (0-21).
// ----------------------------------------------------------------------------------------------------
updateColor(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm color <value>");
        return;
    }
    varN = int(args[2]);
    if (varN >= 0 && varN <= 21)
    {
        player notify("end_colorBAR");
        player thread colorBAR(varN);
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateSizeW(args, player)
// Purpose : Set zombie bar width (validated) and print a confirmation.
// Params  : args, player
// Returns : none
// Notes   :
//   - Valid range is enforced (50-105).
// ----------------------------------------------------------------------------------------------------
updateSizeW(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm sizew <value>");
        return;
    }
    varN = int(args[2]);
    if (varN >= 50 && varN <= 105)
    {
        player.sizeW = varN;
        confirmSize("width", varN, player);
    }
    else
    {
        player tell("^1ERROR VALUE -> 50 a 105");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateSizeH(args, player)
// Purpose : Set zombie bar height (validated) and print a confirmation.
// Params  : args, player
// Returns : none
// Notes   :
//   - Valid range is enforced (2-8).
// ----------------------------------------------------------------------------------------------------
updateSizeH(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm sizeh <value>");
        return;
    }
    varN = int(args[2]);
    if (varN >= 2 && varN <= 8)
    {
        player.sizeH = varN;
        confirmSize("height", varN, player);
    }
    else
    {
        player tell("^1ERROR VALUE -> 2 a 8");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateSizeN(args, player)
// Purpose : Set zombie name font scale (validated) and print a confirmation.
// Params  : args, player
// Returns : none
// Notes   :
//   - Valid range is enforced (1.0-1.4).
// ----------------------------------------------------------------------------------------------------
updateSizeN(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm sizen <value>");
        return;
    }
    varN = float(args[2]);
    if (varN >= 1 && varN <= 1.4)
    {
        player.sizeN = varN;
        confirmSize("font size", varN, player);
    }
    else
    {
        player tell("^1ERROR VALUE -> 1 a 1.4");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: updateShader(args, player)
// Purpose : Toggle shader alpha backing for the bar (0=off, 1=on).
// Params  : args, player
// Returns : none
// Notes   :
//   - Maps 0/1 to alpha values (0 or 0.8) and prints a localized confirmation.
// ----------------------------------------------------------------------------------------------------
updateShader(args, player)
{
    if (!isdefined(args[2]))
    {
        player tell("^1ERROR -> ^1#barzm shader <0 - 1>");
        return;
    }
    varN = int(args[2]);
    if (varN >= 0 && varN <= 1)
    {
        if (varN == 0)
            player.shaderON = 0;
        else
            player.shaderON = 0.8;
        confirmShader(varN, player);
    }
    else
    {
        player tell("^1ERROR VALUE -> 0 a 1");
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: confirmSize(type, value, player)
// Purpose : Localized confirmation message for size changes.
// Params  : type (string), value (number), player
// Returns : none
// Notes   :
//   - Pure feedback; does not change settings itself.
// ----------------------------------------------------------------------------------------------------
confirmSize(type, value, player)
{
    if(player.langLEN == 1)
        player tell("^2Bar adjusted: " + type + " " + value);
    else if(player.langLEN == 0)
        player tell("^2Barra ajustada: " + type + " " + value);
}

// ----------------------------------------------------------------------------------------------------
// Function: confirmShader(value, player)
// Purpose : Localized confirmation message for shader toggle.
// Params  : value (int 0/1), player
// Returns : none
// Notes   :
//   - Pure feedback; does not change settings itself.
// ----------------------------------------------------------------------------------------------------
confirmShader(value, player)
{
    if(player.langLEN == 1)
        player tell("^2Shader adjusted: " + value);
    else if(player.langLEN == 0)
        player tell("^2Shader ajustado: " + value);
}

// ----------------------------------------------------------------------------------------------------
// Function: updateLanguage(args, player)
// Purpose : Set language for feedback strings (English or Spanish).
// Params  : args, player
// Returns : none
// Notes   :
//   - Expected usage: #lang en   or   #lang es
// ----------------------------------------------------------------------------------------------------
updateLanguage(args, player)
{
    if (isDefined(args[1]))
    {
        if (args[1] == "en" || args[1] == "EN")
        {
            if (player.langLEN != 1)
            {
                player.langLEN = 1;
                player tell("The script has been translated to English.");
            }
            else
            {
                player tell("The script is already in English.");
            }
        }
        else if (args[1] == "es" || args[1] == "ES")
        {
            if (player.langLEN != 0)
            {
                player.langLEN = 0;
                player tell("El script ha sido traducido al Espanol.");
            }
            else
            {
                player tell("El script ya esta en Espanol.");
            }
        }
    }
}

// ----------------------------------------------------------------------------------------------------
// Function: helpcommand()
// Purpose : Show a small two-page help overlay listing chat commands and ranges.
// Params  : none
// Returns : none
// Notes   :
//   - Uses a short-lived HUD element and a simple lock (definido_comandos) to avoid overlap.
// ----------------------------------------------------------------------------------------------------
helpcommand()
{
    if(self.definido_comandos == 1)
    {
        if(self.langLEN == 1)
            self tell("Wait for the commands to finish displaying");
        else if(self.langLEN == 0)
            self tell("Espera a que se terminen de mostrar los comandos");
    }
    else if(self.definido_comandos == 0)
    {
        self.definido_comandos = 1;

        hud = create_simple_hud_element();
        hud.x = 0.1; hud.y = 0.1; hud.fontScale = 1;

        if(self.langLEN == 1)
            hud setText("^1#^7barzm ^6color ^7<^30-21^7> <- Change color\n^1#^7barzm ^6sizew ^7<^350-105^7> <- Width\n^1#^7barzm ^6name ^7<^30-1^7> <- Zombie Name");
        else if(self.langLEN == 0)
            hud setText("^1#^7barzm ^6color ^7<^30-21^7> <- Cambia color\n^1#^7barzm ^6sizew ^7<^350-105^7> <- Ancho\n^1#^7barzm ^6name ^7<^30-1^7> <- Zombie Nombre");
        wait(10);

        if(self.langLEN == 1)
            hud setText("^1#^7barzm ^6sizeh ^7<^32-8^7> <- Height\n^1#^7barzm ^6sizen ^7<^31-1.4^7> <- Font size\n^3^1#^7barzm ^6shader <^30-1> ^7<- Black shader");
        else if(self.langLEN == 0)
            hud setText("^1#^7barzm ^6sizeh ^7<^32-8^7> <- Altura\n^1#^7barzm ^6sizen ^7<^31-1.4^7> <- Tamano de fuente\n^1#^4barzm ^6shader <^30-1> ^7<- Shader negro");
        wait(10);

        hud destroy();
        self.definido_comandos = 0;
    }
}

// ====================================================================================================
// HUD UTILITIES
// ====================================================================================================

// ----------------------------------------------------------------------------------------------------
// Function: create_simple_hud_element()
// Purpose : Utility helper to create a basic client HUDelem with common defaults.
// Params  : none (uses self as owner)
// Returns : HUDelem
// Notes   :
//   - Used by helpcommand() for the overlay text.
// ----------------------------------------------------------------------------------------------------
create_simple_hud_element()
{
    hudElem = newclienthudelem(self);
    hudElem.elemtype = "icon";
    hudElem.font = "default";
    hudElem.fontscale = 1;
    hudElem.alpha = 1;
    hudElem.alignx = "left";
    hudElem.aligny = "top";
    hudElem.hidewheninmenu = false;
    return hudElem;
}
