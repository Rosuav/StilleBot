inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["channel": req->misc->channel_name, "quotes": "(none)"]));
	array q = ({ });
	foreach (quotes; int i; mapping quote)
		q += ({sprintf("%d. %s [%s]", i + 1, quote->msg, quote->game)});
	return render_template("chan_quotes.md", ([
		"channel": req->misc->channel_name,
		"quotes": q * "\n",
	]));
}
