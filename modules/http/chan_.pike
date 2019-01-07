inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel)
{
	string uptime = channel_uptime(channel->name[1..]);
	return render_template("chan_.md", ([
		"channel": channel->name[1..],
		"bot_or_mod": channel->mods[persist_config["ircsettings"]->nick] ? "mod" : "bot",
		"currency": channel->config->currency && channel->config->currency != "" ?
			"* [Channel currency](currency) - coming soon" : "",
		"uptime": uptime ? "Channel has been online for " + uptime : "Channel is currently offline.",
	]));
}
