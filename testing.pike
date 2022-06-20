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

continue Concurrent.Future voice_enable(string voiceid, string chan, array(string) msgs) {
	mapping tok = persist_status["voices"][voiceid];
	werror("Connecting to voice %O...\n", voiceid);
	object conn = yield(irc_connect(([
		"user": tok->login, "pass": "oauth:" + tok->token,
		"voiceid": voiceid,
		"capabilities": ({"commands"}),
	])));
	werror("Voice %O connected, sending to channel %O\n", voiceid, chan);
	irc_connections[voiceid] = conn;
	conn->yes_reconnect(); //Mark that we need this connection
	conn->send(chan, msgs[*]);
	conn->enqueue(conn->no_reconnect); //Once everything's sent, it's okay to disconnect
}

continue Concurrent.Future poke_channels() {
	array channels = ({
		"#rosuav", "#pixalicious_", "#mustardmine", "#devicat", "#khamidova",
		"#loudlotus", "#lara_cr", "#hallwayraptor", "#itsastarael",
		"#stephenangelico", "#lulu_jenkins", "#othersister", "#ladydreamtv",
	});
	foreach (channels, string name) {
		mixed _ = yield(voice_enable("279141671", name, ({"Hi! Don't mind me, just doing some random spot-checking of a bot feature. MrDestructoid"})));
		yield(task_sleep(0.125));
	}
}

class channel(string name) {
	mapping config = ([]);

	protected void create() {config = persist_config["channels"][name[1..]];}

	void irc_message(string type, string chan, string msg, mapping params) {
		if (name == "#rosuav" && msg == "!mm") spawn_task(poke_channels());
		if (name == "#rosuav" && msg == "!test") {
			werror("Test command, responding! Queue: %O\n", connection_cache->rosuav->queue);
			irc_connections[0]->send(name, "This is a test MrDestructoid");
		}
		string pfx = sprintf("[%s %s] ", type, name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		if (sscanf(msg, "\1ACTION %s\1", msg)) msg = " " + msg;
		else msg = ": " + msg;
		msg = string_to_utf8(params->display_name + msg + " ");
		if (config->chatlog || params->user_id == "279141671") write("\e[1;32m%s\e[0m", sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
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
	]))->then() {irc_connections[0] = __ARGS__[0]; werror("[%d] Now connected: %O\n", time(), __ARGS__[0]);}
	->thencatch() {werror("Unable to connect to Twitch:\n%s\n", describe_backtrace(__ARGS__[0]));};
	werror("[%d] Now connecting: %O queue %O\n", time(), connection_cache->rosuav, connection_cache->rosuav->queue);
}

protected void create(string name) {
	::create(name);
	reconnect();
	Stdio.stdin->set_read_callback(console);
}
