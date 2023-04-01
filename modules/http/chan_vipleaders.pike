inherit http_websocket;
inherit hook;
constant markdown = #"# Leaderboards and VIPs

NOTE: AnAnonymousGifter may show up in the subgifting leaderboard for
statistical purposes, but will be skipped for VIP badges. Sorry, ghosts.
Similarly, moderators (shown with a green highlight) already have a badge
and will generously pass along the gemstone to the next person.

NOTE: Subgifting stats are currently based on UTC month rollover, but
cheering stats come directly from the Twitch API and are based on Los Angeles
time instead. This creates a 7-8 hour discrepancy in the rollover times.

Ties are broken by favouring whoever was first to subgift in the given month.

<div id=modcontrols></div>

<div id=monthly></div>

$$buttons$$

<style>
.addvip,.remvip {
	margin-left: 0.5em;
	min-width: 2.4em; height: 1.7em;
}
.addvip {color: blue;}
.remvip {color: red;}
.is_mod {
	opacity: 0.5;
	background: #a0f0c0;
}
.anonymous {
	opacity: 0.5;
	background: #c0c0c0;
}
/* .eligible {background: #eef;} */
.eligible .username {
	font-weight: bold;
}
#monthly td {vertical-align: top;}

#modcontrols {margin-bottom: 1em;}
#configform {
	border: 1px solid black;
	padding: 0.5em;
	max-width: 600px;
	margin: auto;
}
</style>
";
constant loggedin = #"
[Force recalculation](: #recalc)
";

//Possible TODO: Permanent VIPs.
//These people would be ineligible for leaderboard badges (and thus skipped),
//would never have badges removed (even if they were given leaderboard badges before becoming permavips),
//and will always have them added when any badges are added (to ensure that they retain them).
//Possible action: "turn current VIPs permanent". Good as part of setting up for the first time.

mapping tierval = (["2": 2, "3": 6]); //TODO: Should this be configurable? Some people might prefer a T3 to be worth 5.

void add_score(mapping monthly, mapping sub) {
	object cal = Calendar.ISO.Second("unix", sub->timestamp)->set_timezone("UTC");
	string month = sprintf("subs%04d%02d", cal->year_no(), cal->month_no()); //To generate weekly or yearly stats, this is the main part to change
	if (!monthly[month]) monthly[month] = ([]);
	mapping user = monthly[month][sub->giver->user_id];
	if (!user) monthly[month][sub->giver->user_id] = user = ([
		"firstsub": sub->timestamp, //Tiebreaker - earliest sub takes the spot
		"user_id": sub->giver->user_id,
	]);
	//If a person renames, update the display on seeing the next sub gift. Note that this
	//affects only the leaderboard itself, as the actual granting/revoking of VIP badges
	//is done based on the user ID.
	user->user_login = sub->giver->login;
	user->user_name = sub->giver->displayname;
	user->score += sub->qty * (tierval[sub->tier] || 1);
}

continue Concurrent.Future force_recalc(string chan, int|void fast) {
	mapping stats = persist_status->path("subgiftstats")[chan];
	if (!stats->?active) return 0;
	if (!fast || !stats->monthly) {
		stats->monthly = ([]);
		foreach (stats->all || ({ }), mapping sub) add_score(stats->monthly, sub);
	}

	int chanid = yield(get_user_id(chan));
	if (!fast || !stats->mods) {
		array mods = yield(twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=" + chanid,
			(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])))->data;
		stats->mods = mkmapping(mods->user_id, mods->user_name);
	}

	//Collect bit stats for that time period. NOTE: Periods other than "monthly" are basically broken. FIXME.
	string period = "month";
	mapping tm = gmtime(time()); //Twitch actually uses America/Pacific. This is behind UTC so it's mostly fine.
	mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
			+ sprintf("&started_at=%d-%02d-02T00:00:00Z", tm->year + 1900, tm->mon + 1),
			(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
	string was_uncertain = stats["latest_bits_" + period];
	//I said "mostly fine", but due to the way that rollover works, we can have uncertain data when we're in the
	//middle of rollover. That's a roughly 8-9 hour period when updates might not push through correctly, so to
	//compensate, we go a bit overboard and, any time there's any update on the 1st of the month, do a more full
	//fetch. It's a bit of work but it means we guarantee good data.
	if (tm->mday == 1) was_uncertain = "force";
	sscanf(info->date_range->started_at, "%d-%d-%*dT%*d:%*d:%*dZ", int year, int month);
	stats[period + "ly"][stats["latest_bits_" + period] = sprintf("bits%04d%02d", year, month)] = info->data;
	for (int i = 0; i < 6; ++i) {
		if (!--month) {--year; month = 12;}
		string key = sprintf("bits%04d%02d", year, month);
		if (was_uncertain != "force" && key != was_uncertain && stats[period + "ly"][key]) break; //We have dependable stats, they shouldn't change now.
		mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
				+ sprintf("&started_at=%d-%02d-02T00:00:00Z", year, month),
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
		stats[period + "ly"][key] = info->data;
	}

	persist_status->save();
	if (!stats->private) send_updates_all("#" + chan);
	send_updates_all("control#" + chan);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string buttons = loggedin;
	string group = "control";
	if (string scopes = ensure_bcaster_token(req, "bits:read moderation:read channel:manage:vips"))
		buttons = sprintf("[Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	else if (!req->misc->is_mod) {
		if (persist_status->path("subgiftstats")[req->misc->channel->name[1..]]->?private_leaderboard) {
			group = 0; //Empty string gives read-only access, null gives no socket (more efficient than one that gives no info)
			buttons = "*This leaderboard is private and viewable only by the moderators.*";
		} else {
			group = "";
			buttons = "*You're not a recognized mod, but you're welcome to view the leaderboard.*";
		}
	}
	return render(req, ([
		"vars": (["ws_group": group]),
		"buttons": buttons,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping stats = persist_status->path("subgiftstats", channel->name[1..]);
	if (grp != "control" && stats->private_leaderboard) return ([]);
	return stats;
}

void websocket_cmd_configure(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	mapping stats = persist_status->path("subgiftstats", channel->name[1..]);
	constant options = "active badge_count board_count private_leaderboard" / " ";
	int was_private = stats->private_leaderboard;
	foreach (options, string opt) if (!undefinedp(msg[opt])) stats[opt] = (int)msg[opt]; //They're all integers at the moment
	if (!was_private || !stats->private_leaderboard) send_updates_all(channel->name);
	send_updates_all("control" + channel->name);
}

void websocket_cmd_recalculate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	spawn_task(force_recalc(channel->name[1..]));
}

void websocket_cmd_addvip(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(addremvip(conn, msg, 1));}
void websocket_cmd_remvip(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(addremvip(conn, msg, 0));}
continue Concurrent.Future addremvip(mapping(string:mixed) conn, mapping(string:mixed) msg, int add) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	string chan = channel->name[1..];
	//If you're a mod, but not the broadcaster, do a dry run - put commands in chat
	//that say what would happen, but don't actually make changes.
	string addrem = add ? "Adding" : "Removing", tofrom = add ? "to" : "from";
	string method = add ? "POST" : "DELETE";
	if (conn->session->user->login != chan) {addrem = "Fake-" + lower_case(addrem); method = 0;}
	mapping stats = persist_status->path("subgiftstats", chan);
	array bits = stats->monthly["bits" + msg->yearmonth] || ({ });
	array subs = values(stats->monthly["subs" + msg->yearmonth] || ([]));
	sort(subs->firstsub, subs); sort(-subs->score[*], subs);
	//1) Get the top cheerers
	int limit = stats->badge_count || 10;
	array(string) userids = ({ }), people = ({ });
	foreach (bits, mapping person) {
		if (stats->mods[person->user_id]) continue;
		userids += ({person->user_id});
		people += ({person->user_name});
		if (!--limit) break;
	}
	if (!sizeof(people)) send_message(channel->name, "No non-mods have cheered bits in that month.");
	else send_message(channel->name, addrem + " VIP status " + tofrom + " cheerers: " + people * ", ");
	//2) Get the top subbers
	limit = stats->badge_count || 10; people = ({ });
	foreach (subs, mapping person) {
		if (stats->mods[person->user_id]) continue;
		if ((string)person->user_id == "274598607") continue; //AnAnonymousGifter
		if (!has_value(userids, person->user_id)) {
			//If that person has already received a VIP badge for cheering, don't re-add.
			userids += ({person->user_id});
			people += ({person->user_name});
		}
		else people += ({"(" + person->user_name + ")"});
		if (!--limit) break;
	}
	if (sizeof(people)) {
		//If nobody's subbed, don't even say anything.
		send_message(channel->name, addrem + " VIP status " + tofrom + " subgifters: " + people * ", ");
	}
	//3) Actually implement badge changes
	//The Twitch API actually limits this to 10 badge changes every 10 seconds,
	//but we simplify this down to 1 every 2 seconds. TODO: Try this at 1 every
	//1.25 seconds to speed it up, hopefully it won't break anything.
	if (method) {
		string baseurl = "https://api.twitch.tv/helix/channels/vips?broadcaster_id=" + channel->userid + "&user_id=";
		foreach (userids, string uid) {
			int status = yield(twitch_api_request(baseurl + uid,
				(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]),
				(["method": method, "return_status": 1])));
			if (status == 204) ; //Successfully added/removed
			else if (status == 422) send_message(channel->name, "NOTE: User " + uid + " already " + (add ? "has" : "doesn't have") + " a VIP badge");
			else send_message(channel->name, "Error " + status + " applying VIP badge to user " + uid + ", skipping");
			mixed _ = yield(task_sleep(2.0));
		}
	}
	send_message(channel->name, "Done " + lower_case(addrem) + " VIPs.");
}

//Note that slabs of this don't depend on the HTTP interface, but for simplicity,
//this is in modules/http. If you're not using StilleBot's web interface, this may
//need to have some things stubbed out.
@hook_subscription:
int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type != "subgift" && type != "subbomb") return 0; 
	if (extra->came_from_subbomb) return 0;
	mapping stats = persist_status->path("subgiftstats")[channel->name[1..]];
	if (!stats->?active) return 0;

	int months = (int)extra->msg_param_gift_months;
	if (months) qty *= months; //Currently, you can't subbomb multimonths.

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
	add_score(stats->monthly, stats->all[-1]);
	persist_status->save();
	send_updates_all(channel->name);
	send_updates_all("control" + channel->name);
}

@hook_cheer:
int cheer(object channel, mapping person, int bits, mapping extra) {
	mapping stats = persist_status->path("subgiftstats")[channel->name[1..]];
	if (!stats->?active) return 0;
	call_out(spawn_task, 1, force_recalc(channel->name[1..], 1)); //Wait a second, then do a fast update (is that enough time?)
}

protected void create(string name) {::create(name);}
