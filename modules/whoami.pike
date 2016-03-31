inherit command;

void process(object channel, object person, string param)
{
	send_message(channel->name, sprintf("@%s: You are %O, and you are %sa mod, and this is %san all-cmds channel.",
		person->nick, person->user,
		channel->mods[person->user] ? "" : "not ",
		channel->config->allcmds ? "" : "not ",
	));
}
