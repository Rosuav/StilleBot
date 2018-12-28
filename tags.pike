void got_command(string what,string ... args)
{
	//With the capability "twitch.tv/tags" active, some messages get delivered prefixed.
	//The Pike IRC client doesn't handle the prefixes, and I'm not sure how standardized
	//this concept is (it could be completely Twitch-exclusive), so I'm handling it here.
	//The prefix is formatted as "@x=y;a=b;q=w" with simple key=value pairs. We parse it
	//out into a mapping and pass that along to not_message. Note that we also parse out
	//whispers the same way, even though there's actually no such thing as whisper_notif
	//in the core Protocols.IRC.Client handler.
	mapping(string:string) attr = ([]);
	if (has_prefix(what, "@"))
	{
		foreach (what[1..]/";", string att)
		{
			[string name, string val] = att/"=";
			attr[replace(name, "-", "_")] = replace(val, "\\s", " ");
		}
	}
	sscanf(args[0], "%s :%s", string a, string message);
	array parts = (a || args[0]) / " ";
	if (sizeof(parts) >= 3 && (<"PRIVMSG", "NOTICE", "WHISPER", "USERNOTICE">)[parts[1]])
	{
		write("%s on %s: %s\n%O\n", parts[1], parts[2], message || "(null)", attr);
		return;
	}
}

int main()
{
	string buf = "";
	while (string l = Stdio.stdin->gets())
	{
		if (l == "")
		{
			//Blank line signals end of current logical-line
			sscanf(buf, "%s :%s", string a, string b);
			got_command(@(a/" "), b);
			buf = "";
			continue;
		}
		if (has_prefix(l, "  ") && !has_prefix(l, "   ")) l = l[2..]; //Strip off two-leading-space indent from Gypsum
		buf += l; //NOTE: No newline added - this joins them into one logical line
	}
}
