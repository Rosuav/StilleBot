object irc;
string bot_nick;
mapping simple_regex_cache = ([]); //Emptied on code reload.
object substitutions = Regexp.PCRE("(\\$[A-Za-z|]+\\$)|({[a-z_@|]+})");

class IRCClient
{
	inherit Protocols.IRC.Client;
	#if __REAL_VERSION__ < 8.1
	//Basically monkey-patch in a couple of methods that Pike 8.0 doesn't ship with.
	void join_channel(string chan)
	{
	   cmd->join(chan);
	   if (options->channel_program)
	   {
	      object ch = options->channel_program();
	      ch->name = lower_case(chan);
	      channels[lower_case(chan)] = ch;
	   }
	}

	void part_channel(string chan)
	{
	   cmd->part(chan);
	   m_delete(channels, lower_case(chan));
	}
	#endif

	void got_command(string what, string ... args)
	{
		//With the capability "twitch.tv/tags" active, some messages get delivered prefixed.
		//The Pike IRC client doesn't handle the prefixes, and I'm not sure how standardized
		//this concept is (it could be completely Twitch-exclusive), so I'm handling it here.
		//The prefix is formatted as "@x=y;a=b;q=w" with simple key=value pairs. We parse it
		//out into a mapping and pass that along to not_message. Note that we also parse out
		//whispers the same way, even though there's actually no such thing as whisper_notif
		//in the core Protocols.IRC.Client handler - they go through to not_message for some
		//channel (currently "#!whisper", though this may change in the future).
		what = utf8_to_string(what); args[0] = utf8_to_string(args[0]); //TODO: Check if anything ever breaks because of this
		mapping(string:string) attr = ([]);
		if (has_prefix(what, "@"))
		{
			foreach (what[1..]/";", string att)
			{
				sscanf(att, "%s=%s", string name, string val);
				attr[replace(name, "-", "_")] = replace(val || "", "\\s", " ");
			}
			//write(">> %O %O <<\n", args[0], attr);
		}
		sscanf(args[0], "%s :%s", string a, string message);
		array parts = (a || args[0]) / " ";
		if (sizeof(parts) >= 3 && (<"PRIVMSG", "NOTICE", "WHISPER", "USERNOTICE", "CLEARMSG", "CLEARCHAT">)[parts[1]])
		{
			//Send whispers to a pseudochannel named #!whisper
			string chan = parts[1] == "WHISPER" ? "#!whisper" : lower_case(parts[2]);
			if (object c = channels[chan])
			{
				attr->_type = parts[1]; //Distinguish the three types of message
				c->not_message(person(@(parts[0] / "!")), message, attr);
				return;
			}
		}
		::got_command(what, @args);
	}
}

void error_notify(mixed ... args) {werror("error_notify: %O\n", args);}

int mod_query_delay = 0;
void reconnect()
{
	//NOTE: This appears to be creating duplicate channel joinings, for some reason.
	//HACK: Destroy and reconnect - this might solve the above problem. CJA 20160401.
	if (bounce(ws_handler)) return; //We're not the current file. Don't connect.
	if (irc && irc == G->G->irc) {irc->close(); if (objectp(irc)) destruct(irc); werror("%% Reconnecting\n");}
	//TODO: Dodge the synchronous gethostbyname?
	mapping opt = persist_config["ircsettings"];
	if (!opt || !opt->pass) return; //Not yet configured - can't connect.
	opt += (["channel_program": channel_notif, "connection_lost": lambda() {werror("%% Connection lost\n"); call_out(reconnect, 10);},
		"error_notify": error_notify]);
	mod_query_delay = 0; //Reset the delay
	if (mixed ex = catch {
		G->G->irc = irc = IRCClient("irc.chat.twitch.tv", opt);
		#if __REAL_VERSION__ >= 8.1
		function cap = irc->cmd->cap;
		#else
		//The 'cap' command isn't supported by Pike 8.0's Protocols.IRC.Client,
		//so we create our own, the same way. There will be noisy failures from
		//the responses, but it's fine in fire-and-forget mode.
		function cap = irc->cmd->SyncRequest(Protocols.IRC.Requests.NoReply("CAP", "string", "text"), irc->cmd);
		#endif
		cap("REQ","twitch.tv/membership");
		cap("REQ","twitch.tv/commands");
		cap("REQ","twitch.tv/tags");
		//Connect to channels progressively to reduce server hammer
		foreach (indices(persist_config["channels"]); int delay; string chan) {
			if (chan[0] == '!') {
				//Hack: Create fake channel objects for special pseudo-channels
				object ch = channel_notif();
				ch->name = "#" + chan;
				irc->channels["#" + chan] = ch;
			}
			else call_out(irc->join_channel, delay, "#" + chan);
		}
	})
	{
		//Something went wrong with the connection. Most likely, it's a
		//network issue, so just print the exception and retry in a
		//minute (non-backoff).
		werror("%% Error connecting to Twitch:\n%s\n", describe_error(ex));
		//Since other modules will want to look up G->G->irc->channels,
		//let them. One little shim is all it takes.
		G->G->irc = (["close": lambda() { }, "channels": ([])]);
	}
}

//NOTE: When this file gets updated, the queues will not be migrated.
//The old queues will be pumped by the old code, and the new code will
//have a single empty queue for the default voice.
mapping(string:object) sendqueues = ([]);
class SendQueue(string id) {
	int lastmsgtime;
	int modmsgs = 0;
	object client;
	array msgqueue = ({ });
	int active = 1;
	string my_nick;
	protected void create() {
		lastmsgtime = time(); //TODO: Subsecond resolution? Have had problems sometimes with triggering my own commands if non-mod.
		if (!id) {my_nick = bot_nick; return;} //The default queue uses the primary connection
		sendqueues[id] = this;
		mapping tok = persist_status["voices"][?id];
		if (!tok) {werror("Unable to get auth token for voice %O\n", id); finalize(); return;}
		mixed ex = catch (client = IRCClient("irc.chat.twitch.tv", ([
			"nick": my_nick = tok->login,
			"pass": "oauth:" + tok->token,
			"connection_lost": finalize,
			"error_notify": error_notify,
		])));
		if (ex) {
			tok->last_error_time = time();
			werror("%% Error connecting to voice %s:\n%s\n", my_nick, describe_error(ex));
			finalize(); return;
		}
		call_out(check_active, 300);
		write("Connected to voice %O\n", my_nick);
	}
	void finalize() {
		write("Finalizing voice queue for %O -> %O\n", my_nick, msgqueue);
		m_delete(sendqueues, id);
		if (client) client->close();
	}
	void check_active() {
		if (!active) {
			write("Voice %s idle, disconnecting\n", my_nick);
			finalize();
			return;
		}
		active = 0;
		call_out(check_active, 300);
	}

	void pump_queue() {
		int tm = time(1);
		if (tm == lastmsgtime) {call_out(pump_queue, 1); return;}
		lastmsgtime = tm; modmsgs = 0;
		[[string|array to, string msg], msgqueue] = Array.shift(msgqueue);
		(client || irc)->send_message(to, string_to_utf8(msg));
	}
	void send_message(string to, string msg, int|void is_mod) {
		if (has_prefix(to, "/"))
		{
			if (to == "/w " + my_nick)
			{
				//Hack: Instead of whispering to ourselves, write to the console.
				write("<%s> %s\n", to, msg);
				return;
			}
			msg = to + " " + msg; //eg "/w target message"
			to = "#" + my_nick; //Shouldn't matter what the dest is with these.
		}
		int tm = time(1);
		if (is_mod)
		{
			//Mods can always ignore slow-mode. But they should still keep it to
			//a max of 100 messages in 30 seconds (which I simplify down to 3/sec)
			//to avoid getting globalled.
			if (tm != lastmsgtime) {lastmsgtime = tm; modmsgs = 0;}
			if (++modmsgs < 3)
			{
				(client || irc)->send_message(to, string_to_utf8(msg));
				return;
			}
		}
		if (sizeof(msgqueue) || tm == lastmsgtime)
		{
			msgqueue += ({({to, msg})});
			call_out(pump_queue, 1);
		}
		else
		{
			lastmsgtime = tm; modmsgs = 0;
			(client || irc)->send_message(to, string_to_utf8(msg));
		}
	}
}
object default_queue = SendQueue(0);

constant badge_aliases = ([ //Fold a few badges together, and give shorthands for others
	"broadcaster": "_mod", "moderator": "_mod", "staff": "_mod",
	"subscriber": "_sub", "founder": "_sub", //Founders (the first 10 or 25 subs) have a special badge.
]);
//Go through a message's parameters/tags to get the info about the person
//There may be some non-person info gathered into here too, just for
//convenience; in fact, the name "person" here is kinda orphanned. (Tragic.)
mapping(string:mixed) gather_person_info(object person, mapping params)
{
	mapping ret = (["nick": person->nick, "user": person->user]);
	if (params->user_id && person->user)
	{
		ret->uid = (int)params->user_id;
		notice_user_name(person->user, params->user_id);
	}
	ret->displayname = params->display_name || person->nick;
	ret->msgid = params->id;
	if (params->badges)
	{
		ret->badges = ([]);
		foreach (params->badges / ",", string badge) if (badge != "")
		{
			sscanf(badge, "%s/%d", badge, int status);
			ret->badges[badge] = status;
			if (string flag = badge_aliases[badge]) ret->badges[flag] = status;
		}
	}
	if (params->emotes)
	{
		ret->emotes = ({ });
		foreach (params->emotes / "/", string emote) if (emote != "")
		{
			sscanf(emote, "%s:%s", string|int id, string pos);
			if (!has_prefix(id, "emotesv2")) id = (int)id; //TODO: Don't do this (it breaks on modified v1 emotes)
			foreach (pos / ",", string p) {
				sscanf(p, "%d-%d", int start, int end);
				if (end < start) continue; //Shouldn't happen (probably a parse failure)
				ret->emotes += ({({id, start, end})});
			}
		}
		sort(ret->emotes[*][1], ret->emotes); //Sort the emotes by start position
	}
	if (int bits = (int)params->bits) ret->bits = bits;
	//ret->raw = params; //For testing
	return ret;
}

mapping(string:function(string:string)) text_filters = ([
	"time_hms": lambda(string tm) {return describe_time_short((int)tm);},
	"time_english": lambda(string tm) {return describe_time((int)tm);},
	"upper": upper_case, "lower": lower_case,
]);

class channel_notif
{
	inherit Protocols.IRC.Channel;
	string color;
	mapping config = ([]);
	multiset mods=(<>);
	mapping(string:int) recent_viewers = ([]);
	string hosting;

	protected void create() {call_out(configure,0);}
	void configure() //Needs to happen after this->name is injected by Protocols.IRC.Client
	{
		config = persist_config["channels"][name[1..]];
		if (config->chatlog)
		{
			if (!G->G->channelcolor[name]) {if (++G->G->nextcolor>7) G->G->nextcolor=1; G->G->channelcolor[name]=G->G->nextcolor;}
			color = sprintf("\e[1;3%dm", G->G->channelcolor[name]);
		}
		else color = "\e[0m"; //Nothing will normally be logged, so don't allocate a color. If logging gets enabled, it'll take a reset to assign one.
		//The streamer counts as a mod. Everyone else has to speak in chat to
		//show us the badge, after which we'll acknowledge mod status. (For a
		//mod-only command, that's trivially easy; for web access, just "poke
		//the bot" in chat first.)
		mods[name[1..]] = 1;
	}

	//NOTE: Without not_join and its friends, Pike 8.0 will spam noisy failure
	//messages. Everything seems to still work, though.
	void not_join(object who) {/*log("%sJoin %s: %s\e[0m\n",color,name,who->user);*/ recent_viewers[who->user] = 1;}
	void not_part(object who,string message,object executor) {/*log("%sPart %s: %s\e[0m\n", color, name, who->user);*/}

	array(command_handler|string) locate_command(mapping person, string msg)
	{
		int mod = mods[person->user];
		if (command_handler f = sscanf(msg, "!%[^# ] %s", string cmd, string param)
			&& find_command(this, cmd, mod))
				return ({f, param||""});
		return ({0, ""});
	}

	void handle_command(mapping person, string msg, mapping defaults)
	{
		if (person->user) G_G_("participants", name[1..], person->user)->lastnotice = time();
		person->vars = (["%s": msg, "{@mod}": person->badges->?_mod ? "1" : "0"]);
		runhooks("all-msgs", 0, this, person, msg);
		trigger_special("!trigger", person, person->vars);
		[command_handler cmd, string param] = locate_command(person, msg);
		int offset = sizeof(msg) - sizeof(param);
		if (msg[offset..offset+sizeof(param)] != param) offset = -1; //TODO: Strip whites from around param without breaking this
		person->measurement_offset = offset;
		string emoted = "", residue = param;
		foreach (person->emotes || ({ }), [int|string id, int start, int end]) {
			emoted += sprintf("%s\uFFFAe%s:%s\uFFFB",
				residue[..start - offset - 1], //Text before the emote
				(string)id, residue[start-offset..end-offset], //Emote ID and name
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

	string set_variable(string var, string val, string action)
	{
		var = "$" + var + "$";
		mapping vars = persist_status->path("variables", name);
		if (action == "add") {
			//Add to a variable, REXX-style (decimal digits in strings).
			//Anything unparseable is considered to be zero.
			val = (string)((int)vars[var] + (int)val);
		}
		//Otherwise, keep the string exactly as-is.
		vars[var] = val;
		//Notify those that depend on this.
		G->G->websocket_types->chan_variables->update_one(name, var - "$");
		//TODO: Defer this until the next tick (with call_out 0), so that multiple
		//changes can be batched, reducing flicker.
		function send_updates_all = G->G->websocket_types->chan_monitors->send_updates_all;
		foreach (config->monitors || ([]); string nonce; mapping info) {
			if (!has_value(info->text, var)) continue;
			mapping info = (["data": (["id": nonce, "display": expand_variables(info->text)])]);
			send_updates_all(nonce + name, info); //Send to the group for just that nonce
			info->id = nonce; send_updates_all(name, info); //Send to the master group as a single-item update
		}
		persist_status->save();
		return val;
	}

	//For consistency, this is used for all vars substitutions. If, in the future,
	//we make $UNKNOWN$ into an error, or an empty string, or something, this would
	//be the place to do it.
	string _substitute_vars(string text, mapping vars, mapping person)
	{
		//Replace shorthands with their long forms. They are exactly equivalent, but the
		//long form can be enhanced with filters and/or defaults.
		text = replace(text, (["%s": "{param}", "$$": "{username}", "$participant$": "{participant}"]));
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
			string value = vars[type + kwd + tail];
			if (!value || value == "") return dflt;
			if (function f = filter != "" && text_filters[filter]) return f(value);
			return value;
		};
	}

	//Changes to vars[] will propagate linearly. Changes to cfg[] will propagate
	//within a subtree only. Change it only with |=.
	void _send_recursive(mapping person, echoable_message message, mapping vars, mapping cfg)
	{
		if (!message) return;
		if (!mappingp(message)) message = (["message": message]);

		if (message->delay)
		{
			call_out(_send_recursive, (int)message->delay, person, message | (["delay": 0, "_changevars": 1]), vars, cfg);
			return;
		}
		if (message->_changevars)
		{
			//When a delayed message gets sent, override any channel variables
			//with their new values. There are some bizarre corner cases that
			//could result from this (eg if you delete a variable, it'll still
			//exist in the delayed version), but there's no right way to do it.
			vars = vars | (persist_status->path("variables")[name] || ([]));
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
			cfg |= (["dest": d, "target": _substitute_vars(t, vars, person)]);
		}
		//Normal mode: Destination and target are separate fields
		else if (message->dest) cfg |= (["dest": message->dest, "target": _substitute_vars(message->target || "", vars, person)]);

		if (message->builtin) {
			object handler = G->G->builtins[message->builtin] || message->builtin; //Chaining can be done by putting the object itself in the mapping
			if (objectp(handler)) {
				string param = _substitute_vars(message->builtin_param || "", vars, person);
				handle_async(handler->message_params(this, person, param)) {
					if (!__ARGS__[0]) return; //No params? No output.
					_send_recursive(person, message->message, vars | __ARGS__[0], cfg);
				};
				return;
			}
			else message = (["message": sprintf("Bad builtin name %O", message->builtin)]);
		}

		echoable_message msg = message->message;
		string expr(string input) {
			if (!input) return "";
			string ret = _substitute_vars(input, vars, person);
			if (message->casefold) return lower_case(ret); //Would be nice to have a real Unicode casefold.
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
				if (re->match(expr(message->expr2))) break; //The regexp passes!
				msg = message->otherwise;
				break;
			}
			case "number": //Integer/float expression evaluator. Subst into expr, then evaluate. If nonzero, pass. If non-numeric, error out.
			{
				if (!G->G->evaluate_expr) msg = "ERROR: Expression evaluator unavailable";
				else if (mixed ex = catch {
					int|float value = G->G->evaluate_expr(expr(message->expr1));
					if (value != 0 && value != 0.0) break; //But I didn't fire an arrow...
					msg = message->otherwise;
				}) msg = "ERROR: " + (describe_error(ex)/"\n")[0];
				break;
			}
			case "cooldown": //Timeout (defined in seconds, although the front end may show it as mm:ss or hh:mm:ss)
			{
				string key = message->cdname + "#" + name;
				int delay = G->G->cooldown_timeout[key] - time();
				if (delay < 0) { //The time has passed!
					G->G->cooldown_timeout[key] = time() + message->cdlength; //But reset it.
					vars["{cooldown}"] = vars["{cooldown_hms}"] = "0";
					break;
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
			default: break; //including UNDEFINED which means unconditional, and 0 which means "condition already processed"
		}
		if (!msg || msg == "") return; //If a message doesn't have an Otherwise, it'll end up null.

		if (mappingp(msg)) {_send_recursive(person, message | (["conditional": 0]) | msg, vars, cfg); return;}

		if (arrayp(msg))
		{
			if (message->mode == "random") msg = random(msg);
			else
			{
				foreach (msg, echoable_message m)
					_send_recursive(person, message | (["conditional": 0, "message": m]), vars, cfg);
				return;
			}
		}

		//And now we have just a single string to send.
		string prefix = _substitute_vars(message->prefix || "", vars, person);
		msg = _substitute_vars(msg, vars, person);
		string dest = cfg->dest || "", target = cfg->target || "";
		if (dest == "/web")
		{
			//Stash the text away. Recommendation: Have a public message that informs the
			//recipient that info is available at https://sikorsky.rosuav.com/channels/%s/private
			mapping n2u = persist_status->path("name_to_uid");
			string uid = n2u[lower_case(target)]; //Yes, it's a string, even though it's always going to be digits
			if (!uid)
			{
				//TODO: Look the person up, delay the message, and then if
				//still not found, give a different error. For now, it depends
				//on the person having said something at some point.
				msg = sprintf("%s: User %s not found, has s/he said anything in chat?", person->user, target);
				dest = name; //Send it to the default, the channel.
			}
			else
			{
				//Normally, you'll be sending something to someone who was recently in chat.
				mapping msgs = persist_status->path("private", name, uid);
				int id = time();
				while (msgs[(string)id]) ++id; //Hack to avoid collisions
				msgs[(string)id] = (["received": time(), "message": msg]);
				persist_status->save();
				G->G->websocket_types->chan_messages->update_one(uid + name, (string)id);
				return; //Nothing more to send here.
			}
		}

		//Variable management. Note that these are silent, so commands may want to pair
		//these with public messages. (Silence is perfectly acceptable for triggers.)
		if (dest == "/set" && sscanf(target, "%[A-Za-z]", string var) && var && var != "")
		{
			vars["$" + var + "$"] = set_variable(var, msg, message->action);
			return;
		}

		if (dest == "/w") dest += " " + target;
		else dest = name; //Everything other than whispers and open chat has been handled elsewhere.

		function send_message = default_queue->send_message;
		if (cfg->voice && cfg->voice != "") {
			write("Selecting voice for %O\n", cfg->voice);
			if (!sendqueues[cfg->voice]) SendQueue(cfg->voice);
			send_message = sendqueues[cfg->voice]->send_message;
			write("Selected voice: %O\n", send_message);
		}

		//VERY simplistic form of word wrap.
		while (sizeof(msg) > 400)
		{
			sscanf(msg, "%400s%s %s", string piece, string word, msg);
			send_message(dest, sprintf("%s%s%s ...", prefix, piece, word), mods[bot_nick]);
		}
		send_message(dest, prefix + msg, mods[bot_nick]);
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
	void send(mapping person, echoable_message message, mapping|void vars)
	{
		vars = (persist_status->path("variables")[name] || ([])) | (vars || ([]));
		vars["$$"] = person->displayname || person->user;
		_send_recursive(person, message, vars, ([]));
	}

	//Expand all channel variables, except for {participant} which usually won't
	//make sense anyway. If you want $$ or %s or any of those, provide them in the
	//second parameter; otherwise, just expand_variables("Foo is $foo$.") is enough.
	string expand_variables(string text, mapping|void vars)
	{
		vars = (persist_status->path("variables")[name] || ([])) | (vars || ([]));
		return _substitute_vars(text, vars, ([]));
	}

	void record_raid(int fromid, string fromname, int toid, string toname, int|void ts, int|void viewers)
	{
		write("Detected a raid: %O %O %O %O %O\n", fromid, fromname, toid, toname, ts);
		if (!ts) ts = time();
		//JavaScript timestamps seem to be borked (given in ms instead of seconds).
		//Real timestamps won't hit this threshold until September 33658. At some
		//point close to that date (!), adjust this threshold.
		else if (ts > 1000000000000) ts /= 1000;
		Concurrent.all(
			fromid ? Concurrent.resolve(fromid) : get_user_id(fromname),
			toid ? Concurrent.resolve(toid) : get_user_id(toname),
		)->then(lambda(array(int) ids) {
			//Record all raids in a "base" of the lower user ID, for
			//consistency. If UID 1234 raids UID 2345, it's an outgoing
			//raid from 1234 to 2345; if 2345 raids 1234, it is instead
			//an incoming raid for 1234 from 2345. Either way, it's in
			//status->raids->1234->2345 and then has the timestamp.
			[int fromid, int toid] = ids;
			int outgoing = fromid < toid;
			string base = outgoing ? (string)fromid : (string)toid;
			string other = outgoing ? (string)toid : (string)fromid;
			mapping raids = persist_status->path("raids", base);
			if (!raids[other]) raids[other] = ({ });
			else if (raids[other][-1]->time > ts) {write("FUTURE RAID - %d, %O\n", ts, raids[other][-1]); return;} //Bugs happen. If timestamps go weird, report what we can.
			else if (raids[other][-1]->time > ts - 60) return; //Ignore duplicate raids within 60s
			raids[other] += ({([
				"time": ts,
				"from": fromname, "to": toname,
				"outgoing": outgoing,
				"viewers": undefinedp(viewers) ? -1 : (int)viewers,
			])});
			persist_status->save();
		});
	}

	void not_message(object ircperson, string msg, mapping(string:string)|void params)
	{
		//TODO: Figure out whether msg and params are bytes or text
		//With the tags parser, they are now always text (I think), but the
		//default parser may be using bytes.
		if (!params) params = ([]);
		mapping(string:mixed) person = gather_person_info(ircperson, params);
		if (!params->_type && person->nick == "tmi.twitch.tv")
		{
			//HACK: If we don't have the actual type provided, guess based on
			//the person's nick and the text of the message. Note that this code
			//is undertested and may easily be buggy. The normal case is that we
			//WILL get the correct message IDs, thus guaranteeing reliability.
			params->_type = "NOTICE";
			foreach (([
				"Now hosting %*s.": "host_on",
				"Exited host mode.": "host_off",
				"%*s has gone offline. Exiting host mode.": "host_target_went_offline",
				"The moderators of this channel are: %*s": "room_mods",
			]); string match; string id)
				if (sscanf(msg, match)) params->msg_id = id;
		}
		mapping responsedefaults;
		switch (params->_type)
		{
			case "NOTICE": case "USERNOTICE": switch (params->msg_id)
			{
				case "host_on": if (sscanf(msg, "Now hosting %s.", string h) && h)
				{
					if (G->G->stream_online_since[name[1..]])
					{
						//Hosting when you're live is a raid. (It might not use the
						//actual /raid command, but for our purposes, it counts.)
						//This has a number of good uses. Firstly, a streamer can
						//check this to see who hasn't been raided recently, and
						//spread the love around; and secondly, a viewer can see
						//which channel led to some other channel ("ohh, I met you
						//when X raided you last week"). Other uses may also be
						//possible. So it's in a flat file, easily greppable.
						mapping info = G->G->channel_info[name[1..]];
						int viewers = info ? info->viewer_count : -1;
						Stdio.append_file("outgoing_raids.log", sprintf("[%s] %s => %s with %d\n",
							Calendar.now()->format_time(), name[1..], h, viewers));
						record_raid(0, name[1..], 0, h, 0, viewers);
					}
					hosting = h;
				}
				break;
				case "host_off": case "host_target_went_offline": hosting = 0; break;
				case "room_mods": if (sscanf(msg, "The moderators of this channel are: %s", string names) && names)
				{
					//Response to a "/mods" command
					foreach (names / ", ", string name) if (!mods[name])
					{
						log("%sAcknowledging %s as a mod\e[0m\n", color, name);
						mods[name] = 1;
					}
				}
				break;
				case "slow_on": case "slow_off": break; //Channel is now/no longer in slow mode
				case "emote_only_on": case "emote_only_off": break; //Channel is now/no longer in emote-only mode
				case "subs_on": case "subs_off": break; //Channel is now/no longer in sub-only mode
				case "followers_on": case "followers_off": break; //Channel is now/no longer in follower-only mode (regardless of minimum time)
				case "followers_on_zero": break; //Regardless? Not quite; if it's zero-second followers-only mode, it's separate.
				case "msg_duplicate": case "msg_slowmode": case "msg_timedout": case "msg_banned":
					/* Last message wasn't sent, for some reason. There seems to be no additional info in the tags.
					- Your message was not sent because it is identical to the previous one you sent, less than 30 seconds ago.
					- This room is in slow mode and you are sending messages too quickly. You will be able to talk again in %d seconds.
					- You are banned from talking in %*s for %d more seconds.
					All of these indicate that the most recent message wasn't sent. Is it worth trying to retrieve that message?
					*/
					break;
				case "ban_success": break; //Just banned someone. Probably only a response to an autoban.
				case "raid": case "unraid": //Incoming raids already get announced and we don't get any more info
				{
					//Stdio.append_file("incoming_raids.log", sprintf("%s Debug incoming raid: chan %s user %O params %O\n",
					//	ctime(time())[..<1], name, person->displayname, params));
					//NOTE: The destination "room ID" might not remain forever.
					//If it doesn't, we'll need to get the channel's user id instead.
					record_raid((int)params->user_id, person->displayname,
						(int)params->room_id, name[1..], (int)params->tmi_sent_ts,
						(int)params->msg_param_viewerCount);
					trigger_special("!raided", person, (["{viewers}": params->msg_param_viewerCount]));
					break;
				}
				case "rewardgift": //Used for special promo messages eg "so-and-so's cheer just gave X people a bonus emote"
				{
					//write("DEBUG REWARDGIFT: chan %s disp %O user %O params %O\n",
					//	name, person->displayname, person->user, params);
					break;
				}
				//TODO: Handle sub plans better, esp since "Prime" should count as tier 1
				case "sub":
					Stdio.append_file("subs.log", sprintf("\n%sDEBUG RESUB: chan %s person %O params %O\n", ctime(time()), name, person->user, params)); //Where is the multimonth info?
					trigger_special("!sub", person, (["{tier}": params->msg_param_sub_plan[0..0]]));
					runhooks("subscription", 0, this, "sub", person, params->msg_param_sub_plan[0..0], 1, params);
					break;
				case "resub": trigger_special("!resub", person, ([
					"{tier}": params->msg_param_sub_plan[0..0],
					"{months}": params->msg_param_cumulative_months,
					"{streak}": params->msg_param_streak_months || "",
				]));
				runhooks("subscription", 0, this, "resub", person, params->msg_param_sub_plan[0..0], 1, params);
				Stdio.append_file("subs.log", sprintf("\n%sDEBUG RESUB: chan %s person %O params %O\n", ctime(time()), name, person->user, params)); //Where is the multimonth info?
				break;
				case "giftpaidupgrade": break; //Pledging to continue a subscription (first introduced for the Subtember special in 2018, and undocumented)
				case "anongiftpaidupgrade": break; //Ditto but when the original gift was anonymous
				case "primepaidupgrade": break; //Similar to the above - if you were on Prime but now pledge to continue, which could be done half price Subtember 2019.
				case "standardpayforward": break; //X is paying forward the Gift they got from Y to Z!
				case "communitypayforward": break; //X is paying forward the Gift they got from Y to the community!
				case "subgift":
				{
					/*write("DEBUG SUBGIFT: chan %s disp %O user %O mon %O recip %O multi %O\n",
						name, person->displayname, person->user,
						params->msg_param_months, params->msg_param_recipient_display_name,
						params->msg_param_gift_months);*/
					trigger_special("!subgift", person, ([
						"{tier}": params->msg_param_sub_plan[0..0],
						"{months}": params->msg_param_cumulative_months || params->msg_param_months || "1",
						"{streak}": params->msg_param_streak_months || "",
						"{recipient}": params->msg_param_recipient_display_name,
						"{multimonth}": params->msg_param_gift_months || "1",
					]));
					//Other params: login, user_id, msg_param_recipient_user_name, msg_param_recipient_id,
					//msg_param_sender_count (the total gifts this person has given in this channel)
					//Remember that all params are strings, even those that look like numbers
					runhooks("subscription", 0, this, "subgift", person, params->msg_param_sub_plan[0..0], 1, params);
					break;
				}
				case "submysterygift":
				{
					/*write("DEBUG SUBGIFT: chan %s disp %O user %O gifts %O multi %O\n",
						name, person->displayname, person->user,
						params->msg_param_mass_gift_count,
						params->msg_param_gift_months);*/
					trigger_special("!subbomb", person, ([
						"{tier}": params->msg_param_sub_plan[0..0],
						"{gifts}": params->msg_param_mass_gift_count,
						//TODO: See if this can actually happen, and if not, drop it
						"{multimonth}": params->msg_param_gift_months || "1",
					]));
					runhooks("subscription", 0, this, "subbomb", person, params->msg_param_sub_plan[0..0],
						(int)params->msg_param_mass_gift_count, params);
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
				default: werror("Unrecognized %s with msg_id %O on channel %s\n%O\n%O\n",
					params->_type, params->msg_id, name, params, msg);
			}
			break;
			case "WHISPER": responsedefaults = (["dest": "/w", "target": "$$"]); //fallthrough
			case "PRIVMSG": case 0: //If there's no params block, assume it's a PRIVMSG
			{
				//TODO: Check message times for other voices too
				if (lower_case(person->nick) == lower_case(bot_nick)) {default_queue->lastmsgtime = time(1); default_queue->modmsgs = 0;}
				if (person->badges) mods[person->user] = person->badges->_mod;
				if (sscanf(msg, "\1ACTION %s\1", msg)) person->is_action_msg = 1;
				//For some reason, whispers show up with "/me" at the start, not "ACTION".
				else if (sscanf(msg, "/me %s", msg)) person->is_action_msg = 1;
				handle_command(person, msg, responsedefaults);
				msg = person->displayname + (person->is_action_msg ? " " : ": ") + msg;
				string pfx=sprintf("[%s] ", name);
				#ifdef __NT__
				int wid = 80 - sizeof(pfx);
				#else
				int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
				#endif
				if (person->badges->?_mod) msg = "\u2694 " + msg;
				msg = string_to_utf8(msg);
				log("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
				if (params->bits && (int)params->bits)
					trigger_special("!cheer", person, (["{bits}": params->bits]));
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
				runhooks("delete-msg", 0, this, person, params->login, params->target_msg_id);
				G_G_("participants", name[1..], params->login)->lastnotice = 0;
				break;
			case "CLEARCHAT":
				runhooks("delete-msgs", 0, this, person, params->target_user_id);
				if (params->target_user_id) get_user_info(params->target_user_id)->then() {
					G_G_("participants", name[1..], __ARGS__[0]->login)->lastnotice = 0;
				};
				break;
			default: werror("Unknown message type %O on channel %s\n", params->_type, name);
		}
	}

	//Not sent by Twitch, so not very useful.
	void not_mode(object who,string mode) { }

	//Requires a UTF-8 encoded byte string (not Unicode text). May contain colour codes.
	void log(strict_sprintf_format fmt, sprintf_args ... args)
	{
		if (config->chatlog) write(fmt, @args);
	}

	void trigger_special(string special, mapping person, mapping info)
	{
		echoable_message response = G->G->echocommands[special + name];
		if (!response) return;
		if (has_value(info, 0)) werror("DEBUG: Special %O got info %O\n", special, info); //Track down those missing-info errors
		send(person, response, info);
	}
}

void session_cleanup()
{
	//Go through all HTTP sessions and dispose of old ones
	G->G->http_session_cleanup = 0;
	mapping sess = G->G->http_sessions;
	int limit = time();
	foreach (sess; string cookie; mapping info)
		if (info->expires <= limit) m_delete(sess, cookie);
	if (sizeof(sess)) G->G->http_session_cleanup = call_out(session_cleanup, 86400);
}

continue Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	req->misc->session = G->G->http_sessions[req->cookies->session] || ([]);
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
	if (mixed ex = handler && catch (resp = yield(handler(req, @args)))) {
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
	mapping sess = req->misc->session;
	if (sizeof(sess) && !sess->fake_session) {
		if (!sess->cookie) do {sess->cookie = random(1<<64)->digits(36);} while (G->G->http_sessions[sess->cookie]);
		sess->expires = time() + 604800; //Overwrite expiry time every request
		resp->extra_heads["Set-Cookie"] = "session=" + sess->cookie + "; Path=/; Max-Age=604800";
		G->G->http_sessions[sess->cookie] = sess;
		if (!G->G->http_session_cleanup) session_cleanup();
	}
	req->response_and_finish(resp);
}

void http_handler(Protocols.HTTP.Server.Request req) {handle_async(http_request(req)) { };}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn)
{
	if (function f = bounce(this_function)) {f(frm, conn); return;}
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	if (!stringp(data->cmd)) return;
	if (data->cmd == "init")
	{
		//Initialization is done with a type and a group.
		//The type has to match a module ("inherit websocket_handler")
		//The group has to be a string or integer.
		if (conn->type) return; //Can't init twice
		object handler = G->G->websocket_types[data->type];
		if (!handler) return; //Ignore any unknown types.
		if (string err = handler->websocket_validate(conn, data)) {
			conn->sock->send_text(Standards.JSON.encode((["error": err])));
			return;
		}
		string group = (stringp(data->group) || intp(data->group)) ? data->group : "";
		conn->type = data->type; conn->group = group;
		handler->websocket_groups[group] += ({conn->sock});
	}
	if (object handler = G->G->websocket_types[conn->type]) handler->websocket_msg(conn, data);
	else write("Message: %O\n", data);
}

void ws_close(int reason, mapping conn)
{
	if (function f = bounce(this_function)) {f(reason, conn); return;}
	if (object handler = G->G->websocket_types[conn->type])
	{
		handler->websocket_msg(conn, 0);
		handler->websocket_groups[conn->group] -= ({conn->sock});
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
	sock->set_id((["sock": sock, //Minstrel Hall style floop
		"session": G->G->http_sessions[req->cookies->session] || ([]),
		"remote_ip": remote_ip,
	]));
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
}

protected void create()
{
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	if (!G->G->cooldown_timeout) G->G->cooldown_timeout = ([]);
	if (!G->G->http_sessions) G->G->http_sessions = ([]);
	if (mixed id = m_delete(G->G, "http_session_cleanup")) remove_call_out(id);
	register_bouncer(ws_handler); register_bouncer(ws_msg); register_bouncer(ws_close);
	irc = G->G->irc;
	//if (!irc) //HACK: Force reconnection every time
		reconnect();
	if (mapping irc = persist_config["ircsettings"])
	{
		bot_nick = persist_config["ircsettings"]->nick || "";
		if (mixed ex = irc->http_address && irc->http_address != "" && catch
		{
			int use_https = has_prefix(irc->http_address, "https://");
			string listen_addr = "::"; //By default, listen on IPv4 and IPv6
			int listen_port = use_https ? 443 : 80; //Default port from protocol
			sscanf(irc->http_address, "http%*[s]://%*s:%d", listen_port); //If one is set for the dest addr, use that
			//Or if there's an explicit listen address/port set, use that.
			sscanf(irc->listen_address||"", "%d", listen_port);
			sscanf(irc->listen_address||"", "%s:%d", listen_addr, listen_port);

			string cert = Stdio.read_file("certificate.pem");
			if (listen_port * -use_https != G->G->httpserver_port_used || cert != G->G->httpserver_certificate)
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
				G->G->httpserver_certificate = cert;
				string key = Stdio.read_file("privkey.pem");
				array certs = cert && Standards.PEM.Messages(cert)->get_certificates();
				string pk = key && Standards.PEM.simple_decode(key);
				//If we don't have a valid PK and cert(s), Pike will autogenerate a cert.
				//TODO: Save the cert? That way, the self-signed could be pinned
				//permanently. Currently it'll be regenned each startup.
				G->G->httpserver = Protocols.WebSocket.SSLPort(http_handler, ws_handler, listen_port, listen_addr, pk, certs);
			}
		})
		{
			werror("NO HTTP SERVER AVAILABLE\n%s\n", describe_backtrace(ex));
			werror("Continuing without.\n");
			//Ensure that we don't accidentally use something unsafe (eg if it's an SSL issue)
			if (object http = m_delete(G->G, "httpserver")) catch {http->close();};
		}
	}
	add_constant("send_message", default_queue->send_message);
}
