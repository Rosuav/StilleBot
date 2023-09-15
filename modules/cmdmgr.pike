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

constant builtin_description = "Manage channel commands";
constant builtin_name = "Command manager";
constant builtin_param = ({"/Action/Automate/Create/Delete", "Command name", "Time/message"});
constant vars_provided = ([
	"{error}": "Blank if all is well, otherwise an error message",
]);
constant command_suggestions = ([
	"!addcmd": ([
		"_description": "Commands - Create a simple command",
		"conditional": "regexp", "expr1":"^[!]([^ ]+) (.*)$", "expr2":"{param}",
		"message": ([
			"builtin": "cmdmgr", "builtin_param": ({"Create", "{regexp1}", "{regexp2}"}),
			"message": ([
				"conditional": "string", "expr1": "{error}", "expr2": "",
				"message": "@$$: {result}",
				"otherwise": "@$$: {error}",
			]),
		]),
		"otherwise": "@$$: Try !addcmd !newcmdname response-message",
	]),
	"!delcmd": ([
		"_description": "Commands - Delete a simple command",
		"builtin": "cmdmgr", "builtin_param": ({"Delete", "{param}"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: {result}",
			"otherwise": "@$$: {error}",
		]),
	]),
	"!repeat": ([
		"_description": "Commands - Automate a simple command",
		"builtin": "argsplit", "builtin_param": "{param}",
		"message": ([
			"builtin": "cmdmgr", "builtin_param": ({"Automate", "{arg2}", "{arg1}"}),
			"message": ([
				"conditional": "string", "expr1": "{error}", "expr2": "",
				"message": "@$$: {result}",
				"otherwise": "@$$: {error}",
			]),
		]),
	]),
	"!unrepeat": ([
		"_description": "Commands - Cancel automation of a command",
		"builtin": "cmdmgr", "builtin_param": ({"Automate", "{param}", "-1"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: {result}",
			"otherwise": "@$$: {error}",
		]),
	]),
]);

mapping message_params(object channel, mapping person, array|string param) {
	if (!arrayp(param)) param /= " ";
	if (sizeof(param) < 2) return (["{error}": "Not enough args"]); //Won't happen if you use the GUI editor normally
	switch (param[0]) {
		case "Automate": {
			if (sizeof(param) < 3) return (["{error}": "Not enough args"]);
			array(int) mins;
			string msg = param[1] - "!";
			if (sscanf(param[2], "%d:%d", int hr, int min) == 2)
				mins = ({hr, min, 1}); //Scheduled at hh:mm
			else if (sscanf(param[2], "%d-%d", int min, int max) == 2)
				mins = ({min, max, 0}); //Repeated between X and Y minutes
			else if (int m = (int)param[2])
				mins = ({m, m, 0}); //Repeated exactly every X minutes
			if (!mins) return (["{error}": "Unrecognized time delay format"]);
			echoable_message command = channel->commands[msg];
			if (mins[0] < 0) {
				if (!mappingp(command) || !command->automate) return (["{error}": "That message wasn't being repeated, and can't be cancelled"]);
				//Copy the command, remove the automation, and do a standard validation
				G->G->update_command(channel, "", msg, command - (<"automate">));
				return (["{error}": "", "{result}": "Command will no longer be run automatically."]);
			}
			if (!command) return (["{error}": "Command not found"]);
			switch (mins[2])
			{
				case 0:
					if (mins[0] < 5) return (["{error}": "Minimum five-minute repeat cycle. You should probably keep to a minimum of 20 mins."]);
					if (mins[1] < mins[0]) return (["{error}": "Maximum period must be at least the minimum period."]);
					break;
				case 1:
					if (mins[0] < 0 || mins[0] >= 24 || mins[1] < 0 || mins[1] >= 60)
						return (["{error}": "Time must be specified as hh:mm (in your local timezone)."]);
					break;
				default: return (["{error}": "Huh?"]); //Shouldn't happen
			}
			if (!mappingp(command)) command = (["message": command]);
			G->G->update_command(channel, "", msg, command | (["automate": mins]));
			return (["{error}": "", "{result}": "Command will now be run automatically."]);
		}
		case "Create": {
			if (sizeof(param) < 3) return (["{error}": "Not enough args"]);
			string cmd = command_casefold(param[1]);
			if (!function_object(make_echocommand)->SPECIAL_NAMES[cmd] && has_value(cmd, '!')) return (["{error}": "Command names cannot include exclamation marks"]);
			string newornot = channel->commands[cmd] ? "Updated" : "Created new";
			make_echocommand(cmd + channel->name, param[2..] * " ");
			return (["{error}": "", "{result}": sprintf("%s command !%s", newornot, cmd)]);
		}
		case "Delete": {
			string cmd = command_casefold(param[1]);
			if (!channel->commands[cmd]) return (["{error}": "No echo command with that name exists here."]);
			make_echocommand(cmd + channel->name, 0);
			return (["{error}": "", "{result}": sprintf("Deleted command !%s", cmd)]);
		}
		default: return (["{error}": "Unknown subcommand"]);
	}
}

protected void create(string name) {
	::create(name);
	register_bouncer(autospam);
	foreach (list_channel_configs(), mapping cfg) if (cfg->login)
		if (G->G->stream_online_since[cfg->login]) connected(cfg->login);
}
