//TODO: Merge this into /twitchlogin as a separate JSON endpoint?
inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	m_delete(G->G->http_sessions, req->misc->session->cookie);
	req->misc->session = ([]); //Prevent session recreation
	return ([
		"data": "You are now logged out.",
		"type": "text/html; charset=\"UTF-8\"",
		"extra_heads": (["Set-Cookie": "session=; Path=/; Max-Age=-1"]),
	]);
}
