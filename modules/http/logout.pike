//TODO: Merge this into /twitchlogin as a separate JSON endpoint?
inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	G->G->DB->save_session((["cookie": req->misc->session->cookie]));
	req->misc->session = ([]); //Prevent session recreation
	string host = deduce_host(req->request_headers);
	return ([
		"data": "You are now logged out.",
		"type": "text/html; charset=\"UTF-8\"",
		"extra_heads": (["Set-Cookie": "session=; Path=/; Max-Age=-1" + (has_suffix(host, "mustardmine.com") ? "; Domain=mustardmine.com" : "")]),
	]);
}
