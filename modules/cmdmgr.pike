//Command manager
//Handles autocommands (repeat/automate), and the adding and removing of commands
//TODO: Migrate functionality from chan_commands into here eg validation and updating
inherit hook;
inherit annotated;
inherit builtin_command;
@retain: mapping autocommands = ([]);

//Convert a number of minutes into a somewhat randomized number of seconds
//Assumes a span of +/- 1 minute if not explicitly given
int seconds(int|array mins, string timezone) {
	if (!arrayp(mins)) mins = ({mins-1, mins+1, 0}); //Ancient compatibility mode. Shouldn't ever happen now.
	if (sizeof(mins) == 2) mins += ({0});
	switch (mins[2])
	{
		case 0: //Scheduled between X and Y minutes
			return mins[0] * 60 + random((mins[1]-mins[0]) * 60);
		case 1: //Scheduled at hh:mm in the user's timezone
		{
			//werror("Scheduling at %02d:%02d in %s\n", mins[0], mins[1], timezone);
			if (!timezone || timezone == "") timezone = "UTC";
			object now = Calendar.Gregorian.Second()->set_timezone(timezone);
			int target = mins[0] * 3600 + mins[1] * 60;
			target -= now->hour_no() * 3600 + now->minute_no() * 60 + now->second_no();
			if (target <= 0) target += 86400;
			return target;
		}
		default: return 86400; //Probably a bug somewhere.
	}
}

void autospam(string channel, string msg) {
	if (function f = bounce(this_function)) return f(channel, msg);
	if (!G->G->stream_online_since[channel[1..]]) return;
	mapping cfg = get_channel_config(channel[1..]);
	if (!cfg) return; //Channel no longer configured
	echoable_message response = cfg->commands[?msg[1..]];
	int|array(int) mins = mappingp(response) && response->automate;
	if (!mins) return; //Autocommand disabled
	G->G->autocommands[msg[1..] + channel] = call_out(autospam, seconds(mins, cfg->timezone), channel, msg);
	if (response) msg = response;
	string me = persist_config["ircsettings"]->nick;
	G->G->irc->channels[channel]->send((["nick": me, "user": me]), msg);
}

@hook_channel_online: int connected(string channel) {
	mapping cfg = get_channel_config(channel); if (!cfg) return 0;
	foreach (cfg->commands || ([]); string cmd; echoable_message response) {
		if (!mappingp(response) || !response->automate) continue;
		mixed id = autocommands[cmd + "#" + channel];
		int next = id && find_call_out(id);
		if (undefinedp(next) || next > seconds(response->automate, cfg->timezone)) {
			if (next) remove_call_out(id); //If you used to have it run every 60 minutes, now every 15, cancel the current and retrigger.
			autocommands[cmd + "#" + channel] = call_out(autospam, seconds(response->automate, cfg->timezone), "#" + channel, "!" + cmd);
		}
	}
}

//Map a flag name to a set of valid values for it
//Blank or null is always allowed, and will result in no flag being set.
constant message_flags = ([
	"mode": (<"random", "rotate", "foreach">),
	"dest": (<"/w", "/web", "/set", "/chain", "/reply", "//">),
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
	"number": ({"expr1"}), //Yes, expr1 even though there's no others - means you still see it when you switch (in the classic editor)
	"spend": ({"expr1", "expr2"}), //Similarly, this uses the same names for the sake of the classic editor's switching.
	"cooldown": ({"cdname", "cdlength", "cdqueue"}),
	"catch": ({ }), //Currently there's no exception type hierarchy, so you always catch everything.
]);

string normalize_cooldown_name(string|int(0..0) cdname, mapping state) {
	sscanf(cdname || "", "%[*]%s", string per_user, string name);
	//Anonymous cooldowns get named for the back end, but the front end will blank this.
	//If the front end happens to return something with a dot name in it, ignore it.
	if (name == "" || name[0] == '.') name = sprintf(".%s:%d", state->cmd, ++state->cdanon);
	return per_user + name;
}

//state array is for purely-linear state that continues past subtrees
echoable_message _validate_recursive(echoable_message resp, mapping state)
{
	//Filter the response to only that which is valid
	if (stringp(resp)) return resp;
	if (arrayp(resp)) switch (sizeof(resp))
	{
		case 0: return ""; //This should be dealt with at a higher level (and suppressed).
		case 1: return _validate_recursive(resp[0], state); //Collapse single element arrays to their sole element
		default: return _validate_recursive(resp[*], state) - ({""}); //Suppress any empty entries
	}
	if (!mappingp(resp)) return ""; //Ensure that nulls become empty strings, for safety and UI simplicity.
	mapping ret = (["message": _validate_recursive(resp->message, state)]);
	//Whitelist the valid flags. Note that this will quietly suppress any empty
	//strings, which would be stating the default behaviour.
	foreach (message_flags; string flag; multiset ok)
	{
		if (ok[resp[flag]]) ret[flag] = resp[flag];
	}
	if (ret->dest == "//") {
		//Comments begin with a double slash. Whodathunk?
		//They're not allowed to have anything else though, just the message.
		//The message itself won't be processed in any way, and could actually
		//contain other, more complex, content, but as long as it's syntactically
		//valid, nothing will be done with it.
		return ret & (<"dest", "message">);
	}
	if (ret->dest) {
		//If there's any dest other than "" (aka "open chat") or "//", it should
		//have a target. Failing to have a target breaks other destinations,
		//so remove that if this is missing; otherwise, any target works.
		if (!resp->target) m_delete(ret, "dest");
		else ret->target = resp->target;
		if (ret->dest == "/chain") {
			//Command chaining gets extra validation done. You may ONLY chain to
			//commands from the current channel; but you may enter them with
			//or without their leading exclamation marks.
			string cmd = (ret->target || "") - "!";
			if (state->channel && !state->channel->commands[cmd])
				//Attempting to chain to something that doesn't exist is invalid.
				//TODO: Accept it if it's recursion (or maybe have a separate "chain
				//to self" notation) to allow a new recursive command to be saved.
				return "";
			ret->target = cmd;
		}
		//Variable names containing these characters would be unable to be correctly output
		//in any command, due to the way variable substitution is processed.
		if (ret->dest == "/set") ret->target = replace(ret->target, "|${}" / 1, "");
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
		//but for now, any array of strings will be accepted.
		else if (arrayp(resp->builtin_param) && sizeof(resp->builtin_param)
			&& !has_value(stringp(resp->builtin_param[*]), 0))
				ret->builtin_param = resp->builtin_param;
	}
	//Conditions have their own active ingredients.
	if (array parts = condition_parts[resp->conditional]) {
		foreach (parts + ({"conditional"}), string key)
			if (resp[key]) ret[key] = resp[key];
		ret->otherwise = _validate_recursive(resp->otherwise, state);
		if (ret->message == "" && ret->otherwise == "") return ""; //Conditionals can omit either message or otherwise, but not both
		if (ret->casefold == "") m_delete(ret, "casefold"); //Blank means not case folded, so omit it
		if (ret->conditional == "cooldown") {
			ret->cdname = normalize_cooldown_name(ret->cdname, state);
			ret->cdlength = (int)ret->cdlength;
			if (ret->cdlength) state->cooldowns[ret->cdname] = ret->cdlength;
			else m_delete(ret, (({"conditional", "otherwise"}) + parts)[*]); //Not a valid cooldown.
			//TODO: Keyword-synchronized cooldowns should synchronize their cdlengths too
		}
	}
	else if (ret->message == "" && (<0, "/web", "/w", "/reply">)[ret->dest] && !ret->builtin) {
		//No message? Nothing to do, if a standard destination. Destinations like
		//"set variable" are perfectly happy to accept blank messages, and builtins
		//can be used for their side effects only. Note that it's up to the command
		//designer to know whether this is meaningful or not (Arg Split with no
		//content isn't very helpful, but Log absolutely would be).
		return "";
	}
	//Delays are integer seconds. We'll permit a string of digits, since that might be
	//easier for the front end.
	if (resp->delay && resp->delay != "0" &&
			(intp(resp->delay) || (sscanf((string)resp->delay, "%[0-9]", string d) && d == resp->delay)))
		ret->delay = (int)resp->delay;

	if (ret->mode == "rotate") {
		//Anonymous rotations, like anonymous cooldowns, get named for the back end only.
		//In this case, though, it also creates a variable. For simplicity, reuse cdanon.
		ret->rotatename = normalize_cooldown_name(resp->rotatename, state);
	}
	//Iteration can be done on all-in-chat or all-who've-chatted.
	if (int timeout = ret->mode == "foreach" && (int)resp->participant_activity)
		ret->participant_activity = timeout;

	//Voice ID validity depends on the channel we're working with. A syntax-only check will
	//accept any voice ID as long as it's a string of digits.
	if (!state->channel) {
		if (resp->voice && sscanf(resp->voice, "%[0-9]%s", string v, string end) && v != "" && end == "") ret->voice = v;
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
echoable_message _validate_toplevel(echoable_message resp, mapping state)
{
	mixed ret = _validate_recursive(resp, state);
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
	if (sizeof(aliases)) ret->aliases = command_casefold(aliases * " ");

	//Automation comes in a couple of strict forms; anything else gets dropped.
	//Very very basic validation is done (no zero-minute automation) but otherwise, stupid stuff is
	//fine; I'm not going to stop you from setting a command to run every 1048576 minutes.
	if (stringp(resp->automate)) {
		if (sscanf(resp->automate, "%d:%d", int hr, int min) == 2) ret->automate = ({hr, min, 1});
		else if (sscanf(resp->automate, "%d-%d", int min, int max) && min >= 0 && max >= min && max > 0) ret->automate = ({min, max, 0});
		else if (sscanf(resp->automate, "%d", int minmax) && minmax > 0) ret->automate = ({minmax, minmax, 0});
		//Else don't set ret->automate.
	} else if (arrayp(resp->automate) && sizeof(resp->automate) == 3 && min(@resp->automate) >= 0 && max(@resp->automate) > 0 && resp->automate[2] <= 1)
		ret->automate = resp->automate;

	//TODO: Ensure that the reward still exists
	if (stringp(resp->redemption) && resp->redemption != "") ret->redemption = resp->redemption;

	return sizeof(ret) == 1 ? ret->message : ret;
}

//mode is "" for regular commands, "!!" for specials, "!!trigger" for triggers.
array validate_command(object channel, string|zero mode, string cmdname, echoable_message response, string|void original) {
	mapping state = (["cdanon": 0, "cooldowns": ([]), "channel": channel]);
	switch (mode) {
		case "!!trigger": {
			echoable_message alltrig = channel->commands["!trigger"];
			alltrig += ({ }); //Force array, and disconnect it for mutation's sake
			string id = cmdname - "!";
			if (id == "") {
				//Blank command name? Create a new one.
				if (!sizeof(alltrig)) id = "1";
				else id = (string)((int)alltrig[-1]->id + 1);
			}
			else if (id == "validateme" || has_prefix(id, "changetab_"))
				return ({0, _validate_toplevel(response, state)}); //Validate-only and ignore preexisting triggers
			else if (!(int)id) return 0; //Invalid ID
			state->cmd = "!!trigger-" + id;
			echoable_message trigger = _validate_toplevel(response, state);
			if (trigger != "") { //Empty string will cause a deletion
				if (!mappingp(trigger)) trigger = (["message": trigger]);
				trigger->id = id;
				m_delete(trigger, "otherwise"); //Triggers don't have an Else clause
			}
			if (cmdname == "") alltrig += ({trigger});
			else foreach ([array]alltrig; int i; mapping r) {
				if (r->id == id) {
					alltrig[i] = trigger;
					break;
				}
			}
			alltrig -= ({""});
			if (!sizeof(alltrig)) alltrig = ""; //No triggers left? Delete the special altogether.
			return ({"!trigger" + channel->name, alltrig, state});
		}
		case "": case "!!": {
			string pfx = mode[..0]; //"!" for specials, "" for normals
			if (!stringp(cmdname)) return 0;
			sscanf(cmdname, "%*[!]%s%*[#]%s", string|zero command, string c);
			if (c != "" && c != channel->name[1..]) return 0; //If you specify the command name as "!demo#rosuav", that's fine if and only if you're working with channel "#rosuav".
			command = String.trim(lower_case(command));
			if (command == "") return 0;
			state->cmd = command = pfx + command;
			if (pfx == "!" && !function_object(make_echocommand)->SPECIAL_NAMES[command]) command = 0; //Only specific specials are valid
			if (pfx == "") {
				//See if an original name was provided
				sscanf(original || "", "%*[!]%s%*[#]", string orig);
				orig = String.trim(lower_case(orig));
				if (orig != "") state->original = orig + channel->name;
			}
			//Validate the message. Note that there will be some things not caught by this
			//(eg trying to set access or visibility deep within the response), but they
			//will be merely useless, not problematic.
			return ({command + channel->name, _validate_toplevel(response, state), state});
		}
		default: return 0; //Internal error, shouldn't happen
	}
}

//Validate and update. TODO: Move make_echocommand into here as _save_echocommand, and
//use this helper for all external updates.
void update_command(object channel, string command, string cmdname, echoable_message response, string|void original) {
	array valid = validate_command(channel, command, cmdname, response, original);
	if (valid) make_echocommand(@valid);
}

constant builtin_description = "Manage channel commands";
constant builtin_name = "Command manager";
constant builtin_param = ({"/Action/Automate/Create/Delete", "Command name", "Time/message"});
constant vars_provided = ([]);
constant command_suggestions = ([
	"!addcmd": ([
		"_description": "Commands - Create a simple command",
		"conditional": "regexp", "expr1": "^[!]*([^ ]+) (.*)$", "expr2": "{param}",
		"message": ([
			"conditional": "catch",
			"message": ([
				"builtin": "cmdmgr", "builtin_param": ({"Create", "{regexp1}", "{regexp2}"}),
				"message": "@$$: {result}",
			]),
			"otherwise": "@$$: {error}",
		]),
		"otherwise": "@$$: Try !addcmd !newcmdname response-message",
	]),
	"!delcmd": ([
		"_description": "Commands - Delete a simple command",
		"conditional": "catch",
		"message": ([
			"builtin": "cmdmgr", "builtin_param": ({"Delete", "{param}"}),
			"message": "@$$: {result}",
		]),
		"otherwise": "@$$: {error}",
	]),
	"!repeat": ([
		"_description": "Commands - Automate a simple command",
		"builtin": "argsplit", "builtin_param": "{param}",
		"message": ([
			"conditional": "catch",
			"message": ([
				"builtin": "cmdmgr", "builtin_param": ({"Automate", "{arg2}", "{arg1}"}),
				"message": "@$$: {result}",
			]),
			"otherwise": "@$$: {error}",
		]),
	]),
	"!unrepeat": ([
		"_description": "Commands - Cancel automation of a command",
		"conditional": "catch",
		"message": ([
			"builtin": "cmdmgr", "builtin_param": ({"Automate", "{param}", "-1"}),
			"message": "@$$: {result}",
		]),
		"otherwise": "@$$: {error}",
	]),
]);

mapping message_params(object channel, mapping person, array param) {
	if (sizeof(param) < 2) error("Not enough args\n"); //Won't happen if you use the GUI editor normally
	switch (param[0]) {
		case "Automate": {
			if (sizeof(param) < 3) error("Not enough args\n");
			array(int) mins;
			string msg = param[1] - "!";
			if (sscanf(param[2], "%d:%d", int hr, int min) == 2)
				mins = ({hr, min, 1}); //Scheduled at hh:mm
			else if (sscanf(param[2], "%d-%d", int min, int max) == 2)
				mins = ({min, max, 0}); //Repeated between X and Y minutes
			else if (int m = (int)param[2])
				mins = ({m, m, 0}); //Repeated exactly every X minutes
			if (!mins) error("Unrecognized time delay format\n");
			echoable_message command = channel->commands[msg];
			if (mins[0] < 0) {
				if (!mappingp(command) || !command->automate) error("That message wasn't being repeated, and can't be cancelled\n");
				//Copy the command, remove the automation, and do a standard validation
				G->G->update_command(channel, "", msg, command - (<"automate">));
				return (["{result}": "Command will no longer be run automatically."]);
			}
			if (!command) error("Command not found\n");
			switch (mins[2])
			{
				case 0:
					if (mins[0] < 5) error("Minimum five-minute repeat cycle. You should probably keep to a minimum of 20 mins.\n");
					if (mins[1] < mins[0]) error("Maximum period must be at least the minimum period.\n");
					break;
				case 1:
					if (mins[0] < 0 || mins[0] >= 24 || mins[1] < 0 || mins[1] >= 60)
						error("Time must be specified as hh:mm (in your local timezone).\n");
					break;
				default: error("Huh?\n"); //Shouldn't happen
			}
			if (!mappingp(command)) command = (["message": command]);
			G->G->update_command(channel, "", msg, command | (["automate": mins]));
			return (["{result}": "Command will now be run automatically."]);
		}
		case "Create": {
			if (sizeof(param) < 3) error("Not enough args\n");
			string cmd = command_casefold(param[1]);
			if (!function_object(make_echocommand)->SPECIAL_NAMES[cmd] && has_value(cmd, '!')) error("Command names cannot include exclamation marks\n");
			string newornot = channel->commands[cmd] ? "Updated" : "Created new";
			make_echocommand(cmd + channel->name, param[2..] * " ");
			return (["{result}": sprintf("%s command !%s", newornot, cmd)]);
		}
		case "Delete": {
			string cmd = command_casefold(param[1]);
			if (!channel->commands[cmd]) error("No echo command with that name exists here.\n");
			make_echocommand(cmd + channel->name, 0);
			return (["{result}": sprintf("Deleted command !%s", cmd)]);
		}
		default: error("Unknown subcommand\n");
	}
}

void scan_command(mapping state, echoable_message message) {
	if (arrayp(message)) scan_command(state, message[*]);
	if (!mappingp(message)) return;
	if (message->builtin && mappingp(message->message) && !message->conditional &&
		message->message->conditional == "string" && message->message->expr1 == "{error}" &&
			(!message->message->expr2 || message->message->expr2 == "")) {
		//We have a builtin, and inside it, something that's checking for errors.
		//It might be a simple "Handle Errors" or it might be more elaborate, but
		//either way, transform it.
		m_delete(message->message, ({"conditional", "expr1", "expr2"})[*]);
		message->otherwise = m_delete(message->message, "otherwise");
		if (message->message->builtin) {
			//It's a bit more complicated. Save ourselves some trouble and just
			//add a layer of indirection.
			message->message = (["message": message->message]);
		}
		message->message->builtin = m_delete(message, "builtin");
		message->message->builtin_param = m_delete(message, "builtin_param");
		message->conditional = "catch";
		state->changed = 1;
	}
	scan_command(state, message->message);
	scan_command(state, message->otherwise);
}

protected void create(string name) {
	::create(name);
	G->G->cmdmgr = this;
	G->G->update_command = update_command; //Deprecated alias for G->G->cmdmgr->update_command
	register_bouncer(autospam);
	foreach (list_channel_configs(), mapping cfg) if (cfg->login)
		if (G->G->stream_online_since[cfg->login]) connected(cfg->login);
	//Look for any lingering aliases, which shouldn't be stored in channel configs
	foreach (list_channel_configs(), mapping cfg) if (cfg->commands) {
		foreach (cfg->commands; string cmd; echoable_message message)
			if (mappingp(message) && message->alias_of) {
				echoable_message of = cfg->commands[message->alias_of];
				if (mappingp(of) && of->aliases && has_value(of->aliases / " ", cmd)) {
					werror("LINGERING ALIAS: %O %O %O\n", cfg->login, cmd, message->alias_of);
					make_echocommand(cmd + "#" + cfg->login, 0); //It's not a problem, just delete it.
					make_echocommand(message->alias_of + "#" + cfg->login, of); //Force recreation of the underlying command
				}
				//Colliding aliases are a major problem. Fix them manually; no automated fix exists.
				else if (of) werror("COLLIDING ALIAS: %O %O %O\n", cfg->login, cmd, message->alias_of);
				else {
					//If the alias is just dangling, it's actually still functional, but
					//can't be edited. Remove the alias marker and allow it to stand alone.
					werror("DANGLING ALIAS: %O %O %O\n", cfg->login, cmd, message);
					m_delete(message, "alias_of");
					make_echocommand(cmd + "#" + cfg->login, message);
				}
			}
	}
	//Look for old-style error handling
	foreach (list_channel_configs(), mapping cfg) if (cfg->commands) {
		foreach (cfg->commands; string cmd; echoable_message message) {
			if (mappingp(message) && message->alias_of) continue;
			mapping state = (["changed": 0]);
			scan_command(state, message);
			if (state->changed) {
				werror("CHANGED: %O %O\n", cfg->login, cmd);
				make_echocommand(cmd + "#" + cfg->login, message);
			}
		}
	}
}
