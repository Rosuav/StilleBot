inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (mapping resp = ensure_login(req, "chat_login user_read whispers:edit user_subscriptions")) return resp;
	return (["data": sprintf("oauth:%s\nLogged in as %O\nScopes %O\n",
			req->misc->session->token,
			req->misc->session->user,
			req->misc->session->scopes),
		"type": "text/plain; charset=\"UTF-8\""]);
}
