inherit http_endpoint;
inherit websocket_handler;

//Note that, in theory, multiple voice support could be done without an HTTP interface.
//It would be fiddly to set up, though, so I'm not going to try to support it at this
//stage. Maybe in the future. For now, if you're working without the web interface, you
//will need to manually set a "voice" on a command, and you'll need to manually craft
//the persist_status entries for the login.

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	return render_template("chan_voices.md", ([
		"vars": (["ws_type": "chan_voices", "ws_group": req->misc->channel->name]),
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if (!channel) return "Bad channel";
	conn->is_mod = channel->mods[conn->session->?user->?login];
	if (!conn->is_mod) return "Not logged in";
}

mapping get_state(string group, string|void id) {
	[object channel, string grp] = split_channel(group);
	if (!channel) return 0;
	return (["items": ({ })]);
}

protected void create(string name) {::create(name);}
