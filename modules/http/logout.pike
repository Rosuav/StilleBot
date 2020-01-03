inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	string cookie = req->misc->?session->?cookie;
	if (cookie) m_delete(G->G->http_sessions, cookie);
	//TODO: Delete the cookie? (It's now useless.)
	return ([
		"data": "You are now logged out.",
		"type": "text/html; charset=\"UTF-8\"",
	]);
}
