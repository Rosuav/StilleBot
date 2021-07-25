inherit command;
constant featurename = "commands";
constant require_moderator = 1;
constant hidden_command = 1;

string process(object channel, object person, string param)
{
	return "@$$: The counter system has been merged into variable handling. "
		"See the bot's web interface for more details. If your bot does not "
		"have a web interface, browse the source code and create a command in "
		"the JSON file.";
}
