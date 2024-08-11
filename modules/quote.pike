inherit builtin_command;

constant builtin_description = "View and manage channel quotes";
constant builtin_name = "Quotes";
constant builtin_param = ({"/Action/Get/Add/Delete", "Quote number (except Add)", "Text (for Add)"});
constant vars_provided = ([
	"{id}": "ID of the selected quote",
	"{msg}": "Text of the quote",
	"{game}": "Current category when the quote was recorded",
	"{timestamp}": "When the quote was recorded (use hms for formatting)",
	"{recorder}": "Person who recorded the quote",
]);
constant command_suggestions = ([
	"!quote": ([
		"_description": "Quotes - View a chosen or random channel quote",
		"conditional": "catch",
		"message": ([
			"builtin": "quote", "builtin_param": ({"Get", "%s"}),
			"message": "@$$: Quote #{id}: {msg} [{game||uncategorized}, {timestamp|date_dmy}]",
		]),
		"otherwise": "@$$: {error}",
	]),
	"!delquote": ([
		"_description": "Quotes - Delete a channel quote",
		"access": "mod",
		"conditional": "catch",
		"message": ([
			"builtin": "quote", "builtin_param": ({"Delete", "%s"}),
			"message": "@$$: Removed quote #{id}",
		]),
		"otherwise": "@$$: {error}",
	]),
	"!addquote": ([
		"_description": "Quotes - Add a channel quote",
		"access": "mod",
		"conditional": "catch",
		"message": ([
			"builtin": "quote", "builtin_param": ({"Add", "", "{@emoted}"}),
			"message": "@$$: Added quote #{id}",
		]),
		"otherwise": "@$$: {error}",
	]),
]);

__async__ mapping message_params(object channel, mapping person, array param) {
	if (sizeof(param) < 2) param += ({"0"});
	if (sizeof(param) < 3) param += ({""});
	array quotes = await(G->G->DB->load_config(channel->userid, "quotes", ({ })));
	int idx = (int)param[1];
	if (idx < 0 || idx > sizeof(quotes)) error("No such quote.\n");
	mapping chaninfo = ([]); catch {chaninfo = await(get_channel_info(channel->login));}; //If we can't query, don't worry about it.
	switch (param[0]) {
		case "Add": {
			if (idx) error("Cannot add with a specific ID, sorry\n");
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
			quotes += ({([
				"msg": text, "emoted": param[2],
				"game": chaninfo->game || "something",
				"timestamp": time(),
				"recorder": person->user,
			])});
			idx = sizeof(quotes);
			await(G->G->DB->save_config(channel->userid, "quotes", quotes));
			//fallthrough
		}
		case "Get": {
			if (!idx) {
				if (!sizeof(quotes)) error("No quotes recorded.\n");
				idx = random(sizeof(quotes)) + 1;
			}
			mapping quote = quotes[idx-1];
			return ([
				"{id}": (string)idx, "{msg}": quote->msg, "{game}": quote->game || "",
				"{timestamp}": (string)quote->timestamp, "{recorder}": quote->recorder || "",
			]);
		}
		case "Delete": {
			if (!idx) error("No such quote.\n");
			quotes[idx - 1] = 0; quotes -= ({0});
			await(G->G->DB->save_config(channel->userid, "quotes", quotes));
			return (["{id}": (string)idx]);
		}
		default: break;
	}
	error("Unknown subcommand, check configuration\n"); //Won't happen if you use the GUI command editor normally
}
