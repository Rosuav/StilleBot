//Small stub page to handle OAuth redirects
//Once it's checked the CSRF state, it will redirect the user to the relevant channel page.
//TODO: Merge patreon.pike into this, and maybe even twitchlogin's response handler (leaving /twitchlogin
//as a landing page only)
inherit annotated;
inherit http_endpoint;

@retain: mapping oauth_csrf_states = ([]);

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!req->variables->code) return redirect("/c/integrations");
	mapping state = m_delete(oauth_csrf_states, req->variables->state);
	if (!state) return "Unable to login, please close this window and try again";
	function handler = this["handle_" + state->platform];
	if (!handler) return "Bwark?"; //Shouldn't happen, internal problem within the bot. Everything that creates an entry in csrf_states should include the platform.
	await(handler(req, state));
	return (["data": "<script>window.close(); window.opener.location.reload();</script>", "type": "text/html"]);
}

__async__ void handle_fourthwall(Protocols.HTTP.Server.Request req, mapping state) {
	mapping cfg = await(G->G->DB->load_config(0, "fourthwall"));
	werror("Got variables: %O\n", req->variables);
	werror("Constructed: %O\n", "grant_type=authorization_code&redirect_uri=https://" + G->G->instance_config->local_address + "/authenticate&client_id="
			+ cfg->clientid + "&client_secret=" + cfg->secret + "&code=" + req->variables->code);
	object res = await(Protocols.HTTP.Promise.post_url("https://api.fourthwall.com/open-api/v1.0/platform/token",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Content-Type": "application/x-www-form-urlencoded",
			"User-Agent": "MustardMine", //Having a user-agent that suggest that it's Mozilla will cause 403s from Fourth Wall's API.
			"Accept": "*/*",
		]), "data": Protocols.HTTP.http_encode_query(([
			"code": req->variables->code,
			"grant_type": "authorization_code",
			"client_id": cfg->clientid,
			"client_secret": cfg->secret,
			"redirect_uri": "https://" + G->G->instance_config->local_address + "/authenticate",
		]))]))
	));
	mapping auth = Standards.JSON.decode_utf8(res->get());
	werror("Got auth: %O\n", auth);
}

protected void create(string name) {::create(name);}
