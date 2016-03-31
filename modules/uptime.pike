inherit command;
constant require_allcmds = 1;

void process(object channel, object person, string param)
{
	if (object started = G->G->stream_online_since[channel->name[1..]])
	{
		int onlinetime = started->distance(Calendar.now())->how_many(Calendar.Second());
		string msg = "";
		if (int t = onlinetime/86400) {msg += sprintf(", %d days", t); onlinetime %= 86400;}
		if (int t = onlinetime/3600) {msg += sprintf(", %d hours", t); onlinetime %= 3600;}
		if (int t = onlinetime/60) {msg += sprintf(", %d minutes", t); onlinetime %= 60;}
		if (onlinetime) msg += sprintf(", %d seconds", onlinetime);
		send_message(channel->name, sprintf("@%s: Channel has been online since %s - %s",
			person->nick, started->format_nice(),msg[2..]));
	}
	else
		send_message(channel->name, "Channel is currently offline.");
}

