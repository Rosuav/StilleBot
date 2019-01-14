inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string user_is_mod = req->misc->is_mod ? "Welcome, " + req->misc->session->user->display_name + ", and your modsword." : "";
	object channel = req->misc->channel;
	string uptime = channel_uptime(req->misc->channel->name[1..]);
	return render_template("chan_.md", ([
		"channel": req->misc->channel_name,
		"bot_or_mod": channel->mods[persist_config["ircsettings"]->nick] ? "mod" : "bot",
		"currency": channel->config->currency && channel->config->currency != "" ?
			"* [Channel currency](currency) - coming soon" : "",
		"uptime": uptime ? "Channel has been online for " + uptime : "Channel is currently offline.",
		"user_is_mod": user_is_mod,
	]));
}
