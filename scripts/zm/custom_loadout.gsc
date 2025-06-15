// zm_custom_loadout.gsc

init()
{
    // Precache all weapons used in the menu
    // These names are now based on the definitive list provided by the user for BO2 Zombies on Plutonium.
    precacheItem("m1911_zm");
    precacheItem("mp5k_zm");
    precacheItem("dsr50_zm");
    precacheItem("bowie_knife_zm");

    level thread onPlayerConnected();
    iprintln("^2[ZM Loadout] Initialized.");
}

onPlayerConnected()
{
    for (;;)
    {
        level waittill("connected", player);
        player thread onPlayerSpawned();
    }
}

onPlayerSpawned()
{
    self endon("disconnect");

    for (;;)
    {
        self waittill("spawned_player");

        // Ensure the menu only opens once per spawn or at game start if desired
        // If you want the menu to reappear every spawn, this is fine.
        // If you want it only once at the beginning, you'd add a flag here.
        self thread loadoutMenu();
    }
}

loadoutMenu()
{
    self endon("disconnect");
    // Ensure the menu is destroyed if player disconnects mid-menu.
    self endon("loadout_chosen"); // End if a loadout is chosen
    self endon("menu_closed");    // End if menu is explicitly closed without selection

    self EnableInvulnerability();
    self.ignoreme = true; // Prevent zombies from targeting player during menu interaction

    // Define menu options and their corresponding internal weapon values
    self.menuList = [];
    self.menuValues = [];

    // --- UPDATED: Using verified Plutonium BO2 Zombies weapon codes! ---
    // Selected a few common/good starting weapons from the provided list.
    self.menuList[self.menuList.size] = "Bowie Knife";
    self.menuValues[self.menuValues.size] = "bowie_knife_zm";
    self.menuList[self.menuList.size] = "M1911";
    self.menuValues[self.menuValues.size] = "m1911_zm";
    self.menuList[self.menuList.size] = "MP5";
    self.menuValues[self.menuValues.size] = "mp5k_zm";
    self.menuList[self.menuList.size] = "DSR50";
    self.menuValues[self.menuValues.size] = "dsr50_zm";


    menuTitle = "^5Select Starting Weapon";
    menuItems = self.menuList;

    self.menuElements = self createMenu(menuTitle, menuItems);

    self.currentItem = 0;
    self.menuOpen = true;
    self.lastMenuOpenInputTime = 0;
    self.lastMenuNavInputTime = 0;

    // Show menu and highlight first item
    self toggleMenuVisibility(true, self.menuElements);
    if (menuItems.size > 0) {
        self.menuElements["options"][self.currentItem].color = (0, 1, 1); // Highlight color (Cyan)
    }

    while (1)
    {
        // Toggle menu visibility (ADS + Melee)
        if (self AdsButtonPressed() && self MeleeButtonPressed() && getTime() > self.lastMenuOpenInputTime + 500)
        {
            self.menuOpen = !self.menuOpen;
            self toggleMenuVisibility(self.menuOpen, self.menuElements);
            self.lastMenuOpenInputTime = getTime();
            self.lastMenuNavInputTime = getTime(); // Reset nav input time too

            if (self.menuOpen)
            {
                // Reset highlight when reopening menu
                self.currentItem = 0;
                foreach (option in self.menuElements["options"])
                {
                    if (isDefined(option)) option.color = (1, 1, 1); // Reset all to white
                }
                if (menuItems.size > 0 && isDefined(self.menuElements["options"][self.currentItem])) {
                    self.menuElements["options"][self.currentItem].color = (0, 1, 1); // Highlight first item
                }
            }
        }

        if (self.menuOpen)
        {
            // Handle menu navigation (ActionSlotOne/Two for up/down)
            self.currentItem = self handleMenuInput(self.menuElements, self.currentItem, menuItems.size, (0, 1, 1));

            // Select weapon (Jump button)
            if (self JumpButtonPressed() && getTime() > self.lastMenuNavInputTime + 200)
            {
                self.selectedWeapon = self.menuValues[self.currentItem];

                // Clear current weapons before giving new one to avoid conflicts
                self TakeAllWeapons();

                self GiveWeapon(self.selectedWeapon, 0); // Give the selected weapon
                self GiveMaxAmmo(self.selectedWeapon);   // Give max ammo for it
                self SwitchToWeapon(self.selectedWeapon); // Switch to the new weapon

                // Hide and destroy menu elements
                self toggleMenuVisibility(false, self.menuElements);
                foreach (option in self.menuElements["options"])
                {
                    if (isDefined(option)) option destroy();
                }
                if (isDefined(self.menuElements["background"])) self.menuElements["background"] destroy();
                if (isDefined(self.menuElements["title"])) self.menuElements["title"] destroy();

                // Re-enable player interaction
                self DisableInvulnerability();
                self.ignoreme = false;

                self notify("loadout_chosen"); // Notify that a loadout has been chosen
                break; // Exit the menu loop
            }
            // Cancel/Close menu (Stance button)
            else if (self StanceButtonPressed() && getTime() > self.lastMenuNavInputTime + 200)
            {
                self.menuOpen = false;
                self toggleMenuVisibility(false, self.menuElements);
                self.lastMenuNavInputTime = getTime(); // Update debounce time

                // Destroy menu elements on cancel
                foreach (option in self.menuElements["options"])
                {
                    if (isDefined(option)) option destroy();
                }
                if (isDefined(self.menuElements["background"])) self.menuElements["background"] destroy();
                if (isDefined(self.menuElements["title"])) self.menuElements["title"] destroy();

                // Re-enable player interaction
                self DisableInvulnerability();
                self.ignoreme = false;

                iprintln("^2[ZM Loadout] Menu closed without selection.");
                self notify("menu_closed"); // Notify that menu was closed
                break; // Exit the menu loop
            }
        }

        wait 0.05; // Small delay to prevent excessive loop iteration
    }
}

// Helper function to create HUD text elements
createText(font, fontScale, alignX, alignY, x, y, text)
{
    hudText = newClientHudElem(self);
    hudText.fontScale = fontScale;
    hudText.x = x;
    hudText.y = y;
    hudText.alignX = alignX;
    hudText.alignY = alignY;
    hudText.horzAlign = alignX; // Horizontal alignment within the element's space
    hudText.vertAlign = alignY; // Vertical alignment within the element's space
    hudText.font = font;
    hudText setText(text);
    return hudText;
}

// Helper function to create HUD rectangle elements (for background)
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
    rect.shader = "white"; // Use a white shader to create a solid color rectangle
    rect.sort = -1; // Render behind other HUD elements
    return rect;
}

// Function to create all menu HUD elements
createMenu(title, items)
{
    menuElements = [];

    // Calculate menu dimensions based on item count
    menuHeight = (items.size * 25) + 40; // Increased spacing and padding slightly for better look
    menuWidth = 350; // Increased width slightly
    centerX = 0; // Center horizontally
    // Position menu slightly above center vertically for better visibility
    centerY = - (menuHeight / 2) + 250; // Adjusted for better vertical centering of the whole menu

    // Create background rectangle
    menuElements["background"] = self createRectangle("CENTER", "CENTER", centerX, centerY, menuWidth, menuHeight, (0, 0, 0), 0.7);
    menuElements["background"].sort = -1; // Ensure background is behind text

    // Create title text
    // Title is placed relative to the top of the background element
    // 'centerY - (menuHeight / 2)' would be the top edge of the background when aligned "CENTER", "CENTER" and adjusted by 'centerY' offset
    menuElements["title"] = self createText("objective", 1.4, "CENTER", "TOP", centerX, (centerY - (menuHeight / 2)) + 20, title);
    menuElements["title"].sort = 0; // Render title above background

    menuElements["options"] = [];
    // Calculate startY for options to be below the title and centered vertically if possible
    // A fixed offset from the vertical center of the menu itself might be more reliable
    // Options will start at 'centerY' (the effective vertical center of the menu) and then offset upwards
    startY = (centerY + 30) - ((items.size - 1) * 25 / 2); // Dynamically center items vertically
    spacing = 25; // Spacing between menu items

    for (i = 0; i < items.size; i++)
    {
        menuElements["options"][i] = self createText("objective", 1.1, "CENTER", "TOP", centerX, startY + (i * spacing), items[i]);
        menuElements["options"][i].sort = 0; // Render options above background
    }

    return menuElements;
}

// Function to toggle the visibility of all menu elements
toggleMenuVisibility(visible, menuElements)
{
    // Toggle HUD visibility as well when menu opens/closes
    self setClientUIVisibilityFlag("hud_visible", !visible);

    if (isDefined(menuElements["background"])) {
        menuElements["background"].alpha = visible ? 0.7 : 0;
    }
    if (isDefined(menuElements["title"])) {
        menuElements["title"].alpha = visible ? 1 : 0;
    }

    foreach (option in menuElements["options"])
    {
        if (isDefined(option)) {
            option.alpha = visible ? 1 : 0;
        }
    }
}

// Function to handle player input for menu navigation
handleMenuInput(menuElements, currentItem, itemCount, highlightColor)
{
    // Navigate up (ActionSlotOne)
    if (self ActionSlotOneButtonPressed() && getTime() > self.lastMenuNavInputTime + 200)
    {
        if (isDefined(menuElements["options"][currentItem]))
            menuElements["options"][currentItem].color = (1, 1, 1); // Unhighlight current

        currentItem = (currentItem - 1 + itemCount) % itemCount; // Loop around

        if (isDefined(menuElements["options"][currentItem]))
            menuElements["options"][currentItem].color = highlightColor; // Highlight new current

        self.lastMenuNavInputTime = getTime(); // Update debounce time
    }
    // Navigate down (ActionSlotTwo)
    else if (self ActionSlotTwoButtonPressed() && getTime() > self.lastMenuNavInputTime + 200)
    {
        if (isDefined(menuElements["options"][currentItem]))
            menuElements["options"][currentItem].color = (1, 1, 1); // Unhighlight current

        currentItem = (currentItem + 1) % itemCount; // Loop around

        if (isDefined(menuElements["options"][currentItem]))
            menuElements["options"][currentItem].color = highlightColor; // Highlight new current

        self.lastMenuNavInputTime = getTime(); // Update debounce time
    }

    return currentItem;
}
