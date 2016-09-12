object irc;

void reconnect()
{
	if (irc) {irc->close(); if (objectp(irc)) destruct(irc); werror("%% Reconnecting\n");}
	mapping opt = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd")),
		"channel_program": channel_notif, "connection_lost": reconnect]);
	G->G->irc = irc = Protocols.IRC.Client("irc.chat.twitch.tv", opt);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->join_channel("#rosuav");
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	void not_join(object who) {write("\e[1;34mJoin %s: %s\e[0m\n",name,who->user);}
	void not_part(object who,string message,object executor) {write("\e[1;34mPart %s: %s\e[0m\n", name, who->user);}
	void not_message(object person,string msg)
	{
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("\e[1;34m%s\e[0m", sprintf("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg));
	}
}

void create()
{
	if (!G->G->channelcolor) G->G->channelcolor = ([]);
	irc = G->G->irc;
	reconnect();
}
