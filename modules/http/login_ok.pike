inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	//write("Cookies: %O\n", req->cookies);
	mapping session = G->G->http_sessions[req->cookies->session];
	if (!session) return redirect("/twitchlogin");
	//write("Got session: %O\n", session);
	return (["data": "Hello, " + session->user->display_name, "type": "text/html"]);
}
