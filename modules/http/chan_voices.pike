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

Having trouble getting voices to work? The 'Say Hello' button can help. [More hints and tips](:.opendlg data-dlg=tipsdlg)

> ### Hints and tips
>
> * Many things can go wrong with setting up a bot voice. The quickest and easiest way
>   to test a voice is to click 'Say Hello', which should put a message in the channel's
>   chat saying hello from that voice. If it does not, you may receive a helpful error
>   message.
> * If 'Say Hello' succeeds but the bot does not react to commands, it may be that general
>   channel permissions need to be re-granted. This can happen if the broadcaster tells
>   Twitch to disconnect the Mustard Mine app, or if other authentication-related issues
>   occur. If you are the broadcaster, [click here to reauthenticate](:.twitchlogin data-scopes=@$$channel_scopes_required$$@).
> * Intermittent failures can be caused by rate limits and timeouts.
> * Having the voice be a moderator bypasses many of Twitch's restrictions.
>
> [Close](:.dialog_close)
{: tag=dialog #tipsdlg}

[Add $$selfname$$ as a voice](:.perms data-id=$$selfuid$$) [Add new voice](:.perms data-id=0)

> ### Permissions
>
> In order to send certain commands, the bot must be authenticated. Choose as many<br>
> or as few as you wish; any commands not authorized here will simply fail to work.
>
> * loading...
> {: #scopelist}
>
> Authenticating someone other than `$$selfname$$`? Copy/paste the login URL to another<br>
> browser, or log in separately - it will work fine!
>
> [Authenticate](:#authenticate) [Close](:.dialog_close)
{: tag=dialog #permsdlg}

<style>
.avatar {width: 40px; vertical-align: middle;}
.defaultvoice .makedefault {display: none;}
.isdefault {display: none;}
.defaultvoice .isdefault {display: unset;}
#hellofail {
	border: 1px solid blue;
	background: aliceblue;
}
#tipsdlg {max-width: 900px}
#tipsdlg li {margin-bottom: 8px;}
</style>

> ### Unable to send chat messages
>
> The attempt to say hello in your channel failed. Twitch told us:
>
> <p id=hellofail></p>
>
> <p id=helloexplan></p>
>
> [Retry](:.testvoice) [Close](:.dialog_close)
{: tag=dialog #hellofaildlg}
";
//Note that, in theory, multiple voice support could be done without an HTTP interface.
//It would be fiddly to set up, though, so I'm not going to try to support it.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping cfg = req->misc->channel->config;
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": ([
			"ws_group": "", "additional_scopes": G->G->voice_additional_scopes,
			//If you're logged in as the bot intrinsic voice, you can activate any standard voices;
			//if you're a standard voice yourself, you can activate yourself; otherwise you can't.
			//This controls the visibility of buttons and should be kept in sync with the corresponding
			//code in websocket_cmd_activate that does the actual authentication checks.
			"can_activate": req->misc->session->user->id == (string)G->G->bot_uid ? "any" : req->misc->session->user->id,
		]),
		"selfname": req->misc->session->user->?display_name || "",
		"selfuid": (string)req->misc->session->user->?id || "",
		"channel_scopes_required": channel_scopes_required,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return 1;}

mapping get_chan_state(object channel, string grp, string|void id) {
	mapping vox = G->G->DB->load_cached_config(channel->userid, "voices");
	if (id) return vox[id] && (vox[id] | (["scopes": G->G->user_credentials[(int)id]->?scopes || ({"chat_login"})]));
	mapping bv = G->G->DB->load_cached_config(0, "voices");
	string defvoice = G->G->irc->id[0]->?config->?defvoice;
	if (defvoice && bv[defvoice] && !vox[defvoice]) {
		vox[defvoice] = bv[defvoice] | ([]);
		G->G->DB->save_config(channel->userid, "voices", vox);
	}
	array voices = values(vox); sort(indices(vox), voices);
	mapping all_voices = G->G->user_credentials;
	foreach (voices, mapping voice)
		voice->scopes = all_voices[(int)voice->id]->?scopes || ({"chat_login"});
	array botvoices = values(bv); sort((array(int))indices(bv), botvoices);
	return ([
		"items": voices,
		"defvoice": channel->config->defvoice,
		"botvoices": botvoices,
	]);
}

void wscmd_update(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->unsetdefault) { //No voice selection here
		m_delete(channel->botconfig, "defvoice");
		send_updates_all(conn->group);
		channel->botconfig_save();
		return;
	}
	mapping v = G->G->DB->load_cached_config(channel->userid, "voices")[msg->id];
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
			if (G->G->DB->load_cached_config(channel->userid, "voices")[msg->id]) {
				channel->botconfig->defvoice = msg->id;
				channel->botconfig_save();
			}
			send_updates_all(conn->group); //Changing the default voice requires a full update, no point shortcutting
		}
		else update_one(conn->group, msg->id);
	};
}

void wscmd_activate(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping bv = G->G->DB->load_cached_config(0, "voices")[msg->id];
	if (!bv) return;
	//Activating a voice requires that you be either the voice itself, or the bot
	//intrinsic voice (and also a mod, but without that you don't get a websocket).
	if (conn->session->user->id != bv->id && conn->session->user->id != (string)G->G->bot_uid) return;
	G->G->DB->mutate_config(channel->userid, "voices") {
		__ARGS__[msg->id] = bv;
		update_one(conn->group, msg->id);
	};
}

void wscmd_delete(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->mutate_config(channel->userid, "voices") {
		if (m_delete(__ARGS__[0], msg->id)) update_one(conn->group, msg->id);
	};
	//Note that deleting the default voice doesn't unset the default, but if a command
	//attempts to use this default, it'll see that the voice isn't authenticated for this
	//channel, and fall back on the global default.
}

void wscmd_testvoice(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping vox = G->G->DB->load_cached_config(channel->userid, "voices")[msg->id];
	if (!vox) return; //Voice has to have been authenticated to do a test
	channel->send(0, (["voice": msg->id, "message": "Hello from " + vox->name + "!"]), 0) {
		send_msg(conn, (["cmd": "testvoice", "voice": vox->name, "voiceid": vox->id, "result": __ARGS__[1]]));
	};
}

void websocket_cmd_login(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return;
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return;
	multiset scopes = (multiset)(msg->scopes || ({ }));
	//Grab the existing credentials. If voiceid is 0, "0", or absent, the intention is
	//likely to copy/paste the auth link to another browser, or log in separately; give
	//no additional scopes. Since it's possible that this copy/paste will be done for
	//reauthentication too, we always set the force_verify flag.
	mapping cred = G->G->user_credentials[(int)msg->voiceid];
	if (cred->?scopes) scopes |= (multiset)cred->scopes;
	string url = function_object(G->G->http_endpoints->twitchlogin)->get_redirect_url(
		scopes, (["force_verify": "true"]), conn->hostname,
	) {
		[object req, mapping user, multiset scopes, string token] = __ARGS__;
		mapping vox = G->G->DB->load_cached_config(channel->userid, "voices");
		mapping v = vox[user->id]; if (!v) v = vox[user->id] = ([]);
		v->id = (string)user->id;
		v->name = user->display_name;
		if (lower_case(user->display_name) != user->login) v->name += " (" + user->login + ")";
		if (!v->desc) v->desc = v->name;
		v->profile_image_url = user->profile_image_url;
		v->last_auth_time = time();
		G->G->DB->save_config(channel->userid, "voices", vox);
		update_one(conn->group, v->id);
		return (["data": "<script>window.close()</script><h1>Authentication successful!</h1><p>You can close this window and return to the previous page.</p>", "type": "text/html"]);
	};
	conn->sock->send_text(Standards.JSON.encode((["cmd": "login", "uri": url])));
}
