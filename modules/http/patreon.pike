//Small stub page to handle Patreon redirects
//Once it's checked the CSRF state, it will redirect the user to the relevant channel page.
inherit annotated;
inherit http_websocket;

@retain: mapping patreon_csrf_states = ([]);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	mapping state = m_delete(patreon_csrf_states, req->variables->state);
	if (!state) return "Unable to login, please close this window and try again";
	object res = await(Protocols.HTTP.Promise.post_url("https://www.patreon.com/api/oauth2/token",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Content-Type": "application/x-www-form-urlencoded",
		]), "data": Protocols.HTTP.http_encode_query(([
			"code": req->variables->code,
			"grant_type": "authorization_code",
			"client_id": G->G->instance_config->patreon_clientid,
			"client_secret": G->G->instance_config->patreon_clientsecret,
			"redirect_uri": "https://" + G->G->instance_config->local_address + "/patreon",
		]))]))
	));
	mapping auth = Standards.JSON.decode_utf8(res->get());
	res = await(Protocols.HTTP.Promise.get_url("https://www.patreon.com/api/oauth2/v2/identity",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + auth->access_token,
		])]))
	));
	werror("Identity: %O\n", Standards.JSON.decode_utf8(res->get()));
	return "Testing";
}

protected void create(string name) {::create(name);}
