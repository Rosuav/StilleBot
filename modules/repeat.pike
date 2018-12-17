inherit command;
constant require_moderator = 1;

void autospam(string channel, string msg)
{
	if (function f = bounce(this_function)) return f(channel, msg);
	//if (!G->G->stream_online_since[channel[1..]]) return;
	//call_out(autospam, delay * 60 - 60 + random(120));
	send_message(channel, "** " + msg);
}

int connected(string channel)
{
	//TODO: Start all timers for this channel at random(delay*60-60)+60
}

string process(object channel, object person, string param)
{
	//TODO: "!repeat 10 Hello, world" to pop out "Hello, world" every
	//10 +/- 1 minutes. If it begins !, run that command instead.
	call_out(autospam, 30, channel->name, "Hello, world");
	return "(happening)";
}

void create(string name)
{
	register_hook("channel-online", connected);
	register_bouncer(autospam);
	::create(name);
}
