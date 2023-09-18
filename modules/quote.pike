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
constant builtin_param = ({"/Action/Get/Add/Delete", "Quote number (except Add)", "Text (for Add)"});
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
		"_description": "Quotes - View a chosen or random channel quote",
		"builtin": "quote", "builtin_param": ({"Get", "%s"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: Quote #{id}: {msg} [{game||uncategorized}, {timestamp|date_dmy}]",
			"otherwise": "@$$: {error}",
		]),
	]),
	"!delquote": ([
		"_description": "Quotes - Delete a channel quote",
		"builtin": "quote", "builtin_param": ({"Delete", "%s"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: Removed quote #{id}",
			"otherwise": "@$$: {error}",
		]),
	]),
	"!addquote": ([
		"_description": "Quotes - Add a channel quote",
		"builtin": "quote", "builtin_param": ({"Add", "", "{@emoted}"}),
		"message": ([
			"conditional": "string", "expr1": "{error}", "expr2": "",
			"message": "@$$: Added quote #{id}",
			"otherwise": "@$$: {error}",
		]),
	]),
]);

mapping message_params(object channel, mapping person, array param) {
	if (sizeof(param) < 2) param += ({"0"});
	if (sizeof(param) < 3) param += ({""});
	array quotes = channel->config->quotes || ({ });
	mapping chaninfo = G->G->channel_info[channel->name[1..]];
	if (!chaninfo) return (["{error}": "Internal error - no channel info"]); //I'm pretty sure this shouldn't happen
	int idx = (int)param[1];
	if (idx < 0 || idx > sizeof(quotes)) return (["{error}": "No such quote."]);
	switch (param[0]) {
		case "Add": {
			if (idx) return (["{error}": "Cannot add with a specific ID, sorry"]);
			if (sscanf(param[2], "%*[@]%s %s", string who, string what) && what && what != "") {
				if (lower_case(who) == channel->name[1..] || G_G_("participants", channel->name[1..])[lower_case(who)]) {
					//Seems to be a person's name at the start. Flip it to the end.
					//Note that this isn't perfect; if the person happens to not be in
					//the viewer list, the transformation won't work.
					if (what[0] == '\xFFFA') what = " " + what;
					if (what[-1] == '\xFFFB') what += " ";
					//We now have spaces guarding any emotes. (Note that we assume here that any
					//interlinear annotations represent emotes, ie that the FFFA is followed by
					//the letter "e". Currently the only other use of FFFA/FFFB in StilleBot is
					//user_text which is only seen during Markdown parsing.)
					param[2] = sprintf("\"%s\" -- %s", what, who);
				}
			}
			//TODO: Make use of the emoted text for the web site
			string text = param[2];
			while (sscanf(text, "%s\ufffae%*s:%s\ufffb%s", string before, string em, string after))
				text = before + em + after;
			channel->config->quotes += ({([
				"msg": text, "emoted": param[2],
				"game": chaninfo->game,
				"timestamp": time(),
				"recorder": person->user,
			])});
			idx = sizeof(quotes = channel->config->quotes);
			persist_config->save();
			//fallthrough
		}
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
