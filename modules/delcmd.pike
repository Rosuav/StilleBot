inherit command;
constant require_moderator = 1;
constant docstring = #"
Remove an echo command for this channel

Usage: `!delcmd !commandname`

Remove a command created with [!addcmd](addcmd).
";

string process(object channel, object person, string param)
{
	if (sscanf(param, "%*[!]%[^# ]", string cmd) == 2)
	{
		//As with addcmd, it *always* gets the channel name appended.
		cmd += channel->name;
		if (!G->G->echocommands[cmd]) return "@$$: No echo command with that name exists here.";
		m_delete(G->G->echocommands, cmd);
		string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
		Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
		return sprintf("@$$: Deleted command !%s", cmd - channel->name);
	}
	return "@$$: Try !delcmd !cmdname";
}
