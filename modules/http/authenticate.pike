//Small stub page to handle OAuth redirects
//Once it's checked the CSRF state, it will redirect the user to the relevant channel page.
//TODO: Merge patreon.pike into this, and maybe even twitchlogin's response handler (leaving /twitchlogin
//as a landing page only)
inherit annotated;
inherit http_endpoint;

@retain: mapping oauth_csrf_states = ([]);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->variables->code) return redirect("/c/integrations");
	mapping state = m_delete(oauth_csrf_states, req->variables->state);
	if (!state) return "Unable to login, please close this window and try again";
	function handler = this["handle_" + state->platform];
	if (!handler) return "Bwark?"; //Shouldn't happen, internal problem within the bot. Everything that creates an entry in csrf_states should include the platform.
	await(handler(req, state));
	return (["data": "<script>window.close(); window.opener.location.reload();</script>", "type": "text/html"]);
}

__async__ void handle_fourthwall(Protocols.HTTP.Server.Request req, mapping state) {
	mapping cfg = await(G->G->DB->load_config(0, "fourthwall"));
	object res = await(Protocols.HTTP.Promise.post_url("https://api.fourthwall.com/open-api/v1.0/platform/token",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Content-Type": "application/x-www-form-urlencoded",
			"User-Agent": "MustardMine", //Having a user-agent that suggest that it's Mozilla will cause 403s from Fourth Wall's API.
			"Accept": "*/*",
		]), "data": Protocols.HTTP.http_encode_query(([
			"code": req->variables->code,
			"grant_type": "authorization_code",
			"client_id": cfg->clientid,
			"client_secret": cfg->secret,
			"redirect_uri": "https://" + G->G->instance_config->local_address + "/authenticate",
		]))]))
	));
	mapping auth = Standards.JSON.decode_utf8(res->get());
	//Since the access token lasts for just five minutes, we don't bother saving it to the database.
	//Instead, we save the refresh token, and then prepopulate the in-memory cache.
	G->G->fourthwall_access_token[state->channel] = ({auth->access_token, time() + auth->expires_in - 2});
	mapping data = await(fourthwall_request(state->channel, "GET", "/shops/current"));
	werror("Shop info: %O\n", data);
	mapping existing = await(fourthwall_request(state->channel, "GET", "/webhooks"));
	if (existing && existing->results) {
		werror("Removing old webhooks\n");
		foreach (existing->results, mapping hook) {
			werror("Deleting %O\n", hook);
			await(fourthwall_request(state->channel, "DELETE", "/webhooks/" + hook->id));
		}
	}
	werror("Creating webhook\n");
	object channel = G->G->irc->id[state->channel];
	mapping created = await(fourthwall_request(state->channel, "POST", "/webhooks", ([
		"url": "https://mustardmine.com/channels/" + channel->login + "/integrations",
		"allowedTypes": ({"ORDER_PLACED", "GIFT_PURCHASE", "DONATION", "SUBSCRIPTION_PURCHASED"}),
	])));
	werror("Result: %O\n", created);
	await(G->G->DB->mutate_config(state->channel, "fourthwall") {mapping cfg = __ARGS__[0];
		cfg->username = data->name;
		cfg->shopname = data->domain;
		cfg->url = data->publicDomain; //Does this always exist?
		cfg->refresh_token = auth->refresh_token;
	});
	G->G->websocket_types->chan_integrations->send_updates_all("#" + state->channel);
}

protected void create(string name) {::create(name);}
