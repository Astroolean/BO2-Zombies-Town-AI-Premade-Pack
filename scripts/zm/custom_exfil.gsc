#include maps\mp\_utility; 
#include common_scripts\utility; 
#include maps\mp\gametypes_zm\_hud_util; 
#include maps\mp\gametypes_zm\_hud_message; 
#include maps\mp\zombies\_zm; 

// Initialize the Exfil system
init() 
{ 
    precacheshader("waypoint_revive"); 
    precacheshader("scorebar_zom_1"); 
    setExfillocation(); // Set the exfil locations based on the map
    if (level.radiomodel != "") 
    { 
    	precachemodel(level.radiomodel); // Precache radio model if defined
    } 
    level thread createExfilIcon(); // Create and manage the exfil icon
    level.roundincrease = 5; // Rounds between exfil opportunities
    level.canexfil = 0; // Flag to check if exfil is available
    level.nextexfilround = 11; // Next round exfil will be available
    level.exfilstarted = 0; // Flag to check if exfil has started
    level.successfulexfil = 0; // Flag for successful exfil
    level.gameisending = 0; // Flag to indicate game is ending
    level.exfilplayervotes = 0; // Count of player votes for exfil
    level thread spawnExfil(); // Handle exfil trigger and voting
    level thread enableExfil(); // Enable exfil availability based on rounds
    level thread checkForRound(); // Check current round for exfil availability
	 
	level.round_wait_func = ::round_wait_exfil; // Custom round wait function for exfil
     
    level thread onPlayerConnect(); // Monitor player connections
} 

// Handle actions for players connecting to the game
onPlayerConnect() 
{ 
    for(;;) 
    { 
        level waittill("connected", player); // Wait for a player to connect
        player thread onPlayerSpawned(); // Handle actions when the player spawns
    } 
} 

// Handle actions for players spawning in the game
onPlayerSpawned() 
{ 
    self endon("disconnect"); // End this thread if player disconnects
	level endon("game_ended"); // End this thread if game ends
    for(;;) 
    { 
        self waittill("spawned_player"); // Wait for the player to spawn

		self thread exfilHUD(); // Display exfil HUD for the player
		self thread downOnExfil(); // Handle player death if outside exfil zone at end
		self thread showscoreboardtext(); // Show scoreboard text at game end
    } 
} 

// Create and manage the exfil icon on the map
createExfilIcon() 
{ 
	exfil_icon = newHudElem(); // Create a new HUD element for the icon
    exfil_icon.x = level.iconlocation[ 0 ]; // Set icon X position
    exfil_icon.y = level.iconlocation[ 1 ]; // Set icon Y position
	exfil_icon.z = level.iconlocation[ 2 ] + 80; // Set icon Z position (slightly above ground)
	exfil_icon.color = (1,1,1); // Set icon color
    exfil_icon.isshown = 1; // Make icon visible
    exfil_icon.archived = 0; // Do not archive (keep it active)
    exfil_icon setshader( "waypoint_revive_zm", 6, 6 ); // Set icon shader and size
    exfil_icon setwaypoint( 1 ); // Make it a waypoint
     
    while(1) 
    { 
    	if (level.canexfil == 1 && level.exfilstarted == 0) 
    	{ 
    		exfil_icon.alpha = 1; // Show icon if exfil is available but not started
    	} 
    	else if (level.canexfil == 1 && level.exfilstarted == 1) 
    	{ 
    		exfil_icon.alpha = 1; // Show icon if exfil is available and started
    		exfil_icon.x = level.exfillocation[ 0 ]; // Move icon to exfil location
    		exfil_icon.y = level.exfillocation[ 1 ]; 
 			exfil_icon.z = level.exfillocation[ 2 ] + 80; 
			exfil_icon setshader( "waypoint_revive_zm", 0, 0 ); // Update shader (might be for animation)
			exfil_icon setwaypoint( 1, "waypoint_revive_zm", 1 ); // Update waypoint (might be for animation)
    	} 
    	else if (level.canexfil == 0 && level.exfilstarted == 0) 
    	{ 
    		exfil_icon.alpha = 0; // Hide icon if exfil is not available
    	} 
    	if (level.gameisending == 1) 
    	{ 
    		exfil_icon.alpha = 0; // Hide icon if game is ending
    	} 
    	wait 0.1; // Short delay
    } 
} 

// Check the current round number to enable exfil
checkForRound() 
{ 
	while(1) 
	{ 
		if(level.round_number == level.nextexfilround) 
		{ 
			level.nextexfilround += level.roundincrease; // Set next exfil round
			level notify ("can_exfil"); // Notify to enable exfil
		} 
		wait 0.5; // Short delay
	} 
} 

// Enable exfil for a limited time when triggered
enableExfil() 
{ 
	while(1) 
	{ 
		level waittill ("can_exfil"); // Wait for exfil to be available
		level endon ("exfil_started"); // If exfil starts, end this instance
		level.canexfil = 1; // Set exfil as available
		 
		foreach ( player in get_players() ) 
	       	player thread showExfilMessage(); // Show exfil message to all players

		wait 120; // Exfil window lasts for 120 seconds
		level.canexfil = 0; // Disable exfil after time runs out

		foreach ( player in get_players() ) 
        	player thread showExfilMessage(); // Show message that exfil window is gone
	} 
} 

// Handle the exfil trigger interaction and voting process
spawnExfil() 
{ 
	exfilTrigger = spawn( "trigger_radius", (level.iconlocation), 1, 50, 50 ); // Create a spherical trigger
	exfilTrigger setHintString(""); // Clear hint string initially
	exfilTrigger setcursorhint( "HINT_NOICON" ); // No cursor hint icon
	if (level.radiomodel != "") 
	{ 
		exfilModel = spawn( "script_model", (level.iconlocation)); // Spawn a model for the exfil
		exfilModel setmodel ("p6_zm_buildable_sq_transceiver"); // Set the model type
		exfilModel rotateTo(level.radioangle,.1); // Rotate the model
	} 
	 
	while(1) 
	{ 
		exfilTrigger waittill( "trigger", i ); // Wait for a player to enter the trigger
		if (level.exfilstarted == 0 && level.canexfil == 1) // Check if exfil hasn't started and is available
		{ 
			if ( i usebuttonpressed() ) // Check if the player pressed the "use" button
			{ 
				 
				if (level.exfilvoting == 0) // If no voting is currently active
				{ 
					level.exfilplayervotes = 0; // Reset votes
					level.exfilvoting = 1; // Start voting
					self.exfilvoted = 1; // The initiating player automatically votes yes
					level.exfilplayervotes += 1; 
					if (level.exfilplayervotes >= level.players.size) // If all players (only one) have voted
					{ 
						level.votingsuccess = 1; // Voting is successful
						level notify ("voting_finished"); // Notify voting finished
					} 

					level thread exfilVoteTimer(); // Start the voting timer
					foreach ( player in get_players() ) 
					{ 
						player thread showvoting(i); // Show voting UI to all players
						player thread checkVotingInput(); // Check for voting input from each player
						player.canrespawn = 0; // Disable respawn during vote
					} 
					 
					if (level.votingsuccess != 1) 
					{ 
						level waittill_any ("voting_finished","voting_expired"); // Wait for voting to finish or expire
					} 

					if (level.votingsuccess == 1) 
						{ 
						level.exfilvoting = 0; // End voting
						earthquake( 0.5, 0.5, self.origin, 800 ); // Create a visual earthquake effect
						foreach ( player in get_players() ) 
						{ 
							player playsound( "evt_nuke_flash" ); // Play a sound effect
						} 
						fadetowhite = newhudelem(); // Create a fade to white HUD element
						fadetowhite.x = 0; 
						fadetowhite.y = 0; 
						fadetowhite.alpha = 0; 
						fadetowhite.horzalign = "fullscreen"; 
						fadetowhite.vertalign = "fullscreen"; 
						fadetowhite.foreground = 1; 
						fadetowhite setshader( "white", 640, 480 ); 
						fadetowhite fadeovertime( 0.2 ); 
						fadetowhite.alpha = 1; // Fade to white
						wait 1; 
					 
						level.exfilstarted = 1; // Set exfil as started
						level thread fixZombieTotal(); // Adjust zombie count for exfil
						level thread change_zombies_speed("sprint"); // Make zombies sprint
						level.zombie_vars[ "zombie_spawn_delay" ] = 0.1; // Increase zombie spawn rate
						playfx( level._effect[ "powerup_on" ], level.exfillocation + (0,0,30) ); // Play visual effects
						playfx( level._effect[ "lght_marker" ], level.exfillocation ); 
						level thread spawnExit(); // Spawn the exfil exit trigger
						level thread spawnMiniBoss(); // Spawn a miniboss
						level thread maintain_exfil_zombie_count(); // Maintain zombie count during exfil
						level notify ("exfil_started"); // Notify that exfil has started
						level thread sendsubtitletext(chooseAnnouncer(), 1, "^5The portal has opened at ^7" + level.escapezone + "", 5); // Announce portal opening
					 
						fadetowhite fadeovertime( 1 ); 
						fadetowhite.alpha = 0; // Fade back from white
						wait 1.1; 
						fadetowhite destroy(); // Destroy fade HUD element
						 
						startCountdown(level.starttimer); // Start the exfil countdown timer
					} 
				} 
			} 
			exfilTrigger setHintString("^5Press ^7&&1 ^5to call an exfil"); // Set hint string for exfil
		} 
		else 
		{ 
			exfilTrigger setHintString(""); // Clear hint string if exfil not available
		} 

		wait 0.5; // Short delay
	} 
} 

// Maintain the zombie count during exfil
maintain_exfil_zombie_count() 
{ 
	level endon ("exfil_end"); // End if exfil ends
	for(;;) 
	{ 
		if(level.zombie_total > 40) 
		{ 
			level.zombie_total = 40; // Cap zombie total at 40
		} 
		wait 0.01; // Very short delay
	} 
} 

// Display the exfil HUD for each player
exfilHUD() 
{ 
//	level endon("end_game"); 
	self endon( "disconnect" ); // End if player disconnects

	exfil_bg = newClientHudElem(self); // Background for the HUD
	exfil_bg.alignx = "left"; 
	exfil_bg.aligny = "middle"; 
	exfil_bg.horzalign = "user_left"; 
	exfil_bg.vertalign = "user_center"; 
	exfil_bg.x -= 0; 
	exfil_bg.y += 0; 
	exfil_bg.fontscale = 2; 
	exfil_bg.alpha = 1; 
	exfil_bg.color = ( 0, 0, 1 ); 
	exfil_bg.hidewheninmenu = 1; 
	exfil_bg.foreground = 1; 
	exfil_bg setShader("scorebar_zom_1", 124, 32); 
	 
	 
	exfil_text = newClientHudElem(self); // Text for the exfil timer
	exfil_text.alignx = "left"; 
	exfil_text.aligny = "middle"; 
	exfil_text.horzalign = "user_left"; 
	exfil_text.vertalign = "user_center"; 
	exfil_text.x += 20; 
	exfil_text.y += 5; 
	exfil_text.fontscale = 1; 
	exfil_text.alpha = 1; 
	exfil_text.color = ( 1, 1, 1 ); 
	exfil_text.hidewheninmenu = 1; 
	exfil_text.foreground = 1; 
	exfil_text.label = &"Exfil Timer: ^2"; 
	 
	exfil_target = newClientHudElem(self); // Text for the exfil target location
	exfil_target.alignx = "left"; 
	exfil_target.aligny = "middle"; 
	exfil_target.horzalign = "user_left"; 
	exfil_target.vertalign = "user_center"; 
	exfil_target.x += 20; 
	exfil_target.y -= 5; 
	exfil_target.fontscale = 1; 
	exfil_target.alpha = 0; 
	exfil_target.color = ( 1, 1, 1 ); 
	exfil_target.hidewheninmenu = 1; 
	exfil_target.foreground = 1; 
	exfil_target settext ("Go to the ^2" + level.escapezone); 
	 
	exfil_kills = newClientHudElem(self); // Text for zombie kills left
	exfil_kills.alignx = "left"; 
	exfil_kills.aligny = "middle"; 
	exfil_kills.horzalign = "user_left"; 
	exfil_kills.vertalign = "user_center"; 
	exfil_kills.x += 20; 
	exfil_kills.y -= 5; 
	exfil_kills.fontscale = 1; 
	exfil_kills.alpha = 0; 
	exfil_kills.color = ( 1, 1, 1 ); 
	exfil_kills.hidewheninmenu = 1; 
	exfil_kills.foreground = 1; 
	exfil_kills.label = &"Zombie Kills Left: ^2"; 
	 
	thread activateTimer(exfil_text); // Activate the timer HUD
	 
	while(1) 
	{ 
		exfil_kills setValue (get_round_enemy_array().size + level.zombie_total); // Update kills left
		if ((level.exfilstarted == 1) && (level.gameisending == 0)) // If exfil started and game not ending
		{ 
			exfil_bg.alpha = 1; // Show HUD elements
			exfil_target.alpha = 0; 
			exfil_text.alpha = 1; 
			exfil_kills.alpha = 1; 
//			exfil_text setValue (level.timer); 
//			exfil_text setTimer(level.timer); 
			exfil_target setValue (level.escapezone); 
			if ( distance( level.exfillocation, self.origin ) <= 300 ) // Change background color if near exfil
			{ 
				exfil_bg.color = ( 0, 1, 0 ); // Green if in range
			} 
			else 
			{ 
				exfil_bg.color = ( 0, 0, 1 ); // Blue if out of range
			} 
			 
			if(get_round_enemy_array().size + level.zombie_total == 0) // If no zombies left
			{ 
				exfil_target.alpha = 1; // Show target message
				exfil_kills.alpha = 0; // Hide kills message
			} 
			 
		} 
		else 
		{ 
			exfil_bg.alpha = 0; // Hide HUD elements if exfil not active
			exfil_target.alpha = 0; 
			exfil_text.alpha = 0; 
			exfil_kills.alpha = 0; 
		} 
		 
		wait 0.5; // Short delay
	} 
} 

// Activate the timer on the HUD
activateTimer(hud) 
{ 
	level waittill("exfil_started"); // Wait for exfil to start
	hud setTimer(120); // Set HUD timer to 120 seconds
} 

// Get timer text (unused function)
getTimerText(seconds) 
{ 
	 
	text = (seconds); 
	return text; 
} 

// Start the exfil countdown
startCountdown(numtoset) 
{ 
	level endon("game_ended"); // End if game ends
	level endon("end_game"); // End if game ends (redundant?)
	level.timer = numtoset; // Set initial timer value
	while(level.timer > 0) 
	{ 
		level.timer -= 1; // Decrement timer
		wait 1; // Wait 1 second
	} 
	level notify ("exfil_end"); // Notify that exfil time has ended
} 

// Set exfil locations based on the current map and gametype
setExfillocation() 
{ 
	if ( getDvar( "g_gametype" ) == "zgrief" || getDvar( "g_gametype" ) == "zstandard" ) 
	{ 
		if(getDvar("mapname") == "zm_prison") //mob of the dead grief 
		{ 
			level.iconlocation = (-769,8671,1374); 
			level.escapezone = ("Roof"); 
			level.radiomodel = (""); 
			level.radioangle = (0,90,0); 
			level.exfillocation = (2496,9433,1704); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_buried") //buried grief 
		{ 
			level.iconlocation = (0,0,0); 
			level.escapezone = ("Roof"); 
			level.radiomodel = (""); 
			level.radioangle = (0,0,0); 
			level.exfillocation = (0,0,0); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_nuked") //nuketown 
		{ 
			level.iconlocation = (-1349,994,-63); 
			level.escapezone = ("Bunker"); 
			level.radiomodel = (""); 
			level.radioangle = (0,0,0); 
			level.exfillocation = (-581,375,80); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_transit") //transit grief and survival 
		{ 
			if(getDvar("ui_zm_mapstartlocation") == "town") //town 
			{ 
				level.iconlocation = (1936,646,-55); 
				level.escapezone = ("Barber"); 
				level.radiomodel = (""); 
				level.radioangle = (0,0,0); 
				level.exfillocation = (744,-1456,128); 
				level.starttimer = 120; 
				level.requirezombiekills = 1; 
			} 
			else if (getDvar("ui_zm_mapstartlocation") == "transit") //busdepot 
			{ 
				level.iconlocation = (-6483,5297,-55); 
				level.escapezone = ("Exfil Point"); 
				level.radiomodel = (""); 
				level.radioangle = (0,126,0); 
				level.exfillocation = (-7388,4239,-63); 
				level.starttimer = 120; 
				level.requirezombiekills = 1; 
			} 
			else if (getDvar("ui_zm_mapstartlocation") == "farm") //farm 
			{ 
				level.iconlocation = (7995,-6627,117); 
				level.escapezone = ("Barn"); 
				level.radiomodel = (""); 
				level.radioangle = (0,0,0); 
				level.exfillocation = (8111,-4787,48); 
				level.starttimer = 120; 
				level.requirezombiekills = 1; 
			} 
		} 
	} 
	else // Default zombie game modes
	{ 
		if(getDvar("mapname") == "zm_prison") //mob of the dead 
		{ 
			level.iconlocation = (-1006,8804,1336); 
			level.escapezone = ("Roof"); 
			level.radiomodel = (""); 
			level.radioangle = (0,90,0); 
			level.exfillocation = (2496,9433,1704); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_buried") //buried 
		{ 
			level.iconlocation = (1005,-1572,50); 
			level.escapezone = ("Tunnel"); 
			level.radiomodel = (""); 
			level.radioangle = (0,0,0); 
			level.exfillocation = (-131,250,358); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_transit") //transit 
		{ 
			level.iconlocation = (-6201,4108,-7); 
			level.escapezone = ("Diner"); 
			level.radiomodel = ("p6_zm_buildable_sq_transceiver"); 
			level.radioangle = (0,126,0); 
			level.exfillocation = (-4415,-7063,-65); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
			 
		} 
		else if(getDvar("mapname") == "zm_tomb") //origins 
		{ 
			level.iconlocation = (2899,5083,-375); 
			level.escapezone = ("No Mans Land"); 
			level.radiomodel = (""); 
			level.radioangle = (0,90,0); 
			level.exfillocation = (137,-299,320); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
		else if(getDvar("mapname") == "zm_highrise") 
		{ 
			level.iconlocation = (1472,1142,3401); 
			level.escapezone = ("Roof"); 
			level.radiomodel = (""); 
			level.radioangle = (0,0,0); 
			level.exfillocation = (2036,305,2880); 
			level.starttimer = 120; 
			level.requirezombiekills = 0; 
		} 
	} 
} 

// Spawn the exfil exit trigger and handle escape conditions
spawnExit() 
{ 
	exfilExit = spawn( "trigger_radius", (level.exfillocation), 10, 200, 200 ); // Create trigger at exfil location
	exfilExit setHintString("^5Kill all the Zombies^7..."); // Initial hint
	exfilExit setcursorhint( "HINT_NOICON" ); 
	 
	foreach (player in get_players()) 
	{ 
		player show_big_message("^5Kill all the Zombies to open the portal^7...", ""); // Message to players
	} 
	 
	waitTillNoZombies(); // Wait until all zombies are dead
	 
	foreach (player in get_players()) 
	{ 
		player show_big_message("^5All Enemies Eliminated^7... ^5You can now Escape^7...", ""); // Message when clear
	} 
	 
	exfilExit setHintString("^5Press ^7&&1 ^5escape"); // Update hint
	 
	while(1) 
	{ 
		exfilExit waittill( "trigger", i ); // Wait for player to enter trigger
		if ( i usebuttonpressed()) // Check for use button press
		{ 
			i enableinvulnerability(); // Make player invulnerable during escape animation
			level.successfulexfil = 1; // Mark exfil as successful
			escapetransition = newClientHudElem(i); // Create fade to black HUD element
			escapetransition.x = 0; 
			escapetransition.y = 0; 
			escapetransition.alpha = 0; 
			escapetransition.horzalign = "fullscreen"; 
			escapetransition.vertalign = "fullscreen"; 
			escapetransition.foreground = 0; 
			escapetransition setshader( "white", 640, 480 ); 
			escapetransition.color = (0,0,0); 
			escapetransition fadeovertime( 0.5 ); 
			escapetransition.alpha = 1; // Fade to black
			wait 0.5; 
			 
			escapetransition.foreground = 0; 
			escapetransition fadeovertime( 0.2 ); 
			escapetransition.alpha = 0; // Fade back
			i disableinvulnerability(); 
			if (level.players.size == 1) // If only one player left
			{ 
				level thread sendsubtitletext(chooseAnnouncer(), 1, "^5Everyone has successfully escaped^7...", 5); // Announce success
				level notify( "end_game" ); // End the game
			} 
			else 
			{ 
				escapetransition.alpha = 0; 
				i thread maps\mp\gametypes_zm\_spectating::setspectatepermissions(); // Set player to spectator
     			i.sessionstate = "spectator"; 
				escapetransition destroy(); 
				if (checkAmountPlayers()) // Check if all players have escaped
				{ 
					level thread sendsubtitletext(chooseAnnouncer(), 1, "^5Everyone has successfully escaped^7...", 5); 
					level notify( "end_game" ); 
				} 
				else 
				{ 
					level thread sendsubtitletext(chooseAnnouncer(), 1, i + " ^5has escaped^7...", 2); // Announce individual escape
				} 
				 
			} 
			level waittill ("end_game"); // Wait for game to end
			exfilExit setHintString(""); // Clear hint string
		} 
	 
	} 
} 

// Wait until there are no zombies left
waitTillNoZombies() 
{ 
	while(get_round_enemy_array().size + level.zombie_total > 0) 
	{ 
		wait 0.1; // Short delay
	} 
} 

// Handle player death if they are outside the exfil zone when time runs out
downOnExfil() 
{ 
	level waittill ("exfil_end"); // Wait for exfil timer to end
	if ( distance( level.exfillocation, self.origin ) > 300 ) // If player is outside exfil zone
	{ 
		 
		deathtransition = newClientHudElem(self); // Create red fade out HUD element
		deathtransition.x = 0; 
		deathtransition.y = 0; 
		deathtransition.alpha = 0; 
		deathtransition.horzalign = "fullscreen"; 
		deathtransition.vertalign = "fullscreen"; 
		deathtransition.foreground = 1; 
		deathtransition setshader( "white", 640, 480 ); 
		deathtransition.color = (1,0,0); 
		deathtransition fadeovertime( 0.2 ); 
		deathtransition.alpha = 1; // Fade to red
		wait 1; 
		self unsetperk("specialty_quickrevive"); // Remove Quick Revive perk
		self.lives = 0; // Set lives to 0
		self thread show_big_message("^5You were consumed by the Aether^7...",""); // Show death message
		self dodamage(self.health, self.origin); // Kill the player
		deathtransition fadeovertime( 1 ); 
		deathtransition.alpha = 0; // Fade back
		wait 1.1; 
		 
		deathtransition.foreground = 0; 
		level notify( "end_game" ); // End the game
	} 
	else // If player is inside exfil zone
	{ 
		self thread forcePlayersToExfil(); // Force player to exfil
	} 
} 

// Show scoreboard text at the end of the game
showscoreboardtext() 
{ 
	level waittill("end_game"); // Wait for game to end
	level.gameisending = 1; // Set game ending flag
	wait 8; 
	 
	scoreboardText = newclienthudelem( self ); // Create scoreboard text HUD element
    scoreboardText.alignx = "center"; 
    scoreboardText.aligny = "middle"; 
    scoreboardText.horzalign = "center"; 
    scoreboardText.vertalign = "middle"; 
    scoreboardText.y -= 100; 

    if ( self issplitscreen() ) 
        scoreboardText.y += 70; 

    scoreboardText.foreground = 1; 
    scoreboardText.fontscale = 8; 
    scoreboardText.alpha = 0; 
    scoreboardText.color = ( 0, 1, 0 ); 
    scoreboardText.hidewheninmenu = 1; 
    scoreboardText.font = "default"; 

	if ((level.successfulexfil == 1) && (level.exfilstarted == 1)) // If exfil successful
	{ 
		scoreboardText.color = ( 0, 1, 0 ); // Green text
		scoreboardText settext( "^2Exfil Successful" ); 
	} 
	else if ((level.successfulexfil == 0) && (level.exfilstarted == 1)) // If exfil failed
	{ 
		scoreboardText.color = ( 1, 0, 0 ); // Red text
		scoreboardText settext( "^1Exfil Failed" ); 
	} 

    scoreboardText changefontscaleovertime( 0.25 ); 
    scoreboardText fadeovertime( 0.25 ); 
    scoreboardText.alpha = 1; 
    scoreboardText.fontscale = 4; // Animate text appearance
} 

// Adjust zombie total during exfil (hardcoded to 40)
fixZombieTotal() 
{ 
	level.zombie_total = 40; 
//	while(1) 
//		{ 
//			if (level.exfilstarted == 1) 
//			{ 
//				level.zombie_total = 20; 
//			} 
//			wait(1); 
//		} 
} 

// Show a temporary message to players about exfil availability
showExfilMessage() 
{	 
	belowMSG = newclienthudelem( self ); // Create HUD element for message
    belowMSG.alignx = "center"; 
    belowMSG.aligny = "bottom"; 
    belowMSG.horzalign = "center"; 
    belowMSG.vertalign = "bottom"; 
    belowMSG.y -= 10; 
     
    belowMSG.foreground = 1; 
    belowMSG.fontscale = 4; 
    belowMSG.alpha = 0; 
    belowMSG.hidewheninmenu = 1; 
    belowMSG.font = "default"; 

	if (level.canexfil == 0) 
	{ 
		belowMSG settext( "^1Exfil window gone!" ); 
		belowMSG.color = ( 1, 0, 0 ); // Red for unavailable
	} 
	else if (level.canexfil == 1) 
	{ 
		belowMSG settext( "^2Exfil is available!" ); 
		belowMSG.color = ( 0, 1, 0 ); // Green for available
	} 

    belowMSG changefontscaleovertime( 0.25 ); 
    belowMSG fadeovertime( 0.25 ); 
    belowMSG.alpha = 1; 
    belowMSG.fontscale = 2; // Animate message appearance
     
    wait 8; // Display for 8 seconds
     
    belowMSG changefontscaleovertime( 0.25 ); 
    belowMSG fadeovertime( 0.25 ); 
    belowMSG.alpha = 0; 
    belowMSG.fontscale = 4; 
    wait 1.1; 
    belowMSG destroy(); // Destroy message HUD element
} 

// Check the number of players who have escaped
checkAmountPlayers() 
{ 
	if (level.players.size == 1) // If only one player in game, always return true
	{ 
		return true; 
	} 
	else 
	{ 
		count = 0; 
		foreach ( player in level.players ) 
		{ 
		if( distance( level.iconlocation, player.origin ) <= 10 ) // Check if player is near icon location (might be wrong, should be exfil location)
		    { 
	   			count += 1; 
	   		} 
		} 
		if (level.players.size <= count) // If all players are near icon
		{ 
			return true; 
		} 
		else 
		{ 
			return false; 
		} 
	} 
} 

// Force players to exfil (used if they were in range when time ran out)
forcePlayersToExfil() 
{ 
	self enableinvulnerability(); 
	level.successfulexfil = 1; 
	escapetransition = newClientHudElem(self); 
	escapetransition.x = 0; 
	escapetransition.y = 0; 
	escapetransition.alpha = 0; 
	escapetransition.horzalign = "fullscreen"; 
	escapetransition.vertalign = "fullscreen"; 
	escapetransition.foreground = 1; 
	escapetransition setshader( "white", 640, 480 ); 
	escapetransition.color = (0,0,0); 
	escapetransition fadeovertime( 0.5 ); 
	escapetransition.alpha = 1; 
	wait 3; 
			 
	escapetransition.foreground = 0; 
	self disableinvulnerability(); 
	if (level.players.size == 1) 
	{ 
		level notify( "end_game" ); 
	} 
	else 
	{ 
		escapetransition.alpha = 0; 
		self thread maps\mp\gametypes_zm\_spectating::setspectatepermissions(); 
     	self.sessionstate = "spectator"; 
		escapetransition destroy(); 
		if (checkAmountPlayers()) 
		{ 
			level notify( "end_game" ); 
		} 
				 
	} 
} 

// Show the exfil voting UI to players
showVoting(execPlayer) 
{ 
	self endon( "disconnect" ); // End if player disconnects
	 
	level.exfilvoteexec = execPlayer; // Store the player who initiated the vote
	 
	hudy = -100; // Vertical offset for the HUD elements
	 
	voting_bg = newClientHudElem(self); // Background for voting UI
	voting_bg.alignx = "left"; 
	voting_bg.aligny = "middle"; 
	voting_bg.horzalign = "user_left"; 
	voting_bg.vertalign = "user_center"; 
	voting_bg.x -= 0; 
	voting_bg.y = hudy; 
	voting_bg.fontscale = 2; 
	voting_bg.alpha = 1; 
	voting_bg.color = ( 1, 1, 1 ); 
	voting_bg.hidewheninmenu = 1; 
	voting_bg.foreground = 1; 
	voting_bg setShader("scorebar_zom_1", 124, 32); 
	 
	 
	voting_text = newClientHudElem(self); // Text for voting timer
	voting_text.alignx = "left"; 
	voting_text.aligny = "middle"; 
	voting_text.horzalign = "user_left"; 
	voting_text.vertalign = "user_center"; 
	voting_text.x += 20; 
	voting_text.y = hudy + 5; 
	voting_text.fontscale = 1; 
	voting_text.alpha = 1; 
	voting_text.color = ( 1, 1, 1 ); 
	voting_text.hidewheninmenu = 1; 
	voting_text.foreground = 1; 
	voting_text.label = &"Timer: "; 
	 
	voting_target = newClientHudElem(self); // Text indicating who wants to exfil and how to vote
	voting_target.alignx = "left"; 
	voting_target.aligny = "middle"; 
	voting_target.horzalign = "user_left"; 
	voting_target.vertalign = "user_center"; 
	voting_target.x += 20; 
	voting_target.y = hudy - 5; 
	voting_target.fontscale = 1; 
	voting_target.alpha = 1; 
	voting_target.color = ( 1, 1, 1 ); 
	voting_target.hidewheninmenu = 1; 
	voting_target.foreground = 1; 
//	voting_target setText ("Press [{+actionslot 4}] to agree on Exfil"); 
	voting_target setText (execPlayer.name + " wants to Exfil - [{+actionslot 4}] to accept"); 
//[{+actionslot 4}] 
	 
	voting_votes = newClientHudElem(self); // Text for votes left
	voting_votes.alignx = "left"; 
	voting_votes.aligny = "middle"; 
	voting_votes.horzalign = "user_left"; 
	voting_votes.vertalign = "user_center"; 
	voting_votes.x += 20; 
	voting_votes.y = hudy + 15; 
	voting_votes.fontscale = 1; 
	voting_votes.alpha = 1; 
	voting_votes.color = ( 1, 1, 1 ); 
	voting_votes.hidewheninmenu = 1; 
	voting_votes.foreground = 1; 
	voting_votes.label = &"Votes left: "; 
	 
	while(1) 
	{ 
		voting_text setValue (level.votingtimer); // Update timer value
		votesLeft = level.players.size - level.exfilplayervotes; // Calculate votes remaining
		voting_votes setValue (votesLeft); // Update votes remaining
		if (self.exfilvoted == 0) 
		{ 
			voting_bg.color = ( 0, 0, 1 ); // Blue if not voted
		} 
		else if (self.exfilvoted == 1) 
		{ 
			voting_bg.color = ( 0, 1, 0 ); // Green if voted
		} 
		 
		if (level.exfilvoting == 0) // If voting ends, destroy HUD elements
		{ 
			voting_target destroy(); 
			voting_bg destroy(); 
			voting_text destroy(); 
			voting_votes destroy(); 
		} 
		wait 0.1; // Short delay
	} 
} 

// Check player input for voting
checkVotingInput() 
{ 
	level endon ("voting_finished"); // End if voting finishes
	level endon ("voting_expired"); // End if voting expires
	while(level.exfilvoting == 1 && self.exfilvoted == 0) // While voting is active and player hasn't voted
	{ 
		if(self actionslotfourbuttonpressed() || (isDefined(self.bot))) // Check if action slot 4 button pressed or if it's a bot
		{ 
			level.exfilplayervotes += 1; // Increment votes
			self.exfilvoted = 1; // Mark player as voted
			if (level.exfilplayervotes >= level.players.size) // If all players have voted
			{ 
				level.votingsuccess = 1; // Voting successful
				level notify ("voting_finished"); // Notify voting finished
			} 
		} 
		wait 0.1; // Short delay
	} 
} 

// Check if all players have voted (redundant, handled in checkVotingInput)
checkIfPlayersVoted() 
{ 
	level endon ("voting_finished"); 
	level endon ("voting_expired"); 
	while(1) 
	{ 
		if (level.exfilplayervotes >= level.players.size) 
		{ 
			level.votingsuccess = 1; 
			level notify ("voting_finished"); 
		} 
	} 
	wait 0.1; 
} 

// Manage the exfil voting timer
exfilVoteTimer() 
{ 
	level endon ("voting_finished"); // End if voting finishes
	level endon ("voting_expired"); // End if voting expires (redundant?)
	level.votingtimer = 15; // Set timer to 15 seconds
	while(1) 
	{ 
		level.votingtimer -= 1; // Decrement timer
		if (level.votingtimer < 0) // If timer runs out
		{ 
			level.exfilplayervotes = 0; // Reset votes
			foreach (player in getPlayers()) 
				player.exfilvoted = 0; // Reset player voted status
			level.exfilvoting = 0; // End voting
			level.votingsuccess = 0; // Voting not successful
			level notify ("voting_expired"); // Notify voting expired
		} 
		wait 1; // Wait 1 second
	} 
} 

// Get the requirement for players to escape (current number of players)
getRequirement() 
{ 
	return level.players.size; 
} 

// Spawn minibosses based on the map
spawnMiniBoss() 
{ 
	if(getDvar("mapname") == "zm_prison") 
	{ 
		level notify( "spawn_brutus", 4 ); // Spawn Brutus on Mob of the Dead
	} 
	else if(getDvar("mapname") == "zm_tomb") 
	{ 
		level.mechz_left_to_spawn++; 
		level notify( "spawn_mechz" ); // Spawn Mechz on Origins
	} 
} 

// Change zombie speed (unused as "ragestarted" is not defined, likely external)
change_zombies_speed(speedtoset){ 
	level endon("end_game"); 
	sprint = speedtoset; 
	can_sprint = false; 
 	while(true){ 
 		if (level.ragestarted == 1) // This variable is not defined in this script
 		{ 
 			can_sprint = false; 
    		zombies = getAiArray(level.zombie_team); 
    		foreach(zombie in zombies) 
    		if(!isDefined(zombie.cloned_distance)) 
    			zombie.cloned_distance = zombie.origin; 
    		else if(distance(zombie.cloned_distance, zombie.origin) > 15){ 
    			can_sprint = true; 
    			zombie.cloned_distance = zombie.origin; 
    			if(zombie.zombie_move_speed == "run" || zombie.zombie_move_speed != sprint) 
    				zombie maps\mp\zombies\_zm_utility::set_zombie_run_cycle(sprint); 
    		}else if(distance(zombie.cloned_distance, zombie.origin) <= 15){ 
    			can_sprint = false; 
    			zombie.cloned_distance = zombie.origin; 
    			zombie maps\mp\zombies\_zm_utility::set_zombie_run_cycle("run"); 
    		} 
    	} 
    	wait 0.25; 
    } 
} 

// Choose the announcer character based on the map
chooseAnnouncer() 
{ 
	if (getDvar("mapname") == "zm_transit") 
		return "Richtofen"; 
	else if (getDvar("mapname") == "zm_nuked") 
		return "Richtofen"; 
	else if (getDvar("mapname") == "zm_tomb") 
		return "Samantha Maxis"; 
	else if (getDvar("mapname") == "zm_prison") 
		return "Afterlife Spirit"; 
	else if (getDvar("mapname") == "zm_buried") 
		return "Richtofen"; 
	else if (getDvar("mapname") == "zm_highrise") 
		return "Richtofen"; 
} 

// Display custom subtitle text
sendsubtitletext(charactername, team, text, time) 
{ 
	if(getDvarInt("enable_custom_subtitles") == 1) // Check if custom subtitles are enabled
	{	 
		if(isDefined(self.subtitleText)) 
		{ 
			self waittill ("subtitle_done"); // Wait for previous subtitle to finish
			self.subtitleText destroy(); 
		} 
	 
	 
		if (team == 1) 
		{ 
			teamcolor = "^4"; // Green color
		} 
		else if (team == 2) 
		{ 
			teamcolor = "^1"; // Red color
		} 
		else 
		{ 
			teamcolor = "^3"; // Yellow color
		} 
	 
	 
		self.subtitleText = newclienthudelem( self ); // Create subtitle HUD element
    	self.subtitleText.alignx = "center"; 
    	self.subtitleText.aligny = "bottom"; 
    	self.subtitleText.horzalign = "center"; 
    	self.subtitleText.vertalign = "bottom"; 
    	self.subtitleText.fontscale = 1.5; 
    	self.subtitleText.y = 0; 
     
    	self.subtitleText.foreground = 1; 
    	self.subtitleText.alpha = 0; 
    	self.subtitleText.hidewheninmenu = 1; 
    	self.subtitleText.font = "default"; 

		self.subtitleText settext( teamcolor + charactername + "^7: " + text ); // Set subtitle text
		self.subtitleText.color = ( 1, 1, 1 ); // White text color

    	self.subtitleText moveovertime( 0.25 ); 
    	self.subtitleText fadeovertime( 0.25 ); 
    	self.subtitleText.alpha = 1; 
    	self.subtitleText.y = -10; // Animate appearance
     
    	wait time; // Display for specified time
     
    	self.subtitleText moveovertime( 0.25 ); 
    	self.subtitleText fadeovertime( 0.25 ); 
    	self.subtitleText.alpha = 0; 
    	self.subtitleText.y = -20; // Animate disappearance
    	wait 1.1; 
    	self.subtitleText destroy(); 
    	self notify ("subtitle_done"); // Notify that subtitle is done
    } 
} 

// Show a big message to all players
show_big_message(setmsg, sound) 
{ 
    msg = setmsg; 
    players = get_players(); 

    if ( isdefined( level.hostmigrationtimer ) ) 
    { 
        while ( isdefined( level.hostmigrationtimer ) ) 
            wait 0.05; 

        wait 4; 
    } 

    foreach ( player in players ) 
        player thread show_big_hud_msg( msg ); // Show big HUD message to each player
        player playsound(sound); // Play sound (sound variable not always passed)

} 

// Show a big HUD message to a single player
show_big_hud_msg( msg, msg_parm, offset, cleanup_end_game ) 
{ 
    self endon( "disconnect" ); // End if player disconnects

    while ( isdefined( level.hostmigrationtimer ) ) 
        wait 0.05; 

    large_hudmsg = newclienthudelem( self ); // Create large HUD message element
    large_hudmsg.alignx = "center"; 
    large_hudmsg.aligny = "middle"; 
    large_hudmsg.horzalign = "center"; 
    large_hudmsg.vertalign = "middle"; 
    large_hudmsg.y -= 130; 

    if ( self issplitscreen() ) 
        large_hudmsg.y += 70; 

    if ( isdefined( offset ) ) 
        large_hudmsg.y += offset; 

    large_hudmsg.foreground = 1; 
    large_hudmsg.fontscale = 5; 
    large_hudmsg.alpha = 0; 
    large_hudmsg.color = ( 1, 1, 1 ); 
    large_hudmsg.hidewheninmenu = 1; 
    large_hudmsg.font = "default"; 

    if ( isdefined( cleanup_end_game ) && cleanup_end_game ) 
    { 
        level endon( "end_game" ); 
        large_hudmsg thread show_big_hud_msg_cleanup(); 
    } 

    if ( isdefined( msg_parm ) ) 
        large_hudmsg settext( msg, msg_parm ); 
    else 
        large_hudmsg settext( msg ); 

    large_hudmsg changefontscaleovertime( 0.25 ); 
    large_hudmsg fadeovertime( 0.25 ); 
    large_hudmsg.alpha = 1; 
    large_hudmsg.fontscale = 2; 
    wait 3.25; 
    large_hudmsg changefontscaleovertime( 1 ); 
    large_hudmsg fadeovertime( 1 ); 
    large_hudmsg.alpha = 0; 
    large_hudmsg.fontscale = 5; 
    wait 1; 
    large_hudmsg notify( "death" ); 

    if ( isdefined( large_hudmsg ) ) 
        large_hudmsg destroy(); 
} 

// Cleanup for big HUD message
show_big_hud_msg_cleanup() 
{ 
    self endon( "death" ); // End if "death" notification received

    level waittill( "end_game" ); // Wait for game to end

    if ( isdefined( self ) ) 
        self destroy(); // Destroy HUD element
} 

// Custom round wait function for exfil
round_wait_exfil() 
{ 
    level endon( "restart_round" ); 
/# 
    if ( getdvarint( #"zombie_rise_test" ) ) 
        level waittill( "forever" ); 
 #/ 
/# 
    if ( getdvarint( #"zombie_cheat" ) == 2 || getdvarint( #"zombie_cheat" ) >= 4 ) 
        level waittill( "forever" ); 
 #/ 
    wait 1; 

    if ( flag( "dog_round" ) ) 
    { 
        wait 7; 

        while ( level.dog_intermission ) 
            wait 0.5; 

        increment_dog_round_stat( "finished" ); 
    } 
    else 
    { 
        while ( true ) 
        { 
            should_wait = 0; 

			if (level.exfilstarted == 0) // Only wait if exfil has not started
			{ 
				if ( isdefined( level.is_ghost_round_started ) && [[ level.is_ghost_round_started ]]() ) 
					should_wait = 1; 
				else 
					should_wait = get_current_zombie_count() > 0 || level.zombie_total > 0 || level.intermission; 

				if ( !should_wait ) 
					return; 

				if ( flag( "end_round_wait" ) ) 
					return; 
			} 

            wait 1.0; 
        } 
    } 
} 
