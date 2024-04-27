inherit http_websocket;
inherit builtin_command;
inherit annotated;

constant markdown = #"# Channel goals

* loading...
{:#goals}

";

@retain: mapping channel_labels = ([]);

constant builtin_name = "Goals";
constant builtin_description = "Query Twitch goals";
constant vars_provided = ([
	"{target}": "", //TODO: Synchronize for the sake of docos
	"{current}": "",
]);

mapping|Concurrent.Future message_params(object channel, mapping person, array param) {
	return (["{target}": "0"]);
}

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (string scopes = ensure_bcaster_token(req, "channel:read:goals"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping info = await(twitch_api_request("https://api.twitch.tv/helix/goals?broadcaster_id=" + channel->userid,
		(["Authorization": "Bearer " + G->G->user_credentials[channel->userid]->token])));
	return ([
		"items": info->data,
	]);
}

@"is_mod": void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	send_updates_all(channel, "");
}

protected void create(string name) {::create(name);}
