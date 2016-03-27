inherit command;

mapping(string:string) commands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}"); //BROKEN

int process(object channel, object person, string param)
{
	if (sscanf(param, "!%s %s", string cmd, string response) == 2)
	{
		//Create a new command
		string newornot = commands["!"+cmd] ? "Updated" : "Created new";
		commands["!"+cmd] = response;
		Stdio.write_file("twitchbot_commands.json", string_to_utf8(Standards.JSON.encode(commands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL)));
		send_message(channel->name, sprintf("@%s: %s command !%s", person->nick, newornot, cmd));
	}
}
