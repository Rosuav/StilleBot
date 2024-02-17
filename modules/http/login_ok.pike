inherit http_endpoint;

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	if (mapping resp = ensure_login(req)) return resp;
	//write("Got session: %O\n", req->misc->session);
	array bcaster_scopes = token_for_user_login(req->misc->session->user->login)[1] / " ";
	return ([
		"data": "Hello, " + req->misc->session->user->display_name
			+ "! Authorized scopes: " + (array)req->misc->session->scopes * ", "
			+ (sizeof(bcaster_scopes) ? ". Broadcaster scopes: " + bcaster_scopes * ", " : ""),
		"type": "text/html"
	]);
}
