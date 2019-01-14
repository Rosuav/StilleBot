inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	string user_is_mod = "";
	if (session && session->user && channel->mods[session->user->login])
		user_is_mod = "Welcome, " + session->user->display_name + ", and your modsword.";
	string uptime = channel_uptime(channel->name[1..]);
	return render_template("chan_.md", ([
		"channel": G->G->channel_info[channel->name[1..]]?->display_name || channel->name[1..],
		"bot_or_mod": channel->mods[persist_config["ircsettings"]->nick] ? "mod" : "bot",
		"currency": channel->config->currency && channel->config->currency != "" ?
			"* [Channel currency](currency) - coming soon" : "",
		"uptime": uptime ? "Channel has been online for " + uptime : "Channel is currently offline.",
		"user_is_mod": user_is_mod,
	]));
}
