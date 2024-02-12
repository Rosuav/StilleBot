inherit hook;
inherit annotated;

@retain: mapping pointsrewards = ([]);
@retain: mapping(int:multiset(string)) rewards_manageable = ([]); //rewards_manageable[broadcaster_id][reward_id] is 1 if we can edit that reward

@create_hook:
constant point_redemption = ({"string chan", "string rewardid", "int(0..1) refund", "mapping data"});
@create_hook:
constant reward_changed = ({"object channel", "string|void rewardid"}); //If no second arg, could be all rewards changed

void points_redeemed(string chanid, mapping data, int|void removal)
{
	object channel = G->G->irc->id[(int)chanid]; if (!channel) return;
	event_notify("point_redemption", channel, data->reward->id, removal, data);
	mapping cfg = channel->config;
	string token = token_for_user_login(cfg->login)[0];

	if (mapping dyn = !removal && cfg->dynamic_rewards && cfg->dynamic_rewards[data->reward->id]) {
		//Up the price every time it's redeemed
		//For this to be viable, the reward needs a global cooldown of
		//at least a few seconds, preferably a few minutes.
		int newcost = (int)G->G->evaluate_expr(channel->expand_variables(replace(dyn->formula, "PREV", (string)data->reward->cost)), ({channel, ([])}));
		if ((string)newcost != (string)data->reward->cost)
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ data->broadcaster_user_id + "&id=" + data->reward->id,
				(["Authorization": "Bearer " + token]),
				(["method": "PATCH", "json": (["cost": newcost])]),
			);
	}
	if (channel && !removal) foreach (channel->redemption_commands[data->reward->id] || ({ }), string cmd) {
		channel->send(([
			"displayname": data->user_name, "user": data->user_login,
			"uid": data->user_id,
		]), channel->commands[cmd], ([
			"%s": data->user_input,
			"{rewardid}": data->reward->id, "{redemptionid}": data->id,
		]));
	}
}

EventSub redemption = EventSub("redemption", "channel.channel_points_custom_reward_redemption.add", "1", points_redeemed);
EventSub redemptiongone = EventSub("redemptiongone", "channel.channel_points_custom_reward_redemption.update", "1") {points_redeemed(@__ARGS__, 1);};

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
	if (rewards_manageable[(int)info->broadcaster_id][?info->id]) info->can_manage = 1;
	mapping current = G->G->irc->id[(int)info->broadcaster_id]->?config->?dynamic_rewards;
	if (current[?info->id]) info->is_dynamic = 1;
	return info;
}

EventSub rewardadd = EventSub("rewardadd", "channel.channel_points_custom_reward.add", "1") {
	[string chanid, mapping info] = __ARGS__;
	if (!pointsrewards[(int)chanid]) return;
	pointsrewards[(int)chanid] += ({remap_eventsub_message(info)});
	event_notify("reward_changed", G->G->irc->id[(int)chanid], info->id);
};
EventSub rewardupd = EventSub("rewardupd", "channel.channel_points_custom_reward.update", "1") {
	[string chanid, mapping info] = __ARGS__;
	array rew = pointsrewards[(int)chanid];
	if (!rew) return;
	foreach (rew; int i; mapping reward)
		if (reward->id == info->id) {rew[i] = remap_eventsub_message(info); break;}
	event_notify("reward_changed", G->G->irc->id[(int)chanid], info->id);
};
EventSub rewardrem = EventSub("rewardrem", "channel.channel_points_custom_reward.remove", "1") {
	[string chanid, mapping info] = __ARGS__;
	array rew = pointsrewards[(int)chanid];
	if (!rew) return;
	pointsrewards[(int)chanid] = filter(rew) {return __ARGS__[0]->id != info->id;};
	object channel = G->G->irc->id[(int)chanid];
	mapping dyn = channel->?config->?dynamic_rewards;
	if (dyn) {m_delete(dyn, info->id); channel->config_save();}
	event_notify("reward_changed", G->G->irc->id[(int)chanid], info->id);
};

__async__ void update_dynamic_reward(object channel, string rewardid) {
	mapping rwd = channel->config->dynamic_rewards[rewardid];
	if (!rwd) return 0;
	mapping updates = ([]);
	mapping cur = ([]); //If the reward isn't found, assume everything has changed.
	foreach (pointsrewards[channel->userid], mapping r) if (r->id == rewardid) cur = r;
	foreach ("title prompt" / " ", string kwd) if (rwd[kwd]) {
		string value = channel->expand_variables(rwd[kwd]);
		if (value != cur[kwd]) updates[kwd] = value;
	}
	if (!sizeof(updates)) return 0;
	string token = await(token_for_user_id_async(channel->userid))[0];
	mixed resp = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + rewardid,
		(["Authorization": "Bearer " + token]),
		(["method": "PATCH", "json": updates]),
	));
	//TODO: Error check
	//Note that the update doesn't need to be pushed through the cache, as the
	//rewardupd hook above should do this for us. It would speed things up though.
}

multiset pending_update_alls = (<>);
__async__ void update_all_rewards(object channel) {
	pending_update_alls[channel->userid] = 0;
	foreach (channel->config->dynamic_rewards || ([]); string rewardid; mapping rwd)
		await(update_dynamic_reward(channel, rewardid));
}

@hook_variable_changed: void notify_rewards(object channel, string varname, string newval) {
	//TODO: Figure out which rewards might have changed (ie which are affected by
	//the variable that changed) and update only those.
	if (!channel->config->dynamic_rewards) return;
	if (pending_update_alls[channel->userid]) return; //If multiple variables are updated all at once, do just one batch of updates at the end
	pending_update_alls[channel->userid] = 1;
	call_out(spawn_task, 0, update_all_rewards(channel));
}

__async__ void populate_rewards_cache(string chan, string|int|void broadcaster_id) {
	if (!broadcaster_id) broadcaster_id = await(get_user_id(chan));
	pointsrewards[(int)broadcaster_id] = ({ }); //If there's any error, don't keep retrying
	string url = "https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id;
	mapping params = (["Authorization": "Bearer " + await(token_for_user_id_async(broadcaster_id))[0]]);
	array rewards = await(twitch_api_request(url, params))->data;
	//Prune the dynamic rewards list
	object channel = G->G->irc->id[(int)broadcaster_id];
	mapping current = channel->?config->?dynamic_rewards;
	if (current) {
		multiset unseen = (multiset)indices(current) - (multiset)rewards->id;
		if (sizeof(unseen)) {m_delete(current, ((array)unseen)[*]); channel->config_save();}
	}
	multiset manageable = rewards_manageable[broadcaster_id] = (multiset)await(twitch_api_request(url + "&only_manageable_rewards=true", params))->data->id;
	foreach (rewards, mapping r) {
		r->can_manage = manageable[r->id];
		if (current[?r->id]) r->is_dynamic = 1;
	}
	pointsrewards[(int)broadcaster_id] = rewards;
	broadcaster_id = (string)broadcaster_id;
	rewardadd(broadcaster_id, (["broadcaster_user_id": broadcaster_id]));
	rewardupd(broadcaster_id, (["broadcaster_user_id": broadcaster_id]));
	rewardrem(broadcaster_id, (["broadcaster_user_id": broadcaster_id]));
	redemption(broadcaster_id, (["broadcaster_user_id": broadcaster_id]));
	redemptiongone(broadcaster_id, (["broadcaster_user_id": broadcaster_id]));
	event_notify("reward_changed", channel, 0);
}

protected void create(string name) {
	::create(name);
	G->G->populate_rewards_cache = populate_rewards_cache;
	G->G->update_dynamic_reward = update_dynamic_reward;
	foreach (list_channel_configs(), mapping cfg) {
		if (!cfg->userid) continue;
		if (!pointsrewards[cfg->userid]) {
			string scopes = token_for_user_login(cfg->login)[1]; //TODO: Switch to ID when that's fundamental
			if (has_value(scopes / " ", "channel:manage:redemptions")
				|| has_value(scopes / " ", "channel:read:redemptions"))
					spawn_task(populate_rewards_cache(cfg->login, cfg->userid));
		}
	}
}
