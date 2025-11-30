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
//TODO: Support single-element updates?
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

void wscmd_cmdedit_subscribe(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping voices = G->G->DB->load_cached_config(channel->userid, "voices");
	string defvoice = channel->config->defvoice;
	if (voices[defvoice]) voices |= (["0": (["name": "Bot's own voice"])]); //TODO: Give the bot's username?
	send_msg(conn, ([
		"cmd": "cmdedit_update_collections",
		"pointsrewards": G->G->pointsrewards[channel->userid] || ({ }),
		"voices": voices,
		"monitors": G->G->DB->load_cached_config(channel->userid, "monitors"),
		"builtins": G->G->commands_builtins,
		"slash_commands": G->G->slash_commands,
	]));
	send_msg(conn, get_state(conn->subscription_group) | (["cmd": "cmdedit_publish_commands"])); //NOTE: Will break if get_chan_state is asynchronous
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

void update_command(object channel, string command) {
	//Push out updates relevant to a particular command.
	//TODO: Rework this to an update_commands that will batch updates where applicable
	//HACK HACK HACK: For now, any time there's an update, it updates everything for that channel
	string suffix = "#" + channel->userid;
	foreach (websocket_groups; string group; array socks)
		if (has_suffix(group, suffix)) {
			mapping msg = get_state(group) | (["cmd": "cmdedit_publish_commands"]);
			string text = Standards.JSON.encode(msg, 4);
			foreach (socks, object sock)
				if (sock && sock->state == 1) sock->send_text(text);
		}
}

@hook_reward_changed: void notify_rewards(object channel, string|void rewardid) {
	update_channel_collection(channel, "pointsrewards", G->G->pointsrewards[channel->userid] || ({ }));
}

void wscmd_cmdedit_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	echoable_message valid = G->G->cmdmgr->update_command(channel, (conn->group / "#")[0], msg->cmdname, msg->response, ([
		"original": msg->original,
		"language": msg->language == "mustard" ? "mustard" : "",
	]));
	if (!valid) return;
	if (msg->cmdname == "" && has_prefix(conn->group, "!!trigger#")) {
		//Newly added command. The client needs to know the ID so it can pop it up.
		//FIXME: Should this be cmdedit_newtrigger? Is it even being used?
		conn->sock->send_text(Standards.JSON.encode((["cmd": "newtrigger", "response": valid[1][-1]])));
	}
}
void wscmd_cmdedit_delete(object c, mapping conn, mapping msg) {wscmd_cmdedit_update(c, conn, msg | (["response": ""]));}

//This should probably go somewhere else, but really, we should just be as consistent as possible
//with key names.
mapping user_to_person(mapping user) {
	return ([
		"displayname": user->display_name || user->login,
		"user": user->login,
		"uid": user->uid,
	]);
}

void wscmd_cmdedit_execute(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string cmdname = "validateme";
	if (conn->subgroup == "!!" && stringp(msg->cmdname) && has_prefix(msg->cmdname, "!")) cmdname = msg->cmdname;
	array valid = G->G->cmdmgr->validate_command(channel, conn->subgroup, cmdname, msg->response, ([
		"language": msg->language == "mustard" ? "mustard" : "",
	]));
	if (valid) {
		mapping runme = valid[2];
		//Triggers are always conditional. (Even an "every message" trigger technically has a condition.)
		//If you explicitly say "run this", you likely want it to happen regardless of the condition, so
		//dig into the message and grab the actual command.
		if (mapping msg = valid[1] == "!trigger" && mappingp(runme) && runme->message) runme = msg;
		//TODO: If G->G->special_commands[valid[1]], call its placeholder generator to make the params
		mapping params = ([
			"{param}": "", //Should there be a prompt for params? Probably not.
		]);
		channel->send(user_to_person(conn->session->user), runme, params);
	}
}

void wscmd_cmdedit_deletereward(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Not technically part of command management, but intended for use alongside it.
	twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + msg->redemption,
		(["Authorization": channel->userid]),
		(["method": "DELETE"]),
	);
}

void websocket_cmd_cmdedit_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string mode] = split_channel(conn->group);
	if (!channel) return 0; //Fake-mod mode is okay here (this handles tab switching inside the editor)
	array valid = G->G->cmdmgr->validate_command(channel, mode, msg->cmdname || "validateme", msg->response, ([
		"original": msg->original,
		"language": msg->language == "mustard" ? "mustard" : "",
	]));
	if (!valid) {
		if (has_prefix(msg->cmdname, "changetab_"))
			conn->sock->send_text(Standards.JSON.encode((["cmd": "changetab_failed"]), 4));
		return;
	}
	if (msg->cmdname == "changetab_mustard") {
		//HACK: Currently using the changetab name to request MustardScript.
		//TODO: Do this properly somehow.
		valid[2] = G->G->mustard->make_mustard(valid[2]);
	}
	string cmdname = ((msg->cmdname || valid[1] || "validateme") / "#")[0];
	conn->sock->send_text(Standards.JSON.encode((["cmd": "cmdedit_validated", "cmdname": cmdname, "response": valid[2]]), 4));
}

__async__ void websocket_cmd_cmdedit_list_emotes(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string mode] = split_channel(conn->group);
	if (!channel) return 0; //Fake-mod mode is okay here too for the same reason (emote picker)
	mapping voices = G->G->DB->load_cached_config(channel->userid, "voices");
	string voice = msg->voice;
	if (!voice || voice == "") voice = channel->config->defvoice;
	if (!voices[voice]) return; //TODO: Send an error back?
	mapping emotes = G_G_("voice_emotes", (string)channel->userid, voice);
	//Send the existing emotes, then update them once they're fetched.
	if (emotes->emotes) conn->sock->send_text(Standards.JSON.encode((["cmd": "emotes_available", "voice": msg->voice, "emotes": emotes]), 4));
	if (emotes->fetched > time() - 60) return; //Or not. I mean, one minute, it can have stale data if it wants.
	emotes->voice = voices[voice]->id;
	emotes->voice_name = voices[voice]->desc; //Or should it use voices[voice]->name?
	emotes->profile_image_url = voices[voice]->profile_image_url;
	m_delete(emotes, "error");
	mapping cred = G->G->user_credentials[(int)voice];
	if (!has_value(cred->scopes, "user:read:emotes")) {
		emotes->error = "Emote picker not available for this voice - reauthenticating may help";
		conn->sock->send_text(Standards.JSON.encode(([
			"cmd": "cmdedit_emotes_available", "voice": msg->voice,
			"emotes": emotes,
		]), 4));
		return;
	}
	mapping args = (["user_id": voice]);
	if (channel->userid) args->broadcaster_id = (string)channel->userid; //Include follower emotes from this channel (unless it's the demo)
	array emotes_raw = await(get_helix_paginated("https://api.twitch.tv/helix/chat/emotes/user",
		args, (["Authorization": "Bearer " + cred->token])));
	emotes->emotes = await(G->G->categorize_emotes(emotes_raw));
	//TODO: Retain this rather than discarding it in get_helix_paginated
	emotes->template = "https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}";
	emotes->fetched = time();
	if (conn->sock) conn->sock->send_text(Standards.JSON.encode((["cmd": "cmdedit_emotes_available", "voice": msg->voice, "emotes": emotes]), 4));
}

protected void create(string name) {::create(name);}
