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
	array rewards = G->G->pointsrewards[channel->userid] || ({ }), dynrewards = ({ });
	mapping current = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	foreach (rewards, mapping rew) {
		mapping r = current[rew->id];
		//Note that attributes set in dynamic_rewards override those seen in current status.
		if (r) dynrewards += ({(["id": rew->id, "title": rew->title, "prompt": rew->prompt, "curcost": rew->cost]) | r});
		rew->invocations = channel->redemption_commands[rew->id] || ({ });
		if (rew->id == id) return type == "dynreward" ? r && dynrewards[-1] : rew; //Can't be bothered remapping to remove the search
	}
	if (id) return 0; //Clearly it wasn't found
	return (["items": rewards, "dynrewards": dynrewards]);
}

void wscmd_add(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array rewards = G->G->pointsrewards[channel->userid] || ({ });
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
	//TODO: Copying attributes like cooldown doesn't work currently due to differences
	//between the way Twitch returns the queried one and the way you create one. Need
	//to map between them.
	twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + token_for_user_id(channel->userid)[0]]),
		(["method": "POST", "json": copyfrom | (["title": title])]),
	);
}

//TODO: Deduplicate with wscmd_add(). Conceptually, this might add, might not, and will make the
//dynamic part. Can it share code?
__async__ void wscmd_new_dynamic(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping body = msg; //this used to be a PUT request...
	int broadcaster_id = channel->userid;
	mapping dyn = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	if (!body->copy_from) {
		//Was an existing ID specified? If so - and if it's manageable and not already dynamic - don't copy it.
		mapping rew;
		foreach (G->G->pointsrewards[broadcaster_id] || ({ }), mapping r) if (r->id == body->id) rew = r;
		if (rew && rew->can_manage && !rew->is_dynamic) {
			dyn[rew->id] = ([
				"basecost": rew->cost || 1000, "availability": "1", "formula": "PREV",
			]);
			await(G->G->DB->save_config(channel->userid, "dynamic_rewards", dyn));
			//As below, might be worth pushing out the update immediately (rather than waiting for Twitch to notify us)
			return;
		}
		else body->copy_from = rew; //If there's no such reward, well, we'll start blank anyway. But otherwise, copy that reward.
	}
	mapping copyfrom = body->copy_from || ([]); //Whatever we get from the front end, pass to Twitch. Good idea? Not sure.
	//Titles must be unique (among all rewards). To simplify rapid creation of
	//multiple rewards, add a numeric disambiguator on conflict.
	string deftitle = copyfrom->title || "Example Dynamic Reward";
	mapping rwd = (["basecost": copyfrom->cost || 1000, "availability": "1", "formula": "PREV"]);
	array have = filter((G->G->pointsrewards[broadcaster_id]||({}))->title, has_prefix, deftitle);
	copyfrom |= (["title": deftitle + " #" + (sizeof(have) + 1), "cost": rwd->basecost]);
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id,
		(["Authorization": channel->userid]),
		(["method": "POST", "json": copyfrom]),
	))->data[0];
	//write("Created new dynamic: %O\n", info);
	//TODO: Update G->G->pointsrewards immediately, and push out the update
	//This will speed up the response to user significantly.
	dyn[info->id] = rwd;
	if (!G->G->rewards_manageable[broadcaster_id]) G->G->rewards_manageable[broadcaster_id] = (<>);
	G->G->rewards_manageable[broadcaster_id][info->id] = 1;
	await(G->G->DB->save_config(channel->userid, "dynamic_rewards", dyn));
}

__async__ void wscmd_update_reward(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Able to edit more fields than update_dynamic can, but does not store placeholdered text for future changes.
	//The edits done by this command are always immediate; note that this might result in a dynamic reward pushing
	//out another update, overwriting your changes here.
	multiset fields = (<
		"title", "prompt", "cost",
		"background_color",
		"is_enabled", "is_paused", "is_user_input_required",
		"should_redemptions_skip_request_queue",
		"max_per_stream", "is_max_per_stream_enabled",
		"max_per_user_per_stream", "is_max_per_user_per_stream_enabled",
		"global_cooldown_seconds", "is_global_cooldown_enabled",
	>);
	mapping ret = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + msg->reward_id,
		(["Authorization": channel->userid]),
		(["method": "PATCH", "json": msg & fields]),
	));
}

__async__ void wscmd_delete_reward(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ channel->userid + "&id=" + msg->reward_id,
		(["Authorization": channel->userid]),
		(["method": "DELETE"]),
	));
}

__async__ void wscmd_update_dynamic(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string id = msg->dynamic_id;
	mapping body = msg; //this used to be a PUT request...
	mapping dyn = await(G->G->DB->load_config(channel->userid, "dynamic_rewards"));
	mapping rwd = dyn[id]; if (!rwd) return;
	mapping updates = ([]);
	foreach ("title prompt" / " ", string kwd) if (body[kwd]) {
		//See if there are any variable or placeholder references in the title/prompt.
		//If there are, retain the value with placeholders, for future updates; but
		//otherwise, set the value immediately, and DON'T store it for placeholdering.
		string value = channel->expand_variables(body[kwd]);
		if (value != body[kwd]) rwd[kwd] = body[kwd];
		else {updates[kwd] = body[kwd]; m_delete(rwd, kwd);}
	}
	if (!undefinedp(body->basecost)) rwd->basecost = (int)body->basecost;
	if (body->formula) rwd->formula = body->formula;
	if (body->availability) rwd->availability = body->availability;
	if (rwd->availability == "" && rwd->formula == "") m_delete(dyn, id); //Hack: Delete by blanking the values. Will be replaced later.
	if (body->curcost) updates["cost"] = (int)body->curcost;
	if (sizeof(updates)) {
		//Currently fire-and-forget - there's no feedback if you get something wrong.
		twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid + "&id=" + id,
			(["Authorization": channel->userid]),
			(["method": "PATCH", "json": updates]),
		);
	}
	await(G->G->DB->save_config(channel->userid, "dynamic_rewards", dyn));
	G->G->update_dynamic_reward(channel, id, rwd);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = !req->misc->session->fake && ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	mapping vars = (["ws_group": ""]) | G->G->command_editor_vars(req->misc->channel); //Load the vars prior to populating the cache
	//Force an update, in case we have stale data. Note that the command editor will only use
	//what's sent in the initial response, but at least this way, if there's an issue, hitting
	//Refresh will fix it (otherwise there's no way for the client to force a refetch).
	G->G->populate_rewards_cache(req->misc->channel->userid);
	return render(req, (["vars": vars]) | req->misc->chaninfo);
}

@hook_reward_changed: void notify_rewards(object channel, string|void rewardid) {
	if (rewardid) {
		update_one(channel, "", rewardid);
		update_one(channel, "", rewardid, "dynreward");
	}
	else send_updates_all(channel, "");
}

constant command_description = "Manage channel point rewards - fulfil and cancel need redemption ID too";
constant builtin_name = "Points rewards";
//TODO: In the front end, label them as "[En/Dis]able reward", "Mark complete", "Refund points"
//TODO: Allow setting more than one attribute, eg setting both title and desc atomically
constant builtin_param = ({"/Reward/reward_id", "/Action/enable/disable/cost/title/desc/query/fulfil/cancel", "Redemption ID"});
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
	string token = token_for_user_id(channel->userid)[0];
	if (token == "") error("Need broadcaster permissions\n");
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
			} //fallthrough
			case "query": empty_ok = 1; break; //Query-only. Other modes will also query, but you can use this to avoid making unwanted changes.
			default: error("Unknown action %O\n", cmd);
		}
	}
	if (!sizeof(params) && !empty_ok) error("No changes requested\n");
	if (reward_id == "") return (["{action}": "Nothing to do"]);
	int broadcaster_id = await(get_user_id(channel->name[1..]));
	mapping prev = await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ broadcaster_id + "&id=" + reward_id,
		(["Authorization": "Bearer " + token])));
	mapping ret = sizeof(params) ? await(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
			+ broadcaster_id + "&id=" + reward_id,
		(["Authorization": "Bearer " + token]),
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

protected void create(string name) {::create(name);}
