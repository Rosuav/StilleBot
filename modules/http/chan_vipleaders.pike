inherit http_websocket;
constant markdown = #"# Leaderboards and VIPs

NOTE: AnAnonymousGifter may show up in the subgifting leaderboard for
statistical purposes, but will be skipped for VIP badges. Sorry, ghosts.

$$save_or_login$$
";

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": "control" * req->misc->is_mod]),
		"save_or_login": "(logged in)",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	return ([]);
}

mapping ignore_individuals = ([]);
mapping ignore_indiv_timeout = ([]);

//Note that slabs of this don't depend on the HTTP interface, but for simplicity,
//this is in modules/http. If you're not using StilleBot's web interface, this may
//need to have some things stubbed out.
int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type != "subgift" && type != "subbomb") return 0; 
	if (!channel->config->tracksubgifts) return 0;
	//Note: Sub bombs get announced first, followed by their individual gifts.
	//We could ignore the bombs and just count the individuals, but I'd rather
	//record the bomb and skip the individuals.
	mapping stats = persist_status->path("subgiftstats", channel->name[1..]);
	int months = (int)extra->msg_param_gift_months;
	if (months) qty *= months; //Currently, you can't subbomb multimonths.
	if (type == "subbomb") {
		ignore_individuals[extra->user_id] += qty;
		ignore_indiv_timeout[extra->user_id] = time() + 600; //After ten minutes, if we haven't reset it, we must have missed them.
	}
	else if (ignore_individuals[extra->user_id] >= qty && ignore_indiv_timeout[extra->user_id] > time()) {
		ignore_individuals[extra->user_id] -= qty;
		return 0;
	}
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
	write("Updated subgift stats for %O: %O\n", channel->name, stats->all);
	write("Extra params: %O\n", extra);
	persist_status->save();
}

protected void create(string name)
{
	register_hook("subscription", subscription);
	::create(name);
}
