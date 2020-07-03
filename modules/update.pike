//Update a single file, in case of problems. Shouldn't normally be needed.
inherit command;
constant hidden_command = 1;
constant require_moderator = 1;
constant active_channels = ({"rosuav"});

string process(object channel, object person, string param)
{
	float t = time(1587947335);
	if (G->bootstrap(param)) return sprintf("Success. Took %.2f seconds.", time(1587947335) - t);
	else return "Failed, check the console.";
}
