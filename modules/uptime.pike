inherit command;
constant require_allcmds = 1;

void process(object channel, object person, string param)
{
	if (string msg = channel_uptime(channel->name[1..]))
		send_message(channel->name, sprintf("@%s: Channel has been online for %s",
			person->nick, msg));
	else
		send_message(channel->name, "Channel is currently offline.");
}

