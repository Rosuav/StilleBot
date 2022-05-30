inherit http_websocket;
inherit builtin_command;
inherit hook;
constant hidden_command = 1;
constant access = "none";
constant markdown = #"# Points rewards - $$channel$$

* TODO: Allow commands to be triggered by channel point redemptions.
{:#rewards}

This will eventually have a list of all your current rewards, whether they can be managed
by StilleBot, and a place to attach behaviour to them. Coupled with appropriate use of
channel voices, this can allow a wide variety of interactions with other bots.
";

/* Ultimately this should be the master management for all points rewards. All shared code for
dynamics, giveaway, etc should migrate into here.

Dynamic pricing will now be implemented with a trigger on redemption that updates price. The
chan_dynamics page will set these up for you.

Dynamic activation will be implemented with a trigger on channel online/offline, or on setup,
that enables or disables a reward. Ditto, chan_dynamics will set these up for you.

Creating rewards (or duplicating existing) can be done here.

Will need to report ALL rewards, not just for copying; the table will need to list every
reward and allow it to have a command attached.

Dynamic management of rewards that weren't created by my client_id has to be rejected. (See
the can_manage flag in the front end; it's 1 if editable, absent if not.)

There are three levels of permission that can be granted:
0) No permissions. Bot has no special access, but can see reward IDs for those that have
   messages. No official support for this, but it might be nice to provide the reward ID
   in normal command/trigger invocation.
1) Read-only access (channel:read:redemptions). We can enumerate rewards but none of them
   can be managed. It will be possible to react to any reward (regardless of who made it),
   even without text, but not possible to mark them as completed.
2) Full access (channel:manage:redemptions). We can create rewards, which we would then be
   able to manage, and can react to any rewards (manageable or not). The builtin to manage
   a redemption would become available, and any drop-down listing rewards would have two
   sections, manageable and unmanageable.
*/

bool need_mod(string grp) {return 1;}
mapping get_chan_state(object channel, string grp, string|void id) {
	array rewards = G->G->pointsrewards[channel->name[1..]] || ({ }), dynrewards = ({ });
	mapping current = channel->config->dynamic_rewards || ([]);
	foreach (rewards, mapping rew) {
		mapping r = current[rew->id];
		if (r) dynrewards += ({r | (["id": rew->id, "title": r->title = rew->title, "curcost": rew->cost])});
		write("Dynamic ID %O --> %O\n", rew->id, r);
	}
	//FIXME: Change chan_dynamics.js to want items to be all rewards, and then
	//other clients can use the same socket type without it feeling weird. This
	//hack just doesn't feel right IMO.
	if (grp == "dyn") return (["items": dynrewards, "allrewards": rewards]);
	return (["items": rewards, "dynrewards": dynrewards]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (!G->G->irc->channels["#" + chan]) return;
}

@create_hook:
constant point_redemption = ({"string chan", "string id", "int(0..1) refund", "mapping data"});

void points_redeemed(string chan, mapping data, int|void removal)
{
	//write("POINTS %s ON %O: %O\n", removal ? "REFUNDED" : "REDEEMED", chan, data);
	event_notify("point_redemption", chan, data->reward->id, removal, data);
	string token = persist_status->path("bcaster_token")[chan];
	mapping cfg = persist_config["channels"][chan]; if (!cfg) return;

	if (mapping dyn = !removal && cfg->dynamic_rewards && cfg->dynamic_rewards[data->reward->id]) {
		//Up the price every time it's redeemed
		//For this to be viable, the reward needs a global cooldown of
		//at least a few seconds, preferably a few minutes.
		object chan = G->G->irc->channels["#" + chan];
		int newcost = G->G->evaluate_expr(chan->expand_variables(replace(dyn->formula, "PREV", (string)data->reward->cost)));
		if ((string)newcost != (string)data->reward->cost)
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ data->broadcaster_user_id + "&id=" + data->reward->id,
				(["Authorization": "Bearer " + token]),
				(["method": "PATCH", "json": (["cost": newcost])]),
			);
	}
	if (!removal) foreach (G->G->redemption_commands[data->reward->id] || ({ }), string cmd) {
		sscanf(cmd, "%*s#%s", string chan);
		G->G->irc->channels["#" + chan]->send(([
			"displayname": data->user_name, "user": data->user_login,
			"uid": data->user_id,
		]), G->G->echocommands[cmd], ([
			"%s": data->user_input,
			"rewardid": data->reward->id, "redemptionid": data->id,
		]));
	}
}

EventSub redemption = EventSub("redemption", "channel.channel_points_custom_reward_redemption.add", "1", points_redeemed);
EventSub redemptiongone = EventSub("redemptiongone", "channel.channel_points_custom_reward_redemption.update", "1") {points_redeemed(@__ARGS__, 1);};

continue Concurrent.Future populate_rewards_cache(string chan, int|void broadcaster_id) {
	if (!broadcaster_id) broadcaster_id = yield(get_user_id(chan));
	G->G->pointsrewards[chan] = ({ }); //If there's any error, don't keep retrying
	string url = "https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id;
	mapping params = (["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]);
	array rewards = yield(twitch_api_request(url, params))->data;
	//Prune the dynamic rewards list
	mapping current = persist_config["channels"][chan]->?dynamic_rewards;
	if (current) {
		write("Current dynamics: %O\n", current);
		multiset unseen = (multiset)indices(current) - (multiset)rewards->id;
		if (sizeof(unseen)) {m_delete(current, ((array)unseen)[*]); persist_config->save();}
	}
	multiset manageable = (multiset)yield(twitch_api_request(url + "&only_manageable_rewards=true", params))->data->id;
	foreach (rewards, mapping r) r->can_manage = manageable[r->id];
	G->G->pointsrewards[chan] = rewards;
	rewardadd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardupd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardrem(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	redemption(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	redemptiongone(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	send_updates_all("#" + chan);
	send_updates_all("dyn#" + chan);
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
	if (!G->G->pointsrewards[chan]) return;
	G->G->pointsrewards[chan] += ({remap_eventsub_message(info)});
	send_updates_all("#" + chan);
	send_updates_all("dyn#" + chan);
};
EventSub rewardupd = EventSub("rewardupd", "channel.channel_points_custom_reward.update", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = G->G->pointsrewards[chan];
	if (!rew) return;
	foreach (rew; int i; mapping reward)
		if (rew->id == info->id) {rew[i] = remap_eventsub_message(info); break;}
	send_updates_all("#" + chan);
	send_updates_all("dyn#" + chan);
};
EventSub rewardrem = EventSub("rewardrem", "channel.channel_points_custom_reward.remove", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = G->G->pointsrewards[chan];
	if (!rew) return;
	G->G->pointsrewards[chan] = filter(rew) {return __ARGS__[0]->id != info->id;};
	mapping dyn = persist_config["channels"][chan]->?dynamic_rewards;
	if (dyn) {m_delete(dyn, info->id); persist_config->save();}
	send_updates_all("#" + chan);
	send_updates_all("dyn#" + chan);
};

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	spawn_task(populate_rewards_cache(req->misc->channel->name[1..], req->misc->channel->userid));
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

constant command_description = "Manage channel point rewards";
constant builtin_name = "Points rewards";
constant builtin_param = "Action";
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{action}": "Action(s) performed, if any (may be blank)",
]);
constant command_suggestions = ([]); //No default command suggestions. Ultimately this will need a proper builder (eg for dynamic pricing).
constant command_template = ([
	"builtin": "chan_pointsrewards",
	"builtin_param": "<ID> enable",
	"message": ([
		"conditional": "string", "expr1": "{error}",
		"message": ([
			"conditional": "string",
			"expr1": "{action}",
			"message": "",
			"otherwise": "Reward updated: {action}",
		]),
		"otherwise": "Unable to update reward: {error}",
	]),
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	if (param == "") return (["{error}": "Need a subcommand"]);
	string token = persist_status->path("bcaster_token")[channel->name[1..]];
	if (!token) return (["{error}": "Need broadcaster permissions"]);
	sscanf(param, "%[-0-9a-f]%{ %s%}", string reward_id, array(array(string)) cmds);
	mapping params = ([]);
	foreach (cmds, [string cmd]) {
		sscanf(cmd, "%s=%s", cmd, string arg);
		switch (cmd) {
			case "enable": params->is_enabled = arg != "0" ? Val.true : Val.false; break;
			case "disable": params->is_enabled = Val.false; break;
			case "cost": params->cost = (int)arg; break;
			default: return (["{error}": sprintf("Unknown action %O", cmd)]);
		}
	}
	if (!sizeof(params)) return (["{error}": "No changes requested"]);
	int broadcaster_id = yield(get_user_id(channel->name[1..]));
	mapping ret = yield(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ broadcaster_id + "&id=" + reward_id,
		(["Authorization": "Bearer " + token]),
		(["method": "PATCH", "json": params, "return_errors": 1]),
	));
	if (ret->error) return (["{error}": ret->error + ": " + ret->message]);
	return ([
		"{error}": "",
		"{action}": "Done", //TODO: Say what actually changed (might require querying before updating)
	]);
}

protected void create(string name) {
	::create(name);
	if (!G->G->pointsrewards) G->G->pointsrewards = ([]);
	foreach (persist_config->path("channels"); string chan; mapping cfg) {
		if (!G->G->pointsrewards[chan]) {
			string scopes = persist_status->path("bcaster_token_scopes")[chan] || "";
			if (has_value(scopes / " ", "channel:manage:redemptions")
				|| has_value(scopes / " ", "channel:read:redemptions"))
					spawn_task(populate_rewards_cache(chan, cfg->userid));
		}
	}
}
