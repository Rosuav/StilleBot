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
* \"Plus Points\" here are calculated simplistically by excluding gift subs. This only
  very roughly approximates to Twitch's calculation, and discrepancies can be expected.
";

constant tiers = (["1000": 1, "2000": 2, "3000": 6]); //Sub points per tier

mapping subpoints_cooldowns = ([]);

void delayed_get_sub_points(Concurrent.Promise p, string chan, string|void type) {
	m_delete(subpoints_cooldowns, chan);
	get_sub_points(chan, type)->then(p->success);
}

__async__ int|array get_sub_points(string chan, string|void type)
{
	if (type == "raw") {
		array cd = subpoints_cooldowns[chan];
		if (cd && cd[1]) return await(cd[1]);
		if (cd && cd[0] > time()) {
			//Not using task_sleep to ensure that it's reusable. We want multiple
			//clients to all wait until there's a result, then return the same.
			Concurrent.Promise p = Concurrent.Promise();
			call_out(delayed_get_sub_points, cd[0] - time(), p, chan, type);
			cd[1] = p->future();
			return await(cd[1]);
		}
		else subpoints_cooldowns[chan] = ({time() + 10, 0});
	}
	int uid = await(get_user_id(chan)); //Should come from cache
	array info = await(get_helix_paginated("https://api.twitch.tv/helix/subscriptions",
		(["broadcaster_id": (string)uid, "first": "99"]),
		(["Authorization": "Bearer " + token_for_user_id(uid)[0]])));
	if (type == "raw") return info;
	int points = 0;
	foreach (info, mapping sub)
		if (sub->user_id != sub->broadcaster_id) { //Ignore self
			switch (type) {
				case "subs": points += 1; break;
				case "plus": if (!sub->is_gift) points += tiers[sub->tier] || 10000; break;
				default: points += tiers[sub->tier] || 10000; break; //Hack: Big noisy thing if the tier is broken
			}
		}
	return points;
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string nonce = req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		mapping info = await(G->G->DB->load_config(req->misc->channel->userid, "subpoints"))[nonce];
		if (!info) return 0; //If you get the nonce wrong, just return an ugly 404 page.
		string style = "";
		if (info->font && info->font != "")
			style = sprintf("@import url(\"https://fonts.googleapis.com/css2?family=%s&display=swap\");"
					"#display {font-family: '%s', sans-serif;}"
					"%s", Protocols.HTTP.uri_encode(info->font), info->font, style);
		if ((int)info->fontsize) style += "#display {font-size: " + (int)info->fontsize + "px;}";
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "subpoints"]),
			"styles": style,
		]));
	}
	if (string scopes = ensure_bcaster_token(req, "channel:read:subscriptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	string chan = req->misc->channel->name[1..];
	if (req->misc->session->user->?login != chan //This is sensitive information, so it's broadcaster-only.
		//&& !is_localhost_mod(req->misc->session->user->?login, req->get_ip()) //But testing may at times be needed.
	)
		return render_template("login.md", (["msg": "authentication as the broadcaster"]));
	array info = await(get_sub_points(chan, "raw"));
	if (req->variables->raw) return render(req, ([
		"vars": (["ws_group": ""]),
		"points": sprintf("<pre>%O</pre>", info),
	]) | req->misc->chaninfo);
	mapping(string:int) tiercount = ([]), gifts = ([]);
	array(string) tierlist = ({ });
	mapping(string|int:mapping) usersubs = ([]);
	foreach (info, mapping sub)
	{
		if (sub->user_id == sub->broadcaster_id) continue; //Ignore self
		if (usersubs[sub->user_id])
		{
			//This can happen if someone upgrades. I don't know how sub points get counted.
			//For example, if you upgrade from T1 to T3, your old sub was worth 1 and your
			//new one is worth 6. Are you currently worth 6 or 7? For now, I'm going to let
			//this through and thus count it as 7.
			if (usersubs[sub->user_id]->tier == sub->tier) {
				//But if the tier is the same, what then? A pagination failure?
				tierlist += ({sprintf("Duplicate! <pre>%O\n%O\n</pre><br>\n", usersubs[sub->user_id], sub)});
			}
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
	int uid = await(get_user_id(chan)); //Should come from cache
	mapping raw = await(twitch_api_request("https://api.twitch.tv/helix/subscriptions?broadcaster_id=" + uid,
		(["Authorization": "Bearer " + token_for_user_id(uid)[0]])));
	return render(req, ([
		"vars": (["ws_group": ""]),
		"points": sort(tierlist) * ""
			+ sprintf("Total: %d subs, %d points", tot, pts)
			+ (totgifts ? sprintf(", of which %d (%d) are gifts", totgiftpts, totgifts) : "")
			+ sprintf("<br>\nTotal as reported by Twitch: %d", raw->points)
			+ sprintf("<br>\nPartner Plus points: %d (minus those from Prime subs)", raw->points - totgiftpts),
	]) | req->misc->chaninfo);
}

__async__ void subpoints_updated(string hook, string chan, mapping info) {
	//TODO: If it's reliable, maintain the subpoint figure and adjust it, instead of re-fetching.
	Stdio.append_file("evt_subpoints.log", sprintf("EVENT: Subpoints %s [%O, %d]: %O\n", hook, chan, time(), info));
	object channel = G->G->irc->channels["#" + chan];
	mapping trackers = await(G->G->DB->load_config(channel->userid, "subpoints"));
	if (!sizeof(trackers)) return;
	int points = await(get_sub_points(chan));
	Stdio.append_file("evt_subpoints.log", sprintf("Updated subpoint count: %d\n", points));
	foreach (trackers; string nonce; mapping tracker)
		send_updates_all(channel, nonce, tracker | (["points": points - (int)tracker->unpaidpoints]));
}
EventSub hook_sub = EventSub("sub", "channel.subscribe", "1") {subpoints_updated("sub", @__ARGS__);};
EventSub hook_subend = EventSub("subend", "channel.subscription.end", "1") {subpoints_updated("subend", @__ARGS__);};
EventSub hook_subgift = EventSub("subgift", "channel.subscription.gift", "1") {subpoints_updated("subgift", @__ARGS__);};
EventSub hook_submessage = EventSub("submessage", "channel.subscription.message", "1") {subpoints_updated("submessage", @__ARGS__);};

bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping trackers = await(G->G->DB->load_config(channel->userid, "subpoints"));
	string chan = channel->name[1..];
	int uid = channel->userid;
	hook_sub(chan, (["broadcaster_user_id": (string)uid]));
	hook_subend(chan, (["broadcaster_user_id": (string)uid]));
	hook_subgift(chan, (["broadcaster_user_id": (string)uid]));
	hook_submessage(chan, (["broadcaster_user_id": (string)uid]));
	if (grp != "") {
		if (!trackers[grp]) return (["data": 0]); //If you delete the tracker with the page open, it'll be a bit ugly.
		string type = trackers[grp]->goaltype || "points";
		int points = await(get_sub_points(channel->name[1..], type));
		Stdio.append_file("evt_subpoints.log", sprintf("Fresh load, subpoint count: %d %s\n", points, type));
		return trackers[grp] | (["points": points - (int)trackers[grp]->unpaidpoints]);
	}
	if (id) return trackers[id];
	array t = values(trackers); sort(t->created, t);
	return (["items": t]);
}

void websocket_cmd_create(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	string nonce = replace(MIME.encode_base64(random_string(30)), (["/": "1", "+": "0"]));
	G->G->DB->mutate_config(channel->userid, "subpoints") {
		__ARGS__[0][nonce] = (["id": nonce, "created": time()]);
	}->then() {send_updates_all(conn->group);};
}

void websocket_cmd_save(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	G->G->DB->mutate_config(channel->userid, "subpoints") {
		mapping tracker = __ARGS__[0][msg->id];
		if (!tracker) return;
		foreach ("unpaidpoints font fontsize goal goaltype usecomfy" / " ", string k)
			if (!undefinedp(msg[k])) tracker[k] = msg[k];
	}->then() {send_updates_all(conn->group);};
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return;
	G->G->DB->mutate_config(channel->userid, "subpoints") {
		m_delete(__ARGS__[0], msg->id);
	}->then() {send_updates_all(conn->group);};
}
