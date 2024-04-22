inherit http_websocket;
inherit hook;
inherit annotated;

constant markdown = #"# Ads and snoozes

Loading...
{:#nextad}

$$controls||$$

Ad-vance warning: <input type=number id=advance_warning> seconds. Enables the [!!adsoon](specials#adsoon/) special trigger.

<style>
#buttons button, #buttons select {font-size: 200%;}
</style>
";

@retain: mapping channel_ad_stats = ([]);
@retain: mapping channel_ad_callouts = ([]);
@retain: mapping channel_ad_vance_warning = ([]);

__async__ void check_stats(object channel) {
	remove_call_out(channel_ad_callouts[channel->userid]);
	mapping snooze = await(twitch_api_request("https://api.twitch.tv/helix/channels/ads?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]])))->data[0];
	//NOTE: The docs say that the timestamps are given in text format, but they seem to be numbers.
	snooze->time_captured = time();
	object since = G->G->stream_online_since[channel->userid];
	if (since) {
		snooze->online_since = since->unix_time();
		if (int adv = channel->config->advance_warning) {
			//TODO: Bouncer?
			int next = snooze->next_ad_at - time();
			if (next > adv + 60) {
				next -= adv + 60; //Precheck to see if a snooze has happened
				m_delete(channel_ad_vance_warning, channel->userid);
			}
			else if (next > adv) {
				next -= adv; //Fire when this happens
				channel_ad_vance_warning[channel->userid] = 1;
			} else if (m_delete(channel_ad_vance_warning, channel->userid)) {
				//We set up to send the notification. Let's send it.
				//Leave next (roughly) where it is, and we'll recheck when the ad is scheduled.
				channel->trigger_special("!adsoon", (["user": channel->login]), (["{advance_warning}": (string)next]));
				//NOTE: If, in response to this message, the streamer hits a snooze, we'll most likely
				//need to get retriggered. Since we don't get notifications on snoozes, the best way to
				//know that this has happened is to ping Twitch at the time when the ad is due to occur,
				//but due to clock desync, this might be a little bit wrong. So we add a little bit of
				//delay here and ping Twitch two seconds AFTER the ad should have started.
				next += 2;
			}
			//Otherwise check when the ad is scheduled to fire.
			//We'll also get notified if an ad is explicitly run.
			if (next > 0) {
				werror("Scheduling next ad check for %O in %O seconds\n", channel->login, next);
				channel_ad_callouts[channel->userid] = call_out(check_stats_by_id, next, channel->userid);
			}
		}
	}
	channel_ad_stats[channel->userid] = snooze;
	send_updates_all(channel, "");
}

void check_stats_by_id(int chanid) {check_stats(G->G->irc->id[chanid]);} //After a delay, look up the channel object again, don't rely on retention
@EventNotify("channel.ad_break.begin=1"):
void ad_fired(object channel, mapping info) {
	m_delete(channel_ad_vance_warning, channel->userid);
	check_stats(channel);
}

@hook_channel_online: int channel_online(string chan, int uptime, int chanid) {
	object channel = G->G->irc->id[chanid]; if (!channel) return 0;
	if (channel->config->advance_warning) check_stats(channel);
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
	establish_notifications(req->misc->channel->userid);
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
	return (channel_ad_stats[channel->userid] || ([])) | (["advance_warning": channel->config->advance_warning]);
}

void wscmd_snooze(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if ((int)conn->session->user->id != channel->userid && !channel->config->snoozeads_mods) return;
	twitch_api_request("https://api.twitch.tv/helix/channels/ads/schedule/snooze?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST"]))
	->then() {
		//Apply the changes directly to state if we have state
		//TODO: Return to doing this, but update the ad-vance warning callout too. For now, just rechecking in full.
		/*if (channel_ad_stats[channel->userid]) {
			channel_ad_stats[channel->userid] |= __ARGS__[0]->data[0];
			send_updates_all(channel, "");
		}
		else*/ check_stats(channel);
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
	channel->botconfig->snoozeads_mods = (int)msg->value;
	channel->botconfig_save();
	send_updates_all(channel, "");
}

void wscmd_advance_warning(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	channel->botconfig->advance_warning = (int)msg->value;
	channel->botconfig_save();
	check_stats(channel); //Will send_updates_all when it has all the stats
}

protected void create(string name) {::create(name);}
