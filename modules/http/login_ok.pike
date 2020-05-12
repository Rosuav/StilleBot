inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	if (mapping resp = ensure_login(req)) return resp;
	//write("Got session: %O\n", req->misc->session);
	return (["data": "Hello, " + req->misc->session->user->display_name, "type": "text/html"]);
}
