inherit http_websocket;
constant markdown = #"# Channel points - dynamic rewards

Title | Base cost | Activation condition | Growth Formula | Current cost | Actions
------|-----------|----------------------|----------------|--------------|--------
-     | -         | -                    | -              | -            | (loading...)
{: #rewards}

[Add dynamic reward](:#add) Copy from: <select id=copyfrom><option value=\"-1\">(none)</option></select>

Choose how the price grows by setting a formula, for example:
* `PREV * 2` (double the price every time)
* `PREV + 500` (add 500 points per purchase)
* `PREV * 2 + 1500` (double it, then add 1500 points)

Rewards will reset to base price whenever the stream starts, and will be automatically
put on pause when the stream is offline. Note that, due to various delays, it's best to
have a cooldown on the reward itself - at least 30 seconds - to ensure that two people
can't claim the reward at the same price.

[Configure reward details here](https://dashboard.twitch.tv/viewer-rewards/channel-points/rewards)

<style>
input[type=number] {width: 4em;}
code {background: #ffe;}
</style>
";

/* Each one needs:
- ID, provided by Twitch. Clicking "New" assigns one.
- Base cost. Whenever the stream goes live, it'll be updated to this.
- Formula for calculating the next. Use PREV for the previous cost. Give examples.
- Title, which also serves as the description within the web page
- Other attributes maybe, or let people handle them elsewhere

TODO: Expand on chan_giveaway so it can handle most of the work, including the
JSON API for managing the rewards (the HTML page will be different though).
*/
continue Concurrent.Future fetch_rewards(string chan, string uid) {
	mapping info = yield(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + uid,
			(["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]])));
	G->G->channel_reward_list[chan] = info->data;
	//Prune the dynamic rewards list
	mapping current = persist_config["channels"][chan]->?dynamic_rewards;
	if (current) {
		write("Current dynamics: %O\n", current);
		multiset unseen = (multiset)indices(current) - (multiset)info->data->id;
		if (sizeof(unseen)) {m_delete(current, ((array)unseen)[*]); persist_config->save();}
	}
	send_updates_all("#" + chan);
}

//Event messages have all the info that we get by querying, but NOT in the same format.
mapping remap_eventsub_message(mapping info) {
	foreach (({
		({0, "broadcaster_user_id", "broadcaster_id"}),
		({0, "broadcaster_user_login", "broadcaster_login"}),
		({0, "broadcaster_user_name", "broadcaster_name"}),
		({0, "global_cooldown", "global_cooldown_setting"}),
		({0, "max_per_stream", "max_per_stream_setting"}),
		({0, "max_per_user_per_stream", "max_per_user_per_stream_setting"}),
		({"global_cooldown_setting", "seconds", "global_cooldown_seconds"}),
		({"max_per_stream_setting", "value", "max_per_stream_setting"}),
		({"max_per_user_per_stream_setting", "value", "max_per_user_per_stream"}),
	}), [string elem, string from, string to]) {
		mapping el = elem ? info[elem] : info;
		if (el && !undefinedp(el[from])) el[to] = m_delete(el, from);
	}
	return info;
}

EventSub rewardadd = EventSub("rewardadd", "channel.channel_points_custom_reward.add", "1") {
	[string chan, mapping info] = __ARGS__;
	if (!G->G->channel_reward_list[chan]) return;
	G->G->channel_reward_list[chan] += ({remap_eventsub_message(info)});
	send_updates_all("#" + chan);
};
EventSub rewardupd = EventSub("rewardupd", "channel.channel_points_custom_reward.update", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = G->G->channel_reward_list[chan];
	if (!rew) return;
	foreach (rew; int i; mapping reward)
		if (rew->id == info->id) {rew[i] = remap_eventsub_message(info); break;}
	send_updates_all("#" + chan);
};
EventSub rewardrem = EventSub("rewardrem", "channel.channel_points_custom_reward.remove", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = G->G->channel_reward_list[chan];
	if (!rew) return;
	G->G->channel_reward_list[chan] = filter(rew) {return __ARGS__[0]->id != info->id;};
	send_updates_all("#" + chan);
};

void make_hooks(string chan, int broadcaster_id) {
	rewardadd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardupd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardrem(chan, (["broadcaster_user_id": (string)broadcaster_id]));
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_bcaster_login(req, "channel:manage:redemptions")) return resp;
	string chan = req->misc->channel->name[1..];
	make_hooks(chan, req->misc->session->user->id);
	//Fire-and-forget a reward listing
	if (!G->G->channel_reward_list[chan]) G->G->channel_reward_list[chan] = ({ });
	handle_async(fetch_rewards(chan, req->misc->session->user->id)) { };
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

mapping get_chan_state(object channel, string grp, string|void id) {
	array rewards = ({ }), allrewards = G->G->channel_reward_list[channel->name[1..]];
	mapping current = channel->config->dynamic_rewards || ([]);
	foreach (allrewards, mapping rew) {
		mapping r = current[rew->id];
		if (r) rewards += ({r | (["id": rew->id, "title": r->title = rew->title, "curcost": rew->cost])});
		write("Dynamic ID %O --> %O\n", rew->id, r);
	}
	return (["items": rewards, "allrewards": allrewards]);
}

protected void create(string name) {
	::create(name);
	if (!G->G->channel_reward_list) G->G->channel_reward_list = ([]);
}
