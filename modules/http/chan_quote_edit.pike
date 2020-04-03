inherit http_endpoint;

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	array quotes = req->misc->channel->config->quotes;
	if (!quotes || !sizeof(quotes)) return 0; //No quotes? Return a 404.
	if (!req->misc->is_mod) return (["error": 401]);
	//TODO: Actually, yaknow, make the change
	mixed body = Standards.JSON.decode(req->body_raw);
	if (!body || !intp(body->id) || body->id < 1 || body->id >= sizeof(quotes)) return 0; //404 if it's not a valid quote index
	if (!stringp(body->msg)) return (["error": 400]);
	quotes[body->id - 1]->msg = body->msg;
	persist_config->save();
	write("Edited quote %O\n", body);
	return (["error": 204]);
}
