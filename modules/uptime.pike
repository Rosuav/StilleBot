inherit command;
constant docstring = #"
Show channel uptime.

It's possible that this information will be a little delayed, showing
that the channel is offline if it's just started, and/or still showing
the uptime just after it goes offline.
";

string process(object channel, object person, string param)
{
	if (string msg = channel_uptime(channel->name[1..]))
		return "@$$: Channel " + channel->name[1..] + " has been online for " + msg;
	return "Channel is currently offline.";
}

