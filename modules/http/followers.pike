inherit http_websocket;
inherit hook;

constant markdown = #"# Recent followers - $$channel$$

$$message||$$

<ul id=followers></ul>
<div id=copied>Copied!</div>

<style>
button {padding: 0;}
</style>
";
/* If no channel, show form to type one in
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
			"message": "Unknown channel name " + req->variables->channel,
		]));
	}
	return render(req, ([
		"vars": (["ws_group": channel]),
		"channel": yield(get_user_info(channel))->display_name,
		"message": has_value(values(G->G->irc->channels)->userid, channel)
			? "Will automatically update as people follow"
			: "Not guaranteed to automatically update - refresh as needed",
	]));
}

Concurrent.Future|mapping get_state(string|int group) {
	return twitch_api_request("https://api.twitch.tv/helix/users/follows?to_id=" + group)->then() {
		return (["followers": __ARGS__[0]->data[..20]]);
	};
}

@hook_follower:
void follower(object channel, mapping follower) {
	send_updates_all(channel->userid, (["newfollow": ([
		"followed_at": follower->followed_at, //Note that this includes subsecond resolution, which it doesn't in get_state()
		"from_id": follower->user_id,
		"from_login": follower->user_login,
		"from_name": follower->user_name,
		"to_id": follower->broadcaster_user_id,
		"to_login": follower->broadcaster_user_login,
		"to_name": follower->broadcaster_user_name,
	])]));
}

protected void create(string name) {::create(name);}
