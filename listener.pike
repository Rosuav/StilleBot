//Stand-alone listener - a massively cut-down version of connection.pike

class channel_notif
{
	inherit Protocols.IRC.Channel;
	void not_join(object who) {write("Join %s: %s\n",name,who->user);}
	void not_part(object who,string message,object executor) {write("Part %s: %s\n", name, who->user);}
	void not_message(object person,string msg)
	{
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg);
	}
}

int main()
{
	mapping opt = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd")),
		"channel_program": channel_notif]);
	object irc = Protocols.IRC.Client("irc.chat.twitch.tv", opt);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->join_channel("#rosuav");
	return -1;
}
