inherit http_endpoint;
mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "channel:read:subscriptions")) return resp;
	return redirect("/channels/" + req->misc->session->user->login + "/subpoints");
}
