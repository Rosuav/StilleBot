inherit http_websocket;

constant markdown = #"# Ads and snoozes

Loading...
{:#nextad}

[Snooze](:#snooze) [Run Ad](:#runad) <select id=adlength><option>30<option selected>60<option>90<option>120<option>180</select>
{:#buttons}

<style>
#buttons button, #buttons select {font-size: 200%;}
</style>
";

@retain: mapping channel_ad_stats = ([]);

continue Concurrent.Future check_stats(object channel) {
	mapping snooze = yield(twitch_api_request("https://api.twitch.tv/helix/channels/ads?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]])))->data[0];
	snooze->time_captured = time();
	werror("%O\n", snooze);
	channel_ad_stats[channel->userid] = snooze;
	send_updates_all(channel->name);
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	//NOTE: It seems that channel:manage:ads does not imply channel:read:ads.
	if (string scopes = ensure_bcaster_token(req, "channel:read:ads channel:manage:ads channel:edit:commercial"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator status"]));
	spawn_task(check_stats(req->misc->channel));
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp, string|void id) {
	return channel_ad_stats[channel->userid];
}

void wscmd_snooze(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	twitch_api_request("https://api.twitch.tv/helix/channels/ads/schedule/snooze?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST"]))
	->then() {
		werror("SNOOZE RESULT: %O\n", __ARGS__);
		//Apply the changes directly to state if we have state
		if (channel_ad_stats[channel->userid]) {
			channel_ad_stats[channel->userid] |= __ARGS__[0]->data[0];
			send_updates_all(channel->name);
		}
		else spawn_task(check_stats(channel));
	};
}

void wscmd_runad(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	int length = (int)msg->adlength;
	if (length < 1 || length > 180) length = 60;
	twitch_api_request("https://api.twitch.tv/helix/channels/commercial?broadcaster_id=" + channel->userid
			+ "&length=" + length,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST"]))
	->then() {
		werror("RUN AD RESULT: %O\n", __ARGS__);
		spawn_task(check_stats(channel));
	};
}

/*
If broadcaster, full access, and also radio buttons to grant access to mods: None, View, Manage
If mod and access is None, report. If access is Manage, include the "Snooze" and "Run Ad" buttons.

Timeline across the top. Current time is shown at the left, stretching out into the future.
Tick marks above it to show the timestamps in stream uptime (1:02:00 meaning an hour and two minutes
since the stream went live).

Show, and allow configurable colours on the time tape for, all of:
* Preroll-free time (from time_captured until time_captured+preroll_free_time_seconds)
* Next scheduled ad (including its length)
* Snoozes available (not on the tape)
* Next snooze becomes available
* Maximum delay possible for next ad
* Based on selected ad length, proposed preroll-free time
* Time since last ad? Not on the tape. Does length_seconds apply to that?
*/
