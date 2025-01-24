inherit http_websocket;

constant markdown = #"# Recorded quotes for $$channel$$

$$quotes$$
{: #quotelist .emotedtext}

Record fun quotes from the channel's broadcaster and/or community! Alongside
Twitch Clips, quotes are a great way to remember those fun moments forever.

To manage and view quotes from the channel, three commands are available.
[Activate](:#activatecommands) [Deactivate](:#deactivatecommands)
<code>!quote</code>, <code>!addquote</code>, and <code>!delquote</code>.
{:#managequotes hidden=true}

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

string deduce_emoted_text(string msg, mapping botemotes) {
	array words = msg / " ";
	foreach (words; int i; string w)
		if (botemotes[w]) words[i] = sprintf("\uFFFAe%s:%s\uFFFB", botemotes[w], w);
		else if (sscanf(w, "%s_%s", string base, string mod) && botemotes[base] && mod)
			words[i] = sprintf("\uFFFAe%s:%s\uFFFB", botemotes[base] + "_" + mod, w);
	return words * " ";
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = await(G->G->DB->load_config(req->misc->channel->userid, "quotes", ({ })));
	if (!sizeof(quotes)) return render(req, (["quotes": "(none)"]) | req->misc->chaninfo);
	array q = ({ });
	string tz = req->misc->channel->config->timezone;
	object user = user_text();
	string btn = req->misc->is_mod && !req->misc->session->fake ? " [\U0001F589](:.editbtn)" : "";
	mapping botemotes;
	foreach (quotes; int i; mapping quote)
	{
		object ts = Calendar.Gregorian.Second("unix", quote->timestamp);
		if (tz) ts = ts->set_timezone(tz) || ts;
		//If we don't have emoted text recorded, use the bot's emote list to figure out what it should be.
		if (!quote->emoted) {
			botemotes = await(G->G->DB->load_config(G->G->bot_uid, "bot_emotes")); //TODO: Use the channel default voice instead of bot_uid
			quote->emoted = deduce_emoted_text(quote->msg, botemotes);
		}
		string msg = "", em = quote->emoted;
		while (sscanf(em, "%s\uFFFAe%s:%s\uFFFB%s", string txt, string emoteid, string emotename, em)) {
			msg += user(txt) + sprintf("![%s](%s)", emotename, emote_url(emoteid, 1));
		}
		msg += user(em);
		string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
		q += ({sprintf("%d. %s [%s, %s]%s", i + 1, msg, quote->game || "uncategorized", date, btn)});
	}
	if (botemotes) await(G->G->DB->save_config(req->misc->channel->userid, "quotes", quotes)); //We must have done at least one edit
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
	return ([
		"items": quotes,
		"can_activate": !channel->commands->quote || !channel->commands->addquote || !channel->commands->delquote,
		"can_deactivate": channel->commands->quote || channel->commands->addquote || channel->commands->delquote,
	]);
}

__async__ void wscmd_edit_quote(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array quotes = await(G->G->DB->load_config(channel->userid, "quotes", ({ })));
	int idx = (int)msg->idx;
	if (idx < 1 || idx > sizeof(quotes)) return;
	if (!stringp(msg->msg)) return;
	quotes[idx - 1]->msg = msg->msg;
	mapping botemotes = await(G->G->DB->load_config(G->G->bot_uid, "bot_emotes")); //TODO: As above, use the default voice
	quotes[idx - 1]->emoted = deduce_emoted_text(msg->msg, botemotes);
	await(G->G->DB->save_config(channel->userid, "quotes", quotes));
	send_updates_all(channel, ""); //No update_one support at the moment
}

void wscmd_managecommands(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	foreach (({"!quote", "!addquote", "!delquote"}), string id)
		G->G->enableable_modules->chan_commands->enable_feature(channel, id, !!msg->state);
	send_updates_all(channel, "");
}
