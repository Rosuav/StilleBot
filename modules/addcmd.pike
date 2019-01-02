inherit command;
constant require_moderator = 1;
constant docstring = #"
Add an echo command for this channel

Usage: `!addcmd !newcommandname text-to-echo`

If the command already exists as an echo command, it will be updated. If it
exists as a global command, the channel-specific echo command will shadow it
(meaning that the global command cannot be accessed in this channel). Please
do not shoot yourself in the foot :)

Echo commands themselves are available to everyone in the channel, and simply
display the text they have been given. The marker `%s` will be replaced with
whatever additional words are given with the command, if any.
";

string process(object channel, object person, string param)
{
	if (sscanf(param, "!%s %s", string cmd, string response) == 2)
	{
		//Create a new command. Note that it *always* gets the channel name appended,
		//making it a channel-specific command; global commands can only be created by
		//manually editing the JSON file.
		cmd += channel->name;
		string newornot = G->G->echocommands[cmd] ? "Updated" : "Created new";
		G->G->echocommands[cmd] = response;
		string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
		Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
		return sprintf("@$$: %s command !%s", newornot, cmd - channel->name);
	}
	return "@$$: Try !addcmd !newcmdname response-message";
}

void create(string name)
{
	::create(name);
	G->G->echocommands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}");
}
