//Build code into this file to be able to quickly and easily run it using "stillebot --test"
inherit irc_callback;

constant messagetypes = ({"WHISPER"});
void irc_message(string type, string chan, string msg, mapping attrs) {
	werror("irc_message: %O, %O, %O, %O\n", type, chan, msg, attrs);
	if (msg == "!quit") exit(0);
}

protected void create(string name) {
	::create(name);
	irc_connect((["join": "#twitch", "user": "mustardmine", "capabilities": "tags commands" / " "]));
}
