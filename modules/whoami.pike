inherit command;
constant featurename = "debug";
constant hidden_command = 1;

string process(object channel, object person, string param)
{
	return sprintf("@$$: You are %O, and you are %sa mod.",
		person->user, G->G->user_mod_status[person->user + channel->name] ? "" : "not ",
	);
}
