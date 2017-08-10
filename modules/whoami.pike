inherit command;
constant hidden_command = 1;

string process(object channel, object person, string param)
{
	return sprintf("@$$: You are %O, and you are %sa mod.",
		person->user, channel->mods[person->user] ? "" : "not ",
	);
}
