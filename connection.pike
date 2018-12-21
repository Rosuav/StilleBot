object irc;
string bot_nick;

#if __REAL_VERSION__ < 8.1
//Basically monkey-patch in a couple of methods that Pike 8.0 doesn't ship with.
class IRCClient
{
	inherit Protocols.IRC.Client;
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
}
#else
#define IRCClient Protocols.IRC.Client
#endif

void error_notify(mixed ... args) {werror("error_notify: %O\n", args);}

int mod_query_delay = 0;
void reconnect()
{
	//NOTE: This appears to be creating duplicate channel joinings, for some reason.
	//HACK: Destroy and reconnect - this might solve the above problem. CJA 20160401.
	if (irc && irc == G->G->irc) {irc->close(); if (objectp(irc)) destruct(irc); werror("%% Reconnecting\n");}
	//TODO: Dodge the synchronous gethostbyname?
	mapping opt = persist_config["ircsettings"];
	if (!opt) return; //Not yet configured - can't connect.
	opt += (["channel_program": channel_notif, "connection_lost": reconnect,
		"generic_notify": generic_notify, "error_notify": error_notify]);
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
		irc->join_channel(("#"+(indices(persist_config["channels"])-({"!whisper"}))[*])[*]);
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

//NOTE: When this file gets updated, the queue will not be migrated.
//The old queue will be pumped by the old code, and the new code will
//have a new (empty) queue.
int lastmsgtime = time();
int modmsgs = 0;
array msgqueue = ({ });
void pump_queue()
{
	int tm = time(1);
	if (tm == lastmsgtime) {call_out(pump_queue, 1); return;}
	lastmsgtime = tm; modmsgs = 0;
	[[string|array to, string msg], msgqueue] = Array.shift(msgqueue);
	irc->send_message(to, string_to_utf8(msg));
}
void send_message(string|array to, string msg, int|void is_mod)
{
	if (stringp(to) && has_prefix(to, "/"))
	{
		msg = to + " " + msg; //eg "/w target message"
		to = "#" + bot_nick; //Shouldn't matter what the dest is with these.
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
			irc->send_message(to, string_to_utf8(msg));
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
		irc->send_message(to, string_to_utf8(msg));
	}
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	string color;
	mapping config = ([]);
	multiset mods=(<>);
	mapping(string:int) viewers = ([]);
	mapping(string:array(int)) viewertime; //({while online, while offline})
	mapping(string:array(int)) wealth; //({actual currency, fractional currency})
	mixed save_call_out;
	string hosting;

	void create() {call_out(configure,0);}
	void configure() //Needs to happen after this->name is injected by Protocols.IRC.Client
	{
		config = persist_config["channels"][name[1..]];
		if (config->chatlog)
		{
			if (!G->G->channelcolor[name]) {if (++G->G->nextcolor>7) G->G->nextcolor=1; G->G->channelcolor[name]=G->G->nextcolor;}
			color = sprintf("\e[1;3%dm", G->G->channelcolor[name]);
		}
		else color = "\e[0m"; //Nothing will normally be logged, so don't allocate a color. If logging gets enabled, it'll take a reset to assign one.
		if (config->currency && config->currency!="") wealth = persist->path("wealth", name); //TODO-STATUS
		if (config->countactive || wealth) //Note that having channel currency implies counting activity time.
		{
			viewertime = persist->path("viewertime", name); //TODO-STATUS
			foreach (viewertime; string user; int|array val) if (intp(val)) m_delete(viewertime, user);
		}
		else if (persist["viewertime"]) m_delete(persist["viewertime"], name); //TODO-STATUS
		persist->save(); //TODO-STATUS
		save_call_out = call_out(save, 300);
		//Twitch will (eventually) notify us of who has "ops" privilege, which
		//corresponds to mods and other people with equivalent powers. But on
		//startup, it's quicker to (a) grant mod powers to the streamer, and
		//(b) ask Twitch who the other mods are. This won't catch people with
		//special powers (Twitch staff etc), so they may not be able to run
		//mod-only commands until the "MODE" lines come through.
		mods[name[1..]] = 1;
		//For some reason, this one line of code triggers the reconnect loop
		//bug. I have no idea what the actual cause is, but the issue seems
		//to be less common if the commands get spaced out a bit - delay the
		//first one by 1 second, the second by 2, etc.
		call_out(irc->send_message, ++mod_query_delay, name, "/mods");
	}

	void destroy() {save(); remove_call_out(save_call_out);}
	void _destruct() {save(); remove_call_out(save_call_out);}
	void save(int|void as_at)
	{
		//Save everyone's online time on code reload and periodically
		remove_call_out(save_call_out); save_call_out = call_out(save, 300);
		if (!as_at) as_at = time();
		int count = 0;
		int offline = !G->G->stream_online_since[name[1..]];
		int payout_div = wealth && (offline ? config->payout_offline : 1);
		foreach (viewers; string user; int start) if (start && as_at > start)
		{
			int t = as_at-start;
			if (viewertime)
			{
				if (!viewertime[user]) viewertime[user] = ({0,0});
				viewertime[user][offline] += t;
			}
			viewers[user] = as_at;
			if (payout_div)
			{
				if (!wealth[user]) wealth[user] = ({0, 0});
				if (int mul = mods[user] && config->payout_mod) t *= mul;
				t /= payout_div; //If offline payout is 1:3, divide the time spent by 3 and discard the loose seconds.
				t += wealth[user][1];
				wealth[user][0] += t / config->payout;
				wealth[user][1] = t % config->payout;
			}
			++count;
		}
		//write("[Saved %d viewer times for channel %s]\n", count, name);
		persist->save(); //TODO-STATUS
	}
	//NOTE: Without not_join and its friends, Pike 8.0 will spam noisy failure
	//messages. Everything seems to still work, though.
	void not_join(object who) {log("%sJoin %s: %s\e[0m\n",color,name,who->user); viewers[who->user] = time(1);}
	void not_part(object who,string message,object executor)
	{
		save(); //TODO, maybe: Save just this viewer's data
		m_delete(viewers, who->user);
		log("%sPart %s: %s\e[0m\n", color, name, who->user);
	}

	array(command_handler|string) locate_command(object person, string msg)
	{
		int mod = mods[person->user];
		if (command_handler f = has_prefix(msg,"!") && find_command(this, msg[1..], mod)) return ({f, ""});
		if (command_handler f = sscanf(msg, "!%s %s", string cmd, string param) == 2
			&& find_command(this, cmd, mod))
				return ({f, param});
		if (string cur = config->currency!="" && config->currency)
		{
			//Note that !currency will work (cf the above code), but !<currency-name> is the recommended way.
			if (msg == "!"+cur) return ({G->G->commands->currency, ""});
			if (sscanf(msg, "!"+cur+" %s", string param) == 1) return ({G->G->commands->currency, param});
		}
		return ({0, 0});
	}

	echoable_message substitute_percent(string|mapping|array(string|mapping) msg, string param)
	{
		if (stringp(msg)) return replace(msg, "%s", param);
		if (mappingp(msg)) return msg | (["message": replace(msg->message, "%s", param)]);
		if (arrayp(msg)) return substitute_percent(msg[*], param); //Yes, recursive. You shouldn't have arrays in arrays though.
		return msg;
	}

	echoable_message handle_command(object person, string msg)
	{
		if (config->noticechat && person->user && has_value(lower_case(msg), config->noticeme||""))
		{
			mapping user = G_G_("participants", name[1..], person->user);
			//Re-check every five minutes, max. We assume that people don't
			//generally unfollow, so just recheck those every day.
			if (config->followers && user->lastfollowcheck <= time() - (user->following ? 86400 : 300))
			{
				user->lastfollowcheck = time();
				check_following(person->user, name[1..]);
			}
			user->lastnotice = time();
		}
		[command_handler cmd, string param] = locate_command(person, msg);
		//Functions do not get %s handling. If they want it, they can do it themselves,
		//and if they don't want it, it would mess things up badly to do it here.
		if (functionp(cmd)) return cmd(this, person, param);
		return substitute_percent(cmd, param);
	}

	void wrap_message(object person, echoable_message info, string|void defaultdest)
	{
		if (!info) return;
		if (arrayp(info)) {wrap_message(person, info[*], defaultdest); return;}
		if (stringp(info)) info = (["message": info]);
		string msg = info->message, dest = info->dest || defaultdest || name;
		if (dest == "/w $$") dest = "/w " + person->user;
		string prefix = replace(info->prefix || "", "$$", person->user);
		msg = replace(msg, "$$", person->user);
		if (config->noticechat && has_value(msg, "$participant$"))
		{
			array users = ({ });
			int limit = time() - config->timeout;
			foreach (G_G_("participants", name[1..]); string name; mapping info)
				if (info->lastnotice >= limit && name != person->user) users += ({name});
			//If there are no other chat participants, pick the person speaking.
			string chosen = sizeof(users) ? random(users) : person->user;
			msg = replace(msg, "$participant$", chosen);
		}
		//VERY simplistic form of word wrap.
		while (sizeof(msg) > 400)
		{
			sscanf(msg, "%400s%s %s", string piece, string word, msg);
			send_message(dest, sprintf("%s%s%s ...", prefix, piece, word), mods[bot_nick]);
		}
		send_message(dest, prefix + msg, mods[bot_nick]);
	}

	void not_message(object person,string msg)
	{
		if (person->nick == "tmi.twitch.tv")
		{
			//It's probably a NOTICE rather than a PRIVMSG
			if (sscanf(msg, "Now hosting %s.", string h) && h)
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
					Stdio.append_file("outgoing_raids.log", sprintf("[%s] %s => %s\n",
						Calendar.now()->format_time(), name[1..], h));
				}
				hosting = h;
			}
			if (msg == "Exited host mode.") hosting = 0;
			if (has_suffix(msg, " has gone offline. Exiting host mode.")) hosting = 0;
			if (sscanf(msg, "The moderators of this channel are: %s", string names) && names)
			{
				//Response to a "/mods" command
				foreach (names / ", ", string name) if (!mods[name])
				{
					log("%sAcknowledging %s as a mod\e[0m\n", color, name);
					mods[name] = 1;
				}
			}
			/* Other useful NOTICE messages:
			- Your message was not sent because it is identical to the previous one you sent, less than 30 seconds ago.
			- This room is in slow mode and you are sending messages too quickly. You will be able to talk again in %d seconds.
			- You are banned from talking in %*s for %d more seconds.
			All of these indicate that the most recent message wasn't sent. Is it worth trying to retrieve that message?
			*/
			//Fall through and display them, if only for debugging
		}
		if (lower_case(person->nick) == lower_case(bot_nick)) {lastmsgtime = time(1); modmsgs = 0;}
		wrap_message(person, handle_command(person, msg));
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		#ifdef __NT__
		int wid = 80 - sizeof(pfx);
		#else
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		#endif
		log("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
	void not_mode(object who,string mode)
	{
		if (sscanf(mode, "+o %s", string newmod)) mods[newmod] = 1;
		if (sscanf(mode, "-o %s", string outmod)) mods[outmod] = 1;
		log("%sMode %s: %s %O\e[0m\n",color,name,who->nick,mode);
	}

	void log(strict_sprintf_format fmt, sprintf_args ... args)
	{
		if (config->chatlog) write(fmt, @args);
	}
}

void generic_notify(string from, string type, string to, string message, string extra)
{
	//NOTE: This function gets *everything*. Even if it's handled elsewhere.
	//Cherry-pick the few things that are interesting and ignore the rest.
	switch (type)
	{
		case "WHISPER":
		{
			sscanf(from, "%s!", string nick);
			write("** Whisper from %s: %s\n", nick, message);
			//Rather than having a pseudo-channel, it would probably be better to
			//have a "primary channel" that handles all whispers - effectively,
			//whispered commands are treated as if they were sent to that channel,
			//except that the response is whispered.
			if (object chan = G->G->irc->channels["#!whisper"])
			{
				mapping person = (["user": nick]); //Hack: The only way person is ever used is person->user. If that changes, replace this with something proper.
				chan->wrap_message(person, chan->handle_command(person, message), "/w $$");
			}
			break;
		}
		default:
			//Record the types in case something looks interesting
			if (!G->G->notify_types) G->G->notify_types = (<>);
			G->G->notify_types[type] = 1;
	}
}

void create()
{
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	irc = G->G->irc;
	//if (!irc) //HACK: Force reconnection every time
		reconnect();
	if (persist_config["ircsettings"]) bot_nick = persist_config["ircsettings"]->nick || "";
	add_constant("send_message", send_message);
}
