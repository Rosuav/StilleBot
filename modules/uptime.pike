inherit command;
constant require_allcmds = 1;

string channel_uptime(string channel)
{
	if (object started = G->G->stream_online_since[channel])
	{
		int onlinetime = started->distance(Calendar.now())->how_many(Calendar.Second());
		string msg = "";
		if (int t = onlinetime/86400) {msg += sprintf(", %d days", t); onlinetime %= 86400;}
		if (int t = onlinetime/3600) {msg += sprintf(", %d hours", t); onlinetime %= 3600;}
		if (int t = onlinetime/60) {msg += sprintf(", %d minutes", t); onlinetime %= 60;}
		if (onlinetime) msg += sprintf(", %d seconds", onlinetime);
		return msg[2..];
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

