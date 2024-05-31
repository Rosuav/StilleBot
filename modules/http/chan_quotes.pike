inherit http_websocket;

constant markdown = #"# Recorded quotes for $$channel$$

$$quotes$$
{: #quotelist .emotedtext}

Record fun quotes from the channel's broadcaster and/or community! Alongside
Twitch Clips, quotes are a great way to remember those fun moments forever.

> ### Edit !quote <span id=idx></span>
> Make changes sensitively. Don't change other people's words :)
>
> Quoted at | <span id=timestamp></span>
> ----------|-----------
> Text      | <textarea id=text rows=4 cols=80></textarea>
> Category  | <span id=category></span>
> Recorder  | <span id=recorder></span>
>
> <button type=button id=update class=dialog_close>Update</button>
{: tag=dialog #editdlg}

<style>
.editbtn {
	padding: 0 5px;
	width: 2em; height: 2em;
}
</style>
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = await(G->G->DB->load_config(req->misc->channel->userid, "quotes", ({ })));
	if (!sizeof(quotes)) return render(req, (["quotes": "(none)"]) | req->misc->chaninfo);
	array q = ({ });
	string tz = req->misc->channel->config->timezone;
	object user = user_text();
	string btn = req->misc->is_mod && !req->misc->session->fake ? " [\U0001F589](:.editbtn)" : "";
	mapping botemotes = await(G->G->DB->load_config(G->G->bot_uid, "bot_emotes")); //TODO: Use the channel default voice instead of bot_uid
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
	return render(req, ([
		"quotes": q * "\n",
		"vars": btn != "" && (["ws_group": ""]),
		"user text": user,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	array quotes = await(G->G->DB->load_config(channel->userid, "quotes", ({ })));
	if (id) return (int)id < sizeof(quotes) && quotes[(int)id];
	return (["items": quotes]);
}

__async__ void wscmd_edit_quote(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array quotes = await(G->G->DB->load_config(channel->userid, "quotes", ({ })));
	int idx = (int)msg->idx;
	if (idx < 1 || idx > sizeof(quotes)) return;
	if (!stringp(msg->msg)) return;
	quotes[idx - 1]->msg = msg->msg;
	m_delete(quotes[idx - 1], "emoted"); //TODO: Rewrite instead of removing
	await(G->G->DB->save_config(channel->userid, "quotes", quotes));
	send_updates_all(channel, ""); //No update_one support at the moment
}
