//Small stub page to handle Patreon redirects
//Once it's checked the CSRF state, it will redirect the user to the relevant channel page.
inherit annotated;
inherit http_websocket;

@retain: mapping patreon_csrf_states = ([]);

constant markdown = #"# Link your Patreon and Twitch

Welcome, $$twitchname$$! (Not you? [Change user](:.twitchlogin data-force=true)) If you link your
Twitch and Patreon accounts, you can enjoy the benefits offered by those creators offering them! Wow!

[Link your Patreon](:#patreonlogin)

<script>
document.getElementById('patreonlogin').onclick = e => window.open('$$uri$$', 'login', 'width=525, height=900');
</script>
";

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->variables->code) {
		if (!req->misc->session->user) return render_template("login.md", ([]));
		string tok = String.string2hex(random_string(8));
		patreon_csrf_states[tok] = (["timestamp": time(), "user": req->misc->session->user->id]);
		object uri = Standards.URI("https://www.patreon.com/oauth2/authorize");
		uri->set_query_variables(([
			"response_type": "code",
			"client_id": G->G->instance_config->patreon_clientid,
			"redirect_uri": "https://" + G->G->instance_config->local_address + "/patreon", //Or should it always go to mustardmine.com?
			"state": tok,
		]));
		return render_template(markdown, ([
			"twitchname": req->misc->session->user->display_name,
			"uri": (string)uri,
		]));
	}
	mapping state = m_delete(patreon_csrf_states, req->variables->state);
	if (!state) return "Unable to login, please close this window and try again";
	object res = await(Protocols.HTTP.Promise.post_url("https://www.patreon.com/api/oauth2/token",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Content-Type": "application/x-www-form-urlencoded",
		]), "data": Protocols.HTTP.http_encode_query(([
			"code": req->variables->code,
			"grant_type": "authorization_code",
			"client_id": G->G->instance_config->patreon_clientid,
			"client_secret": G->G->instance_config->patreon_clientsecret,
			"redirect_uri": "https://" + G->G->instance_config->local_address + "/patreon",
		]))]))
	));
	mapping auth = Standards.JSON.decode_utf8(res->get());
	res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/identity",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + auth->access_token,
		])]))
	));
	mapping ident = Standards.JSON.decode_utf8(res->get());
	string twitch = state->channel ? (string)state->channel : state->user;
	if (twitch) {
		//Record both forward and reverse linkage
		await(G->G->DB->mutate_config(twitch, "patreon") {mapping cfg = __ARGS__[0];
			cfg->auth = auth;
			cfg->patreon_user_id = ident->data->id;
		});
		await(G->G->DB->mutate_config(0, "patreon") {mapping cfg = __ARGS__[0];
			if (!cfg->twitch_from_patreon) cfg->twitch_from_patreon = ([]);
			cfg->twitch_from_patreon[ident->data->id] = twitch;
		});
	}
	if (state->channel) link_channel_patreon(auth, ident, state);
	if (state->user) link_user_patreon(auth, ident, state);
	return (["data": "<script>window.close(); window.opener.location.reload();</script>", "type": "text/html"]);
}

__async__ void link_channel_patreon(mapping auth, mapping ident, mapping state) {
	object channel = G->G->irc->id[state->channel];
	object res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/campaigns?fields[campaign]=url",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + auth->access_token,
		])]))
	));
	mapping campaigns = Standards.JSON.decode_utf8(res->get());
	await(G->G->DB->mutate_config(channel->userid, "patreon") {mapping cfg = __ARGS__[0];
		cfg->campaign_url = campaigns->data[0]->attributes->url;
	});
	res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/webhooks",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + auth->access_token,
		])]))
	));
	mapping hooks = Standards.JSON.decode_utf8(res->get());
	//Do I need to check every campaign to see if it has a hook, or just assume that there's one campaign?
	string hookuri = "https://mustardmine.com/channels/" + channel->login + "/integrations";
	//Note that if you rename your channel, the URL will break, and thus webhooks will stop coming through;
	//to fix this, simply reauthenticate and the new hook will be created.
	if (!has_value(hooks->data->attributes->uri, hookuri)) {
		//No hooks yet; establish one.
		res = await(Protocols.HTTP.Promise.post_url("https://www.patreon.com/api/oauth2/v2/webhooks",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + auth->access_token,
				"Content-Type": "application/json; charset=utf-8",
			]), "data": Standards.JSON.encode((["data": ([
				"type": "webhook",
				"attributes": ([
					"triggers": ({
						"members:create", "members:update", "members:delete",
						"members:pledge:create", "members:pledge:update", "members:pledge:delete",
						"posts:publish", //At least for testing - not sure if this will have long-term value
					}),
					"uri": hookuri,
				]),
				"relationships": ([
					"campaign": (["data": (["type": "campaign", "id": campaigns->data[0]->id])]),
				]),
			])]), 1)]))
		));
		mapping hook = Standards.JSON.decode_utf8(res->get());
		await(G->G->DB->mutate_config(channel->userid, "patreon") {mapping cfg = __ARGS__[0];
			cfg->hook_secret = hook->data->attributes->secret;
		});
		hook->data->attributes->secret = "<redacted>";
		werror("Created a hook! %O\n", hook);
	}
}

__async__ void link_user_patreon(mapping auth, mapping ident, mapping state) {
	werror("USER: Patreon %O is Twitch %O\n", ident->data->id, state->user);
}

//TODO: Periodically check for near-to-expiration credentials and refresh them

protected void create(string name) {::create(name);}
