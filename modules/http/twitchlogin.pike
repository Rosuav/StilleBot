inherit http_endpoint;

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = persist_config["ircsettings"];
	object auth = TwitchAuth(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", ""); //no scopes currently needed
	if (req->variables->code)
	{
		//It's a positive response from Twitch
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
			if (!dest)
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
			return resp;
		});
	}
	write("Redirecting to Twitch...\n");
	mapping resp = redirect(auth->get_auth_uri());
	ensure_session(req, resp);
	//TODO: Sanitize or whitelist-check the destination
	req->misc->session->redirect_after_login = req->variables->next;
	return resp;
}
