inherit http_websocket;
inherit builtin_command;
constant hidden_command = 1;
constant access = "none";
constant markdown = #"# Points rewards - $$channel$$

TODO: Allow commands to be triggered by channel point redemptions.

This will eventually have a list of all your current rewards, whether they can be managed
by StilleBot, and a place to attach behaviour to them. Coupled with appropriate use of
channel voices, this can allow a wide variety of interactions with other bots.
";

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	return 0; //Stub
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	if (grp != "control" || !G->G->irc->channels["#" + chan]) return;
}

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
	]) | req->misc->chaninfo);
}

constant command_description = "Manage channel point rewards";
constant builtin_name = "Points rewards";
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

protected void create(string name) {::create(name);}
