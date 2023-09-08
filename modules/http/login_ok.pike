inherit http_endpoint;

continue Concurrent.Future|mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	if (mapping resp = ensure_login(req)) return resp;
	//write("Got session: %O\n", req->misc->session);
	array bcaster_scopes = yield(token_for_user_login_async(req->misc->session->user->login))[1] / " ";
	return ([
		"data": "Hello, " + req->misc->session->user->display_name
			+ "! Authorized scopes: " + (array)req->misc->session->scopes * ", "
			+ (sizeof(bcaster_scopes) ? ". Broadcaster scopes: " + bcaster_scopes * ", " : ""),
		"type": "text/html"
	]);
}
