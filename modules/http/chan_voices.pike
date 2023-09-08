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

[Add new voice](:#addvoice .perms)

> ### Permissions
>
> In order to send certain commands, the bot must be authenticated. Choose as many<br>
> or as few as you wish; any commands not authorized here will simply fail to work.
>
> * loading...
> {: #scopelist}
>
> [Authenticate](:#authenticate) [Close](:.dialog_close)
{: tag=dialog #permsdlg}

<style>
.avatar {width: 40px; vertical-align: middle;}
.defaultvoice .makedefault {display: none;}
.isdefault {display: none;}
.defaultvoice .isdefault {display: unset;}
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
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]));
	return render(req, ([
		"vars": ([
			"ws_group": "", "additional_scopes": G->G->voice_additional_scopes,
			//If you're logged in as the bot intrinsic voice, you can activate any standard voices;
			//if you're a standard voice yourself, you can activate yourself; otherwise you can't.
			//This controls the visibility of buttons and should be kept in sync with the corresponding
			//code in websocket_cmd_activate that does the actual authentication checks.
			"can_activate": req->misc->session->user->id == (string)G->G->bot_uid ? "any" : req->misc->session->user->id,
		]),
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping vox = channel->config->voices || ([]);
	if (id) return vox[id] && (vox[id] | (["scopes": persist_status->has_path("voices", id)->?scopes || ({"chat_login"})]));
	mapping bv = get_channel_config("!demo")->?voices || ([]);
	string defvoice = get_channel_config("!demo")->?defvoice;
	if (defvoice && bv[defvoice] && !vox[defvoice]) {
		vox[defvoice] = bv[defvoice] | ([]);
		persist_config->save();
	}
	array voices = values(vox); sort(indices(vox), voices);
	mapping all_voices = persist_status->path("voices");
	foreach (voices, mapping voice)
		voice->scopes = all_voices[voice->id]->?scopes || ({"chat_login"});
	array botvoices = values(bv); sort((array(int))indices(bv), botvoices);
	return ([
		"items": voices,
		"defvoice": channel->config->defvoice,
		"botvoices": botvoices,
	]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (msg->unsetdefault) { //No voice selection here
		m_delete(channel->config, "defvoice");
		send_updates_all(conn->group);
		persist_config->save();
		return;
	}
	mapping v = channel->config->voices[?msg->id];
	if (!v) return;
	if (msg->desc) v->desc = msg->desc;
	if (msg->notes) v->notes = msg->notes;
	//Update the profile pic in case it's changed
	get_user_info(msg->id)->then() {mapping user = __ARGS__[0];
		string name = user->display_name;
		if (lower_case(user->display_name) != user->login) name += " (" + user->login + ")";
		if (name != v->name) {
			if (v->desc == v->name) v->desc = name;
			v->name = name;
		}
		v->profile_image_url = user->profile_image_url;
		if (msg->makedefault) {
			if (channel->config->voices[msg->id]) channel->config->defvoice = msg->id;
			send_updates_all(conn->group); //Changing the default voice requires a full update, no point shortcutting
		}
		else update_one(conn->group, msg->id);
		persist_config->save();
	};
}

void websocket_cmd_activate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	mapping bv = get_channel_config("!demo")->?voices[?msg->id];
	if (!bv) return;
	//Activating a voice requires that you be either the voice itself, or the bot
	//intrinsic voice (and also a mod, but without that you don't get a websocket).
	if (conn->session->user->id != bv->id && conn->session->user->id != (string)G->G->bot_uid) return;
	if (!channel->config->voices) channel->config->voices = ([]);
	channel->config->voices[msg->id] = bv;
	update_one(conn->group, msg->id);
	persist_config->save();
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	mapping vox = channel->config->voices;
	if (!vox) return; //Nothing to delete.
	if (m_delete(vox, msg->id)) {update_one(conn->group, msg->id); persist_config->save();}
	//Note that deleting the default voice doesn't unset the default, but if a command
	//attempts to use this default, it'll see that the voice isn't authenticated for this
	//channel, and fall back on the global default.
}

void websocket_cmd_login(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return;
	multiset scopes = (multiset)(msg->scopes || ({ }));
	if (mapping tok = persist_status->has_path("voices", msg->voiceid)) {
		//Merge in pre-existing scopes. If they're not recorded, assume that we had the ones we used to request.
		array have = tok->scopes || ({"chat_login", "user_read", "whispers:edit", "user_subscriptions", "user:manage:whispers"});
		scopes |= (multiset)have;
	}
	//Merge in any broadcaster scopes. TODO: Switch to ID when that is the fundamental - stay synchronous
	scopes |= (multiset)(token_for_user_login(channel->name[1..])[1] / " ");
	string url = function_object(G->G->http_endpoints->twitchlogin)->get_redirect_url(
		scopes, (["force_verify": "true"])
	) {
		[object req, mapping user, multiset scopes, string token, string cookie] = __ARGS__;
		mapping v = channel->path("voices", (string)user->id);
		v->id = (string)user->id;
		v->name = user->display_name;
		if (lower_case(user->display_name) != user->login) v->name += " (" + user->login + ")";
		if (!v->desc) v->desc = v->name;
		v->profile_image_url = user->profile_image_url;
		v->last_auth_time = time();
		persist_config->save();
		mapping tok = persist_status->path("voices", v->id);
		tok->token = token;
		tok->authcookie = cookie;
		tok->login = user->login;
		tok->last_auth_time = v->last_auth_time;
		tok->scopes = (array)scopes;
		persist_status->save();
		update_one(conn->group, v->id);
		return (["data": "<script>window.close()</script>", "type": "text/html"]);
	};
	conn->sock->send_text(Standards.JSON.encode((["cmd": "login", "uri": url])));
}
