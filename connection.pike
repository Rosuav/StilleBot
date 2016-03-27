object irc;
mapping(string:string) commands = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_commands.json")||"{}");

void reconnect()
{
	//NOTE: This appears to be creating duplicate channel joinings, for some reason.
	if (irc) write("%% Reconnecting\n");
	G->G->irc = irc = Protocols.IRC.Client("irc.chat.twitch.tv", G->config);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->join_channel(G->channels[*]);
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
	void create() {call_out(setcolor,0);}
	void setcolor() //Needs to happen after this->name is injected by Protocols.IRC.Client
	{
		if (!G->G->channelcolor[name]) {if (++G->G->nextcolor>7) G->G->nextcolor=1; G->G->channelcolor[name]=G->G->nextcolor;}
		color = sprintf("\e[1;3%dm", G->G->channelcolor[name]);
	}

	void not_join(object who) {write("%sJoin %s: %s\e[0m\n",color,name,who->nick);}
	void not_part(object who,string message,object executor) {write("%sPart %s: %s\e[0m\n",color,name,who->nick);}

	void cmd_hostthis(object person, string param) {send_message("#"+person->nick, "/host "+name[1..]);}
	void cmd_addcmd(object person, string param)
	{
		if (sscanf(param, "!%s %s", string cmd, string response) == 2)
		{
			//Create a new command
			string newornot = commands["!"+cmd] ? "Updated" : "Created new";
			commands["!"+cmd] = response;
			Stdio.write_file("twitchbot_commands.json", string_to_utf8(Standards.JSON.encode(commands, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL)));
			send_message(name, sprintf("@%s: %s command !%s", person->nick, newornot, cmd));
		}
	}
	#if 0
	void cmd_tz(object person, string param)
	{
		string tz = timezone_info(param);
		while (sizeof(tz) > 200)
		{
			sscanf(tz, "%200s%s %s", string piece, string word, tz);
			send_message(name, sprintf("@%s: %s%s ...", person->nick, piece, word));
		}
		send_message(name, sprintf("@%s: %s", person->nick, tz));
	}
	#endif

	void cmd_help(object person, string param)
	{
		array(string) cmds=({ });
		foreach (indices(this), string attr) if (sscanf(attr, "cmd_%s", string c)) cmds+=({"!"+c});
		cmds += indices(commands);
		sort(cmds);
		send_message(name, sprintf("@%s: Available commands are:%{ %s%}", person->nick, cmds));
	}

	void not_message(object person,string msg)
	{
		if (lower_case(person->nick) == lower_case(G->config->nick)) lastmsgtime = time(1);
		if (function f = has_prefix(msg,"!") && G->G->commands[msg[1..]]) f(this, person, "");
		if (function f = (sscanf(msg, "!%s %s", string cmd, string param) == 2) && G->G->commands[cmd]) f(this, person, param);
		if (commands[msg]) send_message(name, commands[msg]);
		if (sscanf(msg, "%s %s", string cmd, string param) && commands[cmd]) send_message(name, replace(commands[cmd], "%s", param));
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%s%s\e[0m", color, sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
}

void create()
{
	G->config->channel_program = channel_notif;
	G->config->connection_lost = reconnect;
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	irc = G->G->irc;
	if (!irc) reconnect();
	add_constant("send_message", send_message);
}
