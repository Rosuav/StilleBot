inherit command;
constant featurename = "commands";
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
		cmd = command_casefold(cmd) + channel->name;
		if (!G->G->echocommands[cmd]) return "@$$: No echo command with that name exists here.";
		make_echocommand(cmd, 0);
		return sprintf("@$$: Deleted command !%s", cmd - channel->name);
	}
	return "@$$: Try !delcmd !cmdname";
}
