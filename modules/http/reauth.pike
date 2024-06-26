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
				token_for_user_login(req->misc->session->user->login)),
			"type": "text/plain; charset=\"UTF-8\""]);
	}
	array havescopes = G->G->dbsettings->credentials->scopes || ({ });
	multiset scopes = (multiset)havescopes | (<"chat:read", "chat:edit", "user_read", "whispers:edit", "user_subscriptions">);
	//Add any requested scopes
	foreach (req->variables; string key; string value)
		if (sscanf(key, "scope-%s", string scope) && scope && scope != "") scopes[scope] = 1;
	if (mapping resp = ensure_login(req, indices(scopes) * " ")) return resp;
	string desc = "Login details saved.";
	if (G->G->dbsettings->credentials->userid == req->misc->session->user->id) {
		mapping c = G->G->dbsettings->credentials | ([
			"username": req->misc->session->user->login,
			"userid": req->misc->session->user->id,
			"token": req->misc->session->token,
			"scopes": sort(indices(req->misc->session->scopes)),
		]);
		werror("Saving to DB.\n");
		spawn_task(G->G->DB->query_rw("update stillebot.settings set credentials = :c",
			(["c": c]))); //TODO: On switching back to Sql.Sql, check JSON encoding
	}
	else desc = "oauth:" + req->misc->session->token;
	string add_scopes = "", authbtn = "All permissions granted.";
	foreach (sort(indices(G->G->voice_additional_scopes)), string scope) {
		add_scopes += sprintf("> * %s %s\n",
			scopes[scope] ? "[Available]" : "<label><input type=checkbox name=\"scope-" + scope + "\">", //bad hack: assume the browser properly ends the labels for me
			G->G->voice_additional_scopes[scope],
		);
		if (!scopes[scope]) authbtn = "[Add permissions](:type=submit)";
	}
	return render_template(markdown, ([
		"desc": desc,
		"user": sprintf("%O", req->misc->session->user),
		"scopes": sort(indices(req->misc->session->scopes)) * ", " + "\n" + add_scopes + "\n> " + authbtn + "\n{:tag=form method=post}",
	]));
}
