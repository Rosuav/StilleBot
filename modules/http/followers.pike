inherit http_websocket;

constant markdown = #"# Recent followers - $$channel$$

$$error||$$

<ul id=followers></ul>
<div id=copied>Copied!</div>

<style>
button {padding: 0;}
</style>
";
/* If no channel, show form to type one in
  - Eventually: Websocket notification of new followers so you can just keep the page open.
*/
continue Concurrent.Future|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->variables->channel) {
		return render(req, ([
			"channel": "channel selection",
		]));
	}
	int channel = (int)req->variables->channel;
	if (!channel) {
		mixed ex = catch (channel = yield(get_user_id(req->variables->channel)));
		if (ex) return render(req, ([
			"channel": "channel selection",
			"error": "Unknown channel name " + req->variables->channel,
		]));
	}
	return render(req, ([
		"vars": (["ws_group": channel]),
		"channel": yield(get_user_info(channel))->display_name,
	]));
}

Concurrent.Future|mapping get_state(string|int group) {
	//TODO: Cache until a new follower is seen
	return twitch_api_request("https://api.twitch.tv/helix/users/follows?to_id=" + group)->then() {
		return (["followers": __ARGS__[0]->data[..20]]);
	};
}
