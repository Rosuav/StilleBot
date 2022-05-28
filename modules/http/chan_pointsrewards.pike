inherit http_websocket;
inherit builtin_command;
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
	array rewards = G->G->pointsrewards[channel->name[1..]];
	if (!rewards) return (["status": "Loading, please wait..."]); //When it's loaded, populate_rewards_cache() will update us
	return (["items": rewards]); //TODO: Support partial updates; also give info about dynamic status
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (!G->G->irc->channels["#" + chan]) return;
}

continue Concurrent.Future populate_rewards_cache(string chan) {
	int broadcaster_id = yield(get_user_id(chan));
	string url = "https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id;
	mapping params = (["Authorization": "Bearer " + persist_status->path("bcaster_token")[chan]]);
	array rewards = yield(twitch_api_request(url, params))->data;
	multiset manageable = (multiset)yield(twitch_api_request(url + "&only_manageable_rewards=true", params))->data->id;
	foreach (rewards, mapping r) r->can_manage = manageable[r->id];
	G->G->pointsrewards[chan] = rewards;
	send_updates_all("#" + chan);
}
void update_rewards_cache(string chan) {spawn_task(populate_rewards_cache(chan));}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (string scopes = ensure_bcaster_token(req, "channel:manage:redemptions"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	update_rewards_cache(req->misc->channel->name[1..]);
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
}
