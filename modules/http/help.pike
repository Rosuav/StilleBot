inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Start with a quick check: Are you logged in? If so, do I bot for you?
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "You are not currently logged in. If you wish, you may: [Log in with your Twitch credentials](:.twitchlogin)";
	if (yourname != "")
	{
		loglink = "[Log out](:.twitchlogout)";
		yourname = "You are currently logged in as " + yourname + ".";
		if (persist_config->path("channels")[req->misc->?session->?user->login])
			yourname += " I currently serve as a bot for your channel, so there are additional features available.";
	}
	return render_template("help.md", ([
		"botname": persist_config["ircsettings"]->nick,
		"yourname": yourname, "loglink": loglink,
	]));
}
