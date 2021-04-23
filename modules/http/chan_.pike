inherit http_endpoint;

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
				//a separate export of that sort of ephemeral data.
				//Config attributes deprecated or for my own use only are not included.
				//(That includes channel currency; nobody has used it, I just never deleted it.)
				mapping cfg = channel->config;
				mapping ret = ([]);
				foreach ("quotes timezone" / " ", string key)
					ret[key] = cfg[key];
				if (cfg->allcmds) ret->active = "all";
				else if (cfg->httponly) ret->active = "httponly";
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
			if (req->variables->timezone != channel->config->timezone)
			{
				if (!has_value(Calendar.TZnames.zonenames(), req->variables->timezone))
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
		//TODO: Have a way to grab the client's timezone (see Mustard Mine)
		timezone = sprintf("<input name=timezone size=30 value=\"%s\">", Parser.encode_html_entities(timezone));
		save_config = "<input type=submit value=Save>";
		if (req->misc->session->user->login == channel->name[1..])
			//You're the broadcaster. Permit saving of all data.
			save_config += " <input type=submit name=export value='Export all configs'>";
	}
	return render_template("chan_.md", ([
		"bot_or_mod": channel->mods[persist_config["ircsettings"]->nick] ? "mod" : "bot",
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
	if (!handler) return (["error": 404]);
	object channel = G->G->irc->channels["#" + chan];
	if (!channel || (!channel->config->allcmds && !channel->config->httponly)) return ([
		"data": "No such page.\n",
		"type": "text/plain; charset=\"UTF-8\"",
		"error": 404,
	]);
	req->misc->channel = channel;
	string channame = G->G->channel_info[channel->name[1..]]->?display_name || channel->name[1..];
	req->misc->is_mod = 0; //If is_mod is false, save_or_login will be overridden
	req->misc->chaninfo = ([ //Additional (or overriding) template variables
		"channel": channame,
		"backlink": "<a href=\"./\">StilleBot - " + channame + "</a>",
	]);
	if (req->misc->session && req->misc->session->user)
	{
		if (channel->mods[req->misc->session->user->login])
		{
			req->misc->is_mod = 1;
			req->misc->chaninfo->autoform = "<form method=post>";
			req->misc->chaninfo->autoslashform = "</form>";
		}
		else req->misc->chaninfo->save_or_login = "<i>You're logged in, but not a recognized mod. Before you can make changes, go to the channel and say something, so I can see your mod sword. Thanks!</i>";
		req->misc->chaninfo->logout = "| <a href=\"/logout\">Log out</a>";
	}
	else req->misc->chaninfo->save_or_login = "<a href=\"/twitchlogin?next=" + req->not_query + "\">Mods, login to make changes</a>";
	return handler(req);
}

mapping(string:mixed) redirect_no_slash(Protocols.HTTP.Server.Request req, string chan)
{
	//Redirect /channels/rosuav to /channels/rosuav/
	return redirect(sprintf("/channels/%s/", chan), 301);
}

mapping(string:mixed) redirect_no_s(Protocols.HTTP.Server.Request req, string tail)
{
	//Redirect /channel/rosuav/ to /channels/rosuav/
	return redirect(sprintf("/channels/%s", tail), 301);
}


protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/channels/%[^/]"] = redirect_no_slash;
	G->G->http_endpoints["/channel/%[^\n]"] = redirect_no_s;
	G->G->http_endpoints["/channels/%[^/]/%[^/]"] = find_channel;
}
