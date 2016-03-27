inherit command;

int process(object channel, object person, string param)
{
	if (sscanf(param, "!%s %s", string cmd, string response) == 2)
	{
		//Create a new command
		string newornot = G->G->echocommands["!"+cmd] ? "Updated" : "Created new";
		G->G->echocommands["!"+cmd] = response;
		string json = Standards.JSON.encode(G->G->echocommands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
		Stdio.write_file("twitchbot_commands.json", string_to_utf8(json));
		send_message(channel->name, sprintf("@%s: %s command !%s", person->nick, newornot, cmd));
	}
}

void create(string name)
{
	::create(name);
	G->G->echocommands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}");
}
