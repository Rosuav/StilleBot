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
	
constant ENABLEABLE_FEATURES = ([
	"song": ([
		"description": "A !song command to show the currently-playing song (see VLC integration)",
		"fragment": "#song/",
	]),
]);

int can_manage_feature(object channel, string kwd) {return G->G->echocommands[kwd + channel->name] ? 2 : 1;} //Should it check if it's the right thing, and if not, return 3?

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	//Hack: Call on the normal commands updater to add a trigger
	if (!state)
		websocket_cmd_delete(
			(["group": channel->name, "session": ([])]),
			(["cmdname": kwd])
		);
	else
		websocket_cmd_update(
			(["group": channel->name, "session": ([])]),
			(["cmdname": kwd, "response": info->response || COMPLEX_TEMPLATES["!" + kwd]])
		);
}

//Gather all the variables that the JS command editor needs. Some may depend on the channel.
mapping(string:mixed) command_editor_vars(object channel) {
	mapping voices = channel->config->voices || ([]);
	string defvoice = channel->config->defvoice;
	if (voices[defvoice]) voices |= (["0": (["name": "Bot's own voice"])]); //TODO: Give the bot's username?
	return ([
		"complex_templates": G->G->commands_complex_templates,
		"builtins": G->G->commands_builtins,
		"pointsrewards": G->G->pointsrewards[channel->name[1..]] || ({ }),
		"voices": voices,
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
		if (!body || !mappingp(body) || !body->msg) return (["error": 400]);
		return jsonify(_syntax_check(body->msg, body->cmdname), 7);
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
constant message_flags = ([
	"mode": (<"random", "rotate">),
	"dest": (<"/w", "/web", "/set", "/chain", "/reply">),
]);
//As above, but applying only to the top level of a command.
constant command_flags = ([
	"access": (<"mod", "vip", "none">),
	"visibility": (<"hidden">),
]);

constant condition_parts = ([
	"string": ({"expr1", "expr2", "casefold"}),
	"contains": ({"expr1", "expr2", "casefold"}),
	"regexp": ({"expr1", "expr2", "casefold"}),
	"number": ({"expr1"}), //Yes, expr1 even though there's no others - means you still see it when you switch
	"cooldown": ({"cdname", "cdlength"}),
]);

//state array is for purely-linear state that continues past subtrees
echoable_message _validate(echoable_message resp, mapping state)
{
	//Filter the response to only that which is valid
	if (stringp(resp)) return resp;
	if (arrayp(resp)) switch (sizeof(resp))
	{
		case 0: return ""; //This should be dealt with at a higher level (and suppressed).
		case 1: return _validate(resp[0], state); //Collapse single element arrays to their sole element
		default: return _validate(resp[*], state) - ({""}); //Suppress any empty entries
	}
	if (!mappingp(resp)) return ""; //Ensure that nulls become empty strings, for safety and UI simplicity.
	mapping ret = (["message": _validate(resp->message, state)]);
	//Whitelist the valid flags. Note that this will quietly suppress any empty
	//strings, which would be stating the default behaviour.
	foreach (message_flags; string flag; multiset ok)
	{
		if (ok[resp[flag]]) ret[flag] = resp[flag];
	}
	if (ret->dest) {
		//If there's any dest other than "" (aka "open chat"), it should
		//have a target. Failing to have a target breaks other destinations,
		//so remove that if this is missing; otherwise, any target works.
		if (!resp->target) m_delete(ret, "dest");
		else ret->target = resp->target;
		if (ret->dest == "/chain") {
			//Command chaining gets extra validation done. You may ONLY chain to
			//echocommands from the current channel; but you may enter them with
			//or without their leading exclamation marks.
			sscanf(ret->target || "", "%*[!]%s", string cmd);
			if (state->channel && !G->G->echocommands[cmd + state->channel->name])
				//Attempting to chain to something that doesn't exist is invalid.
				//TODO: Accept it if it's recursion (or maybe have a separate "chain
				//to self" notation) to allow a new recursive command to be saved.
				return "";
			ret->target = cmd;
		}
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
		//NOTE: In theory, a /web message's destcfg could represent an entire message subtree.
		//Currently only simple strings will pass validation though.
		//Note also that not all destcfgs are truly meaningful, but any string is valid and
		//will be saved.
		if (stringp(resp->destcfg) && resp->destcfg != "") ret->destcfg = resp->destcfg;
		else if (resp->action == "add") ret->destcfg = "add"; //Handle variable management in the old style
	}
	if (resp->builtin && G->G->builtins[resp->builtin]) {
		//Validated separately as the builtins aren't a constant
		ret->builtin = resp->builtin;
		//Simple string? Let the builtin itself handle it.
		if (stringp(resp->builtin_param) && resp->builtin_param != "") ret->builtin_param = resp->builtin_param;
		//Array of strings? Maybe we should validate the number of arguments (different per builtin),
		//but for now, any array will be accepted.
		else if (arrayp(resp->builtin_param) && sizeof(resp->builtin_param)
			&& !has_value(stringp(resp->builtin_param[*]), 0))
				ret->builtin_param = resp->builtin_param;
	}
	//Conditions have their own active ingredients.
	if (array parts = condition_parts[resp->conditional]) {
		foreach (parts + ({"conditional"}), string key)
			if (resp[key]) ret[key] = resp[key];
		ret->otherwise = _validate(resp->otherwise, state);
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
	else if (ret->message == "" && (!ret->dest || ret->dest == "/web" || ret->dest == "/w")) {
		//No message? Might be nothing to do. (Though if there's a special destination, it might be okay.)
		if (!ret->builtin) return "";
		//But if there's a builtin, assume that it could have side effects.
		ret->message = ([ //Synthesized "Handle Errors" element as per the GUI
			"conditional": "string",
			"expr1": "{error}",
			"message": "",
			"otherwise": "Unexpected error: {error}"
		]);
	}
	//Delays are integer seconds. We'll permit a string of digits, since that might be
	//easier for the front end.
	if (resp->delay && resp->delay != "0" &&
			(intp(resp->delay) || (sscanf((string)resp->delay, "%[0-9]", string d) && d == resp->delay)))
		ret->delay = (int)resp->delay;

	if (ret->mode == "rotate") {
		string name = resp->rotatename || "";
		//Anonymous rotations, like anonymous cooldowns, get named for the back end only.
		//In this case, though, it also creates a variable. For simplicity, reuse cdanon.
		if (name == "" || name[0] == '.') name = sprintf(".%s:%d", state->cmd, ++state->cdanon);
		ret->rotatename = name;
	}

	//Voice ID validity depends on the channel we're working with. A syntax-only check will
	//accept any voice ID as long as it's a string of digits.
	if (!state->channel) {
		if (sscanf(resp->voice||"", "%[0-9]%s", string v, string end) && v != "" && end == "") ret->voice = v;
	}
	else if ((state->channel->config->voices || ([]))[resp->voice]) ret->voice = resp->voice;
	//Setting voice to "0" resets to the global default, which is useful if there's a local default.
	else if (resp->voice == "0" && state->channel->config->defvoice) ret->voice = resp->voice;
	else if (resp->voice == "") {
		//Setting voice to blank means "use channel default". This is useful if,
		//and only if, you've already set it to a nondefault voice in this tree.
		//TODO: Track changes to voices and allow such a reset to default.
	}

	if (sizeof(ret) == 1) return ret->message; //No flags? Just return the message.
	return ret;
}
echoable_message validate(echoable_message resp, mapping state)
{
	mixed ret = _validate(resp, state);
	if (!mappingp(resp)) return ret; //There can't be any top-level flags if you start with a string or array
	if (!mappingp(ret)) ret = (["message": ret]);
	//If there are any top-level flags, apply them.
	//TODO: Only do this for commands, not specials or triggers.
	foreach (command_flags; string flag; multiset ok)
	{
		if (ok[resp[flag]]) ret[flag] = resp[flag];
	}

	//Aliases are blank-separated, and might be entered in the UI with bangs.
	//But internally, we'd rather have them without. (Also, trim off any junk.)
	array(string) aliases = (resp->aliases || "") / " ";
	foreach (aliases; int i; string a) sscanf(a, "%*[!]%s%*[#\n]", aliases[i]);
	aliases -= ({"", state->cmd}); //Disallow blank, or an alias pointing back to self (it'd be ignored anyway)
	if (sizeof(aliases)) ret->aliases = aliases * " ";

	//Automation comes in a couple of strict forms; anything else gets dropped.
	if (stringp(resp->automate)) {
		if (sscanf(resp->automate, "%d:%d", int hr, int min) == 2) ret->automate = ({hr, min, 1});
		else if (sscanf(resp->automate, "%d-%d", int min, int max) && min >= 0 && max >= min) ret->automate = ({min, max, 0});
		else if (sscanf(resp->automate, "%d", int minmax) && minmax >= 0) ret->automate = ({minmax, minmax, 0});
		//Else don't set ret->automate.
	} else if (arrayp(resp->automate) && sizeof(resp->automate) == 3 && min(@resp->automate) >= 0 && resp->automate[2] <= 1)
		ret->automate = resp->automate;

	//TODO: Ensure that the reward still exists
	if (stringp(resp->redemption) && resp->redemption != "") ret->redemption = resp->redemption;

	return sizeof(ret) == 1 ? ret->message : ret;
}

//Check a message for syntactic validity without any actual permissions
//The channel will be ignored and you don't have to be a mod (or even logged in).
//If cmdname == "!!trigger", will validate a trigger. Otherwise, will validate
//a command or special (they behave the same way). Returns 0 if the command fails
//validation entirely, otherwise returns the canonicalized version of it.
mapping(string:mixed) _syntax_check(mapping(string:mixed) msg, string|void cmdname) {
	mapping state = (["cmd": cmdname || "validateme", "cooldowns": ([])]); //No channel so full validation isn't done
	echoable_message result = validate(msg, state);
	if (cmdname == "!!trigger" && result != "") {
		if (!mappingp(result)) result = (["message": result]);
		m_delete(result, "otherwise"); //Triggers don't have an Else clause
		if (stringp(msg->id)) result->id = msg->id; //Triggers may have IDs, in which case we should keep them.
	}
	return result;
}

array _validate_command(object channel, string command, string cmdname, echoable_message response, string|void original) {
	mapping state = (["cmd": command, "cdanon": 0, "cooldowns": ([]), "channel": channel]);
	if (command == "!!trigger") {
		echoable_message alltrig = G->G->echocommands["!trigger" + channel->name];
		alltrig += ({ }); //Force array, and disconnect it for mutation's sake
		string id = cmdname - "!";
		if (id == "") {
			//Blank command name? Create a new one.
			if (!sizeof(alltrig)) id = "1";
			else id = (string)((int)alltrig[-1]->id + 1);
		}
		else if (id == "validateme" || has_prefix(id, "changetab_"))
			return ({0, validate(response, state)}); //Validate-only and ignore preexisting triggers
		else if (!(int)id) return 0; //Invalid ID
		state->cmd += "-" + id;
		echoable_message trigger = validate(response, state);
		if (trigger != "") { //Empty string will cause a deletion
			if (!mappingp(trigger)) trigger = (["message": trigger]);
			trigger->id = id;
			m_delete(trigger, "otherwise"); //Triggers don't have an Else clause
		}
		if (cmdname == "") alltrig += ({trigger});
		else foreach (alltrig; int i; mapping r) {
			if (r->id == id) {
				alltrig[i] = trigger;
				break;
			}
		}
		alltrig -= ({""});
		if (!sizeof(alltrig)) alltrig = ""; //No triggers left? Delete the special altogether.
		return ({"!trigger" + channel->name, alltrig});
	}
	if (command == "" || command == "!!") {
		string pfx = command[..0]; //"!" for specials, "" for normals
		if (!stringp(cmdname)) return 0;
		sscanf(cmdname, "%*[!]%s%*[#]%s", command, string c);
		if (c != "" && c != channel->name[1..]) return 0; //If you specify the command name as "!demo#rosuav", that's fine if and only if you're working with channel "#rosuav".
		command = String.trim(lower_case(command));
		if (command == "") return 0;
		state->cmd = command = pfx + command;
		if (pfx == "!" && !function_object(G->G->commands->addcmd)->SPECIAL_NAMES[command]) command = 0; //Only specific specials are valid
		if (pfx == "") {
			//See if an original name was provided
			sscanf(original || "", "%*[!]%s%*[#]", string orig);
			orig = String.trim(lower_case(orig));
			if (orig != "") state->original = orig + channel->name;
		}
	}
	if (command) command += channel->name; //Potentially getting us right back to conn->group, but more likely the group is just the channel
	//Validate the message. Note that there will be some things not caught by this
	//(eg trying to set access or visibility deep within the response), but they
	//will be merely useless, not problematic.
	return ({command, validate(response, state), state});
}

//TODO: Move this out of chan_commands along with everything it depends on.
//This function should not depend on anything web or websocket-specific.
//TODO: Remove the original parameter and have anything capable of renaming
//add it directly to state, so addcmd can purge old versions of a command.
void update_command(object channel, string command, string cmdname, echoable_message response, string|void original) {
	array valid = _validate_command(channel, command, cmdname, response, original);
	if (valid && valid[1] != "") make_echocommand(@valid);
}

array _validate_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string command, string chan);
	object channel = G->G->irc->channels["#" + chan]; if (!channel) return 0;
	//TODO: Fold command and msg->cmdname into a single parameter
	//Currently command is a mode-switch that handles group checks, which is
	//the job of this function, not _validate_command
	return _validate_command(channel, command, msg->cmdname, msg->response, msg->original);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array valid = _validate_update(conn, msg);
	if (!valid || !valid[0] || conn->session->?fake) return;
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
	if (!valid || !valid[0] || conn->session->fake) return;
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

protected void create(string name) {
	::create(name);
	call_out(find_builtins, 0);
	G->G->update_command = update_command; //TODO: Migrate this into addcmd.pike or somewhere
}
