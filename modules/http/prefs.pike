inherit http_websocket;
constant markdown = #"# Preferences and configuration

Coming Soon&trade;
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": "n/a"]), //The real synchronization happens through the per-user prefs
	]));
}

string websocket_validate(mapping conn, mapping msg) {return conn->session->user->?id ? 0 : "Not logged in";}
mapping get_state(string group) {return (["info": "See Other"]);}

//Everything from here down should be looking at the user prefs, and may come from any page,
//not just /prefs.
void websocket_cmd_prefs_send(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->prefs_uid) return;
	mapping prefs = persist_status->path("userprefs", conn->prefs_uid);
	write("SENDING PREFS %O\n", prefs);
	write("My connections: %O\n", websocket_groups);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "prefs_replace", "prefs": prefs])));
}
void websocket_cmd_prefs_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->prefs_uid || !mappingp(msg->prefs)) return;
	write("UPDATING PREFS: %O\n", msg);
	mapping prefs = persist_status->path("userprefs", conn->prefs_uid);
	prefs |= msg->prefs;
	persist_status->save();
	//TODO maybe: Have a simpler command prefs_update which, clientside, will
	//merge the given prefs with any existing ones. It should give the same
	//end result as this, but with less traffic, esp if some things are large
	//and others change frequently.
	conn->sock->send_text(Standards.JSON.encode((["cmd": "prefs_replace", "prefs": prefs])));
}
