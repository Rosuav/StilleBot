inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping ac = req->misc->channel->config->autocommands;
	array repeats = ({ });
	foreach (ac || ({ }); string msg; int mins)
		repeats += ({sprintf("* Every %d mins: `%s`", mins, msg)});
	if (!sizeof(repeats)) repeats = ({"(none)"});
	return render_template("chan_repeats.md", ([
		"channel": req->misc->channel_name,
		"repeats": repeats * "\n",
	]));
}
