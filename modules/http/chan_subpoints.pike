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

continue mapping|Concurrent.Future get_sub_points(string chan, int|void raw)
{
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
	if (mapping resp = ensure_login(req, "channel:read:subscriptions")) return resp;
	string chan = req->misc->channel->name[1..];
	if (chan != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //As with chan_giveaway, would be nice to reword that
	persist_status->path("bcaster_token")[chan] = req->misc->session->token;
	persist_status->save();
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
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
	return render(req, ([
		"vars": (["ws_group": ""]),
		"points": sort(tierlist) * ""
			+ sprintf("Total: %d subs, %d points", tot, pts)
			+ (totgifts ? sprintf(", of which %d (%d) are gifts", totgiftpts, totgifts) : ""),
	]) | req->misc->chaninfo);
}

//bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
continue mapping|Concurrent.Future get_state(string|int group, string|void id) { //get_chan_state isn't asynchronous-compatible
	[object channel, string grp] = split_channel(group);
	if (!channel) return 0;
	mapping trackers = channel->config->subpoints || ([]);
	string chan = channel->name[1..];
	if (!G->G->webhook_signer["sub=" + chan]) {
		int uid = yield(get_user_id(chan));
		create_eventsubhook(
			"sub=" + chan,
			"channel.subscribe", "1",
			(["broadcaster_user_id": (string)uid]),
		);
		foreach ("end gift message" / " ", string hook)
			create_eventsubhook(
				sprintf("sub%s=%s", hook, chan),
				"channel.subscription." + hook, "1",
				(["broadcaster_user_id": (string)uid]),
			);
	}
	if (grp != "") {
		if (!trackers[grp]) return (["data": 0]); //If you delete the tracker with the page open, it'll be a bit ugly.
		int points = yield(get_sub_points(channel->name[1..]));
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

void subpoints_updated(string hook, string chan, mapping info) {
	//TODO: If it's reliable, maintain the subpoint figure and adjust it, instead of re-fetching.
	Stdio.append_file("evthook.log", sprintf("EVENT: Subpoints %s [%O, %d]: %O\n", hook, chan, time(), info));
	object channel = G->G->irc->channels["#" + chan];
	mapping cfg = channel->config->subpoints;
	if (!cfg || !sizeof(cfg)) return;
	handle_async(get_sub_points(chan)) {
		int points = __ARGS__[0];
		foreach (cfg; string nonce; mapping tracker)
			send_updates_all(nonce + "#" + chan, tracker | (["points": points - (int)tracker->unpaidpoints]));
	};
}

protected void create(string name)
{
	::create(name);
	foreach ("sub subend subgift submessage" / " ", string hook) G->G->webhook_endpoints[hook] = Function.curry(subpoints_updated)(hook);
}
