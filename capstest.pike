object irc;
mapping persist_config = Standards.JSON.decode_utf8(Stdio.read_file("twitchbot_config.json"));

class IRCClient
{
	inherit Protocols.IRC.Client;
	void got_command(string what,string ... args)
	{
		//With the capability "twitch.tv/tags" active, some messages get delivered prefixed.
		//The Pike IRC client doesn't handle the prefixes, and I'm not sure how standardized
		//this concept is (it could be completely Twitch-exclusive), so I'm handling it here.
		//The prefix is formatted as "@x=y;a=b;q=w" with simple key=value pairs. We parse it
		//out into a mapping and pass that along to not_message. Note that we also parse out
		//whispers the same way, even though there's actually no such thing as whisper_notif
		//in the core Protocols.IRC.Client handler.
		if (has_prefix(what, "@") && sscanf(args[0],"%s :%s", string a, string message) == 2)
		{
			mapping(string:string) attr = ([]);
			foreach (what[1..]/";", string att)
			{
				[string name, string val] = att/"=";
				attr[replace(name, "-", "_")] = val;
			}
			//write(">> %O %O <<\n", args[0], attr);
			array parts = a / " ";
			if (sizeof(parts) >= 3 && parts[1] == "WHISPER")
			{
				if (options->whisper_notif)
					options->whisper_notif(person(@(parts[0] / "!")), parts[2], message, attr);
				return;
			}
			if (sizeof(parts) >= 3 && (<"PRIVMSG", "NOTICE">)[parts[1]])
			{
				if (object c = channels[lower_case(parts[2])])
				{
					c->not_message(person(@(parts[0] / "!")), message, attr);
					return;
				}
			}
		}
		::got_command(what, @args);
	}
}

void terminate()
{
	werror("Connection lost, terminating.\n");
	exit(0);
}

constant badge_flags = ([
	"broadcaster": "mod", "moderator": "mod", //TODO: Also add staff and global mods
	"vip": "vip", //Unconfirmed
	"subscriber": "sub",
]);
mapping(string:mixed) gather_person_info(object person, mapping params)
{
	mapping ret = (["nick": person->nick]);
	if (params->user_id) ret->uid = (int)params->user_id;
	ret->displayname = params->display_name || person->nick;
	if (params->badges)
	{
		ret->badges = params->badges / ",";
		foreach (ret->badges, string badge)
		{
			sscanf(badge, "%s/%d", badge, int status);
			if (string flag = badge_flags[badge]) ret[flag] = status;
		}
	}
	return ret;
}

class channel_notif
{
	inherit Protocols.IRC.Channel;
	void not_message(object person, string msg, mapping(string:string)|void params)
	{
		mapping(string:mixed) originator = gather_person_info(person, params || ([]));
		if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = originator->displayname+" "+slashme;
		else msg = originator->displayname+": "+msg;
		string pfx=sprintf("[%d-%s] ", originator->uid, name);
		int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
		write("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg);
	}
}

void whisper(object person, string recip, string msg, mapping|void params)
{
	mapping(string:mixed) originator = gather_person_info(person, params || ([]));
	if (sscanf(msg, "\1ACTION %s\1", string slashme)) msg = originator->displayname+" "+slashme;
	else msg = originator->displayname+": "+msg;
	string pfx=sprintf("[%d-@%s] ", originator->uid, recip);
	int wid = Stdio.stdin->tcgetattr()->columns - sizeof(pfx);
	write("%*s%-=*s\n",sizeof(pfx),pfx,wid,msg);
}

int main()
{
	mapping opt = persist_config["ircsettings"];
	opt += (["channel_program": channel_notif, "connection_lost": terminate, "whisper_notif": whisper]);
	irc = IRCClient("irc.chat.twitch.tv", opt);
	irc->cmd->cap("REQ","twitch.tv/membership");
	irc->cmd->cap("REQ","twitch.tv/commands");
	irc->cmd->cap("REQ","twitch.tv/tags");
	irc->join_channel("#rosuav");
	return -1;
}
