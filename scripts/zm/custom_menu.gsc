#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\gametypes_zm\_hud_util;
#include maps\mp\gametypes_zm\_hud_message;
#include maps\mp\zombies\_zm_utility;

// For persistent data, Plutonium provides functions to get a player's XUID.
// We'll use this to create unique Dvar names for each player's bank account and highest round.
// You might need to include specific Plutonium headers if not already available in your environment,
// but for most common Plutonium setups, getXUID() should be globally accessible or handled by core scripts.

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
    level.point_bonuses[3] = 0.70;  // Rank 4: 70% (+25%)
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

    // Initialize main game-level threads.
    level thread onPlayerConnect();
    level thread auto_deposit_on_end_game();
    
    // Ensure the script runs in both server and custom games.
    setDvar("sv_allowscript", 1);
}

onPlayerConnect()
{
    // Loop indefinitely to catch every player connection.
    for(;;)
    {
        // Wait for a player to connect to the game.
        level waittill("connected", player);
        
        // Start player-specific threads for various functionalities.
        player thread onPlayerSpawned();           // Handles actions when a player spawns (initial or respawn).
        player thread init_rank_data();            // Initializes player rank and bonus data.
        player thread load_player_bank_account();  // Loads player's bank account from persistent Dvar.
        player thread load_player_highest_round(); // Loads player's highest round from persistent Dvar.
        player thread update_highest_round_loop(); // Monitors and updates player's highest round during gameplay.
        player check_bank_balance();                // Displays player's current bank balance.
        player thread monitor_player_revival();    // Monitors for player revival to re-apply health.
    }
}

onPlayerSpawned()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");
    
    // Loop indefinitely to catch every spawn event for this player.
    for(;;)
    {
        // Wait for the player to spawn into the game world.
        self waittill("spawned_player");
        
        // self.score = 5000;
        
        // This section ensures all player-specific initializations or
        // re-applications happen immediately after every spawn.
        self thread modMenu();                     // Starts the player's mod menu system.
        self thread init_player_hud();             // Initializes and updates player HUD elements.
        
        // IMPORTANT FIX: Call set_increased_health() here.
        // This ensures health is always 150 upon any full respawn (e.g., after death).
        self thread set_increased_health();     
        
        self thread moneyMultiplier();             // Starts the money multiplier for the player.    
        self thread create_menu_instructions();    // Displays menu instructions on screen.
        self thread init_rank_data();              // Re-initializes (or confirms initialization) of rank data. 
        self.zombieCounterActive = false;          // Resets zombie counter active status.
    }
}

// NEW FUNCTION: Monitors for player revival and re-applies increased health.
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
        self iPrintLnBold("^2You have been revived! Health reset to 150.");
    }
}

create_menu_instructions()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");
    
    // Create and position the menu instructions HUD element.
    instructions = self createText("objective", 1.15, "RIGHT", "TOP", -10, 10, "^5ADS ^7+ ^5Melee^7: ^5Open Menu ^7| ^5Crouch^7: ^5Close Menu");
    instructions.alpha = 0.8;      // Set transparency.
    instructions.hideWhenInMenu = true; // Hide when the menu is open.
}

modMenu()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");
    
    // Define the menu title and available items.
    menuTitle = "^5Control Panel";
    // We'll update the first menu item (Rankup) dynamically.
    menuItems = [];
    menuItems[0] = "Rankup"; // Placeholder, text will be set dynamically
    menuItems[1] = "Rank Status";
    menuItems[2] = "Withdraw 25%";
    menuItems[3] = "Withdraw 50%";
    menuItems[4] = "Withdraw 100%";
    menuItems[5] = "Deposit 25%";
    menuItems[6] = "Deposit 50%";
    menuItems[7] = "Deposit 100%";
    menuItems[8] = "Check Balance";
    menuItems[9] = "Toggle Zombie Counter";
    menuItems[10] = "Toggle AFK Mode";
    
    // Create the actual menu elements (background, title, options).
    menuElements = self createMenu(menuTitle, menuItems);
    
    currentItem = 0;    // Initialize selected menu item.
    menuOpen = false;   // Initialize menu state.
    // Timers to prevent rapid menu open/close or navigation due to button mashing.
    self.lastMenuOpenInputTime = 0; 
    self.lastMenuNavInputTime = 0;  
    
    // Initially hide the menu.
    self toggleMenuVisibility(false, menuElements);
    
    // Main loop for menu interaction.
    while(1)
    {
        // Dynamically update the Rankup menu item text here.
        // This makes sure it always shows the correct cost for the next rank.
        if (self.rankLevel < level.MAX_RANK) {
            nextRankCost = level.rank_costs[self.rankLevel - 1];
            menuElements["options"][0] setText("Rankup ($" + self convert_to_thousands(nextRankCost) + ")");
        } else {
            menuElements["options"][0] setText("Rankup (MAX RANK)");
        }

        // Check for input to open/close the menu (ADS + Melee).
        if(self AdsButtonPressed() && self MeleeButtonPressed() && getTime() > self.lastMenuOpenInputTime + 500)
        {
            menuOpen = !menuOpen; // Toggle menu state.
            self toggleMenuVisibility(menuOpen, menuElements); // Update menu visibility.
            self.lastMenuOpenInputTime = getTime(); // Reset open/close timer.

            // If menu just opened, reset highlight to the first item.
            if (menuOpen) {
                currentItem = 0; // Reset current item to 0.
                // De-highlight all options first.
                foreach(option in menuElements["options"]) {
                    option.color = (1, 1, 1); // White color for unhighlighted.
                }
                // Highlight the current (first) item.
                menuElements["options"][currentItem].color = (0, 1, 1); // Aqua highlight for current.
            }
        }
        
        // If the menu is open, handle navigation and selection.
        if(menuOpen)
        {
            // Update the current selected item based on player input.
            currentItem = self handleMenuInput(menuElements, currentItem, menuItems.size, (0, 1, 1));
            
            // Check for selection input (Jump button).
            if(self jumpButtonPressed() && getTime() > self.lastMenuNavInputTime + 200) 
            {
                // Execute the action corresponding to the selected menu item.
                switch(currentItem)
                {
                    case 0: self thread rankup_logic(); break;
                    case 1: self thread status_logic(); break;
                    case 2: self thread withdraw_logic(0.25); break;
                    case 3: self thread withdraw_logic(0.5); break;
                    case 4: self thread withdraw_logic(1); break;
                    case 5: self thread deposit_logic(0.25); break;
                    case 6: self thread deposit_logic(0.5); break;
                    case 7: self thread deposit_logic(1); break;
                    case 8: self thread balance_logic(); break;
                    case 9: self thread toggle_zombie_counter(); break;
                    case 10: self thread toggleAfk(self); break;
                }
                self.lastMenuNavInputTime = getTime(); // Reset navigation timer after selection.
            }
            // Check for "back" input (Crouch button).
            else if(self stanceButtonPressed() && getTime() > self.lastMenuNavInputTime + 200) 
            {
                menuOpen = false; // Close the menu.
                self toggleMenuVisibility(false, menuElements); // Hide menu elements.
                self.lastMenuNavInputTime = getTime(); // Reset navigation timer after closing.
            }
        }
        
        wait 0.05; // Small delay to prevent excessive looping and conserve resources.
    }
}

// Creates and returns the HUD elements that form the menu.
createMenu(title, items)
{
    menuElements = [];
    
    // Create menu background.
    menuElements["background"] = self createRectangle("LEFT", "CENTER", 20, 100, 180, 270, (0, 0, 0), 0.7);
    menuElements["background"] setShader("white", 180, 270);
    menuElements["background"].sort = -1; // Render behind other HUD elements.

    // Create menu title.
    menuElements["title"] = self createText("objective", 1.4, "LEFT", "TOP", 122, 77, title);
    
    // Create menu options.
    menuElements["options"] = [];
    startY = 100;
    spacing = 20;
    for(i = 0; i < items.size; i++)
    {
        menuElements["options"][i] = self createText("objective", 1.1, "LEFT", "TOP", 75, startY + (i * spacing), items[i]);
    }
    
    // Create menu instructions.
    menuElements["instructions"] = self createText("objective", 0.9, "LEFT", "BOTTOM", 25, 365, "^3Jump^7: Select | ^3Crouch^7: Back");
    
    return menuElements;
}

// Toggles the visibility of all menu elements.
toggleMenuVisibility(visible, menuElements)
{
    menuElements["background"].alpha = visible ? 0.7 : 0;
    menuElements["title"].alpha = visible ? 1 : 0;
    menuElements["instructions"].alpha = visible ? 1 : 0;
    
    foreach(option in menuElements["options"])
    {
        option.alpha = visible ? 1 : 0;
    }
}

// Handles menu navigation input (Action Slot One/Two for up/down).
handleMenuInput(menuElements, currentItem, itemCount, highlightColor)
{
    // Move up in the menu.
    if(self actionSlotOneButtonPressed() && getTime() > self.lastInputTime + 200)
    {
        menuElements["options"][currentItem].color = (1, 1, 1); // De-highlight old item.
        currentItem = (currentItem - 1 + itemCount) % itemCount; // Cycle to previous item.
        menuElements["options"][currentItem].color = highlightColor; // Highlight new item.
        self.lastInputTime = getTime(); // Reset input timer.
    }
    // Move down in the menu.
    else if(self actionSlotTwoButtonPressed() && getTime() > self.lastInputTime + 200)
    {
        menuElements["options"][currentItem].color = (1, 1, 1); // De-highlight old item.
        currentItem = (currentItem + 1) % itemCount; // Cycle to next item.
        menuElements["options"][currentItem].color = highlightColor; // Highlight new item.
        self.lastInputTime = getTime(); // Reset input timer.
    }
    
    return currentItem; // Return the new current item index.
}

// Creates a rectangular HUD element.
createRectangle(alignX, alignY, x, y, width, height, color, alpha)
{
    rect = newClientHudElem(self);
    rect.alignX = alignX;
    rect.alignY = alignY;
    rect.x = x;
    rect.y = y;
    rect.width = width;
    rect.height = height;
    rect.color = color;
    rect.alpha = alpha;
    rect.shader = "white"; // Use a simple white shader for the rectangle.
    rect.sort = 0;
    rect.borderwidth = 2;
    rect.bordercolor = (0.5, 0.5, 0.5); // Light grey border.
    return rect;
}

// Creates a text-based HUD element.
createText(font, fontScale, alignX, alignY, x, y, text)
{
    hudText = newClientHudElem(self);
    hudText.fontScale = fontScale;
    hudText.x = x;
    hudText.y = y;
    hudText.alignX = alignX;
    hudText.alignY = alignY;
    hudText.horzAlign = alignX;
    hudText.vertAlign = alignY;
    hudText.font = font;
    hudText setText(text);
    return hudText;
}

init_player_hud()
{
    // This thread will end if the player disconnects.
    self endon("disconnect");
    
    // Create and position player HUD elements for health, rank, and bonuses.
    // Positioned at the top-right corner, slightly offset to avoid overlap with menu instructions.
    self.rankLevelHud = self createText("objective", 1.0, "RIGHT", "TOP", -10, 30, "^5Level^7: 1");  
    self.pointScalingHud = self createText("objective", 1.0, "RIGHT", "TOP", -10, 45, "^5Point Scaling^7: 0%"); 
    self.bulletDamageHud = self createText("objective", 1.0, "RIGHT", "TOP", -10, 60, "^5Bullet Damage^7: 0%"); 
    // NEW: Highest Round HUD element.
    self.highestRoundHud = self createText("objective", 1.0, "RIGHT", "TOP", -10, 75, "^5Highest Round^7: 0"); 

    // Set initial alpha (visibility) for all HUD elements.
    self.healthHud.alpha = 1;
    self.rankLevelHud.alpha = 1;
    self.pointScalingHud.alpha = 1;
    self.bulletDamageHud.alpha = 1;
    self.highestRoundHud.alpha = 1; 

    // Ensure highestRound is initialized to 0 if it hasn't been loaded from a Dvar yet.
    if (!isDefined(self.highestRound)) {
        self.highestRound = 0;
    }

    // Loop to continuously update the text of the HUD elements.
    for(;;)
    {
        self.rankLevelHud setText("^5Level^7: " + self.rankLevel);
        // Display point and bullet damage bonuses based on the player's current rank.
        self.pointScalingHud setText("^5Point Scaling^7: " + int(self.pointBonus * 100) + "%");
        self.bulletDamageHud setText("^5Bullet Damage^7: " + int(self.bulletDamageBonus * 100) + "%");
        self.highestRoundHud setText("^5Highest Round^7: " + self.highestRound);
        wait 0.1; // Update every 0.1 seconds.
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

// --- PERSISTENCE FUNCTIONS START ---

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
    self endon("disconnect");   // End if player disconnects.
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

// --- PERSISTENCE FUNCTIONS END ---

// Checks and displays the player's bank balance.
check_bank_balance()
{
    value = self.bank_account; 
    self iprintln("^7Checking bank balance...");
    wait 1.5;
    self iprintln("^7You have ^1" + self convert_to_money(value) + "^7 in the bank!");
}

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
        self iPrintLn("^7Deposit failed: Not enough money");
        return;
    }

    self bank_add(num_amount);
    self.score -= num_amount; // Subtract deposited amount from player's current score.
    self iPrintLn("^7Successfully deposited ^1" + convert_to_money(num_amount));
    self save_player_bank_account(); // Save bank account after deposit.
}

// Handles withdrawing a percentage of the player's bank balance to their current score.
withdraw_logic(percentage)
{
    balance = self bank_read(); // Read current bank balance.
    num_amount = int(balance * percentage); // Calculate withdrawal amount.

    if(balance <= 0)
    {
        self iPrintln("^7Withdraw failed: you have no money in the bank");
        return;
    }
    if(self.score >= 1000000)
    {
        self iPrintLn("^7Withdraw failed: Max score is $1,000,000.");
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
    self iPrintLn("^7Successfully withdrew ^1" + convert_to_money(num_amount));
    self save_player_bank_account(); // Save bank account after withdrawal.
}

// Displays the player's current bank balance.
balance_logic()
{
    value = self bank_read();
    self iPrintLn("^7Current balance: ^1" + self convert_to_money(value));
}

// Functions for interacting with the player's bank account variable.
bank_add(value) { self.bank_account += value; }
bank_sub(value) { self.bank_account -= value; }
bank_read()     { return self.bank_account; }
bank_write(value) { self.bank_account = value; }

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

// Initializes player rank and bonus data, ensuring it's only done once.
init_rank_data()
{
    // Initialize rankLevel and bonuses only if they are not already defined.
    // This ensures data persists across spawns but is set correctly on first connect.
    if(!isDefined(self.rankLevel))
    {
        self.rankLevel = 1;
        self.pointBonus = level.point_bonuses[0];        // Set initial point bonus for Rank 1.
        self.bulletDamageBonus = level.bullet_damage_bonuses[0]; // Set initial bullet damage bonus for Rank 1.
    }
}

// Handles the logic for a player to rank up.
rankup_logic()
{
    // Check if player is already at the maximum rank.
    if (self.rankLevel >= level.MAX_RANK)
    {
        self iPrintLnBold("^7You are already at Max Rank!");
        return;
    }

    // Get the cost required to rank up to the next level.
    // If current rank is 1, self.rankLevel - 1 will be 0, which correctly accesses
    // the cost to go from Rank 1 to Rank 2 (level.rank_costs[0]).
    POINTS_REQUIRED = level.rank_costs[self.rankLevel - 1];

    if (self.score >= POINTS_REQUIRED)
    {
        self.score -= POINTS_REQUIRED; // Deduct points for rank up.
        self.rankLevel += 1;          // Increment rank level.

        // Update bonuses based on the newly achieved rank.
        // If new rank is 2, self.rankLevel - 1 will be 1, which correctly accesses
        // the point bonus for Rank 2 (level.point_bonuses[1]).
        self.pointBonus = level.point_bonuses[self.rankLevel - 1];
        self.bulletDamageBonus = level.bullet_damage_bonuses[self.rankLevel - 1];

        // Display rank up messages with updated bonus percentages.
        self iPrintLnBold("^7Rank-up successful! Level: " + self.rankLevel);
        self iPrintLnBold("^7Point Scaling: " + int(self.pointBonus * 100) + "%");
        self iPrintLnBold("^7Bullet Damage: " + int(self.bulletDamageBonus * 100) + "%");
    }
    else
    {
        // Inform player if they don't have enough points, showing the remaining amount needed.
        self iPrintLnBold("^7Not enough points to rank up. You need " + self convert_to_money(POINTS_REQUIRED - self.score) + " more points.");
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

// Toggles the visibility and functionality of the zombie counter.
toggle_zombie_counter()
{
    self.zombieCounterActive = !self.zombieCounterActive; // Toggle active status.
    if(self.zombieCounterActive)
    {
        self thread zombie_counter(); // Start the counter thread.
        self iPrintLn("Zombie Counter: ^2ON");
    }
    else
    {
        if(isDefined(self.zombiecounter))
        {
            self.zombiecounter destroy(); // Destroy the HUD element if counter is turned off.
        }
        self iPrintLn("Zombie Counter: ^1OFF");
    }
}

// Displays the current number of zombies left on the HUD.
zombie_counter()
{
    self endon("disconnect");
    level endon("game_ended");
    
    // Destroy existing counter if it exists to prevent duplicates.
    if(isDefined(self.zombiecounter))
    {
        self.zombiecounter destroy();
    }
    
    flag_wait("initial_blackscreen_passed"); // Wait for game start.
    
    // Create and position the zombie counter HUD element.
    self.zombiecounter = createfontstring("Objective", 1.50); 
    self.zombiecounter setpoint("BOTTOM", "MIDDLE", 0, 200); 
    self.zombiecounter.alpha = 1;
    self.zombiecounter.hidewheninmenu = 1;
    self.zombiecounter.hidewhendead = 1;
    self.zombiecounter.label = &"^5Zombies Left^7: "; // Prefix text.
    
    // Loop to continuously update the zombie count.
    while(self.zombieCounterActive)
    {
        // Adjust transparency if player is in afterlife.
        if(isDefined(self.afterlife) && self.afterlife)
        {
            self.zombiecounter.alpha = 0.2;
        }
        else
        {
            self.zombiecounter.alpha = 1;
        }
        // Set the value of the counter to total zombies + current active zombies.
        self.zombiecounter setvalue(level.zombie_total + get_current_zombie_count());
        wait 0.05;
    }
    
    self.zombiecounter destroy(); // Destroy HUD element when counter is turned off.
}

// Toggles AFK (Away From Keyboard) mode for the player.
toggleAfk(player)
{
    // Initialize isAfk status if not already defined.
    if(!isDefined(player.isAfk))
        player.isAfk = false;

    if(!player.isAfk) // If not currently AFK, enable AFK mode.
    {
        player.isAfk = true;
        player iprintlnbold("AFK mode enabled");
        player enableInvulnerability();      // Make player invulnerable.
        player allowSpectateTeam("allies", true); // Allow spectating.
        player allowSpectateTeam("axis", true);
        player setMoveSpeedScale(0);        // Stop player movement.
        player disableWeapons();            // Disable weapons.
        player hide();                      // Hide the player model.
        
        // Hide various HUD elements while in AFK mode for a cleaner look.
        // Check for definition before attempting to access alpha property.
        if(isDefined(player.balanceHud)) player.balanceHud.alpha = 0;
        if(isDefined(player.healthHud)) player.healthHud.alpha = 0;
        if(isDefined(player.rankLevelHud)) player.rankLevelHud.alpha = 0;
        if(isDefined(player.pointScalingHud)) player.pointScalingHud.alpha = 0;
        if(isDefined(player.bulletDamageHud)) player.bulletDamageHud.alpha = 0;
        if(isDefined(player.zombiecounter)) player.zombiecounter.alpha = 0;
        if(isDefined(player.highestRoundHud)) player.highestRoundHud.alpha = 0;
    }
    else // If currently AFK, disable AFK mode.
    {
        player.isAfk = false;
        player iprintlnbold("AFK mode disabled. Godmode active for 15 seconds."); // Inform about temporary godmode.
        player thread safelyDisableAfk(); // Start thread to safely disable AFK features.
        
        // Show various HUD elements when AFK mode is disabled.
        // Check for definition before attempting to access alpha property.
        if(isDefined(player.balanceHud)) player.balanceHud.alpha = 0.8;
        if(isDefined(player.healthHud)) player.healthHud.alpha = 1;
        if(isDefined(player.rankLevelHud)) player.rankLevelHud.alpha = 1;
        if(isDefined(player.pointScalingHud)) player.pointScalingHud.alpha = 1;
        if(isDefined(player.bulletDamageHud)) player.bulletDamageHud.alpha = 1;
        if(isDefined(player.zombiecounter)) player.zombiecounter.alpha = 1;
        if(isDefined(player.highestRoundHud)) player.highestRoundHud.alpha = 1;
    }
}

// Safely disables AFK mode features after a delay, including temporary godmode.
safelyDisableAfk()
{
    self endon("disconnect");

    self allowSpectateTeam("allies", false); // Disable spectating.
    self allowSpectateTeam("axis", false);
    self setMoveSpeedScale(1);          // Restore player movement speed.
    self enableWeapons();               // Re-enable weapons.
    self show();                        // Show the player model.

    // Keep godmode active for 15 seconds after disabling AFK.
    wait 15;

    // Only disable invulnerability if the player hasn't re-enabled AFK mode during the wait.
    if(!self.isAfk) 
    {
        self disableInvulnerability();
        self iprintlnbold("Godmode deactivated. Be careful!");
    }
}

// Utility function to get the current count of active zombies (AI).
get_current_zombie_count()
{
    return getAIArray().size;
}
