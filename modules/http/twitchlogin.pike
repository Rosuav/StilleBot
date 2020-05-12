inherit http_endpoint;

//constant scopes = "chat:read chat:edit whispers:read whispers:edit user_subscriptions"; //For authenticating the bot itself
//constant scopes = ""; //no scopes currently needed

mapping(string:mixed)|Concurrent.Future twitchlogin(Protocols.HTTP.Server.Request req, string scopes, string|void next)
{
	mapping cfg = persist_config["ircsettings"];
	object auth = TwitchAuth(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", scopes / " ");
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		//write("%O\n", req->variables);
		auth->set_from_cookie(auth->request_access_token(req->variables->code));
		return Protocols.HTTP.Promise.get_url("https://api.twitch.tv/helix/users",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + auth->access_token,
				"Client-ID": cfg->clientid,
			])])))->then(lambda(Protocols.HTTP.Promise.Result res)
		{
			mapping user = Standards.JSON.decode_utf8(res->get())->data[0];
			write("Login: %O %O\n", auth->access_token, user);
			string dest = m_delete(req->misc->session, "redirect_after_login");
			if (!dest || dest == req->not_query)
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
			req->misc->session->scopes = req->variables->scope / " ";
			req->misc->session->token = auth->access_token;
			return resp;
		});
	}
	write("Redirecting to Twitch...\n%s\n", auth->get_auth_uri());
	mapping resp = redirect(auth->get_auth_uri());
	ensure_session(req, resp);
	req->misc->session->redirect_after_login = next || req->not_query;
	return resp;
}

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	//Attempt to sanitize or whitelist-check the destination. The goal is to permit
	//anything that could ever have been req->not_query for any legitimate request,
	//and to deny anything else. Much of this is replicating the routing done by
	//connection.pike's http_handler.
	string next = req->variables->next;
	if (!next) ; //No destination? No problem (will use magic at arrival time).
	else if (!has_prefix(req->not_query, "/")) next = 0; //Destination MUST be absolute within the server but with no protocol or host.
	else if (has_prefix(req->not_query, "/chan_")) next = 0; //These can't be valid (although they wouldn't hurt, they'd just 404).
	else if (G->G->http_endpoints[next[1..]]) ; //Destination is a simple target, clearly whitelisted
	else
	{
		function handler;
		foreach (G->G->http_endpoints; string pat; function h)
		{
			//Match against an sscanf pattern, and require that the entire
			//string be consumed. If there's any left (the last piece is
			//non-empty), it's not a match - look for a deeper pattern.
			array pieces = array_sscanf(req->not_query, pat + "%s");
			if (!pieces || !sizeof(pieces) || pieces[-1] != "") continue;
			handler = h;
			break;
		}
		if (!handler) next = 0;
		//Note that this will permit a lot of things that aren't actually valid, like /channels/SPAM/HAM
		//I'm not sure if I should be stricter here or if that's okay. You won't be
		//able to redirect outside of the StilleBot environment this way.
	}
	return twitchlogin(req, "", req->variables->next);
}

protected void create(string n) {::create(n); G->G->twitchlogin = twitchlogin;}
