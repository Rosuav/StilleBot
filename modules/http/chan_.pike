inherit http_endpoint;
inherit menu_item;
constant menu_label = "Localhost Mod Override";
GTK2.MenuItem make_menu_item() {return GTK2.CheckMenuItem(menu_label);}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string user_is_mod = "";
	object channel = req->misc->channel;
	int uptime = channel_uptime(req->misc->channel->name[1..]);
	string timezone = channel->config->timezone;
	if (!timezone || timezone == "") timezone = "UTC";
	string save_config = "More to come";
	array(string) messages = ({ });
	if (req->misc->is_mod)
	{
		if (req->request_type == "POST")
		{
			if (req->variables->export && req->misc->session->user->login == channel->name[1..])
			{
				//Standard rule: Everything in this export comes from persist_config and the commands list.
				//(Which ultimately may end up being merged anyway.)
				//Anything in persist_status does not belong here; there may eventually be
				//a separate export of that sort of ephemeral data, eg variables.
				//Config attributes deprecated or for my own use only are not included.
				mapping cfg = channel->config;
				mapping ret = ([]);
				foreach ("autoban autocommands dynamic_rewards giveaway monitors quotes timezone vlcblocks" / " ", string key)
					if (cfg[key] && sizeof(cfg[key])) ret[key] = cfg[key];
				if (cfg->allcmds) ret->active = "all"; //TODO: Figure out better keywords for these
				else ret->active = "httponly";
				mapping commands = ([]), specials = ([]);
				string chan = channel->name[1..];
				foreach (G->G->echocommands; string cmd; echoable_message response) {
					sscanf(cmd, "%s#%s", cmd, string c);
					if (c != chan) continue;
					if (has_prefix(cmd, "!")) specials[cmd] = response;
					else commands[cmd] = response;
				}
				ret->commands = commands;
				if (array t = m_delete(specials, "!trigger"))
					if (arrayp(t)) ret->triggers = t;
				ret->specials = specials;
				mapping resp = jsonify(ret, 5);
				string fn = "stillebot-" + channel->name[1..] + ".json";
				resp->extra_heads = (["Content-disposition": sprintf("attachment; filename=%q", fn)]);
				return resp;
			}
			if (!req->misc->session->fake && req->variables->timezone != channel->config->timezone)
			{
				if (req->variables->timezone == "UTC") {
					messages += ({"* Reset timezone to UTC"});
					channel->config->timezone = ""; timezone = "UTC";
					persist_config->save();
				}
				else if (!has_value(Calendar.TZnames.zonenames(), req->variables->timezone))
				{
					//TODO: Handle timezone abbreviations
					messages += ({"* Invalid timezone " + req->variables->timezone});
				}
				else
				{
					messages += ({"* Set timezone to " + req->variables->timezone});
					channel->config->timezone = timezone = req->variables->timezone;
					persist_config->save();
				}
			}
		}
		user_is_mod = "Welcome, " + req->misc->session->user->display_name + ", and your modsword.";
		if (req->misc->session->fake) user_is_mod = "Welcome, demo user, and your modsword. On this special channel, everyone is considered a moderator! " +
			"Actions taken here will not be saved, so feel free to try things out!";
		//TODO: Have a way to grab the client's timezone (see Mustard Mine)
		timezone = sprintf("<input name=timezone size=30 value=\"%s\">", Parser.encode_html_entities(timezone));
		save_config = "<input type=submit value=Save>";
		if (req->misc->session->user->login == channel->name[1..])
			//You're the broadcaster. Permit saving of all data.
			save_config += " <input type=submit name=export value='Export all configs'>";
	}
	return render_template("chan_.md", ([
		"bot_or_mod": G->G->user_mod_status[persist_config["ircsettings"]->nick + channel->name] ? "mod" : "bot",
		"uptime": uptime ? "Channel has been online for " + describe_time(uptime) : "Channel is currently offline.",
		"user_is_mod": user_is_mod,
		"timezone": timezone,
		"save_config": save_config,
		"messages": messages * "\n",
	]) | req->misc->chaninfo);
}

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
	]);
	if (mapping user = req->misc->session->?user) {
		if (G->G->user_mod_status[user->login + channel->name] || is_localhost_mod(user->login, req->get_ip()))
			req->misc->is_mod = 1;
		else req->misc->chaninfo->save_or_login = "<i>You're logged in, but not a recognized mod. Before you can make changes, go to the channel and say something, so I can see your mod sword. Thanks!</i>";
		req->misc->chaninfo->logout = "| <a href=\"/logout\" class=twitchlogout>Log out</a>";
	}
	else req->misc->chaninfo->save_or_login = "[Mods, login to make changes](:.twitchlogin)";
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
