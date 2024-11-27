inherit http_websocket;
inherit hook;
constant markdown = #"# Leaderboards and VIPs

NOTE: AnAnonymousGifter may show up in the subgifting leaderboard for
statistical purposes, but will be skipped for VIP badges. Sorry, ghosts.
Similarly, moderators (shown with a green highlight) already have a badge
and will generously pass along the gemstone to the next person.

NOTE: Subgifting and tipping stats are currently based on UTC month rollover, but
cheering stats come directly from the Twitch API and are based on Los Angeles
time instead. This creates a 7-8 hour discrepancy in the rollover times.

Ties are broken by favouring whoever was first to subgift/tip in the given month.

<div id=modcontrols></div>

<div id=monthly></div>

$$buttons$$

> ### Formatted display
>
> Include the following directive to embed the VIP leader names:<br>
> `%{text...%s...more text%}`<br>
> Any text (including multiple lines) can be used.
>
> <textarea id=formattext rows=15 cols=60></textarea>
>
> [Save](:#formatsave) [Close](:.dialog_close)
{: tag=dialog #formatdlg}

<!-- -->

> ### Formatted display
>
> Configured in the mod section. This includes VIPs from the<br>
> month of <span id=formatdate></span>.
>
> <textarea readonly id=displaytext rows=20 cols=60></textarea>
>
> [Close](:.dialog_close)
{: tag=dialog #displaydlg}

<style>
.addvip,.remvip,.fmtvip {
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
//Note that this should be shown on the front end, in case such users end up on the leaderboard. This
//might have been unlikely when this was first created (the ones Devi gives VIP to permanently are not
//likely to be cheering/subgifting enough to get on the board), but now it's possible to donate a spot
//on the leaderboard by tipping with their name, so anyone could be on the list!


mapping tierval = (["2": 2, "3": 6]); //TODO: Should this be configurable? Some people might prefer a T3 to be worth 5.

void add_score(mapping monthly, string board, mapping sub) {
	object cal = Calendar.ISO.Second("unix", sub->timestamp)->set_timezone("UTC");
	string month = sprintf("%s%04d%02d", board, cal->year_no(), cal->month_no()); //To generate weekly or yearly stats, this is the main part to change
	if (!monthly[month]) monthly[month] = ([]);
	mapping user = monthly[month][sub->giver->user_id];
	if (!user) monthly[month][sub->giver->user_id] = user = ([
		"firstsub": sub->timestamp, //Tiebreaker - earliest takes the spot (note that "sub" is orphanned here, it might be a Ko-fi/StreamLabs tip)
		"user_id": sub->giver->user_id,
	]);
	//If a person renames, update the display on seeing the next sub gift. Note that this
	//affects only the leaderboard itself, as the actual granting/revoking of VIP badges
	//is done based on the user ID.
	user->user_login = sub->giver->login;
	user->user_name = sub->giver->displayname;
	user->score += sub->qty * (tierval[sub->tier] || 1);
}

__async__ void force_recalc(object channel, int|void fast) {
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (!stats->?active) return;
	if (!fast || !stats->monthly) {
		stats->monthly = ([]);
		foreach (stats->all || ({ }), mapping sub) add_score(stats->monthly, "subs", sub);
		foreach (stats->allkofi || ({ }), mapping sub) {
			/* Enable this if a reparse of Ko-fi or SL tips is needed. Much slower of course.
			foreach ("user_id login displayname" / " ", string key)
				if (sub->giver[key]) sscanf(sub->giver[key], "%*[>+?!] %s", sub->giver[key]);
			if (!(int)sub->giver->user_id) catch {
				mapping user = await(get_user_info(sub->giver->login, "login"));
				sub->giver->user_id = user->id;
			}; // */
			add_score(stats->monthly, "kofi", sub);
		}
	}

	int chanid = channel->userid;
	if (!fast || !stats->mods) {
		array mods = await(twitch_api_request("https://api.twitch.tv/helix/moderation/moderators?first=100&broadcaster_id=" + chanid,
			(["Authorization": "Bearer " + token_for_user_id(chanid)[0]])))->data;
		stats->mods = mkmapping(mods->user_id, mods->user_name);
	}

	//Collect bit stats for that time period. NOTE: Periods other than "monthly" are basically broken. FIXME.
	string period = "month";
	mapping tm = gmtime(time()); //Twitch actually uses America/Pacific. This is behind UTC so it's mostly fine.
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
			+ sprintf("&started_at=%d-%02d-02T00:00:00Z", tm->year + 1900, tm->mon + 1),
			(["Authorization": "Bearer " + token_for_user_id(chanid)[0]])));
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
		mapping info = await(twitch_api_request("https://api.twitch.tv/helix/bits/leaderboard?count=25&period=" + period
				+ sprintf("&started_at=%d-%02d-02T00:00:00Z", year, month),
				(["Authorization": "Bearer " + token_for_user_id(chanid)[0]])));
		stats[period + "ly"][key] = info->data;
	}

	await(G->G->DB->save_config(channel->userid, "subgiftstats", stats));
	if (!stats->private) send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string buttons = loggedin;
	string|zero group = "control";
	if (string scopes = ensure_bcaster_token(req, "bits:read moderation:read channel:manage:vips"))
		buttons = sprintf("[Grant permission](: .twitchlogin data-scopes=@%s@)", scopes);
	else if (!req->misc->is_mod) {
		mapping stats = await(G->G->DB->load_config(req->misc->channel->userid, "subgiftstats"));
		if (stats->private_leaderboard) {
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
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (grp != "control" && stats->private_leaderboard) return ([]);
	return stats;
}

__async__ void websocket_cmd_configure(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	constant intopt = "active badge_count board_count private_leaderboard use_kofi use_streamlabs" / " ";
	constant stropt = "displayformat" / " ";
	int was_private = stats->private_leaderboard;
	foreach (intopt, string opt) if (!undefinedp(msg[opt])) stats[opt] = (int)msg[opt];
	foreach (stropt, string opt) if (!undefinedp(msg[opt])) stats[opt] = msg[opt];
	await(G->G->DB->save_config(channel->userid, "subgiftstats", stats));
	if (!was_private || !stats->private_leaderboard) send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

void websocket_cmd_recalculate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	spawn_task(force_recalc(channel));
}

array(array(string)|array(array(string))) collect_leaders(mapping stats, string yearmonth, int include_dups) {
	array bits = stats->monthly["bits" + yearmonth] || ({ });
	//1) Get the top cheerers
	int limit = stats->badge_count || 10;
	array(string) userids = ({ }), people = ({ });
	foreach (bits, mapping person) {
		if (stats->mods[person->user_id]) continue;
		userids += ({person->user_id});
		people += ({person->user_name});
		if (!--limit) break;
	}
	array(array(string)) all_people = ({people});
	//2) Get the top subbers and tippers
	foreach (({"subs", "kofi"}), string which) {
		array subs = values(stats->monthly[which + yearmonth] || ([])); //(or tips, whatever)
		sort(subs->firstsub, subs); sort(-subs->score[*], subs);
		limit = stats->badge_count || 10; people = ({ });
		foreach (subs, mapping person) {
			if (stats->mods[person->user_id]) continue;
			if ((string)person->user_id == "274598607") continue; //AnAnonymousGifter
			if ((string)(int)person->user_id != (string)person->user_id) continue; //Non-numeric user "ids" are for truly-anonymous donations
			if (!has_value(userids, person->user_id)) {
				//If that person has already received a VIP badge for cheering, don't re-add.
				userids += ({person->user_id});
				people += ({person->user_name});
			}
			else if (include_dups) people += ({"(" + person->user_name + ")"});
			if (!--limit) break;
		}
		all_people += ({people});
	}
	return ({userids, all_people});
}

__async__ void websocket_cmd_formattext(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!msg->monthyear) return;
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return;
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (!stats->displayformat) return;
	array all_people = collect_leaders(stats, msg->monthyear, 0)[1];
	string text;
	if (mixed ex = catch {text = sprintf(stats->displayformat, all_people * ({ }));})
		text = describe_error(ex);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "formattext", "text": text]), 4));
}

void websocket_cmd_addvip(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(addremvip(conn, msg, 1));}
void websocket_cmd_remvip(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(addremvip(conn, msg, 0));}
__async__ void addremvip(mapping(string:mixed) conn, mapping(string:mixed) msg, int add) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	string chan = channel->name[1..];
	//If you're a mod, but not the broadcaster, do a dry run - put commands in chat
	//that say what would happen, but don't actually make changes.
	string addrem = add ? "Adding" : "Removing", tofrom = add ? "to" : "from";
	string|zero method = add ? "POST" : "DELETE";
	if (conn->session->user->login != chan) {addrem = "Fake-" + lower_case(addrem); method = 0;}
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	[array(string) userids, [array(string) cheerers, array(string) subbers, array(string) tippers]] = collect_leaders(stats, msg->yearmonth, 1);
	if (sizeof(cheerers)) send_message(channel->name, addrem + " VIP status " + tofrom + " cheerers: " + cheerers * ", ");
	if (sizeof(subbers)) send_message(channel->name, addrem + " VIP status for subs: " + subbers * ", ");
	if (sizeof(tippers)) send_message(channel->name, addrem + " VIP status for Ko-fi: " + tippers * ", ");
	//The Twitch API actually limits this to 10 badge changes every 10 seconds,
	//but we simplify this down to 1 every 2 seconds. TODO: Try this at 1 every
	//1.25 seconds to speed it up, hopefully it won't break anything.
	if (method) {
		string baseurl = "https://api.twitch.tv/helix/channels/vips?broadcaster_id=" + channel->userid + "&user_id=";
		string token = token_for_user_id(channel->userid)[0];
		foreach (userids, string uid) {
			int status = await(twitch_api_request(baseurl + uid,
				(["Authorization": "Bearer " + token]),
				(["method": method, "return_status": 1])));
			if (status == 204) ; //Successfully added/removed
			else if (status == 422) {
				//TODO: If attempting to add a VIP badge to someone who already has it,
				//maybe record that and don't remove it later?
				send_message(channel->name, "NOTE: User " + uid + " already " + (add ? "has" : "doesn't have") + " a VIP badge");
			}
			else send_message(channel->name, "Error " + status + " applying VIP badge to user " + uid + ", skipping");
			await(task_sleep(2.0));
		}
	}
	send_message(channel->name, "Done " + lower_case(addrem) + " VIPs.");
}

@hook_kofi_support:
int kofi_tip(object channel, string type, mapping params, mapping raw) {
	if (type != "!kofi_dono") return 0; 
	add_tip(channel, type, params, raw, "use_kofi");
}
__async__ void add_tip(object channel, string type, mapping params, mapping raw, string flag) {
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (!stats->?active || !stats[flag]) return 0;
	//Ko-fi support comes with a username, but NOT a Twitch user ID. So we look up
	//the Twitch user **at the time of donation**, and record all details. If the
	//lookup fails, the gift is considered anonymous. Note that, if a user renames,
	//their donations will be credited to the same user as long as the name used
	//in the donation matched the name *as of that time*.
	mapping user = ([]);
	catch {user = await(get_user_info(params->username, "login"));}; //Any error, leave it as "anonymous"
	//TODO: If we have a user (and thus an ID), scan through allkofi to find any
	//with the same email address and update them. If that is done, do a full recalc.
	stats->allkofi += ({([
		"giver": ([
			//If we don't have a recognized user, use the name and email as the identity. Close enough
			//but won't give any VIP badges out.
			"user_id": user->id || raw->email || "274598607",
			"login": user->login || params->username,
			"displayname": user->displayname || params->username,
		]),
		"qty": params->cents,
		"timestamp": time(),
	])});
	//As below, assume that monthly is the type wanted.
	if (!stats->monthly) stats->monthly = ([]);
	add_score(stats->monthly, "kofi", stats->allkofi[-1]);
	await(G->G->DB->save_config(channel->userid, "subgiftstats", stats));
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@hook_allmsgs:
int message(object channel, mapping person, string msg)
{
	//TODO: Unify this somewhere and have an event hook for tips.
	//Thanks to Mixer237237 for proving that it's possible to have a comma in the dollar amount.
	if (person->user == "streamlabs" && sscanf(msg - ",", "%s just tipped $%d.%d!", string user, int dollars, int cents) && user && (dollars || cents)) {
		if (sizeof(user) > 3 && user[1] == ' ') user = user[2..]; //Not sure if this always happens. There's often some sort of symbol, and I have no idea if it means anything, just before the name.
		add_tip(channel, "!kofi_dono", ([
			"cents": dollars * 100 + cents,
			"username": user,
		]), (["email": user]), "use_streamlabs");
	}
}

@hook_subscription:
int _subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {subscription(channel, type, person, tier, qty, extra);}
__async__ int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type != "subgift" && type != "subbomb") return 0; 
	if (extra->came_from_subbomb) return 0;
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (!stats->?active) return 0;

	int months = (int)extra->msg_param_gift_months;
	if (months) qty *= months; //Currently, you can't subbomb multimonths.

	stats->all += ({([
		"giver": ([
			"user_id": extra->user_id,
			"login": extra->login,
			"displayname": person->displayname,
		]),
		"tier": tier, "qty": qty,
		"timestamp": time(),
	])});
	//Assume that monthly is the type wanted. TODO: Make it configurable.
	if (!stats->monthly) stats->monthly = ([]);
	add_score(stats->monthly, "subs", stats->all[-1]);
	await(G->G->DB->save_config(channel->userid, "subgiftstats", stats));
	send_updates_all(channel, "");
	send_updates_all(channel, "control");
}

@hook_cheer:
__async__ int cheer(object channel, mapping person, int bits, mapping extra) {
	mapping stats = await(G->G->DB->load_config(channel->userid, "subgiftstats"));
	if (!stats->?active) return 0;
	await(task_sleep(1)); //Wait a second, then do a fast update (is that enough time?)
	force_recalc(channel, 1);
}

protected void create(string name) {::create(name);}
