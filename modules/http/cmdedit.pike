inherit http_websocket;
inherit hook;
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

mapping _get_command(object channel, string cmd) {
	echoable_message response = channel->commands[cmd];
	if (!response) return 0;
	if (mappingp(response)) return response | (["id": cmd]);
	return (["message": response, "id": cmd]);
}
mapping get_chan_state(object channel, string group) {
	if (group == "!!trigger") {
		//For the front end, we pretend that there are multiple triggers with distinct IDs.
		//But here on the back end, they're a single array inside one command.
		echoable_message response = channel->commands["!trigger"];
		return (["commands": arrayp(response) ? response : ({ })]);
	}
	if (group != "" && group != "!!") return 0; //Single-command usage not yet implemented
	array commands = ({ });
	foreach (channel->commands; string cmd; echoable_message response) {
		if (group == "!!" && has_prefix(cmd, "!") && !has_prefix(cmd, "!!trigger")) commands += ({_get_command(channel, cmd)});
		else if (group == "" && !has_prefix(cmd, "!")) commands += ({_get_command(channel, cmd)});
	}
	sort(commands->id, commands);
	return (["commands": commands]);
}

mapping wscmd_cmdedit_subscribe(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping voices = G->G->DB->load_cached_config(channel->userid, "voices");
	string defvoice = channel->config->defvoice;
	if (voices[defvoice]) voices |= (["0": (["name": "Bot's own voice"])]); //TODO: Give the bot's username?
	send_msg(conn, get_state(conn->subscription_group) | (["cmd": "cmdedit_publish_commands"])); //NOTE: Will break if get_chan_state is asynchronous
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
	//Similar to above, broadcast a message across all groups for one channel.
	mapping msg = (["cmd": "cmdedit_update_collections", coll: data]);
	string text = Standards.JSON.encode(msg, 4);
	string suffix = "#" + channel->userid;
	foreach (websocket_groups; string group; array socks)
		if (has_suffix(group, suffix))
			foreach (socks, object sock)
				if (sock && sock->state == 1) sock->send_text(text);
}

@hook_reward_changed: void notify_rewards(object channel, string|void rewardid) {
	update_channel_collection(channel, "pointsrewards", G->G->pointsrewards[channel->userid] || ({ }));
}

protected void create(string name) {::create(name);}
