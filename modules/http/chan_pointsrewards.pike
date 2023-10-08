inherit http_websocket;
inherit builtin_command;
inherit hook;
inherit annotated;
constant hidden_command = 1;
constant access = "none";
constant markdown = #"# Points rewards - $$channel$$

Icon | Title | Prompt | Manage? | Commands
-----|-------|--------|---------|-----------
-    | -     | -      | -       | (loading...)
{:#rewards}

[Add reward](:#add) Copy from: <select id=copyfrom><option value=\"\">(none)</option></select>

If you are a Twitch partner or affiliate, you can see here a list of all your channel point rewards,
whether they can be managed by StilleBot, and a place to attach behaviour to them. Coupled with
appropriate use of channel voices, this can allow a wide variety of interactions with other bots.

You can remove functionality from a reward by deleting the corresponding command, or editing
it so that it no longer responds to the redemption (if you want to keep the command for other
purposes).

[Configure reward details here](https://dashboard.twitch.tv/u/$$channel$$/viewer-rewards/channel-points/rewards)

<style>
#rewards th {
	padding: 0 0.25em;
}
#rewards ul {
	margin: 0; padding: 0;
	list-style-type: none;
}
#rewards li {
	margin: 0.125em 0;
}
</style>
";
@retain: mapping pointsrewards = ([]);

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
mapping get_chan_state(object channel, string grp, string|void id, string|void type) {
	array rewards = pointsrewards[channel->name[1..]] || ({ }), dynrewards = ({ });
	mapping current = channel->config->dynamic_rewards || ([]);
	foreach (rewards, mapping rew) {
		mapping r = current[rew->id];
		if (r) dynrewards += ({r | (["id": rew->id, "title": rew->title, "curcost": rew->cost])});
		rew->invocations = channel->redemption_commands[rew->id] || ({ });
		if (rew->id == id) return type == "dynreward" ? r && dynrewards[-1] : rew; //Can't be bothered remapping to remove the search
	}
	if (id) return 0; //Clearly it wasn't found
	return (["items": rewards, "dynrewards": dynrewards]);
}

void wscmd_add(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array rewards = pointsrewards[channel->name[1..]] || ({ });
	mapping copyfrom = (["cost": 1]);
	string basetitle = "New Custom Reward";
	if (msg->copyfrom && msg->copyfrom != "") {
		int idx = search(rewards->id, msg->copyfrom);
		if (idx != -1) {copyfrom = rewards[idx]; sscanf(basetitle = copyfrom->title, "%s #%*d", basetitle);}
	}
	//Titles must be unique (among all rewards). To simplify rapid creation of
	//multiple rewards, add a numeric disambiguator on conflict.
	multiset have_titles = (multiset)rewards->title;
	string title = basetitle; int idx = 1; //First one doesn't get the number appended
	while (have_titles[title]) title = sprintf("%s #%d", basetitle, ++idx);
	//Twitch will notify us when it's created, so no need to explicitly respond.
	twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST", "json": copyfrom | (["title": title])]),
	);
}

@create_hook:
constant point_redemption = ({"string chan", "string rewardid", "int(0..1) refund", "mapping data"});

void points_redeemed(string chan, mapping data, int|void removal)
{
	//write("POINTS %s ON %O: %O\n", removal ? "REFUNDED" : "REDEEMED", chan, data);
	event_notify("point_redemption", chan, data->reward->id, removal, data);
	string token = token_for_user_login(chan)[0];
	mapping cfg = get_channel_config(chan); if (!cfg) return;

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
	object channel = G->G->irc->channels["#" + chan];
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

continue Concurrent.Future populate_rewards_cache(string chan, string|int|void broadcaster_id) {
	if (!broadcaster_id) broadcaster_id = yield(get_user_id(chan));
	pointsrewards[chan] = ({ }); //If there's any error, don't keep retrying
	string url = "https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id;
	mapping params = (["Authorization": "Bearer " + yield(token_for_user_id_async(broadcaster_id))[0]]);
	array rewards = yield(twitch_api_request(url, params))->data;
	//Prune the dynamic rewards list
	object channel = G->G->irc->channels["#" + chan];
	mapping current = channel->?config->?dynamic_rewards;
	if (current) {
		write("Current dynamics: %O\n", current);
		multiset unseen = (multiset)indices(current) - (multiset)rewards->id;
		if (sizeof(unseen)) {m_delete(current, ((array)unseen)[*]); channel->config_save();}
	}
	multiset manageable = (multiset)yield(twitch_api_request(url + "&only_manageable_rewards=true", params))->data->id;
	foreach (rewards, mapping r) r->can_manage = manageable[r->id];
	pointsrewards[chan] = rewards;
	rewardadd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardupd(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	rewardrem(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	redemption(chan, (["broadcaster_user_id": (string)broadcaster_id]));
	redemptiongone(chan, (["broadcaster_user_id": (string)broadcaster_id]));
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
	if (!pointsrewards[chan]) return;
	pointsrewards[chan] += ({remap_eventsub_message(info)});
	update_one("#" + chan, info->id);
	update_one("#" + chan, info->id, "dynreward");
};
EventSub rewardupd = EventSub("rewardupd", "channel.channel_points_custom_reward.update", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = pointsrewards[chan];
	if (!rew) return;
	foreach (rew; int i; mapping reward)
		if (reward->id == info->id) {rew[i] = remap_eventsub_message(info); break;}
	update_one("#" + chan, info->id);
	update_one("#" + chan, info->id, "dynreward");
};
EventSub rewardrem = EventSub("rewardrem", "channel.channel_points_custom_reward.remove", "1") {
	[string chan, mapping info] = __ARGS__;
	array rew = pointsrewards[chan];
	if (!rew) return;
	pointsrewards[chan] = filter(rew) {return __ARGS__[0]->id != info->id;};
	object channel = G->G->irc->channels["#" + chan];
	mapping dyn = channel->?config->?dynamic_rewards;
	if (dyn) {m_delete(dyn, info->id); channel->config_save();}
	update_one("#" + chan, info->id);
	update_one("#" + chan, info->id, "dynreward");
};

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = !req->misc->session->fake && ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	array rew = pointsrewards[req->misc->channel->name[1..]] || ({ });
	//Force an update, in case we have stale data. Note that the command editor will only use
	//what's sent in the initial response, but at least this way, if there's an issue, hitting
	//Refresh will fix it (otherwise there's no way for the client to force a refetch).
	spawn_task(populate_rewards_cache(req->misc->channel->name[1..], req->misc->channel->userid));
	return render(req, ([
		"vars": (["ws_group": ""]) | G->G->command_editor_vars(req->misc->channel),
	]) | req->misc->chaninfo);
}

constant command_description = "Manage channel point rewards - fulfil and cancel need redemption ID too";
constant builtin_name = "Points rewards";
//TODO: In the front end, label them as "[En/Dis]able reward", "Mark complete", "Refund points"
//TODO: Allow setting more than one attribute, eg setting both title and desc atomically
constant builtin_param = ({"Reward ID", "/Action/enable/disable/title/desc/fulfil/cancel", "Redemption ID"});
constant scope_required = "channel:manage:redemptions";
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{action}": "Action(s) performed, if any (may be blank)",
]);

continue mapping|Concurrent.Future message_params(object channel, mapping person, array param) {
	string token = yield(token_for_user_id_async(channel->userid))[0];
	if (token == "") return (["{error}": "Need broadcaster permissions"]);
	string reward_id = param[0];
	mapping params = ([]);
	int empty_ok = 0;
	foreach (param[1..] / 2, [string cmd, string arg]) {
		switch (cmd) {
			case "enable": params->is_enabled = arg != "0" ? Val.true : Val.false; break;
			case "disable": params->is_enabled = Val.false; break;
			case "cost": params->cost = (int)arg; break;
			case "title": params->title = arg; break; //With legacy form, these would be unable to set more than one word.
			case "desc": params->prompt = arg; break; //Use array parameter form instead.
			case "fulfil": case "cancel": if (arg != "") { //Not an error to attempt to mark nothing
				complete_redemption(channel->name[1..], reward_id, arg, cmd == "fulfil" ? "FULFILLED" : "CANCELED");
			}
			empty_ok = 1;
			break;
			default: return (["{error}": sprintf("Unknown action %O", cmd)]);
		}
	}
	if (!sizeof(params)) {
		if (empty_ok) return (["{error}": "", "{action}": "Done"]);
		else return (["{error}": "No changes requested"]);
	}
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
	foreach (list_channel_configs(), mapping cfg) {
		string chan = cfg->login; if (!chan) continue;
		if (!pointsrewards[chan]) {
			string scopes = token_for_user_login(chan)[1];
			if (has_value(scopes / " ", "channel:manage:redemptions")
				|| has_value(scopes / " ", "channel:read:redemptions"))
					spawn_task(populate_rewards_cache(chan, cfg->userid));
		}
	}
}
