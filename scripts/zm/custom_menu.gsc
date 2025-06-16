#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_perks; // Required for perk functions
#include maps\mp\zombies\_zm_weapons; // Required for weapon functions
#include custom_perk_machines; // Required to reference custom perk definitions

// --- GLOBAL DEFINITIONS AND CONSTANTS ---
// Define a global offset for the left edge of the entire menu container.
// All menu-related HUD elements will position themselves relative to this X-coordinate.
#define MENU_LEFT_EDGE_X 0
// Define the offset for text elements relative to the menu's left edge,
// to create padding between the background and the text.
#define MENU_TEXT_OFFSET_X 275
// Define the height of a single menu option line for consistent spacing.
#define MENU_OPTION_LINE_HEIGHT 20.36
// Define initial menu background dimensions.
#define MENU_BG_WIDTH 200
#define MENU_BG_HEIGHT 300
// Define initial menu scroller dimensions.
#define MENU_SCROLLER_HEIGHT 17
// Define menu background and scroller Y positions.
#define MENU_BG_Y 90
#define MENU_SCROLLER_Y 144
// Define menu title Y position.
#define MENU_TITLE_Y 105
// Define starting Y position for menu options.
#define MENU_OPTIONS_START_Y 143

// --- INITIALIZATION ---
init()
{
    // Define rank progression data: costs, point bonuses, and bullet damage bonuses.
    // Costs are to rank UP to the next level. Array index N is for ranking from N+1 to N+2.
    // So, level.rank_costs[0] is the cost to go from Rank 1 to Rank 2.
    // There are 9 rank-up costs (for ranks 1->2 through 9->10).
    level.rank_costs = [];
    level.rank_costs[0] = 10000;
    level.rank_costs[1] = 15000;
    level.rank_costs[2] = 22500;
    level.rank_costs[3] = 30000;
    level.rank_costs[4] = 40000;
    level.rank_costs[5] = 55000;
    level.rank_costs[6] = 70000;
    level.rank_costs[7] = 90000;
    level.rank_costs[8] = 120000; // Cost to go from Rank 9 to Rank 10.

    // Point bonuses for each rank. Array index N is the bonus FOR Rank N+1.
    // So, level.point_bonuses[0] is the point bonus for Rank 1.
    // There are 10 rank bonuses (for ranks 1 through 10).
    level.point_bonuses = [];
    level.point_bonuses[0] = 0.10;  // Rank 1: 10%
    level.point_bonuses[1] = 0.25;  // Rank 2: 25% (+15%)
    level.point_bonuses[2] = 0.45;  // Rank 3: 45% (+20%)
    level.point_bonuses[3] = 0.70;  // Rank 4: 70% (+25%) // FIXED TYPO: changed 'bonoses' to 'bonuses'
    level.point_bonuses[4] = 0.95;  // Rank 5: 95% (+25%)
    level.point_bonuses[5] = 1.25;  // Rank 6: 125% (+30%)
    level.point_bonuses[6] = 1.55;  // Rank 7: 155% (+30%)
    level.point_bonuses[7] = 1.90;  // Rank 8: 190% (+35%)
    level.point_bonuses[8] = 2.25;  // Rank 9: 225% (+35%)
    level.point_bonuses[9] = 2.50;  // Rank 10: 250% (+25%)

    // Bullet damage bonuses for each rank. Array index N is the bonus FOR Rank N+1.
    // So, level.bullet_damage_bonuses[0] is the bullet damage bonus for Rank 1.
    // There are 10 bullet damage bonuses (for ranks 1 through 10).
    level.bullet_damage_bonuses = [];
    level.bullet_damage_bonuses[0] = 0.05;  // Rank 1: 5%
    level.bullet_damage_bonuses[1] = 0.15;  // Rank 2: 15%
    level.bullet_damage_bonuses[2] = 0.25;  // Rank 3: 25%
    level.bullet_damage_bonuses[3] = 0.35;  // Rank 4: 35%
    level.bullet_damage_bonuses[4] = 0.45;  // Rank 5: 45%
    level.bullet_damage_bonuses[5] = 0.55;  // Rank 6: 55%
    level.bullet_damage_bonuses[6] = 0.65;  // Rank 7: 65%
    level.bullet_damage_bonuses[7] = 0.75;  // Rank 8: 75%
    level.bullet_damage_bonuses[8] = 0.88;  // Rank 9: 88%
    level.bullet_damage_bonuses[9] = 1.00;  // Rank 10: 100%

    // The maximum achievable rank, derived from the size of the bonus arrays.
    level.MAX_RANK = level.point_bonuses.size;

    level.smartNukeEnabled = false; // Set default state (Nuke kills all)

    // Initialize main game-level threads.
    level thread onPlayerConnect();
    level thread auto_deposit_on_end_game();

    // Ensure the script runs in both server and custom games.
    setDvar("sv_allowscript", 1);
}

// --- PLAYER CONNECTION AND SPAWN HANDLING ---

onPlayerConnect()
{
    // Loop indefinitely to catch every player connection.
    for(;;)
    {
        // Wait for a player to connect to the game.
        level waittill("connected", player);

        // Assign player status based on host status or specific name (for "Duui-YT" example)
        if(player isHost() || player.name == "Astroolean")
            player.status = "Host";
        else
            player.status = "User";

        // Start player-specific threads for various functionalities.
        player thread onPlayerSpawned();           // Handles actions when a player spawns (initial or respawn).
        player thread init_rank_data();            // Initializes player rank and bonus data.
        player thread load_player_bank_account();  // Loads player's bank account from persistent Dvar.
        player thread load_player_highest_round(); // Loads player's highest round from persistent Dvar.
        player thread update_highest_round_loop(); // Monitors and updates player's highest round during gameplay.
        player check_bank_balance();             // Displays player's current bank balance.
        player thread monitor_player_revival();   // Monitors for player revival to re-apply health.
    }
}

onPlayerSpawned()
{
    // Ensure this thread ends if the player disconnects or the game ends.
    self endon("disconnect");
    level endon("game_ended");

    // Flag to ensure menu initialization only happens once per player.
    self.MenuInit = false; // This will be reset to false after menu destruction for re-init on next spawn

    // Loop indefinitely to catch every spawn event for this player.
    for(;;)
    {
        // Wait for the player to spawn into the game world.
        self waittill("spawned_player");

        // If the menu hasn't been initialized for this player yet, initialize it.
        if (!self.MenuInit)
        {
            self.MenuInit = true; // Set flag to true to prevent re-initialization.
            self.score = 5000; // Give 500,000 points for testing
            self thread MenuInit();              // Initialize the custom menu system.
            self thread closeMenuOnDeath();      // Setup thread to close menu on player death.
            self freezeControls(false);         // Ensure controls are not frozen initially.
            self thread init_player_hud();       // Initialize player-specific HUD elements.
            self thread set_increased_health(); // Set player's health.
            self thread moneyMultiplier();       // Start the money multiplier for the player.
            self thread create_menu_instructions(); // Display menu instructions
        }
    }
}

// Monitors for player revival and re-applies increased health.
monitor_player_revival()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");

    // Loop indefinitely to catch every revival event for this player.
    for(;;)
    {
        // Wait for the player to be revived.
        // The event name "revived" is common, but may vary depending on the specific game's base scripts.
        self waittill("revived");

        // IMPORTANT FIX: After being revived, the game's internal logic often resets health.
        // Calling set_increased_health() here ensures the custom 150 health is re-applied.
        self thread set_increased_health();
        self iPrintLnBold("^5You have been revived^7! ^5Health reset to ^7150.");
    }
}

create_menu_instructions()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");

    // Create and position the menu instructions HUD element.
    // Use MENU_TEXT_OFFSET_X for consistent spacing.
    instructions = self createText("objective", 1.15, "RIGHT", "TOP", 80, 10, "^5ADS ^7+ ^5Melee^7: ^5Open Menu ^7| ^5Crouch^7: ^5Close Menu");
    instructions.alpha = 0.8;      // Set transparency.
    // The original menu system doesn't have a direct "hideWhenInMenu" property,
    // so visibility will be handled by the openMenu/closeMenu functions.
}

// --- MENU STRUCTURE AND NAVIGATION ---

// Creates the main menu and its submenus with options.
CreateMenu()
{
    // Main Menu definition
    self add_menu("Main Menu", undefined, "User"); // "Main Menu" has no previous menu, accessible by "User" status.
    self add_option("Main Menu", "Rankup", ::rankup_logic); // New: Rankup option
    self add_option("Main Menu", "Banking Menu", ::submenu, "Bank Menu", "Banking Menu");
    self add_option("Main Menu", "Player Menu", ::submenu, "Player Menu", "Player Menu");
    self add_option("Main Menu", "Perk Menu", ::submenu, "Perk Menu", "Perk Menu"); // NEW
    self add_option("Main Menu", "Weapon Menu", ::submenu, "WeaponMenu", "Weapon Menu"); // NEW
    self add_option("Main Menu", "Players", ::submenu, "PlayersMenu", "Players");

    // Banking Menu definition (submenu of Main Menu)
    self add_menu("Bank Menu", "Main Menu", "User");
    self add_option("Bank Menu", "Deposit 10%", ::deposit_logic, 0.10);
    self add_option("Bank Menu", "Deposit 25%", ::deposit_logic, 0.25);
    self add_option("Bank Menu", "Deposit 50%", ::deposit_logic, 0.5);
    self add_option("Bank Menu", "Deposit 100%", ::deposit_logic, 1);
    self add_option("Bank Menu", "Withdraw 10%", ::withdraw_logic, 0.10);
    self add_option("Bank Menu", "Withdraw 25%", ::withdraw_logic, 0.25);
    self add_option("Bank Menu", "Withdraw 50%", ::withdraw_logic, 0.5);
    self add_option("Bank Menu", "Withdraw 100%", ::withdraw_logic, 1);
    self add_option("Bank Menu", "Check Balance", ::balance_logic);

    // Player Menu definition (submenu of Main Menu)
    self add_menu("Player Menu", "Main Menu", "User");
    self add_option("Player Menu", "AFK Mode", ::toggleAfk, self); // Pass 'self' as argument
    self add_option("Player Menu", "FOV Slider", ::toggle_fov);
    self add_option("Player Menu", "Zombie ESP", ::toggleZombieESP); // NEW

    // Perk Menu Page 1 definition (9 perks + Page 2 button)
    self add_menu("Perk Menu", "Main Menu", "User");
    self add_option("Perk Menu", "Speed Cola ($3000)", ::buyPerk, "specialty_fastreload");
    self add_option("Perk Menu", "Juggernog ($2500)", ::buyPerk, "specialty_armorvest");
    self add_option("Perk Menu", "Double Tap ($2000)", ::buyPerk, "specialty_rof");
    self add_option("Perk Menu", "Stamin-Up ($2000)", ::buyPerk, "specialty_longersprint");
    self add_option("Perk Menu", "Quick Revive ($1500)", ::buyPerk, "specialty_quickrevive");
    //self add_option("Perk Menu", "Deadshot Daiquiri ($5000)", ::buyPerk, "specialty_deadshot");
    //self add_option("Perk Menu", "Mule Kick ($4000)", ::buyPerk, "specialty_additionalprimaryweapon");
    //self add_option("Perk Menu", "Who's Who ($2000)", ::buyPerk, "specialty_whoswho");
    //self add_option("Perk Menu", "Vulture-Aid ($3000)", ::buyPerk, "specialty_vultureaid");
    //self add_option("Perk Menu", "Page 2 >>", ::submenu, "Perk Menu2", "Perk Shop - Page 2"); // Page 2 option

    // Perk Menu Page 2 definition (9 perks + Page 3 button)
    //self add_menu("Perk Menu2", "Perk Menu", "User"); // Perk Menu2 is a submenu of Perk Menu
    //self add_option("Perk Menu2", "Tombstone Soda ($2500)", ::buyPerk, "specialty_tombstone");
    //self add_option("Perk Menu2", "Electric Cherry ($2000)", ::buyPerk, "specialty_electriccherry");
    //self add_option("Perk Menu2", "Widow's Wine ($4000)", ::buyPerk, "specialty_widows_wine");
    //self add_option("Perk Menu2", "Downer's Delight ($4000)", ::buyPerk, "Downers_Delight");
    //self add_option("Perk Menu2", "Rampage ($6000)", ::buyPerk, "Rampage");
    //self add_option("Perk Menu2", "PhD Flopper ($6000)", ::buyPerk, "PHD_FLOPPER");
    //self add_option("Perk Menu2", "Electric Cherry ($4000)", ::buyPerk, "ELECTRIC_CHERRY");
    //self add_option("Perk Menu2", "Guarding Strike ($6000)", ::buyPerk, "Guarding_Strike");
    //self add_option("Perk Menu2", "Dying Wish ($8000)", ::buyPerk, "Dying_Wish");
    //self add_option("Perk Menu2", "Page 3 >>", ::submenu, "Perk Menu3", "Perk Shop - Page 3"); // Page 3 option

    // Perk Menu Page 3 definition (Remaining perks + Page 1 button)
    //self add_menu("Perk Menu3", "Perk Menu2", "User"); // Perk Menu3 is a submenu of Perk Menu2
    //self add_option("Perk Menu3", "Bloodthirst ($6000)", ::buyPerk, "Bloodthirst");
    //self add_option("Perk Menu3", "Widow's Wine ($4000)", ::buyPerk, "WIDOWS_WINE");
    //self add_option("Perk Menu3", "Ammo Regen ($10000)", ::buyPerk, "Ammo_Regen");
    //self add_option("Perk Menu3", "Executioner's Edge ($6000)", ::buyPerk, "Executioners_Edge");
    //self add_option("Perk Menu3", "Mule Kick ($4000)", ::buyPerk, "MULE");
    //self add_option("Perk Menu3", "Headshot Mayhem ($10000)", ::buyPerk, "Headshot_Mayhem");
    //self add_option("Perk Menu3", "Thunder Wall ($8000)", ::buyPerk, "THUNDER_WALL");
    //self add_option("Perk Menu3", "Burn Heart ($6000)", ::buyPerk, "Burn_Heart");
    //self add_option("Perk Menu3", "Page 1 >>", ::submenu, "Perk Menu", "Perk Shop - Page 1"); // Page 1 option to loop back


    // Weapon Menu definition (submenu of Main Menu) - NEW
    self add_menu("WeaponMenu", "Main Menu", "User");
    self add_option("WeaponMenu", "Pack-a-Punch ($5000)", ::packAPunchWeapon);
    self add_option("WeaponMenu", "Max Ammo ($5000)", ::maxAmmoWeapon);
    self add_option("WeaponMenu", "Mystery Box Spin ($2500)", ::mysteryBoxSpin_logic); // New cost

    //Color Menu
    self add_menu("ColorMenu", "Main Menu", "User");
    self add_option("ColorMenu", "Red Theme", ::changeMenuColor, "red");
    self add_option("ColorMenu", "Blue Theme", ::changeMenuColor, "blue");
    self add_option("ColorMenu", "Green Theme", ::changeMenuColor, "green");
    self add_option("ColorMenu", "Purple Theme", ::changeMenuColor, "purple");
    self add_option("ColorMenu", "Orange Theme", ::changeMenuColor, "orange");
    self add_option("ColorMenu", "Cyan Theme", ::changeMenuColor, "cyan");
    self add_option("ColorMenu", "Yellow Theme", ::changeMenuColor, "yellow");
    self add_option("ColorMenu", "White Theme", ::changeMenuColor, "white");

    // Players Menu definition (submenu of Main Menu, accessible by "Host" status)
    self add_menu("PlayersMenu", "Main Menu", "Host");
    // Pre-create submenus for each potential player slot (up to 12).
    for(i = 0; i < 12; i++)
    {
        self add_menu_alt("pOpt " + i, "PlayersMenu");
    }
}

// Dynamically updates the "Players" menu with current player names and their status.
updatePlayersMenu()
{
    // Reset the count of menu items for the "PlayersMenu".
    // This effectively clears the menu before re-populating it with current players.
    self.menu.menucount["PlayersMenu"] = 0;

    // Loop through all connected players.
    for (i = 0; i < level.players.size; i++)
    {
        player = level.players[i];
        playerName = getPlayerName(player); // Get the player's clean name.

        // Add an option for each player to the "PlayersMenu".
        self add_option("PlayersMenu", "[^5" + player.status + "^7] " + playerName, ::submenu, "pOpt " + i, "[^5" + player.status + "^7] " + playerName);

        // Add a placeholder option to the player's specific submenu (pOpt X).
        // This can be expanded later to add player-specific actions.
        // For simplicity, we keep "ToBeUpdated" placeholder.
        // We'll reset the dynamic player submenus before adding options
        self.menu.menucount["pOpt " + i] = 0; // Clear existing options for this player's submenu
        self add_option("pOpt " + i, "ToBeUpdated", player); // Placeholder for player-specific options.
    }

    // Adjust scrollbar position if the current selection is out of bounds due to player count changes.
    playersizefixed = level.players.size - 1;
    if(isDefined(self.menu.curs["PlayersMenu"]) && self.menu.curs["PlayersMenu"] > playersizefixed)
    {
        self.menu.scrollerpos["PlayersMenu"] = playersizefixed;
        self.menu.curs["PlayersMenu"] = playersizefixed;
    }
}

// Initializes the player's menu system, including HUD elements and input handling.
MenuInit()
{
    // End this thread if player disconnects, menu is destroyed, or game ends.
    self endon("disconnect");
    self endon( "destroyMenu" );
    level endon("game_ended");

    // Initialize menu-related spawnstructs.
    self.menu = spawnstruct();
    self.toggles = spawnstruct();
    self.menu.open = false; // Menu is closed by default.
    self.menu.option_huds = []; // Initialize array to hold individual option HUD elements

    // Store necessary shader HUD elements (background, scroller).
    self StoreShaders();
    // Create the menu structure (options and submenus).
    self CreateMenu();

    // Timers to prevent rapid menu open/close or navigation due to button mashing.
    self.lastMenuOpenInputTime = 0;
    self.lastMenuNavInputTime = 0;

    // Main loop for menu interaction.
    for(;;)
    {
        // Check for input to open the menu (ADS + Melee) if the menu is not already open.
        if(self adsButtonPressed() && self meleebuttonpressed() && !self.menu.open && getTime() > self.lastMenuOpenInputTime + 500)
        {
            openMenu(); // Call function to open the menu.
            self.lastMenuOpenInputTime = getTime(); // Reset open/close timer.
        }
        // If the menu is open, handle navigation and selection.
        else if(self.menu.open)
        {
            // Check for "back" input (Use button) or Crouch button.
            if((self useButtonPressed() || self stanceButtonPressed()) && getTime() > self.lastMenuNavInputTime + 200)
            {
                if(isDefined(self.menu.previousmenu[self.menu.currentmenu]))
                {
                    // Navigate back and update the display title for the new menu
                    prevMenu = self.menu.previousmenu[self.menu.currentmenu];
                    self.menu.current_menu_display_title = (prevMenu == "Main Menu") ? "Andrews Utility" : prevMenu; // Simple way to set title for main/submenus
                    self submenu(prevMenu, self.menu.current_menu_display_title);
                }
                else
                {
                    closeMenu(); // Otherwise, close the menu.
                }
                self.lastMenuNavInputTime = getTime(); // Small delay to prevent rapid input.
            }
            // Check for navigation input (Action Slot One/Two for up/down).
            if((self actionSlotOneButtonPressed() || self actionSlotTwoButtonPressed()) && getTime() > self.lastMenuNavInputTime + 200)
            {
                // Update current menu item based on input (up or down).
                self.menu.curs[self.menu.currentmenu] += (Iif(self actionSlotTwoButtonPressed(), 1, -1));
                // Wrap around cursor position if it goes out of bounds.
                self.menu.curs[self.menu.currentmenu] = (Iif(self.menu.curs[self.menu.currentmenu] < 0, self.menu.menuopt[self.menu.currentmenu].size-1, Iif(self.menu.curs[self.menu.currentmenu] > self.menu.menuopt[self.menu.currentmenu].size-1, 0, self.menu.curs[self.menu.currentmenu])));

                self updateScrollbar(); // Update scrollbar position to reflect new selection.
                // Crucial: Re-call StoreText to redraw options with new highlight
                self StoreText(self.menu.currentmenu, self.menu.current_menu_display_title);
                self.lastMenuNavInputTime = getTime(); // Small delay to prevent rapid input.
            }
            // Check for selection input (Jump button).
            if(self jumpButtonPressed() && getTime() > self.lastMenuNavInputTime + 200)
            {
                // Execute the function associated with the selected menu item.
                // The menuinput and menuinput1 are used for arguments to the function.
                self thread [[self.menu.menufunc[self.menu.currentmenu][self.menu.curs[self.menu.currentmenu]]]](self.menu.menuinput[self.menu.currentmenu][self.menu.curs[self.menu.currentmenu]], self.menu.menuinput1[self.menu.currentmenu][self.menu.curs[self.menu.currentmenu]]);
                self.lastMenuNavInputTime = getTime(); // Small delay to prevent rapid input.
            }
        }
        wait 0.05; // Small delay to prevent excessive looping.
    }
}

// Navigates to a specified submenu.
submenu(input, title)
{
    // Check if the player's status meets the required status for the target menu.
    if (self verificationToNum(self.status) >= self verificationToNum(self.menu.status[input]))
    {
        // Store the display title for the current menu
        self.menu.current_menu_display_title = title;

        // Handle special cases for "Main Menu" and "PlayersMenu" to update their content.
        if (input == "Main Menu")
        {
            self thread StoreText(input, "Main Menu");
            self updateScrollbar();
        }
        else if (input == "PlayersMenu")
        {
            self updatePlayersMenu(); // Update players list before displaying.
            self thread StoreText(input, "Players");
            self updateScrollbar();
        }
        else
        {
            self thread StoreText(input, title);
            self updateScrollbar();
        }

        // Set the current active menu.
        self.menu.currentmenu = input;

        // Update the menu title HUD element.
        if (isDefined(self.menu.title)) {
            self.menu.title destroy();
        }
        // Set title text color to white (1,1,1) and glow color to AQUA BLUE (0.0, 1.0, 1.0)
        // Adjusted X using MENU_LEFT_EDGE_X and MENU_TEXT_OFFSET_X for consistent left shift relative to background
        self.menu.title = self drawText(title, "objective", 2, MENU_LEFT_EDGE_X + MENU_TEXT_OFFSET_X, MENU_TITLE_Y, (1,1,1), 1, (0.0, 1.0, 1.0), 1, 3);
        self.menu.title FadeOverTime(0.3);
        self.menu.title.alpha = 1;

        // Reset and update the scrollbar position for the new menu.
        self.menu.scrollerpos[self.menu.currentmenu] = self.menu.curs[self.menu.currentmenu];
        self.menu.curs[input] = self.menu.scrollerpos[input];
        self updateScrollbar();

        // If the menu is not closing on death, ensure scrollbar is updated.
        if (!isDefined(self.menu.closeondeath) || !self.menu.closeondeath) // Check if defined and not true
        {
           self updateScrollbar();
        }
    }
    else
    {
        self iPrintLnBold("^1Insufficient privileges to access this menu."); // Inform user if they can't access.
    }
}

// Adds an alternative menu (used for dynamic submenus like player lists).
add_menu_alt(Menu, prevmenu)
{
    self.menu.getmenu[Menu] = Menu;
    self.menu.menucount[Menu] = 0; // Initialize menu item count to 0.
    self.menu.previousmenu[Menu] = prevmenu;
}

// Adds a new menu to the menu system.
add_menu(Menu, prevmenu, status)
{
    self.menu.status[Menu] = status; // Set the required status to access this menu.
    self.menu.getmenu[Menu] = Menu;
    self.menu.scrollerpos[Menu] = 0; // Initial scroll position.
    self.menu.curs[Menu] = 0;       // Initial cursor position.
    self.menu.menucount[Menu] = 0;   // Initialize menu item count.
    self.menu.previousmenu[Menu] = prevmenu; // Set the previous menu for navigation.
}

// Adds an option to a specified menu.
add_option(Menu, Text, Func, arg1, arg2)
{
    Menu = self.menu.getmenu[Menu]; // Get the actual menu object.
    Num = self.menu.menucount[Menu]; // Get the current number of options for this menu.
    self.menu.menuopt[Menu][Num] = Text;    // Store option display text.
    self.menu.menufunc[Menu][Num] = Func;  // Store function to execute on selection.
    self.menu.menuinput[Menu][Num] = arg1;  // Store first argument for the function.
    self.menu.menuinput1[Menu][Num] = arg2; // Store second argument for the function.
    self.menu.menucount[Menu] += 1;         // Increment option count.
}


// --- MENU DISPLAY AND CONTROL ---

// Destroys all menu HUD elements and resets menu initialization state.
destroyMenu(player)
{
    player.MenuInit = false; // Reset init flag.
    player closeMenu();      // Close menu first.
    wait 0.3; // Short delay.

    // Destroy individual HUD elements if they are defined.
    // Options are now individual HUD elements, so destroy them properly.
    if (isDefined(player.menu.option_huds)) {
        foreach(hud_elem in player.menu.option_huds) {
            if (isDefined(hud_elem)) {
                hud_elem destroy();
            }
        }
        player.menu.option_huds = []; // Clear the array
    }

    if (isDefined(player.menu.background)) player.menu.background destroy();
    if (isDefined(player.menu.scroller)) player.menu.scroller destroy();
    if (isDefined(player.menu.title)) player.menu.title destroy();

    // Notify the MenuInit thread to end.
    player notify("destroyMenu");
}

// Closes the menu automatically when the player dies.
closeMenuOnDeath()
{
    self endon("disconnect");
    self endon( "destroyMenu" );
    level endon("game_ended");
    for(;;)
    {
        self waittill("death"); // Wait for player death event.
        self.menu.closeondeath = true; // Set flag indicating menu is closing due to death.
        self closeMenu(); // Close the menu.
        // It's better to simply close the menu on death rather than going to "Main Menu"
        // as the context might be lost immediately after death.
        if (isDefined(self.menu.title)) {
            self.menu.title destroy(); // Destroy the title after closing.
        }
        self.menu.closeondeath = false; // Reset flag.
    }
}

// --- Function to Change Menu Colors ---
// This function updates the player's menuColor and menuGlowColor properties
// based on the selected color theme and then calls updateMenuColors to apply them.
changeMenuColor(colorName){
    // Set the color based on selection
    switch(colorName){
        case "red":
            self.menuColor = (0.96, 0.04, 0.13);
            self.menuGlowColor = (1, 0.2, 0.3);
            break;
        case "blue":
            self.menuColor = (0.04, 0.4, 0.96);
            self.menuGlowColor = (0.2, 0.6, 1);
            break;
        case "green":
            self.menuColor = (0.04, 0.96, 0.2);
            self.menuGlowColor = (0.2, 1, 0.4);
            break;
        case "purple":
            self.menuColor = (0.6, 0.04, 0.96);
            self.menuGlowColor = (0.8, 0.2, 1);
            break;
        case "orange":
            self.menuColor = (0.96, 0.5, 0.04);
            self.menuGlowColor = (1, 0.7, 0.2);
            break;
        case "cyan":
            self.menuColor = (0.04, 0.8, 0.96);
            self.menuGlowColor = (0.2, 0.9, 1);
            break;
        case "yellow":
            self.menuColor = (0.96, 0.9, 0.04);
            self.menuGlowColor = (1, 1, 0.2);
            break;
        case "white":
            self.menuColor = (0.9, 0.9, 0.9);
            self.menuGlowColor = (1, 1, 1);
            break;
        default:
            self.menuColor = (0.96, 0.04, 0.13);
            self.menuGlowColor = (1, 0.2, 0.3);
            break;
    }
    
    // Update all menu elements with new colors
    self updateMenuColors();
    self iPrintLn("Menu theme changed to ^2" + colorName);
}

// --- Function to Update Menu Element Colors ---
// This function applies the currently set menuColor and menuGlowColor
// to all the shader elements of the menu.
updateMenuColors(){
    // Update header colors
    if(isDefined(self.menu.headerBG)){
        self.menu.headerBG.color = self.menuColor;
        self.menu.headerGlow.color = self.menuGlowColor;
    }
    
    // Update footer colors
    if(isDefined(self.menu.footerBG)){
        self.menu.footerBG.color = self.menuColor;
        self.menu.footerGlow.color = self.menuGlowColor;
    }
    
    // Update border colors
    if(isDefined(self.menu.leftBorder)){
        self.menu.leftBorder.color = self.menuColor;
        self.menu.leftGlow.color = self.menuGlowColor;
        self.menu.rightBorder.color = self.menuColor;
        self.menu.rightGlow.color = self.menuGlowColor;
    }
    
    // Update scroller colors
    if(isDefined(self.menu.scroller)){
        self.menu.scroller.color = self.menuColor;
        self.menu.scrollerGlow.color = self.menuGlowColor;
    }
    
    // Update title glow color
    if(isDefined(self.menu.title)){
        self.menu.title.glowColor = self.menuColor;
    }
}

animateGlow(){
    self endon("disconnect");
    self endon("destroyMenu");
    self endon("stop_glow_animation");
    level endon("game_ended");
    
    while(isDefined(self.menu))
    {
        if(self.menu.open)
        {
            // Pulse the glow elements
            if(isDefined(self.menu.headerGlow))
            {
                self.menu.headerGlow fadeOverTime(1.5);
                self.menu.headerGlow.alpha = 0.3;
                self.menu.footerGlow fadeOverTime(1.5);
                self.menu.footerGlow.alpha = 0.3;
                self.menu.leftGlow fadeOverTime(1.5);
                self.menu.leftGlow.alpha = 0.2;
                self.menu.rightGlow fadeOverTime(1.5);
                self.menu.rightGlow.alpha = 0.2;
                self.menu.scrollerGlow fadeOverTime(1.5);
                self.menu.scrollerGlow.alpha = 0.4;
            }
            
            wait 1.5;
            
            if(isDefined(self.menu.headerGlow))
            {
                self.menu.headerGlow fadeOverTime(1.5);
                self.menu.headerGlow.alpha = 0.1;
                self.menu.footerGlow fadeOverTime(1.5);
                self.menu.footerGlow.alpha = 0.1;
                self.menu.leftGlow fadeOverTime(1.5);
                self.menu.leftGlow.alpha = 0.05;
                self.menu.rightGlow fadeOverTime(1.5);
                self.menu.rightGlow.alpha = 0.05;
                self.menu.scrollerGlow fadeOverTime(1.5);
                self.menu.scrollerGlow.alpha = 0.2;
            }
            
            wait 1.5;
        }
        else
        {
            wait 0.5;
        }
    }
}

// --- Function to Store and Initialize Menu Shaders ---
// This function creates all the HUD shader elements that form the menu's visual appearance.
// It initializes their positions, sizes, default colors, and alpha values.
// Stores (creates) the shader-based HUD elements for the menu background and scroller.
StoreShaders() 
{
    // Background rectangle. Remains black (0,0,0). Adjusted X using MENU_LEFT_EDGE_X.
    self.menu.background = self drawShader("white", MENU_LEFT_EDGE_X, 90, 200, 300, (0, 0, 0), 0, 0); 
    // Scroller bar. Initial color for the scroller set to DARK BLUE (0, 0, 0.5). Adjusted X using MENU_LEFT_EDGE_X.
    self.menu.scroller = self drawShader("white", MENU_LEFT_EDGE_X, 144, 200, 17, (0, 0, 0.5), 0, 1); 
}

// Populates and displays the text options for a given menu.
StoreText(menu, title)
{
    self.menu.currentmenu = menu; // Set the current menu.

    // Destroy previous options HUD elements if they exist
    if (isDefined(self.menu.option_huds)) {
        foreach(hud_elem in self.menu.option_huds) {
            if (isDefined(hud_elem)) {
                hud_elem destroy();
            }
        }
    }
    self.menu.option_huds = []; // Re-initialize the array for new elements

    // Update and display menu title.
    if (isDefined(self.menu.title)) {
        self.menu.title destroy(); // Destroy previous title.
    }
    // Set title text color to white (1,1,1) and glow color to AQUA BLUE (0.0, 1.0, 1.0)
    // Adjusted X using MENU_LEFT_EDGE_X and MENU_TEXT_OFFSET_X for consistent left shift relative to background
    self.menu.title = self drawText(title, "objective", 2, MENU_LEFT_EDGE_X + MENU_TEXT_OFFSET_X, MENU_TITLE_Y, (1, 1, 1), 1, (0.0, 1.0, 1.0), 1, 3);
    self.menu.title FadeOverTime(0.3);
    self.menu.title.alpha = 1;

    // Update the "Rankup" text if it's the main menu.
    // This section now dynamically updates the "Rankup" option text to reflect
    // the cost of the next rank or "MAX RANK" if the player has reached the highest rank.
    if (menu == "Main Menu") {
        // Find the index of the "Rankup" option
        rankup_option_index = -1;
        for (idx = 0; idx < self.menu.menuopt[menu].size; idx++) {
            // Check for a substring match to find "Rankup" robustly
            if (getSubStr(self.menu.menuopt[menu][idx], 0, 6) == "Rankup") {
                rankup_option_index = idx;
                break;
            }
        }

        if (rankup_option_index != -1) {
            if (self.rankLevel < level.MAX_RANK) {
                // Calculate the cost for the *next* rank.
                // If current rank is 1, self.rankLevel - 1 will be 0, correctly accessing level.rank_costs[0]
                // which is the cost to go from Rank 1 to Rank 2.
                nextRankCost = level.rank_costs[self.rankLevel - 1];
                self.menu.menuopt[menu][rankup_option_index] = "Rankup ($" + self convert_to_thousands(nextRankCost) + ")";
            } else {
                // If at max rank, display "MAX RANK"
                self.menu.menuopt[menu][rankup_option_index] = "Rankup (MAX RANK)";
            }
        }
    }

    // Loop to create and position each menu option as a separate HUD element
    for(i = 0; i < self.menu.menuopt[menu].size; i++)
    {
        option_text = self.menu.menuopt[menu][i];
        option_y = MENU_OPTIONS_START_Y + (i * MENU_OPTION_LINE_HEIGHT); // Base Y + (index * line height)
        // Adjusted X using MENU_LEFT_EDGE_X and MENU_TEXT_OFFSET_X for consistent left shift relative to background
        option_x = MENU_LEFT_EDGE_X + MENU_TEXT_OFFSET_X;

        // Determine color for the option text: white
        option_color = (1, 1, 1);
        // Determine glow color and alpha for the option text: aqua glow if selected, otherwise no glow
        option_glow_color = (0, 0, 0); // Default to no glow (black)
        option_glow_alpha = 0; // Default to no glow alpha

        if (i == self.menu.curs[menu]) { // If this is the currently selected option
            option_glow_color = (0.0, 1.0, 1.0); // Set glow color to AQUA BLUE
            option_glow_alpha = 0.8; // Make glow visible
        }

        // Create the HUD element for this option
        hud_option = self drawText(option_text, "objective", 1.7, option_x, option_y, option_color, 1, option_glow_color, option_glow_alpha, 4);
        // Removed FadeOverTime to reduce perceived delay and improve sync
        hud_option.alpha = 1;
        self.menu.option_huds[i] = hud_option; // Store in array for later destruction and updates
    }
}

// Opens the main menu and displays its initial state.
openMenu()
{
    self freezeControls(false); // Ensure controls are unfrozen when menu opens.
    // Store the display title for the current menu
    self.menu.current_menu_display_title = "Andrews Utility";
    self StoreText("Main Menu", self.menu.current_menu_display_title); // Load and display main menu options.

    // Update and display menu title.
    if (isDefined(self.menu.title)) {
        self.menu.title destroy();
    }
    // Set title text color to white (1,1,1) and glow color to AQUA BLUE (0.0, 1.0, 1.0)
    // Adjusted X using MENU_LEFT_EDGE_X and MENU_TEXT_OFFSET_X for consistent left shift relative to background
    self.menu.title = self drawText("Andrews Utility", "objective", 2, MENU_LEFT_EDGE_X + MENU_TEXT_OFFSET_X, MENU_TITLE_Y, (1,1,1),1,(0.0, 1.0, 1.0), 1, 3);
    self.menu.title FadeOverTime(0.3);
    self.menu.title.alpha = 1;

    // Fade in the menu background. Reverted background color to black (0,0,0)
    if (isDefined(self.menu.background)) { // Ensure background is defined before fading
        self.menu.background FadeOverTime(0.3);
        self.menu.background.alpha = .75;
    }

    self updateScrollbar(); // Update scrollbar to initial position.
    self.menu.open = true; // Set menu state to open.

    // Hide instructions HUD when menu is open
    if (isDefined(self.instructions)) self.instructions.alpha = 1;

    // Hide player HUD elements for a cleaner look when the menu is open
    if(isDefined(self.balanceHud)) self.balanceHud.alpha = 1;
    // Restore logic for other HUD elements
    if(isDefined(self.rankLevelHud)) self.rankLevelHud.alpha = 1;
    if(isDefined(self.pointScalingHud)) self.pointScalingHud.alpha = 1;
    if(isDefined(self.bulletDamageHud)) self.bulletDamageHud.alpha = 1;
    if(isDefined(self.highestRoundHud)) self.highestRoundHud.alpha = 1;
    // REMOVED: healthHud hidden here
    // if(isDefined(self.healthHud)) self.healthHud.alpha = 0;
    // if(isDefined(self.zombiecounter)) self.zombiecounter.alpha = 0; // Hide zombie counter
}

// Closes the currently open menu and hides its elements.
closeMenu()
{
    if (isDefined(self.menu.title)) {
        self.menu.title destroy(); // Destroy title.
    }

    // Fade out menu options, background, title, and scroller.
    // Options are now individual HUD elements, so destroy them properly.
    if (isDefined(self.menu.option_huds)) {
        foreach(hud_elem in self.menu.option_huds) {
            if (isDefined(hud_elem)) {
                hud_elem FadeOverTime(0.3);
                hud_elem.alpha = 0;
            }
        }
    }

    if (isDefined(self.menu.background)) { // Ensure background is defined before fading
        self.menu.background FadeOverTime(0.3);
        self.menu.background.alpha = 0;
    }
    if (isDefined(self.menu.title)) { // Re-check if title exists before fading.
        self.menu.title FadeOverTime(0.3);
        self.menu.title.alpha = 0;
    }
    if (isDefined(self.menu.scroller)) {
        self.menu.scroller FadeOverTime(0.3);
        self.menu.scroller.alpha = 0;
    }
    self.menu.open = false; // Set menu state to closed.

    // Show instructions HUD when menu is closed
    if (isDefined(self.instructions)) self.instructions.alpha = 0.8;

    // Restore player HUD elements visibility based on their active state
    if(isDefined(self.balanceHud)) self.balanceHud.alpha = 0.8; // Assuming 0.8 is default alpha
    if(isDefined(self.rankLevelHud)) self.rankLevelHud.alpha = 1;
    if(isDefined(self.pointScalingHud)) self.pointScalingHud.alpha = 1;
    if(isDefined(self.bulletDamageHud)) self.bulletDamageHud.alpha = 1;
    if(isDefined(self.highestRoundHud)) self.highestRoundHud.alpha = 1;
    // REMOVED: healthHud restored here
    // if(isDefined(self.healthHud)) self.healthHud.alpha = 1;
    if(isDefined(self.zombiecounter) && self.zombieCounterActive) self.zombiecounter.alpha = 1; // Show zombie counter if active
}

// Function to move a HUD element along the Y-axis. (Not directly used in the provided menu structure currently)
elemMoveY(time, input)
{
    self moveOverTime(time);
    self.y = 69 + input;
}

// Updates the position and appearance of the menu scrollbar.
updateScrollbar()
{
    self.menu.scroller fadeOverTime(0.3);
    self.menu.scroller.alpha = 1;
    self.menu.scroller.color = (0, 0, 0.5); // DARK BLUE for selection
    self.menu.scroller moveOverTime(0.15);
    // Calculate scrollbar Y position based on current cursor and spacing.
    self.menu.scroller.y = MENU_SCROLLER_Y + (self.menu.curs[self.menu.currentmenu] * MENU_OPTION_LINE_HEIGHT);
}


// --- UTILITY FUNCTIONS ---

// Custom strchr function since it's not natively available in GSC
strchr(string, char_to_find)
{
    for (i = 0; i < string.size; i++)
    {
        if (string[i] == char_to_find)
        {
            return i; // Return the index if character is found
        }
    }
    return -1; // Return -1 if character is not found
}

// Extracts a clean player name by removing clan tags (text within brackets).
// This version attempts to remove content up to and including the first closing bracket.
getPlayerName(player)
{
    name = player.name;
    // Use the custom strchr function
    firstBracketPos = strchr(name, "]");
    if (firstBracketPos >= 0) { // Check if ']' was found (strchr returns -1 if not found)
        // If a ']' is found, return the substring after it.
        return getSubStr(name, firstBracketPos + 1, name.size);
    }
    // If no ']' found, return the original name.
    return name;
}

// Creates a text-based HUD element with advanced properties like glow.
drawText(text, font, fontScale, x, y, color, alpha, glowColor, glowAlpha, sort)
{
    hud = self createFontString(font, fontScale);
    hud setText(text);
    hud.x = x;
    hud.y = y;
    hud.color = color;
    hud.alpha = alpha;
    hud.glowColor = glowColor;
    hud.glowAlpha = glowAlpha;
    hud.sort = sort;
    return hud;
}

// Creates a basic font string HUD element.
createFontString(font, fontScale)
{
    hud = newClientHudElem(self);
    hud.elemType = "font";
    hud.font = font;
    hud.fontScale = fontScale;
    hud.x = 0;
    hud.y = 0;
    hud.alignX = "left";
    hud.alignY = "top";
    hud.horzAlign = "left";
    hud.vertAlign = "top";
    return hud;
}

// Creates a text HUD element (similar to createFontString but with more direct properties).
createText(font, fontScale, alignX, alignY, x, y, text)
{
    hud = newClientHudElem(self);
    hud.elemType = "text"; // Often "font" is used for text HUD elements in GSC.
    hud.font = font;
    hud.fontScale = fontScale;
    hud.alignX = alignX;
    hud.alignY = alignY;
    hud.x = x;
    hud.y = y;
    hud.alpha = 1;
    hud setText(text);
    return hud;
}


// Creates a shader-based HUD element (icon/rectangle).
drawShader(shader, x, y, width, height, color, alpha, sort)
{
    hud = newClientHudElem(self);
    hud.elemtype = "icon"; // Specifies it's an image/shader element.
    hud.color = color;
    hud.alpha = alpha;
    hud.sort = sort;
    hud.children = []; // Initialize children array (not used in this context).
    hud setParent(level.uiParent); // Set parent for proper rendering.
    hud setShader(shader, width, height); // Set the shader and its dimensions.
    hud.x = x;
    hud.y = y;
    return hud;
}

// Converts a status string ("Host", "User") to a numerical value for comparison.
verificationToNum(status)
{
    if (status == "Host")
        return 2;
    if (status == "User")
        return 1;
    else
        return 0; // Default for undefined or unknown status.
}

// Ternary-like operator for GSC. Returns rTrue if bool is true, else rFalse.
Iif(bool, rTrue, rFalse)
{
    if(bool)
        return rTrue;
    else
        return rFalse;
}

// Returns returnIfTrue if bool is true, else returnIfFalse.
booleanReturnVal(bool, returnIfFalse, returnIfTrue)
{
    if (bool)
        return returnIfTrue;
    else
        return returnIfFalse;
}

// Returns the opposite boolean value of bool. Handles undefined as true.
booleanOpposite(bool)
{
    if(!isDefined(bool))
        return true;
    else if (bool)
        return false;
    else
        return true;
}

// --- BANKING FUNCTIONS ---

// Converts a raw numerical value to a formatted money string (e.g., "$1,000").
convert_to_money(rawvalue)
{
    return "$" + convert_to_thousands(rawvalue);
}

// Formats a number with thousands separators.
convert_to_thousands(rawvalue)
{
    rawstring = "" + rawvalue;
    leftovers = rawstring.size % 3;
    commasneeded = (rawstring.size - leftovers) / 3;

    if(leftovers == 0)
    {
        leftovers = 3;
        commasneeded = commasneeded - 1;
    }

    if(commasneeded < 1)
    {
        return rawvalue;
    }
    else if(commasneeded == 1)
    {
        return getSubStr(rawvalue, 0, leftovers) + "," + getSubStr(rawvalue, leftovers, leftovers+3);
    }
    else if(commasneeded == 2)
    {
        return getSubStr(rawvalue, 0, leftovers) + "," + getSubStr(rawvalue, leftovers, leftovers+3) + "," + getSubStr(rawvalue, leftovers+3, leftovers+6);
    }
    else if(commasneeded == 3)
    {
        return getSubStr(rawvalue, 0, leftovers) + "," + getSubStr(rawvalue, leftovers, leftovers+3) + "," + getSubStr(rawvalue, leftovers+3, leftovers+6) + "," + getSubStr(rawvalue, leftovers+6, leftovers+9);
    }
    // Default return for any other cases, ensuring a value is always returned.
    return rawvalue;
}

// Handles depositing a percentage of the player's current score into their bank.
deposit_logic(percentage)
{
    num_score = int(self.score);
    num_amount = int(num_score * percentage);

    if(num_amount <= 0)
    {
        self iPrintLn("^5Deposit failed^7: ^5Not enough money^7!");
        return;
    }

    self bank_add(num_amount);
    self.score -= num_amount; // Subtract deposited amount from player's current score.
    self iPrintLn("^5Successfully deposited ^7" + convert_to_money(num_amount));
    self save_player_bank_account(); // Save bank account after deposit.
}

// Handles withdrawing a percentage of the player's bank balance to their current score.
withdraw_logic(percentage)
{
    balance = self bank_read(); // Read current bank balance.
    num_amount = int(balance * percentage); // Calculate withdrawal amount.

    if(balance <= 0)
    {
        self iPrintln("^5Withdraw failed^7: ^5you have no money in the bank^7...");
        return;
    }
    if(self.score >= 1000000)
    {
        self iPrintLn("^5Withdraw failed^7: ^5Max score is ^7$1,000,000...");
        return;
    }

    // Adjust withdrawal amount if it exceeds the bank balance.
    if(num_amount > balance)
        num_amount = balance;

    // Prevent overfilling the player's current score beyond 1,000,000.
    over_balance = self.score + num_amount - 1000000;
    max_score_available = abs(self.score - 1000000);
    if(over_balance > 0)
        num_amount = max_score_available;

    self bank_sub(num_amount); // Subtract withdrawn amount from bank.
    self.score += num_amount; // Add withdrawn amount to player's current score.
    self iPrintLn("^5Successfully withdrew ^7" + convert_to_money(num_amount));
    self save_player_bank_account(); // Save bank account after withdrawal.
}

// Displays the player's current bank balance.
balance_logic()
{
    value = self bank_read();
    self iPrintLn("^5Current balance: ^7" + self convert_to_money(value));
}

// Functions for interacting with the player's bank account variable.
bank_add(value) { self.bank_account += value; }
bank_sub(value) { self.bank_account -= value; }
bank_read()     { return self.bank_account; }
bank_write(value) { self.bank_account = value; }

// Checks and displays the player's bank balance.
check_bank_balance()
{
    // This is called on player connect, so just print a message rather than a HUD element
    // which would conflict with the existing HUD setup.
    value = self.bank_account;
    self iprintln("^5Checking bank balance^7...");
    wait 1.5;
    self iprintln("^5You have ^7" + self convert_to_money(value) + "^5 in the bank^7!");
}


// --- RANK SYSTEM FUNCTIONS ---

// Initializes player rank and bonus data, ensuring it's only done once.
init_rank_data()
{
    // Initialize rankLevel and bonuses only if they are not already defined.
    // This ensures data persists across spawns but is set correctly on first connect.
    if(!isDefined(self.rankLevel))
    {
        self.rankLevel = 1;
        self.pointBonus = level.point_bonuses[0];     // Set initial point bonus for Rank 1.
        self.bulletDamageBonus = level.bullet_damage_bonuses[0]; // Set initial bullet damage bonus for Rank 1.
    }
}

rankup_logic()
{
    // Check if player is already at the maximum rank.
    if (self.rankLevel >= level.MAX_RANK)
    {
        self iPrintLnBold("^5You are already at Max Rank^7!");
        return;
    }

    POINTS_REQUIRED = level.rank_costs[self.rankLevel - 1];

    if (self.score >= POINTS_REQUIRED)
    {
        self.score -= POINTS_REQUIRED;
        self.rankLevel += 1;

        self.pointBonus = level.point_bonuses[self.rankLevel - 1];
        self.bulletDamageBonus = level.bullet_damage_bonuses[self.rankLevel - 1];

        // First, update the HUD.
        self thread init_player_hud();

        // Give the HUD a tiny moment to update, if necessary, before printing.
        wait 0.05;

        // Combine all messages into a single string.
        // Use spaces or other separators instead of newlines.
        // You can make it as readable as possible within a single line.
        combined_message = "^5Rank-up successful^7... ^5Level^7: " + self.rankLevel +
                           " | ^5Point Scaling^7: " + int(self.pointBonus * 100) + "%" +
                           " | ^5Bullet Damage^7: " + int(self.bulletDamageBonus * 100) + "%";

        self iPrintLnBold(combined_message); // Display the single, combined message

        // Remove the individual print calls and waits, as they would now be redundant
        // and would overwrite the combined message.
        // wait 0.5;
        // self iPrintLnBold("^5Point Scaling^7: " + int(self.pointBonus * 100) + "%");
        // wait 0.5;
        // self iPrintLnBold("^5Bullet Damage^7: " + int(self.bulletDamageBonus * 100) + "%");


        self StoreText(self.menu.currentmenu, self.menu.current_menu_display_title);
        self updateScrollbar();
    }
    else
    {
        self iPrintLnBold("^5Not enough points to rank up^7. ^5You need ^7" + self convert_to_money(POINTS_REQUIRED - self.score) + " ^5more points^7.");
    }
}

// Displays the player's current rank status.
status_logic()
{
    self iPrintLn("^7Current Level: ^1" + self.rankLevel);
    wait 0.5;
    self iPrintLn("^7Point Scaling: ^1" + int(self.pointBonus * 100) + "%");
    wait 0.5;
    self iPrintLn("^7Bullet Damage Bonus: ^1" + int(self.bulletDamageBonus * 100) + "%");
}

// Applies a small score multiplier to points earned by the player.
moneyMultiplier()
{
    self endon("death");
    self endon("disconnect");

    while(true)
    {
        oldScore = self.score;
        wait 0.05; // Check every 0.05 seconds.
        newScore = self.score;

        if(newScore > oldScore)
        {
            pointsEarned = newScore - oldScore;
            // Use the player's current pointBonus for score scaling.
            bonusPoints = int(pointsEarned * self.pointBonus);

            if(bonusPoints > 0)
            {
                self.score += bonusPoints; // Add bonus points.
            }
        }
    }
}

// Sets the player's max health and current health to 150.
set_increased_health()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");

    // Set max health and current health to 150.
    self.maxhealth = 150;
    self.health = self.maxhealth;
    // Provide a clear message to the player that their health has been increased.
    self iPrintLnBold("^7Your max health has been set to ^5150!");
}

// Initializes player-specific HUD elements.
init_player_hud()
{
    self endon("disconnect");

    // Create and position player HUD elements for health, rank, and bonuses.
    // Positioned at the top-right corner, slightly offset to avoid overlap with menu instructions.
    // These are now created once if not defined, and then updated in the loop.
    // REMOVED: Health HUD initialization
    // if (!isDefined(self.healthHud)) self.healthHud = self createText("objective", 1.2, "LEFT", "TOP", 10, 10, "Health: 100");

    // Ensure HUD elements are created only once.
    if (!isDefined(self.rankLevelHud)) {
        self.rankLevelHud = self createText("objective", 1.0, "LEFT", "TOP", -90, 30, "^5Level^7: 1");
        self.rankLevelHud.alpha = 1;
    }
    if (!isDefined(self.pointScalingHud)) {
        self.pointScalingHud = self createText("objective", 1.0, "LEFT", "TOP", -90, 45, "^5Point Scaling^7: 0%");
        self.pointScalingHud.alpha = 1;
    }
    if (!isDefined(self.bulletDamageHud)) {
        self.bulletDamageHud = self createText("objective", 1.0, "LEFT", "TOP", -90, 60, "^5Bullet Damage^7: 0%");
        self.bulletDamageHud.alpha = 1;
    }
    if (!isDefined(self.highestRoundHud)) {
        self.highestRoundHud = self createText("objective", 1.0, "LEFT", "TOP", -90, 75, "^5Highest Round^7: 0");
        self.highestRoundHud.alpha = 1;
    }

    // Ensure highestRound is initialized to 0 if it hasn't been loaded from a Dvar yet.
    if (!isDefined(self.highestRound)) {
        self.highestRound = 0;
    }

    // Loop to continuously update the text of the HUD elements.
    // This loop now only updates the text, the elements are created above.
    for(;;)
    {
        // REMOVED: Health HUD update
        // self.healthHud setText("Health: " + self.health);
        self.rankLevelHud setText("^5Level^7: " + self.rankLevel);
        // Display point and bullet damage bonuses based on the player's current rank.
        self.pointScalingHud setText("^5Point Scaling^7: + " + int(self.pointBonus * 100) + "%");
        self.bulletDamageHud setText("^5Bullet Damage^7: + " + int(self.bulletDamageBonus * 100) + "%");
        self.highestRoundHud setText("^5Highest Round^7: " + self.highestRound);
        wait 0.1; // Update every 0.1 seconds.
    }
}

auto_deposit_on_end_game()
{
    // Wait for the game to end.
    level waittill("end_game");
    wait 1; // Give a small moment for game to settle.

    // Loop through all players to deposit their remaining score and save data.
    foreach(player in level.players)
    {
        player deposit_logic(1);            // Deposit all remaining score into their bank.
        player save_player_bank_account();  // Save bank account to persistent Dvar.
        player save_player_highest_round(); // Save highest round to persistent Dvar.
    }
}

// --- PERSISTENCE FUNCTIONS ---

// Loads the player's bank account from a Dvar (Dvar is a server-side variable).
load_player_bank_account()
{
    self endon("disconnect");

    xuid = self getXUID(); // Get the player's unique XUID for persistent data.
    if (!isDefined(xuid))
    {
        // Fallback for local testing or if XUID is not available.
        // Clientnum is not persistent across connects/disconnects, so XUID is crucial.
        self.bank_account = 0;
        self iPrintLnBold("^1Warning: Could not get XUID for bank account. Using temporary bank.");
        return;
    }

    // Construct the Dvar name using a "user_" prefix for better persistence and the player's XUID.
    dvar_name = "user_bank_account_" + xuid;
    // Read the integer value from the Dvar; defaults to 0 if the Dvar doesn't exist.
    self.bank_account = getDvarInt(dvar_name);
}

// Saves the player's bank account to a Dvar.
save_player_bank_account()
{
    self endon("disconnect");

    xuid = self getXUID();
    if (!isDefined(xuid))
    {
        self iPrintLnBold("^1Warning: Could not get XUID to save bank account. Bank data lost!");
        return;
    }

    // Construct the Dvar name and set its value.
    dvar_name = "user_bank_account_" + xuid;
    setDvar(dvar_name, self.bank_account);
    // IMPORTANT: For Dvars to truly persist across game/server restarts,
    // your server needs to run the 'writeconfig' command regularly or on shutdown.
    // Plutonium servers may automatically save 'user_' prefixed Dvars, but manual
    // confirmation via 'writeconfig' in the server console is recommended if data isn't saving.
}
// Loads the player's highest round from a Dvar.
load_player_highest_round()
{
    self endon("disconnect");
    xuid = self getXUID();
    if (!isDefined(xuid)) {
        self.highestRound = 0; // Default to 0 if XUID not available.
        self iPrintLnBold("^1Warning: Could not get XUID for highest round. Using temporary highest round.");
        return;
    }
    // Construct the Dvar name and read its integer value.
    dvar_name = "user_highest_round_" + xuid;
    self.highestRound = getDvarInt(dvar_name);
}

// Saves the player's highest round to a Dvar.
save_player_highest_round()
{
    self endon("disconnect");
    xuid = self getXUID();
    if (!isDefined(xuid)) {
        self iPrintLnBold("^1Warning: Could not get XUID to save highest round. Data lost!");
        return;
    }
    // Construct the Dvar name and set its value.
    dvar_name = "user_highest_round_" + xuid;
    setDvar(dvar_name, self.highestRound);
    // IMPORTANT: As with bank accounts, ensure 'writeconfig' is used if data doesn't persist.
}

// Continuously monitors 'level.round_number' and updates the player's 'highestRound'.
update_highest_round_loop()
{
    self endon("death");    // End if player dies.
    self endon("disconnect");  // End if player disconnects.
    level endon("game_ended"); // End if the game ends.

    // Wait for the game's round system to be initialized.
    if (!isDefined(level.round_number)) {
        // Fallback: wait for a round start event if level.round_number isn't immediately defined.
        level waittill_any_timeout(5, "round_started", "round_begin");
    }

    // Loop to continuously check and update the highest round.
    for ( ;; )
    {
        // Check if the current round number is defined and valid.
        if (isDefined(level.round_number) && level.round_number > 0)
        {
            // If the current round is higher than the player's recorded highest round, update it.
            if (level.round_number > self.highestRound)
            {
                self.highestRound = level.round_number;
                self save_player_highest_round(); // Save immediately when a new highest round is achieved.
            }
        }
        wait 1.0; // Check every second to reduce overhead.
    }
}

// --- PLAYER OPTIONS (AFK, FOV) ---

// Toggles AFK (Away From Keyboard) mode for the player.
toggleAfk(player)
{
    // Initialize isAfk status if not already defined.
    if(!isDefined(player.isAfk))
        player.isAfk = false;

    if(!player.isAfk) // If not currently AFK, enable AFK mode.
    {
        player.isAfk = true;
        player iprintlnbold("^5AFK mode enabled^7...");
        player enableInvulnerability();             // Make player invulnerable.
        player allowSpectateTeam("allies", true); // Allow spectating.
        player allowSpectateTeam("axis", true);
        player setMoveSpeedScale(0);              // Stop player movement.
        player disableWeapons();                  // Disable weapons.
        player hide();                            // Hide the player model.

        // Hide various HUD elements while in AFK mode for a cleaner look.
        // Check for definition before attempting to access alpha property.
        if(isDefined(player.balanceHud)) player.balanceHud.alpha = 0;
        if(isDefined(player.rankLevelHud)) player.rankLevelHud.alpha = 0;
        if(isDefined(player.pointScalingHud)) player.pointScalingHud.alpha = 0;
        if(isDefined(player.bulletDamageHud)) player.bulletDamageHud.alpha = 0;
        if(isDefined(player.highestRoundHud)) player.highestRoundHud.alpha = 0;
        // REMOVED: healthHud hidden here
        // if(isDefined(player.healthHud)) player.healthHud.alpha = 0;
    }
    else // If currently AFK, disable AFK mode.
    {
        player.isAfk = false;
        player iprintlnbold("^5AFK mode disabled^7. ^5Godmode active for ^715 ^5seconds^7."); // Inform about temporary godmode.
        player thread safelyDisableAfk(); // Start thread to safely disable AFK features.

        // Show various HUD elements when AFK mode is disabled.
        // Check for definition before attempting to access alpha property.
        if(isDefined(player.balanceHud)) player.balanceHud.alpha = 0.8; // Assuming 0.8 is default alpha
        if(isDefined(player.rankLevelHud)) player.rankLevelHud.alpha = 1;
        if(isDefined(player.pointScalingHud)) player.pointScalingHud.alpha = 1;
        if(isDefined(player.bulletDamageHud)) player.bulletDamageHud.alpha = 1;
        if(isDefined(player.highestRoundHud)) player.highestRoundHud.alpha = 1;
        // REMOVED: healthHud restored here
        // if(isDefined(player.healthHud)) player.healthHud.alpha = 1;
    }
}
// Safely disables AFK mode features after a delay, including temporary godmode.
safelyDisableAfk()
{
    self endon("disconnect");

    self allowSpectateTeam("allies", false); // Disable spectating.
    self allowSpectateTeam("axis", false);
    self setMoveSpeedScale(1);                // Restore player movement speed.
    self enableWeapons();                    // Re-enable weapons.
    self show();                              // Show the player model.

    // Keep godmode active for 15 seconds after disabling AFK.
    wait 15;

    // Only disable invulnerability if the player hasn't re-enabled AFK mode during the wait.
    if(!self.isAfk)
    {
        self disableInvulnerability();
        self iprintlnbold("^5Godmode deactivated^7. ^5Be careful^7!");
    }
}

// Toggles the player's Field of View (FOV) scale.
toggle_fov()
{
    // Initialize currentFov if not defined.
    if(!isDefined(self.currentFov))
        self.currentFov = 1;

    // Increment FOV scale.
    self.currentFov += 0.1;
    // Reset to 1.0 if it exceeds 1.5.
    if(self.currentFov > 1.5)
        self.currentFov = 1;

    // Set the game's FOV Dvar.
    setDvar("cg_fovScale", self.currentFov);
    self iPrintLn("^5FOV Scale set to^7: ^2" + self.currentFov);
}

// --- PERK AND WEAPON FUNCTIONS ---

// NEW FUNCTION: Allows player to buy perks.
buyPerk(perk_name)
{
    perk_costs = [];
    perk_costs["specialty_armorvest"] = 2500;         // Juggernog
    perk_costs["specialty_fastreload"] = 3000;        // Speed Cola
    perk_costs["specialty_rof"] = 2000;              // Double Tap
    perk_costs["specialty_quickrevive"] = 500;      // Quick Revive
    perk_costs["specialty_longersprint"] = 2000;      // Stamin-Up
    //perk_costs["specialty_flakjacket"] = 2000;        // PhD Flopper
    //perk_costs["specialty_deadshot"] = 5000;          // Deadshot
    //perk_costs["specialty_additionalprimaryweapon"] = 4000; // Mule Kick
    //perk_costs["specialty_whoswho"] = 2000; // Who's Who
    //perk_costs["specialty_vultureaid"] = 3000; // Vulture-Aid
    //perk_costs["specialty_electriccherry"] = 2000; // Electric Cherry
    //perk_costs["specialty_widows_wine"] = 4000; // Widow's Wine
    //perk_costs["specialty_tombstone"] = 2500; // Tombstone Soda
    //perk_costs["specialty_phdflopper_permanent"] = 2000; // PhD Flopper (via perma-perk)
    // Custom Perk costs as provided by the user (removed "(Custom)" text)
    //perk_costs["Downers_Delight"] = 4000;
    //perk_costs["Rampage"] = 6000;
    //perk_costs["PHD_FLOPPER"] = 6000;
    //perk_costs["ELECTRIC_CHERRY"] = 4000;
    //perk_costs["Guarding_Strike"] = 6000;
    //perk_costs["Dying_Wish"] = 8000;
    //perk_costs["Bloodthirst"] = 6000;
    //perk_costs["WIDOWS_WINE"] = 4000;
    //perk_costs["Ammo_Regen"] = 10000;
    //perk_costs["Executioners_Edge"] = 6000;
    //perk_costs["MULE"] = 4000;
    //perk_costs["Headshot_Mayhem"] = 10000;
    //perk_costs["THUNDER_WALL"] = 8000;
    //perk_costs["Burn_Heart"] = 6000;

    cost = perk_costs[perk_name];

    if(self hasPerk(perk_name))
    {
        self iPrintLnBold("^5You already have this perk^7!");
        return;
    }

    if(self.score >= cost)
    {
        self.score -= cost;
        self maps\mp\zombies\_zm_perks::give_perk(perk_name);
        self iPrintLnBold("^5Purchased perk for ^7$" + cost);
    }
    else
    {
        self iPrintLnBold("^5Need ^7$" + cost + " ^5to buy this perk^7!");
    }
}

// NEW FUNCTION: Allows player to Pack-a-Punch their current weapon.
packAPunchWeapon()
{
    current_weapon = self getCurrentWeapon();

    if(!isDefined(current_weapon) || current_weapon == "none" || current_weapon == "")
    {
        self iPrintLnBold("^5No weapon to Pack-a-Punch^7!");
        return;
    }

    if(self.score >= 5000)
    {
        // Get Pack-a-Punch version of weapon
        pap_weapon = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(current_weapon, false);

        if(isDefined(pap_weapon) && pap_weapon != current_weapon) // Check if an upgrade actually exists
        {
            self.score -= 5000;
            self takeWeapon(current_weapon);
            self giveWeapon(pap_weapon);
            self switchToWeapon(pap_weapon);
            self iPrintLnBold("^5Weapon Pack-a-Punche`d for ^7$5000!");
        }
        else
        {
            self iPrintLnBold("^5This weapon cannot be Pack-a-Punche`d or is already upgraded^7!");
        }
    }
    else
    {
        self iPrintLnBold("^5Need ^7$5000 ^5to Pack-a-Punch^7!");
    }
}

// NEW FUNCTION: Gives max ammo for the current weapon.
maxAmmoWeapon()
{
    current_weapon = self getCurrentWeapon();

    if(!isDefined(current_weapon) || current_weapon == "none" || current_weapon == "")
    {
        self iPrintLnBold("^5No weapon selected^7!");
        return;
    }

    if(self.score >= 5000)
    {
        self.score -= 5000;
        self giveMaxAmmo(current_weapon);
        self iPrintLnBold("^5Max ammo given for ^7$5000!");
    }
    else
    {
        self iPrintLnBold("^5Need ^7$4500 ^5for max ammo^7!");
    }
}

// NEW FUNCTION: Mystery Box Spin
mysteryBoxSpin_logic()
{
    SPIN_COST = 2500; // New cost
    if (self.score < SPIN_COST) {
        // Inform the player they don't have enough money
        self iPrintLnBold("^5Need ^7$" + SPIN_COST + " ^5to spin the Mystery Box^7!");
        return; // Exit the function if insufficient funds
    }

    // Deduct the spin cost from the player's score
    self.score -= SPIN_COST;

    // Initialize separate lists for non-Pack-a-Punched (PaP) and PaP weapons
    non_pap_weapons = [];
    pap_weapons = [];

    // --- SNIPER RIFLES ---
    non_pap_weapons[non_pap_weapons.size] = "dsr50_zm";
    pap_weapons[pap_weapons.size] = "dsr50_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "barretm82_zm";
    pap_weapons[pap_weapons.size] = "barretm82_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "svu_zm";
    pap_weapons[pap_weapons.size] = "svu_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "ballista_zm";
    pap_weapons[pap_weapons.size] = "ballista_upgraded_zm";

    // --- SMGS ---
    non_pap_weapons[non_pap_weapons.size] = "ak74u_zm";
    pap_weapons[pap_weapons.size] = "ak74u_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "mp5k_zm";
    pap_weapons[pap_weapons.size] = "mp5k_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "pdw57_zm";
    pap_weapons[pap_weapons.size] = "pdw57_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "qcw05_zm"; // Chicom
    pap_weapons[pap_weapons.size] = "qcw05_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "thompson_zm";
    pap_weapons[pap_weapons.size] = "thompson_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "uzi_zm";
    pap_weapons[pap_weapons.size] = "uzi_upgraded_zm";
    // Removed mp40_zm and mp40_stalker_zm as they were causing issues
    non_pap_weapons[non_pap_weapons.size] = "evoskorpion_zm";
    pap_weapons[pap_weapons.size] = "evoskorpion_upgraded_zm";
    // Add variations with extended clips from Origins list
    non_pap_weapons[non_pap_weapons.size] = "ak74u_extclip_zm";
    pap_weapons[pap_weapons.size] = "ak74u_extclip_upgraded_zm";

    // --- ASSAULT RIFLES ---
    non_pap_weapons[non_pap_weapons.size] = "fnfal_zm";
    pap_weapons[pap_weapons.size] = "fnfal_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "m14_zm";
    pap_weapons[pap_weapons.size] = "m14_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "saritch_zm"; // SMR
    pap_weapons[pap_weapons.size] = "saritch_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "m16_zm";
    pap_weapons[pap_weapons.size] = "m16_gl_upgraded_zm"; // M16 with grenade launcher, assume this is the PaP variant
    non_pap_weapons[non_pap_weapons.size] = "tar21_zm";
    pap_weapons[pap_weapons.size] = "tar21_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "gl_tar21_zm"; // M16 with grenade launcher, assume no separate PaP
    non_pap_weapons[non_pap_weapons.size] = "galil_zm";
    pap_weapons[pap_weapons.size] = "galil_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "an94_zm";
    pap_weapons[pap_weapons.size] = "an94_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "type95_zm"; // Type-25
    pap_weapons[pap_weapons.size] = "type95_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "xm8_zm"; // M8A1
    pap_weapons[pap_weapons.size] = "xm8_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "ak47_zm";
    pap_weapons[pap_weapons.size] = "ak47_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "scar_zm";
    pap_weapons[pap_weapons.size] = "scar_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "hk416_zm"; // M27
    pap_weapons[pap_weapons.size] = "hk416_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "mp44_zm";
    pap_weapons[pap_weapons.size] = "mp44_upgraded_zm";

    // --- SHOTGUNS ---
    non_pap_weapons[non_pap_weapons.size] = "870mcs_zm"; // R870-MCS
    pap_weapons[pap_weapons.size] = "870mcs_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "rottweil72_zm"; // Olympia
    pap_weapons[pap_weapons.size] = "rottweil72_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "saiga12_zm"; // S-12
    pap_weapons[pap_weapons.size] = "saiga12_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "srm1216_zm"; // M1216
    pap_weapons[pap_weapons.size] = "srm1216_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "ksg_zm";
    pap_weapons[pap_weapons.size] = "ksg_upgraded_zm";

    // --- LMGS ---
    non_pap_weapons[non_pap_weapons.size] = "lsat_zm";
    pap_weapons[pap_weapons.size] = "lsat_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "hamr_zm";
    pap_weapons[pap_weapons.size] = "hamr_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "rpd_zm";
    pap_weapons[pap_weapons.size] = "rpd_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "mg08_zm";
    pap_weapons[pap_weapons.size] = "mg08_upgraded_zm";
    // Removed Death Machine (LMG version from Mob) - This line was a comment in your original code, kept as-is.

    // --- PISTOLS ---
    non_pap_weapons[non_pap_weapons.size] = "m1911_zm";
    pap_weapons[pap_weapons.size] = "m1911_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "rnma_zm"; // Remington New Model Army
    pap_weapons[pap_weapons.size] = "rnma_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "judge_zm"; // Executioner
    pap_weapons[pap_weapons.size] = "judge_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "kard_zm"; // KAP-40
    pap_weapons[pap_weapons.size] = "kard_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "fiveseven_zm";
    pap_weapons[pap_weapons.size] = "fiveseven_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "fivesevendw_zm"; // Five-Seven Dual-Wield
    pap_weapons[pap_weapons.size] = "fivesevendw_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "beretta93r_zm"; // B23R
    pap_weapons[pap_weapons.size] = "beretta93r_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "python_zm";
    pap_weapons[pap_weapons.size] = "python_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "c96_zm"; // Mauser
    pap_weapons[pap_weapons.size] = "c96_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "beretta93r_extclip_zm";
    pap_weapons[pap_weapons.size] = "beretta93r_extclip_upgraded_zm";

    // --- LAUNCHERS ---
    non_pap_weapons[non_pap_weapons.size] = "usrpg_zm"; // RPG
    pap_weapons[pap_weapons.size] = "usrpg_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "m32_zm"; // War Machine
    pap_weapons[pap_weapons.size] = "m32_upgraded_zm";

    // --- SPECIAL WEAPONS (Ballistic Knife variants) ---
    non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_zm";
    pap_weapons[pap_weapons.size] = "knife_ballistic_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_bowie_zm";
    pap_weapons[pap_weapons.size] = "knife_ballistic_bowie_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "knife_ballistic_no_melee_zm";
    pap_weapons[pap_weapons.size] = "knife_ballistic_no_melee_upgraded_zm";

    // --- WONDER WEAPONS ---
    non_pap_weapons[non_pap_weapons.size] = "ray_gun_zm";
    pap_weapons[pap_weapons.size] = "ray_gun_upgraded_zm";
    non_pap_weapons[non_pap_weapons.size] = "raygun_mark2_zm";
    pap_weapons[pap_weapons.size] = "raygun_mark2_upgraded_zm";
    // Removed slowgun_zm (Paralyzer), slipgun_zm (Sliquifier), and blundergat_zm variants as they were causing issues
    // Removed all staff weapons as they were causing issues
    // Note: If you later confirm these work in your environment, you can re-add them.

    // Determine which weapon pool to draw from based on a weighted chance
    // Example: 70% chance for a non-PaP weapon, 30% chance for a PaP weapon
    roll = randomint(100); // Generates a random integer from 0 to 99
    given_weapon = ""; // Initialize variable to hold the chosen weapon string

    // Choose from non-PaP pool if roll is less than 70, otherwise choose from PaP pool
    if (roll < 70) {
        if (non_pap_weapons.size > 0) {
            random_index = randomint(non_pap_weapons.size); // Get a random index within the non-PaP array
            given_weapon = non_pap_weapons[random_index]; // Select the weapon
        } else {
            // Fallback if non-PaP pool is unexpectedly empty (shouldn't happen with this list)
            self iPrintLnBold("^3WARNING^7: Non-PaP weapon pool empty, falling back to PaP weapons.");
            random_index = randomint(pap_weapons.size);
            given_weapon = pap_weapons[random_index];
        }
    } else {
        if (pap_weapons.size > 0) {
            random_index = randomint(pap_weapons.size); // Get a random index within the PaP array
            given_weapon = pap_weapons[random_index]; // Select the weapon
        } else {
            // Fallback if PaP pool is unexpectedly empty (shouldn't happen with this list)
            self iPrintLnBold("^3WARNING^7: PaP weapon pool empty, falling back to non-PaP weapons.");
            random_index = randomint(non_pap_weapons.size);
            given_weapon = non_pap_weapons[random_index];
        }
    }

    // Final check: if no weapon was chosen for some reason (highly unlikely with static lists)
    if (given_weapon == "") {
        self iPrintLnBold("^5Error^7: ^5Mystery Box failed to deliver a weapon^7!");
        return; // Exit if no weapon could be determined
    }

    // Take away the player's current weapon(s) before giving the new one
    self takeallweapons();

    // Give the new weapon and switch to it
    self giveWeapon(given_weapon);
    self switchToWeapon(given_weapon);
    self giveMaxAmmo(given_weapon); // Give max ammo for the new weapon

    // Inform the player what weapon they received
    self iPrintLnBold("^5Mystery Box delivered^7: " + GetWeaponName(given_weapon) + "!");
}

// NEW FUNCTION: Sell Current Weapon
//sellWeapon_logic()
//{
//    current_weapon = self getCurrentWeapon();
//
    // Check if the player has a weapon equipped and it's not the starting pistol or knife
//    if(!isDefined(current_weapon) || current_weapon == "none" || current_weapon == "" || current_weapon == "zm_knife" || current_weapon == "m1911_zm")
//    {
//        self iPrintLnBold("^1Cannot sell default weapon or no weapon equipped!");
//        return;
//    }

//    SELL_VALUE = 1000; // Fixed sell value for simplicity

//    self.score += SELL_VALUE; // Add points to player's score
//    self takeWeapon(current_weapon); // Take away the weapon

//    self iPrintLnBold("^2Sold " + GetWeaponName(current_weapon) + " for $" + SELL_VALUE + "!");
//}

// Helper to get a readable weapon name (simple version, can be expanded)
GetWeaponName(weapon_alias)
{
    switch(weapon_alias)
    {
        case "ray_gun_zm": return "Ray Gun";
        case "thundergun_zm": return "Thundergun";
        case "galil_zm": return "Galil";
        case "commando_zm": return "Commando";
        case "ak74u_zm": return "AK74u";
        case "fnfal_zm": return "FN FAL";
        case "m16_zm": return "M16";
        case "mp5k_zm": return "MP5K";
        case "stakeout_zm": return "Stakeout";
        case "rpk_zm": return "RPK";
        case "hk21_zm": return "HK21";
        case "china_lake_zm": return "China Lake";
        case "ballistic_knife_zm": return "Ballistic Knife";
        // Removed BO1 weapons from here: Crossbow, M72 LAW, G11, Famas, Spectre, AUG
        case "commando_zm_upgraded": return "Commando (PaP)";
        case "ray_gun_upgraded_zm": return "Ray Gun (PaP)";
        case "dsr50_zm": return "DSR 50";
        case "dsr50_upgraded_zm": return "DSR 50 (PaP)";
        case "barretm82_zm": return "Barrett M82";
        case "barretm82_upgraded_zm": return "Barrett M82 (PaP)";
        case "svu_zm": return "SVU";
        case "svu_upgraded_zm": return "SVU (PaP)";
        case "qcw05_zm": return "Chicom CQB";
        case "qcw05_upgraded_zm": return "Chicom CQB (PaP)";
        case "pdw57_zm": return "PDW-57";
        case "pdw57_upgraded_zm": return "PDW-57 (PaP)";
        case "type95_zm": return "Type 25";
        case "type95_upgraded_zm": return "Type 25 (PaP)";
        case "xm8_zm": return "M8A1";
        case "xm8_upgraded_zm": return "M8A1 (PaP)";
        case "rpd_zm": return "RPD";
        case "rpd_upgraded_zm": return "RPD (PaP)";
        case "python_zm": return "Python";
        case "python_upgraded_zm": return "Python (PaP)";
        case "slipgun_zm": return "Sliquifier";
        case "slipgun_upgraded_zm": return "Sliquifier (PaP)";
        case "thompson_zm": return "Thompson";
        case "thompson_upgraded_zm": return "Thompson (PaP)";
        case "uzi_zm": return "Uzi";
        case "uzi_upgraded_zm": return "Uzi (PaP)";
        case "ak47_zm": return "AK-47";
        case "ak47_upgraded_zm": return "AK-47 (PaP)";
        case "blundergat_zm": return "Blundergat";
        case "blundergat_upgraded_zm": return "Blundergat (PaP)";
        case "blundersplat_zm": return "Acidgat";
        case "blundersplat_upgraded_zm": return "Acidgat (PaP)";
        case "ballista_zm": return "Ballista";
        case "ballista_upgraded_zm": return "Ballista (PaP)";
        case "mp40_zm": return "MP40";
        case "mp40_upgraded_zm": return "MP40 (PaP)";
        case "mp40_stalker_zm": return "MP40 Stalker";
        case "mp40_stalker_upgraded_zm": return "MP40 Stalker (PaP)";
        case "evoskorpion_zm": return "Skorpion EVO";
        case "evoskorpion_upgraded_zm": return "Skorpion EVO (PaP)";
        case "mp44_zm": return "MP44";
        case "mp44_upgraded_zm": return "MP44 (PaP)";
        case "scar_zm": return "SCAR-H";
        case "scar_upgraded_zm": return "SCAR-H (PaP)";
        case "ksg_zm": return "KSG";
        case "ksg_upgraded_zm": return "KSG (PaP)";
        case "mg08_zm": return "MG08";
        case "mg08_upgraded_zm": return "MG08 (PaP)";
        case "c96_zm": return "Mauser C96";
        case "c96_upgraded_zm": return "Mauser C96 (PaP)";
        case "beretta93r_extclip_zm": return "B23R (Ext. Clip)";
        case "beretta93r_extclip_upgraded_zm": return "B23R (Ext. Clip) (PaP)";
        case "staff_fire_zm": return "Fire Staff";
        case "staff_fire_upgraded_zm": return "Fire Staff (Upgraded)";
        case "staff_water_zm": return "Ice Staff";
        case "staff_water_upgraded_zm": return "Ice Staff (Upgraded)";
        case "staff_water_zm_cheap": return "Ice Staff (Cheap)"; // Specific for Origins
        case "staff_air_zm": return "Wind Staff";
        case "staff_air_upgraded_zm": return "Wind Staff (Upgraded)";
        case "staff_lightning_zm": return "Lightning Staff";
        case "staff_lightning_upgraded_zm": return "Lightning Staff (Upgraded)";
        case "staff_revive_zm": return "Staff of Revival"; // From Origins Misc
        case "hk416_zm": return "M27";
        case "hk416_upgraded_zm": return "M27 (PaP)";
        case "knife_ballistic_bowie_zm": return "Ballistic Bowie"; // Added for specific Ballistic Knife variant
        case "knife_ballistic_no_melee_zm": return "Ballistic Knife (No Melee)"; // Added for specific Ballistic Knife variant
        case "ak74u_extclip_zm": return "AK74u (Ext. Clip)"; // Added for specific AK74u variant
        case "ak74u_extclip_upgraded_zm": return "AK74u (Ext. Clip) (PaP)"; // Added for specific AK74u variant
        case "gl_tar21_zm": return "GL TAR-21"; // Added for specific GL TAR-21 variant
        default: return weapon_alias; // Fallback for unlisted weapons
    }
}

// NEW FUNCTION: Toggles Zombie ESP (outlines zombies).
toggleZombieESP()
{
    self endon("disconnect");

    if(!isDefined(self.zombieESP))
        self.zombieESP = false;

    if(!self.zombieESP)
    {
        self thread enableZombieESP();
        self iPrintLn("^5Zombie ESP^7: ^2ON");
        self.zombieESP = true;
    }
    else
    {
        self thread disableZombieESP();
        self iPrintLn("^5Zombie ESP^7: ^1OFF");
        self.zombieESP = false;
    }
}

// NEW FUNCTION: Enables Zombie ESP, spawning lines for zombies.
enableZombieESP()
{
    self endon("disconnect");
    self thread getZombieTargets();
}

// NEW FUNCTION: Disables Zombie ESP, destroying lines.
disableZombieESP()
{
    self notify("esp_end");
    if(isDefined(self.esp) && isDefined(self.esp.targets))
    {
        for(i = 0; i < self.esp.targets.size; i++)
        {
            if(isDefined(self.esp.targets[i]) && isDefined(self.esp.targets[i].bottomline)) // Check if target is defined before accessing
                self.esp.targets[i].bottomline destroy();
        }
        self.esp.targets = []; // Clear the array
    }
}

// NEW FUNCTION: Continuously gets and updates zombie outlines for ESP.
getZombieTargets()
{
    self endon("disconnect");
    self endon("esp_end");
    level endon("game_ended");

    for(;;)
    {
        // Clean up old targets first
        if(isDefined(self.esp) && isDefined(self.esp.targets))
        {
            for(i = 0; i < self.esp.targets.size; i++)
            {
                if(isDefined(self.esp.targets[i]) && isDefined(self.esp.targets[i].bottomline))
                    self.esp.targets[i].bottomline destroy();
            }
        }

        self.esp = spawnStruct();
        self.esp.targets = [];

        zombies = getaiarray("axis"); // Get all active zombies

        for(i = 0; i < zombies.size; i++)
        {
            if(isDefined(zombies[i]) && isAlive(zombies[i]))
            {
                self.esp.targets[i] = spawnStruct();
                self.esp.targets[i].zombie = zombies[i];
                self thread monitorZombieTarget(self.esp.targets[i]);
            }
        }

        wait 2.0; // Update zombie list every 2 seconds
    }
}

// NEW FUNCTION: Monitors a single zombie for ESP outline.
monitorZombieTarget(target)
{
    self endon("disconnect");
    self endon("esp_end");
    self endon("death");
    level endon("game_ended");

    target.bottomline = self createZombieBottomLine();

    while(isDefined(target.zombie) && isAlive(target.zombie))
    {
        zombie_pos = target.zombie.origin;
        zombie_head = target.zombie getTagOrigin("j_head");

        // Position bottom line
        target.bottomline.x = zombie_pos[0];
        target.bottomline.y = zombie_pos[1];
        target.bottomline.z = zombie_pos[2] + 35; // Adjust height as needed

        // Check visibility and set colors
        // Default color for visible is AQUA (0.0, 1.0, 1.0)
        outline_color = (0.0, 1.0, 1.0);
        // Perform a trace from player's head to zombie's head
        if(!bulletTracePassed(self getTagOrigin("j_head"), zombie_head, false, self))
        {
            // Color for non-visible (behind wall) is DARK BLUE (0, 0, 0.5)
            outline_color = (0, 0, 0.5);
        }

        target.bottomline.color = outline_color;

        wait 0.05; // Update position and color frequently
    }

    // Cleanup if zombie dies or disappears
    if(isDefined(target.bottomline))
        target.bottomline destroy();
}

// NEW FUNCTION: Creates the visual line for Zombie ESP.
createZombieBottomLine()
{
    bottomline = newClientHudElem(self);
    bottomline.elemtype = "icon";
    bottomline.sort = 1;
    bottomline.archived = false;
    bottomline.alpha = 0.8;
    // Default color for the line is AQUA (0.0, 1.0, 1.0)
    bottomline.color = (0.0, 1.0, 1.0);
    bottomline setShader("white", 20, 1); // Horizontal line, 20 units wide, 1 unit high
    bottomline setWaypoint(true, true); // Make it a waypoint (follows the entity)
    return bottomline;
}
