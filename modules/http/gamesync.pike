inherit http_websocket;

constant markdown = #"# Game sync

<div id=game></div>
";

@retain: mapping game_data = ([]); //Map a room ID to (["data": arbitrary JSON-compatible data])

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	string group = req->variables->room;
	//TODO: Validate the group ID syntactically
	return render(req, ([
		"vars": (["ws_group": group || ""]),
	]));
}

mapping game_info(string group) {
	mapping info = game_data[group];
	if (!info) info = game_data[group] = (["data": ([])]);
	return info;
}

//TODO: Check the group ID to see if it's a private one
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) { }

mapping get_state(string|int group, string|void id) {
	if (!group || group == "" || group == "0" || group == "undefined") return (["no_room": 1]);
	mapping info = game_info(group);
	if (info->reset) return info->data | (["reset": info->reset]);
	return info->data;
}

void websocket_cmd_replace_data(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!mappingp(msg->data)) return;
	mapping info = game_info(conn->group);
	info->reset = info->data;
	info->data = msg->data;
	send_updates_all(conn->group);
}

void websocket_cmd_update_data(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!mappingp(msg->data)) return;
	mapping info = game_info(conn->group);
	foreach (msg->data; string key; mixed val)
		info->data[key] = val;
	m_delete(info, "reset");
	send_updates_all(conn->group);
}
