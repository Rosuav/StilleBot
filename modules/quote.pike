inherit builtin_command;
constant docstring = #"
View a chosen or randomly-selected quote

Pick a random quote with `!quote`, or call up one in particular by giving its
reference number, such as `!quote 42`. Quotes are per-channel and any mod can
add more quotes, so when funny things happen, use the !addquote
command to save it for posterity!
";

constant builtin_description = "View and manage channel quotes";
constant builtin_name = "Quotes";
constant builtin_param = ({"/Action/Get/Add/Edit/Delete", "Quote number", "Text (add/edit)"});
constant vars_provided = ([
	"{error}": "Blank if all is well, otherwise an error message",
	"{id}": "ID of the selected quote",
	"{msg}": "Text of the quote",
	"{game}": "Current category when the quote was recorded",
	"{timestamp}": "When the quote was recorded (use hms for formatting)",
	"{recorder}": "Person who recorded the quote",
]);
constant command_suggestions = ([
	"!quote": ([
		"_description": "View a chosen or random channel quote",
		"builtin": "quote", "builtin_param": ({"Get", "%s"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: Quote #{id}: {msg} [{game||uncategorized}, {timestamp|date_dmy}]",
			"otherwise": "@$$: {error}",
		]),
	]),
	"!delquote": ([
		"_description": "Delete a channel quote",
		"builtin": "quote", "builtin_param": ({"Delete", "%s"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: Removed quote #{id}",
			"otherwise": "@$$: {error}",
		]),
	]),
]);

mapping message_params(object channel, mapping person, array|string param) {
	if (stringp(param)) {
		param /= " ";
		param = ({param[0], param[1], param[2..] * " "}); //Only split three parts off
	}
	if (sizeof(param) < 2) param += ({"0"});
	if (sizeof(param) < 3) param += ({""});
	array quotes = channel->config->quotes || ({ });
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return (["{error}": "Internal error - no channel info"]); //I'm pretty sure this shouldn't happen
	int idx = (int)param[1];
	if (idx < 0 || idx > sizeof(quotes)) return (["{error}": "No such quote."]);
	switch (param[0]) {
		case "Get": {
			if (!idx) {
				if (!sizeof(quotes)) return (["{error}": "No quotes recorded."]);
				idx = random(sizeof(quotes)) + 1;
			}
			mapping quote = quotes[idx-1];
			return ([
				"{error}": "",
				"{id}": (string)idx, "{msg}": quote->msg, "{game}": quote->game || "",
				"{timestamp}": (string)quote->timestamp, "{recorder}": quote->recorder || "",
			]);
		}
		case "Delete": {
			if (!idx) return (["{error}": "No such quote."]);
			quotes[idx - 1] = 0;
			channel->config->quotes -= ({0});
			persist_config->save();
			return (["{error}": "", "{id}": (string)idx]);
		}
		default: break;
	}
	return (["{error}": "Unknown subcommand, check configuration"]); //Won't happen if you use the GUI command editor normally
}
