inherit http_websocket;
constant markdown = #"# Leaderboards and VIPs

NOTE: AnAnonymousGifter may show up in the subgifting leaderboard for
statistical purposes, but will be skipped for VIP badges. Sorry, ghosts.

NOTE: Subgifting stats are currently based on UTC month rollover, but
cheering stats come directly from the Twitch API and are based on Los Angeles
time instead. This creates a 7-8 hour discrepancy in the rollover times.

FIXME: Ties are currently broken by people's usernames for stability. Would
prefer to break them by preferring the one who first subbed earlier in the
month.

<div id=monthly></div>

$$buttons$$
";
constant loggedin = #"
[Force recalculation](: #recalc)
";
//TODO: Have a way to enable and disable channel->config->tracksubgifts

mapping tierval = (["2": 2, "3": 6]); //TODO: Should this be configurable? Some people might prefer a T3 to be worth 5.

continue Concurrent.Future force_recalc(string chan) {
	mapping stats = persist_status->path("subgiftstats", chan);
	if (!stats->all) return 0;
	stats->monthly = ([]);
	foreach (stats->all, mapping sub) {
		object cal = Calendar.ISO.Day("unix", sub->timestamp);
		string month = sprintf("%04d%02d", cal->year_no(), cal->month_no());
		if (!stats->monthly[month]) stats->monthly[month] = ([]);
		stats->monthly[month][sub->giver->user_id] += sub->qty * (tierval[sub->tier] || 1);
	}
	int chanid = yield(get_user_id(chan));
	stats->mods = yield(twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=" + chanid,
		(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
	persist_status->save();
	send_updates_all("#" + chan);
	send_updates_all("control#" + chan);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string buttons = loggedin;
	if (string scopes = ensure_bcaster_token(req, "bits:read moderation:read channel:moderate chat_login chat:edit"))
		buttons = sprintf("[Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	else if (!req->misc->is_mod)
		buttons = "*You're logged in, but not a recognized mod. View-only access granted.*";
	return render(req, ([
		"vars": (["ws_group": "control" * req->misc->is_mod]),
		"buttons": buttons,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping stats = persist_status->path("subgiftstats", channel->name[1..]);
	if (!stats->all) return ([]);
	return stats;
}

void websocket_cmd_recalculate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	spawn_task(force_recalc(channel->name[1..]));
}

mapping ignore_individuals = ([]);
mapping ignore_indiv_timeout = ([]);

//Note that slabs of this don't depend on the HTTP interface, but for simplicity,
//this is in modules/http. If you're not using StilleBot's web interface, this may
//need to have some things stubbed out.
int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type != "subgift" && type != "subbomb") return 0; 
	if (!channel->config->tracksubgifts) return 0;

	int months = (int)extra->msg_param_gift_months;
	if (months) qty *= months; //Currently, you can't subbomb multimonths.

	//Note: Sub bombs get announced first, followed by their individual gifts.
	//We could ignore the bombs and just count the individuals, but I'd rather
	//record the bomb and skip the individuals.
	if (type == "subbomb") {
		ignore_individuals[extra->user_id] += qty;
		ignore_indiv_timeout[extra->user_id] = time() + 600; //After ten minutes, if we haven't reset it, we must have missed them.
	}
	else if (ignore_individuals[extra->user_id] >= qty && ignore_indiv_timeout[extra->user_id] > time()) {
		ignore_individuals[extra->user_id] -= qty;
		return 0;
	}

	mapping stats = persist_status->path("subgiftstats", channel->name[1..]);
	stats->all += ({([
		"giver": ([
			"user_id": extra->user_id,
			"login": extra->login,
			"displayname": person->displayname,
			"is_mod": person->_mod,
		]),
		"tier": tier, "qty": qty,
		"timestamp": time(),
	])});
	//Assume that monthly is the type wanted. TODO: Make it configurable.
	if (!stats->monthly) stats->monthly = ([]);
	object cal = Calendar.ISO.Day("unix", stats->all[-1]->timestamp);
	string month = sprintf("%04d%02d", cal->year_no(), cal->month_no()); //eg 202112
	if (!stats->monthly[month]) stats->monthly[month] = ([]);
	stats->monthly[month][extra->user_id] += qty * (tierval[tier] || 1);
	persist_status->save();
	send_updates_all(channel->name);
	send_updates_all("control" + channel->name);
}

protected void create(string name)
{
	register_hook("subscription", subscription);
	::create(name);
}
