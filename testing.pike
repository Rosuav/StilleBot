//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;
mapping irc_connections = ([]);

constant messagetypes = ({"WHISPER", "PRIVMSG"});

void bootstrap_all() {
	G->bootstrap("persist.pike");
	G->bootstrap("globals.pike");
	G->bootstrap("poll.pike");
	G->bootstrap("testing.pike");
}
void console(object stdin, string buf) {
	while (buf != "") {
		sscanf(buf, "%s%*[\n]%s", string line, buf);
		if (line == "update") bootstrap_all();
		if (line == "module") G->bootstrap("testing.pike");
	}
}

class channel(string name) {
	mapping config = ([]);

	protected void create() {config = persist_config["channels"][name[1..]];}

	void send(mapping person, echoable_message message, mapping|void vars) {
		if (stringp(message)) irc_connections[0]->send(name, message);
	}

	void irc_message(string type, string chan, string msg, mapping params) {
		string pfx = sprintf("[%s %s] ", type, name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		msg = string_to_utf8(msg);
		write("\e[1;42m%s\e[0m", sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
}

void irc_message(string type, string chan, string msg, mapping attrs) {
	object channel = G->G->irc->channels[chan];
	if (channel) channel->irc_message(type, chan, msg, attrs);
}

void irc_closed(mapping options) {
	::irc_closed(options);
	if (options->voiceid) m_delete(irc_connections, options->voiceid);
}

void reconnect() {
	array channels = "#" + indices(persist_config["channels"] || ([]))[*];
	G->G->irc = (["channels": mkmapping(channels, channel(channels[*]))]);
	irc_connect(([
		"join": filter(channels) {return __ARGS__[0][1] != '!';},
		"capabilities": "membership tags commands" / " ",
	]))->then() {irc_connections[0] = __ARGS__[0]; werror("Now connected: %O\n", __ARGS__[0]);}
	->thencatch() {werror("Unable to connect to Twitch:\n%s\n", describe_backtrace(__ARGS__[0]));};
	werror("Now connecting: %O queue %O\n", connection_cache->rosuav, connection_cache->rosuav->queue);
}

protected void create(string name) {
	::create(name);
	reconnect();
	Stdio.stdin->set_read_callback(console);
}
