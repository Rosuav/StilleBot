inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = persist_config["ircsettings"];
	object auth = TwitchAuth(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", ""); //no scopes currently needed
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		//TODO: Do all this asynchronously (will require an async protocol with http_endpoint)
		auth->set_from_cookie(auth->request_access_token(req->variables->code));
		string data = Protocols.HTTP.get_url_data("https://api.twitch.tv/helix/users", 0, ([
			"Authorization": "Bearer " + auth->access_token,
			"Client-ID": cfg->clientid,
		]));
		mapping user = Standards.JSON.decode_utf8(data)->data[0];
		write("Login: %O\n", user);
		mapping resp = redirect("/login_ok");
		object channel = G->G->irc->channels["#" + user->login];
		if (channel && channel->config->allcmds)
		{
			//This is a streamer's login. Redirect to the stream's landing page.
			resp = redirect("/channels/" + user->login + "/");
		}
		ensure_session(req, resp);
		req->misc->session->user = user;
		return resp;
	}
	write("Redirecting to Twitch...\n");
	return redirect(auth->get_auth_uri());
}
