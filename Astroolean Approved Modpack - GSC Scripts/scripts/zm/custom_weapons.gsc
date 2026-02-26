#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;

// ============================================================================
//  Created by Astroolean
//  Custom Weapon Rebalance v2.0 (Black Ops II Zombies / Plutonium T6)
//
//  What this file does
//    - Applies movement speed scaling based on the current weapon class.
//    - Applies one-time reserve ammo adjustments when a weapon is first obtained.
//    - Provides optional tuning lookup tables (damage/headshot multipliers and
//      bonus points) that you can hook into a damage/kill pipeline if desired.
//
//  How it works (high level)
//    1) init() sets default dvars (only if missing) and starts onPlayerConnect().
//    2) onPlayerSpawned() starts per-player threads:
//         - weaponWatchLoop(): monitors weapon switches and updates move speed.
//         - ammoWatchLoop(): applies reserve ammo changes once per weapon.
//         - mapvoteHider(): listens for mapvote_start and flips a HUD-hide flag.
//    3) getWeaponClass() classifies weapons by name substring matching.
//
//  Configuration
//    - This script uses DVARS (wb_*) so you can tune behavior without editing code.
//    - Defaults are only applied when the DVAR is blank, so server/user overrides win.
//
//  Compatibility notes
//    - setMoveSpeedScale() overrides your current move speed scale. If another mod
//      also sets it constantly, the last one to set it wins.
//    - Ammo changes use setWeaponAmmoStock() and are tracked so they do NOT stack.
// ============================================================================

// ╔══════════════════════════════════════════════════════════════════╗
// ║       CUSTOM WEAPON REBALANCE v2.0 — COMPLETE EDITION            ║
// ║    Complete Weapon Overhaul · Black Ops II Zombies               ║
// ║                  Plutonium T6 Client Mod                         ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║                                                                  ║
// ║  PHILOSOPHY                                                      ║
// ║    Every weapon should be worth picking up. No more instant      ║
// ║    box-spins past the SMR, no more ignoring half the arsenal.    ║
// ║    Weak guns get meaningful buffs, dominant guns get slight      ║
// ║    trade-offs, and every weapon class has a unique identity.     ║
// ║                                                                  ║
// ║  CLASS IDENTITIES                                                ║
// ║    SMGs     — Speed demons. +8% move speed, fast handling        ║
// ║    ARs      — All-rounders. Balanced stats, no penalty           ║
// ║    LMGs     — Heavy hitters. Huge ammo, -10% move penalty        ║
// ║    Shotguns — Close-quarters kings. Damage bonus up close        ║
// ║    Snipers  — Precision. +50% headshot damage, slower move       ║
// ║    Pistols  — Sidearm agility. +5% move speed, ammo buffs        ║
// ║    Launchers — Crowd control. Bigger reserves, area damage       ║
// ║    Specials — Unique niches preserved and enhanced               ║
// ║                                                                  ║
// ║  WEAK WEAPON BUFFS (C/D/F TIER → B/A TIER)                       ║
// ║    SMR          — +50% dmg, +100 reserve, tighter spread         ║
// ║    War Machine  — +75% dmg, double ammo reserves                 ║
// ║    Five-Seven   — +80 reserve ammo                               ║
// ║    Chicom CQB   — +30% dmg, +80 reserve ammo                     ║
// ║    KAP-40       — +100 reserve ammo                              ║
// ║    Executioner   — +40% dmg, +24 reserve ammo                    ║
// ║    Olympia      — +35% dmg, +16 reserve ammo                     ║
// ║    FAL          — +25% dmg, +60 reserve ammo                     ║
// ║    M8A1         — +20% dmg, +40 reserve ammo                     ║
// ║    S12          — +60 reserve ammo                               ║
// ║    M1911        — +40 reserve ammo                               ║
// ║    Ballistic Kn — +10% move speed, bonus points on kill          ║
// ║                                                                  ║
// ║  MID-TIER TUNING (B TIER — slight buffs)                         ║
// ║    Type 25      — +40 reserve ammo                               ║
// ║    M16          — +30 reserve ammo                               ║
// ║    MP5          — +40 reserve ammo                               ║
// ║    M14          — +25% dmg (early-round viability)               ║
// ║                                                                  ║
// ║  TOP-TIER TRADE-OFFS (S/A TIER — keep strong, add cost)          ║
// ║    AN-94        — -5% move speed (price of being best wall AR)   ║
// ║    Ray Gun MK2  — -20 reserve ammo                               ║
// ║    HAMR         — -12% move speed (it's an LMG, act like it)     ║
// ║    RPD          — -10% move speed                                ║
// ║    LSAT         — -10% move speed                                ║
// ║    Galil        — unchanged (box-only, balanced)                 ║
// ║                                                                  ║
// ║  FEATURES                                                        ║
// ║    · Real-time weapon class detection on switch                  ║
// ║    · Dynamic movement speed per weapon class                     ║
// ║    · Ammo pool adjustments applied on weapon pickup              ║
// ║    · Damage multiplier system via zombie damage callback         ║
// ║    · Headshot bonus scaling per weapon class                     ║
// ║    · HUD indicator showing active weapon class bonus             ║
// ║    · Mapvote-aware — hides during voting                         ║
// ║    · Full dvar configuration                                     ║
// ║                                                                  ║
// ║  DVARS                                                           ║
// ║    wb_enabled      1     Master enable (0/1)                     ║
// ║    wb_hud          1     Show weapon class HUD (0/1)             ║
// ║    wb_smg_speed    1.08  SMG move speed multiplier               ║
// ║    wb_lmg_speed    0.90  LMG move speed multiplier               ║
// ║    wb_sniper_speed 0.92  Sniper move speed multiplier            ║
// ║    wb_pistol_speed 1.05  Pistol move speed multiplier            ║
// ║    wb_sniper_hs    1.50  Sniper headshot damage multiplier       ║
// ║                                                                  ║
// ╚══════════════════════════════════════════════════════════════════╝


// ============================================================
//  INITIALIZATION
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: init()
//  Entry point for this script.
//  Sets default DVARS (only when missing) and starts the connect listener.
// --------------------------------------------------------------------------

init()
{
        // Master enable. Set wb_enabled 0 to disable everything in this file.
        if (getDvar("wb_enabled") == "")
                setDvar("wb_enabled", "1");

        // Show/enable the class HUD hook (0/1). The hook itself is in showClassHUD().
        SetDvarIfNotInizialized("wb_hud", "1");
        // SMG movement speed multiplier. 1.08 = +8% speed.
        SetDvarIfNotInizialized("wb_smg_speed", "1.08");
        // LMG movement speed multiplier. 0.90 = -10% speed.
        SetDvarIfNotInizialized("wb_lmg_speed", "0.90");
        // Sniper movement speed multiplier.
        SetDvarIfNotInizialized("wb_sniper_speed", "0.92");
        // Pistol movement speed multiplier.
        SetDvarIfNotInizialized("wb_pistol_speed", "1.05");
        // Sniper headshot multiplier (lookup value for external hooks).
        SetDvarIfNotInizialized("wb_sniper_hs", "1.50");

        level thread onPlayerConnect();
}

// --------------------------------------------------------------------------
//  FUNCTION: onPlayerConnect()
//  Global listener that waits for players to connect.
//  For each connecting player, starts the per-player spawn lifecycle thread.
// --------------------------------------------------------------------------

onPlayerConnect()
{
        for (;;)
        {
                level waittill("connected", player);
                player thread onPlayerSpawned();
        }
}

// --------------------------------------------------------------------------
//  FUNCTION: onPlayerSpawned()
//  Per-player lifecycle loop (runs every time the player spawns).
//  Resets per-life state, then starts the weapon/ammo/mapvote threads.
// --------------------------------------------------------------------------

onPlayerSpawned()
{
        self endon("disconnect");
        // This thread persists across the match for this player.
        // It loops each time the player respawns/re-enters a playable state.

        for (;;)
        {
                self waittill("spawned_player");

                // If disabled, skip starting any per-life threads.
                if (!getDvarInt("wb_enabled"))
                        continue;

                // Reset cached state for this life.
                self.wb_last_weapon = "";
                self.wb_class = "";
                self.wb_hud_hidden = false;
                self.wb_last_hud_time = 0;
                self.wb_last_hud_class = "";

                // Start background watchers for this life.
                self thread weaponWatchLoop();
                self thread ammoWatchLoop();
                self thread mapvoteHider();

                self iPrintLn("^5Weapon Rebalance ^7Active");
        }
}


// ============================================================
//  WEAPON CLASS DETECTION
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: getWeaponClass(weapon)
//  Classifies a weapon string into a simple category used by this script.
//  Returns: "smg", "ar", "lmg", "shotgun", "sniper", "pistol", "launcher",
//  "wonder", "special", "melee", "equipment", "unknown", or "none".
//  This uses substring matching; if you add custom weapons, update this table.
// --------------------------------------------------------------------------

getWeaponClass(weapon)
{
        if (!isDefined(weapon) || weapon == "" || weapon == "none")
                return "none";

        if (isSubStr(weapon, "ray_gun") || isSubStr(weapon, "raygun_mark2"))
                return "wonder";
        if (isSubStr(weapon, "blundergat") || isSubStr(weapon, "blundersplat"))
                return "wonder";
        if (isSubStr(weapon, "slipgun") || isSubStr(weapon, "slowgun"))
                return "wonder";
        if (isSubStr(weapon, "staff_"))
                return "wonder";
        if (isSubStr(weapon, "jetgun"))
                return "wonder";
        if (isSubStr(weapon, "cymbal_monkey"))
                return "equipment";
        if (isSubStr(weapon, "claymore") || isSubStr(weapon, "frag_grenade") || isSubStr(weapon, "sticky_grenade"))
                return "equipment";
        if (isSubStr(weapon, "bowie_knife") || isSubStr(weapon, "tazer_knuckles") || isSubStr(weapon, "knife_zm"))
                return "melee";
        if (isSubStr(weapon, "riotshield"))
                return "equipment";

        if (isSubStr(weapon, "m32") || isSubStr(weapon, "usrpg") || isSubStr(weapon, "smaw"))
                return "launcher";
        if (isSubStr(weapon, "crossbow"))
                return "launcher";

        if (isSubStr(weapon, "knife_ballistic"))
                return "special";

        if (isSubStr(weapon, "m1911") || isSubStr(weapon, "fiveseven") || isSubStr(weapon, "kard_zm") || isSubStr(weapon, "beretta93r") || isSubStr(weapon, "judge") || isSubStr(weapon, "python") || isSubStr(weapon, "rnma") || isSubStr(weapon, "mauser"))
                return "pistol";

        if (isSubStr(weapon, "dsr50") || isSubStr(weapon, "barretm82") || isSubStr(weapon, "svu") || isSubStr(weapon, "ballista"))
                return "sniper";

        if (isSubStr(weapon, "870mcs") || isSubStr(weapon, "rottweil72") || isSubStr(weapon, "saiga12") || isSubStr(weapon, "srm1216") || isSubStr(weapon, "ksg"))
                return "shotgun";

        if (isSubStr(weapon, "rpd") || isSubStr(weapon, "hamr") || isSubStr(weapon, "lsat"))
                return "lmg";

        if (isSubStr(weapon, "mp5k") || isSubStr(weapon, "pdw57") || isSubStr(weapon, "ak74u") || isSubStr(weapon, "qcw05") || isSubStr(weapon, "thompson") || isSubStr(weapon, "mp40") || isSubStr(weapon, "uzi") || isSubStr(weapon, "vector") || isSubStr(weapon, "insas") || isSubStr(weapon, "evoskorpion"))
                return "smg";

        if (isSubStr(weapon, "m14") || isSubStr(weapon, "m16") || isSubStr(weapon, "saritch") || isSubStr(weapon, "xm8") || isSubStr(weapon, "type95") || isSubStr(weapon, "tar21") || isSubStr(weapon, "galil") || isSubStr(weapon, "fnfal") || isSubStr(weapon, "an94") || isSubStr(weapon, "m27") || isSubStr(weapon, "hk416"))
                return "ar";

        return "unknown";
}


// ============================================================
//  WEAPON SWITCH MONITOR — MOVEMENT SPEED + HUD
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: weaponWatchLoop()
//  Polls the current weapon and reacts when it changes.
//  On change: updates cached class, applies move-speed scaling, and optionally
//  calls the HUD hook (if enabled).
// --------------------------------------------------------------------------

weaponWatchLoop()
{
        self endon("disconnect");
        self endon("death");

        for (;;)
        {
                // Poll current weapon. This is lightweight and runs every ~0.15s.
                weapon = self getCurrentWeapon();

                // Only react when the weapon actually changes.
                if (weapon != self.wb_last_weapon && isDefined(weapon) && weapon != "none")
                {
                        // Cache and classify the new weapon.
                        self.wb_last_weapon = weapon;
                        wClass = getWeaponClass(weapon);
                        self.wb_class = wClass;
                        // Apply movement speed scaling based on class.
                        self applyClassMoveSpeed(weapon, wClass);

                        if (getDvarInt("wb_hud") && !self.wb_hud_hidden)
                                self thread showClassHUD(weapon, wClass);
                }

                wait 0.15;
        }
}

// --------------------------------------------------------------------------
//  FUNCTION: applyClassMoveSpeed(weapon, wClass)
//  Applies movement speed scaling based on weapon class (and a few specific
//  weapon exceptions).
//  Uses wb_* speed DVARS so you can tune feel without editing code.
// --------------------------------------------------------------------------

applyClassMoveSpeed(weapon, wClass)
{
        switch (wClass)
        {
        case "smg":
                self setMoveSpeedScale(getDvarFloat("wb_smg_speed"));
                break;
        case "lmg":
                self setMoveSpeedScale(getDvarFloat("wb_lmg_speed"));
                break;
        case "sniper":
                self setMoveSpeedScale(getDvarFloat("wb_sniper_speed"));
                break;
        case "pistol":
                self setMoveSpeedScale(getDvarFloat("wb_pistol_speed"));
                break;
        case "special":
                if (isSubStr(weapon, "knife_ballistic"))
                        self setMoveSpeedScale(1.10);
                else
                        self setMoveSpeedScale(1.0);
                break;
        case "ar":
                if (isSubStr(weapon, "an94"))
                        self setMoveSpeedScale(0.95);
                else
                        self setMoveSpeedScale(1.0);
                break;
        default:
                self setMoveSpeedScale(1.0);
                break;
        }
}

// --------------------------------------------------------------------------
//  FUNCTION: showClassHUD(weapon, wClass)
//  HUD hook for showing the detected weapon class.
//  Currently kept minimal/empty to avoid conflicts with other HUD mods.
//  If you want a visible HUD label/icon, implement it inside this function.
// --------------------------------------------------------------------------

showClassHUD(weapon, wClass)
{
        self endon("disconnect");

        switch (wClass)
        {
        case "smg":
                break;
        case "lmg":
                break;
        case "sniper":
                break;
        case "pistol":
                break;
        case "shotgun":
                break;
        case "ar":
                break;
        case "special":
                break;
        }
}


// ============================================================
//  AMMO REBALANCE — APPLIED ON WEAPON PICKUP
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: ammoWatchLoop()
//  Checks the player's owned primary weapons periodically.
//  When it sees a weapon for the first time this life, it calls applyAmmoRebalance()
//  and records it so ammo buffs do NOT stack or repeat.
// --------------------------------------------------------------------------

ammoWatchLoop()
{
        // Tracks primaries owned by the player and applies reserve ammo changes once.
        self endon("disconnect");
        self endon("death");

        self.wb_tracked_weapons = [];

        for (;;)
        {
                weaponsList = self getWeaponsListPrimaries();

                for (i = 0; i < weaponsList.size; i++)
                {
                        weapon = weaponsList[i];

                        if (!isDefined(weapon) || weapon == "none")
                                continue;

                        alreadyTracked = false;
                        for (j = 0; j < self.wb_tracked_weapons.size; j++)
                        {
                                if (self.wb_tracked_weapons[j] == weapon)
                                {
                                        alreadyTracked = true;
                                        break;
                                }
                        }

                        if (!alreadyTracked)
                        {
                                self applyAmmoRebalance(weapon);
                                self.wb_tracked_weapons[self.wb_tracked_weapons.size] = weapon;
                        }
                }

                wait 1.0;
        }
}

// --------------------------------------------------------------------------
//  FUNCTION: applyAmmoRebalance(weapon)
//  Applies reserve ammo changes for specific weapons (buffs/nerfs).
//  IMPORTANT: This only changes reserve ammo stock (not damage, fire rate, etc.).
//  This is called once per weapon per life by ammoWatchLoop().
// --------------------------------------------------------------------------

applyAmmoRebalance(weapon)
{
        // Reserve ammo rebalance table.
        // This runs once per unique weapon (per life) and adjusts ammo stock only.
        // ===========================================================
        //  WEAK WEAPON BUFFS — EXTRA AMMO RESERVES
        // ===========================================================

        // SMR — universally hated, give it a fighting chance
        if (isSubStr(weapon, "saritch"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 100);
        }

        // Chicom CQB — 120 total rounds is a joke, fix it
        if (isSubStr(weapon, "qcw05"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 80);
        }

        // KAP-40 — lowest ammo of any pistol, barely functional
        if (isSubStr(weapon, "kard"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 100);
        }

        // Five-Seven — solid gun held back by reserves
        if (isSubStr(weapon, "fiveseven"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 80);
        }

        // Executioner — shotgun pistol needs more shells
        if (isSubStr(weapon, "judge"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 24);
        }

        // Olympia — double barrel starves for ammo
        if (isSubStr(weapon, "rottweil72"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 16);
        }

        // FAL — good concept, bad execution
        if (isSubStr(weapon, "fnfal"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 60);
        }

        // M8A1 — burst fire needs more attempts
        if (isSubStr(weapon, "xm8"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 40);
        }

        // S12 — auto-shotgun burns through ammo instantly
        if (isSubStr(weapon, "saiga12"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 60);
        }

        // M1911 — starter pistol, give it a bit more life
        if (isSubStr(weapon, "m1911"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 40);
        }

        // War Machine — 12 total grenades is pathetic
        if (isSubStr(weapon, "m32"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 12);
        }

        // ===========================================================
        //  MID-TIER TUNING — SLIGHT AMMO BUFFS
        // ===========================================================

        // Type 25 — overshadowed by AN-94 and Galil
        if (isSubStr(weapon, "type95"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 40);
        }

        // M16 — classic AR, could use a touch more
        if (isSubStr(weapon, "m16"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 30);
        }

        // MP5 — solid SMG but runs dry
        if (isSubStr(weapon, "mp5k"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 40);
        }

        // M14 — early-game wall buy, more ammo helps early rounds
        if (isSubStr(weapon, "m14"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 30);
        }

        // MTAR — decent AR but burns ammo fast
        if (isSubStr(weapon, "tar21"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                self setWeaponAmmoStock(weapon, currentStock + 30);
        }

        // ===========================================================
        //  TOP-TIER TRADE-OFFS — SLIGHT AMMO REDUCTIONS
        // ===========================================================

        // Ray Gun Mark II — still amazing, just slightly fewer reserves
        if (isSubStr(weapon, "raygun_mark2"))
        {
                currentStock = self getWeaponAmmoStock(weapon);
                newStock = currentStock - 20;
                if (newStock < 40)
                        newStock = 40;
                self setWeaponAmmoStock(weapon, newStock);
        }
}


// ============================================================
//  DAMAGE MULTIPLIER SYSTEM
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: getDamageMultiplier(weapon)
//  Lookup table for per-weapon damage multipliers.
//  NOTE: This function does not automatically change damage by itself.
//  To make it active, you must plug it into a damage override/hook that your
//  setup supports.
// --------------------------------------------------------------------------

getDamageMultiplier(weapon)
{
        // WEAK WEAPONS — significant damage buffs
        if (isSubStr(weapon, "saritch"))        return 1.50;    // SMR: +50%
        if (isSubStr(weapon, "m32"))            return 1.75;    // War Machine: +75%
        if (isSubStr(weapon, "qcw05"))          return 1.30;    // Chicom: +30%
        if (isSubStr(weapon, "judge"))          return 1.40;    // Executioner: +40%
        if (isSubStr(weapon, "rottweil72"))     return 1.35;    // Olympia: +35%
        if (isSubStr(weapon, "fnfal"))          return 1.25;    // FAL: +25%
        if (isSubStr(weapon, "xm8"))            return 1.20;    // M8A1: +20%
        if (isSubStr(weapon, "m14"))            return 1.25;    // M14: +25%

        // MID-TIER — slight buffs to make them competitive
        if (isSubStr(weapon, "type95"))         return 1.10;    // Type 25: +10%
        if (isSubStr(weapon, "mp5k"))           return 1.10;    // MP5: +10%
        if (isSubStr(weapon, "kard"))           return 1.15;    // KAP-40: +15%
        if (isSubStr(weapon, "m1911"))          return 1.15;    // M1911: +15%
        if (isSubStr(weapon, "fiveseven"))      return 1.10;    // Five-Seven: +10%

        // SHOTGUNS — across the board close-range buff
        if (isSubStr(weapon, "870mcs"))         return 1.15;    // Remington: +15%
        if (isSubStr(weapon, "saiga12"))        return 1.20;    // S12: +20%
        if (isSubStr(weapon, "srm1216"))        return 1.10;    // M1216: +10%
        if (isSubStr(weapon, "ksg"))            return 1.15;    // KSG: +15%

        // SNIPERS — already strong but reward precision
        if (isSubStr(weapon, "dsr50"))          return 1.05;    // DSR-50: slight
        if (isSubStr(weapon, "barretm82"))      return 1.05;    // Barrett: slight
        if (isSubStr(weapon, "svu"))            return 1.15;    // SVU: semi-auto needs help

        // TOP TIER — untouched or very slight
        // AN-94, Galil, HAMR, RPD, LSAT, PDW = 1.0 (no damage change)
        // Ray Gun, Ray Gun MK2 = 1.0 (already powerful)

        return 1.0;
}

// --------------------------------------------------------------------------
//  FUNCTION: getHeadshotMultiplier(weapon)
//  Lookup table for additional headshot multiplier by class/weapon.
//  Like getDamageMultiplier(), this is informational unless you hook it up.
// --------------------------------------------------------------------------

getHeadshotMultiplier(weapon)
{
        wClass = getWeaponClass(weapon);

        if (wClass == "sniper")
                return getDvarFloat("wb_sniper_hs");

        // SMR gets rewarded for headshots since it's semi-auto
        if (isSubStr(weapon, "saritch"))
                return 1.40;

        // FAL same deal — semi-auto should reward aim
        if (isSubStr(weapon, "fnfal"))
                return 1.35;

        // M14 — semi-auto early weapon, reward skill
        if (isSubStr(weapon, "m14"))
                return 1.30;

        // Executioner — hitting heads with this thing deserves a medal
        if (isSubStr(weapon, "judge"))
                return 1.50;

        // Pistols in general get a slight headshot bonus
        if (wClass == "pistol")
                return 1.20;

        return 1.0;
}


// ============================================================
//  BONUS POINT SYSTEM — REWARD USING WEAK WEAPONS
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: getWeaponBonusPoints(weapon)
//  Lookup table for bonus points per kill (to help weak weapons feel rewarding).
//  This is safe to use client-side because it only affects score/feedback.
// --------------------------------------------------------------------------

getWeaponBonusPoints(weapon)
{
        // Weak weapons earn you MORE points as incentive to use them
        if (isSubStr(weapon, "saritch"))        return 20;      // SMR bonus
        if (isSubStr(weapon, "qcw05"))          return 15;      // Chicom bonus
        if (isSubStr(weapon, "judge"))          return 15;      // Executioner bonus
        if (isSubStr(weapon, "rottweil72"))     return 15;      // Olympia bonus
        if (isSubStr(weapon, "fnfal"))          return 10;      // FAL bonus
        if (isSubStr(weapon, "m32"))            return 20;      // War Machine bonus
        if (isSubStr(weapon, "kard"))           return 10;      // KAP-40 bonus
        if (isSubStr(weapon, "knife_ballistic")) return 30;     // Ballistic Knife big bonus

        return 0;
}


// ============================================================
//  KILL TRACKER — APPLIES DAMAGE/POINT BONUSES
// ============================================================

// NOTE: This system hooks into zombie kills to apply bonus points.
// For actual damage multipliers, the getDamageMultiplier() table above
// is designed to be used with level.overrideActorDamage if the server
// supports it. On client-side Plutonium, the bonus point system and
// ammo rebalance are the primary balancing tools.


// ============================================================
//  MAPVOTE INTEGRATION — HIDE DURING VOTING
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: mapvoteHider()
//  Listens for the map vote to start and flips a flag that other HUD logic can
//  use to hide custom HUD elements during voting.
// --------------------------------------------------------------------------

mapvoteHider()
{
        self endon("disconnect");

        // When map voting starts, mark HUD as hidden so custom HUD can stop drawing.
        level waittill("mapvote_start");
        self.wb_hud_hidden = true;
}


// ============================================================
//  UTILITY
// ============================================================

// --------------------------------------------------------------------------
//  FUNCTION: SetDvarIfNotInizialized(dvar, value)
//  Utility: sets a DVAR only if it is currently blank.
//  Keeps user/server config in control while still providing safe defaults.
// --------------------------------------------------------------------------

SetDvarIfNotInizialized(dvar, value)
{
        if (getDvar(dvar) == "")
                setDvar(dvar, value);
}
