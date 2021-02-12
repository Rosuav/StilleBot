inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:manage:redemptions")) return resp;
	mapping cfg = req->misc->channel->config;
	//TODO: Allow mods to control some things (if the broadcaster's set it up),
	//and allow all users to see status. This MAY require retaining the OAuth.
	if (req->misc->channel->name[1..] != req->misc->session->user->login)
		return render_template("login.md", req->misc->chaninfo); //TODO: Change the text to say "not the broadcaster" rather than "not a mod"
	if (req->request_type == "PUT") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body)) return (["error": 400]);
		write("Got request: %O\n", body);
		return jsonify((["ok": 1]));
	}
	return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + req->misc->session->user->id,
			(["Authorization": "Bearer " + req->misc->session->token])
		)->then(lambda(mapping info) {
			return render_template("chan_giveaway.md", (["vars": ([
				"rewards": info->data,
			])]));
		});
}
