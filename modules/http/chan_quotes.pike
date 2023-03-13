inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return render_template("chan_quotes.md", (["quotes": "(none)"]) | req->misc->chaninfo);
	array q = ({ });
	string tz = req->misc->channel->config->timezone;
	object user = user_text();
	string btn = req->misc->is_mod ? " [\U0001F589](:.editbtn)" : "";
	mapping botemotes = persist_status->path("bot_emotes");
	foreach (quotes; int i; mapping quote)
	{
		//Render emotes. TODO: Use the bot's emote list primarily, but
		//if we have emote info retained from addquote, use that too.
		object ts = Calendar.Gregorian.Second("unix", quote->timestamp);
		if (tz) ts = ts->set_timezone(tz) || ts;
		array words = quote->msg / " ";
		//This is pretty inefficient - it makes a separate user() entry for each
		//individual word. If this is a problem, consider at least checking for
		//any emotes at all, and if not, just set msg to user(text) instead.
		foreach (words; int i; string w)
			if (botemotes[w]) words[i] = sprintf("![%s](%s)", w, emote_url(botemotes[w], 1));
			else if (sscanf(w, "%s_%s", string base, string mod) && botemotes[base] && mod)
				words[i] = sprintf("![%s](%s)", w, emote_url(botemotes[base] + "_" + mod, 1));
			else words[i] = user(w);
		string msg = words * " ";
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
