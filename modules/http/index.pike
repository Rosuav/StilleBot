inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "[Log in with your Twitch credentials](:.twitchlogin)";
	if (yourname != "")
	{
		loglink = "[Log out](:.twitchlogout)";
		yourname = "You are currently logged in as " + yourname + ".";
	}
	return render_template("index.md", ([
		"botname": G->G->dbsettings->credentials->username,
		"yourname": yourname, "loglink": loglink,
	]));
}

//Timing tests. Each performs exactly one database query; "ro" should be able to be resolved
//from the fast local database, but "rw" will always go to the active (non-read-only) DB.
__async__ string pingro(Protocols.HTTP.Server.Request req) {
	return sprintf("%O\n", await(G->G->DB->query_ro("select 1")));
}

__async__ string pingrw(Protocols.HTTP.Server.Request req) {
	return sprintf("%O\n", await(G->G->DB->query_rw("select 1")));
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
	G->G->http_endpoints["pingro"] = pingro;
	G->G->http_endpoints["pingrw"] = pingrw;
}
