inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = persist_config["ircsettings"];
	object auth = TwitchAuth(cfg->clientid, cfg->clientsecret, cfg->http_address + "/twitchlogin", ""); //no scopes currently needed
	if (req->variables->code)
	{
		//It's a positive response from Twitch
		//TODO: Do all this asynchronously (will require an async protocol with http_endpoint)
		string resp = auth->request_access_token(req->variables->code);
		auth->set_from_cookie(resp);
		string data = Protocols.HTTP.get_url_data("https://api.twitch.tv/helix/users", 0, ([
			"Authorization": "Bearer " + auth->access_token,
			"Client-ID": cfg->clientid,
		]));
		mapping info = Standards.JSON.decode_utf8(data);
		return (["data": "Hello, " + info->data[0]->display_name, "type": "text/html"]);
	}
	write("Redirecting to Twitch...\n");
	return (["error": 302, "extra_heads": (["Location": auth->get_auth_uri()])]);
}
