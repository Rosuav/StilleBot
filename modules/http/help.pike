inherit http_endpoint;

string nonlink(string txt) {
	sscanf(txt, "%*s %s", txt);
	return txt; //No link, just the flat text
}

string keeptext(string txt) {return txt;}
string ignoretext(string txt) {return "";}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Start with a quick check: Are you logged in? If so, do I bot for you?
	string yourname = req->misc->?session->?user->?display_name || "";
	string loglink = "You are not currently logged in. If you wish, you may: [Log in with your Twitch credentials](:.twitchlogin)";
	function link = nonlink, anon = keeptext, loggedin = ignoretext;
	string botname = persist_config["ircsettings"]->nick, chan = botname;
	string botowner = yield(get_user_info(botname, "login"))->display_name;
	if (yourname != "")
	{
		loglink = "[Log out](:.twitchlogout)";
		yourname = "You are currently logged in as " + yourname + ".";
		chan = req->misc->?session->?user->login;
		if (persist_config->has_path("channels", chan)) {
			yourname += " I currently serve as a bot for your channel, so there are additional features available.";
			link = lambda(string desttxt) {
				sscanf(desttxt, "%s %s", string dest, string txt);
				if (!txt) dest = txt = desttxt;
				return sprintf("[%s](/channels/%s/%s)", txt, chan, dest);
			};
			anon = ignoretext; loggedin = keeptext;
		}
	}
	return render_template("help.md", ([
		"botname": botname, "botowner": botowner,
		"yourname": yourname, "loglink": loglink,
		"link": link, "chan": chan,
		"anon": anon, "loggedin": loggedin,
	]));
}
