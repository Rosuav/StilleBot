object irc;

void reconnect()
{
	//NOTE: This appears to be creating duplicate channel joinings, for some reason.
	//HACK: Destroy and reconnect - this might solve the above problem. CJA 20160401.
	if (irc) {irc->close(); destruct(irc); werror("%% Reconnecting\n");}
	G->G->irc = irc = Protocols.IRC.Client("irc.chat.twitch.tv", G->config);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->join_channel(("#"+indices(persist["channels"])[*])[*]);
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
	irc->send_message(to, msg);
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
		irc->send_message(to, msg);
	}
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	string color;
	mapping config;
	multiset mods=(<>);
	mapping(string:int) viewers = ([]);
	mapping(string:int) viewertime;
	mapping(string:array(int)) wealth;
	mixed save_call_out;

	void create() {call_out(configure,0);}
	void configure() //Needs to happen after this->name is injected by Protocols.IRC.Client
	{
		if (!G->G->channelcolor[name]) {if (++G->G->nextcolor>7) G->G->nextcolor=1; G->G->channelcolor[name]=G->G->nextcolor;}
		color = sprintf("\e[1;3%dm", G->G->channelcolor[name]);
		config = persist["channels"][name[1..]];
		viewertime = persist->path("viewertime", name);
		if (config->currency && config->currency!="") wealth = persist->path("wealth", name);
		save_call_out = call_out(save, 300);
	}

	void destroy() {save(); remove_call_out(save_call_out);}
	void save(int|void as_at)
	{
		//Save everyone's online time on code reload and periodically
		remove_call_out(save_call_out); save_call_out = call_out(save, 300);
		if (!as_at) as_at = time();
		int count = 0;
		int payout_div = wealth && (G->G->stream_online_since[name[1..]] ? 1 : config->payout_offline);
		foreach (viewers; string user; int start) if (start && as_at > start)
		{
			int t = as_at-start;
			viewertime[user] += t;
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
		write("[Saved %d viewer times for channel %s]\n", count, name);
		persist->save();
	}
	void not_join(object who) {write("%sJoin %s: %s\e[0m\n",color,name,who->user); viewers[who->user] = time(1);}
	void not_part(object who,string message,object executor)
	{
		int tm = viewers[who->user];
		string msg = "";
		if (tm)
		{
			tm = time()-tm;
			viewertime[who->user] += tm; persist->save();
			msg = " [watched for " + describe_time(tm) + "]";
		}
		write("%sPart %s: %s%s\e[0m\n", color, name, who->user, msg);
	}

	void not_message(object person,string msg)
	{
		if (lower_case(person->nick) == lower_case(G->config->nick)) lastmsgtime = time(1);
		if (function f = has_prefix(msg,"!") && G->G->commands[msg[1..]]) f(this, person, "");
		if (function f = (sscanf(msg, "!%s %s", string cmd, string param) == 2) && G->G->commands[cmd]) f(this, person, param);
		if (string cur = config->currency!="" && config->currency)
		{
			//Note that !currency will work, as will !<currency-name>.
			//And don't set the currency name to "currency" or it'll happen twice :)
			if (msg == "!"+cur) G->G->commands->currency(this, person, "");
			if (sscanf(msg, "!"+cur+" %s", string param) == 1) G->G->commands->currency(this, person, param);
		}
		if (string response = G->G->echocommands[msg]) send_message(name, response);
		if (string response = sscanf(msg, "%s %s", string cmd, string param) && G->G->echocommands[cmd])
			send_message(name, replace(response, "%s", param));
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
	void not_mode(object who,string mode)
	{
		if (sscanf(mode, "+o %s", string newmod)) mods[newmod] = 1;
		if (sscanf(mode, "-o %s", string outmod)) mods[outmod] = 1;
		write("%sMode %s: %s %O\e[0m\n",color,name,who->nick,mode);
	}
}

void create()
{
	G->config->channel_program = channel_notif;
	G->config->connection_lost = reconnect;
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	irc = G->G->irc;
	if (irc) destruct(irc); //HACK: Force reconnection every time
	reconnect();
	add_constant("send_message", send_message);
}
