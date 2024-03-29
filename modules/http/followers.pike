inherit http_websocket;
inherit hook;

constant markdown = #"# Recent followers - $$channel$$

$$message||$$

X | User | Followed | Created | Description
--|------|----------|---------|-------------
- |-     |-         |-        | loading...
{:#followers}

<div id=copied>Copied!</div>

<style>
button {padding: 0;}
img.avatar {max-width: 40px;}
</style>
";
__async__ string|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
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
		mixed ex = catch (channel = await(get_user_id(req->variables->channel)));
		if (ex) return render(req, ([
			"channel": "channel selection",
			"message": "Unknown channel name " + req->variables->channel,
		]));
	}
	if (req->variables->all && 0) { //Enable only when needed. Can be v slow for streamers w/ many followers.
		//FIXME: Replace with helix/channels/followers as per below
		string baseurl = "https://api.twitch.tv/helix/users/follows?first=100&to_id=" + channel + "&after=";
		string cursor = ""; int tot = 0;
		string ret = "";
		do {
			mapping cur = await(twitch_api_request(baseurl + cursor));
			werror("Loaded %d/%d...\n", tot += sizeof(cur->data), cur->total);
			ret += cur->data->from_name * "\n" + "\n";
			cursor = cur->pagination->?cursor;
			await(task_sleep(1));
		} while (cursor && cursor != "IA");
		Stdio.write_file("all_follows.txt", string_to_utf8(ret));
		return "Done";
	}
	mapping resp = await(twitch_api_request("https://api.twitch.tv/helix/channels/followers?first=100&broadcaster_id=" + channel,
		(["Authorization": "Bearer " + req->misc->session->token]),
	));
	//Note: If we don't have permission, there'll be a result but it has only the
	//follower *count*, not the actual names. Unfortunately, this could also imply
	//that the channel has no followers whatsoever...
	if (!sizeof(resp->data) && resp->total) return render(req, ([
		"channel": await(get_user_info(channel))->display_name,
		"message": resp->total + " followers. As of 2023, viewing followers requires moderator permissions. "
			"[Moderator login](:.twitchlogin data-scopes=moderator:read:followers)",
	]));
	array user_info = await(get_users_info(resp->data->user_id));
	mapping users = mkmapping(user_info->id, user_info);
	foreach (resp->data, mapping user) user->details = users[user->user_id] || ([]);
	return render(req, ([
		"vars": (["current_followers": resp->data, "ws_group": G->G->irc->id[channel] && channel]),
		"channel": await(get_user_info(channel))->display_name,
		"message": G->G->irc->id[channel]
			? "Will automatically update as people follow"
			: "Not guaranteed to automatically update - refresh as needed"
				"\n\n<script type=module>import {render} from '" + G->G->template_defaults["static"]("followers.js") + "'; render({});</script>",
	]));
}

//No initial state; the socket exists solely for pushed updates via the follower hook.
mapping get_state(string|int group) {return ([]);}

@hook_follower:
void follower(object channel, mapping follower) {
	get_user_info(follower->user_id)->then() {send_updates_all(channel->userid, (["newfollow": ([
		"followed_at": follower->followed_at, //Note that this includes subsecond resolution, which it doesn't in get_state()
		"user_id": follower->user_id,
		"user_login": follower->user_login,
		"user_name": follower->user_name,
		"details": __ARGS__[0],
	])]));};
}

protected void create(string name) {::create(name);}
