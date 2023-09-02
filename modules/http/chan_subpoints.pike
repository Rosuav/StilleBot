inherit http_websocket;

constant markdown = #"# Subpoints trackers for $$channel$$

<style>input[type=number] {width: 4em;}</style>

$$points$$

Unpaid | Font | Goal | Options | Actions | Link
-------|------|------|---------|---------|--------
loading... | - | - | - | - | -
{:#trackers}

[Add tracker](:#add_tracker)

* Unpaid points (eg for a bot) can also be adjusted to correct for API errors
* Changing the font or options will require a refresh of the in-OBS page
* In-chat notifications add load to your OBS, but *might* improve reliability.
  Regardless of this setting, an event hook will be active, which may be sufficient.
";

constant tiers = (["1000": 1, "2000": 2, "3000": 6]); //Sub points per tier

mapping subpoints_cooldowns = ([]);

void delayed_get_sub_points(Concurrent.Promise p, string chan) {
	m_delete(subpoints_cooldowns, chan);
	spawn_task(get_sub_points(chan), p->success);
}

continue mapping|Concurrent.Future get_sub_points(string chan, int|void raw)
{
	if (!raw) {
		array cd = subpoints_cooldowns[chan];
		if (cd && cd[1]) return yield(cd[1]);
		if (cd && cd[0] > time()) {
			//Not using task_sleep to ensure that it's reusable. We want multiple
			//clients to all wait until there's a result, then return the same.
			Concurrent.Promise p = Concurrent.Promise();
			call_out(delayed_get_sub_points, cd[0] - time(), p, chan);
			cd[1] = p->future();
			return yield(cd[1]);
		}
		else subpoints_cooldowns[chan] = ({time() + 10, 0});
	}
	int uid = yield(get_user_id(chan)); //Should come from cache
	array info = yield(get_helix_paginated("https://api.twitch.tv/helix/subscriptions",
		(["broadcaster_id": (string)uid, "first": "99"]),
		(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
	if (raw) return info;
	int points = 0;
	foreach (info, mapping sub)
		if (sub->user_id != sub->broadcaster_id) //Ignore self
			points += tiers[sub->tier] || 10000; //Hack: Big noisy thing if the tier is broken
	return points;
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (string nonce = req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		mapping info = cfg->subpoints[?nonce];
		if (!info) return 0; //If you get the nonce wrong, just return an ugly 404 page.
		string style = "";
		if (info->font && info->font != "")
			style = sprintf("@import url(\"https://fonts.googleapis.com/css2?family=%s&display=swap\");"
					"#display {font-family: '%s', sans-serif;}"
					"%s", Protocols.HTTP.uri_encode(info->font), info->font, style);
		if ((int)info->fontsize) style += "#display {font-size: " + (int)info->fontsize + "px;}";
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + req->misc->channel->name, "ws_code": "subpoints"]),
			"styles": style,
		]));
	}
	if (string scopes = ensure_bcaster_token(req, "channel:read:subscriptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	string chan = req->misc->channel->name[1..];
	if (req->misc->session->user->?login != chan) //This is sensitive information, so it's broadcaster-only.
		return render_template("login.md", (["msg": "authentication as the broadcaster"]));
	array info = yield(get_sub_points(chan, 1));
	mapping(string:int) tiercount = ([]), gifts = ([]);
	array(string) tierlist = ({ });
	mapping(string|int:mapping) usersubs = ([]);
	foreach (info, mapping sub)
	{
		if (sub->user_id == sub->broadcaster_id) continue; //Ignore self
		if (usersubs[sub->user_id])
		{
			//Don't know how this would happen, but maybe a pagination failure???
			tierlist += ({sprintf("Duplicate! <pre>%O\n%O\n</pre><br>\n", usersubs[sub->user_id], sub)});
		}
		usersubs[sub->user_id] = sub;
		tiercount[sub->tier]++; if (sub->is_gift) gifts[sub->tier]++;
		if (!tiers[sub->tier]) tierlist += ({sprintf("Unknown sub tier %O<br>\n", sub->tier)});
		//Try to figure out if we get any extra info
		mapping unknowns = sub - (<
			"broadcaster_id", "broadcaster_name", "broadcaster_login",
			"gifter_id", "gifter_name", "gifter_login", "is_gift",
			"plan_name", "tier", "user_id", "user_name", "user_login",
		>);
		if (sizeof(unknowns)) tierlist += ({sprintf("Unknown additional info on %s's sub:%{ %O%}<br>\n", sub->user_name, indices(unknowns))});
	}
	int tot, pts, totgifts, totgiftpts;
	foreach (tiercount; string tier; int count)
	{
		tot += count; pts += tiers[tier] * count;
		totgifts += gifts[tier]; totgiftpts += tiers[tier] * gifts[tier];
		string gift = gifts[tier] ? sprintf(", of which %d (%d) are gifts", tiers[tier] * gifts[tier], gifts[tier]) : "";
		tierlist += ({sprintf("Tier %c: %d (%d)%s<br>\n", tier[0], tiers[tier] * count, count, gift)});
	}
	int uid = yield(get_user_id(chan)); //Should come from cache
	mapping raw = yield(twitch_api_request("https://api.twitch.tv/helix/subscriptions?broadcaster_id=" + uid,
		(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
	return render(req, ([
		"vars": (["ws_group": ""]),
		"points": sort(tierlist) * ""
			+ sprintf("Total: %d subs, %d points", tot, pts)
			+ (totgifts ? sprintf(", of which %d (%d) are gifts", totgiftpts, totgifts) : "")
			+ sprintf("<br>\nPartner Plus points: %d", pts - totgiftpts)
			+ sprintf("<br>\nTotal as reported by Twitch: %d", raw->points),
	]) | req->misc->chaninfo);
}

void subpoints_updated(string hook, string chan, mapping info) {
	//TODO: If it's reliable, maintain the subpoint figure and adjust it, instead of re-fetching.
	Stdio.append_file("evt_subpoints.log", sprintf("EVENT: Subpoints %s [%O, %d]: %O\n", hook, chan, time(), info));
	object channel = G->G->irc->channels["#" + chan];
	mapping cfg = channel->?config->?subpoints;
	if (!cfg || !sizeof(cfg)) return;
	spawn_task(get_sub_points(chan)) {
		int points = __ARGS__[0];
		Stdio.append_file("evt_subpoints.log", sprintf("Updated subpoint count: %d\n", points));
		foreach (cfg; string nonce; mapping tracker)
			send_updates_all(nonce + "#" + chan, tracker | (["points": points - (int)tracker->unpaidpoints]));
	};
}
EventSub hook_sub = EventSub("sub", "channel.subscribe", "1") {subpoints_updated("sub", @__ARGS__);};
EventSub hook_subend = EventSub("subend", "channel.subscription.end", "1") {subpoints_updated("subend", @__ARGS__);};
EventSub hook_subgift = EventSub("subgift", "channel.subscription.gift", "1") {subpoints_updated("subgift", @__ARGS__);};
EventSub hook_submessage = EventSub("submessage", "channel.subscription.message", "1") {subpoints_updated("submessage", @__ARGS__);};

//bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
continue mapping|Concurrent.Future get_state(string|int group, string|void id) { //get_chan_state isn't asynchronous-compatible
	[object channel, string grp] = split_channel(group);
	if (!channel) return 0;
	mapping trackers = channel->config->subpoints || ([]);
	string chan = channel->name[1..];
	int uid = yield(get_user_id(chan));
	hook_sub(chan, (["broadcaster_user_id": (string)uid]));
	hook_subend(chan, (["broadcaster_user_id": (string)uid]));
	hook_subgift(chan, (["broadcaster_user_id": (string)uid]));
	hook_submessage(chan, (["broadcaster_user_id": (string)uid]));
	if (grp != "") {
		if (!trackers[grp]) return (["data": 0]); //If you delete the tracker with the page open, it'll be a bit ugly.
		int points = yield(get_sub_points(channel->name[1..]));
		Stdio.append_file("evt_subpoints.log", sprintf("Fresh load, subpoint count: %d\n", points));
		return trackers[grp] | (["points": points - (int)trackers[grp]->unpaidpoints]);
	}
	if (id) return trackers[id];
	array t = values(trackers); sort(t->created, t);
	return (["items": t]);
}

void websocket_cmd_create(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	if (!channel->config->subpoints) channel->config->subpoints = ([]);
	string nonce = replace(MIME.encode_base64(random_string(30)), (["/": "1", "+": "0"]));
	channel->config->subpoints[nonce] = (["id": nonce, "created": time()]);
	persist_config->save();
	send_updates_all(conn->group);
}

void websocket_cmd_save(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	mapping tracker = channel->config->subpoints[?msg->id];
	if (!tracker) return;
	foreach ("unpaidpoints font fontsize goal usecomfy" / " ", string k)
		if (!undefinedp(msg[k])) tracker[k] = msg[k];
	persist_config->save();
	send_updates_all(conn->group);
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	mapping cfg = channel->config->subpoints;
	if (cfg[?msg->id]) {
		m_delete(cfg, msg->id);
		persist_config->save();
		send_updates_all(conn->group);
	}
}
