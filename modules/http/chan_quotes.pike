inherit http_endpoint;

string respstr(mapping|string resp) {return stringp(resp) ? resp : resp->message;}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["channel": req->misc->channel_name, "quotes": "(none)"]));
	string editlink = ""; int editing = 0;
	//FIXME: Eventually make this available to all mods. For testing, it's bot-self only.
	if (req->misc->is_mod && req->misc->session->user->login == function_object(send_message)->bot_nick)
	{
		if (req->variables->edit)
		{
			//TODO
			editing = 1;
			editlink = "[Cancel changes](quotes)";
		}
		else editlink = "[Welcome, owner. Edit quotes if desired.](quotes?edit)";
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
		"editlink": editlink,
	]));
}
