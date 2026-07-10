inherit http_websocket;
inherit builtin_command;
inherit hook;
inherit annotated;
constant markdown = #"# Channel Point Rewards - $$channel$$

Icon | Title | Prompt | Manage? | Commands
-----|-------|--------|---------|-----------
-    | -     | -      | -       | (loading...)
{:#rewards}

[Add reward](:#add) Copy from: <select id=copyfrom><option value=\"\">(none)</option></select>

If you are a Twitch partner or affiliate, you can see here a list of all your channel point rewards,
whether they can be managed by Mustard Mine, and a place to attach behaviour to them. Coupled with
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

> ### Edit reward details
>
> <table border id=rewardfields></table>
>
> [Save](:type=submit) [Close](:.dialog_close) [Delete reward](:#deletereward)
{: tag=formdialog #editrewarddlg}
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
__async__ mapping get_chan_state(object channel, string grp, string|void id, string|void type) {
	array rewards = G->G->pointsrewards[channel->userid] || ({ });
	mapping dynrewards = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	foreach (rewards, mapping rew) {
		rew->invocations = channel->redemption_commands[rew->id] || ({ });
		if (mapping dyn = dynrewards[rew->id]) rew->dynamic = dyn;
		if (rew->id == id) return rew;
	}
	if (id) return 0; //Clearly it wasn't found
	return (["items": rewards]);
}

Regexp.SimpleRegexp trailing_number = Regexp.SimpleRegexp(" #[0-9]+$");
void wscmd_add(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping settings = (["cost": 1, "title": "New Custom Reward"]);
	if (msg->copyfrom && msg->copyfrom != "") {
		array rewards = G->G->pointsrewards[channel->userid] || ({ });
		int idx = search(rewards->id, msg->copyfrom);
		if (idx != -1) {
			settings = rewards[idx];
			settings->title = trailing_number->replace(settings->title, "");
		}
	}
	//Twitch will notify us when it's created, so no need to explicitly respond.
	create_channel_point_reward(channel, settings);
}

__async__ void wscmd_update_reward(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//TODO maybe: Automatic price capture into variable????? Currently an invisible undocumented feature
	//used exclusively by stream boss.
	mapping simpleedits = msg & (< //Simple fields to update at Twitch
		"cost",
		"background_color",
		"is_paused", "is_user_input_required",
		"should_redemptions_skip_request_queue",
		"max_per_stream", "is_max_per_stream_enabled",
		"max_per_user_per_stream", "is_max_per_user_per_stream_enabled",
		"global_cooldown_seconds", "is_global_cooldown_enabled",
	>);
	mapping dynedits = ([]);
	if (!undefinedp(msg->increment)) dynedits->increment = (int)msg->increment;
	foreach ("title prompt" / " ", string kwd) if (msg[kwd]) {
		//See if there are any variable or placeholder references in the title/prompt.
		//If there are, store this as a dynamic field, for future updates; either way,
		//set the current value after any expansion.
		simpleedits[kwd] = channel->expand_variables(msg[kwd]);
		if (simpleedits[kwd] != msg[kwd]) dynedits[kwd] = msg[kwd];
		else dynedits[kwd] = 0;
	}
	//If you set enabled status to "only while online", that's dynamic.
	if (msg->is_enabled) {
		if (msg->is_enabled == "{online}") dynedits->is_enabled = "{online}";
		else {dynedits->is_enabled = 0; simpleedits->is_enabled = msg->is_enabled;}
	}
	if (sizeof(dynedits)) await(G->G->DB->mutate_config(channel->userid, "dynamic_rewards") {mapping alldyn = __ARGS__[0];
		mapping dyn = alldyn[msg->reward_id] || ([]);
		dyn = filter(dyn | dynedits) {return __ARGS__[0];}; //Exclude any that have become null
		if (sizeof(dyn)) alldyn[msg->reward_id] = dyn;
		else m_delete(alldyn, msg->reward_id);
		//NOTE: Not calling G->G->update_dynamic_reward here - the immediate update is folded into simpleedits
	});
	if (sizeof(simpleedits)) await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + msg->reward_id,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": simpleedits]),
	));
}

__async__ void wscmd_delete_reward(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + msg->reward_id,
		(["Authorization": channel->userid]),
		(["method": "DELETE"]),
	));
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = req->misc->channel->userid && ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	if (!await(modprobe(req))) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	//Force an update, in case we have stale data. Note that the command editor will only use
	//what's sent in the initial response, but at least this way, if there's an issue, hitting
	//Refresh will fix it (otherwise there's no way for the client to force a refetch).
	G->G->populate_rewards_cache(req->misc->channel->userid);
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

@hook_reward_changed: void notify_rewards(object channel, string|void rewardid) {
	if (rewardid) update_one(channel, "", rewardid);
	else send_updates_all(channel, "");
}

__async__ void channel_on_off(string channel, int online, int broadcaster_id) {
	if (!is_active_bot()) return 0;
	object chan = G->G->irc->id[broadcaster_id]; if (!chan) return;
	mapping dyn = await(G->G->DB->load_config(broadcaster_id, "dynamic_rewards"));
	if (!sizeof(dyn)) return; //Nothing to do
	//TODO: Store the cache keyed by id?
	mapping rewards = ([]);
	foreach (G->G->pointsrewards[broadcaster_id] || ({ }), mapping r) rewards[r->id] = r;
	foreach (dyn; string reward_id; mapping info) {
		mapping params = ([]);
		if (info->is_enabled == "{online}") {
			//Weirdly negative. We want to know if the enabled state differs from
			//the online state, but online is 1 or 0 where is_enabled is True/False.
			//So we booleanly negate is_enabled, then see if the result is the same
			//as onlineness; if so, we update using Val.* to ensure the right JSON.
			//TODO maybe: When is_enabled is dynamic, disable the reward as part
			//of stream reset, and enable it as part of an initial online.
			if (!rewards[reward_id]->?is_enabled == online)
				params->is_enabled = online ? Val.true : Val.false;
		}
		if (sizeof(params)) twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
				+ broadcaster_id + "&id=" + reward_id,
			(["Authorization": broadcaster_id]),
			(["method": "PATCH", "json": params]),
		);
	}
}
@hook_channel_online: int channel_online(string channel, int uptime, int id) {channel_on_off(channel, 1, id);}
@hook_channel_offline: int channel_offline(string channel, int uptime, int id) {channel_on_off(channel, 0, id);}

constant builtin_description = "Manage channel point rewards - fulfil and cancel need redemption ID too";
constant builtin_name = "Channel points rewards";
//TODO: In the front end, label them as "[En/Dis]able reward", "Mark complete", "Refund points"
//TODO: Allow setting more than one attribute, eg setting both title and desc atomically
constant builtin_param = ({
	"/Reward/reward_id",
	([
		"\0": "Action",
		"enable": ({"Enabled (1/0)"}), //TODO: Boolean as a checkbox
		"disable": ({ }), //Do we need both this and enable?
		"cost": ({"New cost"}),
		"title": ({"New title"}),
		"desc": ({"New description"}),
		"cooldown": ({"Cooldown (secs)"}),
		//"reset": ({ }),
		"query": ({ }),
		"fulfil": ({"Redemption ID"}),
		"cancel": ({"Redemption ID"}),
	]),
});
constant scope_required = "channel:manage:redemptions";
constant vars_provided = ([
	"{action}": "Action(s) performed, if any (may be blank)",
	"{prevcost}": "Redemption cost prior to any update",
	"{prevtitle}": "Short description prior to any update",
	"{prevdesc}": "Long description (prompt) prior to any update",
	"{newcost}": "Redemption cost after any update",
	"{newtitle}": "Short description after any update",
	"{newdesc}": "Long description (prompt) after any update",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (cfg->simulate) return ([]); //In simulation mode, all this is likely to be used for is refunding or fulfilling the triggering redemption, so assume that that happened.
	string reward_id = param[0];
	mapping params = ([]);
	int empty_ok = 0, hack_reset = 0;
	foreach (param[1..] / 2, [string cmd, string arg]) {
		switch (cmd) {
			case "enable": params->is_enabled = arg != "0" ? Val.true : Val.false; break;
			case "disable": params->is_enabled = Val.false; break;
			case "cost": params->cost = (int)arg; break;
			case "title": params->title = arg; break; //With legacy form, these would be unable to set more than one word.
			case "desc": params->prompt = arg; break; //Use array parameter form instead.
			case "cooldown":
				//A cooldown of zero means "no cooldown", otherwise it's enabled.
				params->global_cooldown_seconds = (int)arg;
				params->is_global_cooldown_enabled = (int)arg ? Val.true : Val.false;
				break;
			case "reset": hack_reset = empty_ok = 1; break;
			case "fulfil": case "cancel": if (arg != "") { //Not an error to attempt to mark nothing
				complete_redemption(channel->name[1..], reward_id, arg, cmd == "fulfil" ? "FULFILLED" : "CANCELED");
			} //fallthrough
			case "query": empty_ok = 1; break; //Query-only. Other modes will also query, but you can use this to avoid making unwanted changes.
			default: error("Unknown action %O\n", cmd);
		}
	}
	if (!sizeof(params) && !empty_ok) error("No changes requested\n");
	if (reward_id == "") return (["{action}": "Nothing to do"]);
	mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + reward_id,
		(["Authorization": channel->userid])));
	if (hack_reset && arrayp(prev->data) && sizeof(prev->data)) {
		//First, find all per-stream limits and cooldowns. (Assumes that we can, in fact, query
		//the reward; if we can't, it's probably a borked ID.) Then reset them all, then reenable.
		//NOTE: This doesn't actually work. TODO: See if we can figure out an alternative way to
		//clear the counts. This technique might still be useful for clearing cooldowns though?
		mapping cur = prev->data[0];
		mapping resets = ([]);
		if (cur->max_per_stream_setting->?is_enabled) {
			resets |= (["is_max_per_stream_enabled": Val.false, "max_per_stream": 0]);
			params |= (["is_max_per_stream_enabled": Val.true, "max_per_stream": cur->max_per_stream_setting->max_per_stream]);
		}
		if (cur->max_per_user_per_stream_setting->?is_enabled) {
			resets |= (["is_max_per_user_per_stream_enabled": Val.false, "max_per_user_per_stream": 0]);
			params |= (["is_max_per_user_per_stream_enabled": Val.true, "max_per_user_per_stream": cur->max_per_user_per_stream_setting->max_per_user_per_stream]);
		}
		if (cur->global_cooldown_setting->?is_enabled) {
			resets |= (["is_global_cooldown_enabled": Val.false, "global_cooldown_seconds": 0]);
			params |= (["is_global_cooldown_enabled": Val.true, "global_cooldown_seconds": cur->global_cooldown_setting->global_cooldown_seconds]);
		}
		await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
				+ channel->userid + "&id=" + reward_id,
			(["Authorization": channel->userid]),
			(["method": "PATCH", "json": resets, "return_errors": 1])));
		sleep(2);
		//Then fall through and let the params reenable the limits.
	}
	mapping ret = sizeof(params) ? await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + reward_id,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": params, "return_errors": 1]),
	)) : prev; //If you didn't request any changes, the previous and new states are the same.
	if (ret->error) error(ret->error + ": " + ret->message + "\n");
	mapping resp = ([
		"{action}": "Done", //Would it be worth having a human-readable summary of the actual diff? The raw information is available.
	]);
	foreach ((["prev": prev, "new": ret]); string lbl; mapping ret) {
		if (!arrayp(ret->data) || !sizeof(ret->data)) continue; //No useful data available. Shouldn't normally happen.
		resp["{" + lbl + "cost}"] = (string)ret->data[0]->cost;
		resp["{" + lbl + "title}"] = ret->data[0]->title || "";
		resp["{" + lbl + "desc}"] = ret->data[0]->prompt || "";
	}
	return resp;
}

mapping(string:mixed) pointsrewards(Protocols.HTTP.Server.Request req) {return redirect("rewards");}
protected void create(string name) {
	::create(name);
	G->G->http_endpoints["chan_pointsrewards"] = pointsrewards;
	G->G->builtins->chan_pointsrewards = builtin_redirect(this);
}
