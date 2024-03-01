//Command manager
//Handles autocommands (repeat/automate), and the adding and removing of commands
inherit hook;
inherit annotated;
inherit builtin_command;
@retain: mapping autocommands = ([]);

//Note: Each special with the same-named parameter is assumed to use it in the same way.
//It's good to maintain this for the sake of humans anyway, but also the display makes
//this assumption, and has only a single description for any given name.
constant SPECIALS = ({
	({"!follower", ({"Someone follows the channel", "The new follower", ""}), "Stream support"}),
	({"!sub", ({"Someone subscribes for the first time", "The subscriber", "tier, multimonth"}), "Stream support"}),
	({"!resub", ({"Someone announces a resubscription", "The subscriber", "tier, months, streak, multimonth, msg"}), "Stream support"}),
	({"!subgift", ({"Someone gives a sub", "The giver", "tier, months, streak, recipient, multimonth, from_subbomb"}), "Stream support"}),
	({"!subbomb", ({"Someone gives random subgifts", "The giver", "tier, gifts"}), "Stream support"}),
	({"!cheer", ({"Any bits are cheered (including anonymously)", "The cheerer", "bits, msg, msgid"}), "Stream support"}),
	({"!cheerbadge", ({"A viewer attains a new cheer badge", "The cheerer", "level"}), "Stream support"}),
	({"!raided", ({"Another broadcaster raided you", "The raiding broadcaster", "viewers"}), "Stream support"}),
	({"!charity", ({"Someone donates to the charity you're supporting", "The donor", "amount, msgid"}), "Stream support"}),
	//Do these need to move somewhere else? Also - check their provides, it may be added to soon.
	({"!hypetrain_begin", ({"A hype train just started!", "The broadcaster", "levelup"}), "Stream support"}),
	({"!hypetrain_progress", ({"Progress was made on a hype train", "The broadcaster", "levelup"}), "Stream support"}),
	({"!hypetrain_end", ({"A hype train just ended (successfully or unsuccessfully)", "The broadcaster", ""}), "Stream support"}),

	({"!channelonline", ({"The channel has recently gone online (started streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!channelsetup", ({"The channel is online and has recently changed its category/title/tags", "The broadcaster", "category, title, tag_names, ccls"}), "Status"}),
	({"!channeloffline", ({"The channel has recently gone offline (stopped streaming)", "The broadcaster", "uptime, uptime_hms, uptime_english"}), "Status"}),
	({"!musictrack", ({"A track just started playing (see VLC integration)", "VLC", "desc, blockpath, block, track, playing"}), "Status"}),
	({"!pollbegin", ({"A channel poll just began", "The broadcaster", "title, choices, points_per_vote, choice_N_title"}), "Status"}),
	({"!pollended", ({"A channel poll just ended", "The broadcaster", "title, choices, points_per_vote, choice_N_title, choice_N_votes, choice_N_pointsvotes, winner_title"}), "Status"}),
	({"!predictionlocked", ({"A channel prediction no longer accepts entries", "The broadcaster", "title, choices, choice_N_title, choice_N_users, choice_N_points, choice_N_top_M_user, choice_N_top_M_points_used"}), "Status"}),
	({"!predictionended", ({"A channel prediction just ended", "The broadcaster", "title, choices, choice_N_title, choice_N_users, choice_N_points, choice_N_top_M_user, choice_N_top_M_points_used, choice_N_top_M_points_won, winner_*, loser_*"}), "Status"}),
	//Should these go into some other category?
	({"!timeout", ({"A user got timed out or banned", "The victim", "ban_duration"}), "Status"}),
	({"!adbreak", ({"An ad just started on this channel", "The broadcaster", "length, is_automatic"}), "Status"}),

	({"!giveaway_started", ({"A giveaway just opened, and people can buy tickets", "The broadcaster", "title, duration, duration_hms, duration_english"}), "Giveaways"}),
	({"!giveaway_ticket", ({"Someone bought ticket(s) in the giveaway", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_toomany", ({"Ticket purchase attempt failed", "Ticket buyer", "title, tickets_bought, tickets_total, tickets_max"}), "Giveaways"}),
	({"!giveaway_closed", ({"The giveaway just closed; people can no longer buy tickets", "The broadcaster", "title, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_winner", ({"A giveaway winner has been chosen!", "The broadcaster", "title, winner_name, winner_tickets, tickets_total, entries_total"}), "Giveaways"}),
	({"!giveaway_ended", ({"The giveaway is fully concluded and all ticket purchases are nonrefundable.", "The broadcaster", "title, tickets_total, entries_total, giveaway_cancelled"}), "Giveaways"}),

	({"!kofi_dono", ({"Donation received on Ko-fi.", "The broadcaster", "amount, msg, from_name"}), "Ko-fi"}),
	({"!kofi_member", ({"New monthly membership on Ko-fi.", "The broadcaster", "amount, msg, from_name, tiername"}), "Ko-fi"}),
	({"!kofi_shop", ({"Shop sale on Ko-fi.", "The broadcaster", "amount, msg, from_name, shop_item_ids"}), "Ko-fi"}),
});
constant SPECIAL_NAMES = (multiset)SPECIALS[*][0];
constant SPECIAL_PARAMS = ({
	({"tier", "Subscription tier - 1, 2, or 3 (Prime subs show as tier 1)"}),
	({"months", "Cumulative months of subscription"}), //TODO: Check interaction with multimonth
	({"streak", "Consecutive months of subscription. If a sub is restarted after a delay, {months} continues, but {streak} resets."}),
	({"recipient", "Display name of the gift sub recipient"}),
	({"multimonth", "Number of consecutive months of subscription given"}),
	({"msg", "Any message included with the sub/cheer/dono (blank if none)"}),
	({"msgid", "UUID of the message, suitable for replies etc"}),
	({"from_subbomb", "1 if the gift was part of a sub bomb, 0 if not"}),
	({"gifts", "Number of randomly-assigned gifts. Can be 1."}),
	({"bits", "Total number of bits cheered in this message"}),
	({"level", "New badge level, eg 1000 if the 1K bits badge has just been attained"}),
	({"viewers", "Number of viewers arriving on the raid"}),
	({"uptime", "Stream broadcast duration - use {uptime|time_hms} or {uptime|time_english} for readable form"}),
	({"uptime_hms", "(deprecated) Equivalent to {uptime|time_hms}"}),
	({"uptime_english", "(deprecated) Equivalent to {uptime|time_english}"}),
	({"category", "English name of the game or category being streamed in"}),
	({"tag_names", "Stream tags eg '[English], [FamilyFriendly]' - should be searched case insensitively"}),
	({"ccls", "Content classification labels eg '[ProfanityVulgarity], [ViolentGraphic]'"}),
	({"track", "Name of the audio file that's currently playing"}),
	({"block", "Name of the section/album/block of tracks currently playing, if any"}),
	({"blockpath", "Full path to the current block"}),
	({"desc", "Human-readable description of what's playing (block and track names)"}),
	({"playing", "1 if music is playing, or 0 if paused, stopped, disconnected, etc"}),
	({"title", "Title of the stream or giveaway (eg the thing that can be won)"}),
	({"duration", "How long the giveaway will be open (seconds; 0 means open until explicitly closed)"}),
	({"duration_hms", "(deprecated) Equivalent to {duration|time_hms}"}),
	({"duration_english", "(deprecated) Equivalent to {duration|time_english}"}),
	({"tickets_bought", "Number of tickets just bought (or tried to)"}),
	({"tickets_total", "Total number of tickets bought"}),
	({"tickets_max", "Maximum number of tickets any single user may purchase"}),
	({"entries_total", "Total number of unique people who entered"}),
	({"winner_name", "Name of the person who won - blank if no tickets purchased"}),
	({"winner_tickets", "Number of tickets the winner had purchased"}),
	({"giveaway_cancelled", "1 if the giveaway was cancelled (refunding all tickets), 0 if not (normal ending)"}),
	({"amount", "Total amount given (with currency eg '3 USD')"}),
	({"from_name", "Name (possibly username) of the Ko-fi supporter. Not (necessarily) a Twitch username."}),
	({"shop_item_ids", "Blank-separated list of ten-digit hexadecimal item IDs bought."}),
	({"tiername", "Ko-fi subscription tier (if applicable)"}),
	({"choices", "Number of choices in the poll"}),
	({"points_per_vote", "Channel points to buy a vote (0 if not available)"}),
	({"choice_N_title", "For each N from 1 to {choices}, the title of the Nth choice"}),
	({"choice_N_votes", "The number of votes that the Nth choice received"}),
	({"choice_N_pointsvotes", "The number of votes bought for Nth choice with points"}),
	({"choice_N_users", "The number of users who selected this choice"}),
	({"choice_N_points", "The total number of points spent on this choice"}),
	({"winner_title", "The title of the choice that had the most votes"}),
	({"choice_N_top_M_user", "Name of the Mth top user for the Nth choice (1 = biggest spender)"}),
	({"choice_N_top_M_points_used", "Number of points the Mth user for the Nth choice spent"}),
	({"choice_N_top_M_points_won", "Number of points the Mth user for the Nth choice won (0 if lost)"}),
	({"winner_*", "Same as choice_N_* for N == {winner}"}),
	({"loser_*", "Same as choice_N_* for N != {winner} if there were precisely two options"}),
	({"ban_duration", "Number of seconds the person got timed out for, or 0 for ban"}),
	({"length", "How many seconds it will last for"}),
	({"is_automatic", "Whether it was triggered automatically rather than manually"}),
	({"levelup", "Level number the hype train just reached, or blank if it didn't"}),
});

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

void autospam(string|int chanid, string cmd) {
	if (function f = bounce(this_function)) return f(chanid, cmd);
	cmd -= "!"; //Compat with older parameter style
	if (stringp(chanid)) chanid = G->G->user_info[chanid - "#"]->id; //Compat with older param style
	if (!G->G->stream_online_since[chanid]) return;
	object channel = G->G->irc->id[chanid];
	if (!channel) return; //Channel no longer configured (TODO: handle channel deactivation)
	echoable_message response = channel->commands[?cmd];
	int|array(int) mins = mappingp(response) && response->automate;
	if (!mins) return; //Autocommand disabled
	autocommands[chanid + "!" + cmd] = call_out(autospam, seconds(mins, channel->config->timezone), chanid, cmd);
	string me = channel->config->display_name || channel->name[1..]; //If you use $$ in an autocommand, use the broadcaster's name.
	channel->send((["nick": me, "user": me]), response);
}

@hook_channel_online: int connected(string chan, int uptime, int chanid) {
	object channel = G->G->irc->id[chanid]; if (!channel) return 0;
	foreach (channel->commands || ([]); string cmd; echoable_message response) {
		if (!mappingp(response) || !response->automate) continue;
		mixed id = autocommands[chanid + "!" + cmd];
		int next = id && find_call_out(id);
		if (undefinedp(next) || next > seconds(response->automate, channel->config->timezone)) {
			if (next) remove_call_out(id); //If you used to have it run every 60 minutes, now every 15, cancel the current and retrigger.
			autocommands[chanid + "!" + cmd] = call_out(autospam, seconds(response->automate, channel->config->timezone), chanid, cmd);
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
	//For validation purposes, it's easier to retain existing names, since they don't matter to
	//runtime execution anyway. This helps with some round-trip testing.
	if (name != "" && state->retain_internal_names) return cdname;
	//Anonymous cooldowns get named for the back end, but the front end will blank this.
	//If the front end happens to return something with a dot name in it, ignore it.
	if (name == "" || name[0] == '.') name = sprintf(".%s:%d", state->cmd, ++state->cdanon);
	return per_user + name;
}

array|zero string_to_automation(string automate) {
	if (sscanf(automate, "%d:%d", int hr, int min) == 2) return ({hr, min, 1});
	else if (sscanf(automate, "%d-%d", int min, int max) && min >= 0 && max >= min && max > 0) return ({min, max, 0});
	else if (sscanf(automate, "%d", int minmax) && minmax > 0) return ({minmax, minmax, 0});
	//Else there's no valid automation, so return zero.
}
string automation_to_string(mixed val) {
	//NOTE: Keep this in sync with the same-named function in command_gui.js
	if (!val) return "";
	if (!arrayp(val)) {
		//Parse string to array, then parse array to string, thus ensuring canonicalization.
		int mode = has_value(val, ':');
		array m = val / (mode ? ":" : "-");
		if (sizeof(m) == 1) m += ({m[0]});
		val = ({(int)m[0], (int)m[1], mode});
	}
	int m1 = val[0], m2 = val[1], mode = sizeof(val) > 2 ? val[2] : 0;
	if (mode) return sprintf("%02d:%02d", m1, m2); //hr:min
	else if (m1 >= m2) return (string)m1; //min-min is the same as just min
	else return sprintf("%d-%d", m1, m2); //min-max
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
	if (object handler = resp->builtin && G->G->builtins[resp->builtin]) {
		//Validated separately as the builtins aren't a constant
		ret->builtin = resp->builtin;
		//Simple string? Split it into words according to the number of args the builtin expects.
		//Note that this might not always be correct (builtins can grow args in the future), but
		//it's a start. Note also that MustardScript commands can pass any number of args they
		//like to any builtin, so the number of them still has to be checked.
		if (stringp(resp->builtin_param) && resp->builtin_param != "") {
			if (!objectp(handler) || !arrayp(handler->builtin_param) || sizeof(handler->builtin_param) <= 1)
				ret->builtin_param = ({resp->builtin_param}); //Default to assuming that a single arg is fine.
			else {
				ret->builtin_param = Process.split_quoted_string(resp->builtin_param);
				//If the builtin is expecting 3 params, and the user provides more words
				//than that, join the remainder into a single string.
				int max = sizeof(handler->builtin_param);
				if (sizeof(ret->builtin_param) > max)
					ret->builtin_param = ret->builtin_param[..max - 2] + ({ret->builtin_param[max - 1..] * " "});
			}
		}
		//Array of strings is also valid, but array of anything else won't be.
		else if (arrayp(resp->builtin_param) && sizeof(resp->builtin_param)
			&& !has_value(stringp(resp->builtin_param[*]), 0)
			&& (sizeof(resp->builtin_param) > 1 || resp->builtin_param[0] != "")) //A single empty string can be omitted.
				ret->builtin_param = resp->builtin_param;
	}
	//Conditions have their own active ingredients.
	if (array parts = condition_parts[resp->conditional]) {
		foreach (parts + ({"conditional"}), string key)
			if (resp[key] && resp[key] != "") ret[key] = resp[key];
		ret->otherwise = _validate_recursive(resp->otherwise, state);
		if (ret->message == "" && ret->otherwise == "") return ""; //Conditionals can omit either message or otherwise, but not both
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
	//Delays are either integer seconds, or a string representing that delay. If it looks
	//like a string of digits, store it as an integer to save the execution some work.
	if (resp->delay && resp->delay != "0" && (intp(resp->delay) || stringp(resp->delay))) {
		int|string delay = resp->delay;
		if (stringp(delay) && sscanf(delay, "%[0-9]", string d) && d == delay) delay = (int)delay;
		ret->delay = delay;
	}

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
		array|zero automate = string_to_automation(resp->automate);
		if (automate) ret->automate = automate;
	} else if (arrayp(resp->automate) && sizeof(resp->automate) == 3 && min(@resp->automate) >= 0 && max(@resp->automate) > 0 && resp->automate[2] <= 1)
		ret->automate = resp->automate;

	//TODO: Ensure that the reward still exists
	if (stringp(resp->redemption) && resp->redemption != "") ret->redemption = resp->redemption;

	return sizeof(ret) == 1 ? ret->message : ret;
}

//mode is "" for regular commands, "!!" for specials, "!!trigger" for triggers.
array validate_command(object channel, string|zero mode, string cmdname, echoable_message response, mapping|void options) {
	if (!options) options = ([]);
	mapping state = (["cdanon": 0, "cooldowns": ([]), "channel": channel]);
	if (options->language == "mustard") {
		//Incoming MustardScript as a simple string. Convert it and THEN parse/validate.
		mixed ex = catch {response = G->G->mustard->parse_mustard(response);};
		if (ex) return 0; //TODO: Report the error in some way??
	}
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
				return ({channel, "!trigger", _validate_toplevel(response, state)}); //Validate-only and ignore preexisting triggers
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
			return ({channel, "!trigger", alltrig, state});
		}
		case "": case "!!": {
			string pfx = mode[..0]; //"!" for specials, "" for normals
			if (!stringp(cmdname)) return 0;
			sscanf(cmdname, "%*[!]%s%*[#]%s", string|zero command, string c);
			if (c != "" && c != channel->name[1..]) return 0; //If you specify the command name as "!demo#rosuav", that's fine if and only if you're working with channel "#rosuav".
			command = String.trim(lower_case(command));
			if (command == "") return 0;
			state->cmd = command = pfx + command;
			if (pfx == "!" && !SPECIAL_NAMES[command]) command = 0; //Only specific specials are valid
			if (pfx == "") {
				//See if an original name was provided
				string orig = "";
				if (options->original) sscanf(options->original, "%*[!]%s%*[#]", orig);
				orig = String.trim(lower_case(orig));
				if (orig != "") state->original = orig + channel->name;
			}
			//Validate the message. Note that there will be some things not caught by this
			//(eg trying to set access or visibility deep within the response), but they
			//will be merely useless, not problematic.
			return ({channel, command, _validate_toplevel(response, state), state});
		}
		default: return 0; //Internal error, shouldn't happen
	}
}

void update_aliases(object channel, string aliases, echoable_message response, multiset updates) {
	foreach (aliases / " ", string alias) {
		sscanf(alias, "%*[!]%[^#\n]", string safealias);
		if (safealias && safealias != "" && (!mappingp(response) || safealias != response->alias_of)) {
			if (response) channel->commands[safealias] = response;
			else m_delete(channel->commands, safealias);
			updates[safealias] = 1;
		}
	}
}

void purge(object channel, string cmd, multiset updates, multiset permsgone) {
	echoable_message prev = m_delete(channel->commands, cmd);
	m_delete(channel->path("commands"), cmd);
	if (prev) updates[cmd] = 1;
	if (!mappingp(prev)) return;
	if (prev->alias_of) purge(channel, prev->alias_of, updates, permsgone);
	if (prev->aliases) update_aliases(channel, prev->aliases, 0, updates);
	if (prev->automate) {
		//Clear out the timer. FIXME: Only do this if the command is really going away (not just if it's being updated).
		mixed id = m_delete(autocommands, cmd + channel->name);
		if (id) remove_call_out(id);
	}
	if (prev->redemption) {
		channel->redemption_commands[prev->redemption] -= ({cmd});
		if (!sizeof(channel->redemption_commands[prev->redemption])) m_delete(channel->redemption_commands, prev->redemption);
		updates["rew " + prev->redemption] = 1;
	}
	//TODO: Only do this if not extra->?nosave (which we don't currently have here)
	permsgone["cmd:" + cmd] = 1;
}

//Recursively scan a response for all needed permissions
void scan_for_permissions(echoable_message response, multiset need_perms) {
	if (stringp(response)) {
		//TODO: If it's a slash command, record the permission needed for that command
		//This will require recognition of the voice in use.
	}
	if (arrayp(response)) scan_for_permissions(response[*], need_perms);
	if (!mappingp(response)) return;
	if (response->builtin) {
		object builtin = G->G->builtins[response->builtin];
		if (builtin->scope_required) need_perms[builtin->scope_required] = 1;
	}
	scan_for_permissions(response->message, need_perms);
	scan_for_permissions(response->otherwise, need_perms);
}

//Update (or delete) a per-channel echo command and save to disk
void _save_command(object channel, string cmd, echoable_message response, mapping|void extra)
{
	sscanf(cmd, "%[!]%s#", string pfx, string basename);
	if (basename == "") error("Requires a command name.\n");
	multiset updates = (<cmd>), permsgone = (<>);
	purge(channel, cmd, updates, permsgone);
	if (extra->?original && sscanf(extra->original, "%s#", string oldname)) {
		//Renaming a command requires removal of what used to be.
		purge(channel, oldname, updates, permsgone);
		if (!extra->?nosave) G->G->DB->save_command(channel->userid, oldname, 0);
	}
	//Purge any iteration variables that begin with ".basename:" - anonymous rotations restart on
	//any edit. This ensures that none of the anonymous ones hang around. Named ones are regular
	//variables, though, and might be shared, so we don't delete those.
	//TODO: Only do this if not extra->?nosave, as this should already have been done.
	{
		mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
		string remove = "$." + basename + ":";
		int changed = 0;
		if (vars) foreach (indices(vars), string v) if (has_prefix(v, remove)) {
			changed = 1;
			m_delete(vars, v);
			if (object handler = G->G->websocket_types->chan_variables)
				handler->update_one(channel->name, v - "$");
		}
		if (changed) G->G->DB->save_config(channel->userid, "variables", vars);
	}
	if (response && response != "") channel->commands[cmd] = response;
	//TODO: What if other things need to be purged?
	if (!extra->?nosave) G->G->DB->save_command(channel->userid, cmd, response); //Don't re-save to the database if it came from there.
	if (mappingp(response) && response->aliases) update_aliases(channel, response->aliases, (response - (<"aliases">)) | (["alias_of": cmd]), updates);
	//FIXME: What happens with cooldowns after a change is detected in the database?
	//Should we just scan the command for cooldowns at the same time as scanning for
	//permissions (see below), which would make this work even when fetching from PG?
	foreach (extra->?cooldowns || ([]); string cdname; int cdlength) {
		//If the cooldown delay is shorter than the cooldown timeout,
		//reset the timeout. That way, if you accidentally set a command
		//to have a really long timeout (eg an hour when you wanted a
		//minute), lowering the timeout will fix it. Note that any
		//cooldowns no longer part of the command won't be purged; at
		//worst, they'll linger in G->G until restart - no big deal.
		int timeout = G->G->cooldown_timeout[cdname + channel->name] - time();
		if (cdlength && timeout > cdlength) G->G->cooldown_timeout[cdname + channel->name] = cdlength + time();
	}
	if (mappingp(response) && response->automate && G->G->stream_online_since[channel->userid]) {
		//Start a timer. For simplicity, just pretend the channel freshly went online.
		//Note that database saving is asynchronous, but the live channel->commands[] mapping
		//will already have been updated, so this will be safe.
		connected(channel->config->login, 0, channel->userid);
	}
	if (mappingp(response) && response->redemption) {
		channel->redemption_commands[response->redemption] += ({cmd});
		updates["rew " + response->redemption] = 1;
	}
	channel->config_save();
	if (object handler = G->G->websocket_types->chan_commands) {
		//If the command name starts with "!", it's a special, to be
		//sent out to "!!#channel" and not to "#channel".
		foreach (updates; cmd;) {
			//TODO maybe: If a command has been renamed, notify clients to rename, rather than
			//deleting the old and creating the new.
			if (has_prefix(cmd, "rew ")) continue;
			if (cmd == "!trigger") handler->send_updates_all(channel, "!" + cmd);
			else handler->update_one(channel, pfx + pfx, cmd);
			handler->send_updates_all(channel, cmd);
		}
	}
	if (object handler = G->G->websocket_types->chan_pointsrewards) {
		//Similarly to the above, notify changes to any redemption invocations.
		foreach (updates; cmd;) {
			if (!has_prefix(cmd, "rew ")) continue;
			//update_one not currently supported on this socket, so just
			//send a full update and then stop (so we don't multiupdate).
			handler->send_updates_all(channel, ""); break;
		}
	}
	if (function handler = response && G->G->specials_check_hooks) {
		//If this is a special that requires a hook, ensure that we have the hook.
		foreach (updates; cmd;) {
			if (sscanf(cmd, "!%s#", string spec) && G->G->SPECIALS_SCOPES[spec]) {
				handler(channel->config);
				break; //No need to update more than once - it'll check all the hooks
			}
		}
	}
	//If this uses any builtins that require permissions, and we don't have those, flag the user.
	//TODO: Do this only if not extra->?nosave.
	multiset need_perms = (<>); scan_for_permissions(response, need_perms);
	if (sizeof(need_perms) || sizeof(permsgone)) update_perms_notifications(channel->userid, need_perms, permsgone, basename);
}

__async__ void update_perms_notifications(int channelid, multiset need_perms, multiset permsgone, string basename) {
	mapping prefs = await(G->G->DB->load_config(channelid, "userprefs"));
	int changed = 0;
	if (prefs->notif_perms) foreach (prefs->notif_perms; string perm; array reasons) {
		int removed = 0;
		foreach (reasons; int i; mapping r) if (permsgone[r->reason]) {reasons[i] = 0; removed = 1;}
		if (removed) {prefs->notif_perms[perm] = reasons - ({0}); changed = 1;}
	}
	multiset scopes = (multiset)(G->G->user_credentials[channelid]->?scopes || ({ }));
	foreach (need_perms; string perm;) {
		if (!scopes[perm]) {
			if (!prefs->notif_perms) prefs->notif_perms = ([]);
			prefs->notif_perms[perm] += ({([
				"desc": "Command - " + basename, //or special/trigger?
				"reason": "cmd:" + basename,
			])});
			changed = 1;
		}
	}
	if (changed) {
		G->G->DB->save_config(channelid, "userprefs", prefs);
		G->G->update_user_prefs(channelid, (["notif_perms": prefs->notif_perms]));
	}
}

//Validate and update. Returns 0 if command was invalid, otherwise the response.
echoable_message|zero update_command(object channel, string mode, string cmdname, echoable_message response, mapping|void options) {
	array valid = validate_command(channel, mode, cmdname, response, options);
	if (valid) {_save_command(@valid); return valid[2];}
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
		"builtin": "argsplit", "builtin_param": ({"{param}"}),
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
			string msg = param[1] - "!";
			array(int) mins = string_to_automation(param[2]);
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
			if (!SPECIAL_NAMES[cmd] && has_value(cmd, '!')) error("Command names cannot include exclamation marks\n");
			string newornot = channel->commands[cmd] ? "Updated" : "Created new";
			_save_command(channel, cmd, param[2..] * " ");
			return (["{result}": sprintf("%s command !%s", newornot, cmd)]);
		}
		case "Delete": {
			string cmd = command_casefold(param[1]);
			if (!channel->commands[cmd]) error("No echo command with that name exists here.\n");
			_save_command(channel, cmd, 0);
			return (["{result}": sprintf("Deleted command !%s", cmd)]);
		}
		default: error("Unknown subcommand\n");
	}
}

@on_irc_loaded: void check_autospam() {
	foreach (indices(G->G->irc->id), int userid)
		if (G->G->stream_online_since[userid]) connected("", 0, userid);
}

protected void create(string name) {
	::create(name);
	G->G->cmdmgr = this;
	G->G->update_command = update_command; //Deprecated alias for G->G->cmdmgr->update_command
	//Old API - if you are using this, switch to update_command which also validates.
	add_constant("make_echocommand", lambda() {error("make_echocommand is no longer supported.\n");});
	register_bouncer(autospam);
}
