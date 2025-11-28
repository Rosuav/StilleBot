inherit http_websocket;
constant subscription_valid = 1; //A bit hacky. Mark this as a type that can be subscribed to.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return redirect("commands"); //You shouldn't be going to /c/cmdedit, it's just a sub-socket
}

bool need_mod(string grp) {return 1;}
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	if (msg->cmd == "init") return "Subscription only";
	sscanf(msg->group, "%s#%s", string command, string chan);
	if (!(<"", "!!", "!!trigger">)[command]) return "UNIMPL"; //TODO: Unify this with chan_commands' validation, or just migrate it here. Also handle single-command subscription.
}

mapping get_chan_state(object channel, string group) {
	return (["unimp": "cmdedit socket data"]);
}

mapping wscmd_cmdedit_subscribe(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping voices = G->G->DB->load_cached_config(channel->userid, "voices");
	string defvoice = channel->config->defvoice;
	if (voices[defvoice]) voices |= (["0": (["name": "Bot's own voice"])]); //TODO: Give the bot's username?
	return ([
		"cmd": "cmdedit_update_collections",
		"pointsrewards": G->G->pointsrewards[channel->userid] || ({ }),
		"voices": voices,
		"monitors": G->G->DB->load_cached_config(channel->userid, "monitors"),
		"builtins": G->G->commands_builtins,
		"slash_commands": G->G->slash_commands,
	]);
}

void update_collection(string coll, array|mapping data) {
	//Broadcast a message across all groups, giving the new collection
	mapping msg = (["cmd": "cmdedit_update_collections", coll: data]);
	string text = Standards.JSON.encode(msg, 4);
	foreach (websocket_groups;; array socks)
		foreach (socks, object sock)
			if (sock && sock->state == 1) sock->send_text(text);
}

void update_channel_collection(object channel, string coll, array|mapping data) {
	//TODO: Whenever any of the per-channel subscribed features changes (eg new
	//voice authenticated), push out a change. This should be similar to
	//update_collection above, but send only to sockets for the given channel.
}
