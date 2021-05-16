inherit http_endpoint;
inherit websocket_handler;

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
		"message": "/me devicatHug $$ warmly hugs everyone maayaHug",
		"otherwise": "/me devicatHug $$ warmly hugs %s maayaHug",
	]),
]);

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array templates = ({ });
	mapping complex_templates = COMPLEX_TEMPLATES | ([]);
	multiset seen = (<>);
	mapping(string:mapping(string:string)) builtins = ([]);
	foreach (sort(indices(G->G->builtins)), string name) {
		object handler = G->G->builtins[name];
		if (seen[handler]) continue; seen[handler] = 1; //If there are multiple, keep the alphabetically-earliest.
		templates += ({sprintf("!%s | %s", name, handler->command_description)});
		complex_templates["!" + name] = ([
			"dest": "/builtin", "target": "!" + name + " %s",
			//"builtin": name, "builtin_param": "%s",
			"access": handler->require_moderator ? "mod" : handler->access,
			"message": handler->default_response,
			"aliases": handler->aliases * " ",
		]);
		builtins[name] = (["": handler->builtin_description]) | handler->vars_provided;
		if (builtins[name][""] == "") builtins[name][""] = handler->command_description;
	}
	if (req->misc->is_mod) {
		return render_template("chan_commands.md", ([
			"vars": (["ws_type": "chan_commands", "ws_group": req->misc->channel->name,
				"complex_templates": complex_templates, "builtins": builtins]),
			"templates": templates * "\n",
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
	return render_template("chan_commands.md", ([
		"user text": user,
		"commands": commands * "\n",
		"templates": templates * "\n",
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->session || !conn->session->user) return "Not logged in";
	sscanf(msg->group, "%s#%s", string command, string chan);
	object channel = G->G->irc->channels["#" + chan];
	if (!channel) return "Bad channel";
	if (!channel->mods[conn->session->user->login]) return "Not logged in"; //Most likely this will result from some other issue, but whatever
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
	"dest": (<"/w", "/web", "/set", "/builtin">),
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
	else if (resp->dest && has_prefix(resp->dest, "/"))
	{
		//Legacy mode. Fracture the dest into dest and target.
		sscanf(resp->dest, "/%[a-z] %[a-zA-Z$%]%s", string dest, string target, string empty);
		if ((<"w", "web", "set">)[dest] && target != "" && empty == "")
			[ret->dest, ret->target] = ({"/" + dest, target});
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

	if (sizeof(ret) == 1) return ret->message; //No flags? Just return the message.
	return ret;
}

array _validate_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string command, string chan);
	if (!G->G->irc->channels["#" + chan]) return 0;
	mapping state = (["cmd": command, "cdanon": 0, "cooldowns": ([])]);
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
		if (pfx == "!" && !function_object(G->G->commands->addcmd)->SPECIAL_NAMES[command]) return 0; //Only specific specials are valid
	}
	command += "#" + chan; //Potentially getting us right back to conn->group, but more likely the group is just the channel
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic.
	return ({command, validate(msg->response, state), state});
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg);
	if (!valid) return;
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
	if (!valid) return;
	if (valid[1] == "") make_echocommand(valid[0], 0);
	else if (has_prefix(conn->group, "!!trigger#")) make_echocommand(@valid);
	//Else something went wrong. Does it need a response?
}
void websocket_cmd_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, (["cmdname": "validateme"]) | msg);
	if (!valid) return;
	sscanf(valid[0], "%s#", string cmdname);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "validated", "cmdname": cmdname, "response": valid[1]])));
}

protected void create(string name) {::create(name);}
