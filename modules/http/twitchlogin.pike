inherit http_endpoint;

//constant scopes = "chat:read chat:edit whispers:read whispers:edit user_subscriptions"; //For authenticating the bot itself
//constant scopes = ""; //no scopes currently needed

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		//write("Login response %O\n", req->variables);
		object auth = TwitchAuth();
		write("Requesting access token for %O...\n", req->variables->code); //Does this show up twice when those crashes happen?
		string cookie = yield(Concurrent.Promise(lambda(function ... cb) {
			auth->request_access_token(req->variables->code) {cb[!__ARGS__[0]](__ARGS__[1]);};
		}));
		auth->set_from_cookie(cookie);
		Protocols.HTTP.Promise.Result res = yield(Protocols.HTTP.Promise.get_url("https://api.twitch.tv/helix/users",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + auth->access_token,
				"Client-ID": cfg->clientid,
			])]))));
		mapping user = Standards.JSON.decode_utf8(res->get())->data[0];
		//write("Login: %O %O\n", auth->access_token, user);
		string dest = m_delete(req->misc->session, "redirect_after_login");
		if (!dest || dest == req->not_query || has_prefix(dest + "?", req->not_query))
		{
			//If no destination was given, try to figure out a plausible default.
			//For streamers, redirect to the stream's landing page. Doesn't work
			//for mods, as we have no easy way to check which channel(s).
			object channel = G->G->irc->channels["#" + user->login];
			if (channel && channel->config->allcmds)
				dest = "/channels/" + user->login + "/";
			else dest = "/login_ok";
		}
		mapping resp = redirect(dest);
		ensure_session(req, resp);
		req->misc->session->user = user;
		req->misc->session->scopes = (multiset)(req->variables->scope / " ");
		req->misc->session->token = auth->access_token;
		return resp;
	}
	//Attempt to sanitize or whitelist-check the destination. The goal is to permit
	//anything that could ever have been req->not_query for any legitimate request,
	//and to deny anything else. Much of this is replicating the routing done by
	//connection.pike's http_handler.
	//Note that this will not accept anything with a querystring in it. For now, I'm
	//fine with that. If it's a problem, split on question mark here and do separate
	//sanitization of the two halves.
	string next = req->variables->next;
	if (!next) ; //No destination? No problem (will use magic at arrival time).
	else if (!has_prefix(next, "/")) next = 0; //Destination MUST be absolute within the server but with no protocol or host.
	else if (has_prefix(next, "/chan_")) next = 0; //These can't be valid (although they wouldn't hurt, they'd just 404).
	else if (G->G->http_endpoints[next[1..]]) ; //Destination is a simple target, clearly whitelisted
	else
	{
		function handler;
		foreach (G->G->http_endpoints; string pat; function h)
		{
			//Match against an sscanf pattern, and require that the entire
			//string be consumed. If there's any left (the last piece is
			//non-empty), it's not a match - look for a deeper pattern.
			array pieces = array_sscanf(next, pat + "%s");
			if (!pieces || !sizeof(pieces) || pieces[-1] != "") continue;
			handler = h;
			break;
		}
		if (!handler) next = 0;
		//Note that this will permit a lot of things that aren't actually valid, like /channels/SPAM/HAM
		//I'm not sure if I should be stricter here or if that's okay. You won't be
		//able to redirect outside of the StilleBot environment this way.
	}
	//Merge scopes, similarly to ensure_login()
	multiset havescopes = req->misc->session->?scopes || (<>);
	multiset wantscopes = (multiset)((req->variables->scopes || "") / " " - ({""}));
	multiset bad = wantscopes - TwitchAuth()->list_valid_scopes();
	if (sizeof(bad)) return (["error": 400, "type": "text/plain", //Note that this is a 400, as opposed to a 500 in ensure_login
		"data": sprintf("Unrecognized scope %O being requested", (array)bad * " ")]);
	multiset needscopes = havescopes | wantscopes; //Note that we'll keep any that we already have.
	return twitchlogin(req, needscopes, next);
}
