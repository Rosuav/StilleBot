inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	if (mapping resp = ensure_login(req)) return resp;
	//write("Got session: %O\n", req->misc->session);
	array bcaster_scopes = (persist_status->path("bcaster_token_scopes")[req->misc->session->user->login]||"") / " ";
	return ([
		"data": "Hello, " + req->misc->session->user->display_name
			+ "! Authorized scopes: " + (array)req->misc->session->scopes * ", "
			+ (sizeof(bcaster_scopes) ? ". Broadcaster scopes: " + bcaster_scopes * ", " : ""),
		"type": "text/html"
	]);
}
