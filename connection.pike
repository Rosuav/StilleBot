object irc;

void reconnect()
{
	if (irc) {irc->close(); if (objectp(irc)) destruct(irc); werror("%% Reconnecting\n");}
	mapping opt = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd"))]);
	if (!opt) return; //Not yet configured - can't connect.
	opt += (["channel_program": channel_notif, "connection_lost": reconnect]);
	G->G->irc = irc = Protocols.IRC.Client("irc.chat.twitch.tv", opt);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->join_channel("#rosuav");
}

void send_message(string|array to,string msg)
{
	irc->send_message(to, string_to_utf8(msg));
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	string color = "\e[1;34m";

	void not_join(object who) {write("%sJoin %s: %s\e[0m\n",color,name,who->user);}
	void not_part(object who,string message,object executor) {write("%sPart %s: %s\e[0m\n", color, name, who->user);}

	void not_message(object person,string msg)
	{
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
