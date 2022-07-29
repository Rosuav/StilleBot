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

void irc_message(string type, string chan, string msg, mapping params) {
	if (chan == "#rosuav" && msg == "!test") {
		werror("Test command, responding! Queue: %O\n", connection_cache->rosuav->queue);
		irc_connections[0]->send(chan, "This is a test MrDestructoid");
	}
	string pfx = sprintf("[%s %s] ", type, chan);
	int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
	if (sscanf(msg, "\1ACTION %s\1", msg)) msg = " " + msg;
	else msg = ": " + msg;
	msg = string_to_utf8(params->display_name + msg + " ");
	write("\e[1;32m%s\e[0m", sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
}

void reconnect() {
	irc_connect(([
		"join": "#rosuav",
		"capabilities": "membership tags commands" / " ",
	]))->then() {irc_connections[0] = __ARGS__[0]; werror("[%d] Now connected: %O\n", time(), __ARGS__[0]);}
	->thencatch() {werror("Unable to connect to Twitch:\n%s\n", describe_backtrace(__ARGS__[0]));};
	werror("[%d] Now connecting: %O queue %O\n", time(), connection_cache->rosuav, connection_cache->rosuav->queue);
}

protected void create(string name) {
	::create(name);
	reconnect();
	Stdio.stdin->set_read_callback(console);
}
