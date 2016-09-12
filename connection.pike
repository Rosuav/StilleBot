object irc;
string bot_nick;

void reconnect()
{
	//NOTE: This appears to be creating duplicate channel joinings, for some reason.
	//HACK: Destroy and reconnect - this might solve the above problem. CJA 20160401.
	if (irc) {irc->close(); if (objectp(irc)) destruct(irc); werror("%% Reconnecting\n");}
	//TODO: Dodge the synchronous gethostbyname?
	mapping opt = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": "oauth:<censored>"]);
	if (!opt) return; //Not yet configured - can't connect.
	opt += (["channel_program": channel_notif, "connection_lost": reconnect]);
	if (mixed ex = catch {
		G->G->irc = irc = Protocols.IRC.Client("irc.chat.twitch.tv", opt);
		irc->cmd->cap("REQ","twitch.tv/membership");
		irc->join_channel("#rosuav");
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
array msgqueue = ({ });
void pump_queue()
{
	int tm = time(1);
	if (tm == lastmsgtime) {call_out(pump_queue, 1); return;}
	lastmsgtime = tm;
	[[string|array to, string msg], msgqueue] = Array.shift(msgqueue);
	irc->send_message(to, string_to_utf8(msg));
}
void send_message(string|array to,string msg)
{
	int tm = time(1);
	if (sizeof(msgqueue) || tm == lastmsgtime)
	{
		msgqueue += ({({to, msg})});
		call_out(pump_queue, 1);
	}
	else
	{
		lastmsgtime = tm;
		irc->send_message(to, string_to_utf8(msg));
	}
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	string color = "\e[1;34m";

	void not_join(object who) {write("%sJoin %s: %s\e[0m\n",color,name,who->user);}
	void not_part(object who,string message,object executor) {write("%sPart %s: %s\e[0m\n", color, name, who->user);}

	void not_message(object person,string msg)
	{
		if (lower_case(person->nick) == lower_case(bot_nick)) lastmsgtime = time(1);
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
	void not_mode(object who,string mode)
	{
		write("%sMode %s: %s %O\e[0m\n",color,name,who->nick,mode);
	}
}

void create()
{
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	irc = G->G->irc;
	//if (!irc) //HACK: Force reconnection every time
		reconnect();
	add_constant("send_message", send_message);
}
