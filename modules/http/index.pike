#charset utf-8
inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "[Log in with your Twitch credentials](:.twitchlogin)";
	if (yourname != "")
	{
		loglink = "[Log out](:.twitchlogout)";
		yourname = "You are currently logged in as " + yourname + ".";
		int id = (int)req->misc->session->user->id;
		if (id && G->G->irc->id[id]) yourname += " [Manage your channel](/c/)";
	}
	return render_template("index.md", ([
		"botname": G->G->dbsettings->credentials->username,
		"yourname": yourname, "loglink": loglink,
	]));
}

mapping(string:mixed)|Concurrent.Future faq(Protocols.HTTP.Server.Request req) {
	return render_template("faq.md", ([]));
}

//Timing tests. Each performs exactly one database query; "ro" should be able to be resolved
//from the fast local database, but "rw" will always go to the active (non-read-only) DB.
__async__ string pingro(Protocols.HTTP.Server.Request req) {
	return sprintf("%O\n", await(G->G->DB->query_ro("select 1")));
}

__async__ string pingrw(Protocols.HTTP.Server.Request req) {
	return sprintf("%O\n", await(G->G->DB->query_rw("select 1")));
}

//For channels where we don't have mod-check perms, let the user click a button to recheck
//mod status. Otherwise it will only be done occasionally.
string swordcheck(Protocols.HTTP.Server.Request req) {
	req->misc->session->modcheck_time = 0;
	return "Okay";
}

//Quick and dirty font display test
mapping font(Protocols.HTTP.Server.Request req) {return render_template(#"# Font test

	Pre-formatted: 🖉⯇⣿🔒💎👪🌞🌚

* Pencil 🖉
* Arrow ⯇
* Dots ⣿
* Lock 🔒
* Gem 💎
* Crowd 👪
* Sun 🌞
* Moon 🌚
", ([]));}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints[""] = http_request;
	G->G->http_endpoints["faq"] = faq;
	G->G->http_endpoints["pingro"] = pingro;
	G->G->http_endpoints["pingrw"] = pingrw;
	G->G->http_endpoints["font"] = font;
	G->G->http_endpoints["swordcheck"] = swordcheck;
}
