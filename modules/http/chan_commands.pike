inherit http_websocket;
inherit enableable_module;

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
		//TODO: Populate the actual channel name in the template
		"Congratulations, %s! You have won The Thing! Details are waiting for you over here: https://sikorsky.rosuav.com/channels/##CHANNEL##/private",
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
		"message": "SingsNote Now playing: {track} ({block}) SingsNote",
		"otherwise": "rosuavMuted Not currently playing anything in VLC rosuavMuted",
	]),
]);
	
constant ENABLEABLE_FEATURES = ([
	"song": ([
		"description": "A !song command to show the currently-playing song (see VLC integration)",
	]),
]);

int can_manage_feature(object channel, string kwd) {return G->G->echocommands[kwd + channel->name] ? 2 : 1;} //Should it check if it's the right thing, and if not, return 3?

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	//Hack: Call on the normal commands updater to add a trigger
	if (!state)
		websocket_cmd_delete(
			(["group": channel->name]),
			(["cmdname": kwd])
		);
	else
		websocket_cmd_update(
			(["group": channel->name]),
			(["cmdname": kwd, "response": info->response || COMPLEX_TEMPLATES["!" + kwd]])
		);
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
		mapping cmds = handler->command_suggestions || (["!" + name: ([
			"builtin_param": "%s",
			"access": handler->require_moderator ? "mod" : handler->access,
			"message": handler->default_response,
			"aliases": handler->aliases * " ",
		])]);
		foreach (cmds; string cmd; mapping info) {
			templates += ({sprintf("%s | %s", cmd, info->_description || handler->command_description)});
			complex_templates[cmd] = (["builtin": name, "builtin_param": "%s"]) | info - (<"_description">);
		}
		builtins[name] = (["*": handler->builtin_description, "": handler->builtin_name]) | handler->vars_provided;
		if (builtins[name]["*"] == "") builtins[name]["*"] = handler->command_description;
		if (builtins[name][""] == "") builtins[name][""] = "!" + name; //Best not to rely on this
	}
	G->G->commands_templates = templates;
	G->G->commands_complex_templates = complex_templates;
	G->G->commands_builtins = builtins;
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->misc->is_mod) {
		return render(req, ([
			"vars": (["ws_group": "", "complex_templates": G->G->commands_complex_templates, "builtins": G->G->commands_builtins,
				"voices": req->misc->channel->config->voices || ([])]),
			"templates": G->G->commands_templates * "\n",
			"save_or_login": ("<p><a href=\"#examples\" id=examples>Example and template commands</a></p>"
				"<input type=submit value=\"Save all\">"
			),
		]) | req->misc->chaninfo);
	}
	string c = req->misc->channel->name;
	array commands = ({ }), order = ({ });
	object user = user_text();
	foreach (G->G->echocommands; string cmd; echoable_message response) if (!has_prefix(cmd, "!") && has_suffix(cmd, c))
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
			(["mod": "Mod-only", "none": "Disabled"])[mappingp(response) && response->access] || "",
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

mapping _get_command(string cmd) {
	echoable_message response = G->G->echocommands[cmd];
	if (!response) return 0;
	if (mappingp(response)) return response | (["id": cmd]);
	return (["message": response, "id": cmd]);
}

mapping get_state(string group, string|void id) {
	sscanf(group, "%s#%s", string command, string chan);
	if (!G->G->irc->channels["#" + chan]) return 0;
	if (command == "!!trigger") {
		//For the front end, we pretend that there are multiple triggers with distinct IDs.
		//But here on the back end, they're a single array inside one command.
		echoable_message response = G->G->echocommands["!trigger#" + chan];
		if (id) return 0; //Partial updates of triggers not currently supported. If there are enough that this matters, consider implementing.
		return (["items": arrayp(response) ? response : ({ })]);
	}
	if (id) return _get_command(id); //Partial update of a single command. This will only happen if signalled from the back end.
	if (command != "" && command != "!!") return 0; //Single-command usage not yet implemented
	array commands = ({ });
	foreach (G->G->echocommands; string cmd; echoable_message response) if (has_suffix(cmd, "#" + chan))
	{
		if (command == "!!" && has_prefix(cmd, "!") && !has_prefix(cmd, "!!trigger#")) commands += ({_get_command(cmd)});
		else if (command == "" && !has_prefix(cmd, "!")) commands += ({_get_command(cmd)});
	}
	sort(commands->id, commands);
	return (["items": commands]);
}

//Map a flag name to a set of valid values for it
//Blank or null is always allowed, and will result in no flag being set.
constant valid_flags = ([
	"mode": (<"random">),
	"access": (<"mod", "none">),
	"visibility": (<"hidden">),
	"action": (<"add">),
	"dest": (<"/w", "/web", "/set">),
]);

constant condition_parts = ([
	"string": ({"expr1", "expr2", "casefold"}),
	"contains": ({"expr1", "expr2", "casefold"}),
	"regexp": ({"expr1", "expr2", "casefold"}),
	"number": ({"expr1"}), //Yes, expr1 even though there's no others - means you still see it when you switch
	"cooldown": ({"cdname", "cdlength"}),
]);

//state array is for purely-linear state that continues past subtrees
echoable_message validate(echoable_message resp, mapping state)
{
	//Filter the response to only that which is valid
	if (stringp(resp)) return resp;
	if (arrayp(resp)) switch (sizeof(resp))
	{
		case 0: return ""; //This should be dealt with at a higher level (and suppressed).
		case 1: return validate(resp[0], state); //Collapse single element arrays to their sole element
		default: return validate(resp[*], state) - ({""}); //Suppress any empty entries
	}
	if (!mappingp(resp)) return ""; //Ensure that nulls become empty strings, for safety and UI simplicity.
	mapping ret = (["message": validate(resp->message, state)]);
	//Whitelist the valid flags. Note that this will quietly suppress any empty
	//strings, which would be stating the default behaviour.
	foreach (valid_flags; string flag; multiset ok)
	{
		if (ok[resp[flag]]) ret[flag] = resp[flag];
	}
	if (ret->dest) {
		//If there's any dest other than "" (aka "open chat"), it should
		//have a target. Failing to have a target breaks other destinations,
		//so remove that if this is missing; otherwise, any target works.
		if (!resp->target) m_delete(ret, "dest");
		else ret->target = resp->target;
	}
	if (resp->dest == "/builtin" && resp->target) {
		//A dest of "/builtin" is really a builtin. What a surprise :)
		sscanf(resp->target, "!%[^ ]%*[ ]%s", resp->builtin, resp->builtin_param);
	}
	else if (resp->dest && has_prefix(resp->dest, "/"))
	{
		//Legacy mode. Fracture the dest into dest and target.
		sscanf(resp->dest, "/%[a-z] %[a-zA-Z$%]%s", string dest, string target, string empty);
		if ((<"w", "web", "set">)[dest] && target != "" && empty == "")
			[ret->dest, ret->target] = ({"/" + dest, target});
	}
	if (resp->builtin && G->G->builtins[resp->builtin]) {
		//Validated separately as the builtins aren't a constant
		ret->builtin = resp->builtin;
		if (resp->builtin_param && resp->builtin_param != "") ret->builtin_param = resp->builtin_param;
	}
	//Conditions have their own active ingredients.
	if (array parts = condition_parts[resp->conditional]) {
		foreach (parts + ({"conditional"}), string key)
			if (resp[key]) ret[key] = resp[key];
		ret->otherwise = validate(resp->otherwise, state);
		if (ret->message == "" && ret->otherwise == "") return ""; //Conditionals can omit either message or otherwise, but not both
		if (ret->conditional == "cooldown") {
			string name = ret->cdname || "";
			//Anonymous cooldowns get named for the back end, but the front end will blank this.
			//If the front end happens to return something with a dot name in it, ignore it.
			if (name == "" || name[0] == '.') ret->cdname = name = sprintf(".%s:%d", state->cmd, ++state->cdanon);
			ret->cdlength = (int)ret->cdlength;
			if (ret->cdlength) state->cooldowns[name] = ret->cdlength;
			else m_delete(ret, (({"conditional", "otherwise"}) + parts)[*]); //Not a valid cooldown.
			//TODO: Keyword-synchronized cooldowns should synchronize their cdlengths too
		}
	}
	else if (ret->message == "") return ""; //No message? Nothing to do.
	//Delays are integer seconds. We'll permit a string of digits, since that might be
	//easier for the front end.
	if (resp->delay && resp->delay != "0" &&
			(intp(resp->delay) || (sscanf((string)resp->delay, "%[0-9]", string d) && d == resp->delay)))
		ret->delay = (int)resp->delay;

	//Aliases are blank-separated, and might be entered in the UI with bangs.
	//But internally, we'd rather have them without.
	array(string) aliases = (resp->aliases || "") / " " - ({""});
	aliases = aliases[*] - "!";
	if (sizeof(aliases)) ret->aliases = aliases * " ";

	//Voice ID validity depends on the channel we're working with.
	if (state->voices[resp->voice]) ret->voice = resp->voice;

	if (sizeof(ret) == 1) return ret->message; //No flags? Just return the message.
	return ret;
}

array _validate_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string command, string chan);
	object channel = G->G->irc->channels["#" + chan]; if (!channel) return 0;
	mapping state = (["cmd": command, "cdanon": 0, "cooldowns": ([]), "voices": channel->config->voices || ([])]);
	if (command == "!!trigger") {
		echoable_message response = G->G->echocommands["!trigger#" + chan];
		response += ({ }); //Force array, and disconnect it for mutation's sake
		string id = msg->cmdname - "!";
		if (id == "") {
			//Blank command name? Create a new one.
			if (!sizeof(response)) id = "1";
			else id = (string)((int)response[-1]->id + 1);
		}
		else if (!(int)id) return 0; //Invalid ID
		state->cmd += "-" + id;
		echoable_message trigger = validate(msg->response, state);
		if (trigger != "") { //Empty string will cause a deletion
			if (!mappingp(trigger)) trigger = (["message": trigger]);
			trigger->id = id;
			m_delete(trigger, "otherwise"); //Triggers don't have an Else clause
		}
		if (msg->cmdname == "") response += ({trigger});
		else foreach (response; int i; mapping r) {
			if (r->id == id) {
				response[i] = trigger;
				break;
			}
		}
		response -= ({""});
		if (!sizeof(response)) response = ""; //No triggers left? Delete the special altogether.
		return ({"!trigger#" + chan, response});
	}
	if (command == "" || command == "!!") {
		string pfx = command[..0]; //"!" for specials, "" for normals
		if (!stringp(msg->cmdname)) return 0;
		sscanf(msg->cmdname, "%*[!]%s%*[#]%s", command, string c);
		if (c != "" && c != chan) return 0; //If you specify the command name as "!demo#rosuav", that's fine if and only if you're working with channel "#rosuav".
		command = String.trim(lower_case(command));
		if (command == "") return 0;
		state->cmd = command = pfx + command;
		if (pfx == "!" && !function_object(G->G->commands->addcmd)->SPECIAL_NAMES[command]) command = 0; //Only specific specials are valid
	}
	if (command) command += "#" + chan; //Potentially getting us right back to conn->group, but more likely the group is just the channel
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic.
	return ({command, validate(msg->response, state), state});
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg);
	if (!valid || !valid[0]) return;
	if (valid[1] != "") {
		make_echocommand(@valid);
		if (msg->cmdname == "" && has_prefix(conn->group, "!!trigger#")) {
			//Newly added command. The client needs to know the ID so it can pop it up.
			conn->sock->send_text(Standards.JSON.encode((["cmd": "newtrigger", "response": valid[1][-1]])));
		}
	}
	//Else message failed validation. TODO: Send a response on the socket.
}
void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg | (["response": ""]));
	if (!valid || !valid[0]) return;
	if (valid[1] == "") make_echocommand(valid[0], 0);
	else if (has_prefix(conn->group, "!!trigger#")) make_echocommand(@valid);
	//Else something went wrong. Does it need a response?
}
void websocket_cmd_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, (["cmdname": "validateme"]) | msg);
	if (!valid) return; //But it's okay if the name is invalid.
	string cmdname = ((valid[0] || msg->cmdname) / "#")[0];
	conn->sock->send_text(Standards.JSON.encode((["cmd": "validated", "cmdname": cmdname, "response": valid[1]]), 4));
}

protected void create(string name) {::create(name); call_out(find_builtins, 0);}
