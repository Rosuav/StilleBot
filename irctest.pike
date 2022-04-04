inherit irc_callback;
object irc;

continue Concurrent.Future say_hello(string channel) {
	irc = yield(irc_connect(([
		"user": "rosuav", "pass": persist_config->path("ircsettings", "pass"),
		"join": channel,
		//"capabilities": ({"membership", "commands", "tags"}),
	])));
	//irc->send(channel, "!hello");
}

void irc_message(string type, string chan, string msg, mapping attrs) {
	if (type != "PRIVMSG") return;
	write("[%d] Got msg: %O %O\n", hash_value(this), msg, attrs);
	if (msg == "!quit") irc->quit();
}

void irc_closed(mapping options) {
	write("Shutting down!\n");
	exit(0);
}

protected void create(string name) {
	::create(name);
	write("Creating %O with ID %d\n", name, hash_value(this));
	spawn_task(say_hello("#rosuav"));
}
