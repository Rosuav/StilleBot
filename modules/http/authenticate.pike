//Small stub page to handle OAuth redirects
//Once it's checked the CSRF state, it will redirect the user to the relevant channel page.
//TODO: Merge patreon.pike into this, and maybe even twitchlogin's response handler (leaving /twitchlogin
//as a landing page only)
inherit annotated;
inherit http_endpoint;

//Used if the user isn't logged in, attempts an OAuth consent flow, and needs to link to
//a Twitch account.
constant markdown = #"# Authenticate Mustard Mine

To complete the process, we will need to connect your Twitch account. [Connect with Twitch](:.twitchlogin data-scopes=@$$scopes$$@)
";

/*
jierenchen — 4:58 AM
So what should happen is 
1. from apps page: click connect
2. shows fourthwall grant screen, click allow
3. this goes through fourthwall oauth dance and then lands on your redirect
4. Exchange code for the fourthwall oauth token
5. If they are cookied, they are good. If not, show them the login register screen for your site
*/
@retain: mapping oauth_csrf_states = ([]);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->variables->code) return redirect("/c/integrations");
	mapping state = m_delete(oauth_csrf_states, req->variables->state);
	if (!req->variables->state) {
		//Requests that originate from FW have no state parameter, and should be linked to
		//the currently-logged-in user; if you aren't, invite a login and auto-activate.
		int userid = (int)req->misc->session->?user->?id;
		string|zero scopes = "chat:read channel:bot"; //Must match the scopes from /activate
		if (userid && !G->G->irc->id[userid]) {
			//CORNER CASE: If you are already logged in, but the bot is not active for
			//your channel, attempt to auto-activate.
			array havescopes = G->G->user_credentials[userid]->?scopes || ({ });
			multiset wantscopes = (multiset)(scopes / " ");
			multiset needscopes = (multiset)havescopes | wantscopes;
			if (sizeof(needscopes) > sizeof(havescopes)) {
				//We need more permissions to make this happen. Ask the user to log in.
				//Note that this MAY result in the OAuth timing out, in which case it will
				//need to be restarted.
				userid = 0; //Give the same login page as if the user wasn't logged in at all.
				scopes = sort(indices(needscopes)) * " ";
			}
			else {
				string login = req->misc->session->user->login;
				Stdio.append_file("activation.log", sprintf("[%d] Account activated after Fourth Wall OAuth: uid %d login %O\n", time(), userid, login));
				await(connect_to_channel(userid));
				//Give the rest of the bot a chance to connect. TODO: Actually get notified somehow
				while (!G->G->irc->id[userid]) sleep(1);
			}
		}
		if (!userid) return render_template(markdown, (["scopes": scopes]));
		state = (["platform": "fourthwall", "channel": userid, "next": "/c/integrations"]); //What should happen if other platforms also need this support?
	}
	if (!state) return "Unable to login, please close this window and try again";
	function handler = this["handle_" + state->platform];
	if (!handler) return "Bwark?"; //Shouldn't happen, internal problem within the bot. Everything that creates an entry in csrf_states should include the platform.
	await(handler(req, state));
	if (state->next) return redirect(state->next);
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
	//TODO: Cope with a delayed callback, which could happen if the user needs to authenticate with Twitch.
	//(Return to /c/integrations and let them restart the process?)
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
