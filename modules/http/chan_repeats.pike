inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req, object channel, mapping(string:mixed) session)
{
	mapping ac = channel->config->autocommands;
	if (!ac || !sizeof(ac)) return render_template("chan_repeats.md", (["channel": G->G->channel_info[channel->name[1..]]?->display_name || channel->name[1..], "repeats": "(none)"]));
	array repeats = ({ });
	foreach (ac; string msg; int mins)
		repeats += ({sprintf("* Every %d mins: `%s`", mins, msg)});
	return render_template("chan_repeats.md", ([
		"channel": G->G->channel_info[channel->name[1..]]?->display_name || channel->name[1..],
		"repeats": repeats * "\n",
	]));
}
