inherit command;
constant require_moderator = 1;
constant docstring = #"
Add a counter command for this channel

Usage: `!addcounter !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Counter commands themselves are currently available to everyone in the
channel (TODO: support mod-only counters), and will increment the counter and
display the text they have been given. The marker `%d` will be replaced with
the total number of times the command has been run, and `%s` will be replaced
with any words given after the command (not usually needed). Similarly, `$$`
is replaced with the username of the person who triggered the command.

TODO: Support counter-viewing commands that don't increment. Would go well with
mod-only counters - anyone can view, only a mod can add one.
";

string process(object channel, object person, string param)
{
	if (sscanf(param, "!%[^# ] %s", string cmd, string response) == 2)
	{
		//Largely parallels !addcmd handling
		cmd = lower_case(cmd);
		if (has_value(cmd, '!')) return "@$$: Command names cannot include exclamation marks";
		string newornot = G->G->echocommands[cmd + channel->name] ? "Updated" : "Created new";
		make_echocommand(cmd + channel->name, (["message": response, "counter": cmd, "action": "+1"]));
		return sprintf("@$$: %s counter !%s", newornot, cmd);
	}
	return "@$$: Try !addcounter !newcmdname response-message";
}
