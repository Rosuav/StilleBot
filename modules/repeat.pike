inherit command;
constant require_moderator = 1;

void autospam()
{
	//if (has_been_updated) {chain(); return;}
	//if (!channel_is_online) return;
	//call_out(autospam, delay * 60 - 60 + random(120));
}

int connected(string channel)
{
	//TODO: Start all timers for this channel
}

string process(object channel, object person, string param)
{
	//TODO: "!repeat 10 Hello, world" to pop out "Hello, world" every
	//10 +/- 1 minutes. If it begins !, run that command instead.
	return "(unimplemented)";
}

void create(string name)
{
	register_hook("channel-online", connected);
	::create(name);
}
