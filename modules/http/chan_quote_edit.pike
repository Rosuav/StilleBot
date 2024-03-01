inherit http_endpoint;

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	array quotes = await(G->G->DB->load_config(req->misc->channel->userid, "quotes", ({ })));
	if (!quotes || !sizeof(quotes)) return 0; //No quotes? Return a 404.
	if (!req->misc->is_mod) return (["error": 401]);
	mixed body = Standards.JSON.decode(req->body_raw);
	if (!body || !intp(body->id) || body->id < 1 || body->id > sizeof(quotes)) return 0; //404 if it's not a valid quote index
	if (!stringp(body->msg)) return (["error": 400]);
	if (req->misc->session->fake) return (["error": 204]);
	quotes[body->id - 1]->msg = body->msg;
	await(G->G->DB->save_config(req->misc->channel->userid, "quotes", quotes));
	write("Edited quote %O\n", body);
	return (["error": 204]);
}
