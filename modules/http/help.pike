inherit http_endpoint;

string nonlink(string txt) {
	sscanf(txt, "%*s %s", txt);
	return txt; //No link, just the flat text
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Start with a quick check: Are you logged in? If so, do I bot for you?
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "You are not currently logged in. If you wish, you may: [Log in with your Twitch credentials](:.twitchlogin)";
	function link = nonlink;
	if (yourname != "")
	{
		loglink = "[Log out](:.twitchlogout)";
		yourname = "You are currently logged in as " + yourname + ".";
		string chan = req->misc->?session->?user->login;
		if (persist_config->path("channels")[chan]) {
			yourname += " I currently serve as a bot for your channel, so there are additional features available.";
			link = lambda(string desttxt) {
				sscanf(desttxt, "%s %s", string dest, string txt);
				if (!txt) dest = txt = desttxt;
				return sprintf("[%s](/channels/%s/%s)", txt, chan, dest);
			};
		}
	}
	return render_template("help.md", ([
		"botname": persist_config["ircsettings"]->nick,
		"yourname": yourname, "loglink": loglink,
		"link": link,
	]));
}
