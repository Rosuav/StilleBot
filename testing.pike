//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;

constant messagetypes = ({"WHISPER", "PRIVMSG"});
void irc_message(string type, string chan, string msg, mapping attrs) {
	werror("irc_message: %O, %O, %O, %O\n", type, chan, msg, attrs);
	if (msg == "!quit") exit(0);
}

void irc_closed(mapping options) {werror("IRC connection closed.\n"); exit(0);}

protected void create(string name) {
	::create(name);
	spawn_task(do_stuff());
}
continue Concurrent.Future do_stuff() {
	string voiceid = "279141671", chan = "#rosuav";
	array msgs = ({"Hello from Mustard Mine"});
	mapping tok = persist_status["voices"][voiceid];
	werror("Connecting to voice %O...\n", voiceid);
	mixed ex = catch {
		object conn = yield(irc_connect(([
			"user": tok->login, "pass": tok->token,
			"voiceid": voiceid,
			"capabilities": ({"commands"}),
		])));
		werror("Voice %O connected, sending to channel %O\n", voiceid, chan);
		conn->send(chan, msgs[*]);
		conn->quit();
	};
	if (ex) werror("Unable to connect to voice %O:\n%s\n", voiceid, describe_backtrace(ex));
}
