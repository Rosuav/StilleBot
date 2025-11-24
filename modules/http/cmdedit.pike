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
	return ([
		"cmd": "cmdedit_update_collections",
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
