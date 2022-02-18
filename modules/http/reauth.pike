inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (req->variables->bcaster) {
		if (mapping resp = ensure_login(req)) return resp; //Make sure we have at least SOME token first, so we know who we're talking to
		if (string scopes = ensure_bcaster_token(req, req->variables->bcaster, req->misc->session->user->login))
			return render_template("login.md", (["scopes": scopes, "msg": "additional scopes"]));
		return (["data": sprintf("Broadcaster login for %O saved\nScopes %O\n",
				req->misc->session->user,
				persist_status->path("bcaster_token_scopes")[req->misc->session->user->login]),
			"type": "text/plain; charset=\"UTF-8\""]);
	}
	if (mapping resp = ensure_login(req, "chat:read chat:edit user_read whispers:edit user_subscriptions")) return resp;
	return (["data": sprintf("oauth:%s\nLogged in as %O\nScopes %O\n",
			req->misc->session->token,
			req->misc->session->user,
			req->misc->session->scopes),
		"type": "text/plain; charset=\"UTF-8\""]);
}
