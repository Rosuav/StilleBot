inherit command;

string process(object channel, object person, string param)
{
	return sprintf("@$$: You are %O, and you are %sa mod, and this is %san all-cmds channel.",
		person->user, channel->mods[person->user] ? "" : "not ", channel->config->allcmds ? "" : "not ",
	);
}
