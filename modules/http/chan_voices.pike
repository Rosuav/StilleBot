inherit http_websocket;
constant markdown = #"# Available voices for $$channel$$

Normally the channel bot will speak using its own voice, as defined by the
bot's login. However, for certain situations, it is preferable to allow the bot
to speak using some other voice. This requires authentication as the new voice,
which is not necessarily who you're currently logged in as.

You must first be a channel moderator to enable this, and then must also have
the credentials for the voice you plan to use (be it the broadcaster or some
dedicated bot account).

Name        | Mnemonic | Description/purpose | -
------------|----------|---------------------|----
-           | -        | Loading...
{: #voices}

[Add new voice](:#addvoice)

<style>
.avatar {max-width: 40px; vertical-align: middle;}
</style>
";
//Note that, in theory, multiple voice support could be done without an HTTP interface.
//It would be fiddly to set up, though, so I'm not going to try to support it at this
//stage. Maybe in the future. For now, if you're working without the web interface, you
//will need to manually set a "voice" on a command, and you'll need to manually craft
//the persist_status entries for the login.

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping vox = channel->config->voices;
	if (!vox) return !id && (["items": ({ })]);
	if (id) return vox[id];
	array voices = values(vox); sort(indices(vox), voices);
	return (["items": voices]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	mapping v = channel->config->voices[?msg->id];
	if (!v) return;
	if (msg->desc) v->desc = msg->desc;
	if (msg->notes) v->notes = msg->notes;
	update_one(conn->group, msg->id);
	persist_config->save();
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	mapping vox = channel->config->voices;
	if (!vox) return; //Nothing to delete.
	if (m_delete(vox, msg->id)) {update_one(conn->group, msg->id); persist_config->save();}
}

void websocket_cmd_login(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return;
	string url = function_object(G->G->http_endpoints->twitchlogin)->get_redirect_url(
		(<"chat_login", "user_read", "whispers:edit", "user_subscriptions">), (["force_verify": "true"])
	) {
		[object req, mapping user, multiset scopes, string token] = __ARGS__;
		mapping v = persist_config->path("channels", channel->name[1..], "voices", (string)user->id);
		v->id = (string)user->id;
		v->name = user->display_name;
		if (lower_case(user->display_name) != user->login) v->name += " (" + user->login + ")";
		if (!v->desc) v->desc = v->name;
		v->profile_image_url = user->profile_image_url;
		v->last_auth_time = time();
		persist_config->save();
		mapping tok = persist_status->path("voices", v->id);
		tok->token = token;
		tok->last_auth_time = v->last_auth_time;
		persist_status->save();
		update_one(conn->group, v->id);
		return (["data": "<script>window.close()</script>", "type": "text/html"]);
	};
	conn->sock->send_text(Standards.JSON.encode((["cmd": "login", "uri": url])));
}
