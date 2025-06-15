init()
{
	level.player_too_many_players_check = false;

	if ( isDedicated() )
	{
		level thread upload_stats_on_round_end();
		level thread upload_stats_on_game_end();
		level thread upload_stats_on_player_connect();
	}
}

upload_stats_on_round_end()
{
	level endon( "end_game" );

	for ( ;; )
	{
		level waittill( "end_of_round" );

		uploadstats();
	}
}

upload_stats_on_game_end()
{
	level waittill( "end_game" );

	uploadstats();
}

upload_stats_on_player_connect()
{
	level endon( "end_game" );

	for ( ;; )
	{
		level waittill( "connected" );

		level thread delay_uploadstats( 1 );
	}
}

delay_uploadstats( delay )
{
	level notify( "delay_uploadstats" );
	level endon( "delay_uploadstats" );

	level endon( "end_game" );

	wait delay;
	uploadstats();
}
