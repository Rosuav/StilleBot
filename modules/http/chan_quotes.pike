inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["quotes": "(none)"]) | req->misc->chaninfo);
	array q = ({ });
	string tz = req->misc->channel->config->timezone;
	object user = user_text();
	string btn = req->misc->is_mod ? " [\U0001F589](:.editbtn)" : "";
	foreach (quotes; int i; mapping quote)
	{
		//Render emotes. TODO: Use the bot's emote list primarily, but
		//if we have emote info retained from addquote, use that too.
		object ts = Calendar.Gregorian.Second("unix", quote->timestamp);
		if (tz) ts = ts->set_timezone(tz) || ts;
		string msg = emotify_user_text(quote->msg, user);
		string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
		q += ({sprintf("%d. %s [%s, %s]%s", i + 1, msg, quote->game || "uncategorized", date, btn)});
	}
	return render_template("chan_quotes.md", ([
		"quotes": q * "\n",
		"editjs": req->misc->is_mod ? "<script type=module src=\"" + G->G->template_defaults["static"]("quotes.js") + "\"></script>" : "",
		"vars": req->misc->is_mod && (["quotes": quotes]),
		"user text": user,
	]) | req->misc->chaninfo);
}
