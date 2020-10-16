inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "[Log in with your Twitch credentials](/twitchlogin?next=/)";
	if (yourname != "")
	{
		loglink = "[Log out](/logout)";
		yourname = "You are currently logged in as " + yourname + ".";
	}
	return render_template("index.md", ([
		"botname": persist_config["ircsettings"]->nick,
		"yourname": yourname, "loglink": loglink,
	]));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
}
