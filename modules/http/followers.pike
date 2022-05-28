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
continue Concurrent.Future|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (!req->variables->channel) {
		return render(req, ([
			"channel": "channel selection",
			"message": #"<form>
				<label>No channel selected - type a channel name: <input name=channel size=20></label>
				<input type=submit value=Go>
			</form>"
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
	if (req->variables->all && 0) { //Enable only when needed. Can be v slow for streamers w/ many followers.
		string baseurl = "https://api.twitch.tv/helix/users/follows?first=100&to_id=" + channel + "&after=";
		string cursor = ""; int tot = 0;
		string ret = "";
		do {
			mapping cur = yield(twitch_api_request(baseurl + cursor));
			werror("Loaded %d/%d...\n", tot += sizeof(cur->data), cur->total);
			ret += cur->data->from_name * "\n" + "\n";
			cursor = cur->pagination->?cursor;
			mixed _ = yield(task_sleep(1));
		} while (cursor && cursor != "IA");
		Stdio.write_file("all_follows.txt", string_to_utf8(ret));
		return "Done";
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
