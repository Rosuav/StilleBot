inherit http_websocket;

constant markdown = #"# Ads and snoozes

Loading...
{:#nextad}

$$controls||$$

<style>
#buttons button, #buttons select {font-size: 200%;}
</style>
";

@retain: mapping channel_ad_stats = ([]);

__async__ void check_stats(object channel) {
	mapping snooze = await(twitch_api_request("https://api.twitch.tv/helix/channels/ads?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]])))->data[0];
	snooze->time_captured = time();
	object since = G->G->stream_online_since[channel->userid];
	if (since) snooze->online_since = since->unix_time();
	channel_ad_stats[channel->userid] = snooze;
	send_updates_all(channel, "");
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	//NOTE: It seems that channel:manage:ads does not imply channel:read:ads.
	if (req->misc->session->fake) {
		//Demo mode uses some plausible information but won't send any updates.
		//These numbers are all pretty arbitrary.
		int basis = time();
		channel_ad_stats[0] = ([
			"last_ad_at": basis - 912,
			"duration": 60,
			"next_ad_at": basis + 1818,
			"preroll_free_time": 849,
			"snooze_count": 2,
			"snooze_refresh_at": basis + 3600 - 912,
			"time_captured": basis,
		]);
		return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
	}
	if (string scopes = ensure_bcaster_token(req, "channel:read:ads channel:manage:ads channel:edit:commercial"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator status"]) | req->misc->chaninfo);
	spawn_task(check_stats(req->misc->channel));
	string controls = "[Snooze](:#snooze) [Run Ad](:#runad) <select id=adlength><option>30<option selected>60<option>90<option>120<option>180</select> <span id=adtriggered></span>\n{:#buttons}";
	if ((int)req->misc->session->user->id == req->misc->channel->userid) {
		int state = req->misc->channel->config->snoozeads_mods;
		controls += "\n\n<select id=modsnooze><option value=0" + (!state ? " selected" : "") + ">Mods may not snooze ads<option value=1" + (state ? " selected" : "") + ">Mods may snooze ads on your behalf</select>";
	} else {
		if (!req->misc->channel->config->snoozeads_mods) controls = "";
	}
	return render(req, ([
		"vars": (["ws_group": ""]),
		"controls": controls,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp, string|void id) {
	return channel_ad_stats[channel->userid];
}

void wscmd_snooze(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if ((int)conn->session->user->id != channel->userid && !channel->config->snoozeads_mods) return;
	twitch_api_request("https://api.twitch.tv/helix/channels/ads/schedule/snooze?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST"]))
	->then() {
		//Apply the changes directly to state if we have state
		if (channel_ad_stats[channel->userid]) {
			channel_ad_stats[channel->userid] |= __ARGS__[0]->data[0];
			send_updates_all(channel, "");
		}
		else spawn_task(check_stats(channel));
	};
}

void wscmd_runad(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if ((int)conn->session->user->id != channel->userid && !channel->config->snoozeads_mods) return;
	int length = (int)msg->adlength;
	if (length < 1 || length > 180) length = 60;
	twitch_api_request("https://api.twitch.tv/helix/channels/commercial?broadcaster_id=" + channel->userid
			+ "&length=" + length,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST"]))
	->then() {
		mapping resp = __ARGS__[0]->data[0];
		//When the ad starts, the webhook should notify us.
		if (conn->sock->?state) conn->sock->send_text(Standards.JSON.encode(([
			"cmd": "adtriggered",
			"length": resp->length,
			"message": resp->message,
		]), 4));
	};
}

void wscmd_modsnooze(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if ((int)conn->session->user->id != channel->userid) return;
	channel->config->snoozeads_mods = (int)msg->value;
	channel->save();
	send_updates_all(channel, "");
}
