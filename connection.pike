inherit hook;
inherit irc_callback;
inherit annotated;

mapping simple_regex_cache = ([]); //Emptied on code reload.
object substitutions = Regexp.PCRE("(\\$[*?A-Za-z0-9|:]*\\$)|({[A-Za-z0-9_@|]+})");
constant messagetypes = ({"PRIVMSG", "NOTICE", "WHISPER", "USERNOTICE", "CLEARMSG", "CLEARCHAT", "USERSTATE"});
mapping irc_connections = ([]); //Not persisted across code reloads, but will be repopulated (after checks) from the connection_cache.
@retain: mapping channelcolor = ([]);
@retain: mapping cooldown_timeout = ([]);
@retain: mapping nonce_callbacks = ([]);
int(1bit) is_active; //Cache of is_active_bot() since we need to check it freuqently.

constant badge_aliases = ([ //Fold a few badges together, and give shorthands for others
	"broadcaster": "_mod", "moderator": "_mod", "staff": "_mod",
	"subscriber": "_sub", "founder": "_sub", //Founders (the first 10 or 25 subs) have a special badge.
]);
//Go through a message's parameters/tags to get the info about the person
//There may be some non-person info gathered into here too, just for
//convenience; in fact, the name "person" here is kinda orphanned. (Tragic.)
mapping(string:mixed) gather_person_info(mapping params, string msg)
{
	string user = params->login || params->user;
	mapping ret = (["nick": user, "user": user]); //TODO: Is nick used anywhere? If not, remove.
	if (params->user_id && user) //Should always be the case
	{
		ret->uid = (int)params->user_id;
		notice_user_name(user, params->user_id);
	}
	ret->displayname = params->display_name || user;
	ret->msgid = params->id;
	ret->badges = ([]);
	if (params->badges) foreach (params->badges / ",", string badge) if (badge != "") {
		sscanf(badge, "%s/%d", badge, int status);
		ret->badges[badge] = status;
		if (string flag = badge_aliases[badge]) ret->badges[flag] = status;
	}
	if (params->emotes)
	{
		ret->emotes = ({ });
		foreach (params->emotes / "/", string emote) if (emote != "")
		{
			sscanf(emote, "%s:%s", string id, string pos);
			foreach (pos / ",", string p) {
				sscanf(p, "%d-%d", int start, int end);
				if (end < start) continue; //Shouldn't happen (probably a parse failure)
				ret->emotes += ({({id, start, end})});
			}
		}
		//Also list all cheer emotes as emotes
		int ofs = 0;
		foreach (msg / " ", string word) {
			//4Head is the only cheeremote with non-alphabetics in the prefix.
			//Since we don't want to misparse "4head4000", we special-case it
			//by accepting a 4 at the start of the letters (but nowhere else).
			sscanf(word, "%[4]%[A-Za-z]%[0-9]%s", string four, string letters, string digits, string blank);
			mapping cheer = G->G->cheeremotes[lower_case(four + letters)];
			if (cheer && digits != "" && digits != "0" && blank == "") {
				//Synthesize an emote ID with a leading space so we know that
				//it can't be a normal emote. This may cause some broken images,
				//but it should at least allow cheeremotes to be suppressed with
				//other emotes.
				ret->emotes += ({({"/" + cheer->prefix + "/" + digits, ofs, ofs + sizeof(word) - 1})});
			}
			ofs += sizeof(word) + 1;
		}
		sort(ret->emotes[*][1], ret->emotes); //Sort the emotes by start position
	}
	if (int bits = (int)params->bits) ret->bits = bits;
	//ret->raw = params; //For testing
	return ret;
}

//May receive up to three parameters: the value to be formatted, the default (which can be a parameter),
//and the channel object
mapping(string:function(string:string)) text_filters = ([
	"time_hms": lambda(string tm) {return describe_time_short((int)tm);},
	"time_english": lambda(string tm) {return describe_time((int)tm);},
	"date_dmy": lambda(string tm, string dflt, object channel) {
		object ts = Calendar.Gregorian.Second("unix", (int)tm);
		if (string tz = channel->config->timezone) ts = ts->set_timezone(tz) || ts;
		return sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
	},
	"upper": upper_case, "lower": lower_case,
]);

__async__ void raidwatch(int channel, string raiddesc) {
	await(task_sleep(30)); //It seems common for streamers to be offline after about 30 seconds
	string status = "error";
	mixed ex = catch {status = await(channel_still_broadcasting(channel));};
	Stdio.append_file("raidwatch.log", sprintf("[%s] %s: %s\n", ctime(time())[..<1], raiddesc, status));
}

@create_hook:
constant allmsgs = ({"object channel", "mapping person", "string msg"});
@create_hook:
constant subscription = ({"object channel", "string type", "mapping person", "string tier", "int qty", "mapping extra", "string msg"});
@create_hook:
constant cheer = ({"object channel", "mapping person", "int bits", "mapping extra", "string msg"});
@create_hook:
constant deletemsg = ({"object channel", "object person", "string target", "string msgid"});
@create_hook:
constant deletemsgs = ({"object channel", "object person", "string target"});

__async__ void voice_enable(string voiceid, string chan, mapping|void tags) {
	mapping tok = G->G->user_credentials[(int)voiceid];
	werror("Connecting to voice %O...\n", voiceid);
	object conn = await(irc_connect(([
		"user": tok->login, "pass": "oauth:" + tok->token,
		"voiceid": voiceid, //Triggers auto-cleanup when the voice is no longer in use
		"capabilities": ({"commands"}),
	])));
	werror("Voice %O connected, sending to channel %O\n", voiceid, chan);
	array msgs = irc_connections[voiceid]; //Note that the queue may be added to while we're connecting.
	if (!arrayp(msgs)) {conn->queueclose(); return;} //We've been kicked for auth change. Ignore it.
	irc_connections[voiceid] = conn;
	conn->yes_reconnect(); //Mark that we need this connection
	conn->send(chan, msgs[*], tags);
	conn->enqueue(conn->no_reconnect); //Once everything's sent, it's okay to disconnect
}

string subtier(string plan) {
	if (plan == "Prime") return "1";
	return plan[0..0]; //Plans are usually 1000, 2000, 3000 - I don't know if they're ever anything else?
}

@create_hook:
constant variable_changed = ({"object channel", "string varname", "string newval"});

class channel(mapping identity) {
	string name; //name begins with a hash and is all lowercase. Preference: Use this->login (no hash) instead.
	string color;
	int userid; string login, display_name;
	mapping raiders = ([]); //People who raided the channel this (or most recent) stream. Cleared on stream online.
	mapping user_badges = ([]); //Latest-seen user badge status (see gather_person_info). Not guaranteed fresh.
	//Command names are simple atoms (eg "foo" will handle the "!foo" command), or well-known
	//bang-prefixed special triggers (eg "!resub" for a channel's resubscription trigger).
	mapping(string:echoable_message) commands = ([]);
	//Map a reward ID to the redemption triggers for that reward. Empty arrays should be expunged.
	mapping(string:array(string)) redemption_commands = ([]);
	mapping botconfig, config;

	protected void create(multiset|void loading, array|void commands) {
		botconfig = m_delete(identity, "data") || ([]);
		config = identity | botconfig;
		name = "#" + config->login; userid = config->userid;
		login = config->login; display_name = config->display_name;
		if (config->chatlog)
		{
			if (!channelcolor[name]) {if (++G->G->nextcolor>7) G->G->nextcolor=1; channelcolor[name]=G->G->nextcolor;}
			color = sprintf("\e[1;3%dm", channelcolor[name]);
		}
		else color = "\e[0m"; //Nothing will normally be logged, so don't allocate a color. If logging gets enabled, it'll take a reset to assign one.
		//The streamer counts as a mod. Everyone else has to speak in chat to
		//show us the badge, after which we'll acknowledge mod status. (For a
		//mod-only command, that's trivially easy; for web access, just "poke
		//the bot" in chat first.) The helix/moderation/moderators endpoint
		//might look like the perfect solution, but it requires broadcaster's
		//permission, so it's not actually dependable.
		user_badges = G_G_("channel_user_badges", (string)userid);
		if (!user_badges[userid]) user_badges[userid] = (["_mod": 1, "broadcaster": 1]);
		if (name == "#!demo") user_badges[3141592653589793] = (["_mod": 1, "moderator": 1]); //Fake mod status for the fake mod
		/* TODO:
		if (have the right permission) twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=49497888")->then() {
			foreach (__ARGS__[0]->data || ({ }), mapping mod)
				if (!user_badges[(int)mod->user_id]) user_badges[(int)mod->user_id] = (["_mod": 1, "moderator": 1]);
		};
		This won't quite work due to timing and the way credentials get loaded asynchronously.
		*/
		//Note that !demo has no userid and can't re-fetch login/display name.
		if (userid) {
			G->G->recent_user_sightings[userid] = login;
			get_user_info(userid)->then() {
				if (config->login != __ARGS__[0]->login || config->display_name != __ARGS__[0]->display_name) {
					//Note: This is asynchronous, but we'll be triggering a reconnect shortly.
					G->G->DB->save_sql("update stillebot.botservice set login = :login, display_name = :display_name where twitchid = :id", __ARGS__[0]);
				}
			};
		}
		load_commands(loading, commands);
	}

	__async__ void load_commands(multiset|void loading, array|void cmds) {
		//Load up the channel's commands. Note that aliases are not stored in the database,
		//but are individually available here in the lookup mapping.
		commands = ([]);
		if (!cmds) cmds = await(G->G->DB->load_commands(userid));
		foreach (cmds, mapping cmd) {
			echoable_message response = commands[cmd->cmdname] = cmd->content;
			if (!mappingp(response)) continue; //No top-level flags, nothing to handle specially.
			if (response->aliases) {
				mapping duplicate = (response - (<"aliases">)) | (["alias_of": cmd->cmdname]);
				foreach (response->aliases / " ", string alias) {
					alias -= "!";
					if (alias != "") commands[alias] = duplicate;
				}
			}
			if (response->redemption) redemption_commands[response->redemption] += ({cmd->cmdname});
		}
		//Indicate that we're now done loading. If other things than commands are done
		//asynchronously but in parallel, don't remove from loading till ALL are done.
		if (loading) loading[userid] = 0;
	}

	void botconfig_save() {
		config = identity | botconfig; //Update the mapping synchronously - we'll also be notified via reconfigure shortly
		G->G->DB->save_config(userid, "botconfig", botconfig);
	}
	void reconfigure(mapping data) { //Called after a bot config change is noticed in the database
		config = identity | (botconfig = data);
	}

	//Drill down into any mapping. Could become global?? maybe??
	mapping _path(mapping base, string ... parts) {
		mapping ret = base;
		foreach (parts, string idx) {
			if (undefinedp(ret[idx])) ret[idx] = ([]);
			ret = ret[idx];
		}
		return ret;
	}

	void remove_bot_from_channel() {
		G->G->DB->save_sql("update stillebot.botservice set deactivated = now() where twitchid = :userid and deactivated is null", (["userid": userid]));
	}

	void channel_online(int uptime) {
		//Purge the raider list of anyone who didn't raid since the stream went online.
		//This signal comes through a minute or six after the channel actually goes
		//online, so we use the current uptime as a signal to know who raided THIS stream
		//as opposed to LAST stream.
		int went_online = time() - uptime;
		raiders = filter(raiders) {return __ARGS__[0] >= went_online;};
	}

	array(echoable_message|function|string) locate_command(mapping person, string msg)
	{
		if (mixed f = sscanf(msg, "!%[^# ] %s", string cmd, string param)
			&& find_command(this, cmd, person->badges->?_mod, person->badges->?vip))
				return ({f, param||""});
		return ({0, ""});
	}

	//TODO: Figure out what this function's purpose is. I frankly have no idea why some
	//code is in here, and other code is down in "case PRIVMSG" below. Whatever.
	void handle_command(mapping person, string msg, mapping defaults, mapping params)
	{
		if (person->user) {
			mapping p = G_G_("participants", name[1..], person->user);
			p->lastnotice = time();
			p->userid = person->uid;
		}
		person->vars = ([
			"%s": msg, "{@mod}": person->badges->?_mod ? "1" : "0", "{@sub}": person->badges->?_sub ? "1" : "0",
			//Even without broadcaster permissions, it's possible to see the UUID of a reward.
			//You can't see the redemption ID, and definitely can't complete/reject it, but you
			//would be able to craft a trigger that responds to it.
			"{rewardid}": params->custom_reward_id || "",
			"{msgid}": params->id || "",
			"{usernamecolor}": params->color || "", //Undocumented, mainly here as a toy
		]);
		event_notify("allmsgs", this, person, msg);
		trigger_special("!trigger", person, person->vars);
		[mixed cmd, string param] = locate_command(person, msg);
		int offset = sizeof(msg) - sizeof(param);
		if (msg[offset..offset+sizeof(param)] != param) offset = -1; //TODO: Strip whites from around param without breaking this
		person->measurement_offset = offset;
		string emoted = "", residue = param;
		foreach (person->emotes || ({ }), [string id, int start, int end]) {
			emoted += sprintf("%s\uFFFAe%s:%s\uFFFB",
				residue[..start - offset - 1], //Text before the emote
				id, residue[start-offset..end-offset], //Emote ID and name
			);
			residue = residue[end - offset + 1..];
			offset = end + 1;
		}
		person->vars["%s"] = param;
		person->vars["{@emoted}"] = emoted + residue;
		//Functions do not get %s handling. If they want it, they can do it themselves,
		//and if they don't want it, it would mess things up badly to do it here.
		//(They still get other variable handling.) NOTE: This may change in the future.
		//If a function specifically does not want %s handling, it should:
		//m_delete(person->vars, "%s");
		if (functionp(cmd)) send(person, cmd(this, person, param));
		else send(person, cmd, person->vars);
	}

	__async__ void delete_msg(string uid, string msgid) {
		await(G->G->DB->mutate_config(userid, "private") {m_delete(__ARGS__[0][uid] || ([]), msgid);});
		G->G->websocket_types->chan_messages->update_one(uid + "#" + userid, msgid);
	}

	__async__ void send_private_message(string login, echoable_message msg, string destcfg) {
		string uid = (string)await(get_user_id(login));
		mapping priv = await(G->G->DB->load_config(userid, "private"));
		mapping msgs = priv[uid]; if (!msgs) msgs = priv[uid] = ([]);
		mapping meta = msgs["_meta"]; if (!meta) meta = msgs["_meta"] = ([]);
		int id = ++meta->lastid;
		msgs[(string)id] = (["received": time(), "message": msg]);
		//NOTE: The destcfg has already been var-substituted, and then it gets reprocessed
		//when it gets sent. That's a bit awkward. Maybe the ideal would be to retain it
		//unprocessed, but keep the local vars, and then when it's sent, set _changevars?
		if (destcfg != "") {
			//TODO maybe: make destcfg accept non-string values, then it can just have
			//multiple parts.
			sscanf(destcfg, ":%d:%s", int timeout, string ack);
			msgs[(string)id]->acknowledgement = ack || destcfg;
			if (timeout) {
				msgs[(string)id]->expiry = time() + timeout;
				call_out(delete_msg, timeout, uid, (string)id);
			}
		}
		await(G->G->DB->save_config(userid, "private", priv));
		G->G->websocket_types->chan_messages->update_one(uid + "#" + userid, (string)id);
	}

	mapping(string:string) get_channel_variables(int|string|void uid) {
		mapping vars = G->G->DB->load_cached_config(userid, "variables");
		mapping ephemvars = G->G->variables[?(string)userid];
		if (ephemvars) return vars | ephemvars;
		return vars;
	}

	string set_variable(string var, string val, string action, mapping|void users)
	{
		//Per-user variable. If you try this without a user context, it will
		//use uid 0 aka "root" which doesn't exist in Twitch.
		int per_user = sscanf(var, "%s*%s", string user, var);
		int ephemeral = sscanf(var, "%s?", var);
		var = "$" + var + "?" * ephemeral + "$";
		mapping basevars = ephemeral ? G_G_("variables", (string)userid) : G->G->DB->load_cached_config(userid, "variables");
		mapping vars = per_user ? _path(basevars, "*", (string)users[?user]) : basevars;
		if (action == "add") {
			//Add to a variable, REXX-style (decimal digits in strings).
			//Anything unparseable is considered to be zero.
			val = (string)((int)vars[var] + (int)val);
		} else if (action == "spend") {
			//Inverse of add, but will fail (and return 0) if the variable
			//doesn't have enough value in it.
			int cur = (int)vars[var];
			if (cur < (int)val) return 0;
			val = (string)(cur - (int)val);
		}
		//Otherwise, keep the string exactly as-is.
		vars[var] = val;
		if (val == "" && per_user) {
			//Per-user variables don't need to store blank
			m_delete(vars, var);
			if (!sizeof(vars)) m_delete(basevars["*"], (string)users[?user]);
		}
		if (ephemeral) return val; //Ephemeral variables are not pushed out to listeners.
		//Notify those that depend on this. Note that an unadorned per-user variable is
		//probably going to behave bizarrely in a monitor, so don't do that; use either
		//global variables or namespace to a particular user eg "$49497888*varname$".
		G->G->DB->save_config(userid, "variables", basevars);
		if (per_user) var = "$" + (string)users[?user] + "*" + var[1..];
		else if (!has_value(var, ':')) G->G->websocket_types->chan_variables->update_one(name, var - "$");
		//Note that we don't currently push out signals relating to grouped variables.
		//The only signal that would matter is "hey, there's a new grouped var", but
		//that's going to be fairly rare anyway. The update_one handler would need to
		//be enhanced to handle groups, and it's more complexity than it's worth. We
		//do, however, use variable_changed, so it's only the /c/variables page that
		//is missing out on this information (eg monitors work fine).
		event_notify("variable_changed", this, var, val);
		return val;
	}

	//For consistency, this is used for all vars substitutions. If, in the future,
	//we make $UNKNOWN$ into an error, or an empty string, or something, this would
	//be the place to do it.
	string|array _substitute_vars(string|array text, mapping vars, mapping person, mapping users) {
		if (arrayp(text)) return _substitute_vars(text[*], vars, person, users);
		//Replace shorthands with their long forms. They are exactly equivalent, but the
		//long form can be enhanced with filters and/or defaults.
		text = replace(text, (["%s": "{param}", "$participant$": "{participant}"]));
		if (!vars["{participant}"] && has_value(text, "{participant}") && person->user)
		{
			//Note that {participant} with a delay will invite people to be active
			//before the timer runs out, but only if there's no {participant} prior
			//to the delay.
			array users = ({ });
			int limit = time() - 300; //Find people active within the last five minutes
			foreach (G_G_("participants", name[1..]); string name; mapping info)
				if (info->lastnotice >= limit && name != person->user) users += ({name});
			//If there are no other chat participants, pick the person speaking.
			string chosen = sizeof(users) ? random(users) : person->user;
			vars["{participant}"] = chosen;
		}
		//TODO: Don't use the shortforms internally anywhere
		vars["{param}"] = vars["%s"]; vars["{username}"] = vars["$$"];
		//Scan for two types of substitution - variables and parameters
		return substitutions->replace(text) {
			sscanf(__ARGS__[0], "%[${]%[^|$}]%[^$}]%[$}]", string type, string kwd, string filterdflt, string tail);
			//TODO: Have the absence of a default be actually different from an empty one
			//So $var||$ would give an empty string if var doesn't exist, but $var$ might
			//throw an error or something. For now, they're equivalent, and $var$ will be
			//an empty string if the var isn't found.
			[string _, string filter, string dflt] = ((filterdflt + "||") / "|")[..2];
			string value;
			if (type == "$" && sscanf(kwd, "%s*%s", string user, string basename) && basename) {
				//If the kwd is of the format "49497888*varname", and the type is "$",
				//look up a per-user variable called "*varname" for that user.
				user = users[user] || user;
				if (basename == "") value = user; //"$*$" or "$kwd*$" will give you the ID of that user.
				else if (mappingp(vars["*"])) value = vars["*"][user][?type + basename + tail];
			}
			else value = vars[type + kwd + tail];
			if (!value || value == "") return dflt;
			if (function f = filter != "" && text_filters[filter]) return f(value, dflt, this);
			return value;
		};
	}

	//Mutually recursive with _send_recursive. Call this rather than _send_recursive directly
	//when you want an error boundary that sends to cfg->error_handler, or if the call is being
	//delayed in some way.
	void _send_with_catch(mapping person, echoable_message message, mapping vars, mapping cfg) {
		if (mixed ex = catch {_send_recursive(person, message, vars, cfg);}) {
			//TODO: Carry context around, eg who triggered what command
			if (arrayp(ex) && sizeof(ex) && stringp(ex[0])) {
				if (cfg->error_handler) {
					vars["{error}"] = String.trim(ex[0]);
					_send_with_catch(person, cfg->error_handler->message, vars, cfg->error_handler->cfg);
				}
				report_error("ERROR", String.trim(ex[0]), "");
			}
			else werror("**** Error in command handling, unexpected format ****\n%s\n", describe_backtrace(ex));
		}
	}

	//Changes to vars[] will propagate linearly. Changes to cfg[] will propagate
	//within a subtree only. Change it only with |=.
	void _send_recursive(mapping person, echoable_message message, mapping vars, mapping cfg)
	{
		if (!message) return;
		if (!mappingp(message)) message = (["message": message]);
		if (message->dest == "//") return; //Comments are ignored. Not even side effects.

		if (message->delay && message->delay != "") {
			int|string delay = message->delay;
			if (!intp(delay)) delay = (int)_substitute_vars((string)delay, vars, person, cfg->users);
			//Note that, if a string delay evaluates to zero - say, it has a bad variable
			//reference that falls to blank - this will call_out zero, which should work fine.
			call_out(_send_with_catch, delay, person, message | (["delay": 0, "_changevars": 1]), vars, cfg);
			return;
		}
		if (message->_changevars)
		{
			//When a delayed message gets sent, override any channel variables
			//with their new values. There are some bizarre corner cases that
			//could result from this (eg if you delete a variable, it'll still
			//exist in the delayed version), but there's no right way to do it.
			vars = vars | get_channel_variables(person->uid);
			message->_changevars = 0; //It's okay to mutate this one, since it'll only ever be a bookkeeping mapping from delay handling.
		}

		if (message->dest == "/builtin") { //Deprecated way to call on a builtin
			//NOTE: Prior to 2021-05-16, variable substitution was done on the entire
			//target. It's now done only on the builtin_param (below).
			sscanf(message->target, "!%[^ ]%*[ ]%s", string cmd, string param);
			message = (message - (<"dest", "target">)) | (["builtin": cmd, "builtin_param": param]);
		}

		if (message->voice) cfg |= (["voice": message->voice]);
		//Legacy mode: dest is dest + " " + target, target doesn't exist
		if (has_value(message->dest || "", ' ') && !message->target) {
			sscanf(message->dest, "%s %s", string d, string t);
			cfg |= (["dest": d, "target": _substitute_vars(t, vars, person, cfg->users), "destcfg": message->action || ""]);
		}
		//Normal mode: Destination and target are separate fields
		//Note that message->action was a variables-only form of destcfg, so it is merged in too.
		else if (message->dest) cfg |= ([
			"dest": message->dest,
			"target": String.trim(_substitute_vars(message->target || "", vars, person, cfg->users)),
			"destcfg": _substitute_vars(message->action || message->destcfg || "", vars, person, cfg->users),
		]);

		if (message->builtin) {
			object handler = G->G->builtins[message->builtin] || message->builtin; //Chaining can be done by putting the object itself in the mapping
			if (objectp(handler)) {
				string|array param = _substitute_vars(message->builtin_param || "", vars, person, cfg->users);
				if (stringp(param)) param = ({param});
				spawn_task(handler->message_params(this, person, param, cfg))->then() {
					if (!__ARGS__[0]) return; //No params? No output.
					mapping cfg_changes = m_delete(__ARGS__[0], "cfg") || ([]);
					_send_with_catch(person, message->message, vars | __ARGS__[0], cfg | cfg_changes);
				};
				return;
			}
			else message = (["message": sprintf("Bad builtin name %O", message->builtin)]); //FIXME: Log error instead?
		}

		echoable_message msg = message->message;
		string expr(string input) {
			if (!input) return "";
			string ret = _substitute_vars(input, vars, person, cfg->users);
			if (message->casefold) return command_casefold(ret); //Use the same case-folding algorithm as !command lookups use
			return ret;
		}
		switch (message->conditional) {
			case "string": //String comparison. If (after variable substitution) expr1 == expr2, continue.
			{
				if (expr(message->expr1) == expr(message->expr2)) break; //The condition passes!
				msg = message->otherwise;
				break;
			}
			case "contains": //String containment. Similar.
			{
				if (has_value(expr(message->expr2), expr(message->expr1))) break; //The condition passes!
				msg = message->otherwise;
				break;
			}
			case "regexp":
			{
				if (!message->expr1) break; //A null regexp matches everything
				//Note that expr1 does not get variable substitution done. The
				//notation for variables would potentially conflict with the
				//regexp's own syntax.
				object re = simple_regex_cache[message->expr1];
				if (!re) re = simple_regex_cache[message->expr1] = Regexp.PCRE(message->expr1);
				string matchtext = expr(message->expr2);
				int|array result = re->exec(matchtext);
				if (arrayp(result)) { //The regexp passes!
					//NOTE: Other {regexpNN} vars are not cleared. This may mean
					//that nested regexps can both contribute. I may change this
					//in the future, if I allow an easy way to set a local var.
					foreach (result / 2; int i; [int start, int end])
						vars["{regexp" + i + "}"] = matchtext[start..end-1];
					break;
				}
				//Otherwise, the return code is probably NOMATCH (-1). If it isn't, should we
				//show something to the user?
				msg = message->otherwise;
				break;
			}
			case "number": //Integer/float expression evaluator. Subst into expr, then evaluate. If nonzero, pass. If non-numeric, error out.
			{
				if (!G->G->evaluate_expr) msg = "ERROR: Expression evaluator unavailable";
				else if (mixed ex = catch {
					int|float|string value = G->G->evaluate_expr(expr(message->expr1), ({this, cfg}));
					if (value != 0 && value != 0.0) break; //But I didn't fire an arrow...
					//Note that all strings are currently considered true. This MAY change
					//in the future, with empty strings being considered false.
					msg = message->otherwise;
				}) msg = "ERROR: " + (describe_error(ex)/"\n")[0];
				break;
			}
			case "spend":
			{
				string var = message->expr1;
				if (!var || var == "") break; //Blank/missing variable name? Not a functional condition.
				string val = set_variable(var, message->expr2, "spend", cfg->users);
				if (!val) msg = message->otherwise; //The condition DOESN'T pass if the spending failed.
				else if (!has_value(var, '*')) vars["$" + var + "$"] = val; //It usually WILL have an asterisk.
				break;
			}
			case "cooldown": //Timeout (defined in seconds, although the front end may show it as mm:ss or hh:mm:ss)
			{
				string key = message->cdname + name;
				if (has_prefix(key, "*")) key = vars["{uid}"] + key; //Cooldown of "*foo" will be a per-user cooldown.
				int delay = cooldown_timeout[key] - time();
				if (delay < 0) { //The time has passed!
					cooldown_timeout[key] = time() + message->cdlength; //But reset it.
					vars["{cooldown}"] = vars["{cooldown_hms}"] = "0";
					break;
				}
				if (message->cdqueue) {
					//As well as bouncing to the Otherwise, we queue the original message
					//after the delay. (You probably don't often need an Otherwise here.)
					cooldown_timeout[key] = time() + delay + message->cdlength;
					call_out(_send_with_catch, delay, person, message | (["conditional": 0, "_changevars": 1]), vars, cfg);
				}
				//Yes, it's possible for the timeout to be 0 seconds.
				msg = message->otherwise;
				vars["{cooldown}"] = (string)delay;
				//Note that the hms format is defined by the span of the cooldown in total,
				//not the remaining time. A ten minute timeout, down to its last seconds,
				//will still show "00:15". If you want conditional rendering based on the
				//remaining time, use {cooldown} in a numeric condition.
				vars["{cooldown_hms}"] =
					(int)message->cdlength < 60 ? (string)delay :
					(int)message->cdlength < 3600 ? sprintf("%d:%02d", delay / 60, delay % 60) :
					sprintf("%d:%02d:%02d", delay / 3600, (delay / 60) % 60, delay % 60);
				break;
			}
			case "catch": { //Exception handling
				_send_with_catch(person, message | (["conditional": 0]), vars,
					cfg | (["error_handler": (["message": message->otherwise, "cfg": cfg])]));
				return;
			}
			default: break; //including UNDEFINED which means unconditional, and 0 which means "condition already processed"
		}
		if (!msg) return; //If a message doesn't have an Otherwise, it'll end up null.

		//cfg->voice could be absent, blank, "0", or a voice ID eg "279141671"
		//Absent and blank mean "use the channel default" - config->defvoice - which
		//might be zero (meaning that the channel default is the global default).
		//"0" means "use the global default, even if it's not the channel default"
		//Otherwise, it's the ID of a Twitch user whose voice we should use. Note that
		//there's no check to ensure that we have permission to do so; if you add a
		//voice but don't grant permission to use chat, all chat messages will just
		//fail silently. (This would be fine if it's only used for slash commands.)
		string|zero voice = (cfg->voice && cfg->voice != "") ? cfg->voice : config->defvoice;
		if (!G->G->DB->load_cached_config(userid, "voices")[voice]) voice = 0; //Ensure that the voice hasn't been deauthenticated since the command was edited
		if (!voice) {
			//No voice has been selected (either explicitly or as the channel default).
			//Use the bot's global default voice, or the intrinsic voice (implicitly zero).
			voice = G->G->irc->id[0]->?config->?defvoice;
			//Even if this voice hasn't been activated for this channel, that's fine - it is
			//implicitly permitted for use by all channels.
		}

		if (message->mode == "foreach") {
			//For now, this only iterates over participants. To expand and generalize this,
			//create a builtin that gathers a collection of participants, and then foreach
			//will iterate over any collection. The builtin's args would specify the timeout
			//(or "no timeout" for all in chat), and would probably collect into something
			//akin to a variable. Then foreach mode would iterate over that variable.
			//NOTE: Due to Twitch API restrictions, the "everyone in chat" version of this
			//requires that the currently-selected voice be a moderator with scope permission
			//to read chatters (moderator:read:chatters). This is a tad awkward. Fortunately,
			//we can use the "active chatter" mode simply based on sightings in chat. This IS
			//going to create a bizarre disconnect; for example, you could say "everyone who
			//has been active within the last 15 minutes", and this may well include people
			//who are no longer listed in the "all chatters" list.
			//TODO: Allow the iteration to do other things than just select a user into "each"
			array users = ({ });
			if (string varname = message->variable) {
				//Iterate over every user for whom there are variables.
				//Note that there may not be a specific variable; you'll need to do some
				//sort of check eg "$each*varname$" == "" to see if it's actually set.
				mapping vars = G->G->DB->load_cached_config(userid, "variables")["*"] || ([]);
				if (varname == "*") users = sort(indices(vars)); //Everyone who has any variable, in ID order.
				else {
					//Everyone who has this variable set, in descending order by the intification of
					//that variable. NOTE: If the variable is set to "0" or "foo", the person will be
					//included in the result, sorted at position 0; but if the variable is absent,
					//they will not be included at all. Thus this can be used - albeit without useful
					//sorting - for non-numeric variables too.
					array(int) values = ({ });
					varname = "$" + replace(varname, "$", "") + "$";
					foreach (vars; string uid; mapping v) if (v[varname]) {
						users += ({uid});
						values += ({-(int)v[varname]}); //Descending sort
					}
					sort(values, users);
				}
			} else if (message->participant_activity) {
				int limit = time() - (int)message->participant_activity; //eg find people active within the last five minutes
				foreach (G_G_("participants", name[1..]); string name; mapping info)
					if (info->lastnotice >= limit) users += ({info->userid});
			} else {
				//Ask Twitch who's currently in chat.
				mapping tok = G->G->user_credentials[(int)voice];
				get_helix_paginated(
					"https://api.twitch.tv/helix/chat/chatters",
					(["broadcaster_id": (string)userid, "moderator_id": (string)voice]),
					(["Authorization": "Bearer " + tok->token]),
				)->then() {
					cfg |= (["users": cfg->users | (["each": "0"])]);
					//Now that we've disconnected both cfg and cfg->users, it's okay to mutate.
					foreach (__ARGS__[0], mapping user) {
						cfg->users->each = user->user_id;
						_send_recursive(person, msg, vars, cfg);
					}
				};
			}
			cfg |= (["users": cfg->users | (["each": "0"])]);
			//Ditto, mutation is okay now.
			foreach (users, cfg->users->each) _send_recursive(person, msg, vars, cfg);
			return;
		}

		if (mappingp(msg)) {_send_recursive(person, (["conditional": 0]) | msg, vars, cfg); return;} //CJA 20230623: See other of this datemark.

		if (arrayp(msg))
		{
			if (message->mode == "random") msg = random(msg);
			else if (message->mode == "rotate") {
				string varname = message->rotatename;
				if (!varname || varname == "") varname = ".borked"; //Shouldn't happen, just guard against crashes
				int val = (int)vars["$" + varname + "$"];
				if (val >= sizeof(msg)) val = 0;
				msg = msg[val];
				vars["$" + varname + "$"] = set_variable(varname, (string)(val + 1), "", cfg->users);
			} else {
				//CJA 20230623: This previously kept all attributes from the current
				//message except for conditional, and merged that with the message.
				//Why? I don't understand what I was thinking at the time (see fbd850)
				//and it's causing issues with a random that contains groups. If it is
				//needed, it may be better to whitelist attributes to retain, rather
				//than blacklisting those to remove.
				foreach (msg, echoable_message m)
					_send_recursive(person, m, vars, cfg);
				return;
			}
			_send_recursive(person, (["conditional": 0, "message": msg]), vars, cfg); //CJA 20230623: See other.
			return;
		}

		//And now we have just a single string to send.
		string prefix = _substitute_vars(message->prefix || "", vars, person, cfg->users);
		msg = _substitute_vars(msg, vars, person, cfg->users);
		string dest = cfg->dest || "", target = cfg->target || "", destcfg = cfg->destcfg || "";

		//Variable management. Note that these are silent, so commands may want to pair
		//these with public messages. (Silence is perfectly acceptable for triggers.)
		if (dest == "/set" && sscanf(target, "%[*?A-Za-z0-9:]", string var) && var && var != "")
		{
			string val = set_variable(var, msg, destcfg, cfg->users);
			//Variable names with asterisks are per-user (possibly this, possibly another),
			//and should not be stuffed back into the vars mapping.
			if (!has_value(var, '*')) vars["$" + var + "$"] = val;
			return;
		}

		if (echoable_message cmd = dest == "/chain" && commands[target]) {
			//You know what the chain of command is? It's a chain that I get, and then
			//I BREAK so that nobody else can ever be in command.
			if (cfg->chaindepth) return; //For now, no chaining if already chaining - hard and fast rule.
			//Note that cfg is largely independent in the chained-to command; the
			//only values retained are the chaindepth itself, and the "current user"
			//(normally the one who invoked it). Everything else - voice selection,
			//destination, etc - is reset to defaults as per the normal start of a
			//command. This does mean that a "User Vars" with no keyword will carry,
			//where one with a keyword won't. Unsure if this is good or bad.
			_send_recursive(person, cmd, vars | (["%s": destcfg]),
				(["users": (["": cfg->users[""]]), "chaindepth": cfg->chaindepth + 1]));
			return;
		}

		if (msg == "") return; //All other message destinations make no sense if there's no message.

		if (dest == "/web")
		{
			if (target == "") return; //Attempting to send to a borked destination just silences it
			send_private_message(target - "@", msg, destcfg);
			return; //Nothing more to send here.
		}

		//Whispers are currently handled with a command prefix. The actual sending
		//is done via twitch_apis.pike which hooks the slash commands.
		if (dest == "/w") prefix = sprintf("%s %s %s", dest, target, prefix);
		//Any other destination, just send it to open chat (there used to be a facility
		//for sending to other channels, but this is no longer the case).

		//Wrap to 500 characters to fit inside the Twitch limit
		array msgs = ({ });
		while (sizeof(msg) > 500)
		{
			int pos = 500 - sizeof(prefix);
			while (msg[pos] != ' ' && pos--) ;
			if (!pos) pos = 500 - sizeof(prefix);
			msgs += ({prefix + String.trim(msg[..pos-1])});
			msg = String.trim(msg[pos+1..]);
		}
		msgs += ({prefix + msg});

		if (G->G->send_chat_command) {
			//Attempt to send the message(s) via the Twitch APIs if they have slash commands
			//Any that can't be sent that way will be sent the usual way.
			msgs = filter(msgs, G->G->send_chat_command, this, voice);
			if (!sizeof(msgs)) return;
		}
		mapping tags = ([]);
		if (dest == "/reply") tags->reply_parent_msg_id = target;
		if (cfg->callback) {
			//Provide a nonce for the messages, so we call the callback later.
			//Note that the vars could be mutated between here and the callback,
			//so we copy them. Note also that we'll use the same nonce for them
			//all, and only call the callback once.
			string nonce = sprintf("stillebot-%d", ++G->G->nonce_counter);
			tags->client_nonce = nonce;
			nonce_callbacks[nonce] = ({cfg->callback, vars | ([])});
		}
		if (voice == (string)G->G->bot_uid) voice = 0; //Use the intrinsic connection if possible.
		if (objectp(irc_connections[voice])) irc_connections[voice]->send(name, msgs[*], tags);
		else {
			if (!arrayp(irc_connections[voice])) spawn_task(voice_enable(voice, name, tags));
			irc_connections[voice] += msgs;
		}
	}

	//Send any sort of echoable message.
	//The vars will be augmented by channel variables, and can be changed in flight.
	//NOTE: To specify a default destination but allow it to be overridden, just wrap
	//the entire message up in another layer: (["message": message, "dest": "..."])
	//NOTE: Messages are a hybrid of a tree and a sequence. Attributes apply to the
	//tree (eg setting a dest applies it to that branch, and setting a delay will
	//defer sending of that entire subtree), but vars apply linearly, EXCEPT that
	//changes apply at time of sending. This creates a minor wart in the priority of
	//variables; normally, something in the third arg takes precedence over a channel
	//var of the same name, but if the message is delayed, the inverse is true. This
	//should never actually affect anything, though, as vars should contain things
	//like "%s", and channel variables are like "$foo$".
	//NOTE: Variables should be able to be used in any user-editable text. This means
	//that all messages involving user-editable text need to come through send(), and
	//any that don't should be considered buggy.
	//If the ID of the message is needed, pass a callback (note that this is intended
	//for single-message sends, and if multiple messages are sent, it will only be
	//called once). Example: void cb(mapping vars, mapping params) --> params->id is
	//the message ID that just got sent.
	void send(mapping person, echoable_message message, mapping|void vars, function|void callback)
	{
		if (!is_active) Stdio.append_file("inactivebot.log", sprintf(#"==================\n%sInactive bot sending message:\nperson %O\nmessage %O\nvars %O\n%s\n",
			ctime(time()), person, message, vars, describe_backtrace(backtrace())));
		vars = get_channel_variables(person->uid) | (vars || ([]));
		vars["$$"] = person->displayname || person->user;
		vars["{uid}"] = (string)person->uid; //Will be "0" if no UID known
		_send_with_catch(person, message, vars, (["callback": callback, "users": (["": (string)person->uid])]));
	}

	//Expand all channel variables, except for {participant} which usually won't
	//make sense anyway. If you want $$ or %s or any of those, provide them in the
	//second parameter; otherwise, just expand_variables("Foo is $foo$.") is enough.
	string expand_variables(string text, mapping|void vars, mapping|void users)
	{
		vars = get_channel_variables() | (vars || ([]));
		return _substitute_vars(text, vars, ([]), users || ([]));
	}

	__async__ void record_raid(int fromid, string fromname, int toid, string toname, int|void ts, int|void viewers)
	{
		write("Detected a raid: %O %O %O %O %O\n", fromid, fromname, toid, toname, ts);
		if (!is_active) return;
		if (!ts) ts = time();
		//JavaScript timestamps seem to be borked (given in ms instead of seconds).
		//Real timestamps won't hit this threshold until September 33658. At some
		//point close to that date (!), adjust this threshold.
		else if (ts > 1000000000000) ts /= 1000;
		if (!fromid) fromid = await(get_user_id(fromname));
		if (!toid) toid = await(get_user_id(toname));
		raidwatch(fromid, sprintf("%s raided %s", fromname, toname));
		await(G->G->DB->add_raid(fromid, toid, ([
			"time": ts,
			"from": fromname, "to": toname,
			"viewers": undefinedp(viewers) ? -1 : (int)viewers,
		])));
	}

	mapping subbomb_ids = ([]);
	void irc_message(string type, string chan, string msg, mapping params) {
		mapping(string:mixed) person = gather_person_info(params, msg);
		if (person->uid && person->badges) user_badges[person->uid] = person->badges;
		if (!is_active) return;
		mapping responsedefaults;
		//For some unknown reason, certain types of notification come through
		//as PRIVMSG when they would more logically be a NOTICE. They're usually
		//suppressed from the default chat view, but are visible to bots.
		if (params->user == "jtv" && type == "PRIVMSG") type = "NOTICE";
		switch (type)
		{
			case "NOTICE": case "USERNOTICE": switch (params->msg_id)
			{
				case "unrecognized_cmd": werror("NOTICE: %O\n", msg); break; //The message already says "Unrecognized command"
				case "slow_on": case "slow_off": break; //Channel is now/no longer in slow mode
				case "emote_only_on": case "emote_only_off": break; //Channel is now/no longer in emote-only mode
				case "subs_on": case "subs_off": break; //Channel is now/no longer in sub-only mode
				case "followers_on": case "followers_off": break; //Channel is now/no longer in follower-only mode (regardless of minimum time)
				case "followers_on_zero": break; //Regardless? Not quite; if it's zero-second followers-only mode, it's separate.
				case "msg_duplicate": case "msg_slowmode": case "msg_timedout": case "msg_banned": case "msg_requires_verified_phone_number":
					/* Last message wasn't sent, for some reason. There seems to be no additional info in the tags.
					- Your message was not sent because it is identical to the previous one you sent, less than 30 seconds ago.
					- This room is in slow mode and you are sending messages too quickly. You will be able to talk again in %d seconds.
					- You are banned from talking in %*s for %d more seconds.
					All of these indicate that the most recent message wasn't sent. Is it worth trying to retrieve that message?
					*/
					break;
				case "ban_success": break; //Just banned someone. Probably only a response to an autoban.
				case "raid": //Incoming raids already get announced and we don't get any more info
				{
					//Stdio.append_file("incoming_raids.log", sprintf("%s Debug incoming raid: chan %s user %O params %O\n",
					//	ctime(time())[..<1], name, person->displayname, params));
					//NOTE: The destination "room ID" might not remain forever.
					//If it doesn't, we'll need to get the channel's user id instead.
					raiders[(int)params->user_id] = time();
					record_raid((int)params->user_id, person->displayname,
						(int)params->room_id, name[1..], (int)params->tmi_sent_ts,
						(int)params->msg_param_viewerCount);
					trigger_special("!raided", person, (["{viewers}": params->msg_param_viewerCount]));
					break;
				}
				case "unraid": break; //Raid has been cancelled, nothing to see here.
				case "rewardgift": //Used for special promo messages eg "so-and-so's cheer just gave X people a bonus emote"
				{
					//write("DEBUG REWARDGIFT: chan %s disp %O user %O params %O\n",
					//	name, person->displayname, person->user, params);
					break;
				}
				case "sub": {
					string tier = subtier(params->msg_param_sub_plan);
					Stdio.append_file("subs.log", sprintf("\n%sDEBUG SUB: chan %s person %O params %O\n", ctime(time()), name, person->user, params)); //Where is the multimonth info?
					trigger_special("!sub", person, ([
						"{tier}": tier,
						"{multimonth}": params->msg_param_multimonth_duration || "1",
						//There's also msg_param_multimonth_tenure - what happens when they get announced? Does duration remain and tenure count up?
					]));
					event_notify("subscription", this, "sub", person, tier, 1, params, "");
					break;
				}
				case "resub": {
					string tier = subtier(params->msg_param_sub_plan);
					Stdio.append_file("subs.log", sprintf("\n%sDEBUG RESUB: chan %s person %O params %O\n", ctime(time()), name, person->user, params)); //Where is the multimonth info?
					trigger_special("!resub", person, ([
						"{tier}": tier,
						"{months}": params->msg_param_cumulative_months,
						"{streak}": params->msg_param_streak_months || "",
						"{multimonth}": params->msg_param_multimonth_duration || "1", //Ditto re tenure
						"{msg}": msg, "{msgid}": params->id || "",
					]));
					event_notify("subscription", this, "resub", person, tier, 1, params, msg);
					break;
				}
				case "giftpaidupgrade": break; //Pledging to continue a subscription (first introduced for the Subtember special in 2018, and undocumented)
				case "anongiftpaidupgrade": break; //Ditto but when the original gift was anonymous
				case "primepaidupgrade": break; //Similar to the above - if you were on Prime but now pledge to continue, which could be done half price Subtember 2019.
				case "standardpayforward": break; //X is paying forward the Gift they got from Y to Z!
				case "communitypayforward": break; //X is paying forward the Gift they got from Y to the community!
				case "viewermilestone": switch (params->msg_param_category) {
					case "watch-streak": //"X sparked a watch streak!" params->msg_param_category == "watch-streak", also has a msg_param_value == months
						trigger_special("!watchstreak", person, ([
							"{months}": params->msg_param_value,
							"{reward}": params->msg_param_copoReward,
						]));
						break;
					default: break;
				}
				break;
				case "subgift":
				{
					string tier = subtier(params->msg_param_sub_plan);
					Stdio.append_file("subs.log", sprintf("\n%sDEBUG SUBGIFT: chan %s id %O origin %O bomb %d\n", ctime(time()), name, params->id, params->msg_param_origin_id, subbomb_ids[params->msg_param_origin_id]));
					//Note: Sub bombs get announced first, followed by their individual gifts.
					//It may be that the msg_param_origin_id is guaranteed unique, but in case
					//it can't, we count down the messages as we see them.
					if (subbomb_ids[params->msg_param_origin_id] > 0) {
						subbomb_ids[params->msg_param_origin_id]--;
						params->came_from_subbomb = "1"; //Hack in an extra parameter
					}
					/*write("DEBUG SUBGIFT: chan %s disp %O user %O mon %O recip %O multi %O\n",
						name, person->displayname, person->user,
						params->msg_param_months, params->msg_param_recipient_display_name,
						params->msg_param_gift_months);*/
					trigger_special("!subgift", person, ([
						"{tier}": tier,
						"{months}": params->msg_param_cumulative_months || params->msg_param_months || "1",
						"{streak}": params->msg_param_streak_months || "",
						"{recipient}": params->msg_param_recipient_display_name,
						"{multimonth}": params->msg_param_gift_months || "1",
						"{from_subbomb}": params->came_from_subbomb || "0",
					]));
					//Other params: login, user_id, msg_param_recipient_user_name, msg_param_recipient_id,
					//msg_param_sender_count (the total gifts this person has given in this channel)
					//Remember that all params are strings, even those that look like numbers
					event_notify("subscription", this, "subgift", person, tier, 1, params, "");
					break;
				}
				case "submysterygift":
				{
					string tier = subtier(params->msg_param_sub_plan);
					Stdio.append_file("subs.log", sprintf("\n%sDEBUG SUBBOMB: chan %s person %O count %O id %O\n", ctime(time()), name, person, params->msg_param_mass_gift_count, params->msg_param_origin_id));
					subbomb_ids[params->msg_param_origin_id] += (int)params->msg_param_mass_gift_count;
					/*write("DEBUG SUBGIFT: chan %s disp %O user %O gifts %O multi %O\n",
						name, person->displayname, person->user,
						params->msg_param_mass_gift_count,
						params->msg_param_gift_months);*/
					trigger_special("!subbomb", person, ([
						"{tier}": tier,
						"{gifts}": params->msg_param_mass_gift_count,
						//TODO: See if this can actually happen, and if not, drop it
						"{multimonth}": params->msg_param_gift_months || "1",
					]));
					event_notify("subscription", this, "subbomb", person, tier,
						(int)params->msg_param_mass_gift_count, params, "");
					break;
				}
				case "extendsub":
				{
					//Person has pledged to continue a subscription? Not sure.
					//"msg_param_cumulative_months": "7",
					//"msg_param_sub_benefit_end_month": "5",
					//"msg_param_sub_plan": "1000",
					break;
				}
				case "bitsbadgetier":
				{
					trigger_special("!cheerbadge", person, ([
						"{level}": params->msg_param_threshold,
					]));
					break;
				}
				case "announcement": //The /announce command
					//Has a msg_param_color that is either PRIMARY or a colour word eg "PURPLE"
					string pfx = sprintf("** %s ** ", name);
					#ifdef __NT__
					int wid = 80 - sizeof(pfx);
					#else
					int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
					#endif
					msg = string_to_utf8(msg) + " "; //Trailing space improves wrapping with %= mode
					log("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
					break;
				case "charitydonation":
					trigger_special("!charity", person, ([
						"{amount}": params->msg_param_donation_amount + " " + params->msg_param_donation_currency,
						"{msgid}": params->id || "", //Does this happen? Is there a message at all?
					]));
					break;
				default: werror("Unrecognized %s with msg_id %O on channel %s\n%O\n%O\n",
					type, params->msg_id, name, params, msg);
					Stdio.append_file("notice.log", sprintf("%sUnknown %s %s %s %O\n", ctime(time()), type, chan, msg, params));
			}
			break;
			case "WHISPER": responsedefaults = (["dest": "/w", "target": "$$"]); //fallthrough
			case "PRIVMSG":
			{
				request_rate_token(lower_case(person->nick), name); //Do we need to lowercase it?
				if (sscanf(msg, "\1ACTION %s\1", msg)) person->is_action_msg = 1;
				//For some reason, whispers show up with "/me" at the start, not "ACTION".
				else if (sscanf(msg, "/me %s", msg)) person->is_action_msg = 1;
				if (person->badges->?broadcaster && sscanf(msg, "fakecheer%d", int bits) && bits) {
					//Allow the broadcaster to "fakecheer100" (start of message only) to
					//test alerts etc. Note that "fakecheer-100" can also be done, if that
					//is ever useful to your testing. It may confuse things though!
					params->bits = (string)bits;
					person->bits = bits;
				}
				if (type != "WHISPER" || config->whispers_as_commands) //Whispers aren't normally counted as commands
					handle_command(person, msg, responsedefaults, params);
				if (params->bits && (int)params->bits) {
					event_notify("cheer", this, person, (int)params->bits, params, msg);
					trigger_special("!cheer", person, (["{bits}": params->bits, "{msg}": msg, "{msgid}": params->id || ""]));
				}
				msg = person->displayname + (person->is_action_msg ? " " : ": ") + msg;
				string pfx = sprintf("[%s%s] ", type == "PRIVMSG" ? "" : type, name);
				#ifdef __NT__
				int wid = 80 - sizeof(pfx);
				#else
				int wid = (Stdio.stdin->tcgetattr()->?columns || 1024) - sizeof(pfx);
				#endif
				if (person->badges->?_mod) msg = "\u2694 " + msg;
				msg = string_to_utf8(msg) + " "; //Trailing space improves wrapping with %= mode
				log("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
				break;
			}
			//The delete-msg hook has person (the one who triggered it),
			//target (the login who got purged), and msgid.
			//The very similar delete-msgs hook has person (ditto) and
			//target (the *user id* who got purged), which may be null.
			//(If target is null, all chat got cleared ("/clear").)
			//When anyone's chat gets deleted, that user gets removed from
			//the participant list, so autobanned people won't ever get
			//acknowledged accidentally.
			case "CLEARMSG":
				event_notify("deletemsg", this, person, params->login, params->target_msg_id);
				G_G_("participants", name[1..], params->login)->lastnotice = 0;
				break;
			case "CLEARCHAT":
				G_G_("banned_list", (string)userid)->stale = 1; //When anyone's banned/timed out, drop the banned users cache
				event_notify("deletemsgs", this, person, params->target_user_id);
				if (params->target_user_id) get_user_info(params->target_user_id)->then() {
					mapping user = __ARGS__[0];
					G_G_("participants", name[1..], user->login)->lastnotice = 0;
					trigger_special("!timeout", ([
						"nick": user->login, "user": user->login,
						"uid": (int)user->id,
						"displayname": user->display_name,
					]),
					(["{ban_duration}": params->ban_duration]));
				};
				break;
			case "USERSTATE": { //Sent after our messages. The only ones we care about are those with nonces we sent.
				array callback = m_delete(nonce_callbacks, params->client_nonce);
				if (callback) callback[0](callback[1], params);
				break;
			}
			default: werror("Unknown message type %O on channel %s\n", type, name);
		}
	}

	//Requires a UTF-8 encoded byte string (not Unicode text). May contain colour codes.
	void log(strict_sprintf_format fmt, sprintf_args ... args)
	{
		if (config->chatlog) write(fmt, @args);
	}

	void trigger_special(string special, mapping person, mapping info) {
		if (!is_active) return;
		echoable_message response = commands[special];
		if (!response) return;
		//if (has_value(info, 0)) werror("DEBUG: Special %O got info %O\n", special, info); //Track down those missing-info errors
		send(person, response, info);
	}

	int _cached_error_count, _cached_error_count_time; //Cache gets discarded on code reload, no big deal
	__async__ void report_error(string level, string message, string|void context) {
		//NOTE: This can currently be called on a non-active bot. Normally there should
		//be no way to trigger errors that aren't already restricted to active bots, but
		//if there is something, we need to see the error reported.
		string msgid;
		await(G->G->DB->mutate_config(userid, "errors") {
			__ARGS__[0]->msglog += ({([
				"id": msgid = (string)++__ARGS__[0]->nextid,
				"datetime": time(0),
				"level": level,
				"message": message,
				"context": context || "",
			])});
			++_cached_error_count; //Cache staleness is not affected here - we just assume an increment.
		});
		G->G->websocket_types->chan_errors->update_one("#" + userid, msgid);
	}

	//Count the number of error/warning messages still pending.
	//If cacheable is 1 and we have a recent figure, it'll use that (might not be entirely accurate).
	__async__ int error_count(int(1bit) cacheable) {
		if (cacheable && _cached_error_count_time > time() - 600) return _cached_error_count;
		mapping err = await(G->G->DB->load_config(userid, "errors"));
		_cached_error_count_time = time();
		if (err->msglog && sizeof(err->msglog)) {
			array msglog = err->msglog;
			if (err->lastread) {
				if ((int)err->lastread >= (int)msglog[-1]->id) return _cached_error_count = 0; //Common case: All messages read.
				//In theory this could binary search for the right ID, but in practice,
				//not worth the hassle. The most common case will be that all messages
				//have been read, or none have, both of which will be quick.
				foreach (msglog; int i; mapping msg) {
					if ((int)msg->id > (int)err->lastread) {
						msglog = msglog[i..];
						break;
					}
				}
			}
			multiset vis = err->visibility ? (multiset)err->visibility : (<"ERROR", "WARN">);
			return _cached_error_count = `+(@vis[err->msglog->level[*]]);
		}
		return _cached_error_count = 0;
	}
}

void irc_message(string type, string chan, string msg, mapping attrs) {
	object channel = G->G->irc->channels[chan];
	if (channel) channel->irc_message(type, chan, msg, attrs);
}

void irc_closed(mapping options) {
	::irc_closed(options);
	if (options->voiceid) m_delete(irc_connections, options->voiceid);
}

@export: object connect_to_channel(string|int user) {
	return get_user_info(user, intp(user) ? "id" : "login")->then() {
		G->G->DB->save_sql(#"insert into stillebot.botservice values (:id, null, :login, :display_name)
			on conflict (twitchid) do update set deactivated = null", __ARGS__[0]);
	};
}

@hook_channel_online: int connected(string chan, int uptime, int chanid) {
	object channel = G->G->irc->id[chanid];
	if (channel) channel->channel_online(uptime);
}

void session_cleanup() {
	//Go through all HTTP sessions and dispose of old ones
	G->G->http_session_cleanup = call_out(session_cleanup, 86400);
	G->G->DB->query_rw("delete from stillebot.http_sessions where active < now () - '7 days'::interval");
}

__async__ void http_request(Protocols.HTTP.Server.Request req)
{
	req->misc->session = await(G->G->DB->load_session(req->cookies->session));
	if (string dest = req->request_type == "GET" && req->misc->session->autoxfr) {
		//This check shouldn't be necessary; the session value can't easily be set except on this one host.
		string host = deduce_host(req->request_headers);
		if (host == "sikorsky.rosuav.com") {
			req->response_and_finish(redirect("https://" + dest + req->full_query));
			return;
		}
		//Otherwise carry on as if the autoxfr marker wasn't there. (This also applies to non-GET requests.)
	}
	//TODO maybe: Refresh the login token. Currently the tokens don't seem to expire,
	//but if they do, we can get the refresh token via authcookie (if present).
	[function handler, array args] = find_http_handler(req->not_query);
	//If we receive URL-encoded form data, assume it's UTF-8.
	if (req->request_headers["content-type"] == "application/x-www-form-urlencoded" && mappingp(req->variables))
	{
		//NOTE: We currently don't UTF-8-decode the keys; they should usually all be ASCII anyway.
		foreach (req->variables; string key; mixed value) catch {
			if (stringp(value)) req->variables[key] = utf8_to_string(value);
		};
	}
	mapping|string resp;
	if (mixed ex = handler && catch {
		mixed h = handler(req, @args); //Either a promise or a result (mapping/string).
		resp = objectp(h) && h->on_await ? await(h) : h; //Await if promise, otherwise we already have it.
	}) {
		werror("HTTP handler crash: %O\n", req->not_query);
		werror(describe_backtrace(ex));
		resp = (["error": 500, "data": "Internal server error\n", "type": "text/plain; charset=\"UTF-8\""]);
	}
	if (!resp)
	{
		//werror("HTTP request: %s %O %O\n", req->request_type, req->not_query, req->variables);
		//werror("Headers: %O\n", req->request_headers);
		resp = ([
			"data": "No such page.\n",
			"type": "text/plain; charset=\"UTF-8\"",
			"error": 404,
		]);
	}
	if (stringp(resp)) resp = (["data": resp, "type": "text/plain; charset=\"UTF-8\""]);
	//All requests should get to this point with a response.

	//As of 20190122, the Pike HTTP server doesn't seem to handle keep-alive.
	//The simplest fix is to just add "Connection: close" to all responses.
	if (!resp->extra_heads) resp->extra_heads = ([]);
	resp->extra_heads->Connection = "close";
	resp->extra_heads["Access-Control-Allow-Origin"] = "*";
	resp->extra_heads["Access-Control-Allow-Private-Network"] = "true";
	mapping sess = req->misc->session;
	if (sizeof(sess) && !sess->fake) {
		if (!sess->cookie) sess->cookie = await(G->G->DB->generate_session_cookie());
		G->G->DB->save_session(sess);
		string host = deduce_host(req->request_headers);
		resp->extra_heads["Set-Cookie"] = "session=" + sess->cookie + "; Path=/; Max-Age=604800; SameSite=Lax; HttpOnly"
			+ (has_suffix(host, "mustardmine.com") ? "; Domain=mustardmine.com" : "");
	}
	req->response_and_finish(resp);
	// *********** Current issue under investigation ************ //
	//For some reason, open files are accumulating, sometimes reaching critical levels,
	//without triggering garbage collection. This MAY be related to HTTP requests, but
	//even if it's not, this is a place that gets hit fairly often, so we'll do the
	//collection here.
	gc();
}

void http_handler(Protocols.HTTP.Server.Request req) {spawn_task(http_request(req));}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn)
{
	if (function f = bounce(this_function)) {f(frm, conn); return;}
	//Depending on timings, we might not have loaded the session yet. Hold all messages till we have.
	if (arrayp(conn->session)) {conn->session += ({frm}); return;}
	//Check for an expired session. It's highly unlikely that a websocket will be idle for a week
	//without anything pinging the session, but much more likely that the user logs out in another
	//tab, which should kick the websocket's session and login.
	//Note that this is the only place we reload the session. Changes to an existing session are not
	//currently picked up. That means, if you log in again (eg to add scopes), the token will most
	//likely be broken. This may require redefining "http_sessions_deleted" to "session_login_changed"
	//or something, and using it for both. Reconsider this if tokens get removed from session though.
	if (conn->session->user && !conn->session->fake && G->G->http_sessions_deleted[conn->session->cookie]) {
		//This is only relevant if the user's logged in; otherwise, I don't think anyone will
		//much care if a still-connected socket remains. We then keep a list of removed sessions.
		string cookie = conn->session->cookie;
		conn->session = ({frm});
		G->G->DB->load_session(cookie)->then() { //TODO: Deduplicate, again
			if (sizeof(__ARGS__[0]) < 2) {
				//No active session. Kick the socket.
				conn->sock->send_text(Standards.JSON.encode(([
					"cmd": "*DC*",
					"error": "Logged out.",
				])));
				return;
			}
			//Otherwise, we have a session, so go ahead and use it (freshly loaded).
			//And we can drop it from the deleted list, so we don't keep checking.
			array pending = conn->session;
			conn->session = __ARGS__[0];
			m_delete(G->G->http_sessions_deleted, conn->session->cookie);
			ws_msg(pending[*], conn);
		};
	}
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	if (!stringp(data->cmd)) return;
	if (data->cmd == "init")
	{
		if (string other = !is_active && get_active_bot()) {
			//If we are definitely not active and there's someone who is,
			//send the request over there instead. Browsers don't all follow
			//302 redirects for websockets, and even if they did, session and
			//login information would be lost (since the websocket would be
			//going to an unrelated origin). So instead, we notify the client
			//of the situation. This DOES mean that we have to give the JS the
			//session cookie, but that's only a minor security issue - you'd
			//have to know how to retrieve that, and then use it to gain access
			//to the real server. In theory, the transfer cookie could be some
			//completely separate identifier, which we first stash into the DB
			//somewhere before notifying the client; this would be valid for
			//some extremely short duration, after which the client would be
			//told "redirect back to default".
			conn->sock->send_text(Standards.JSON.encode(([
				"cmd": "*DC*",
				"error": "This bot is not active, see other",
				"redirect": other,
				"xfr": conn->session->cookie,
			])));
			conn->sock->close();
			return;
		}
		//Initialization is done with a type and a group.
		//The type has to match a module ("inherit websocket_handler")
		//The group has to be a string or integer.
		if (conn->type) return; //Can't init twice
		object handler = G->G->websocket_types[data->type];
		if (!handler) return; //Ignore any unknown types.
		//If this socket was redirected from a different node, it will include a
		//session transfer cookie. (See above; currently, a "transfer cookie" is
		//just the session cookie itself, but that may change.)
		if (stringp(data->xfr) && data->xfr != conn->session->cookie) {
			conn->session = ({frm});
			G->G->DB->load_session(data->xfr)->then() { //TODO: Deduplicate with below?
				array pending = conn->session;
				conn->session = __ARGS__[0];
				ws_msg(pending[*], conn);
			};
			return;
		}
		[object channel, string grp] = handler->split_channel(data->group);
		//Previously, this transformation would transform to logins.
		//if (channel) data->group = grp + channel->name;
		if (channel) data->group = grp + "#" + channel->userid;
		//NOTE: Don't save the channel object itself here, in case code gets
		//updated. We want to fetch up the latest channel object whenever it's
		//needed. But it'll be useful to synchronize the group, regardless of
		//whether it was requested by name or ID.
		if (string err = handler->websocket_validate(conn, data)) {
			conn->sock->send_text(Standards.JSON.encode((["cmd": "*DC*", "error": err])));
			conn->sock->close();
			return;
		}
		string group = (stringp(data->group) || intp(data->group)) ? data->group : "";
		conn->type = data->type; conn->group = group;
		handler->websocket_groups[group] += ({conn->sock});
		string uid = conn->session->user->?id;
		if (object h = uid && uid != "0" && uid != "3141592653589793" && G->G->websocket_types->prefs) {
			//You're logged in. Provide automated preference synchronization.
			h->websocket_groups[conn->prefs_uid = uid] += ({conn->sock});
			call_out(h->websocket_cmd_prefs_send, 0, conn, ([]));
		}
	}
	string type = has_prefix(data->cmd||"", "prefs_") ? "prefs" : conn->type;
	if (object handler = G->G->websocket_types[type]) handler->websocket_msg(conn, data);
	else write("Message to unknown type %O: %O\n", type, data);
}

void ws_close(int reason, mapping conn)
{
	if (function f = bounce(this_function)) {f(reason, conn); return;}
	if (object handler = G->G->websocket_types[conn->type])
	{
		handler->websocket_msg(conn, 0);
		handler->websocket_groups[conn->group] -= ({conn->sock});
	}
	if (object handler = conn->prefs_uid && G->G->websocket_types->prefs) //Disconnect from preferences
	{
		handler->websocket_msg(conn, 0);
		handler->websocket_groups[conn->prefs_uid] -= ({conn->sock});
	}
	m_delete(conn, "sock"); //De-floop
}

void ws_handler(array(string) proto, Protocols.WebSocket.Request req)
{
	if (function f = bounce(this_function)) {f(proto, req); return;}
	if (req->not_query != "/ws")
	{
		req->response_and_finish((["error": 404, "type": "text/plain", "data": "Not found"]));
		return;
	}
	//Lifted from Protocols.HTTP.Server.Request since, for some reason,
	//this isn't done for WebSocket requests.
	if (req->request_headers->cookie)
		foreach (MIME.decode_headerfield_params(req->request_headers->cookie); ; ADT.OrderedMapping m)
			foreach (m; string key; string value)
				if (value) req->cookies[key] = value;
	//End lifted from Pike's sources
	string remote_ip = req->get_ip(); //Not available after accepting the socket for some reason
	Protocols.WebSocket.Connection sock = req->websocket_accept(0);
	mapping conn = (["sock": sock, //Minstrel Hall style floop
		"session": ({ }), //Queue of requests awaiting the session
		"remote_ip": remote_ip,
		"hostname": deduce_host(req->request_headers),
	]);
	sock->set_id(conn);
	G->G->DB->load_session(req->cookies->session)->then() {
		array pending = conn->session;
		conn->session = __ARGS__[0];
		if (sizeof(pending)) ws_msg(pending[*], conn);
	};
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
}

//FIXME: Start with this null once initial testing is done. Hard-coding this saves a couple of seconds each startup.
@retain: string condid = "64e2637e-f5cf-43d6-a7ae-308fb623a0d3";
constant CONDUIT_KICK_TIMEOUT = 60; //If we haven't heard from the server in this many seconds, kick the conduit and restart.
multiset recent_raids = (<>);
__async__ void conduit_message(Protocols.WebSocket.Frame frm, mapping conn) {
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	string type = mappingp(data) && data->metadata->?message_type;
	//If it's been too long since a message came in, kick the conduit and start over
	remove_call_out(G->G->conduit_fallen_over);
	G->G->conduit_fallen_over = call_out(setup_conduit, CONDUIT_KICK_TIMEOUT);
	//if (type == "session_keepalive") werror("Got WS msg: %O\n", data);
	switch (type) {
		case "session_welcome": { //New socket established. Associate with shard.
			mapping ret = await(twitch_api_request("https://api.twitch.tv/helix/eventsub/conduits/shards", ([]), ([
				"authtype": "app", "method": "PATCH", "json": ([
					"conduit_id": condid, "shards": ({([
						"id": "0", "transport": ([
							"method": "websocket",
							"session_id": G->G->active_conduit_shard_id = conn->shard_id = data->payload->session->id,
						]),
					])}),
				]),
			])));
			werror("* Conduit notifications active *\n"); //TODO: Check the response to make sure it really is successful
			break;
		}
		case "session_keepalive":
			//If another instance has added itself as the active shard, disconnect this one on next notification.
			if (conn->shard_id != G->G->active_conduit_shard_id) {
				werror("CLOSING OLD CONDUIT SHARD %O b/c %O active\n", conn->shard_id, G->G->active_conduit_shard_id);
				conn->sock->close();
				return;
			}
			break;
		case "session_reconnect": {
			Stdio.append_file("conduit_reconnect.log", sprintf("%sRECONNECT: %O\n", ctime(time()), data));
			setup_conduit(data->payload->?session->?reconnect_url);
			break;
		}
		case "notification": { //Incoming notification. Send it to the appropriate module.
			mapping event = data->payload->?event; if (!mappingp(event)) return;
			string type = data->metadata->subscription_type + "=" + data->metadata->subscription_version;
			if (type == "channel.raid=1") {
				//Raids are a bit hacky. When one tracked channel raids another, this triggers
				//the same raid notification both as an outgoing and an incoming raid. Sometimes
				//we need to deduplicate. One option would be to use data->payload->subscription
				//to figure out whether we hooked this as an incoming or outgoing event, and send
				//the event on to modules separately for the two; the other option is to dedup
				//events based on the two IDs.
				string key = event->from_broadcaster_user_id + ":" + event->to_broadcaster_user_id;
				if (recent_raids[key]) {werror("Ignoring duplicate raid signal %O\n", key); return;}
				recent_raids[key] = 1;
				call_out(m_delete, 30, recent_raids, key);
			}
			object channel = G->G->irc->id[(int)event->broadcaster_user_id]; //Some events (eg raid) won't have a single channel, so this will be null
			werror("Hook %O channel %O\n", type, channel->?login);
			foreach (G->G->eventhooks[type] || ([]); string name; function func)
				if (mixed ex = name != "" && catch (func(channel, event)))
					werror("Error in hook %s->%s: %s", name, event, describe_backtrace(ex));
			break;
		}
		default: werror("Got unknown WS message: %O\n", data); break;
	}
}

void conduit_closed(int reason, mapping conn) {werror("CONDUIT CONNECTION GONE: %O\n", conn); m_delete(conn, "sock");}

__async__ void setup_conduit(string|void url) {
	if (!condid) { // or if something fails?
		mapping cond = await(twitch_api_request("https://api.twitch.tv/helix/eventsub/conduits", ([]), (["authtype": "app"])));
		if (!sizeof(cond->data)) {
			mapping conduit = await(twitch_api_request("https://api.twitch.tv/helix/eventsub/conduits", ([]), ([
				"authtype": "app", "json": (["shard_count": 1]),
			])));
			
		} else condid = cond->data[0]->id;
	}
	Protocols.WebSocket.Connection conn = Protocols.WebSocket.Connection();
	conn->connect(url || "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=" + (CONDUIT_KICK_TIMEOUT - 5)); //Will establish TCP and TLS synchronously, then HTTP and WS asynchronously
	conn->set_id((["sock": conn]));
	conn->onmessage = conduit_message;
	conn->onclose = conduit_closed;
}

void establish_hook_notification(string|int channelid, string hook, mapping|void cond) {
	//TODO: If we don't have a condid yet, queue the request
	//HACK: If the channelid is a string, and cond is specified, they are allowed to be
	//desynchronized. This can be useful but be cautious with it.
	if (G->G->eventhooks[hook][?""][?(string)channelid]) return; //Already got the subscription.
	sscanf(hook, "%s=%s", string type, string version);
	twitch_api_request("https://api.twitch.tv/helix/eventsub/subscriptions", ([]), ([
		"authtype": "app",
		"json": ([
			"type": type, "version": version,
			"condition": cond || (["broadcaster_user_id": (string)channelid]),
			"transport": ([
				"method": "conduit",
				"conduit_id": condid,
			]),
		]),
		"return_errors": 1,
	]));
}

@hook_database_settings: void kick_when_inactive(mapping settings) {
	//Delay this till we have access to credentials
	if (!G->G->cheeremotes) twitch_api_request("https://api.twitch.tv/helix/bits/cheermotes")->then() {
		mapping c = G->G->cheeremotes = ([]);
		foreach (__ARGS__[0]->data, mapping em) c[lower_case(em->prefix)] = em;
		//Hack to enable fakecheers to look like emotes
		c->fakecheer = c->cheerwhal;
	};
	int now_active = is_active_bot();
	werror("kick_when_inactive: was %O now %O\n", is_active, now_active);
	if (now_active && !is_active) call_out(reconnect, 0); //Just become active? Make sure we're connected.
	is_active = now_active;
	string other = !is_active && get_active_bot();
	if (!other) return; //We're active (or uncertain), don't kick clients.
	foreach (G->G->websocket_groups; string type; mapping groups)
		foreach (groups; string group; array socks)
			foreach (socks, object sock) {
				mapping conn = sock->query_id();
				if (!conn || !mappingp(conn->session)) continue;
				sock->send_text(Standards.JSON.encode(([
					"cmd": "*DC*",
					"error": "This bot is deactivating, see other",
					"redirect": other,
					"xfr": conn->session->cookie,
				])));
			}
}

//If desired, sharding of the primary connection can be done using the !demo channel's
//assigned voices. This is unnecessary if there are fewer than 20 channels in use, and
//barely necessary for fewer than about 60, but beyond that, becomes more valuable. It
//is also completely unnecessary if the bot has Verified status, but this would need to
//be coded in properly (to allow !demo to still have some example voices).
array(mapping) shard_voices;
__async__ void reconnect() {
	if (!shard_voices) {
		//Fetch up the list of bot shard voices from the demo's available voices
		mapping demo_voices;
		while (1) {
			catch (demo_voices = G->G->DB->load_cached_config(0, "voices"));
			if (demo_voices) break;
			//If there's an exception, most likely the voices haven't been loaded yet.
			//Delay a bit and try again.
			sleep(0.25);
		}
		array voices = values(demo_voices);
		sort((array(int))voices->id, voices);
		foreach (voices; int i; mapping v) if (v->id == (string)G->G->bot_uid) voices[i] = 0;
		shard_voices = ({0}) + (voices - ({0})); //Move the null entry (for intrinsic voice) to the start
	}
	array channels = await(G->G->DB->query_ro(#"
		select stillebot.botservice.twitchid as userid, login, display_name, coalesce(data, '{}') as data
		from stillebot.botservice left join stillebot.config
		on stillebot.botservice.twitchid = stillebot.config.twitchid and keyword = 'botconfig'
		where deactivated is null"));
	if (sizeof(channels)) {
		sort(channels->login, channels); //Default to sorting affabeck by username
		sort(-channels->data->connprio[*], channels);
	}
	mapping irc = (["channels": ([]), "id": ([]), "loading": (<>)]);
	mapping commands = await(G->G->DB->preload_commands(channels->userid));
	foreach (channels, mapping cfg) {
		irc->loading[cfg->userid] = 1;
		object c = channel(cfg, irc->loading, commands[cfg->userid]);
		irc->channels[c->name] = c;
		irc->id[c->userid] = c;
	}
	G->G->irc = irc;
	if (array waiting = m_delete(G->G, "awaiting_irc_loaded")) waiting(); //Notify everyone who's waiting for the channel list.
	channels = filter("#" + channels->login[*]) {return __ARGS__[0][1] != '!';};
	//Deal the channels out into N piles based on available users. Any spares
	//go onto the primary channel. This speeds up initial connection when there
	//are more than 20 channels to connect to, but isn't necessary.
	array shards = Array.transpose(channels / sizeof(shard_voices));
	if (!sizeof(shards)) shards = ({channels}); //If we have fewer channels than voices, connect to them all on the intrinsic voice.
	else shards[0] += channels % sizeof(shard_voices);
	foreach (shards; int i; array chan) {
		irc_connect(([
			"user": i && shard_voices[i]->name,
			"join": chan,
			"capabilities": "membership tags commands" / " ",
			//"verbose": 1, "force_reconnect": 1,
			"shard_id": i && shard_voices[i]->id,
		]))->then() {
			mapping opt = __ARGS__[0]->options;
			werror("IRC now connected: %O --> %O\n", opt->user, opt->join);
			irc_connections[opt->shard_id] = __ARGS__[0];
		}
		->thencatch() {werror("Unable to connect to Twitch:\n%s\n", describe_backtrace(__ARGS__[0]));};
	}
	werror("Now connecting: %O queue %O\n", connection_cache->rosuav, connection_cache->rosuav->queue);
	if (is_active && !G->G->args["no-conduit"]) setup_conduit(); //Asynchronously establish event hooks too
}

@hook_credentials_changed: void kick_voice_on_auth_change(mapping cred) {
	//If the user that just reauthenticated is an active bot voice, reconnect.
	//Note that this comes in two forms depending on whether it's a shard voice
	//or an alternate voice.
	werror("Got credentials for %O/%O\n", cred->userid, cred->login);
	if (cred->userid == G->G->bot_uid || has_value((shard_voices - ({0}))->id, (string)cred->userid)) {
		//If the bot's primary auth has changed, or any of the voices used for sharding, do a full
		//reconnect and reestablish them all.
		werror("Reconnecting due to credentials change for %O/%O\n", cred->userid, cred->login);
		reconnect();
	} else if (object|array conn = m_delete(irc_connections, (string)cred->userid)) {
		//Otherwise, if we're connected to that voice (note that this is also true of shard voices
		//so we need to check for that first), kick the connection and let it be resumed later.
		//Now, things get a bit awkward. If conn is an object, we have a connection, so we need to
		//kick it; but if it's an array, we might be half way through connecting, but that might
		//just fail. For simplicity's sake, I'm going to discard any pending messages in that case,
		//since the most likely cause is that a voice got deauthed; people will just retrigger the
		//messages after reauthing anyway.
		werror("Kicking voice credentials for %O/%O\n", cred->userid, cred->login);
	}
}

void send_message(string chan, string msg) {if (irc_connections[0]) irc_connections[0]->send(chan, msg);}

protected void create(string name)
{
	::create(name);
	add_constant("send_message", send_message);
	G->G->establish_hook_notification = establish_hook_notification;
	G->G->setup_conduit = setup_conduit; //Reestablish after disconnect.
	if (!G->G->irc) G->G->irc = (["channels": ([]), "id": ([]), "loading": (<>)]);
	#if constant(INTERACTIVE)
	return;
	#endif
	is_active = is_active_bot(); //Cache it - we'll check this a lot
	werror("Initializing: active %O\n", is_active);
	if (mixed id = m_delete(G->G, "http_session_cleanup")) remove_call_out(id);
	session_cleanup();
	register_bouncer(ws_handler); register_bouncer(ws_msg); register_bouncer(ws_close);
	G->G->on_botservice_change = reconnect;
	reconnect();
	mapping http = G->G->instance_config;
	if (mixed ex = http->http_address && http->http_address != "" && catch
	{
		int use_https = has_prefix(http->http_address, "https://");
		string listen_addr = "::"; //By default, listen on IPv4 and IPv6
		int listen_port = use_https ? 443 : 80; //Default port from protocol
		sscanf(http->http_address, "http%*[s]://%*s:%d", listen_port); //If one is set for the dest addr, use that
		//Or if there's an explicit listen address/port set, use that.
		if (http->listen_address) {
			string listen = http->listen_address;
			if (sscanf(listen, "http://%s", listen)) use_https = 0; //Use this when encryption is done outside of the bot (no cert here, but external addresses still use https).
			sscanf(listen, "%s:%s", listen_addr, listen);
			sscanf(listen, "%d", listen_port);
		}

		string cert = Stdio.read_file("certificate.pem");
		string cert2 = Stdio.read_file("certificate_local.pem");
		string combined = (cert || "") + (cert2 || ""); //If either cert changes, update both certs and keys
		if (listen_port * -use_https != G->G->httpserver_port_used || combined != G->G->httpserver_certificate)
		{
			//Port or SSL status has changed. Force the server to be restarted.
			if (object http = m_delete(G->G, "httpserver")) http->close();
			G->G->httpserver_port_used = listen_port * -use_https;
			werror("Resetting HTTP server.\n");
		}

		if (G->G->httpserver) G->G->httpserver->callback = http_handler;
		else if (!use_https) G->G->httpserver = Protocols.WebSocket.Port(http_handler, ws_handler, listen_port, listen_addr);
		else
		{
			G->G->httpserver_certificate = combined;
			string key = Stdio.read_file("privkey.pem");
			array certs = cert && Standards.PEM.Messages(cert)->get_certificates();
			string pk = key && Standards.PEM.simple_decode(key);
			//If we don't have a valid PK and cert(s), Pike will autogenerate a cert.
			//TODO: Save the cert? That way, the self-signed could be pinned
			//permanently. Currently it'll be regenned each startup.
			G->G->httpserver = Protocols.WebSocket.SSLPort(http_handler, ws_handler, listen_port, listen_addr, pk, certs);
			//To enable SNI, have another keypair with these names. The above
			//certificate will be used for all connections that do not stipulate
			//a servername found in the local key's CN or SAN.
			key = Stdio.read_file("privkey_local.pem");
			if (key && cert2) {
				pk = Standards.PEM.simple_decode(key);
				certs = Standards.PEM.Messages(cert2)->get_certificates();
				G->G->httpserver->ctx->add_cert(pk, certs);
			}
		}
	})
	{
		werror("NO HTTP SERVER AVAILABLE\n%s\n", describe_backtrace(ex));
		werror("Continuing without.\n");
		//Ensure that we don't accidentally use something unsafe (eg if it's an SSL issue)
		if (object http = m_delete(G->G, "httpserver")) catch {http->close();};
	}
}
