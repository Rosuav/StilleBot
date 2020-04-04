inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["channel": req->misc->channel_name, "quotes": "(none)", "editjs": ""]));
	string editjs = "";
	if (req->misc->is_mod)
	{
		//All the work is done client-side
		editjs = "<script>const quotes = " + Standards.JSON.encode(quotes) + "</script>"
			"<script type=module src=\"/static/quotes.js\"></script>";
	}
	array q = ({ });
	string tz = req->misc->channel->config->timezone;
	object user = user_text();
	foreach (quotes; int i; mapping quote)
	{
		//TODO: Render emotes. Use the bot's emote list primarily, but
		//if we have emote info retained from addquote, use that too.
		object ts = Calendar.Gregorian.Second("unix", quote->timestamp);
		if (tz) ts = ts->set_timezone(tz) || ts;
		string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
		q += ({sprintf("%d. %s [%s, %s]", i + 1, user(quote->msg), quote->game || "uncategorized", date)});
	}
	return render_template("chan_quotes.md", ([
		"channel": req->misc->channel_name,
		"quotes": q * "\n",
		"editjs": editjs,
		"user text": user,
	]));
}
