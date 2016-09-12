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
}

int main()
{
	Protocols.IRC.Client("irc.chat.twitch.tv",([
		"nick": "Rosuav", "realname": "Chris Angelico", "pass": String.trim_all_whites(Stdio.read_file("pwd")),
		"channel_program": channel_notif]);
	)->join_channel("#rosuav");
	return -1;
}
