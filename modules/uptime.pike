inherit command;
//TODO-DOCSTRING

string process(object channel, object person, string param)
{
	if (string msg = channel_uptime(channel->name[1..]))
		return "@$$: Channel " + channel->name[1..] + " has been online for " + msg;
	return "Channel is currently offline.";
}

