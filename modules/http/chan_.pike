inherit http_endpoint;
inherit menu_item;
constant menu_label = "Localhost Mod Override";
GTK2.MenuItem make_menu_item() {return GTK2.CheckMenuItem(menu_label);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string user_is_mod = "";
	object channel = req->misc->channel;
	int uptime = channel_uptime(req->misc->channel->name[1..]);
	if (req->misc->is_mod)
	{
		user_is_mod = "Welcome, " + req->misc->session->user->display_name + ", and your modsword.";
		if (req->misc->session->fake) user_is_mod = "Welcome, demo user, and your modsword. On this special channel, everyone is considered a moderator! " +
			"Actions taken here will not be saved, so feel free to try things out!";
	}
	return render_template("chan_.md", ([
		"bot_or_mod": G->G->user_mod_status[persist_config["ircsettings"]->nick + channel->name] ? "mod" : "bot",
		"uptime": uptime ? "Channel has been online for " + describe_time(uptime) : "Channel is currently offline.",
		"user_is_mod": user_is_mod,
	]) | req->misc->chaninfo);
}

constant sidebar_menu = ({
	({".", "Home"}),
	({"*features", "Features"}),
	({"commands", "Commands"}),
	({"*triggers", "Triggers"}),
	({"*specials", "Specials"}),
	({"*variables", "Variables"}),
	({"*repeats", "Autocommands"}),
	({"*pointsrewards", "Channel points"}),
	({"*dynamics", "Dynamic costs"}),
	({"quotes", "Quotes"}),
	({"giveaway", "Giveaway"}),
	({"*alertbox", "Alert box"}),
	({"*voices", "Voices"}),
	//({"vlc", "VLC music"}), //Not really needed in the sidebar IMO
	({"*monitors", "Monitors"}),
	({"messages", "Messages"}),
	({"share", "Art sharing"}),
	//TODO: Hype train, raid finder, emote showcase
});
array sidebar_modmenu = map(sidebar_menu) {return ({__ARGS__[0][0] - "*", __ARGS__[0][1]});};
array sidebar_nonmodmenu = filter(sidebar_menu) {return __ARGS__[0][0][0] != '*';};

mapping(string:mixed) find_channel(Protocols.HTTP.Server.Request req, string chan, string endpoint)
{
	function handler = G->G->http_endpoints["chan_" + endpoint];
	if (!handler) return 0;
	if (chan == "") return ([ //TODO: Better landing page? No menu of channels though, that would leak info
		"data": "Please select a channel.\n",
		"type": "text/plain; charset=\"UTF-8\"",
		"error": 404,
	]);
	if (chan == "demo") {
		chan = "!demo"; //Use /channels/demo/commands to access fake-mod demo mode
		string l = req->misc->session->user->?login;
		if (!l || !is_localhost_mod(l, req->get_ip())) {
			//Localhost mod status takes precedence over fake mod status.
			req->misc->session = ([
				"fake": 1,
				"user": ([
					"broadcaster_type": "fakemod", //Hack :)
					"display_name": "!Demo",
					"id": "3141592653589793", //Hopefully Twitch doesn't get THAT many users any time soon. If this ever shows up in logs, it should be obvious.
					"login": "!demo",
				]),
			]);
		}
	}
	object channel = G->G->irc->channels["#" + chan];
	if (!channel || !channel->config->active) return 0;
	req->misc->channel = channel;
	string channame = G->G->channel_info[channel->name[1..]]->?display_name || channel->name[1..];
	req->misc->is_mod = 0; //If is_mod is false, save_or_login will be overridden
	req->misc->chaninfo = ([ //Additional (or overriding) template variables
		"channel": channame,
		"backlink": "<a href=\"./\">StilleBot - " + channame + "</a>",
		"menubutton": "<span id=togglesidebarbox class=sbvis><button type=button id=togglesidebar title=\"Show/hide sidebar\">Show/hide sidebar</button></span>",
	]);
	if (mapping user = req->misc->session->?user) {
		if (G->G->user_mod_status[user->login + channel->name] || is_localhost_mod(user->login, req->get_ip()))
			req->misc->is_mod = 1;
		else req->misc->chaninfo->save_or_login = "<i>You're logged in, but not a recognized mod. Before you can make changes, go to the channel and say something, so I can see your mod sword. Thanks!</i>";
		req->misc->chaninfo->logout = "| <a href=\"/logout\" class=twitchlogout>Log out</a>";
	}
	else req->misc->chaninfo->save_or_login = "[Mods, login to make changes](:.twitchlogin)";
	req->misc->chaninfo->menunav = sprintf(
		"<nav id=sidebar class=vis><ul>%{<li><a href=%q>%s</a></li>%}</ul></nav>",
		req->misc->is_mod ? sidebar_modmenu : sidebar_nonmodmenu);
	return handler(req);
}

mapping(string:mixed) redirect_no_slash(Protocols.HTTP.Server.Request req, string chan)
{
	//Redirect /channels/?chan=rosuav to /channels/rosuav/
	if (chan == "" && req->variables->chan) chan = req->variables->chan;
	//Redirect /channels/rosuav to /channels/rosuav/
	return redirect(sprintf("/channels/%s/", chan), 301);
}

mapping(string:mixed) redirect_no_s(Protocols.HTTP.Server.Request req, string tail)
{
	//Redirect /channel/rosuav/ to /channels/rosuav/
	return redirect(sprintf("/channels/%s", tail), 301);
}

mapping(string:string|array) safe_query_vars(mapping(string:string|array) vars, mixed ... args) {
	if (sizeof(args) != 2) return 0;
	function handler = G->G->http_endpoints["chan_" + args[1]];
	if (!handler) return 0;
	return function_object(handler)->safe_query_vars(vars);
}

protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/channels/%[^/]"] = redirect_no_slash;
	G->G->http_endpoints["/channel/%[^\n]"] = redirect_no_s;
	G->G->http_endpoints["/channels/%[^/]/%[^/]"] = find_channel;
}
