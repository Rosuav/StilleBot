inherit http_endpoint;

constant markdown = #"# Authentication complete

$$desc$$

<pre>$$user$$</pre>

Scopes: $$scopes$$
";

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
	mapping config = persist_config->path("ircsettings");
	multiset scopes = (multiset)(config->scopes || (<>)) | (<"chat:read", "chat:edit", "user_read", "whispers:edit", "user_subscriptions">);
	if (mapping resp = ensure_login(req, indices(scopes) * " ")) return resp;
	string desc = "Login details saved.";
	if (config->nick == req->misc->session->user->login) {
		config->pass = "oauth:" + req->misc->session->token;
		config->scopes = sort(indices(req->misc->session->scopes));
		persist_config->save();
	}
	else desc = "oauth:" + req->misc->session->token;
	return render_template(markdown, ([
		"desc": desc,
		"user": sprintf("%O", req->misc->session->user),
		"scopes": sort(indices(req->misc->session->scopes)) * ", ",
	]));
}
