inherit command;
constant require_allcmds = 1;
constant docstring = #"
VLC integration

Usage: `!song`

Show the currently-playing song, if StilleBot VLC integration is active.

Mod usage: `!song report` / `!song unreport`

Enable or disable automatic reporting of songs as they start playing
";

echoable_message process(object channel, object person, string param)
{
	mapping status = G->G->vlc_status[channel->name]; //May be UNDEFINED
	if (person->badges->_mod) {
		//TODO: !song skip, maybe !song notes
	}
	if (status->?playing) return "Current song: " + status->current; //Yes, it might say "Current song: 0" if not set up right
	//Otherwise just be silent.
}
