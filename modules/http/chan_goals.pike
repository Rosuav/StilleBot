inherit http_websocket;
inherit builtin_command;
inherit annotated;
inherit hook;

constant markdown = #"# Channel goals

* loading...
{:#goals}

";

@retain: mapping channel_labels = ([]);

constant builtin_name = "Goals";
constant builtin_description = "Query Twitch goals";
constant builtin_param = ({"Goal ID"});
constant vars_provided = ([
	"{goalid}": "Goal ID; if multiple available and none selected, is all goal IDs.",
	"{type}": "Type of goal - selected, or the first available - follower, subscription, etc",
	"{current}": "Current amount for the selected/first goal",
	"{target}": "Target for the selected/first goal",
	"{title}": "Title of the goal",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (cfg->simulate) return (["{goalid}": ""]); //No goals when simulating (to avoid API calls)
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/goals?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + G->G->user_credentials[channel->userid]->token])));
	if (!sizeof(info->data)) return (["{goalid}": ""]); //No goals.
	mapping goal = info->data[0];
	string id = info->data->id * " ";
	if (sizeof(param) && param[0] != "") {
		//Pick out a single goal by its ID
		foreach (info->data, mapping g) if (g->id == param[0]) {goal = g; id = g->id; break;}
		//Not found? Fall through as if no ID specified.
	}
	return ([
		"{goalid}": id,
		"{type}": goal->type,
		"{current}": (string)goal->current_amount,
		"{target}": (string)goal->target_amount,
		"{title}": goal->description,
	]);
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (string scopes = ensure_bcaster_token(req, "channel:read:goals"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/goals?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + G->G->user_credentials[channel->userid]->token])));
	return ([
		"items": info->data,
	]);
}

@EventNotify("channel.goal.progress=1"):
void goal_advanced(object channel, mapping info) {
	send_updates_all(channel, "");
}

protected void create(string name) {::create(name);}
