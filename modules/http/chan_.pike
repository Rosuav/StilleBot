inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string user_is_mod = "";
	object channel = req->misc->channel;
	string uptime = channel_uptime(req->misc->channel->name[1..]);
	string timezone = channel->config->timezone;
	if (!timezone || timezone == "") timezone = "UTC";
	string transcoding = channel->config->reporttrans ? "Announced on startup" : "Not announced";
	if (req->misc->is_mod)
	{
		user_is_mod = "Welcome, " + req->misc->session->user->display_name + ", and your modsword.";
		//TODO: Have a way to grab the client's timezone (see Mustard Mine)
		timezone = sprintf("<input name=timezone size=30 value=\"%s\">", Parser.encode_html_entities(timezone));
		transcoding = sprintf("<label><input type=checkbox %s name=reporttrans> Report on stream start</label>",
			channel->config->reporttrans ? "checked" : "");
	}
	return render_template("chan_.md", ([
		"channel": req->misc->channel_name,
		"bot_or_mod": channel->mods[persist_config["ircsettings"]->nick] ? "mod" : "bot",
		"uptime": uptime ? "Channel has been online for " + uptime : "Channel is currently offline.",
		"user_is_mod": user_is_mod,
		"timezone": timezone,
		"transcoding": transcoding,
	]));
}

mapping(string:mixed) find_channel(Protocols.HTTP.Server.Request req, string chan, string endpoint)
{
	function handler = G->G->http_endpoints["chan_" + endpoint];
	if (!handler) return (["error": 404]);
	object channel = G->G->irc->channels["#" + chan];
	if (!channel || !channel->config->allcmds) return ([
		"data": "No such page.\n",
		"type": "text/plain; charset=\"UTF-8\"",
		"error": 404,
	]);
	req->misc->channel = channel;
	req->misc->channel_name = G->G->channel_info[channel->name[1..]]->?display_name || channel->name[1..];
	req->misc->is_mod = req->misc->session && req->misc->session->user && channel->mods[req->misc->session->user->login];
	return handler(req);
}

mapping(string:mixed) redirect_no_slash(Protocols.HTTP.Server.Request req, string chan)
{
	//Redirect /channels/rosuav to /channels/rosuav/
	return redirect(sprintf("/channels/%s/", chan), 301);
}


protected void create(string name)
{
	::create(name);
	G->G->http_endpoints["/channels/%[^/]"] = redirect_no_slash;
	G->G->http_endpoints["/channels/%[^/]/%[^/]"] = find_channel;
}
