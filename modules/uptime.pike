inherit command;
constant require_allcmds = 1;

string channel_uptime(string channel)
{
	if (object started = G->G->stream_online_since[channel])
	{
		return describe_time(started->distance(Calendar.now())->how_many(Calendar.Second()));
	}
}

void process(object channel, object person, string param)
{
	if (string msg = channel_uptime(channel->name[1..]))
		send_message(channel->name, sprintf("@%s: Channel has been online for %s",
			person->nick, msg));
	else
		send_message(channel->name, "Channel is currently offline.");
}

