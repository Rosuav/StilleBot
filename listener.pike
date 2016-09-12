//Stand-alone listener - a massively cut-down version of connection.pike
//Requires the oauth password to be in a file called 'pwd'.

class channel_notif
{
	inherit Protocols.IRC.Channel;
	void not_message(object person,string msg)
	{
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = person->nick+" "+slashme;
		else msg = person->nick+": "+msg;
		string pfx=sprintf("[%s] ",name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg);
	}
	//Stubs because older Pikes don't include all of these by default
	void not_join(object who) { }
	void not_part(object who, string message, object executor) { }
	void not_mode(object who, string mode) { }
	void not_failed_to_join() { }
	void not_invite(object who) { }
}

int main()
{
	mapping opts = (["nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd"))]);
	object irc = Protocols.IRC.Client("irc.chat.twitch.tv", opts);
	irc->cmd->join("#rosuav");
	(irc->channels["#rosuav"] = channel_notif())->name = "#rosuav";
	return -1;
}
