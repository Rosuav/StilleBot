inherit http_websocket;
inherit enableable_module; //Also handles all builtins with suggestions

//Simplistic stringification for read-only display.
string respstr(echoable_message resp)
{
	if (stringp(resp)) return resp;
	if (arrayp(resp)) return respstr(resp[*]) * "<br>";
	return respstr(resp->message);
}

constant MAX_RESPONSES = 10; //Max pieces of text per command, for simple view. Can be exceeded by advanced editing.

//If a command is listed here, its base description is just the human-readable version, and
//this is what will actually be used for the command. Selecting such a template will also
//use the Advanced view in the front end.
constant COMPLEX_TEMPLATES = ([
	"!winner": ({
		"Congratulations, %s! You have won The Thing! Details are waiting for you over here: https://sikorsky.rosuav.com/channels/##CHANNEL##/messages",
		(["message": "Your secret code is 0TB54-I3YKG-CNDKV and you can go to https://some.url.example/look-here to redeem it!", "dest": "/web %s"]),
	}),
	"!play": (["message": "We're over here: https://jackbox.tv/#ABCD", "dest": "/web $$"]),
	"!hydrate": ({
		"devicatSip Don't forget to drink water! devicatSip",
		(["message": "devicatSip Drink more water! devicatSip", "delay": 1800]),
	}),
	"!hug": ([
		"conditional": "string", "expr1": "%s",
		"message": "/me devicatHug $$ warmly hugs {participant} maayaHug",
		"otherwise": "/me devicatHug $$ warmly hugs %s maayaHug",
	]),
	"!song": ([
		"conditional": "string", "expr1": "$vlcplaying$", "expr2": "1",
		"message": "SingsNote Now playing: $vlccurtrack$ SingsNote",
		"otherwise": "rosuavMuted Not currently playing anything in VLC rosuavMuted",
	]),
	"!periodic": ([
		"access": "none", "visibility": "hidden",
		"automate": ({30, 30, 0}), "mode": "rotate",
		"message": ({
			"If you'd like to see more of what I do, check out my social media: https://some.example/ https://example.com/ https://etc.example/myusername",
			"If you're enjoying your time here, consider devicatLove_TK the follow button - it would touch my heart!",
			"Thank you for being here! We appreciate you for choosing to spend time here <3",
			"It's totally okay to lurk here! Thank you for hanging out with us.",
		}),
	]),
	"!raid": ({
		"Let's go raiding! Copy and paste this raid call and be ready when I host our target!",
		" /me twitchRaid YOUR RAID CALL HERE twitchRaid"
	}),
]);

//It's okay for this to be empty, but this module must remain able to enable and disable features
constant ENABLEABLE_FEATURES = ([
	"!song": ([
		"description": "Show the currently-playing song (see VLC integration)",
		"fragment": "#song/",
	]),
]);

int can_manage_feature(object channel, string kwd) {return channel->commands[kwd - "!"] ? 2 : 1;} //Should it check if it's the right thing, and if not, return 3?

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd];
	//Not one defined here? Try a builtin's suggestions.
	if (!info) foreach (G->G->builtins; string name; object blt)
		if (blt->command_suggestions[?kwd]) info = (["response": blt->command_suggestions[kwd]]);
	if (!info) return;
	G->G->cmdmgr->update_command(channel, "", kwd, state ? info->response || COMPLEX_TEMPLATES[kwd] : "");
}

//Gather all the variables that the JS command editor needs. Some may depend on the channel.
mapping(string:mixed) command_editor_vars(object channel) {
	mapping voices = channel->config->voices || ([]);
	string defvoice = channel->config->defvoice;
	if (voices[defvoice]) voices |= (["0": (["name": "Bot's own voice"])]); //TODO: Give the bot's username?
	return ([
		"complex_templates": G->G->commands_complex_templates,
		"builtins": G->G->commands_builtins,
		"pointsrewards": G->G->pointsrewards[channel->userid] || ({ }),
		"voices": voices,
		"monitors": channel->config->monitors || ([]),
	]);
}

//Cache the set of available builtins. Needs to be called after any changes to any
//builtin; currently, is call_out zero'd any time this file gets updated. Note that
//this info can also be used by other things that call on the commands front end.
void find_builtins() {
	array templates = ({ });
	mapping complex_templates = COMPLEX_TEMPLATES | ([]);
	multiset seen = (<>);
	mapping(string:mapping(string:string)) builtins = ([]);
	foreach (sort(indices(G->G->builtins)), string name) {
		object handler = G->G->builtins[name];
		if (seen[handler]) continue; seen[handler] = 1; //If there are multiple, keep the alphabetically-earliest.
		mapping cmds = handler->command_suggestions || ([]);
		foreach (cmds; string cmd; mapping info) {
			templates += ({sprintf("%s | %s", cmd, info->_description || handler->command_description)});
			complex_templates[cmd] = info - (<"_description">);
		}
		builtins[name] = (["desc": handler->builtin_description, "name": handler->builtin_name, "param": handler->builtin_param]) | handler->vars_provided;
		if (builtins[name]->desc == "") builtins[name]->desc = handler->command_description;
	}
	G->G->commands_templates = templates;
	G->G->commands_complex_templates = complex_templates;
	G->G->commands_builtins = builtins;
	G->G->command_editor_vars = command_editor_vars;
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->request_type == "POST") {
		//Undocumented and private. May be moved to a better location and made public.
		//Syntax-validate a JSON message structure. Returns the canonicalized version,
		//or a zero.
		mixed body = Standards.JSON.decode(utf8_to_string(req->body_raw));
		if (!body || !mappingp(body) || !mappingp(body->msg)) return (["error": 400]);
		//NOTE: Uses an internal API. So this is undocumented AND unsupported. Great.
		echoable_message result = G->G->cmdmgr->_validate_toplevel(body->msg, (["cmd": body->cmdname || "validateme", "cooldowns": ([])]));
		if (body->cmdname == "!!trigger" && result != "") {
			if (!mappingp(result)) result = (["message": result]);
			m_delete(result, "otherwise"); //Triggers don't have an Else clause
			if (stringp(body->msg->id)) result->id = body->msg->id; //Triggers may have IDs, in which case we should keep them.
		}
		return jsonify(result, 7);
	}
	if (req->misc->is_mod) {
		return render(req, ([
			"vars": (["ws_group": ""]) | command_editor_vars(req->misc->channel),
			"templates": G->G->commands_templates * "\n",
			"save_or_login": ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
				"[Save all](:#saveall)"
			),
		]) | req->misc->chaninfo);
	}
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ });
	object user = user_text();
	foreach (req->misc->channel->commands; string cmd; echoable_message response) if (!has_prefix(cmd, "!"))
	{
		if (mappingp(response) && response->visibility == "hidden") continue;
		//Recursively convert a response into HTML. Ignores submessage flags.
		//TODO: Respect *some* flags, even if only to suppress a subbranch.
		string htmlify(echoable_message response) {
			if (stringp(response)) return user(response);
			if (arrayp(response)) return htmlify(response[*]) * "</code><br><code>";
			if (mappingp(response)) return htmlify(response->message);
		}
		commands += ({sprintf("<code>!%s</code> | <code>%s</code> | %s",
			user(cmd - c), htmlify(response),
			//TODO: Show if a response would be whispered?
			(["mod": "Mod-only", "vip": "Mods/VIPs", "none": "Disabled"])[mappingp(response) && response->access] || "",
		)});
		order += ({cmd});
	}
	sort(order, commands);
	if (!sizeof(commands)) commands = ({"(none) |"});
	return render(req, ([
		"user text": user,
		"commands": commands * "\n",
		"templates": G->G->commands_templates * "\n",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	sscanf(msg->group, "%s#%s", string command, string chan);
	if (!(<"", "!!", "!!trigger">)[command]) return "UNIMPL"; //TODO: Check that there actually is a command of that name
}

mapping _get_command(object channel, string cmd) {
	sscanf(cmd, "%s#", cmd); //In case any command names have the channel name appended (it'll be ignored even if wrong).
	echoable_message response = channel->commands[cmd];
	if (!response) return 0;
	if (mappingp(response)) return response | (["id": cmd + channel->name]);
	return (["message": response, "id": cmd + channel->name]);
}

mapping get_chan_state(object channel, string command, string|void id) {
	if (command == "!!trigger") {
		//For the front end, we pretend that there are multiple triggers with distinct IDs.
		//But here on the back end, they're a single array inside one command.
		echoable_message response = channel->commands["!trigger"];
		if (id) return 0; //Partial updates of triggers not currently supported. If there are enough that this matters, consider implementing.
		return (["items": arrayp(response) ? response : ({ })]);
	}
	if (id) return _get_command(channel, id); //Partial update of a single command. This will only happen if signalled from the back end.
	if (command != "" && command != "!!") return 0; //Single-command usage not yet implemented
	array commands = ({ });
	foreach (channel->commands; string cmd; echoable_message response) {
		if (command == "!!" && has_prefix(cmd, "!") && !has_prefix(cmd, "!!trigger")) commands += ({_get_command(channel, cmd)});
		else if (command == "" && !has_prefix(cmd, "!")) commands += ({_get_command(channel, cmd)});
	}
	sort(commands->id, commands);
	return (["items": commands]);
}

void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	echoable_message valid = G->G->cmdmgr->update_command(channel, (conn->group / "#")[0], msg->cmdname, msg->response, ([
		"original": msg->original,
		"language": msg->language == "mustard" ? "mustard" : "",
	]));
	if (!valid) return;
	if (msg->cmdname == "" && has_prefix(conn->group, "!!trigger#")) {
		//Newly added command. The client needs to know the ID so it can pop it up.
		conn->sock->send_text(Standards.JSON.encode((["cmd": "newtrigger", "response": valid[1][-1]])));
	}
}
void wscmd_delete(object c, mapping conn, mapping msg) {wscmd_update(c, conn, msg | (["response": ""]));}

void websocket_cmd_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string mode] = split_channel(conn->group);
	if (!channel) return 0;
	array valid = G->G->cmdmgr->validate_command(channel, mode, msg->cmdname || "validateme", msg->response, ([
		"original": msg->original,
		"language": msg->language == "mustard" ? "mustard" : "",
	]));
	if (!valid) { //But it's okay if the name is invalid, or in demo mode (fake-mod)
		if (has_prefix(msg->cmdname, "changetab_"))
			conn->sock->send_text(Standards.JSON.encode((["cmd": "changetab_failed"]), 4));
		return;
	}
	if (msg->cmdname == "changetab_mustard") {
		//HACK: Currently using the changetab name to request MustardScript.
		//TODO: Do this properly somehow.
		valid[1] = G->G->mustard->make_mustard(valid[1]);
	}
	string cmdname = ((msg->cmdname || valid[0] || "validateme") / "#")[0];
	conn->sock->send_text(Standards.JSON.encode((["cmd": "validated", "cmdname": cmdname, "response": valid[1]]), 4));
}

protected void create(string name) {
	::create(name);
	call_out(find_builtins, 0);
}
