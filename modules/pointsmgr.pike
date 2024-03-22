inherit hook;
inherit annotated;

@retain: mapping pointsrewards = ([]);
@retain: mapping(int:multiset(string)) rewards_manageable = ([]); //rewards_manageable[broadcaster_id][reward_id] is 1 if we can edit that reward

@create_hook:
constant point_redemption = ({"string chan", "string rewardid", "int(0..1) refund", "mapping data"});
@create_hook:
constant reward_changed = ({"object channel", "string|void rewardid"}); //If no second arg, could be all rewards changed

@EventNotify("channel.channel_points_custom_reward_redemption.update=1"):
void redemptiongone(object channel, mapping data) {points_redeemed1(channel, data, 1);} //Not an async annotation shim, this one remains (as points_redeemed).
@EventNotify("channel.channel_points_custom_reward_redemption.add=1"):
void points_redeemed(object channel, mapping data) {points_redeemed1(channel, data, 0);}
__async__ void points_redeemed1(object channel, mapping data, int|void removal) {
	if (!channel) return;
	werror("points_redeemed(%O) [%d] %O\n", channel->name, removal, data);
	event_notify("point_redemption", channel, data->reward->id, removal, data);
	string token = token_for_user_id(channel->userid)[0];

	mapping all_dyn = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	if (mapping dyn = !removal && all_dyn[data->reward->id]) {
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
	//There's something borked about these already, so I'm not migrating it to the new
	//way to look up dynamic rewards. TODO: Fix this so that updating of rewards doesn't
	//lose these "is dynamic" and "is manageable" flags.
	if (rewards_manageable[(int)info->broadcaster_id][?info->id]) info->can_manage = 1;
	//mapping current = G->G->irc->id[(int)info->broadcaster_id]->?config->?dynamic_rewards;
	//if (current[?info->id]) info->is_dynamic = 1;
	return info;
}

@EventNotify("channel.channel_points_custom_reward.add=1"):
void rewardadd(object channel, mapping info) {
	if (!pointsrewards[channel->userid]) return;
	pointsrewards[channel->userid] += ({remap_eventsub_message(info)});
	event_notify("reward_changed", channel, info->id);
};
@EventNotify("channel.channel_points_custom_reward.update=1"):
void rewardupd(object channel, mapping info) {
	array rew = pointsrewards[channel->userid];
	if (!rew) return;
	foreach (rew; int i; mapping reward)
		if (reward->id == info->id) {rew[i] = remap_eventsub_message(info); break;}
	event_notify("reward_changed", channel, info->id);
};
@EventNotify("channel.channel_points_custom_reward.remove=1"):
void rewardrem(object channel, mapping info) {
	array rew = pointsrewards[channel->userid];
	if (!rew) return;
	pointsrewards[channel->userid] = filter(rew) {return __ARGS__[0]->id != info->id;};
	G->G->DB->mutate_config(channel->userid, "dynamic_rewards") {m_delete(__ARGS__[0], info->id);};
	event_notify("reward_changed", channel, info->id);
};

__async__ void update_dynamic_reward(object channel, string rewardid, mapping rwd) {
	if (!rwd) return 0;
	mapping updates = ([]);
	mapping cur = ([]); //If the reward isn't found, assume everything has changed.
	foreach (pointsrewards[channel->userid] || ({ }), mapping r) if (r->id == rewardid) cur = r;
	foreach ("title prompt" / " ", string kwd) if (rwd[kwd]) {
		string value = channel->expand_variables(rwd[kwd]);
		if (value != cur[kwd]) updates[kwd] = value;
	}
	if (!sizeof(updates)) return 0;
	string token = token_for_user_id(channel->userid)[0];
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
	mapping dyn = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	foreach (dyn; string rewardid; mapping rwd)
		await(update_dynamic_reward(channel, rewardid, rwd));
}

@hook_variable_changed: void notify_rewards(object channel, string varname, string newval) {
	//TODO: Figure out which rewards might have changed (ie which are affected by
	//the variable that changed) and update only those.
	if (pending_update_alls[channel->userid]) return; //If multiple variables are updated all at once, do just one batch of updates at the end
	pending_update_alls[channel->userid] = 1;
	call_out(spawn_task, 0, update_all_rewards(channel));
}

__async__ void populate_rewards_cache(string|int broadcaster_id) {
	pointsrewards[(int)broadcaster_id] = ({ }); //If there's any error, don't keep retrying
	string url = "https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id;
	mapping params = (["Authorization": "Bearer " + token_for_user_id(broadcaster_id)[0]]);
	array rewards = await(twitch_api_request(url, params))->data;
	//Prune the dynamic rewards list
	object channel = G->G->irc->id[(int)broadcaster_id];
	mapping current = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	if (current) {
		multiset unseen = (multiset)indices(current) - (multiset)rewards->id;
		if (sizeof(unseen)) {
			m_delete(current, ((array)unseen)[*]);
			await(G->G->DB->save_config(channel->userid, "dynamic_rewards", current));
		}
	}
	multiset manageable = rewards_manageable[(int)broadcaster_id] = (multiset)await(twitch_api_request(url + "&only_manageable_rewards=true", params))->data->id;
	foreach (rewards, mapping r) {
		r->can_manage = manageable[r->id];
		if (current[?r->id]) r->is_dynamic = 1;
	}
	pointsrewards[(int)broadcaster_id] = rewards;
	establish_notifications(broadcaster_id);
	event_notify("reward_changed", channel, 0);
}

@on_irc_loaded: void populate_all_rewards() {
	foreach (indices(G->G->irc->id), int userid)
		if (userid && !pointsrewards[userid]) {
			string scopes = token_for_user_id(userid)[1];
			if (has_value(scopes / " ", "channel:manage:redemptions")
				|| has_value(scopes / " ", "channel:read:redemptions"))
					populate_rewards_cache(userid);
		}
}

protected void create(string name) {
	::create(name);
	G->G->populate_rewards_cache = populate_rewards_cache;
	G->G->update_dynamic_reward = update_dynamic_reward;
}
