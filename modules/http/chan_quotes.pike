inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["channel": req->misc->channel_name, "quotes": "(none)"]));
	string editjs = "";
	//FIXME: Eventually make this available to all mods. For testing, it's bot-self only.
	if (req->misc->is_mod && req->misc->session->user->login == function_object(send_message)->bot_nick)
	{
		//All the work is done client-side
		editjs = "<script>const quotes = " + Standards.JSON.encode(quotes) + "</script>"
			"<script type=module src=\"/static/quotes.js\"></script>";
	}
	array q = ({ });
	foreach (quotes; int i; mapping quote)
	{
		//TODO: Render emotes. Use the bot's emote list primarily, but
		//if we have emote info retained from addquote, use that too.
		q += ({sprintf("%d. %s [%s]", i + 1, quote->msg, quote->game)});
	}
	return render_template("chan_quotes.md", ([
		"channel": req->misc->channel_name,
		"quotes": q * "\n",
		"editjs": editjs,
	]));
}
