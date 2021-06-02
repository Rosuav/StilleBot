inherit http_endpoint;

//constant scopes = "chat:read chat:edit whispers:read whispers:edit user_subscriptions"; //For authenticating the bot itself
//constant scopes = ""; //no scopes currently needed

mapping(string:string) resend_redirect = ([]);
continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		if (string dest = resend_redirect[req->variables->code]) return redirect(dest);
		//write("Login response %O\n", req->variables);
		object auth = TwitchAuth();
		write("Requesting access token for %O...\n", req->variables->code); //This shows up twice when those crashes happen. Maybe caching the redirect will help?
		string cookie = yield(Concurrent.Promise(lambda(function ... cb) {
			auth->request_access_token(req->variables->code) {cb[!__ARGS__[0]](__ARGS__[1]);};
		}));
		auth->set_from_cookie(cookie);
		Protocols.HTTP.Promise.Result res = yield(Protocols.HTTP.Promise.get_url("https://api.twitch.tv/helix/users",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + auth->access_token,
				"Client-ID": persist_config["ircsettings"]->clientid,
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
		resend_redirect[req->variables->code] = dest;
		call_out(m_delete, 30, resend_redirect, req->variables->code);
		mapping resp = redirect(dest);
		ensure_session(req, resp);
		req->misc->session->user = user;
		req->misc->session->scopes = (multiset)(req->variables->scope / " ");
		req->misc->session->token = auth->access_token;
		return resp;
	}
	//Attempt to sanitize or whitelist-check the destination. The goal is to permit
	//anything that could ever have been req->not_query for any legitimate request,
	//and to deny anything else.
	string next = req->variables->next || "";
	sscanf(next, "%s?%s", next, string query);
	if (!has_prefix(next, "/")) next = 0; //Destination MUST be absolute within the server but with no protocol or host.
	else {
		//Look up a handler. If we find one, then it's valid.
		[function handler, array args] = find_http_handler(next);
		if (!handler) next = 0;
		if (query) {
			mapping vars = function_object(handler)->safe_query_vars(Protocols.HTTP.Server.http_decode_urlencoded_query(query), @args);
			if (!vars) next = 0;
			else next += "?" + Protocols.HTTP.http_encode_query(vars);
		}
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
