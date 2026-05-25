inherit http_endpoint;

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	if (mapping resp = ensure_login(req)) return resp;
	//write("Got session: %O\n", req->misc->session);
	mapping creds = G->G->user_credentials[(int)req->misc->session->user->id] || ([]);
	return ([
		"data": "Hello, " + req->misc->session->user->display_name
			+ "! Authorized scopes: " + (creds->scopes || ({ })) * ", ",
		"type": "text/html"
	]);
}
